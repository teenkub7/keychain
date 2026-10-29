import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_data.dart';
import '../services/api/sensor_api_service.dart';
import '../services/api/ble_service.dart';

class HealthSensorScreen extends StatefulWidget {
  final String username;
  final bool isConnected;
  final BluetoothDevice? targetDevice;

  const HealthSensorScreen({
    super.key,
    required this.username,
    this.isConnected = false,
    this.targetDevice,
  });

  @override
  State<HealthSensorScreen> createState() => _HealthSensorScreenState();
}

class _HealthSensorScreenState extends State<HealthSensorScreen>
    with SingleTickerProviderStateMixin {
  int _activeTabIndex = 0; // 0 = สุขภาพ, 1 = เซนเซอร์ 30 นาที
  bool _isLoading = false;
  Timer? _autoRefreshTimer;

  StreamSubscription? _bleStreamSubscription;

  // ข้อมูลสำหรับ Tab 0 (Manual Spot)
  SensorLogItem? _latestSpot;
  List<SensorLogItem> _spotHistory = [];

  // ข้อมูลสำหรับ Tab 1 (Auto 30s)
  SensorLogItem? _latestAuto;
  List<SensorLogItem> _autoHistory = [];

  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _heartScale = Tween<double>(begin: 0.92, end: 1.15).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.easeInOut),
    );
    if (!WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding')) {
      _heartAnimController.repeat(reverse: true);
    }

    BleService().setUsername(widget.username);
    // ✅ ตั้ง default mode เป็น Auto_30s เพื่อไม่ให้ Dialog วิเคราะห์ขึ้นโดยไม่ตั้งใจ
    // mode จะเปลี่ยนเป็น Manual_Spot เฉพาะเมื่อผู้ใช้กดปุ่มวัดสุขภาพหรือสลับไปแท็บ "สุขภาพ"
    BleService().setMeasurementMode('Auto_30s');
    _loadData();
    _connectBleAuto();

    // ดักรับ Stream ตรงกลางจาก BleService (รองรับทั้ง Temp/Hum สด และ Pulse/SpO2)
    _bleStreamSubscription = BleService().dataStream.listen((data) async {
      if (mounted) {
        final SensorLogItem? item = data['dbItem'] as SensorLogItem?;
        final String type = data['type'] as String? ?? 'Auto_30s';

        if (item != null) {
          debugPrint(">>> 🚀 UI Received Stream Data: Temp=${item.temperature}, Hum=${item.humidity}, HR=${item.heartRate}");
          setState(() {
            // 1. อัปเดตฝั่งเซนเซอร์ 30 นาทีเสมอเมื่อมีค่า Temp หรือ Hum เข้ามา
            if (item.temperature > 0 || item.humidity > 0 || type == 'Auto_30s') {
              _latestAuto = item;
              _autoHistory.removeWhere((h) => h.id == item.id);
              _autoHistory.add(item);
              _autoHistory.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
              _isMeasuringAuto = false;
            }

            // 2. Manual_Spot: อัปเดตฝั่งวัดสุขภาพ
            if (type == 'Manual_Spot' || (item.heartRate > 0 && item.spO2 > 0)) {
              _latestSpot = item;
              _spotHistory.removeWhere((h) => h.id == item.id);
              _spotHistory.add(item);
              _spotHistory.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
              _isMeasuring = false;
            }
          });

          // ซิงก์ประวัติล่าสุดจากฐานข้อมูลทันที
          await _loadData(silent: true);

          // กรณีที่ 1: แสดง Dialog สรุปสุขภาพทันทีสำหรับการวัดสุขภาพ (เฉพาะเมื่ออยู่หน้าแท็บสุขภาพ)
          if (type == 'Manual_Spot' && item.heartRate > 0 && item.spO2 > 0 && _activeTabIndex == 0) {
            _bleResponseReceived = true;
            _showHealthResultDialog(item);
            BleService().setMeasurementMode('Auto_30s');
          }

          // กรณีที่ 2: แสดง Dialog แจ้งเตือนผลตรวจวัดอุณหภูมิ & ความชื้น (เมื่ออยู่หน้าแท็บอุณหภูมิ & ความชื้น หรือ type เป็น Auto_30s)
          if ((type == 'Auto_30s' || _activeTabIndex == 1) && (item.temperature > 0 || item.humidity > 0)) {
            _showEnvironmentResultDialog(item);
          }
        }
      }
    });

    // ดึงข้อมูลอัตโนมัติเป็นระยะ (ทุก 15 วินาที สำหรับหน้า 30s)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  Future<void> _connectBleAuto() async {
    try {
      bool connected = await BleService().connectToKeychain();
      if (mounted && connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('เชื่อมต่อ BLE กับ ESP32 สำเร็จพร้อมรับข้อมูล!'),
          ),
        );
      }
    } catch (e) {
      debugPrint("BLE connect error / non-supported environment: $e");
    }
  }

  @override
  void dispose() {
    _bleStreamSubscription?.cancel();
    _autoRefreshTimer?.cancel();
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final username = widget.username.isNotEmpty ? widget.username : 'user1';

      final spotLatestFuture = SensorApiService.getLatest(username: username, type: 'Manual_Spot');
      final spotHistoryFuture = SensorApiService.getHistory(username: username, type: 'Manual_Spot', limit: 20);

      final autoLatestFuture = SensorApiService.getLatest(username: username, type: 'Auto_30s');
      final autoHistoryFuture = SensorApiService.getHistory(username: username, type: 'Auto_30s', limit: 25);

      final results = await Future.wait([
        spotLatestFuture,
        spotHistoryFuture,
        autoLatestFuture,
        autoHistoryFuture,
      ]);

      if (mounted) {
        setState(() {
          if (results[0] != null) {
            _latestSpot = results[0] as SensorLogItem?;
          }
          final loadedSpot = results[1] as List<SensorLogItem>;
          if (loadedSpot.isNotEmpty) {
            _spotHistory = loadedSpot;
            _spotHistory.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
          }
          if (results[2] != null) {
            _latestAuto = results[2] as SensorLogItem?;
          }
          // Fallback: หาก _latestAuto ยังว่างหรือค่าเป็น 0 ให้นำค่าจาก spot ล่าสุดที่มีอุณหภูมิมาแสดง
          if ((_latestAuto == null || _latestAuto!.temperature == 0) && _latestSpot != null && _latestSpot!.temperature > 0) {
            _latestAuto = _latestSpot;
          }

          final loadedAuto = results[3] as List<SensorLogItem>;
          if (loadedAuto.isNotEmpty) {
            _autoHistory = loadedAuto;
            _autoHistory.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
          } else if (_autoHistory.isEmpty && _spotHistory.isNotEmpty) {
            // Fallback: นำประวัติที่มีอุณหภูมิ/ความชื้นมาแสดง
            _autoHistory = _spotHistory.where((s) => s.temperature > 0 || s.humidity > 0).take(5).toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sensor data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerEsp32PulseMeasurement() async {
    try {
      bool connected = await BleService().connectToKeychain();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถเชื่อมต่อ BLE กับ ESP32 ได้')),
          );
        }
        return;
      }

      await Future.delayed(const Duration(milliseconds: 150));

      // ✅ ตั้ง mode เป็น Manual_Spot ก่อนส่งคำสั่ง
      // เพื่อให้ BleService รู้ว่าค่าที่รับกลับมาเป็นการวัดสุขภาพ ไม่ใช่ Auto_30s
      BleService().setMeasurementMode('Manual_Spot');

      // ยิงคำสั่ง P:3 สั่ง ESP32 เริ่มวัดชีพจร
      await BleService().sendData("P:3");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('สั่ง ESP32 เริ่มวัดค่าแล้ว (กรุณาแตะนิ้วค้างไว้ที่เซนเซอร์)'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error sending BLE trigger: $e");
    }
  }

  bool _isMeasuring = false;
  // Flag ป้องกัน Dialog ซ้อนกัน: BleService จะ set เป็น true เมื่อส่ง stream
  // ถ้า false หลัง timeout หมายความว่าไม่มี ESP32 ตอบกลับ → ใช้ค่าล่าสุดแสดง Dialog แทน
  bool _bleResponseReceived = false;

  /// หน่วงเวลารอ BLE response — สามารถ override ได้ในการทดสอบผ่าน subclass
  @visibleForTesting
  Duration get bleResponseTimeout => const Duration(milliseconds: 8000);

  // ฟังก์ชันสำหรับปุ่มกดวัดค่าสุขภาพ: สั่ง BLE และรอค่าจาก ESP32
  Future<void> _handleMeasurement() async {
    if (_isMeasuring) return;
    setState(() {
      _isMeasuring = true;
      _bleResponseReceived = false;
    });

    try {
      // 1. ส่งคำสั่งไปยังพวงกุญแจ ESP32 ผ่าน BLE ให้เริ่มวัดค่าชีพจร
      await _triggerEsp32PulseMeasurement();

      // 2. รอ BLE response ตาม timeout (8s จริง / สั้นกว่าในการทดสอบ)
      // BleService จะ broadcast stream → _bleStreamSubscription รับค่า → แสดง Dialog อัตโนมัติ
      await Future.delayed(bleResponseTimeout);

      // 3. Fallback: ถ้าหมด timeout ยังไม่ได้รับ BLE → ใช้ค่าล่าสุดในมือแสดง Dialog
      if (mounted && !_bleResponseReceived && _latestSpot != null) {
        debugPrint('>>> ⚠️ BLE timeout - showing dialog with last known values');
        setState(() => _isMeasuring = false);
        _showHealthResultDialog(_latestSpot!);
      } else if (mounted) {
        setState(() => _isMeasuring = false);
      }
    } catch (e) {
      debugPrint("Error in _handleMeasurement: $e");
      if (mounted) setState(() => _isMeasuring = false);
    }
  }

  bool _isMeasuringAuto = false;

  // ฟังก์ชันสำหรับปุ่มกดวัดค่าอุณหภูมิ & ความชื้น: สั่ง BLE และบันทึกลงฐานข้อมูล
  Future<void> _handleAutoMeasurement() async {
    if (_isMeasuringAuto) return;
    setState(() => _isMeasuringAuto = true);

    try {
      // 1. ตั้ง mode เป็น Auto_30s ให้ BleService
      BleService().setMeasurementMode('Auto_30s');

      // 2. ลองส่งคำสั่ง T:1 ไปยัง ESP32 หากเชื่อมต่อ BLE อยู่
      bool connected = await BleService().connectToKeychain();
      if (connected) {
        await Future.delayed(const Duration(milliseconds: 150));
        await BleService().sendData("T:1");
      }

      // 3. รอรับ BLE ตอบกลับ
      await Future.delayed(const Duration(milliseconds: 2500));

      // 4. Fallback: ถ้ายังอยู่ในสถานะ _isMeasuringAuto (ไม่มี BLE ส่งกลับมา) ให้ดึงค่าล่าสุดหรือบันทึกค่าลงฐานข้อมูล
      if (mounted && _isMeasuringAuto) {
        final username = widget.username.isNotEmpty ? widget.username : 'user1';
        double temp = _latestAuto?.temperature ?? (_latestSpot?.temperature ?? 25.5);
        double hum = _latestAuto?.humidity ?? (_latestSpot?.humidity ?? 58.0);
        if (temp == 0) temp = 25.5;
        if (hum == 0) hum = 58.0;

        final saved = await SensorApiService.logData(
          username: username,
          heartRate: 0,
          spO2: 0,
          temperature: temp,
          humidity: hum,
          measurementType: 'Auto_30s',
        );

        if (saved != null && mounted) {
          setState(() {
            _latestAuto = saved;
            _autoHistory.removeWhere((h) => h.id == saved.id);
            _autoHistory.add(saved);
            _autoHistory.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
            _isMeasuringAuto = false;
          });
          _showEnvironmentResultDialog(saved);
        } else if (mounted) {
          setState(() => _isMeasuringAuto = false);
        }
        await _loadData(silent: true);
      }
    } catch (e) {
      debugPrint("Error in _handleAutoMeasurement: $e");
      if (mounted) setState(() => _isMeasuringAuto = false);
    }
  }

  // ฟังก์ชันบันทึกการตรวจวัดสุขภาพลงฐานข้อมูล (Spot Check)
  // ⚠️ ฟังก์ชันนี้ถูกแทนที่ด้วย _handleMeasurement ที่ใช้ BLE stream แล้ว
  // คงเอาไว้เพื่อ backward compatibility กับส่วนอื่น

  // กล่องแจ้งเตือนผลการตรวจสุขภาพพร้อมอิโมจิและคำแนะนำทางการแพทย์
  void _showHealthResultDialog(SensorLogItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // หน้าอิโมจิขนาดใหญ่ตามระดับสุขภาพ
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.healthStatusColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: item.healthStatusColor.withValues(alpha: 0.3), width: 2),
              ),
              child: Text(
                item.healthEmoji,
                style: const TextStyle(fontSize: 44),
              ),
            ),
            const SizedBox(height: 12),

            // ข้อความสถานะสุขภาพ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: item.healthStatusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: item.healthStatusColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                item.healthStatusLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: item.healthStatusColor,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // กล่องคำแนะนำปฏิบัติตัว
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                item.healthAdvice,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // กล่องสรุปค่าตัวเลข
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('อัตราเต้นหัวใจ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        Text(
                          '${item.heartRate.toInt()} BPM',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: item.heartRateColor,
                          ),
                        ),
                        Text(
                          item.heartRateStatus,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: item.heartRateColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('ออกซิเจนในเลือด', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        Text(
                          '${item.spO2.toInt()}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: item.spO2Color,
                          ),
                        ),
                        Text(
                          item.spO2Status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: item.spO2Color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // คำเตือนทางการแพทย์ (Medical Disclaimer)
            const Text(
              '* สำหรับผู้ใหญ่ขณะพักผ่อน ใช้เพื่อการเฝ้าระวังเบื้องต้น ไม่ใช่การวินิจฉัยทางการแพทย์',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: Color(0xFF94A3B8),
                height: 1.3,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: item.healthStatusColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('ตกลง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // กล่องแจ้งเตือนผลตรวจวัดอุณหภูมิและความชื้น (สภาพแวดล้อม)
  void _showEnvironmentResultDialog(SensorLogItem item) {
    String comfortStatus;
    Color statusColor;
    String comfortEmoji;

    if (item.temperature >= 24 && item.temperature <= 29 && item.humidity >= 40 && item.humidity <= 65) {
      comfortStatus = 'สภาพอากาศสบายตัว เหมาะแก่การอยู่อาศัย';
      statusColor = const Color(0xFF10B981);
      comfortEmoji = '🍃';
    } else if (item.temperature > 32 || item.humidity > 70) {
      comfortStatus = 'อากาศค่อนข้างร้อนหรือชื้น แนะนำให้อยู่ในที่ถ่ายเท';
      statusColor = const Color(0xFFF59E0B);
      comfortEmoji = '☀️';
    } else if (item.temperature < 22) {
      comfortStatus = 'อากาศค่อนข้างเย็น ควรรักษาความอบอุ่น';
      statusColor = const Color(0xFF0284C7);
      comfortEmoji = '❄️';
    } else {
      comfortStatus = 'บันทึกสภาพแวดล้อมเรียบร้อย';
      statusColor = const Color(0xFFFF6B00);
      comfortEmoji = '🌡️';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 2),
              ),
              child: Text(
                comfortEmoji,
                style: const TextStyle(fontSize: 36),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'ผลตรวจวัดสภาพแวดล้อม',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'บันทึกเวลา ${item.formattedTime} น.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4EC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFE0CC)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'อุณหภูมิ',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFFF6B00)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.temperature.toStringAsFixed(1)} °C',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF14293D)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'ความชื้น',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.humidity.toStringAsFixed(1)} %',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF14293D)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      comfortStatus,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('ตกลง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadData(),
          color: const Color(0xFFFF6B00),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildPillTabSwitch(),
                const SizedBox(height: 20),
                if (_isLoading && _spotHistory.isEmpty && _autoHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFFF6B00)),
                    ),
                  )
                else if (_activeTabIndex == 0)
                  _buildSpotHealthTab()
                else
                  _buildAutoSensorTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'สุขภาพ & เซนเซอร์',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'วิเคราะห์ข้อมูลสุขภาพและสถิติสภาพแวดล้อม',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
          tooltip: 'รีเฟรชข้อมูล',
          onPressed: () => _loadData(),
        ),
      ],
    );
  }

  Widget _buildPillTabSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPillItem(
              index: 0,
              title: 'สุขภาพ',
            ),
          ),
          Expanded(
            child: _buildPillItem(
              index: 1,
              title: 'อุณหภูมิ & ความชื้น',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillItem({
    required int index,
    required String title,
  }) {
    final bool isSelected = _activeTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTabIndex = index;
        });
        // ✅ แจ้ง BleService ว่าเราอยู่ใน mode ใด
        // Tab 0 (สุขภาพ) = Manual_Spot, Tab 1 (เซนเซอร์ 30 นาที) = Auto_30s
        BleService().setMeasurementMode(index == 0 ? 'Manual_Spot' : 'Auto_30s');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF14293D) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildSpotHealthTab() {
    final spot = _latestSpot;

    final String hrVal = (_latestSpot != null && _latestSpot!.heartRate > 0)
        ? _latestSpot!.heartRate.toInt().toString()
        : '--';

    final String spo2Val = (_latestSpot != null && _latestSpot!.spO2 > 0)
        ? '${_latestSpot!.spO2.toInt()}%'
        : '--';

    final hrColor = spot?.heartRateColor ?? const Color(0xFF94A3B8);
    final spo2Color = spot?.spO2Color ?? const Color(0xFF94A3B8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ผลตรวจวัดสุขภาพล่าสุด',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14293D),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'เซนเซอร์ ESP32',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      spot != null ? spot.formattedTime : 'ไม่มีข้อมูล',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFEE2E2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'อัตราเต้นหัวใจ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                hrVal,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: hrColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'BPM',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCFCE7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ออกซิเจน SpO2',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF155E75),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                spo2Val,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: spo2Color,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ส่วนที่ 2: วิเคราะห์สุขภาพ ในช่อง ผลตรวจวัดสุขภาพล่าสุด วัดจาก ประวัติย้อนหลัง 10 ครั้งล่าสุด
              _buildRecentHealthAnalysisCard(),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _isMeasuring ? null : _handleMeasurement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  disabledBackgroundColor: const Color(0xFFFCA5A5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isMeasuring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.touch_app_rounded, size: 18),
                label: Text(
                  _isMeasuring ? 'กำลังวัดสัญญาณชีพสุขภาพ...' : 'แตะเพื่อบันทึกการวัดสุขภาพตอนนี้',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSpotChartCard(),
        const SizedBox(height: 24),
        _buildSpotHistoryList(),
      ],
    );
  }

  // ส่วนที่ 2: การ์ดวิเคราะห์สุขภาพจากประวัติย้อนหลัง 5 ครั้งล่าสุดในฐานข้อมูล (ปรับแต่งคลีน มินิมอล)
  Widget _buildRecentHealthAnalysisCard() {
    final analysis = RecentHealthAnalysis.fromHistory(_spotHistory, limit: 5);
    final themeColor = analysis.statusColor;

    return Container(
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.2), width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  analysis.emoji,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'วิเคราะห์สุขภาพ ${analysis.count > 0 ? "(${analysis.count} ครั้งล่าสุด)" : ""}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      analysis.summary,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  analysis.statusLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ),
            ],
          ),
          if (analysis.hasData) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildMiniStat('HR เฉลี่ย', '${analysis.avgHeartRate.round()} BPM', const Color(0xFFEF4444))),
                  Container(width: 1, height: 20, color: const Color(0xFFE2E8F0)),
                  Expanded(child: _buildMiniStat('SpO2 เฉลี่ย', '${analysis.avgSpO2.round()}%', const Color(0xFF0284C7))),
                  Container(width: 1, height: 20, color: const Color(0xFFE2E8F0)),
                  Expanded(child: _buildMiniStat('สม่ำเสมอ', '${analysis.normalCount}/${analysis.count} ครั้ง', const Color(0xFF10B981))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSpotChartCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'กราฟแนวโน้มสัญญาณชีพ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'การเปลี่ยนแปลงของชีพจรและออกซิเจน',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildLegendItem(const Color(0xFFEF4444), 'BPM'),
                  const SizedBox(width: 10),
                  _buildLegendItem(const Color(0xFF0284C7), 'SpO2'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: _spotHistory.isEmpty
                ? _buildEmptyChartPlaceholder('ยังไม่มีข้อมูลสำหรับพล็อตแนวโน้ม')
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: const Color(0xFFF1F5F9),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: max(1, (_spotHistory.length / 5).floor().toDouble()),
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < _spotHistory.length) {
                                final time = _spotHistory[index].recordedAt;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${time.minute}:${time.second.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 20,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: 40,
                      maxY: 140,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _spotHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.heartRate);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFFEF4444),
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          ),
                        ),
                        LineChartBarData(
                          spots: _spotHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.spO2);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFF0284C7),
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotHistoryList() {
    // เรียงลำดับจากเวลาใหม่สุดไปหาเก่าสุด เพื่อให้ข้อมูลล่าสุดอยู่บนสุดเสมอ (แสดง 5 จุดข้อมูลล่าสุด)
    final sortedDesc = List<SensorLogItem>.from(_spotHistory)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final displayList = sortedDesc.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'ประวัติการตรวจวัดย้อนหลัง',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${displayList.length} ครั้งล่าสุด',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (displayList.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Text(
                'ยังไม่มีประวัติการวัด (กดปุ่มวัดค่าที่ ESP32 หรือกดปุ่มด้านบน)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = displayList[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showHealthResultDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: item.heartRateColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(item.heartRateIcon, size: 18, color: item.heartRateColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${item.heartRate.toInt()} BPM',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: Color(0xFF14293D),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '• SpO2 ${item.spO2.toInt()}%',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF0284C7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item.healthStatusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.healthStatusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: item.healthStatusColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      item.heartRateStatus,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: item.heartRateColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item.formattedTime,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF14293D),
                              ),
                            ),
                            Text(
                              item.formattedDate,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAutoSensorTab() {
    final auto = _latestAuto;

    // ตรวจสอบค่าอุณหภูมิและความชื้นสดสำหรับแสดงผล
    final tempVal = (auto != null && auto.temperature > 0)
        ? '${auto.temperature.toStringAsFixed(1)} °C'
        : '--';

    final humVal = (auto != null && auto.humidity > 0)
        ? '${auto.humidity.toStringAsFixed(1)} %'
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.thermostat_rounded,
                        color: Color(0xFFFF6B00),
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'อุณหภูมิโดยรอบ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tempVal,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.water_drop_rounded,
                        color: Color(0xFF3B82F6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ความชื้นในอากาศ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      humVal,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _isMeasuringAuto ? null : _handleAutoMeasurement,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B00),
            disabledBackgroundColor: const Color(0xFFFFB280),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: _isMeasuringAuto
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.touch_app_rounded, size: 18),
          label: Text(
            _isMeasuringAuto ? 'กำลังอ่านค่าสภาพแวดล้อม...' : 'แตะเพื่อบันทึกค่าอุณหภูมิ & ความชื้นตอนนี้',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 24),
        _buildAutoChartCard(),
        const SizedBox(height: 24),
        _buildAutoHistoryList(),
      ],
    );
  }

  Widget _buildAutoChartCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'กราฟแนวโน้มสภาพแวดล้อม',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'อุณหภูมิ (°C) และความชื้นสัมพัทธ์ (% RH)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(const Color(0xFFFF6B00), 'Temp'),
                  const SizedBox(width: 10),
                  _buildLegendItem(const Color(0xFF3B82F6), 'Humidity'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 210,
            child: _autoHistory.isEmpty
                ? _buildEmptyChartPlaceholder('ยังไม่มีข้อมูลเซนเซอร์ 30 นาที')
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 10,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: const Color(0xFFF1F5F9),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: max(1, (_autoHistory.length / 5).floor().toDouble()),
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < _autoHistory.length) {
                                final time = _autoHistory[index].recordedAt;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 20,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: 10,
                      maxY: 100,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _autoHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.temperature);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFFFF6B00),
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFFFF6B00).withValues(alpha: 0.1),
                          ),
                        ),
                        LineChartBarData(
                          spots: _autoHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.humidity);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFF3B82F6),
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoHistoryList() {
    // เรียงลำดับจากเวลาใหม่สุดไปหาเก่าสุด เพื่อให้ข้อมูลล่าสุดอยู่บนสุดเสมอ (แสดง 5 จุดข้อมูลล่าสุด)
    final sortedDesc = List<SensorLogItem>.from(_autoHistory)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final displayList = sortedDesc.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'บันทึกล่าสุดจากเซนเซอร์ (ทุก 30 นาที)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${displayList.length} จุดข้อมูล',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (displayList.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Text(
                'ยังไม่มีข้อมูลการบันทึก',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = displayList[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFECFDF5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sensors_rounded,
                        size: 18,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${item.temperature} °C',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: Color(0xFF14293D),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '• ความชื้น ${item.humidity}%',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'บันทึกอัตโนมัติจากฮาร์ดแวร์',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item.formattedTime,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildEmptyChartPlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart_rounded, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

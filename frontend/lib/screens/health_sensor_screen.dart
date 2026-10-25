import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/sensor_data.dart';
import '../services/api/sensor_api_service.dart';

class HealthSensorScreen extends StatefulWidget {
  final String username;
  final bool isConnected;

  const HealthSensorScreen({
    super.key,
    required this.username,
    this.isConnected = false,
  });

  @override
  State<HealthSensorScreen> createState() => _HealthSensorScreenState();
}

class _HealthSensorScreenState extends State<HealthSensorScreen>
    with SingleTickerProviderStateMixin {
  int _activeTabIndex = 0; // 0 = วัดสุขภาพเฉพาะกิจ, 1 = สภาพแวดล้อม 30 วินาที
  bool _isLoading = false;
  Timer? _autoRefreshTimer;

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
    )..repeat(reverse: true);
    _heartScale = Tween<double>(begin: 0.92, end: 1.15).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.easeInOut),
    );

    _loadData();

    // ดึงข้อมูลอัตโนมัติเป็นระยะ (ทุก 15 วินาที สำหรับหน้า 30s)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
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
          _latestSpot = results[0] as SensorLogItem?;
          _spotHistory = results[1] as List<SensorLogItem>;
          _latestAuto = results[2] as SensorLogItem?;
          _autoHistory = results[3] as List<SensorLogItem>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sensor data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ฟังก์ชันจำลองการส่งข้อมูลเซนเซอร์ (สำหรับ Demo / ทดสอบบนเครื่อง)
  Future<void> _triggerSimulate({required String type, int count = 12}) async {
    setState(() => _isLoading = true);
    final username = widget.username.isNotEmpty ? widget.username : 'user1';
    final success = await SensorApiService.simulateData(
      username: username,
      measurementType: type,
      count: count,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('สร้างข้อมูลจำลอง ($type) เรียบร้อยแล้ว'),
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('ไม่สามารถเชื่อมต่อ Backend API ได้ (ตรวจสอบว่า dotnet run อยู่หรือไม่)'),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ผู้ใช้กดบันทึกวัดค่าเดี๋ยวนี้ (Spot Check)
  Future<void> _recordManualMeasurement() async {
    final random = Random();
    final hr = (70 + random.nextInt(26)).toDouble(); // 70-95 bpm
    final spo2 = (96 + random.nextInt(4)).toDouble(); // 96-99 %
    final temp = (27.5 + (random.nextDouble() * 2.0)); // 27.5-29.5 C
    final hum = (54.0 + (random.nextDouble() * 8.0)); // 54-62 %

    final username = widget.username.isNotEmpty ? widget.username : 'user1';
    final result = await SensorApiService.logData(
      username: username,
      heartRate: hr,
      spO2: spo2,
      temperature: double.parse(temp.toStringAsFixed(1)),
      humidity: double.parse(hum.toStringAsFixed(1)),
      measurementType: 'Manual_Spot',
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('บันทึกค่าแล้ว: $hr BPM, SpO2 $spo2%'),
        ),
      );
      await _loadData(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. หัวข้อหน้า + ปุ่มจำลองข้อมูล
                  _buildHeader(),
                  const SizedBox(height: 16),

                  // 2. แถบสวิตช์แคปซูล 2 แท็บ
                  _buildPillTabSwitch(),
                  const SizedBox(height: 20),

                  // 3. แสดงผลเนื้อหาตามแท็บ
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
      ),
    );
  }

  // 1. Header
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'สุขภาพ & เซนเซอร์',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'วิเคราะห์ข้อมูลสุขภาพและสถิติสภาพแวดล้อม',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        Row(
          children: [
            // ปุ่ม Refresh
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              tooltip: 'รีเฟรชข้อมูล',
              onPressed: () => _loadData(),
            ),
            // ปุ่ม Demo Simulator
            PopupMenuButton<String>(
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD8BF)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_graph_rounded, color: Color(0xFFFF6B00), size: 16),
                    SizedBox(width: 4),
                    Text(
                      'จำลอง',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ],
                ),
              ),
              tooltip: 'จำลองข้อมูลทดสอบ (Demo)',
              onSelected: (value) {
                if (value == 'sim_spot') {
                  _triggerSimulate(type: 'Manual_Spot', count: 12);
                } else if (value == 'sim_auto') {
                  _triggerSimulate(type: 'Auto_30s', count: 20);
                } else if (value == 'clear') {
                  SensorApiService.clearHistory(username: widget.username);
                  _loadData();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sim_spot',
                  child: Row(
                    children: [
                      Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 18),
                      SizedBox(width: 8),
                      Text('จำลองข้อมูลวัดสุขภาพ (Spot)'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'sim_auto',
                  child: Row(
                    children: [
                      Icon(Icons.sensors_rounded, color: Color(0xFF10B981), size: 18),
                      SizedBox(width: 8),
                      Text('จำลองข้อมูลเซนเซอร์ 30 วิ (Auto)'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 18),
                      SizedBox(width: 8),
                      Text('ล้างข้อมูลทดสอบ'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // 2. Pill Segmented Switch
  Widget _buildPillTabSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPillItem(
              index: 0,
              icon: Icons.favorite_rounded,
              title: 'วัดสุขภาพเฉพาะกิจ',
              activeColor: const Color(0xFFEF4444),
            ),
          ),
          Expanded(
            child: _buildPillItem(
              index: 1,
              icon: Icons.thermostat_rounded,
              title: 'เซนเซอร์ 30 วินาที',
              activeColor: const Color(0xFFFF6B00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillItem({
    required int index,
    required IconData icon,
    required String title,
    required Color activeColor,
  }) {
    final bool isSelected = _activeTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTabIndex = index;
        });
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
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? activeColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF14293D) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: วัดสุขภาพเฉพาะกิจ (SPOT HEALTH)
  // ==========================================
  Widget _buildSpotHealthTab() {
    final spot = _latestSpot;

    final hrVal = spot != null && spot.heartRate > 0 ? spot.heartRate.toInt().toString() : '--';
    final spo2Val = spot != null && spot.spO2 > 0 ? '${spot.spO2.toInt()}%' : '--';
    final hrStatus = spot?.heartRateStatus ?? 'ยังไม่ได้วัดค่า';
    final hrColor = spot?.heartRateColor ?? const Color(0xFF94A3B8);
    final spo2Status = spot?.spO2Status ?? 'ยังไม่มีข้อมูล';
    final spo2Color = spot?.spO2Color ?? const Color(0xFF94A3B8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // การ์ดแสดงผลค่าล่าสุดแบบ Hero
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
              // หัวการ์ด: ไอคอนเต้นตุบๆ + เวลาวัดล่าสุด
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ScaleTransition(
                        scale: _heartScale,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ผลตรวจวัดสุขภาพล่าสุด',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF14293D),
                            ),
                          ),
                          Text(
                            'เซนเซอร์สัมผัสบนพวงกุญแจ',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ],
                  ),
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

              // 2 ตัวเลขใหญ่ (Heart Rate & SpO2)
              Row(
                children: [
                  // กล่องอัตราการเต้นหัวใจ
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFEE2E2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'อัตราเต้นหัวใจ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF991B1B),
                                ),
                              ),
                              Icon(Icons.monitor_heart_rounded, size: 18, color: hrColor),
                            ],
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
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: hrColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              hrStatus,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: hrColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // กล่องออกซิเจนในเลือด SpO2
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFEFF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFCFFAFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ออกซิเจน SpO2',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF155E75),
                                ),
                              ),
                              Icon(Icons.water_drop_rounded, size: 18, color: spo2Color),
                            ],
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
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: spo2Color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              spo2Status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: spo2Color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ปุ่มกดวัดค่าตอนนี้ (Manual Spot Measurement Trigger)
              ElevatedButton.icon(
                onPressed: _recordManualMeasurement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.touch_app_rounded, size: 18),
                label: const Text(
                  'แตะเพื่อบันทึกการวัดสุขภาพตอนนี้',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 3. กราฟ Data Analytics สำหรับ Heart Rate & SpO2
        _buildSpotChartCard(),

        const SizedBox(height: 24),

        // 4. รายการประวัติย้อนหลัง (History Logs)
        _buildSpotHistoryList(),
      ],
    );
  }

  // วิดเจ็ตกราฟแนวโน้ม Spot Health
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
                      'แนวโน้มสุขภาพ (Analytics)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'เปรียบเทียบอัตราการเต้นหัวใจและการวัดล่าสุด',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildLegendItem(const Color(0xFFEF4444), 'Heart Rate'),
                  const SizedBox(width: 10),
                  _buildLegendItem(const Color(0xFF06B6D4), 'SpO2'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ตัวกราฟ FlChart
          SizedBox(
            height: 200,
            child: _spotHistory.isEmpty
                ? _buildEmptyChartPlaceholder('ยังไม่มีข้อมูลประวัติการวัดสุขภาพ')
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
                            interval: 25,
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
                        // เส้น Heart Rate (สีแดง)
                        LineChartBarData(
                          spots: _spotHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.heartRate);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFFEF4444),
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          ),
                        ),
                        // เส้น SpO2 (สีฟ้า)
                        LineChartBarData(
                          spots: _spotHistory.asMap().entries.map((entry) {
                            return FlSpot(entry.key.toDouble(), entry.value.spO2);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFF06B6D4),
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

  // วิดเจ็ตรายการประวัติ Spot History
  Widget _buildSpotHistoryList() {
    final reversed = _spotHistory.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ประวัติการตรวจวัดย้อนหลัง',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
              ),
            ),
            Text(
              '${reversed.length} ครั้งล่าสุด',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reversed.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Text(
                'ยังไม่มีประวัติการวัด (กดปุ่มวัดค่า หรือกดปุ่ม "จำลอง" ด้านบน)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(reversed.length, 6),
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = reversed[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${item.heartRate.toInt()} BPM',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: Color(0xFF14293D),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '•   SpO2 ${item.spO2.toInt()}%',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF0284C7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.heartRateStatus,
                            style: TextStyle(
                              fontSize: 11,
                              color: item.heartRateColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.formattedTime,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14293D),
                          ),
                        ),
                        Text(
                          item.formattedDate,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ==========================================
  // TAB 1: สภาพแวดล้อมอัตโนมัติ 30 วินาที (AUTO 30S)
  // ==========================================
  Widget _buildAutoSensorTab() {
    final auto = _latestAuto;

    final tempVal = auto != null && auto.temperature > 0 ? '${auto.temperature} °C' : '--';
    final humVal = auto != null && auto.humidity > 0 ? '${auto.humidity} %' : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Live Banner เซนเซอร์ตรวจวัดอัตโนมัติ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'มอนิเตอร์สภาพแวดล้อมอัตโนมัติ (Continuous Sensor)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    Text(
                      auto != null
                          ? 'บันทึกค่าทุกๆ 30 วินาที • อัปเดตล่าสุด: ${auto.formattedTime}'
                          : 'รอรับข้อมูลจากเซนเซอร์ทุก 30 วินาที...',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF047857)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.sync_rounded, color: Color(0xFF10B981), size: 20),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 2. การ์ดคู่แสดงอุณหภูมิและความชื้นปัจจุบัน
        Row(
          children: [
            // การ์ดอุณหภูมิ
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
                    const SizedBox(height: 4),
                    Text(
                      auto?.tempStatus ?? 'สภาวะปกติ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: auto?.tempColor ?? const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // การ์ดความชื้น
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
                    const SizedBox(height: 4),
                    const Text(
                      'ระดับเหมาะสม (RH)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 3. กราฟ Time-series แสดงความผันผวนของสภาพแวดล้อม
        _buildAutoChartCard(),

        const SizedBox(height: 24),

        // 4. ไทม์ไลน์บันทึกข้อมูลทุก 30 วินาที
        _buildAutoHistoryList(),
      ],
    );
  }

  // วิดเจ็ตกราฟ Time-series สำหรับ Auto 30s
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
                      'กราฟแนวโน้มสภาพแวดล้อม (30s Stream)',
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
                ? _buildEmptyChartPlaceholder('ยังไม่มีข้อมูลเซนเซอร์ 30 วิ (กดปุ่ม "จำลอง" เพื่อสร้างข้อมูลตัวอย่าง)')
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
                      minY: 10,
                      maxY: 80,
                      lineBarsData: [
                        // เส้นอุณหภูมิ (สีส้ม)
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
                        // เส้นความชื้น (สีฟ้า)
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

  // วิดเจ็ตรายการประวัติ Auto 30s
  Widget _buildAutoHistoryList() {
    final reversed = _autoHistory.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'บันทึกล่าสุดจากเซนเซอร์ (ทุก 30 วินาที)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
              ),
            ),
            Text(
              '${reversed.length} จุดข้อมูล',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reversed.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Text(
                'ยังไม่มีข้อมูลการบันทึก (กดปุ่ม "จำลอง" เพื่อสร้างข้อมูลตัวอย่าง)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(reversed.length, 6),
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = reversed[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        color: const Color(0xFFECFDF5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sensors_rounded,
                        size: 18,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 14),
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
                                '•   ความชื้น ${item.humidity}%',
                                style: const TextStyle(
                                  fontSize: 13,
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
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item.formattedTime,
                      style: const TextStyle(
                        fontSize: 12,
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

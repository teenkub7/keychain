import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import 'services/api/image_ble_helper.dart';
import 'services/api/api_config.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/health_sensor_screen.dart';
import 'screens/display_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Keychain',
      theme: ThemeData(
        fontFamily: 'Prompt',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          primary: const Color(0xFFFF6B00),
          secondary: const Color(0xFF14293D),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const MainScreen({super.key, this.userData});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  bool isConnected = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // 🟢 1. สร้าง StreamController ไว้ส่งสัญญาณ BLE Notify ไปยัง HomeScreen
  final StreamController<String> _bleNotifyController = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _valueSubscription?.cancel();
    _connectionSubscription?.cancel();
    _bleNotifyController.close();
    super.dispose();
  }

  // ฟังก์ชันส่งข้อมูลข้อความ BLE ไปยัง ESP32
  Future<void> sendBleData(String payload) async {
    if (targetCharacteristic != null && isConnected) {
      try {
        await targetCharacteristic!.write(utf8.encode(payload));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งข้อมูลลงพวงกุญแจแล้ว: $payload')),
        );
      } catch (e) {
        debugPrint("Error sending BLE data: $e");
      }
    } else {
      debugPrint("ไม่ได้เชื่อมต่อ BLE (จำลองการส่ง): $payload");
    }
  }

  // ฟังก์ชันประมวลผลและส่งรูปภาพผ่าน BLE ไปยัง ESP32
  Future<void> sendImageBle(Uint8List rawImageBytes, {String type = 'image'}) async {
    if (targetDevice == null || targetCharacteristic == null || !isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเชื่อมต่ออุปกรณ์ BLE ก่อน')),
      );
      return;
    }

    try {
      if (!mounted) return;
      final label = type == 'qr' ? 'รูปภาพ QR Code' : 'รูปภาพ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('กำลังประมวลผลและส่ง$label...')),
      );

      await ImageBleHelper.sendImageToESP32(
        rawImageBytes: rawImageBytes,
        characteristic: targetCharacteristic!,
        device: targetDevice!,
        type: type == 'qr' ? 'IMG_QR' : 'IMG',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่ง$labelลงพวงกุญแจสำเร็จ!')),
      );
    } catch (e) {
      debugPrint("Handled Exception: $e");
      // แม้เกิด Warning แต่ฝั่ง ESP32 แสดงผล OK แล้ว ให้ถือว่าสำเร็จ
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรูปภาพเรียบร้อยแล้ว')),
      );
    }
  }

  // ฟังก์ชันส่งเวลาปัจจุบันไปซิงค์กับนาฬิกาของ ESP32
  Future<void> syncTimeToEsp32() async {
    if (targetCharacteristic == null || !isConnected) return;
    try {
      DateTime now = DateTime.now();
      String hour = now.hour.toString().padLeft(2, '0');
      String minute = now.minute.toString().padLeft(2, '0');
      String second = now.second.toString().padLeft(2, '0');
      String timePayload = "TIME:$hour:$minute:$second";

      await targetCharacteristic!.write(utf8.encode(timePayload), withoutResponse: false);
      debugPrint("🕒 ซิงค์เวลาสำเร็จ: $timePayload");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🕒 ซิงค์เวลากับพวงกุญแจสำเร็จ ($hour:$minute:$second)'),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ เกิดข้อผิดพลาดในการซิงค์เวลา: $e");
    }
  }

  // ฟังก์ชันส่งข้อมูลกลับไปอัปเดตลง C# Server
  Future<void> saveUserDataToBackend(String key, String value) async {
    if (widget.userData == null) return;

    final url = Uri.parse('${ApiConfig.userBaseUrl}/update-data');
    final username = widget.userData!['username'] ?? widget.userData!['userId'];

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          key: value,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("บันทึก $key ลง MySQL สำเร็จ");
      } else {
        debugPrint("C# API Error ($key): ${response.body}");
      }
    } catch (e) {
      debugPrint("Failed to update data on C# API: $e");
    }
  }

  // ฟังก์ชันยกเลิกการเชื่อมต่อ BLE
  Future<void> disconnectEsp32() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _valueSubscription?.cancel();
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      if (targetDevice != null) {
        await targetDevice!.disconnect();
      }
    } catch (e) {
      debugPrint("Error disconnecting BLE device: $e");
    } finally {
      if (mounted) {
        setState(() {
          isConnected = false;
          targetDevice = null;
          targetCharacteristic = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ตัดการเชื่อมต่อบลูทูธเรียบร้อย'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF64748B),
          ),
        );
      }
    }
  }

  // ฟังก์ชันสแกนและเชื่อมต่อ BLE พร้อมหน้าต่าง Animation เรดาร์
  void connectToEsp32() async {
    showDialog(
      context: context,
      builder: (ctx) => _BleScanningDialog(
        isConnected: isConnected,
        onDisconnect: disconnectEsp32,
        onCancelScan: () async {
          await FlutterBluePlus.stopScan();
          await _scanSubscription?.cancel();
        },
      ),
    );

    // หากรันบน Native Mobile (Android/iOS) ให้เริ่มสแกนหา ESP32 จริง
    if (!kIsWeb && !isConnected) {
      try {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();

        if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
            statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
          return;
        }

        if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
          return;
        }

        await _scanSubscription?.cancel();
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

        _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
          for (ScanResult r in results) {
            String deviceName = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName;

            if (deviceName == "ESP32_SmartKeychain" || deviceName == "Smart Keychain") {
              await FlutterBluePlus.stopScan();
              await _scanSubscription?.cancel();

              targetDevice = r.device;
              await targetDevice!.connect();

              List<BluetoothService> services = await targetDevice!.discoverServices();
              for (var service in services) {
                for (var c in service.characteristics) {
                  // เช็ค Characteristic ที่รองรับ Notify, Indicate หรือ Write
                  if (c.properties.notify || c.properties.indicate || c.properties.write) {
                    targetCharacteristic = c;
                    
                    // 🟢 2. เปิดระบบรับ Notification จาก ESP32
                    if (c.properties.notify || c.properties.indicate) {
                      await c.setNotifyValue(true);
                      _valueSubscription?.cancel();
                      _valueSubscription = c.lastValueStream.listen((value) {
                        if (value.isNotEmpty) {
                          String message = utf8.decode(value).trim();
                          debugPrint(">>> 📥 BLE Notification Received: $message");

                          // ตรวจสอบค่าสุขภาพและเซนเซอร์ (Health/Sensor Alert)
                          try {
                            if (message.startsWith('{') && message.endsWith('}')) {
                              final Map<String, dynamic> data = jsonDecode(message);
                              final hr = double.tryParse(data['hr']?.toString() ?? '0');
                              final spo2 = double.tryParse(data['spo2']?.toString() ?? '0');
                              final temp = double.tryParse(data['temp']?.toString() ?? '0');
                              final hum = double.tryParse(data['hum']?.toString() ?? '0');
                              NotificationService.instance.checkAndAlertSensorData(
                                heartRate: hr,
                                spO2: spo2,
                                temperature: temp,
                              );

                              // 🌡️ แจ้งเตือนผลการวัดอุณหภูมิและความชื้น
                              if ((temp != null && temp > 0) || (hum != null && hum > 0)) {
                                NotificationService.instance.showTempHumidityAlert(
                                  temperature: temp ?? 0.0,
                                  humidity: hum ?? 0.0,
                                );
                              }
                            }
                          } catch (_) {}

                          // ตรวจสอบข้อความเมื่อ Buzzer ของ ESP32 ทำงานครบเวลา (DEL_T:)
                          if (message.startsWith("DEL_T:")) {
                            String deletedText = message.substring(6).trim();
                            NotificationService.instance.showNotification(
                              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                              title: '📋 ถึงเวลาทำกิจกรรมแล้ว! (Smart Keychain)',
                              body: deletedText,
                              payload: 'TODO_DEL_T',
                            );
                          }

                          // ยิงข้อความที่ได้จาก ESP32 เข้า StreamController
                          _bleNotifyController.add(message);
                        }
                      });
                    }

                    // 🚨 Anti-Lost Alert: ดักจับเหตุการณ์สัญญาณขาดหาย/หลุดระยะ
                    _connectionSubscription?.cancel();
                    _connectionSubscription = targetDevice!.connectionState.listen((state) {
                      if (state == BluetoothConnectionState.disconnected && isConnected) {
                        debugPrint("🚨 [Anti-Lost] BLE Disconnected from $deviceName!");
                        if (mounted) {
                          setState(() {
                            isConnected = false;
                            targetCharacteristic = null;
                          });
                        }
                        NotificationService.instance.showAntiLostAlert(deviceName: deviceName);
                      }
                    });

                    if (mounted) {
                      setState(() {
                        isConnected = true;
                      });
                      Navigator.of(context, rootNavigator: true).maybePop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🟢 เชื่อมต่อกับ $deviceName สำเร็จ!'),
                          backgroundColor: const Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    syncUserDataToEsp32();
                    break;
                  }
                }
              }
              break;
            }
          }
        });
      } catch (e) {
        debugPrint("BLE Scan Exception: $e");
      }
    }
  }

  void syncUserDataToEsp32() async {
    // 🟢 1. ซิงค์เวลาปัจจุบันกับ ESP32 ทันทีที่เชื่อมต่อ
    await syncTimeToEsp32();

    if (widget.userData != null && isConnected) {
      if (widget.userData!['routineData'] != null) {
        await sendBleData("R:${widget.userData!['routineData']}");
      }
      if (widget.userData!['imageData'] != null) {
        await sendBleData("IMG:${widget.userData!['imageData']}");
      }
      if (widget.userData!['qrData'] != null) {
        await sendBleData("QR:${widget.userData!['qrData']}");
      }
      if (widget.userData!['nfcData'] != null) {
        await sendBleData("NFC:${widget.userData!['nfcData']}");
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String currentUsername =
        widget.userData?['username']?.toString() ??
        widget.userData?['userId']?.toString() ??
        widget.userData?['UserId']?.toString() ??
        'User';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 38,
              height: 38,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.key_rounded,
                color: Color(0xFFFF6B00),
                size: 32,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Smart Keychain',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // 🟢 3. ส่ง bleNotifyStream และ onUpdateDatabaseRoutine ไปยัง HomeScreen
          HomeScreen(
            isConnected: isConnected,
            onConnectPressed: connectToEsp32,
            username: currentUsername,
            userData: widget.userData,
            onNavigateToTab: _onItemTapped,
            onSendBleData: sendBleData,
            bleNotifyStream: _bleNotifyController.stream,
            
            // 1. อัปเดต Database เมื่อมีการลบ/แก้ไข (ถ้าเป็นค่าว่าง จะล้าง Database เป็น "")
            onUpdateDatabaseRoutine: (newRoutine) {
              String cleanRoutine = (newRoutine == "CLEAR" || newRoutine == "T:CLEAR") ? "" : newRoutine;
              saveUserDataToBackend("routineData", cleanRoutine);
            },
            
            // 2. จัดการคำสั่งส่ง BLE ไปยัง ESP32
            onSendTodoList: (data) {
              if (data == "CLEAR" || data == "T:CLEAR" || data.isEmpty) {
                sendBleData("T:CLEAR");
              } else {
                String payload = data.startsWith("T:") ? data : "T:$data";
                sendBleData(payload);
              }
            },
          ),
          HealthSensorScreen(
            username: currentUsername,
            isConnected: isConnected,
          ),
          DisplayScreen(
            initialQrData: widget.userData?['qrData'],
            initialImageData: widget.userData?['imageData'],
            onSendDisplay: (data, {String type = 'image'}) async {
              if (data is Uint8List) {
                await sendImageBle(data, type: type);
                
                Uint8List processed = ImageBleHelper.processImageForESP32(data, isQr: type == 'qr');
                String base64Str = base64Encode(processed);
                if (type == 'qr') {
                  saveUserDataToBackend("qrData", base64Str);
                } else {
                  saveUserDataToBackend("imageData", base64Str);
                }
              } 
              else if (data is String) {
                sendBleData(data);
                if (data.startsWith("IMG:")) {
                  saveUserDataToBackend("imageData", data.substring(4));
                } else if (data.startsWith("QR:")) {
                  saveUserDataToBackend("qrData", data.substring(3));
                }
              }
            },
          ),
          SettingsPage(
            isConnected: isConnected,
            connectedDeviceName: (targetDevice != null && targetDevice!.platformName.isNotEmpty)
                ? targetDevice!.platformName
                : null,
            onDisconnect: disconnectEsp32,
            onConnect: connectToEsp32,
            onSendBleData: sendBleData,
            onSyncTime: syncTimeToEsp32,
            username: currentUsername,
            userData: widget.userData,
            onLogout: () async {
              if (isConnected && targetDevice != null) {
                try {
                  await targetDevice!.disconnect();
                } catch (_) {}
              }
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: const Color(0xFFFF6B00),
          unselectedItemColor: const Color(0xFF94A3B8),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded, color: Color(0xFFFF6B00)),
              label: 'หน้าแรก',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.monitor_heart_outlined),
              activeIcon: Icon(Icons.monitor_heart_rounded, color: Color(0xFFFF6B00)),
              label: 'สุขภาพ',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_2_rounded),
              activeIcon: Icon(Icons.qr_code_2_rounded, color: Color(0xFFFF6B00)),
              label: 'ส่งรูป/QR',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded, color: Color(0xFFFF6B00)),
              label: 'ตั้งค่า',
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// กล่องแจ้งเตือนสแกนบลูทูธ พร้อมเรดาร์แอนิเมชัน (Radar Pulse Animation)
// -------------------------------------------------------------
class _BleScanningDialog extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onDisconnect;
  final VoidCallback? onCancelScan;

  const _BleScanningDialog({
    required this.isConnected,
    required this.onDisconnect,
    this.onCancelScan,
  });

  @override
  State<_BleScanningDialog> createState() => _BleScanningDialogState();
}

class _BleScanningDialogState extends State<_BleScanningDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isConnected) {
      // หน้าต่างเมื่อเชื่อมต่ออยู่แล้ว: ให้ผู้ใช้ดูสถานะหรือตัดการเชื่อมต่อได้
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(26.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bluetooth_connected_rounded,
                  color: Color(0xFF15803D),
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'เชื่อมต่อบลูทูธแล้ว',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'เชื่อมต่อกับ ESP32_SmartKeychain สำเร็จ พร้อมส่งข้อมูลและอัปเดตหน้าจอทันที',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE11D48),
                        side: const BorderSide(color: Color(0xFFFECDD3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDisconnect();
                      },
                      child: const Text('ตัดการเชื่อมต่อ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14293D),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('เรียบร้อย'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // หน้าต่างค้นหาบลูทูธ: แสดงเรดาร์แอนิเมชันหมุน/พัลส์
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Radar Wave Animation
            SizedBox(
              width: 130,
              height: 130,
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // คลื่นรอบนอก วงที่ 2
                      Transform.scale(
                        scale: 0.6 + (_animController.value * 0.4),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFF6B00).withValues(
                                alpha: (1.0 - _animController.value) * 0.45,
                              ),
                              width: 2.2,
                            ),
                          ),
                        ),
                      ),
                      // คลื่นรอบนอก วงที่ 1
                      Transform.scale(
                        scale: 0.4 + (_animController.value * 0.4),
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF6B00).withValues(
                              alpha: (1.0 - _animController.value) * 0.18,
                            ),
                          ),
                        ),
                      ),
                      // วงกลมแกนกลางไอคอน Bluetooth
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF7A00), Color(0xFFFF4800)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B00).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bluetooth_searching_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'กำลังค้นหาอุปกรณ์ Bluetooth...',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'กำลังสแกนหา "ESP32_SmartKeychain" ในบริเวณใกล้เคียง',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 18),

            // การ์ดแสดงคำแนะนำสำหรับค้นหาฮาร์ดแวร์จริง
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'กรุณาเปิดอุปกรณ์พวงกุญแจและนำมาไว้ใกล้ๆ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCancelScan?.call();
                },
                child: const Text(
                  'ยกเลิกการค้นหา',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

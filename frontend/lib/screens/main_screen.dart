import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import 'login_screen.dart';
import 'home_screen.dart';
import 'todo_list_screen.dart';
import 'display_screen.dart';
import 'nfc_screen.dart';
import 'settings_screen.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

  // 🔴 กำหนด IP Address ของ C# Backend เพียงจุดเดียวที่นี่
  final String backendUrl = 'http://172.20.10.4:5000/api/User/update-data';

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  // ฟังก์ชันส่งข้อมูล BLE ไปยัง ESP32
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

  // ฟังก์ชันส่งข้อมูลกลับไปอัปเดตลง C# Backend
  Future<void> saveUserDataToBackend(String key, String value) async {
    if (widget.userData == null) return;

    final url = Uri.parse(backendUrl);
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
        debugPrint("บันทึก $key ลง Database สำเร็จ");
      } else {
        debugPrint("C# API Error ($key): ${response.body}");
      }
    } catch (e) {
      debugPrint("Failed to update data on C# API: $e");
    }
  }

  // ฟังก์ชันสแกนและเชื่อมต่อ BLE
  void connectToEsp32() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาอนุญาตสิทธิ์ Bluetooth เพื่อสแกนหาอุปกรณ์')),
      );
      return;
    }

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเปิด Bluetooth บนมือถือของคุณก่อน')),
      );
      return;
    }

    await _scanSubscription?.cancel();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

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
              if (c.properties.write) {
                targetCharacteristic = c;
                if (mounted) {
                  setState(() {
                    isConnected = true;
                  });
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
  }

  // ซิงก์ข้อมูลจาก C# API เข้า ESP32 เมื่อเชื่อมต่อ BLE ครั้งแรก
  void syncUserDataToEsp32() async {
    if (widget.userData != null && isConnected) {
      if (widget.userData!['routineData'] != null) {
        await sendBleData("T:${widget.userData!['routineData']}");
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
    // 🟢 เอา sendBleData("P:$index"); ออก เพื่อไม่ให้แอปส่งคำสั่งไปรบกวนปุ่มกดเปลี่ยนหน้าบน ESP32
  }

  @override
  Widget build(BuildContext context) {
    final String currentUsername =
        widget.userData?['username'] ?? widget.userData?['userId']?.toString() ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userData != null
            ? 'Keychain ($currentUsername)'
            : 'Smart Keychain Controller'),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
              color: isConnected ? Colors.green : Colors.grey,
            ),
            onPressed: connectToEsp32,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeScreen(
            isConnected: isConnected,
            onConnectPressed: connectToEsp32,
          ),
          TodoListScreen(
            username: currentUsername,
            initialTodoList: widget.userData?['routineData'],
            onSendTodoList: (data) {
              if (data == "CLEAR" || data.isEmpty) {
                sendBleData("T:CLEAR");
                saveUserDataToBackend("routineData", "");
              } else {
                sendBleData("T:$data");
                saveUserDataToBackend("routineData", data);
              }
            },
          ),
          DisplayScreen(
            initialQrData: widget.userData?['qrData'],
            initialImageData: widget.userData?['imageData'],
            onSendDisplay: (data) {
              sendBleData(data);
              if (data.startsWith("IMG:")) {
                saveUserDataToBackend("imageData", data.substring(4));
              } else if (data.startsWith("QR:")) {
                saveUserDataToBackend("qrData", data.substring(3));
              }
            },
          ),
          NfcScreen(
            initialNfcData: widget.userData?['nfcData'],
            onSendNfc: (String nfcData) {
              sendBleData("NFC:$nfcData");
              saveUserDataToBackend("nfcData", nfcData);
            },
          ),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'หน้าแรก'),
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'ตารางเวลา'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code), label: 'ส่งรูป/QR'),
          BottomNavigationBarItem(icon: Icon(Icons.nfc), label: 'NFC'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
        ],
      ),
    );
  }
}
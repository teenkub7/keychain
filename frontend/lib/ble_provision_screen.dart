import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleProvisionScreen extends StatefulWidget {
  const BleProvisionScreen({super.key});

  @override
  State<BleProvisionScreen> createState() => _BleProvisionScreenState();
}

class _BleProvisionScreenState extends State<BleProvisionScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  // ขอสิทธิ์เปิดใช้งาน Bluetooth และ Location บนมือถือ
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // ฟังก์ชันเริ่มสแกนหาอุปกรณ์รอบตัว
  void _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    // ฟังค่าผลลัพธ์การสแกนแบบ Realtime
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    });

    // สแกนเป็นเวลา 5 วินาที
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE ESP32 Provisioning')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_isScanning ? 'กำลังสแกน...' : 'สแกนหาบอร์ด ESP32'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final data = _scanResults[index];
                final deviceName = data.device.platformName.isNotEmpty
                    ? data.device.platformName
                    : 'Unregistered Device';

                return ListTile(
                  leading: const Icon(Icons.developer_board),
                  title: Text(deviceName),
                  subtitle: Text(data.device.remoteId.str),
                  trailing: Text('${data.rssi} dBm'),
                  onTap: () {
                    // ขั้นตอนถัดไป: คลิกแล้วส่ง SSID / Password ไปยัง ESP32
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
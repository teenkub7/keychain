import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnectPressed;

  const HomeScreen({
    super.key,
    required this.isConnected,
    required this.onConnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // สถานะการเชื่อมต่อ BLE
          Card(
            color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 60,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isConnected ? 'เชื่อมต่อพวงกุญแจแล้ว' : 'ยังไม่ได้เชื่อมต่ออุปกรณ์',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: isConnected ? null : onConnectPressed,
                    icon: const Icon(Icons.search),
                    label: Text(isConnected ? 'พร้อมใช้งาน' : 'สแกนหา Smart Keychain'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // การ์ดแสดงอุณหภูมิโดยรอบ (ข้อมูลตัวอย่างจากเซนเซอร์)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Icon(Icons.thermostat, size: 40, color: Colors.orange),
                  SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('อุณหภูมิโดยรอบ', style: TextStyle(color: Colors.grey)),
                      Text('28.5 °C', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
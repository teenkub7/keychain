import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String backendUrl = "http://localhost:5000/api/Device/ESP32_01/status";
  
  bool isLoading = false;
  bool isOnline = false;
  bool isLedOn = false; // 👈 1. ตัวแปรเก็บสถานะไฟ LED
  String deviceName = "ESP32_01";
  String lastSeen = "-";
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    fetchDeviceStatus();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      fetchDeviceStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ดึงสถานะปัจจุบันจาก C# Backend
  Future<void> fetchDeviceStatus() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(Uri.parse(backendUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isOnline = data['isOnline'] ?? true;
          deviceName = data['deviceId'] ?? "ESP32_01";
          isLedOn = data['led'] ?? false; // 👈 อัปเดตสถานะ LED ตาม Backend
          lastSeen = data['lastSeen'] ?? DateTime.now().toString().substring(11, 19);
        });
      } else {
        setState(() {
          isOnline = false;
        });
      }
    } catch (e) {
      setState(() {
        isOnline = false;
      });
      debugPrint("Error fetching status: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 👈 2. ฟังก์ชันส่งคำสั่ง เปิด-ปิด LED ไป C# Backend
  Future<void> toggleLed(bool value) async {
    try {
      final response = await http.post(
        Uri.parse("http://localhost:5000/api/Device/ESP32_01/control"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"led": value}),
      );

      if (response.statusCode == 200) {
        setState(() {
          isLedOn = value;
        });
      }
    } catch (e) {
      debugPrint("Error sending command: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('IoT Device Dashboard'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchDeviceStatus,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'อุปกรณ์ในระบบ',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: isOnline ? Colors.green.shade100 : Colors.red.shade100,
                      child: Icon(
                        Icons.developer_board,
                        size: 32,
                        color: isOnline ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 20),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'อัปเดตล่าสุด: $lastSeen',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    // 👈 3. สวิตช์เปิด-ปิด LED วางต่อท้ายใน Row ตรงนี้
                    Column(
                      children: [
                        const Text("ควบคุม LED", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Switch(
                          value: isLedOn,
                          activeThumbColor: Colors.amber,
                          onChanged: isOnline ? (value) => toggleLed(value) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
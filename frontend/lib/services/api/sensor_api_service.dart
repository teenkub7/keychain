import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/sensor_data.dart';

class SensorApiService {
  static const String baseUrl = 'http://localhost:5000/api/Sensor';

  // 1. ดึงข้อมูลล่าสุด
  static Future<SensorLogItem?> getLatest({
    required String username,
    String? type,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/latest').replace(queryParameters: {
        'username': username,
        if (type != null && type.isNotEmpty) 'type': type,
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['hasData'] == true && data['data'] != null) {
          return SensorLogItem.fromJson(data['data']);
        }
      }
    } catch (e) {
      debugPrint('SensorApiService.getLatest error: $e');
    }
    return null;
  }

  // 2. ดึงประวัติข้อมูลสำหรับกราฟและรายการย้อนหลัง
  static Future<List<SensorLogItem>> getHistory({
    required String username,
    String? type,
    int limit = 25,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/history').replace(queryParameters: {
        'username': username,
        if (type != null && type.isNotEmpty) 'type': type,
        'limit': limit.toString(),
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['history'] is List) {
          return (data['history'] as List)
              .map((item) => SensorLogItem.fromJson(item))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('SensorApiService.getHistory error: $e');
    }
    return [];
  }

  // 3. บันทึกข้อมูลใหม่
  static Future<SensorLogItem?> logData({
    required String username,
    required double heartRate,
    required double spO2,
    required double temperature,
    required double humidity,
    String measurementType = 'Manual_Spot',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/log');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'heartRate': heartRate,
          'spO2': spO2,
          'temperature': temperature,
          'humidity': humidity,
          'measurementType': measurementType,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null) {
          return SensorLogItem.fromJson(data['data']);
        }
      }
    } catch (e) {
      debugPrint('SensorApiService.logData error: $e');
    }
    return null;
  }

  // 4. สั่งจำลองข้อมูล (สำหรับทดสอบ Demo และดูกราฟทันที)
  static Future<bool> simulateData({
    required String username,
    String measurementType = 'Auto_30s',
    int count = 15,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/simulate');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'measurementType': measurementType,
          'count': count,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SensorApiService.simulateData error: $e');
      return false;
    }
  }

  // 5. ล้างประวัติ (สำหรับรีเซ็ตการทดสอบ)
  static Future<bool> clearHistory({
    required String username,
    String? type,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/clear').replace(queryParameters: {
        'username': username,
        if (type != null && type.isNotEmpty) 'type': type,
      });
      final response = await http.delete(uri);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SensorApiService.clearHistory error: $e');
      return false;
    }
  }
}

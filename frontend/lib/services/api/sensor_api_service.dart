import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/sensor_data.dart';
import 'api_config.dart';

class SensorApiService {
  static String get baseUrl => ApiConfig.sensorBaseUrl;

  static void setBaseUrl(String newUrl) {
    ApiConfig.setBaseUrl(newUrl.replaceAll('/Sensor', ''));
  }

  // 1. ดึงข้อมูลล่าสุด
  static Future<SensorLogItem?> getLatest({
    required String username,
    String? type,
  }) async {
    for (int attempt = 0; attempt < ApiConfig.candidateUrls.length; attempt++) {
      try {
        final uri = Uri.parse('$baseUrl/latest').replace(queryParameters: {
          'username': username,
          if (type != null && type.isNotEmpty) 'type': type,
        });

        final response = await http.get(uri).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final bool hasData = data['hasData'] == true || data['HasData'] == true;
          final rawItem = data['data'] ?? data['Data'];
          if (hasData && rawItem != null) {
            return SensorLogItem.fromJson(rawItem);
          }
          return null;
        }
      } catch (e) {
        debugPrint('SensorApiService.getLatest attempt $attempt error ($baseUrl): $e');
        ApiConfig.switchToNextCandidate();
      }
    }
    return null;
  }

  // 2. ดึงประวัติข้อมูลสำหรับกราฟและรายการย้อนหลัง
  static Future<List<SensorLogItem>> getHistory({
    required String username,
    String? type,
    int limit = 25,
  }) async {
    for (int attempt = 0; attempt < ApiConfig.candidateUrls.length; attempt++) {
      try {
        final uri = Uri.parse('$baseUrl/history').replace(queryParameters: {
          'username': username,
          if (type != null && type.isNotEmpty) 'type': type,
          'limit': limit.toString(),
        });

        final response = await http.get(uri).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final historyList = data['history'] ?? data['History'];
          if (historyList is List) {
            return historyList
                .map((item) => SensorLogItem.fromJson(item))
                .toList();
          }
          return [];
        }
      } catch (e) {
        debugPrint('SensorApiService.getHistory attempt $attempt error ($baseUrl): $e');
        ApiConfig.switchToNextCandidate();
      }
    }
    return [];
  }

  // 3. บันทึกข้อมูลใหม่ลงฐานข้อมูล MySQL
  static Future<SensorLogItem?> logData({
    required String username,
    required double heartRate,
    required double spO2,
    required double temperature,
    required double humidity,
    String measurementType = 'Manual_Spot',
  }) async {
    for (int attempt = 0; attempt < ApiConfig.candidateUrls.length; attempt++) {
      try {
        final uri = Uri.parse('$baseUrl/log');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'Username': username,
            'heartRate': heartRate,
            'HeartRate': heartRate,
            'spO2': spO2,
            'SpO2': spO2,
            'temperature': temperature,
            'Temperature': temperature,
            'humidity': humidity,
            'Humidity': humidity,
            'measurementType': measurementType,
            'MeasurementType': measurementType,
          }),
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic>) {
            if (data['data'] != null || data['Data'] != null) {
              return SensorLogItem.fromJson(data['data'] ?? data['Data']);
            }
            return SensorLogItem.fromJson(data);
          }
        } else {
          debugPrint('❌ logData Status Error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        debugPrint('SensorApiService.logData attempt $attempt error ($baseUrl): $e');
        ApiConfig.switchToNextCandidate();
      }
    }
    return null;
  }

  // 4. สั่งจำลองข้อมูล (สำหรับทดสอบ)
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
      ).timeout(const Duration(seconds: 4));
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
      final response = await http.delete(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SensorApiService.clearHistory error: $e');
      return false;
    }
  }
}

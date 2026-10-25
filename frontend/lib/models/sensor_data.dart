import 'package:flutter/material.dart';

class SensorLogItem {
  final int id;
  final String username;
  final double heartRate;
  final double spO2;
  final double temperature;
  final double humidity;
  final String measurementType;
  final DateTime recordedAt;

  SensorLogItem({
    required this.id,
    required this.username,
    required this.heartRate,
    required this.spO2,
    required this.temperature,
    required this.humidity,
    required this.measurementType,
    required this.recordedAt,
  });

  factory SensorLogItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'].toString()).toLocal()
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return SensorLogItem(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      heartRate: (json['heartRate'] as num?)?.toDouble() ?? 0.0,
      spO2: (json['spO2'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['humidity'] as num?)?.toDouble() ?? 0.0,
      measurementType: json['measurementType'] ?? 'Manual_Spot',
      recordedAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'heartRate': heartRate,
        'spO2': spO2,
        'temperature': temperature,
        'humidity': humidity,
        'measurementType': measurementType,
        'recordedAt': recordedAt.toIso8601String(),
      };

  // Helper สำหรับสีและสถานะ Heart Rate
  String get heartRateStatus {
    if (heartRate <= 0) return 'ไม่มีข้อมูล';
    if (heartRate < 60) return 'ชีพจรช้า (Bradycardia)';
    if (heartRate <= 100) return 'ปกติ (Normal)';
    if (heartRate <= 120) return 'ค่อนข้างเร็ว (Elevated)';
    return 'ชีพจรเร็ว (Tachycardia)';
  }

  Color get heartRateColor {
    if (heartRate <= 0) return const Color(0xFF94A3B8);
    if (heartRate < 60) return const Color(0xFF3B82F6);
    if (heartRate <= 100) return const Color(0xFF10B981);
    if (heartRate <= 120) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  IconData get heartRateIcon {
    if (heartRate > 120 || (heartRate < 60 && heartRate > 0)) {
      return Icons.warning_amber_rounded;
    }
    return Icons.favorite_rounded;
  }

  // Helper สำหรับสีและสถานะ SpO2
  String get spO2Status {
    if (spO2 <= 0) return 'ไม่มีข้อมูล';
    if (spO2 >= 95) return 'ออกซิเจนสมบูรณ์ (ปกติ)';
    if (spO2 >= 90) return 'ออกซิเจนต่ำเล็กน้อย (เฝ้าระวัง)';
    return 'ออกซิเจนต่ำผิดปกติ (อันตราย)';
  }

  Color get spO2Color {
    if (spO2 <= 0) return const Color(0xFF94A3B8);
    if (spO2 >= 95) return const Color(0xFF06B6D4);
    if (spO2 >= 90) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  // Helper สำหรับอุณหภูมิ
  String get tempStatus {
    if (temperature < 25) return 'เย็นสบาย';
    if (temperature <= 30) return 'ปกติ เหมาะสม';
    if (temperature <= 34) return 'ค่อนข้างร้อน';
    return 'ร้อนจัด';
  }

  Color get tempColor {
    if (temperature < 25) return const Color(0xFF3B82F6);
    if (temperature <= 30) return const Color(0xFF10B981);
    if (temperature <= 34) return const Color(0xFFFF6B00);
    return const Color(0xFFEF4444);
  }

  // Helper แสดงเวลาเป็นสตริงอ่านง่าย
  String get formattedTime {
    final hour = recordedAt.hour.toString().padLeft(2, '0');
    final minute = recordedAt.minute.toString().padLeft(2, '0');
    final second = recordedAt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second น.';
  }

  String get formattedDate {
    return '${recordedAt.day}/${recordedAt.month}/${recordedAt.year}';
  }
}

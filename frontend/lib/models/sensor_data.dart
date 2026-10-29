import 'package:flutter/material.dart';

/// ระดับความเสี่ยงสัญญาณชีพทางการแพทย์ (Priority-based Health Risk Level)
enum HealthRiskLevel {
  noData,
  normal,
  warning,
  abnormal,
}

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
      // ตรวจสอบทั้ง camelCase และ PascalCase สำหรับเวลา
      final dateStr = json['recordedAt'] ?? json['RecordedAt'];
      parsedDate = dateStr != null
          ? DateTime.parse(dateStr.toString()).toLocal()
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    // ดึงค่าโดยรองรับทั้ง camelCase และ PascalCase จาก C# Backend
    final num? rawHr = (json['heartRate'] ?? json['HeartRate']) as num?;
    final num? rawSpo2 = (json['spO2'] ?? json['SpO2'] ?? json['spo2']) as num?;
    final num? rawTemp = (json['temperature'] ?? json['Temperature']) as num?;
    final num? rawHum = (json['humidity'] ?? json['Humidity']) as num?;

    return SensorLogItem(
      id: json['id'] ?? json['Id'] ?? 0,
      username: json['username'] ?? json['Username'] ?? '',
      heartRate: rawHr?.toDouble() ?? 0.0,
      spO2: rawSpo2?.toDouble() ?? 0.0,
      temperature: rawTemp?.toDouble() ?? 0.0,
      humidity: rawHum?.toDouble() ?? 0.0,
      measurementType: json['measurementType'] ?? json['MeasurementType'] ?? 'Manual_Spot',
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

  /// ตรวจสอบความถูกต้องของข้อมูล (Sanity / Physical Bounds Check)
  bool get hasValidHealthData =>
      heartRate > 0 &&
      heartRate >= 20 &&
      heartRate <= 220 &&
      spO2 > 0 &&
      spO2 <= 100;

  /// ระบบประเมินลำดับความรุนแรง (Priority-based Evaluation Logic)
  HealthRiskLevel get healthRiskLevel {
    // 0. ดักจับค่าว่าง / วัดไม่ติด / หลุดกรอบกายภาพ (No Data)
    if (!hasValidHealthData) {
      return HealthRiskLevel.noData;
    }

    // Priority 1 - High Risk (ผิดปกติ):
    // ตรวจสอบว่า (Heart Rate < 50 หรือ Heart Rate > 120) หรือ (SpO2 < 90)
    // เข้าเงื่อนไขข้อใดข้อหนึ่งแม้แต่ตัวเดียว -> ตัดสินเป็น "ผิดปกติ" ทันที
    if (heartRate < 50 || heartRate > 120 || spO2 < 90) {
      return HealthRiskLevel.abnormal;
    }

    // Priority 2 - Medium Risk (เฝ้าระวัง):
    // ตรวจสอบว่า (Heart Rate อยู่ในช่วง 50–59 หรือ 101–120) หรือ (SpO2 อยู่ในช่วง 90–94)
    // เข้าเงื่อนไขข้อใดข้อหนึ่ง -> ตัดสินเป็น "เฝ้าระวัง"
    if ((heartRate >= 50 && heartRate <= 59) ||
        (heartRate >= 101 && heartRate <= 120) ||
        (spO2 >= 90 && spO2 <= 94)) {
      return HealthRiskLevel.warning;
    }

    // Priority 3 - Safe (ปกติ):
    // จะได้สถานะนี้เมื่อ Heart Rate อยู่ในช่วง 60–100 และ SpO2 อยู่ในช่วง 95–100 พร้อมกันทั้งคู่เท่านั้น
    if (heartRate >= 60 && heartRate <= 100 && spO2 >= 95 && spO2 <= 100) {
      return HealthRiskLevel.normal;
    }

    return HealthRiskLevel.warning;
  }

  /// ป้ายสถานะสุขภาพรวม
  String get healthStatusLabel {
    switch (healthRiskLevel) {
      case HealthRiskLevel.normal:
        return 'ปกติ';
      case HealthRiskLevel.warning:
        return 'เฝ้าระวัง';
      case HealthRiskLevel.abnormal:
        return 'ผิดปกติ';
      case HealthRiskLevel.noData:
        return 'ยังไม่มีข้อมูล';
    }
  }

  /// อิโมจิแสดงอารมณ์สุขภาพตามเกณฑ์
  String get healthEmoji {
    switch (healthRiskLevel) {
      case HealthRiskLevel.normal:
        return '😊';
      case HealthRiskLevel.warning:
        return '😐';
      case HealthRiskLevel.abnormal:
        return '😟';
      case HealthRiskLevel.noData:
        return '❓';
    }
  }

  /// สีประจำระดับสุขภาพ
  Color get healthStatusColor {
    switch (healthRiskLevel) {
      case HealthRiskLevel.normal:
        return const Color(0xFF10B981); // สีเขียว #10B981
      case HealthRiskLevel.warning:
        return const Color(0xFFF59E0B); // สีส้ม/เหลือง #F59E0B
      case HealthRiskLevel.abnormal:
        return const Color(0xFFEF4444); // สีแดง #EF4444
      case HealthRiskLevel.noData:
        return const Color(0xFF94A3B8); // สีเทา
    }
  }

  /// ความหมายทางการแพทย์ของสถานะ
  String get healthMeaning {
    switch (healthRiskLevel) {
      case HealthRiskLevel.normal:
        return 'การไหลเวียนโลหิตและระบบแลกเปลี่ยนก๊าซทำงานสมบูรณ์';
      case HealthRiskLevel.warning:
        return 'ร่างกายอาจมีภาวะตึงเครียด เหนื่อยล้า เพิ่งออกแรงมา หรือขยับนิ้วขณะวัด';
      case HealthRiskLevel.abnormal:
        return 'หัวใจเต้นผิดจังหวะชัดเจน หรือมีความเสี่ยงภาวะพร่องออกซิเจน';
      case HealthRiskLevel.noData:
        return 'ยังไม่พบข้อมูลสัญญาณชีพที่ถูกต้องจากเซนเซอร์';
    }
  }

  /// คำแนะนำปฏิบัติตัว (Actionable Advice)
  String get healthAdvice {
    switch (healthRiskLevel) {
      case HealthRiskLevel.normal:
        return 'สัญญาณชีพอยู่ในเกณฑ์ปกติ ร่างกายพักผ่อนเพียงพอ';
      case HealthRiskLevel.warning:
        return 'ตรวจพบค่าเริ่มเบี่ยงเบนจากเกณฑ์ แนะนำให้นั่งพักเฉยๆ ไม่พูดคุย หายใจเข้า-ออกยาวๆ 3-5 นาที แล้วลองวัดซ้ำอีกครั้ง';
      case HealthRiskLevel.abnormal:
        return 'ค่าสัญญาณชีพอยู่นอกเกณฑ์มาตรฐาน หากลองวัดซ้ำแล้วยังได้ค่าเดิม หรือมีอาการหน้ามืด แน่นหน้าอก หายใจไม่อิ่ม ควรปรึกษาแพทย์หรือผู้เชี่ยวชาญทันที';
      case HealthRiskLevel.noData:
        return 'กรุณาวางนิ้วบนเซนเซอร์และแตะปุ่มเพื่อเริ่มตรวจวัดสัญญาณชีพ';
    }
  }

  // ========================================================
  // พารามิเตอร์เดี่ยว: Heart Rate (ชีพจรขณะพัก)
  // ========================================================
  String get heartRateStatus {
    if (heartRate <= 0 || heartRate < 20 || heartRate > 220) return 'ไม่มีข้อมูล';
    if (heartRate < 50) return 'ชีพจรช้าวิกฤต (<50 bpm)';
    if (heartRate <= 59) return 'ชีพจรช้ากว่าปกติ (50–59 bpm)';
    if (heartRate <= 100) return 'จังหวะหัวใจปกติ (60–100 bpm)';
    if (heartRate <= 120) return 'ชีพจรเร็วกว่าปกติ (101–120 bpm)';
    return 'ชีพจรเร็ววิกฤต (>120 bpm)';
  }

  Color get heartRateColor {
    if (heartRate <= 0 || heartRate < 20 || heartRate > 220) return const Color(0xFF94A3B8);
    if (heartRate < 50) return const Color(0xFFEF4444); // แดง
    if (heartRate <= 59) return const Color(0xFFF59E0B); // ส้ม/เหลือง
    if (heartRate <= 100) return const Color(0xFF10B981); // เขียว
    if (heartRate <= 120) return const Color(0xFFF59E0B); // ส้ม/เหลือง
    return const Color(0xFFEF4444); // แดง
  }

  IconData get heartRateIcon {
    if (heartRate <= 0 || heartRate < 20 || heartRate > 220) {
      return Icons.favorite_border_rounded;
    }
    if (heartRate < 50 || heartRate > 120) {
      return Icons.warning_rounded;
    }
    if (heartRate <= 59 || heartRate > 100) {
      return Icons.warning_amber_rounded;
    }
    return Icons.favorite_rounded;
  }

  // ========================================================
  // พารามิเตอร์เดี่ยว: SpO2 (ระดับออกซิเจนในเลือด)
  // ========================================================
  String get spO2Status {
    if (spO2 <= 0 || spO2 > 100) return 'ไม่มีข้อมูล';
    if (spO2 >= 95) return 'ระดับออกซิเจนสมบูรณ์ (95–100%)';
    if (spO2 >= 90) return 'พร่องออกซิเจนระดับเริ่มต้น (90–94%)';
    return 'ออกซิเจนต่ำวิกฤต (<90%)';
  }

  Color get spO2Color {
    if (spO2 <= 0 || spO2 > 100) return const Color(0xFF94A3B8);
    if (spO2 >= 95) return const Color(0xFF10B981); // เขียว
    if (spO2 >= 90) return const Color(0xFFF59E0B); // ส้ม/เหลือง
    return const Color(0xFFEF4444); // แดง
  }

  IconData get spO2Icon {
    if (spO2 <= 0 || spO2 > 100) return Icons.water_drop_outlined;
    if (spO2 < 90) return Icons.warning_rounded;
    if (spO2 < 95) return Icons.warning_amber_rounded;
    return Icons.water_drop_rounded;
  }

  // ========================================================
  // สภาพแวดล้อม: อุณหภูมิและความชื้น
  // ========================================================
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

/// การวิเคราะห์แนวโน้มสุขภาพจากข้อมูลประวัติย้อนหลัง 10 ครั้งล่าสุดในฐานข้อมูล
class RecentHealthAnalysis {
  final int count; // จำนวนครั้งที่นำมาวิเคราะห์ (สูงสุด 10)
  final double avgHeartRate;
  final double avgSpO2;
  final int normalCount;
  final int warningCount;
  final int abnormalCount;
  final HealthRiskLevel overallRiskLevel;
  final String emoji;
  final String title;
  final String statusLabel;
  final String summary;
  final Color statusColor;

  RecentHealthAnalysis({
    required this.count,
    required this.avgHeartRate,
    required this.avgSpO2,
    required this.normalCount,
    required this.warningCount,
    required this.abnormalCount,
    required this.overallRiskLevel,
    required this.emoji,
    required this.title,
    required this.statusLabel,
    required this.summary,
    required this.statusColor,
  });

  bool get hasData => count > 0;

  factory RecentHealthAnalysis.fromHistory(List<SensorLogItem> history, {int limit = 5}) {
    // กรองเฉพาะค่าที่มีข้อมูลสัญญาณชีพจริง (HR > 0 และ SpO2 > 0)
    // เรียงตามเวลาล่าสุดก่อน (descending) แล้วหยิบ limit รายการแรก (ค่าเริ่มต้น 5 จุดข้อมูล)
    final sortedDesc = List<SensorLogItem>.from(history)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    final validItems = sortedDesc
        .where((item) => item.hasValidHealthData)
        .take(limit)
        .toList();

    if (validItems.isEmpty) {
      return RecentHealthAnalysis(
        count: 0,
        avgHeartRate: 0,
        avgSpO2: 0,
        normalCount: 0,
        warningCount: 0,
        abnormalCount: 0,
        overallRiskLevel: HealthRiskLevel.noData,
        emoji: '📋',
        title: 'รอข้อมูลประวัติการวัด',
        statusLabel: 'ยังไม่มีประวัติ',
        summary: 'ยังไม่มีประวัติการวัด บันทึกข้อมูลเพื่อเริ่มวิเคราะห์แนวโน้มสุขภาพ',
        statusColor: const Color(0xFF94A3B8),
      );
    }

    final double sumHr = validItems.fold(0.0, (acc, item) => acc + item.heartRate);
    final double sumSpo2 = validItems.fold(0.0, (acc, item) => acc + item.spO2);
    final double avgHr = sumHr / validItems.length;
    final double avgSpo2 = sumSpo2 / validItems.length;

    int normal = 0;
    int warning = 0;
    int abnormal = 0;

    for (final item in validItems) {
      switch (item.healthRiskLevel) {
        case HealthRiskLevel.normal:
          normal++;
          break;
        case HealthRiskLevel.warning:
          warning++;
          break;
        case HealthRiskLevel.abnormal:
          abnormal++;
          break;
        case HealthRiskLevel.noData:
          break;
      }
    }

    HealthRiskLevel risk;
    String emoji;
    String title;
    String statusLabel;
    String summary;
    Color color;

    final n = validItems.length;
    if (abnormal > 0 || avgHr < 50 || avgHr > 120 || avgSpo2 < 90) {
      risk = HealthRiskLevel.abnormal;
      emoji = '😟';
      statusLabel = 'มีความเสี่ยง';
      title = 'พบค่าผิดปกติ $abnormal/$n ครั้ง';
      summary = 'สัญญาณชีพเริ่มมีความเสี่ยง แนะนำเฝ้าระวังและพักผ่อน';
      color = const Color(0xFFEF4444);
    } else if (warning > 0 || avgHr < 60 || avgHr > 100 || avgSpo2 < 95) {
      risk = HealthRiskLevel.warning;
      emoji = '😐';
      statusLabel = 'ควรเฝ้าระวัง';
      title = 'พบค่าเบี่ยงเบน $warning/$n ครั้ง';
      summary = 'สัญญาณชีพเริ่มเบี่ยงเบนจากเกณฑ์ แนะนำผ่อนคลายและวัดซ้ำ';
      color = const Color(0xFFF59E0B);
    } else {
      risk = HealthRiskLevel.normal;
      emoji = '😊';
      statusLabel = 'ปกติและคงที่';
      title = 'สุขภาพสม่ำเสมอ ($normal/$n ครั้ง)';
      summary = 'สัญญาณชีพอยู่ในเกณฑ์มาตรฐานสมบูรณ์ต่อเนื่อง';
      color = const Color(0xFF10B981);
    }

    return RecentHealthAnalysis(
      count: n,
      avgHeartRate: avgHr,
      avgSpO2: avgSpo2,
      normalCount: normal,
      warningCount: warning,
      abnormalCount: abnormal,
      overallRiskLevel: risk,
      emoji: emoji,
      title: title,
      statusLabel: statusLabel,
      summary: summary,
      statusColor: color,
    );
  }
}

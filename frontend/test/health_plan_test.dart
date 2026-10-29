import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/sensor_data.dart';

void main() {
  group('Health Monitoring Evaluation Logic Tests (Standard Plan)', () {
    SensorLogItem createItem({required double hr, required double spo2}) {
      return SensorLogItem(
        id: 1,
        username: 'test_user',
        heartRate: hr,
        spO2: spo2,
        temperature: 28.0,
        humidity: 60.0,
        measurementType: 'Manual_Spot',
        recordedAt: DateTime.now(),
      );
    }

    test('ดักจับค่าว่าง / วัดไม่ติด (No Data)', () {
      final itemZero = createItem(hr: 0, spo2: 0);
      expect(itemZero.healthRiskLevel, HealthRiskLevel.noData);
      expect(itemZero.healthStatusLabel, 'ยังไม่มีข้อมูล');
      expect(itemZero.healthEmoji, '❓');
      expect(itemZero.healthStatusColor, const Color(0xFF94A3B8));

      final itemNegative = createItem(hr: -5, spo2: 98);
      expect(itemNegative.healthRiskLevel, HealthRiskLevel.noData);

      final itemSpO2Zero = createItem(hr: 75, spo2: 0);
      expect(itemSpO2Zero.healthRiskLevel, HealthRiskLevel.noData);

      // Out of bounds / sensor glitch
      final itemGlitchSpO2 = createItem(hr: 75, spo2: 105);
      expect(itemGlitchSpO2.healthRiskLevel, HealthRiskLevel.noData);

      final itemGlitchHR = createItem(hr: 250, spo2: 98);
      expect(itemGlitchHR.healthRiskLevel, HealthRiskLevel.noData);
    });

    test('Priority 1 - High Risk (ผิดปกติ): ตรวจจับความผิดปกติก่อนเป็นอันดับแรก', () {
      // 1. SpO2 < 90 แม้ Heart Rate ปกติ -> ผิดปกติ
      final itemLowSpO2 = createItem(hr: 75, spo2: 88);
      expect(itemLowSpO2.healthRiskLevel, HealthRiskLevel.abnormal);
      expect(itemLowSpO2.healthStatusLabel, 'ผิดปกติ');
      expect(itemLowSpO2.healthEmoji, '😟');
      expect(itemLowSpO2.healthStatusColor, const Color(0xFFEF4444));

      // 2. Heart Rate < 50 bpm (Bradycardia รุนแรง) แม้ SpO2 ปกติ -> ผิดปกติ
      final itemLowHR = createItem(hr: 45, spo2: 98);
      expect(itemLowHR.healthRiskLevel, HealthRiskLevel.abnormal);
      expect(itemLowHR.healthStatusLabel, 'ผิดปกติ');

      // 3. Heart Rate > 120 bpm (Tachycardia สูงชัดเจน) แม้ SpO2 ปกติ -> ผิดปกติ
      final itemHighHR = createItem(hr: 130, spo2: 97);
      expect(itemHighHR.healthRiskLevel, HealthRiskLevel.abnormal);
      expect(itemHighHR.healthStatusLabel, 'ผิดปกติ');

      // 4. ผิดปกติทั้งคู่ -> ผิดปกติ
      final itemBothAbnormal = createItem(hr: 135, spo2: 85);
      expect(itemBothAbnormal.healthRiskLevel, HealthRiskLevel.abnormal);
      expect(itemBothAbnormal.healthStatusLabel, 'ผิดปกติ');
    });

    test('Priority 2 - Medium Risk (เฝ้าระวัง): ตรวจจับสภาวะเฝ้าระวัง', () {
      // 1. Heart Rate ในช่วง 50–59 bpm (ช้ากว่าปกติเล็กน้อย) + SpO2 ปกติ -> เฝ้าระวัง
      final itemWarnLowHR = createItem(hr: 55, spo2: 98);
      expect(itemWarnLowHR.healthRiskLevel, HealthRiskLevel.warning);
      expect(itemWarnLowHR.healthStatusLabel, 'เฝ้าระวัง');
      expect(itemWarnLowHR.healthEmoji, '😐');
      expect(itemWarnLowHR.healthStatusColor, const Color(0xFFF59E0B));

      // 2. Heart Rate ในช่วง 101–120 bpm (เร็วกว่าปกติเล็กน้อย) + SpO2 ปกติ -> เฝ้าระวัง
      final itemWarnHighHR = createItem(hr: 110, spo2: 97);
      expect(itemWarnHighHR.healthRiskLevel, HealthRiskLevel.warning);
      expect(itemWarnHighHR.healthStatusLabel, 'เฝ้าระวัง');

      // 3. SpO2 ในช่วง 90–94% (Mild Hypoxemia) + Heart Rate ปกติ -> เฝ้าระวัง
      final itemWarnSpO2 = createItem(hr: 75, spo2: 93);
      expect(itemWarnSpO2.healthRiskLevel, HealthRiskLevel.warning);
      expect(itemWarnSpO2.healthStatusLabel, 'เฝ้าระวัง');

      // 4. ทั้ง HR และ SpO2 อยู่ในเกณฑ์เฝ้าระวัง -> เฝ้าระวัง
      final itemBothWarning = createItem(hr: 108, spo2: 92);
      expect(itemBothWarning.healthRiskLevel, HealthRiskLevel.warning);
    });

    test('Priority 3 - Safe (ปกติ): Heart Rate 60–100 และ SpO2 95–100 พร้อมกัน', () {
      final itemNormal = createItem(hr: 72, spo2: 98);
      expect(itemNormal.healthRiskLevel, HealthRiskLevel.normal);
      expect(itemNormal.healthStatusLabel, 'ปกติ');
      expect(itemNormal.healthEmoji, '😊');
      expect(itemNormal.healthStatusColor, const Color(0xFF10B981));

      // ขอบเขตล่างของปกติ: HR 60, SpO2 95
      final itemLowerEdge = createItem(hr: 60, spo2: 95);
      expect(itemLowerEdge.healthRiskLevel, HealthRiskLevel.normal);

      // ขอบเขตบนของปกติ: HR 100, SpO2 100
      final itemUpperEdge = createItem(hr: 100, spo2: 100);
      expect(itemUpperEdge.healthRiskLevel, HealthRiskLevel.normal);
    });

    test('คำแนะนำทางการแพทย์และข้อความความหมายครบถ้วนตามเกณฑ์', () {
      final normal = createItem(hr: 75, spo2: 98);
      expect(normal.healthAdvice, contains('สัญญาณชีพอยู่ในเกณฑ์ปกติ'));
      expect(normal.healthMeaning, contains('การไหลเวียนโลหิตและระบบแลกเปลี่ยนก๊าซทำงานสมบูรณ์'));

      final warning = createItem(hr: 110, spo2: 97);
      expect(warning.healthAdvice, contains('นั่งพักเฉยๆ ไม่พูดคุย หายใจเข้า-ออกยาวๆ 3-5 นาที'));
      expect(warning.healthMeaning, contains('ร่างกายอาจมีภาวะตึงเครียด'));

      final abnormal = createItem(hr: 130, spo2: 88);
      expect(abnormal.healthAdvice, contains('หากลองวัดซ้ำแล้วยังได้ค่าเดิม หรือมีอาการหน้ามืด แน่นหน้าอก'));
      expect(abnormal.healthMeaning, contains('หัวใจเต้นผิดจังหวะชัดเจน หรือมีความเสี่ยงภาวะพร่องออกซิเจน'));
    });

    test('RecentHealthAnalysis: วิเคราะห์ประวัติย้อนหลัง 5 ครั้งล่าสุด (ส่วนที่ 2)', () {
      // 1. กรณีไม่มีข้อมูล
      final emptyAnalysis = RecentHealthAnalysis.fromHistory([]);
      expect(emptyAnalysis.hasData, false);
      expect(emptyAnalysis.emoji, '📋');
      expect(emptyAnalysis.count, 0);

      // 2. กรณีข้อมูลปกติ 5 ครั้ง (default limit = 5)
      final normalList = List.generate(
        12,
        (i) => SensorLogItem(
          id: i + 1,
          username: 'user1',
          heartRate: 70.0 + (i % 5),
          spO2: 98.0,
          temperature: 28.0,
          humidity: 55.0,
          measurementType: 'Manual_Spot',
          recordedAt: DateTime.now().subtract(Duration(minutes: i * 5)),
        ),
      );

      final normalAnalysis = RecentHealthAnalysis.fromHistory(normalList);
      expect(normalAnalysis.count, 5);
      expect(normalAnalysis.overallRiskLevel, HealthRiskLevel.normal);
      expect(normalAnalysis.emoji, '😊');
      expect(normalAnalysis.statusLabel, 'ปกติและคงที่');
      expect(normalAnalysis.normalCount, 5);
      expect(normalAnalysis.abnormalCount, 0);

      // 3. กรณีมีค่าผิดปกติ 1 ครั้งใน 5 ครั้งล่าสุด -> ตัดสินเป็น abnormal
      final mixedList = List<SensorLogItem>.from(normalList.take(4));
      mixedList.add(
        SensorLogItem(
          id: 99,
          username: 'user1',
          heartRate: 135.0, // ผิดปกติ
          spO2: 88.0,       // ผิดปกติ
          temperature: 28.0,
          humidity: 55.0,
          measurementType: 'Manual_Spot',
          recordedAt: DateTime.now(),
        ),
      );

      final mixedAnalysis = RecentHealthAnalysis.fromHistory(mixedList);
      expect(mixedAnalysis.count, 5);
      expect(mixedAnalysis.overallRiskLevel, HealthRiskLevel.abnormal);
      expect(mixedAnalysis.emoji, '😟');
      expect(mixedAnalysis.statusLabel, 'มีความเสี่ยง');
      expect(mixedAnalysis.abnormalCount, 1);
    });
  });
}

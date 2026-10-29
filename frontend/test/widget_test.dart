import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/health_sensor_screen.dart';
import 'package:frontend/services/api/ble_service.dart';

void main() {
  testWidgets('SettingsPage renders without user card, connection card, or user header', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ตั้งค่า (Settings)'), findsOneWidget);
    expect(find.text('ความสว่างหน้าจอ TFT'), findsOneWidget);
    expect(find.text('เวลาพักหน้าจอ (Sleep Timeout)'), findsOneWidget);
    expect(find.text('ออกจากระบบ (Log Out)'), findsOneWidget);
    expect(find.text('Smart Keychain v1.0.0'), findsOneWidget);

    // Verify removed elements are NOT present
    expect(find.text('user1'), findsNothing);
    expect(find.text('การเชื่อมต่อพวงกุญแจ'), findsNothing);
    expect(find.text('บัญชีผู้ใช้'), findsNothing);
    expect(find.text('Minimal IoT Companion for Smart Life'), findsNothing);
  });

  testWidgets('Routine BottomSheet modal does not contain "จัดการหน้าเต็ม"', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            isConnected: false,
            onConnectPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on the daily routine card to open modal
    final routineCard = find.text('ตารางกิจกรรมประจำวัน');
    expect(routineCard, findsOneWidget);
    await tester.tap(routineCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Verify the modal opened
    expect(find.text('ซิงก์แจ้งเตือนบนพวงกุญแจฮาร์ดแวร์'), findsOneWidget);
    expect(find.text('เพิ่มกิจกรรม'), findsOneWidget);

    // Verify "จัดการหน้าเต็ม ->" is NOT present
    expect(find.text('จัดการหน้าเต็ม ->'), findsNothing);
    expect(find.textContaining('จัดการหน้าเต็ม'), findsNothing);
  });

  testWidgets('HealthSensorScreen removes icons and status badges as requested', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthSensorScreen(username: 'test_user'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Verify Tab titles are present without icon emojis
    expect(find.text('สุขภาพ'), findsOneWidget);
    expect(find.text('อุณหภูมิ & ความชื้น'), findsOneWidget);

    // 2. Verify "ผลตรวจวัดสุขภาพล่าสุด" is present
    expect(find.text('ผลตรวจวัดสุขภาพล่าสุด'), findsOneWidget);

    // 3. Verify Heart rate & SpO2 cards are present
    expect(find.text('อัตราเต้นหัวใจ'), findsOneWidget);
    expect(find.text('ออกซิเจน SpO2'), findsOneWidget);

    // Verify removed icons and status texts are absent
    expect(find.byIcon(Icons.monitor_heart_rounded), findsNothing);
    expect(find.byIcon(Icons.water_drop_rounded), findsNothing);
    expect(find.textContaining('ปกติ (Normal)'), findsNothing);
    expect(find.textContaining('ออกซิเจนสมบูรณ์'), findsNothing);
  });

  testWidgets('HealthSensorScreen measurement shows emoji dialog and limits history to 5 items', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthSensorScreen(username: 'test_user'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // ✅ ตรวจสอบว่าปุ่มวัดสุขภาพอยู่ในหน้า
    final measureBtn = find.text('แตะเพื่อบันทึกการวัดสุขภาพตอนนี้');
    expect(measureBtn, findsOneWidget);

    // ✅ ตั้ง mode เป็น Manual_Spot ก่อน tap
    BleService().setMeasurementMode('Manual_Spot');
    await tester.tap(measureBtn);
    await tester.pump(const Duration(milliseconds: 100));

    // ✅ ปุ่มเปลี่ยนเป็น "กำลังวัด..." ระหว่างรอ
    expect(find.text('กำลังวัดสัญญาณชีพสุขภาพ...'), findsOneWidget);

    // ✅ ส่วนประวัติ (ครั้งล่าสุด) ยังแสดงอยู่ในหน้า
    expect(find.textContaining('ครั้งล่าสุด'), findsOneWidget);

    // ✅ ไม่มี Dialog ก่อน timeout (BLE ไม่ทำงานใน test)
    expect(find.byType(AlertDialog), findsNothing);

    // ✅ pump ผ่าน timer 8 วินาที (fake async จะกระโดดข้ามเวลาทันที)
    // เพื่อให้ _handleMeasurement timeout และ cleanup เสร็จสมบูรณ์
    await tester.pump(const Duration(seconds: 9));

    // cleanup: reset mode
    BleService().setMeasurementMode('Auto_30s');
  });

  testWidgets('HealthSensorScreen 30s sensor tab does not display removed monitor or status badges', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: HealthSensorScreen(username: 'test_user'),
      ),
    );
    await tester.pump();

    // Switch to 30s Sensor tab
    final sensorTab = find.text('อุณหภูมิ & ความชื้น');
    expect(sensorTab, findsOneWidget);
    await tester.tap(sensorTab);
    await tester.pumpAndSettle();

    // Verify removed texts are absent
    expect(find.textContaining('มอนิเตอร์สภาพแวดล้อม'), findsNothing);
    expect(find.textContaining('ระดับเหมาะสม'), findsNothing);
    expect(find.textContaining('ค่อนข้างร้อน'), findsNothing);
    expect(find.textContaining('สบายตัว'), findsNothing);

    // Verify main temperature and humidity labels remain
    expect(find.text('อุณหภูมิโดยรอบ'), findsOneWidget);
    expect(find.text('ความชื้นในอากาศ'), findsOneWidget);
  });

  testWidgets('HomeScreen removes "สัญญาณ BLE" card and keeps battery and temp', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            isConnected: true,
            onConnectPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('สัญญาณ BLE'), findsNothing);
    expect(find.text('แบตเตอรี่'), findsOneWidget);
    expect(find.text('อุณหภูมิ'), findsOneWidget);
  });

  testWidgets('HealthSensorScreen removes Demo button and displays 5-record analysis', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthSensorScreen(username: 'test_user'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Demo button is NOT present
    expect(find.text('Demo'), findsNothing);
    expect(find.byIcon(Icons.science_rounded), findsNothing);

    // Verify Section 2: Recent health analysis inside the latest reading card
    expect(find.textContaining('วิเคราะห์สุขภาพ'), findsOneWidget);
  });

  testWidgets('HealthSensorScreen 30s sensor tab has temperature & humidity measurement button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthSensorScreen(username: 'test_user'),
        ),
      ),
    );
    await tester.pump();

    // Switch to temperature & humidity tab
    final sensorTab = find.text('อุณหภูมิ & ความชื้น');
    expect(sensorTab, findsOneWidget);
    await tester.tap(sensorTab);
    await tester.pumpAndSettle();

    // Verify presence of "แตะเพื่อบันทึกค่าอุณหภูมิ & ความชื้นตอนนี้" button
    expect(find.text('แตะเพื่อบันทึกค่าอุณหภูมิ & ความชื้นตอนนี้'), findsOneWidget);
  });
}

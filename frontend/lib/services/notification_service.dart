import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // สำหรับป้องกันการแจ้งเตือน Sensor ถี่เกินไป (Cooldown)
  DateTime? _lastSensorAlertTime;
  DateTime? _lastTempHumAlertTime;

  /// กำหนดค่าเริ่มต้นให้กับ Notification
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Initialise Timezone สำหรับประเทศไทย (Asia/Bangkok: UTC+7)
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
      } catch (e) {
        debugPrint('>>> Timezone location fallback: $e');
      }

      // 2. ตั้งค่าสำหรับ Android และ iOS
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('>>> 🔔 User tapped notification payload: ${response.payload}');
        },
      );

      // 3. ขอ Permission สำหรับ Android 13+ (API 33+) และ Exact Alarm (Android 14+)
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        try {
          await androidImplementation.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('⚠️ requestExactAlarmsPermission note: $e');
        }
      }

      _isInitialized = true;
      debugPrint('>>> 🔔 NotificationService initialized successfully!');
    } catch (e) {
      debugPrint('❌ NotificationService initialize error: $e');
    }
  }

  /// แสดงการแจ้งเตือนทั่วไปทันที
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'keychain_general_channel',
      'ทั่วไป (General Alerts)',
      channelDescription: 'การแจ้งเตือนทั่วไปของ Smart Keychain',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: payload,
    );
  }

  /// 1. 🚨 Anti-Lost Alert: แจ้งเตือนเมื่อหลุดการเชื่อมต่อกับพวงกุญแจ
  Future<void> showAntiLostAlert({String deviceName = 'Smart Keychain'}) async {
    const AndroidNotificationDetails antiLostDetails =
        AndroidNotificationDetails(
      'keychain_lost_channel',
      'แจ้งเตือนกุญแจสูญหาย (Anti-Lost)',
      channelDescription: 'แจ้งเตือนเมื่อหลุดระยะการเชื่อมต่อบลูทูธกับพวงกุญแจ',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: antiLostDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _notificationsPlugin.show(
      id: 1001, // ID เฉพาะสำหรับ Anti-lost
      title: '⚠️ คำเตือน: หลุดการเชื่อมต่อพวงกุญแจ!',
      body: 'พวงกุญแจ ($deviceName) อยู่ห่างเกินระยะ หรือสัญญาณขาดหาย กรุณาตรวจสอบว่าลืมไว้หรือไม่',
      notificationDetails: platformDetails,
      payload: 'ANTI_LOST_ALERT',
    );
  }

  /// 2. ❤️ Health/Sensor Alert: แจ้งเตือนค่าสุขภาพผิดปกติ
  Future<void> checkAndAlertSensorData({
    double? heartRate,
    double? spO2,
    double? temperature,
  }) async {
    final now = DateTime.now();
    if (_lastSensorAlertTime != null &&
        now.difference(_lastSensorAlertTime!).inSeconds < 60) {
      return;
    }

    String? warningTitle;
    String? warningBody;

    if (spO2 != null && spO2 > 0 && spO2 < 95.0) {
      warningTitle = '🫁 ระดับออกซิเจนในเลือดต่ำกว่าเกณฑ์!';
      warningBody = 'ค่า SpO2 ปัจจุบันอยู่ที่ ${spO2.toStringAsFixed(1)}% (เกณฑ์ปกติควร >= 95%)';
    } else if (heartRate != null && heartRate > 0) {
      if (heartRate > 120.0) {
        warningTitle = '💓 อัตราการเต้นของหัวใจสูงผิดปกติ!';
        warningBody = 'ตรวจพบอัตราการเต้นของหัวใจ ${heartRate.toStringAsFixed(0)} bpm กรุณาพักผ่อนหรือตรวจสอบอาการ';
      } else if (heartRate < 50.0) {
        warningTitle = '💓 อัตราการเต้นของหัวใจต่ำผิดปกติ!';
        warningBody = 'ตรวจพบอัตราการเต้นของหัวใจ ${heartRate.toStringAsFixed(0)} bpm กรุณาตรวจสอบอาการ';
      }
    } else if (temperature != null && temperature > 37.8) {
      warningTitle = '🌡️ อุณหภูมิร่างกายสูงผิดปกติ (อาจมีไข้)!';
      warningBody = 'ตรวจพบอุณหภูมิ ${temperature.toStringAsFixed(1)} °C';
    }

    if (warningTitle != null && warningBody != null) {
      _lastSensorAlertTime = now;

      const AndroidNotificationDetails healthDetails =
          AndroidNotificationDetails(
        'keychain_health_channel',
        'แจ้งเตือนสุขภาพ (Health Alert)',
        channelDescription: 'แจ้งเตือนเมื่อค่าเซนเซอร์สุขภาพตรวจพบความผิดปกติ',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: healthDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        id: 1002,
        title: warningTitle,
        body: warningBody,
        notificationDetails: platformDetails,
        payload: 'HEALTH_ALERT',
      );
    }
  }

  /// 🌡️ แจ้งเตือนเมื่อวัดอุณหภูมิและความชื้นจาก Hardware
  Future<void> showTempHumidityAlert({
    required double temperature,
    required double humidity,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        _lastTempHumAlertTime != null &&
        now.difference(_lastTempHumAlertTime!).inSeconds < 15) {
      return;
    }
    _lastTempHumAlertTime = now;

    // ประเมินสภาพแวดล้อม
    String status = 'อากาศกำลังสบาย 😊';
    if (temperature >= 35.0) {
      status = 'อากาศร้อนจัด ☀️';
    } else if (temperature >= 32.0) {
      status = 'อากาศค่อนข้างร้อน 🌤️';
    } else if (temperature <= 23.0) {
      status = 'อากาศเย็น ❄️';
    } else if (humidity >= 75.0) {
      status = 'ความชื้นสูง 🌧️';
    } else if (humidity <= 40.0) {
      status = 'อากาศแห้ง 💨';
    }

    const AndroidNotificationDetails envDetails = AndroidNotificationDetails(
      'keychain_env_channel',
      'อุณหภูมิและความชื้น (Environment Alerts)',
      channelDescription: 'แจ้งเตือนผลการวัดอุณหภูมิและความชื้นจาก Smart Keychain',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: envDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      id: 1003,
      title: '🌡️ วัดอุณหภูมิและความชื้นแล้ว ($status)',
      body: 'อุณหภูมิ: ${temperature.toStringAsFixed(1)} °C  |  ความชื้น: ${humidity.toStringAsFixed(1)}% RH',
      notificationDetails: platformDetails,
      payload: 'TEMP_HUM_ALERT',
    );
  }

  /// 3. 📝 ToDo Reminder: ตั้งเวลาเตือนสิ่งที่ต้องทำ
  Future<void> scheduleTodoReminder({
    required int id,
    required String task,
    required String timeStr, // รูปแบบ "HH:mm" เช่น "08:30"
  }) async {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length < 2) return;

      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return;

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
        0,
      );

      // ถ้าเวลาของวันนี้เลยไปแล้ว
      if (scheduledDate.isBefore(now)) {
        // หากอยู่ในช่วงเวลาเดียวกัน (เลยไปไม่เกิน 45 วินาที) ให้เด้งแจ้งเตือนทันที
        if (now.difference(scheduledDate).inSeconds <= 45) {
          await showNotification(
            id: id,
            title: '📋 แจ้งเตือนสิ่งที่ต้องทำ ($timeStr)',
            body: task,
            payload: 'TODO_$id',
          );
          return;
        } else {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }
      }

      const AndroidNotificationDetails todoDetails =
          AndroidNotificationDetails(
        'keychain_todo_channel',
        'เตือนความจำสิ่งที่ต้องทำ (ToDo Reminders)',
        channelDescription: 'แจ้งเตือนกำหนดการและสิ่งที่ต้องทำจาก Smart Keychain',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        fullScreenIntent: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: todoDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      try {
        await _notificationsPlugin.zonedSchedule(
          id: id,
          title: '📋 แจ้งเตือนสิ่งที่ต้องทำ ($timeStr)',
          body: task,
          scheduledDate: scheduledDate,
          notificationDetails: platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'TODO_$id',
        );
      } catch (e) {
        // Fallback ในกรณีที่ OS ไม่อนุญาต exact alarm mode
        debugPrint('⚠️ Exact alarm fallback to inexact: $e');
        await _notificationsPlugin.zonedSchedule(
          id: id,
          title: '📋 แจ้งเตือนสิ่งที่ต้องทำ ($timeStr)',
          body: task,
          scheduledDate: scheduledDate,
          notificationDetails: platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'TODO_$id',
        );
      }

      debugPrint('>>> ⏰ Scheduled ToDo "$task" at $scheduledDate (ID: $id)');
    } catch (e) {
      debugPrint('❌ scheduleTodoReminder error: $e');
    }
  }

  /// ⏱️ ทดสอบตั้งเวลาเตือน ToDo ในอีก X วินาทีข้างหน้า (เช่น 5 วินาที)
  Future<void> scheduleTestTodoInSeconds({int seconds = 5}) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      final scheduledDate = now.add(Duration(seconds: seconds));

      const AndroidNotificationDetails todoDetails =
          AndroidNotificationDetails(
        'keychain_todo_channel',
        'เตือนความจำสิ่งที่ต้องทำ (ToDo Reminders)',
        channelDescription: 'แจ้งเตือนกำหนดการและสิ่งที่ต้องทำจาก Smart Keychain',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: todoDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.zonedSchedule(
        id: 9998,
        title: '📋 แจ้งเตือน ToDo (นับถอยหลัง $seconds วิ)',
        body: 'ถึงเวลาทำภารกิจแล้ว! (ระบบ Schedule แจ้งเตือนตรงเวลาสำเร็จ)',
        scheduledDate: scheduledDate,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'TODO_TEST',
      );
      debugPrint('>>> ⏰ Scheduled Test ToDo in $seconds seconds ($scheduledDate)');
    } catch (e) {
      debugPrint('❌ scheduleTestTodoInSeconds error: $e');
    }
  }

  /// ยกเลิกการแจ้งเตือนตาม ID
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }

  /// ปุ่มทดสอบระบบแจ้งเตือน (Demo Test)
  Future<void> testNotification() async {
    await showNotification(
      id: 9999,
      title: '🔔 ทดสอบการแจ้งเตือน Smart Keychain',
      body: 'ระบบแจ้งเตือน Local Notification ทำงานได้ถูกต้องสมบูรณ์แล้ว!',
      payload: 'TEST_NOTIFICATION',
    );
  }
}

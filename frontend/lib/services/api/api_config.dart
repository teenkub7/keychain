import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  /// IP Address ปัจจุบันของเครื่องคอมพิวเตอร์ที่รัน C# Backend บนเครือข่าย Wi-Fi
  static const String defaultLanIp = '172.20.10.4';
  static const int port = 5000;

  /// Candidate URLs เรียงตามลำดับความน่าจะเป็น
  /// บน Android ใช้ 127.0.0.1 แทน localhost เสมอ เพื่อป้องกัน DNS lookup 'localhost' ล้มเหลว
  static final List<String> candidateUrls = [
    // 1. USB Connection (ผ่าน adb reverse) หรือรันบน Desktop/Web
    'http://127.0.0.1:$port/api',
    // 2. Android Emulator (10.0.2.2 ชี้ไปยัง localhost ของโฮสต์)
    'http://10.0.2.2:$port/api',
    // 3. Physical Android / มือถือที่ต่อ Wi-Fi วงเดียวกัน
    'http://$defaultLanIp:$port/api',
  ];

  static String _activeBaseUrl = 'http://127.0.0.1:$port/api';

  static String get baseUrl => _activeBaseUrl;
  static String get sensorBaseUrl => '$_activeBaseUrl/Sensor';
  static String get userBaseUrl => '$_activeBaseUrl/User';

  static Future<void> loadSavedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_backend_url');
      if (saved != null && saved.trim().isNotEmpty) {
        setBaseUrl(saved);
        return;
      }
    } catch (_) {}
  }

  static void setBaseUrl(String newUrl) {
    var trimmed = newUrl.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    // บน Android หากมีคำว่า localhost ให้แปลงเป็น 127.0.0.1 อัตโนมัติ ป้องกัน Failed host lookup
    if (!kIsWeb) {
      try {
        if (Platform.isAndroid && trimmed.contains('localhost')) {
          trimmed = trimmed.replaceAll('localhost', '127.0.0.1');
        }
      } catch (_) {}
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    if (!trimmed.endsWith('/api') && !trimmed.contains('/api/')) {
      trimmed = '$trimmed/api';
    }
    _activeBaseUrl = trimmed;

    // บันทึกลง SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('custom_backend_url', _activeBaseUrl);
    }).catchError((_) {});

    debugPrint('🌐 ApiConfig activeBaseUrl set to: $_activeBaseUrl');
  }

  static String switchToNextCandidate() {
    int currentIndex = candidateUrls.indexOf(_activeBaseUrl);
    int nextIndex = (currentIndex + 1) % candidateUrls.length;
    setBaseUrl(candidateUrls[nextIndex]);
    return _activeBaseUrl;
  }
}

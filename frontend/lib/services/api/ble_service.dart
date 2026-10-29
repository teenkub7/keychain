import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/sensor_data.dart';
import 'sensor_api_service.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  static const String deviceName = "ESP32_SmartKeychain";
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  StreamSubscription? _notifySubscription;

  String currentUsername = 'user1';
  void setUsername(String username) {
    if (username.isNotEmpty) {
      currentUsername = username;
    }
  }

  /// โหมดการวัดปัจจุบัน: 'Manual_Spot' หรือ 'Auto_30s'
  /// UI ต้องเรียก setMeasurementMode() ก่อนส่งคำสั่งให้ ESP32 ทุกครั้ง
  String _currentMode = 'Auto_30s';
  void setMeasurementMode(String mode) {
    _currentMode = mode;
    debugPrint('>>> 🔧 BleService mode set to: $_currentMode');
  }

  final _dataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;

  Future<bool> connectToKeychain() async {
    try {
      debugPrint(">>> 🔍 1. Scanning / Finding Connected Devices...");
      
      List<BluetoothDevice> connected = FlutterBluePlus.connectedDevices;
      for (var dev in connected) {
        String name = dev.platformName.isNotEmpty ? dev.platformName : dev.advName;
        if (name.contains("ESP32") || name.contains("Keychain")) {
          targetDevice = dev;
          break;
        }
      }

      if (targetDevice == null) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
        var results = await FlutterBluePlus.scanResults.first;
        for (ScanResult r in results) {
          String name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
          if (name.contains("ESP32") || name.contains("Keychain")) {
            targetDevice = r.device;
            break;
          }
        }
        await FlutterBluePlus.stopScan();
      }

      if (targetDevice == null) {
        debugPrint("❌ BLE Error: Device not found!");
        return false;
      }

      debugPrint(">>> 🔗 2. Connecting to Device: ${targetDevice!.remoteId}");
      await targetDevice!.connect(autoConnect: false, timeout: const Duration(seconds: 8));

      List<BluetoothService> services = await targetDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains(serviceUuid.substring(0, 8))) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(characteristicUuid.substring(0, 8))) {
              targetCharacteristic = char;

              // หน่วงเวลา 300ms ให้ Android GATT Cache พร้อมใช้งาน
              await Future.delayed(const Duration(milliseconds: 300));

              try {
                await targetCharacteristic!.setNotifyValue(true);
              } catch (e) {
                debugPrint("⚠️ setNotifyValue warning: $e");
              }

              // ดักฟังข้อมูลด้วย lastValueStream
              await _notifySubscription?.cancel();
              _notifySubscription = targetCharacteristic!.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  String jsonStr = String.fromCharCodes(value);
                  debugPrint(">>> 📥 Real BLE Incoming: $jsonStr");
                  processAndSaveBleData(jsonStr);
                }
              });

              debugPrint(">>> 🟢 SUCCESS: BLE Notification Active!");
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint("❌ BLE Connect Exception: $e");
      return false;
    }
  }

  Future<void> processAndSaveBleData(String jsonStr) async {
    try {
      jsonStr = jsonStr.trim();
      
      if (!jsonStr.startsWith('{') || !jsonStr.endsWith('}')) {
        debugPrint(">>> ℹ️ Ignored Non-JSON BLE Message: $jsonStr");
        return;
      }

      final Map<String, dynamic> data = jsonDecode(jsonStr);

      final double temp = double.tryParse(data['temp']?.toString() ?? '0') ?? 0.0;
      final double hum = double.tryParse(data['hum']?.toString() ?? '0') ?? 0.0;
      final double hr = double.tryParse(data['hr']?.toString() ?? '0') ?? 0.0;
      final double spo2 = double.tryParse(data['spo2']?.toString() ?? '0') ?? 0.0;

      // ใช้ _currentMode ที่ UI ตั้งไว้ก่อนส่งคำสั่ง
      // แทนการเดาจากค่า hr/spo2 (เพราะ ESP32 ส่งมาทุก field ทุกครั้ง)
      final String type = _currentMode;

      // 🔴 บันทึกลง MySQL Database ทันที
      SensorLogItem? savedItem;
      try {
        savedItem = await SensorApiService.logData(
          username: currentUsername,
          heartRate: hr,
          spO2: spo2,
          temperature: temp,
          humidity: hum,
          measurementType: type,
        );
      } catch (e) {
        debugPrint("⚠️ SensorApiService.logData in BLE Error: $e");
      }

      SensorLogItem localItem = savedItem ??
          SensorLogItem(
            id: DateTime.now().millisecondsSinceEpoch,
            username: currentUsername,
            heartRate: hr,
            spO2: spo2,
            temperature: temp,
            humidity: hum,
            measurementType: type,
            recordedAt: DateTime.now(),
          );

      _dataStreamController.add({
        'dbItem': localItem,
        'type': type,
      });

      debugPrint(">>> 🚀 Broadcast BLE to UI & DB Saved: HR=$hr, SpO2=$spo2, Temp=$temp, Hum=$hum (DB_ID=${localItem.id})");
    } catch (e) {
      debugPrint("❌ processAndSaveBleData Error: $e");
    }
  }

  Future<bool> sendData(String text) async {
    if (targetCharacteristic == null) {
      bool ok = await connectToKeychain();
      if (!ok || targetCharacteristic == null) return false;
    }
    try {
      await targetCharacteristic!.write(utf8.encode(text));
      debugPrint(">>> 📤 Sent BLE Command: $text");
      return true;
    } catch (e) {
      debugPrint("❌ Send BLE Error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    if (targetDevice != null) {
      try {
        await targetDevice!.disconnect();
      } catch (e) {
        debugPrint("BLE disconnect error: $e");
      }
      targetDevice = null;
      targetCharacteristic = null;
    }
  }
}

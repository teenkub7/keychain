import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String deviceName = "Smart Keychain";
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;

  Future<bool> connectToKeychain() async {
    try {
      // 1. เริ่มสแกนหาอุปกรณ์
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      var results = await FlutterBluePlus.scanResults.first;
      for (ScanResult r in results) {
        if (r.device.platformName == deviceName || r.advertisementData.advName == deviceName) {
          targetDevice = r.device;
          break;
        }
      }

      // หยุดสแกนก่อนสั่งเชื่อมต่อ
      await FlutterBluePlus.stopScan();

      if (targetDevice == null) return false;

// 2. เชื่อมต่ออุปกรณ์
      await targetDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10),
      );

      // 3. ค้นหา Service และ Characteristic สำหรับรับส่งข้อมูล
      List<BluetoothService> services = await targetDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == characteristicUuid) {
              targetCharacteristic = char;
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      print("BLE Error: $e");
      return false;
    }
  }

  // ส่งข้อมูลไปที่ ESP32
  Future<void> sendData(String text) async {
    if (targetCharacteristic != null) {
      List<int> bytes = utf8.encode(text);
      await targetCharacteristic!.write(bytes);
    }
  }

  // ตัดการเชื่อมต่อ
  Future<void> disconnect() async {
    if (targetDevice != null) {
      await targetDevice!.disconnect();
    }
  }
}
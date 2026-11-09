import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ImageBleHelper {
  /// ประมวลผลรูปภาพสำหรับ ESP32:
  /// - รูปทั่วไป (isQr = false): ครอบตัดและย่อให้เต็มจอ (240x320)
  /// - รูป QR Code (isQr = true): ย่อให้พอดีกรอบ ไม่ตัดขอบเด็ดขาด (Fit/Contain 240x275) บนผืนผ้าใบสีขาว
  static Uint8List processImageForESP32(Uint8List rawBytes, {bool isQr = false}) {
    img.Image? original = img.decodeImage(rawBytes);
    if (original == null) throw Exception("Failed to decode image");

    if (isQr) {
      // หน้าจอ QR บน ESP32 มี Header ด้านบนกินพื้นที่ไป 45px (y=0..44)
      // พื้นที่แสดงผลด้านล่างที่เหลือพอดีจอ 240x320 คือ กว้าง 240 x สูง 275 (320 - 45)
      const int targetWidth = 240;
      const int targetHeight = 275;

      // คำนวณอัตราส่วนย่อแบบ Fit/Contain เพื่อให้เห็น QR Code ครบทุกมุม ไม่ถูกตัดขอบ
      double scale = min(
        (targetWidth - 16) / original.width,
        (targetHeight - 16) / original.height,
      );
      int scaledWidth = (original.width * scale).round();
      int scaledHeight = (original.height * scale).round();

      img.Image scaled = img.copyResize(
        original,
        width: scaledWidth,
        height: scaledHeight,
        interpolation: img.Interpolation.cubic,
      );

      // สร้างพื้นหลังสีขาวขนาด 240 x 275 แล้ววาง QR Code ไว้ตรงกลางพอดี
      img.Image canvas = img.Image(width: targetWidth, height: targetHeight);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

      int dstX = (targetWidth - scaledWidth) ~/ 2;
      int dstY = (targetHeight - scaledHeight) ~/ 2;
      img.compositeImage(canvas, scaled, dstX: dstX, dstY: dstY);

      return Uint8List.fromList(img.encodeJpg(canvas, quality: 75));
    } else {
      // รูปภาพทั่วไป: ครอบตัดและปรับขนาดให้เต็มจอ 240 x 320 พอดีเป๊ะ
      const int targetWidth = 240;
      const int targetHeight = 320;

      double targetAspect = targetWidth / targetHeight;
      double currentAspect = original.width / original.height;

      int cropWidth = original.width;
      int cropHeight = original.height;
      int cropX = 0;
      int cropY = 0;

      if (currentAspect > targetAspect) {
        cropWidth = (original.height * targetAspect).toInt();
        cropX = (original.width - cropWidth) ~/ 2;
      } else if (currentAspect < targetAspect) {
        cropHeight = (original.width / targetAspect).toInt();
        cropY = (original.height - cropHeight) ~/ 2;
      }

      // ป้องกันค่า Crop หลุดออกนอกขอบภาพต้นฉบับ
      cropX = max(0, min(cropX, original.width - cropWidth));
      cropY = max(0, min(cropY, original.height - cropHeight));
      cropWidth = min(cropWidth, original.width - cropX);
      cropHeight = min(cropHeight, original.height - cropY);

      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );

      img.Image resized = img.copyResize(
        cropped,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.cubic,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    }
  }

  static Future<void> sendImageToESP32({
    required Uint8List rawImageBytes,
    required BluetoothCharacteristic characteristic,
    required BluetoothDevice device,
    String type = "IMG", // "IMG" สำหรับรูปภาพทั่วไป หรือ "IMG_QR" สำหรับรูปภาพ QR Code
  }) async {
    // 1. ส่งสัญญาณเริ่ม (START)
    await characteristic.write(utf8.encode("START"), withoutResponse: false);
    await Future.delayed(const Duration(milliseconds: 200));

    bool isQr = (type == "IMG_QR" || type == "QR");
    Uint8List processedJpg = processImageForESP32(rawImageBytes, isQr: isQr);
    String base64Image = base64Encode(processedJpg);
    String imagePayload = "$type:$base64Image";

    const int chunkSize = 100;

    // 2. ส่งข้อมูลรูปภาพ (Data Chunks)
    for (int i = 0; i < imagePayload.length; i += chunkSize) {
      int end = (i + chunkSize < imagePayload.length)
          ? i + chunkSize
          : imagePayload.length;
      String chunk = imagePayload.substring(i, end);

      await characteristic.write(
        utf8.encode("D:$chunk"),
        withoutResponse: false,
      );
      
      await Future.delayed(const Duration(milliseconds: 20));
    }

    // 3. ส่งสัญญาณจบ (END) พร้อมดัก Error ไม่ให้แอปเด้ง Exception
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      await characteristic.write(utf8.encode("END"), withoutResponse: false);
    } catch (e) {
      debugPrint("END signal write bypass warning: $e");
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
    debugPrint("Image ($type) sent completely!");
  }
}

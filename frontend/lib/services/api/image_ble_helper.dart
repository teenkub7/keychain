import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ImageBleHelper {
  static Uint8List processImageForESP32(Uint8List rawBytes) {
    img.Image? original = img.decodeImage(rawBytes);
    if (original == null) throw Exception("Failed to decode image");

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
      cropY = (original.height - cropY) ~/ 2;
    }

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
      interpolation: img.Interpolation.average,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 35));
  }

  static Future<void> sendImageToESP32({
    required Uint8List rawImageBytes,
    required BluetoothCharacteristic characteristic,
    required BluetoothDevice device,
  }) async {
    // 1. ส่งสัญญาณเริ่ม (START)
    await characteristic.write(utf8.encode("START"), withoutResponse: false);
    await Future.delayed(const Duration(milliseconds: 200));

    Uint8List processedJpg = processImageForESP32(rawImageBytes);
    String base64Image = base64Encode(processedJpg);
    String imagePayload = "IMG:$base64Image";

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
    debugPrint("Image sent completely!");
  }
}
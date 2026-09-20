import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const String apiBaseUrl = "http://192.168.0.100:5000/api/User";

class DisplayScreen extends StatelessWidget {

  final Function(dynamic) onSendDisplay;
  final String? initialQrData;
  final String? initialImageData;
  final String currentUsername;

  const DisplayScreen({
    super.key,
    required this.onSendDisplay,
    this.initialQrData,
    this.initialImageData,
    this.currentUsername = "user1",
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const TabBar(
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: [
            Tab(icon: Icon(Icons.image), text: "รูปภาพ"),
            Tab(icon: Icon(Icons.qr_code), text: "QR Code"),
          ],
        ),
        body: TabBarView(
          children: [
            _TftImageTab(
              onSendDisplay: onSendDisplay,
              initialImageData: initialImageData,
              username: currentUsername,
            ),
            _TftQrTab(
              onSendDisplay: onSendDisplay,
              initialQrData: initialQrData,
              username: currentUsername,
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== หน้า 1: รูปภาพ TFT ====================
class _TftImageTab extends StatefulWidget {
  final Function(dynamic) onSendDisplay;
  final String? initialImageData;
  final String username;

  const _TftImageTab({
    required this.onSendDisplay,
    this.initialImageData,
    required this.username,
  });

  @override
  State<_TftImageTab> createState() => _TftImageTabState();
}

class _TftImageTabState extends State<_TftImageTab> {
  File? _selectedImage;
  Uint8List? _selectedRawBytes;
  String? _savedBase64Image;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialImageData != null && widget.initialImageData!.isNotEmpty) {
      _savedBase64Image = widget.initialImageData;
    }
  }

  // เลือกรูปจาก Gallery
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      Uint8List imageBytes = await File(pickedFile.path).readAsBytes();

      setState(() {
        _selectedImage = File(pickedFile.path);
        _selectedRawBytes = imageBytes;
      });
    }
  }

  // กดปุ่มบันทึกและส่งข้อมูล
  Future<void> _sendImage() async {
    if (_selectedRawBytes == null && (_savedBase64Image == null || _savedBase64Image!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปภาพก่อนครับ')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedRawBytes != null) {
        // ✨ ส่ง Uint8List ออกไป ให้ main.dart และ ImageBleHelper เป็นตัวจัดการทั้งหมด
        await widget.onSendDisplay(_selectedRawBytes);
      } else if (_savedBase64Image != null) {
        // กรณีดึงภาพเดิม Base64 จาก DB
        Uint8List decodedBytes = base64Decode(_savedBase64Image!);
        await widget.onSendDisplay(decodedBytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ประมวลผลและส่งรูปภาพเข้าพวงกุญแจสำเร็จ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งรูปภาพ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text(
            "เลือกรูปภาพเพื่อแสดงบนพวงกุญแจ TFT",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _pickImage,
            icon: const Icon(Icons.add_a_photo),
            label: const Text("เลือกรูปภาพจาก Gallery"),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 140,
              height: 248,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple, width: 4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  color: Colors.grey.shade300,
                  child: _buildImagePreview(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _sendImage,
              icon: const Icon(Icons.send),
              label: const Text("ส่งรูปภาพเข้าพวงกุญแจ TFT"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_selectedImage != null) {
      return Image.file(_selectedImage!, fit: BoxFit.cover);
    } else if (_savedBase64Image != null && _savedBase64Image!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(_savedBase64Image!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
        );
      } catch (e) {
        return const Icon(Icons.broken_image, size: 50);
      }
    }
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image, size: 40, color: Colors.grey),
        SizedBox(height: 8),
        Text("ยังไม่ได้เลือกรูป", style: TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

// ==================== หน้า 2: QR Code ====================
class _TftQrTab extends StatefulWidget {
  final Function(dynamic) onSendDisplay;
  final String? initialQrData;
  final String username;

  const _TftQrTab({
    required this.onSendDisplay,
    this.initialQrData,
    required this.username,
  });

  @override
  State<_TftQrTab> createState() => _TftQrTabState();
}

class _TftQrTabState extends State<_TftQrTab> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQrData != null && widget.initialQrData!.isNotEmpty) {
      final parts = widget.initialQrData!.split('|');
      if (parts.isNotEmpty) _urlController.text = parts[0];
      if (parts.length > 1) _titleController.text = parts[1];
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _sendQrCode() async {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก URL สำหรับ QR Code')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final payload = "$url|$title";

    // ส่งให้ main.dart (main.dart จะจัดการส่งผ่าน BLE และบันทึกลง Database ให้เอง)
    widget.onSendDisplay("QR:$payload");

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่ง QR Code เข้าพวงกุญแจเรียบร้อย')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: "ข้อความแสดงใต้ QR Code บนจอ TFT",
              hintText: "เช่น Instagram: @myname",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.subtitles),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: "ใส่ URL โซเชียล/ข้อความ QR Code",
              hintText: "https://instagram.com/...",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 140,
              height: 248,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple, width: 4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.qr_code_2, size: 85, color: Colors.black),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _titleController.text.isEmpty ? "SCAN ME" : _titleController.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _sendQrCode,
              icon: const Icon(Icons.send),
              label: const Text("ส่ง QR Code เข้าพวงกุญแจ TFT"),
            ),
          ),
        ],
      ),
    );
  }
}
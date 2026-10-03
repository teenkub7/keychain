import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

class DisplayScreen extends StatefulWidget {
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
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  int _activeTabIndex = 0; // 0 = รูปภาพ, 1 = QR Code

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. หัวข้อหน้า
                  _buildHeader(),
                  const SizedBox(height: 18),

                  // 2. แถบสลับแท็บแบบแคปซูล (Pill Segmented Switch)
                  _buildPillTabSwitch(),
                  const SizedBox(height: 20),

                  // 3. เนื้อหาตามแท็บที่เลือก
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _activeTabIndex == 0
                        ? _TftImageSection(
                            key: const ValueKey('image_tab'),
                            onSendDisplay: widget.onSendDisplay,
                            initialImageData: widget.initialImageData,
                            username: widget.currentUsername,
                          )
                        : _TftQrSection(
                            key: const ValueKey('qr_tab'),
                            onSendDisplay: widget.onSendDisplay,
                            initialQrData: widget.initialQrData,
                            username: widget.currentUsername,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. ส่วนหัวข้อหน้า
  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'หน้าจอพวงกุญแจ TFT',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF14293D),
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'ส่งรูปภาพหรือคิวอาร์โค้ดขึ้นแสดงบนหน้าจอพวงกุญแจ LCD',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // 2. แถบสลับแคปซูล
  Widget _buildPillTabSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              title: 'ส่งรูปภาพ (Image)',
              icon: Icons.image_rounded,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              index: 1,
              title: 'คิวอาร์โค้ด (QR)',
              icon: Icons.qr_code_2_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final bool isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTabIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? const Color(0xFFFF6B00) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF14293D) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ส่วนที่ 1: ส่งรูปภาพ TFT ====================
class _TftImageSection extends StatefulWidget {
  final Function(dynamic) onSendDisplay;
  final String? initialImageData;
  final String username;

  const _TftImageSection({
    super.key,
    required this.onSendDisplay,
    this.initialImageData,
    required this.username,
  });

  @override
  State<_TftImageSection> createState() => _TftImageSectionState();
}

class _TftImageSectionState extends State<_TftImageSection> {
  Uint8List? _selectedRawBytes;
  String? _savedBase64Image;
  bool _isLoading = false;
  bool _isImageCleared = false;
  String _selectedPresetName = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialImageData != null && widget.initialImageData!.isNotEmpty) {
      _savedBase64Image = widget.initialImageData;
    }
  }

  // แจ้งเตือนมินิมอล
  void _showCustomSnackBar({required String message, required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
        content: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.close_rounded : Icons.check_rounded,
                    color: isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF14293D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // เลือกรูปภาพจากเครื่อง
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final Uint8List bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedRawBytes = bytes;
          _selectedPresetName = 'รูปภาพที่เลือก';
          _isImageCleared = false;
        });
        _showCustomSnackBar(message: 'เลือกรูปภาพเรียบร้อยแล้ว', isError: false);
      }
    } catch (e) {
      _showCustomSnackBar(message: 'ไม่สามารถเปิดรูปภาพได้: $e', isError: true);
    }
  }

  // สลับเลือก/ยกเลิก Preset รูปภาพโลโก้ Smart Keychain
  Future<void> _toggleLogoPreset() async {
    if (_selectedPresetName == 'โลโก้ Smart Keychain') {
      setState(() {
        _selectedRawBytes = null;
        _selectedPresetName = '';
        _isImageCleared = true;
      });
      _showCustomSnackBar(message: 'ยกเลิกการเลือกภาพแล้ว', isError: false);
      return;
    }

    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      final Uint8List bytes = data.buffer.asUint8List();
      setState(() {
        _selectedRawBytes = bytes;
        _selectedPresetName = 'โลโก้ Smart Keychain';
        _isImageCleared = false;
      });
      _showCustomSnackBar(message: 'เลือก Preset โลโก้ Smart Keychain แล้ว', isError: false);
    } catch (e) {
      _showCustomSnackBar(message: 'เกิดข้อผิดพลาดในการโหลดรูปภาพตัวอย่าง', isError: true);
    }
  }

  // ส่งรูปภาพ
  Future<void> _sendImage() async {
    if (_selectedRawBytes == null && (_savedBase64Image == null || _savedBase64Image!.isEmpty)) {
      _showCustomSnackBar(message: 'กรุณาเลือกรูปภาพก่อนส่งครับ', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedRawBytes != null) {
        await widget.onSendDisplay(_selectedRawBytes);
      } else if (_savedBase64Image != null) {
        final Uint8List decodedBytes = base64Decode(_savedBase64Image!);
        await widget.onSendDisplay(decodedBytes);
      }

      if (mounted) {
        _showCustomSnackBar(message: '✨ ประมวลผลและส่งรูปภาพเข้าพวงกุญแจสำเร็จ!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar(message: 'เกิดข้อผิดพลาดในการส่งรูป: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. กล่องอัปโหลดรูปภาพ
        _buildUploadCard(),
        const SizedBox(height: 14),

        // 2. ชิปตัวเลือก Preset ด่วน
        _buildPresetsRow(),
        const SizedBox(height: 24),

        // 3. กรอบพวงกุญแจ Smart Keychain Mockup เสมือนจริง
        Center(
          child: _buildKeychainDeviceFrame(
            screenChild: _buildImagePreview(),
          ),
        ),
        const SizedBox(height: 24),

        // 4. ปุ่มกดส่งภาพเข้าพวงกุญแจ
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendImage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              shadowColor: const Color(0xFFFF6B00).withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _isLoading ? 'กำลังประมวลผลและส่งรูปภาพ...' : 'ส่งรูปภาพเข้าพวงกุญแจ TFT',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // การ์ดอัปโหลดภาพ
  Widget _buildUploadCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _isLoading ? null : _pickImage,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4EC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_rounded,
                  color: Color(0xFFFF6B00),
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'แตะเพื่อเลือกรูปภาพจากเครื่อง',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'รองรับ JPG, PNG (ระบบจะย่อขนาดเข้าจอ LCD 240x280 อัตโนมัติ)',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ชิป Preset
  Widget _buildPresetsRow() {
    final bool isLogoSelected = _selectedPresetName == 'โลโก้ Smart Keychain';
    final bool hasCustomImage = _selectedRawBytes != null && !isLogoSelected;

    return Row(
      children: [
        const Text(
          'ตัวอย่างด่วน: ',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _toggleLogoPreset,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isLogoSelected ? const Color(0xFFFF6B00) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.vpn_key_rounded,
                  size: 13,
                  color: isLogoSelected ? Colors.white : const Color(0xFFFF6B00),
                ),
                const SizedBox(width: 5),
                Text(
                  'โลโก้ Smart Keychain',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isLogoSelected ? Colors.white : const Color(0xFF14293D),
                  ),
                ),
                if (isLogoSelected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
        if (hasCustomImage) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _selectedRawBytes = null;
                _selectedPresetName = '';
              });
              _showCustomSnackBar(message: 'ยกเลิกรูปภาพแล้ว', isError: false);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.close_rounded, size: 13, color: Color(0xFFE11D48)),
                  SizedBox(width: 4),
                  Text(
                    'ยกเลิกรูปภาพ',
                    style: TextStyle(fontSize: 11, color: Color(0xFFE11D48), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ตัวพรีวิวภาพในหน้าจอ
  Widget _buildImagePreview() {
    if (_isImageCleared && _selectedRawBytes == null) {
      return _buildPlaceholderContent();
    }
    if (_selectedRawBytes != null) {
      return Image.memory(
        _selectedRawBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (_savedBase64Image != null && _savedBase64Image!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(_savedBase64Image!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderContent(),
        );
      } catch (e) {
        return _buildPlaceholderContent();
      }
    }
    return _buildPlaceholderContent();
  }

  Widget _buildPlaceholderContent() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wallpaper_rounded, size: 36, color: Color(0xFF94A3B8)),
          SizedBox(height: 8),
          Text(
            'ยังไม่ได้เลือกรูปภาพ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          SizedBox(height: 2),
          Text(
            '240 x 280 TFT LCD',
            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

// ==================== ส่วนที่ 2: ส่ง QR Code TFT ====================
class _TftQrSection extends StatefulWidget {
  final Function(dynamic) onSendDisplay;
  final String? initialQrData;
  final String username;

  const _TftQrSection({
    super.key,
    required this.onSendDisplay,
    this.initialQrData,
    required this.username,
  });

  @override
  State<_TftQrSection> createState() => _TftQrSectionState();
}

class _TftQrSectionState extends State<_TftQrSection> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  bool _isLoading = false;

  final List<Map<String, String>> _qrPresets = [
    {
      'label': 'Instagram',
      'asset': 'assets/Instagram_icon.png',
      'title': 'MY INSTAGRAM',
      'url': 'https://instagram.com/your_name',
    },
    {
      'label': 'LINE',
      'asset': 'assets/line.png',
      'title': 'ADD LINE',
      'url': 'https://line.me/ti/p/your_id',
    },
    {
      'label': 'Facebook',
      'asset': 'assets/facebook.png',
      'title': 'FACEBOOK',
      'url': 'https://facebook.com/your_profile',
    },
    {
      'label': 'เบอร์โทร',
      'asset': 'assets/phone.png',
      'title': 'EMERGENCY CALL',
      'url': 'tel:0812345678',
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQrData != null && widget.initialQrData!.isNotEmpty) {
      final parts = widget.initialQrData!.split('|');
      if (parts.isNotEmpty) _urlController.text = parts[0];
      if (parts.length > 1) _titleController.text = parts[1];
    } else {
      _titleController.text = 'MY INSTAGRAM';
      _urlController.text = 'https://instagram.com/your_name';
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _showCustomSnackBar({required String message, required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
        content: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.close_rounded : Icons.check_rounded,
                    color: isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF14293D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendQrCode() async {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();

    if (url.isEmpty) {
      _showCustomSnackBar(message: 'กรุณากรอก URL หรือข้อความ QR Code', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final payload = "$url|$title";

    try {
      await widget.onSendDisplay("QR:$payload");
      if (mounted) {
        _showCustomSnackBar(message: '✨ ส่ง QR Code เข้าพวงกุญแจเรียบร้อยแล้ว!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar(message: 'เกิดข้อผิดพลาดในการส่ง QR: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentTitle = _titleController.text.trim().isEmpty ? 'SCAN ME' : _titleController.text.trim();
    final String currentUrl = _urlController.text.trim().isEmpty ? 'https://...' : _urlController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. กล่องตั้งค่า QR Code
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ตั้งค่าเนื้อหา QR Code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
              const SizedBox(height: 12),

              // ชิปแม่แบบด่วน
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _qrPresets.map((preset) {
                    final bool isPresetSelected = _titleController.text == preset['title']!;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isPresetSelected) {
                              _titleController.clear();
                              _urlController.clear();
                            } else {
                              _titleController.text = preset['title']!;
                              _urlController.text = preset['url']!;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPresetSelected ? const Color(0xFFFFF4EC) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isPresetSelected ? const Color(0xFFFF6B00) : const Color(0xFFE2E8F0),
                              width: isPresetSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                  preset['asset']!,
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                    Icons.link_rounded,
                                    size: 16,
                                    color: Color(0xFFFF6B00),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                preset['label']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isPresetSelected ? const Color(0xFFFF6B00) : const Color(0xFF14293D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // ช่องพิมพ์ข้อความหัวข้อใต้ QR
              TextField(
                controller: _titleController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'ข้อความกำกับใต้ QR Code (บนจอ TFT)',
                  hintText: 'เช่น MY INSTAGRAM, SCAN ME',
                  prefixIcon: const Icon(Icons.title_rounded, size: 18, color: Color(0xFFFF6B00)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ช่องพิมพ์ลิงก์ URL
              TextField(
                controller: _urlController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'ลิงก์ URL หรือข้อความที่จะให้สแกน',
                  hintText: 'https://instagram.com/...',
                  prefixIcon: const Icon(Icons.link_rounded, size: 18, color: Color(0xFFFF6B00)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. กรอบพวงกุญแจ Smart Keychain Mockup เสมือนจริง
        Center(
          child: _buildKeychainDeviceFrame(
            screenChild: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 90,
                      color: Color(0xFF14293D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    currentTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B00),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    currentUrl,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 3. ปุ่มกดส่ง QR Code เข้าพวงกุญแจ
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendQrCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              shadowColor: const Color(0xFFFF6B00).withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _isLoading ? 'กำลังส่ง QR Code...' : 'ส่ง QR Code เข้าพวงกุญแจ TFT',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== Shared: กรอบพวงกุญแจจำลอง (Realistic Keychain Mockup) ====================
Widget _buildKeychainDeviceFrame({required Widget screenChild}) {
  return Container(
    width: 170,
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B), // สีบอดี้ไทเทเนียม / Dark Slate
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFF334155), width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. ห่วงพวงกุญแจด้านบน (Keychain Hole & Speaker slot)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981), // ไฟสถานะ LED เขียว
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 32,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Icon(
              Icons.all_out_rounded,
              size: 10,
              color: Color(0xFF64748B),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 2. หน้าจอ TFT LCD Screen
        Container(
          width: 150,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF0F172A), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Positioned.fill(child: screenChild),

                // แถบ Status Bar เล็กๆ ด้านบนจอ TFT
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '10:30',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.bluetooth_rounded, size: 9, color: Colors.white),
                            SizedBox(width: 3),
                            Icon(Icons.battery_5_bar_rounded, size: 10, color: Color(0xFF10B981)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 3. ป้ายชื่อแบรนด์ด้านล่างพวงกุญแจ
        const Text(
          'SMART KEYCHAIN',
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}
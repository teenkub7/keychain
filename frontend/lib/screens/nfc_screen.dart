import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcScreen extends StatefulWidget {
  final String? initialNfcData;
  final Function(String) onSendNfc;

  const NfcScreen({
    super.key,
    this.initialNfcData,
    required this.onSendNfc,
  });

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> {
  String _selectedNfcType = 'URL'; // 'URL', 'PHONE', 'VCARD'
  late TextEditingController _dataController;
  bool _isWriting = false;

  @override
  void initState() {
    super.initState();
    _dataController = TextEditingController(
      text: (widget.initialNfcData != null && widget.initialNfcData!.isNotEmpty)
          ? widget.initialNfcData
          : "https://instagram.com/your_username",
    );
  }

  @override
  void dispose() {
    _dataController.dispose();
    super.dispose();
  }

  Future<void> _stopNfcSessionWithError(String message) async {
    await NfcManager.instance.stopSession();
    if (mounted) {
      setState(() => _isWriting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _writeNfcTag() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อุปกรณ์นี้ไม่รองรับ NFC หรือยังไม่ได้เปิดใช้งาน')),
      );
      return;
    }

    setState(() => _isWriting = true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กรุณานำแท็ก NFC หรือพวงกุญแจมาแตะที่หลังมือถือ...')),
    );

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          Ndef? ndef = Ndef.from(tag);

          if (ndef == null) {
            await _stopNfcSessionWithError('แท็กนี้ไม่รองรับการเขียน NDEF');
            return;
          }

          if (!ndef.isWritable) {
            await _stopNfcSessionWithError('แท็กนี้ถูกล็อกไว้ ไม่สามารถเขียนได้');
            return;
          }

          String textVal = _dataController.text.trim();
          if (textVal.isEmpty) {
            await _stopNfcSessionWithError('กรุณากรอกข้อมูลก่อนทำการเขียน');
            return;
          }

          NdefRecord record;
          if (_selectedNfcType == 'PHONE') {
            String phoneUrl = textVal.startsWith('tel:') ? textVal : 'tel:$textVal';
            record = NdefRecord.createUri(Uri.parse(phoneUrl));
          } else if (_selectedNfcType == 'VCARD') {
            record = NdefRecord.createMime(
              'text/vcard',
              Uint8List.fromList(utf8.encode(textVal)),
            );
          } else {
            String url = textVal.startsWith('http') ? textVal : 'https://$textVal';
            record = NdefRecord.createUri(Uri.parse(url));
          }

          NdefMessage message = NdefMessage([record]);
          await ndef.write(message);

          await NfcManager.instance.stopSession();
          widget.onSendNfc(textVal);

          if (mounted) {
            setState(() => _isWriting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('เขียน NFC ($_selectedNfcType) และซิงก์ข้อมูลสำเร็จ!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          await _stopNfcSessionWithError('เกิดข้อผิดพลาดขณะเขียน: ${e.toString()}');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.deepPurple.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.nfc, size: 40, color: Colors.deepPurple),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "NFC Smart Tag",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "เมื่อนำสมาร์ตโฟนมาแตะพวงกุญแจ มือถือจะเปิดข้อมูลด้านล่างนี้ทันที",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "เลือกประเภทข้อมูล NFC",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'URL',
                label: Text('เว็บบอร์ด/IG'),
                icon: Icon(Icons.link),
              ),
              ButtonSegment(
                value: 'PHONE',
                label: Text('เบอร์ฉุกเฉิน'),
                icon: Icon(Icons.phone),
              ),
              ButtonSegment(
                value: 'VCARD',
                label: Text('ข้อความ'),
                icon: Icon(Icons.badge),
              ),
            ],
            selected: {_selectedNfcType},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _selectedNfcType = newSelection.first;
                if (_selectedNfcType == 'URL') {
                  _dataController.text = "https://instagram.com/your_username";
                } else if (_selectedNfcType == 'PHONE') {
                  _dataController.text = "081-234-5678";
                } else {
                  _dataController.text = "พวงกุญแจของ [ชื่อคุณ] ติดต่อ 081-xxx-xxxx";
                }
              });
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _dataController,
            maxLines: _selectedNfcType == 'VCARD' ? 3 : 1,
            decoration: InputDecoration(
              labelText: _getLabelText(),
              border: const OutlineInputBorder(),
              prefixIcon: Icon(_getPrefixIcon()),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _isWriting ? Colors.amber.shade50 : Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isWriting ? Colors.amber : Colors.deepPurple,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isWriting ? Icons.sensors_sharp : Icons.contactless_outlined,
                    size: 50,
                    color: _isWriting ? Colors.amber.shade800 : Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isWriting ? "กำลังรอการแตะพวงกุญแจ NFC..." : "พร้อมเขียนข้อมูลลงชิป NFC",
                  style: TextStyle(
                    fontSize: 12,
                    color: _isWriting ? Colors.amber.shade900 : Colors.grey,
                    fontWeight: _isWriting ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              onPressed: _isWriting ? null : _writeNfcTag,
              icon: _isWriting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.sensors, color: Colors.white),
              label: Text(
                _isWriting ? 'กำลังรอแตะแท็ก NFC...' : 'เขียนข้อมูล NFC และซิงก์ฐานข้อมูล',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                widget.onSendNfc(_dataController.text.trim());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ส่งข้อมูล NFC เข้า ESP32 ผ่าน BLE เรียบร้อย')),
                );
              },
              icon: const Icon(Icons.send),
              label: const Text('ส่งข้อมูลไป ESP32 ผ่าน BLE'),
            ),
          ),
        ],
      ),
    );
  }

  String _getLabelText() {
    switch (_selectedNfcType) {
      case 'PHONE':
        return 'เบอร์โทรศัพท์ฉุกเฉิน';
      case 'VCARD':
        return 'ข้อความ หรือ ข้อมูลติดต่อ';
      default:
        return 'URL โซเชียล/เว็บไซต์';
    }
  }

  IconData _getPrefixIcon() {
    switch (_selectedNfcType) {
      case 'PHONE':
        return Icons.phone;
      case 'VCARD':
        return Icons.text_snippet;
      default:
        return Icons.language;
    }
  }
}
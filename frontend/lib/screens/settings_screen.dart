import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';

/// คลาสตัวเลือกเวลาพักหน้าจอ (Sleep Timeout) แบบ Type-Safe ป้องกัน Null Type Error
class _SleepOption {
  final String label;
  final int seconds;
  final String fullLabel;

  const _SleepOption({
    required this.label,
    required this.seconds,
    required this.fullLabel,
  });
}

class SettingsPage extends StatefulWidget {
  final bool isConnected;
  final String? connectedDeviceName;
  final VoidCallback? onDisconnect;
  final VoidCallback? onConnect;
  final Function(String payload)? onSendBleData;
  final Future<void> Function()? onSyncTime;
  final String? username;
  final Map<String, dynamic>? userData;
  final VoidCallback? onLogout;

  const SettingsPage({
    super.key,
    this.isConnected = false,
    this.connectedDeviceName,
    this.onDisconnect,
    this.onConnect,
    this.onSendBleData,
    this.onSyncTime,
    this.username = 'User',
    this.userData,
    this.onLogout,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // สถานะฮาร์ดแวร์และสิทธิ์
  PermissionStatus _bluetoothStatus = PermissionStatus.denied;
  PermissionStatus _locationStatus = PermissionStatus.denied;
  bool _autoConnectDevice = false;

  // ฟีเจอร์ปรับแต่งพวงกุญแจ
  int _brightness = 80; // ค่าความสว่าง 10 - 100 (%)
  int _sleepTimeout = 60; // วินาที (15, 30, 60, 120, 300, 0 = ตลอดเวลา)

  // ตัวเลือกเวลา Sleep แบบคงที่
  static const List<_SleepOption> _sleepOptions = [
    _SleepOption(label: '15 วิ', seconds: 15, fullLabel: '15 วินาที'),
    _SleepOption(label: '30 วิ', seconds: 30, fullLabel: '30 วินาที'),
    _SleepOption(label: '1 นาที', seconds: 60, fullLabel: '1 นาที (แนะนำ)'),
    _SleepOption(label: '2 นาที', seconds: 120, fullLabel: '2 นาที'),
    _SleepOption(label: '5 นาที', seconds: 300, fullLabel: '5 นาที'),
    _SleepOption(label: 'ตลอดเวลา', seconds: 0, fullLabel: 'เปิดตลอด (ไม่พักหน้าจอ)'),
  ];

  @override
  void initState() {
    super.initState();
    _checkDeviceCapabilities();
    _loadSavedPreferences();
  }

  // ดึงข้อความสรุปสำหรับแสดงในชิปด้านบน
  String _getSleepFullLabel(int seconds) {
    for (final opt in _sleepOptions) {
      if (opt.seconds == seconds) {
        return opt.seconds == 0 ? 'เปิดตลอด' : opt.label;
      }
    }
    return '$seconds วิ';
  }

  // ตรวจสอบความพร้อมของสิทธิ์ต่างๆ
  Future<void> _checkDeviceCapabilities() async {
    try {
      final btStatus = await Permission.bluetoothConnect.status;
      final locStatus = await Permission.location.status;

      if (mounted) {
        setState(() {
          _bluetoothStatus = btStatus;
          _locationStatus = locStatus;
        });
      }
    } catch (e) {
      debugPrint("Error checking capabilities: $e");
    }
  }

  // โหลดค่าตั้งค่าที่เคยเซฟไว้
  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoConnectDevice = prefs.getBool('auto_connect') ?? false;
          _brightness = (prefs.getInt('keychain_brightness') ?? 80).clamp(10, 100);
          _sleepTimeout = prefs.getInt('keychain_sleep_timeout') ?? 60;
        });
      }
    } catch (e) {
      debugPrint("Error loading preferences: $e");
    }
  }

  // บันทึกและส่งค่าความสว่าง
  Future<void> _updateBrightness(int value) async {
    final clampedValue = value.clamp(10, 100);
    setState(() {
      _brightness = clampedValue;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('keychain_brightness', clampedValue);

    // ส่งคำสั่ง BLE ไปยัง ESP32 พวงกุญแจ
    widget.onSendBleData?.call("BRIGHT:$clampedValue");
    widget.onSendBleData?.call("B:$clampedValue");
  }

  // บันทึกและส่งค่า Sleep Timeout
  Future<void> _updateSleepTimeout(int seconds, String label) async {
    setState(() {
      _sleepTimeout = seconds;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('keychain_sleep_timeout', seconds);

    // ส่งคำสั่ง BLE ไปยัง ESP32 พวงกุญแจ
    widget.onSendBleData?.call("SLEEP:$seconds");
    widget.onSendBleData?.call("S:$seconds");

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🌙 ตั้งเวลาพักหน้าจอเป็น: $label'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF14293D),
        ),
      );
    }
  }

  // สลับการเชื่อมต่ออัตโนมัติ
  Future<void> _toggleAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_connect', value);
    setState(() {
      _autoConnectDevice = value;
    });
  }

  // แสดงกล่องยืนยันการออกจากระบบ
  void _confirmLogout() {
    final displayName = (widget.username != null && widget.username!.trim().isNotEmpty)
        ? widget.username!.trim()
        : 'User';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFEF4444),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'ออกจากระบบ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14293D),
              ),
            ),
          ],
        ),
        content: Text(
          'คุณต้องการออกจากระบบบัญชี "$displayName" ใช่หรือไม่? ข้อมูลและการตั้งค่าที่บันทึกไว้จะไม่สูญหาย',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (widget.onLogout != null) {
                widget.onLogout!();
              } else {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'ออกจากระบบ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. หัวข้อหน้าตั้งค่า
                  _buildHeader(),
                  const SizedBox(height: 20),

                  // 2. การ์ดปรับแต่งหน้าจอและพลังงาน (ความสว่าง & ค่า Sleep)
                  _buildSectionTitle('หน้าจอและพลังงาน', Icons.tune_rounded),
                  const SizedBox(height: 10),
                  _buildDisplayAndPowerCard(),
                  const SizedBox(height: 22),

                  // 3. การ์ดสิทธิ์ในระบบ (Permissions)
                  _buildSectionTitle('ระบบและสิทธิ์การใช้งาน', Icons.shield_outlined),
                  const SizedBox(height: 10),
                  _buildPermissionsCard(),
                  const SizedBox(height: 22),

                  // 3.5 ระบบการแจ้งเตือน (Notifications)
                  _buildSectionTitle('ระบบการแจ้งเตือน (Notifications)', Icons.notifications_active_rounded),
                  const SizedBox(height: 10),
                  _buildNotificationsCard(),
                  const SizedBox(height: 26),

                  // 4. ปุ่มออกจากระบบ (Logout) - เหลือเฉพาะปุ่ม Logout ไม่มีหัวข้อตามที่ต้องการ
                  _buildLogoutCard(),
                  const SizedBox(height: 32),

                  // 5. ข้อมูลเวอร์ชันแอป
                  _buildAppFooter(),
                  const SizedBox(height: 20),
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
          'ตั้งค่า (Settings)',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF14293D),
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'ปรับแต่งหน้าจอ สิทธิ์การใช้งาน และความปลอดภัย',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // หัวข้อส่วนย่อย (Section Title)
  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFFFF6B00)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // การ์ดปรับแต่งหน้าจอและพลังงาน (ความสว่าง & ค่า Sleep)
  Widget _buildDisplayAndPowerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ฟีเจอร์ปรับความสว่าง (Screen Brightness)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.wb_sunny_rounded,
                  color: Color(0xFFFF6B00),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ความสว่างหน้าจอ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    Text(
                      'ปรับระดับแสงสว่างของหน้าจอพวงกุญแจ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_brightness%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Slider ควบคุมความสว่าง
          Row(
            children: [
              const Icon(Icons.brightness_low_rounded, size: 18, color: Color(0xFF94A3B8)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: const Color(0xFFFF6B00),
                    inactiveTrackColor: const Color(0xFFF1F5F9),
                    thumbColor: const Color(0xFFFF6B00),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayColor: const Color(0xFFFF6B00).withValues(alpha: 0.15),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _brightness.toDouble().clamp(10.0, 100.0),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: (val) {
                      setState(() {
                        _brightness = val.round().clamp(10, 100);
                      });
                    },
                    onChangeEnd: (val) {
                      _updateBrightness(val.round());
                    },
                  ),
                ),
              ),
              const Icon(Icons.brightness_high_rounded, size: 20, color: Color(0xFFFF6B00)),
            ],
          ),

          // ชิปพรีเซ็ตความสว่างด่วน
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [25, 50, 75, 100].map((preset) {
              final bool isSelected = _brightness == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => _updateBrightness(preset),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF6B00)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF6B00)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$preset%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 18),

          // ฟีเจอร์ตั้งเวลาพักหน้าจอ (Sleep Timeout)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.nightlight_round,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เวลาพักหน้าจอ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    Text(
                      'ดับหน้าจอเมื่อไม่ได้ใช้งาน',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0C2), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFFF6B00)),
                    const SizedBox(width: 4),
                    Text(
                      _getSleepFullLabel(_sleepTimeout),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ตัวเลือกเวลาพักหน้าจอแบบตารางกริดมินิมอล 3x2 ขนาดกะทัดรัด
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sleepOptions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 34,
            ),
            itemBuilder: (context, index) {
              final opt = _sleepOptions[index];
              final bool isSelected = _sleepTimeout == opt.seconds;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _updateSleepTimeout(opt.seconds, opt.fullLabel),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFFFF7A00), Color(0xFFFF5200)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF6B00) : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.2 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF6B00).withValues(alpha: 0.22),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected) ...[
                          const Icon(Icons.check_rounded, size: 12.5, color: Colors.white),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.white : const Color(0xFF475569),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // ปุ่มซิงค์เวลาของพวงกุญแจกับเวลาปัจจุบันของมือถือ
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.access_time_filled_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ซิงค์เวลานาฬิกากับมือถือ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    Text(
                      'อัปเดตเวลานาฬิกาบนพวงกุญแจให้ตรงกับมือถือ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: widget.isConnected ? () => widget.onSyncTime?.call() : null,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('ซิงค์เวลา', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // การ์ดสิทธิ์ในระบบ (Permissions)
  Widget _buildPermissionsCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // สิทธิ์ Bluetooth
            _buildPermissionTile(
              icon: Icons.bluetooth_rounded,
              iconColor: _bluetoothStatus.isGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              title: 'สิทธิ์การเชื่อมต่อ Bluetooth',
              subtitle: _bluetoothStatus.isGranted ? 'อนุญาตแล้วสำหรับการค้นหาพวงกุญแจ' : 'จำเป็นสำหรับการค้นหา ESP32',
              statusWidget: _bluetoothStatus.isGranted
                  ? _buildStatusChip(label: 'อนุญาตแล้ว', isGood: true)
                  : TextButton(
                      onPressed: () async {
                        await [
                          Permission.bluetoothScan,
                          Permission.bluetoothConnect,
                        ].request();
                        _checkDeviceCapabilities();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'ขอสิทธิ์',
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1, indent: 60, color: Color(0xFFF1F5F9)),

            // สิทธิ์ Location
            _buildPermissionTile(
              icon: Icons.location_on_rounded,
              iconColor: _locationStatus.isGranted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              title: 'สิทธิ์การเข้าถึงตำแหน่ง (Location)',
              subtitle: _locationStatus.isGranted ? 'อนุญาตแล้วสำหรับค้นหา BLE' : 'จำเป็นสำหรับค้นหา Bluetooth ใน Android',
              statusWidget: _locationStatus.isGranted
                  ? _buildStatusChip(label: 'อนุญาตแล้ว', isGood: true)
                  : TextButton(
                      onPressed: () async {
                        await Permission.location.request();
                        _checkDeviceCapabilities();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'ขอสิทธิ์',
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1, indent: 60, color: Color(0xFFF1F5F9)),

            // การเชื่อมต่ออัตโนมัติ
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.autorenew_rounded, size: 20, color: Color(0xFF475569)),
              ),
              title: const Text(
                'เชื่อมต่ออุปกรณ์ล่าสุดอัตโนมัติ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF14293D)),
              ),
              subtitle: const Text(
                'ค้นหาและเชื่อมต่อ Bluetooth ทันทีเมื่อเปิดแอป',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              value: _autoConnectDevice,
              activeThumbColor: const Color(0xFFFF6B00),
              activeTrackColor: const Color(0xFFFF6B00).withValues(alpha: 0.4),
              onChanged: _toggleAutoConnect,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            const Divider(height: 1, indent: 60, color: Color(0xFFF1F5F9)),

            // เปิดหน้า App Settings ของอุปกรณ์
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_applications_rounded, size: 20, color: Color(0xFF475569)),
              ),
              title: const Text(
                'เปิดการตั้งค่าแอปในระบบ (System Settings)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF14293D)),
              ),
              subtitle: const Text(
                'กรณีต้องการเปิดหรือแก้ไขสิทธิ์ย่อยในเครื่อง',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
              onTap: () => openAppSettings(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
          ],
        ),
      ),
    );
  }

  // ListTile สิทธิ์แต่ละรายการ
  Widget _buildPermissionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget statusWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF14293D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          statusWidget,
        ],
      ),
    );
  }

  // ชิปสถานะสิทธิ์
  Widget _buildStatusChip({required String label, required bool isGood}) {
    final Color bg = isGood ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9);
    final Color text = isGood ? const Color(0xFF16A34A) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  // การ์ดออกจากระบบ (Logout)
  Widget _buildLogoutCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFEE2E2), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: _confirmLogout,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ออกจากระบบ (Log Out)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'ออกจากบัญชีปัจจุบันและกลับไปยังหน้าล็อกอิน',
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFFEF4444),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // การ์ดระบบแจ้งเตือน (Notifications) พร้อมปุ่มเดโม
  Widget _buildNotificationsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFFF6B00),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'การแจ้งเตือนอัจฉริยะ (Local Alerts)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    Text(
                      'แจ้งเตือนบนมือถือทันทีแม้ไม่ต่อเน็ต (Offline 100%)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // 1. ปุ่มทดสอบ Anti-Lost Alert
          _buildAlertActionRow(
            icon: Icons.bluetooth_disabled_rounded,
            iconColor: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFEF2F2),
            title: '1. ทดสอบเตือนกุญแจหาย (Anti-Lost)',
            subtitle: 'จำลองเหตุการณ์ Bluetooth หลุดระยะหรือลืมกุญแจ',
            btnText: 'ทดสอบ',
            btnColor: const Color(0xFFEF4444),
            onTap: () {
              NotificationService.instance.showAntiLostAlert(
                deviceName: widget.connectedDeviceName ?? 'ESP32_SmartKeychain',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚨 ส่งการแจ้งเตือน Anti-Lost สำเร็จ!'),
                  backgroundColor: Color(0xFFEF4444),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 2. ปุ่มทดสอบ Health / Sensor Alert
          _buildAlertActionRow(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFF43F5E),
            bgColor: const Color(0xFFFFF1F2),
            title: '2. ทดสอบเตือนสุขภาพ (Health Alert)',
            subtitle: 'จำลองค่า SpO2 ต่ำ (<95%) หรือหัวใจเต้นผิดปกติ',
            btnText: 'ทดสอบ',
            btnColor: const Color(0xFFF43F5E),
            onTap: () {
              NotificationService.instance.checkAndAlertSensorData(
                heartRate: 128.0,
                spO2: 92.5,
                temperature: 38.2,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('💓 ส่งการแจ้งเตือน Health Alert สำเร็จ!'),
                  backgroundColor: Color(0xFFF43F5E),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 3. ปุ่มทดสอบแจ้งเตือนทั่วไป
          _buildAlertActionRow(
            icon: Icons.notifications_rounded,
            iconColor: const Color(0xFFFF6B00),
            bgColor: const Color(0xFFFFF7ED),
            title: '3. ทดสอบการแจ้งเตือนทั่วไป (Test Alert)',
            subtitle: 'ทดสอบแถบ Notification ป๊อปอัปและเสียงเตือน',
            btnText: 'ทดสอบ',
            btnColor: const Color(0xFFFF6B00),
            onTap: () {
              NotificationService.instance.testNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔔 ส่งการแจ้งเตือนทั่วไปสำเร็จ!'),
                  backgroundColor: Color(0xFFFF6B00),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 4. ปุ่มทดสอบตั้งเวลาเตือน ToDo (นับถอยหลัง 5 วินาที)
          _buildAlertActionRow(
            icon: Icons.access_alarm_rounded,
            iconColor: const Color(0xFF3B82F6),
            bgColor: const Color(0xFFEFF6FF),
            title: '4. ทดสอบตั้งเวลาเตือน ToDo (นับถอยหลัง 5 วิ)',
            subtitle: 'ทดสอบระบบ Schedule Notification (เด้งเตือนในอีก 5 วินาที)',
            btnText: 'ทดสอบ',
            btnColor: const Color(0xFF3B82F6),
            onTap: () {
              NotificationService.instance.scheduleTestTodoInSeconds(seconds: 5);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⏱️ ตั้งเวลาเตือนแล้ว! กรุณารอ 5 วินาที (ลองพับแอปได้เลย)'),
                  backgroundColor: Color(0xFF3B82F6),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 5. ปุ่มทดสอบเตือนอุณหภูมิและความชื้น (Temp & Humidity Alert)
          _buildAlertActionRow(
            icon: Icons.thermostat_rounded,
            iconColor: const Color(0xFF0EA5E9),
            bgColor: const Color(0xFFF0F9FF),
            title: '5. ทดสอบเตือนอุณหภูมิและความชื้น',
            subtitle: 'จำลองการวัดค่า Temp: 29.5 °C / Hum: 65% RH จาก ESP32',
            btnText: 'ทดสอบ',
            btnColor: const Color(0xFF0EA5E9),
            onTap: () {
              NotificationService.instance.showTempHumidityAlert(
                temperature: 29.5,
                humidity: 65.0,
                force: true,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🌡️ ส่งการแจ้งเตือนผลการวัดอุณหภูมิและความชื้นแล้ว!'),
                  backgroundColor: Color(0xFF0EA5E9),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // วิดเจ็ตแถวปุ่มทดสอบ Alert แต่ละประเภท
  Widget _buildAlertActionRow({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required String btnText,
    required Color btnColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF14293D),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              btnText,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ส่วนท้าย (App Footer)
  Widget _buildAppFooter() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFFF6B00),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Smart Keychain v1.0.0',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

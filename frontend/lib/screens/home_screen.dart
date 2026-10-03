import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onConnectPressed;
  final String username;
  final Map<String, dynamic>? userData;
  final Function(int index)? onNavigateToTab;
  final Function(String payload)? onSendBleData;

  const HomeScreen({
    super.key,
    required this.isConnected,
    required this.onConnectPressed,
    this.username = 'User',
    this.userData,
    this.onNavigateToTab,
    this.onSendBleData,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnline = widget.isConnected;
    final String batteryText = isOnline ? '85%' : '--';
    final String signalText = isOnline ? '-58 dBm' : '--';
    final String tempText = isOnline ? '28.5 °C' : '--';

    final routineData = widget.userData?['routineData']?.toString() ?? '';
    final hasRoutine = routineData.isNotEmpty && routineData != 'CLEAR';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Top Greeting Header
                  _buildGreetingHeader(),
                  const SizedBox(height: 20),

                  // 2. Virtual Smart Keychain Hero Card
                  _buildKeychainHeroCard(isOnline, batteryText, signalText, tempText),
                  const SizedBox(height: 24),

                  // 3. Quick Actions Section Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ฟังก์ชันหลัก (Quick Actions)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF14293D),
                        ),
                      ),
                      Text(
                        '3 รายการ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. Quick Actions
                  _buildQuickActionList(hasRoutine),
                  const SizedBox(height: 24),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. Header ต้อนรับผู้ใช้
  Widget _buildGreetingHeader() {
    final String displayName = widget.username.isNotEmpty ? widget.username : 'User';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'สวัสดีคุณ $displayName',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF14293D),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ภาพรวมสถานะพวงกุญแจและฟังก์ชันการใช้งาน',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // 2. การ์ดพวงกุญแจเสมือนจริง (Virtual Keychain Hero Card)
  Widget _buildKeychainHeroCard(
    bool isOnline,
    String batteryText,
    String signalText,
    String tempText,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // แถวหัวการ์ด: Logo + ชื่ออุปกรณ์ + ชิปสถานะ
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.key_rounded,
                    color: Color(0xFFFF6B00),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Keychain',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    Text(
                      widget.isConnected
                          ? 'ฮาร์ดแวร์จริงเชื่อมต่อแล้ว'
                          : 'ESP32 BLE & NFC (ยังไม่ได้เชื่อมต่อ)',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isConnected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              // ชิปสถานะออนไลน์ / ออฟไลน์
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOnline ? const Color(0xFF15803D) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3 แถบวัดข้อมูลสถานะ (แบตเตอรี่, บลูทูธ RSSI, อุณหภูมิ)
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  title: 'แบตเตอรี่',
                  value: batteryText,
                  subtext: isOnline ? 'พลังงานสูง' : 'ไม่ระบุ',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.bluetooth_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  bgColor: const Color(0xFFEFF6FF),
                  title: 'สัญญาณ BLE',
                  value: signalText,
                  subtext: isOnline ? 'เสถียรมาก' : 'ไม่ได้ต่อ',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.thermostat_rounded,
                  iconColor: const Color(0xFFFF6B00),
                  bgColor: const Color(0xFFFFF4EC),
                  title: 'อุณหภูมิ',
                  value: tempText,
                  subtext: isOnline ? 'สภาวะปกติ' : '--',
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 14),

          // แถวสถานะบลูทูธ & ปุ่มสแกนบลูทูธ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: widget.isConnected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        size: 16,
                        color: widget.isConnected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.isConnected
                            ? 'เชื่อมต่อพร้อมส่งข้อมูล'
                            : 'ยังไม่ได้เชื่อมต่อบลูทูธ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: widget.isConnected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ปุ่มสแกนหาบลูทูธ (Bluetooth Search Button พร้อม Animation)
              widget.isConnected
                  ? Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: widget.onConnectPressed,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_connected_rounded,
                                size: 18,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'เชื่อมต่อแล้ว',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: widget.onConnectPressed,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF7A00), Color(0xFFFF4800)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF6B00).withValues(
                                      alpha: 0.22 + (_pulseController.value * 0.22),
                                    ),
                                    blurRadius: 8 + (_pulseController.value * 8),
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // ไอคอน Bluetooth พร้อม Animation Pulse
                                  ScaleTransition(
                                    scale: _pulseScale,
                                    child: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'สแกนบลูทูธ (BLE)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ],
      ),
    );
  }

  // วิดเจ็ตกล่องแสดงข้อมูลตัวเลขย่อย (Metric Box)
  Widget _buildMetricItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String value,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14293D),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // 4. Quick Actions (3 รายการ)
  Widget _buildQuickActionList(bool hasRoutine) {
    return Column(
      children: [
        // เมนู 1: ตารางเวลา
        _buildActionCard(
          icon: Icons.access_time_filled_rounded,
          iconColor: const Color(0xFFFF6B00),
          bgColor: const Color(0xFFFFF4EC),
          title: 'ตารางเวลา',
          subtitle: hasRoutine ? 'มีตารางที่ตั้งไว้แล้ว' : 'ตั้งเวลา & กิจกรรม',
          onTap: () => widget.onNavigateToTab?.call(1),
        ),
        const SizedBox(height: 12),

        // เมนู 2: หน้าจอพวงกุญแจ
        _buildActionCard(
          icon: Icons.qr_code_2_rounded,
          iconColor: const Color(0xFF4F46E5),
          bgColor: const Color(0xFFEEF2FF),
          title: 'หน้าจอพวงกุญแจ',
          subtitle: 'ส่งรูปภาพ & QR Code',
          onTap: () => widget.onNavigateToTab?.call(2),
        ),
        const SizedBox(height: 12),

        // เมนู 3: นามบัตร NFC
        _buildActionCard(
          icon: Icons.contactless_rounded,
          iconColor: const Color(0xFF059669),
          bgColor: const Color(0xFFECFDF5),
          title: 'นามบัตร NFC',
          subtitle: 'แตะแชร์โปรไฟล์ทันที',
          onTap: () => widget.onNavigateToTab?.call(3),
        ),
      ],
    );
  }

  // วิดเจ็ตการ์ดเมนูด่วนแต่ละอัน (Horizontal Modern Card)
  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: iconColor.withValues(alpha: 0.1),
        highlightColor: iconColor.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
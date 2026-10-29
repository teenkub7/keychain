import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api/api_config.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool isRegisterMode = false;
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;

  // Base URL สำหรับเชื่อมต่อ C# Backend
  String get baseUrl => ApiConfig.userBaseUrl;

  @override
  void initState() {
    super.initState();
    ApiConfig.loadSavedBaseUrl().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> submitForm() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showCustomSnackBar(
        message: 'กรุณากรอกชื่อผู้ใช้และรหัสผ่านให้ครบถ้วน',
        isError: true,
      );
      return;
    }

    if (isRegisterMode && password != confirmPassword) {
      _showCustomSnackBar(
        message: 'รหัสผ่านยืนยันไม่ตรงกัน กรุณาตรวจสอบอีกครั้ง',
        isError: true,
      );
      return;
    }

    setState(() => isLoading = true);

    final path = isRegisterMode ? 'register' : 'login';

    // รายการ Candidates ที่จะลองเชื่อมต่อ (เริ่มจาก activeBaseUrl แล้วตามด้วย candidates อื่นๆ)
    final candidatesToTry = <String>[
      ApiConfig.baseUrl,
      ...ApiConfig.candidateUrls.where((u) => u != ApiConfig.baseUrl),
    ];

    http.Response? response;
    String? workingBaseUrl;

    for (final base in candidatesToTry) {
      try {
        final endpoint = '$base/User/$path';
        final url = Uri.parse(endpoint);

        final res = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username,
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 4));

        response = res;
        workingBaseUrl = base;
        ApiConfig.setBaseUrl(base);
        break;
      } catch (e) {
        debugPrint('Connection attempt failed for $base: $e');
      }
    }

    if (!mounted) return;

    if (response != null) {
      try {
        final data = jsonDecode(response.body);

        if (response.statusCode == 200) {
          if (isRegisterMode) {
            _showCustomSnackBar(
              message: '🎉 สมัครสมาชิกสำเร็จ! กรุณาเข้าสู่ระบบ',
              isError: false,
            );
            setState(() {
              isRegisterMode = false;
              _confirmPasswordController.clear();
            });
          } else {
            _showCustomSnackBar(
              message: '✨ ยินดีต้อนรับคุณ ${data['userId']}',
              isError: false,
            );

            // เข้าสู่หน้าหลักพร้อมส่งข้อมูลผู้ใช้งาน
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MainScreen(userData: data),
              ),
            );
          }
        } else {
          _showCustomSnackBar(
            message: data['message'] ?? 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
            isError: true,
          );
        }
      } catch (e) {
        _showCustomSnackBar(
          message: 'เกิดข้อผิดพลาดในการประมวลผลข้อมูลจาก Server',
          isError: true,
        );
      }
    } else {
      _showCustomSnackBar(
        message: 'ไม่สามารถติดต่อ Backend Server ($baseUrl) ได้ กรุณาแตะที่ "ตั้งค่า Server IP" ด้านล่าง',
        isError: true,
      );
    }

    if (mounted) setState(() => isLoading = false);
  }

  // หน้าต่าง BottomSheet สำหรับตั้งค่า Server IP และทดสอบการเชื่อมต่อ
  void _showServerConfigSheet() {
    final ipController = TextEditingController(text: ApiConfig.baseUrl.replaceAll('/api', ''));
    bool isTesting = false;
    String? testResult;
    bool testSuccess = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.dns_rounded, color: Color(0xFF3B82F6), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ตั้งค่าเชื่อมต่อ Backend Server',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14293D),
                          ),
                        ),
                        Text(
                          'เลือกหรือระบุ IP Address ของเครื่องคอมพิวเตอร์',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'พรีเซ็ตแนะนำ:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPresetChip('📱 USB (localhost:5000)', 'http://localhost:5000', ipController, setSheetState),
                  _buildPresetChip('📶 Wi-Fi (10.26.13.87:5000)', 'http://10.26.13.87:5000', ipController, setSheetState),
                  _buildPresetChip('🤖 Emulator (10.0.2.2:5000)', 'http://10.0.2.2:5000', ipController, setSheetState),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: InputDecoration(
                  labelText: 'Server URL (เช่น http://10.26.13.87:5000 หรือ http://localhost:5000)',
                  labelStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              if (testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: testSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        testSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 16,
                        color: testSuccess ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: testSuccess ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isTesting
                          ? null
                          : () async {
                              setSheetState(() {
                                isTesting = true;
                                testResult = 'กำลังทดสอบเชื่อมต่อ...';
                              });
                              try {
                                var host = ipController.text.trim();
                                if (!host.startsWith('http://') && !host.startsWith('https://')) {
                                  host = 'http://$host';
                                }
                                if (host.endsWith('/')) host = host.substring(0, host.length - 1);
                                final testUrl = Uri.parse('$host/api/Sensor/latest?username=test');

                                final res = await http.get(testUrl).timeout(const Duration(seconds: 3));
                                setSheetState(() {
                                  isTesting = false;
                                  testSuccess = true;
                                  testResult = 'เชื่อมต่อ Backend สำเร็จ (Status: ${res.statusCode})';
                                });
                              } catch (e) {
                                setSheetState(() {
                                  isTesting = false;
                                  testSuccess = false;
                                  testResult = 'เชื่อมต่อไม่สำเร็จ: $e';
                                });
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isTesting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('ทดสอบเชื่อมต่อ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ApiConfig.setBaseUrl(ipController.text);
                        Navigator.pop(ctx);
                        setState(() {});
                        _showCustomSnackBar(
                          message: 'บันทึก Server IP: ${ApiConfig.baseUrl} เรียบร้อย',
                          isError: false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('บันทึกและใช้งาน', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    String targetUrl,
    TextEditingController controller,
    StateSetter setSheetState,
  ) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        setSheetState(() {
          controller.text = targetUrl;
        });
      },
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  void _showCustomSnackBar({required String message, required bool isError}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final Color accentColor = isError ? const Color(0xFFFF5252) : const Color(0xFF10B981);
    final Color badgeBg = isError ? const Color(0xFFFFF1F0) : const Color(0xFFECFDF5);
    final IconData icon = isError ? Icons.error_rounded : Icons.check_circle_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        duration: const Duration(seconds: 3),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.28),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFF14293D),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
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


  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF6B00);
    const darkNavy = Color(0xFF14293D);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // พื้นหลังตกแต่ง Gradient Blob แบบมินิมอลนุ่มนวล
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.12),
                    primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    darkNavy.withValues(alpha: 0.08),
                    darkNavy.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // เนื้อหาหลัก Responsive Center Box
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ส่วนหัว: โลโก้พวงกุญแจน่ารักพร้อมเงา
                      Container(
                        width: 88,
                        height: 88,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.16),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.key_rounded,
                            size: 44,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ชื่อแอป (ไม่มีคำโปรยกวนตา สะอาดตา)
                      const Text(
                        'Smart Keychain',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: darkNavy,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // กล่องการ์ดสีขาวนวลสำหรับฟอร์ม
                      Container(
                        padding: const EdgeInsets.all(26.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ปุ่มสลับโหมด Segmented Control สไตล์ Pill (เรียบ สะอาด เข้าใจง่าย ไม่มีแอนิเมชันกวนใจ)
                            Container(
                              height: 46,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (isRegisterMode) setState(() => isRegisterMode = false);
                                      },
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: !isRegisterMode ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: !isRegisterMode
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.06),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Text(
                                          'เข้าสู่ระบบ',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: !isRegisterMode ? FontWeight.bold : FontWeight.w500,
                                            color: !isRegisterMode ? darkNavy : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (!isRegisterMode) setState(() => isRegisterMode = true);
                                      },
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isRegisterMode ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: isRegisterMode
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.06),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Text(
                                          'สมัครสมาชิก',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: isRegisterMode ? FontWeight.bold : FontWeight.w500,
                                            color: isRegisterMode ? primaryColor : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ช่องกรอก Username
                            _buildInputField(
                              controller: _usernameController,
                              label: 'ชื่อผู้ใช้ (Username)',
                              hintText: 'กรอกชื่อผู้ใช้งาน',
                              icon: Icons.person_outline_rounded,
                            ),
                            const SizedBox(height: 16),

                            // ช่องกรอก Password
                            _buildInputField(
                              controller: _passwordController,
                              label: 'รหัสผ่าน (Password)',
                              hintText: 'กรอกรหัสผ่าน',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              isPasswordVisible: isPasswordVisible,
                              onTogglePasswordVisibility: () {
                                setState(() => isPasswordVisible = !isPasswordVisible);
                              },
                            ),

                            // ช่องกรอก Confirm Password (แสดงเมื่ออยู่ในโหมด Register)
                            if (isRegisterMode) ...[
                              const SizedBox(height: 16),
                              _buildInputField(
                                controller: _confirmPasswordController,
                                label: 'ยืนยันรหัสผ่านอีกครั้ง',
                                hintText: 'กรอกรหัสผ่านเดิมอีกครั้ง',
                                icon: Icons.shield_outlined,
                                isPassword: true,
                                isPasswordVisible: isConfirmPasswordVisible,
                                onTogglePasswordVisibility: () {
                                  setState(() => isConfirmPasswordVisible = !isConfirmPasswordVisible);
                                },
                              ),
                            ],

                            const SizedBox(height: 24),

                            // ปุ่มดำเนินการหลัก (Primary Action Button)
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF7A00), Color(0xFFFF5200)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: isLoading ? null : submitForm,
                                  child: Center(
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                isRegisterMode ? 'สร้างบัญชีผู้ใช้' : 'เข้าสู่ระบบ',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // ปุ่มตั้งค่า Server IP / สถานะการเชื่อมต่อ
                      InkWell(
                        onTap: _showServerConfigSheet,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Server: ${ApiConfig.baseUrl.replaceAll('/api', '')}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.settings_outlined, size: 14, color: Color(0xFF94A3B8)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    bool isPasswordVisible = false,
    VoidCallback? onTogglePasswordVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: isPassword && !isPasswordVisible,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF14293D).withValues(alpha: 0.65), size: 20),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: onTogglePasswordVisibility,
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
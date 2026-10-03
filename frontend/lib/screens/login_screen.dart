import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  String baseUrl = 'http://localhost:5000/api/User';

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

    final endpoint = isRegisterMode ? '$baseUrl/register' : '$baseUrl/login';
    final url = Uri.parse(endpoint);

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (!mounted) return;

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
          message: data['message'] ?? 'เกิดข้อผิดพลาดในการเข้าสู่ระบบ',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar(
        message: 'ไม่สามารถติดต่อ Backend Server ($baseUrl) ได้ กรุณาตรวจสอบการเชื่อมต่อ',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
                              hintText: 'เช่น user1',
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
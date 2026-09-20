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
  bool isLoading = false;
  bool isRegisterMode = false;

  // URL C# API
  final String baseUrl = 'http://192.168.0.100:5000/api/User';

  Future<void> submitForm() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก Username และ Password')),
      );
      return;
    }

    setState(() => isLoading = true);

    final endpoint = isRegisterMode ? '$baseUrl/register' : '$baseUrl/login';
    final url = Uri.parse(endpoint);

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (isRegisterMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('สมัครสมาชิกสำเร็จ! กรุณาล็อกอิน')),
          );
          setState(() => isRegisterMode = false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ยินดีต้อนรับ ${data['userId']}')),
          );

          // เข้าสู่หน้าหลักพร้อมส่งข้อมูลยูเซอร์
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MainScreen(userData: data),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'เกิดข้อผิดพลาด')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถติดต่อ C# Server ได้: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isRegisterMode ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.vpn_key_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: isLoading ? null : submitForm,
              child: isLoading
                  ? const CircularProgressIndicator()
                  : Text(isRegisterMode ? 'ยืนยันลงทะเบียน' : 'เข้าสู่ระบบ'),
            ),
            TextButton(
              onPressed: () {
                setState(() => isRegisterMode = !isRegisterMode);
              },
              child: Text(
                isRegisterMode
                    ? 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'
                    : 'ยังไม่มีบัญชี? สมัครสมาชิก',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
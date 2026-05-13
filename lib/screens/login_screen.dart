import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'pending_screen.dart';
import 'register_screen.dart';

const _ownerEmail = 'gksdud9685@loveapp.com';
const _domain = '@loveapp.com';

String _toEmail(String username) =>
    username.contains('@') ? username : '$username$_domain';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _autoLogin = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final autoLogin = prefs.getBool('auto_login') ?? false;
    if (!autoLogin) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      bool approved = true;
      try {
        final token = await user.getIdToken();
        final res = await http.get(
          Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/${user.uid}'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          final approvedField = fields?['approved'] as Map<String, dynamic>?;
          approved = approvedField?['booleanValue'] as bool? ?? true;
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => approved ? const HomeScreen() : const PendingScreen()),
      );
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFFE91E63),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _login() async {
    final username = _emailController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showMessage('아이디와 비밀번호를 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _toEmail(username),
        password: password,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_login', _autoLogin);

      bool approved = true;
      try {
        final token = await credential.user!.getIdToken();
        final uid = credential.user!.uid;
        final res = await http.get(
          Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/$uid'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          final approvedField = fields?['approved'] as Map<String, dynamic>?;
          approved = approvedField?['booleanValue'] as bool? ?? true;
        } else if (res.statusCode == 404) {
          final email = _toEmail(_emailController.text.trim());
          if (email != _ownerEmail) {
            await FirebaseAuth.instance.signOut();
            if (mounted) _showMessage('탈퇴된 계정이에요');
            return;
          }
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => approved ? const HomeScreen() : const PendingScreen()),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = '등록되지 않은 아이디예요';
        case 'wrong-password':
        case 'invalid-credential':
          message = '아이디 또는 비밀번호가 틀렸어요';
        case 'invalid-email':
          message = '올바르지 않은 아이디예요';
        case 'too-many-requests':
          message = '잠시 후 다시 시도해주세요';
        default:
          message = '로그인 오류: ${e.code}';
      }
      if (mounted) _showMessage(message);
    } catch (e) {
      if (mounted) _showMessage('오류: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B9D),
              Color(0xFFE91E63),
              Color(0xFFC2185B),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 48,
                      color: Color(0xFFE91E63),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Love App',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '사랑하는 연인을 위해',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 48),

                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '로그인 / 회원가입',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.text,
                            decoration: InputDecoration(
                              labelText: '아이디',
                              hintText: '사용할 아이디를 입력하세요',
                              prefixIcon: const Icon(
                                Icons.person_outline,
                                color: Color(0xFFE91E63),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8F8F8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE91E63),
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '아이디를 입력해주세요';
                              }
                              if (value.trim().length < 2) {
                                return '아이디는 2자 이상이어야 해요';
                              }
                              if (RegExp(r'\s').hasMatch(value)) {
                                return '아이디에 공백을 포함할 수 없어요';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: '비밀번호',
                              hintText: '6자 이상 입력하세요',
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Color(0xFFE91E63),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8F8F8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE91E63),
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '비밀번호를 입력해주세요';
                              }
                              if (value.length < 6) {
                                return '비밀번호는 6자 이상이어야 합니다';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),

                          // 자동로그인 체크박스
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _autoLogin,
                                  onChanged: (v) => setState(() => _autoLogin = v ?? false),
                                  activeColor: const Color(0xFFE91E63),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _autoLogin = !_autoLogin),
                                child: const Text(
                                  '자동로그인',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 로그인 버튼
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE91E63),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFFE91E63).withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      '로그인',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 회원가입 버튼
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                      ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE91E63),
                                side: const BorderSide(
                                  color: Color(0xFFE91E63),
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                '처음이에요 (회원가입)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

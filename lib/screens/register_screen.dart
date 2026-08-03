import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'pending_screen.dart';
import '../theme/app_theme.dart';

const _ownerEmail = 'gksdud9685@loveapp.com';
const _domain = '@loveapp.com';

String _toEmail(String username) =>
    username.contains('@') ? username : '$username$_domain';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final username = _usernameController.text.trim();
      final email = _toEmail(username);
      final isOwner = email == _ownerEmail;

      UserCredential credential;
      try {
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          await _tryReregister(email: email, username: username, password: _passwordController.text);
          return;
        }
        String message;
        switch (e.code) {
          case 'weak-password':
            message = '비밀번호가 너무 짧아요 (6자 이상)';
          case 'invalid-email':
            message = '올바르지 않은 아이디예요';
          default:
            message = '회원가입에 실패했어요. 다시 시도해주세요';
        }
        if (mounted) _showMessage(message);
        return;
      }

      final token = await credential.user!.getIdToken();
      final uid = credential.user!.uid;
      await http.patch(
        Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/$uid'
            '?updateMask.fieldPaths=email'
            '&updateMask.fieldPaths=username'
            '&updateMask.fieldPaths=approved'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'email': {'stringValue': email},
            'username': {'stringValue': username},
            'approved': {'booleanValue': isOwner},
          }
        }),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PendingScreen()),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _tryReregister({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 10));

      final token = await cred.user!.getIdToken();
      final uid = cred.user!.uid;
      final res = await http.get(
        Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/$uid'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 404) {
        await http.patch(
          Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/$uid'
              '?updateMask.fieldPaths=email'
              '&updateMask.fieldPaths=username'
              '&updateMask.fieldPaths=approved'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'fields': {
              'email': {'stringValue': email},
              'username': {'stringValue': username},
              'approved': {'booleanValue': false},
            }
          }),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PendingScreen()),
        );
      } else {
        await FirebaseAuth.instance.signOut();
        if (mounted) _showMessage('이미 사용 중인 아이디예요');
      }
    } on FirebaseAuthException {
      if (mounted) _showMessage('이미 사용 중인 아이디예요');
    } catch (_) {
      if (mounted) _showMessage('이미 사용 중인 아이디예요');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.light,
              AppTheme.primary,
              AppTheme.dark,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 상단 뒤로가기
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, size: 48, color: Colors.white),
                        const SizedBox(height: 12),
                        const Text(
                          '회원가입',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '사용할 아이디와 비밀번호를 입력하세요',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 32),

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
                                // 아이디
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    labelText: '아이디',
                                    hintText: '사용할 아이디를 입력하세요',
                                    prefixIcon: Icon(Icons.person_outline, color: AppTheme.primary),
                                    filled: true,
                                    fillColor: const Color(0xFFF8F8F8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: AppTheme.primary, width: 2),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 2),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return '아이디를 입력해주세요';
                                    if (value.trim().length < 2) return '아이디는 2자 이상이어야 해요';
                                    if (RegExp(r'\s').hasMatch(value)) return '아이디에 공백을 포함할 수 없어요';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // 비밀번호
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: '비밀번호',
                                    hintText: '6자 이상 입력하세요',
                                    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primary),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8F8F8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: AppTheme.primary, width: 2),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 2),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return '비밀번호를 입력해주세요';
                                    if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // 비밀번호 확인
                                TextFormField(
                                  controller: _confirmController,
                                  obscureText: _obscureConfirm,
                                  decoration: InputDecoration(
                                    labelText: '비밀번호 확인',
                                    hintText: '비밀번호를 한 번 더 입력하세요',
                                    prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primary),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8F8F8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: AppTheme.primary, width: 2),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Colors.red, width: 2),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return '비밀번호를 한 번 더 입력해주세요';
                                    if (value != _passwordController.text) return '비밀번호가 일치하지 않아요';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),

                                // 가입 버튼
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Text(
                                            '가입 신청',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

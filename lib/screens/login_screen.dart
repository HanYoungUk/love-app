import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'pending_screen.dart';
import 'register_screen.dart';
import '../utils/app_routes.dart';
import '../utils/direct_chat_pref.dart';
import '../theme/app_theme.dart';

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
  bool _directChat = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final autoLogin = prefs.getBool('auto_login') ?? false;
    // 채팅 헤더 ⋯ 메뉴에서도 끌 수 있어서 그쪽과 값을 공유한다
    final directChat = DirectChatPref.enabled.value;
    // 지난번에 켜둔 상태 그대로 체크박스에 보여준다
    if (mounted) {
      setState(() {
        _autoLogin = autoLogin;
        _directChat = directChat;
      });
    }
    if (!autoLogin) return;

    // currentUser는 iOS에서 앱 시작 직후 null일 수 있어서 authStateChanges로 복원 완료를 기다림
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      bool approved = true;
      try {
        final token = await user.getIdToken();
        final res = await http
            .get(
              Uri.parse(
                'https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/${user.uid}',
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          final approvedField = fields?['approved'] as Map<String, dynamic>?;
          approved = approvedField?['booleanValue'] as bool? ?? true;
        }
      } catch (_) {}

      if (!mounted) return;
      _goAfterLogin(approved);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 로그인 후 이동.
  ///
  /// '채팅 바로 열기'를 켰으면 홈을 깔고 그 위에 채팅을 얹는다. 홈이 밑에 있어야
  /// 채팅에서 뒤로 나올 수 있고(설정 변경·로그아웃), 알림 감시도 홈에서 돈다.
  void _goAfterLogin(bool approved) {
    final nav = Navigator.of(context);
    nav.pushReplacement(
      appRoute(approved ? const HomeScreen() : const PendingScreen()),
    );
    if (approved && _directChat) {
      nav.push(appRoute(const ChatScreen()));
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
        backgroundColor: isError ? Colors.red : AppTheme.primary,
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
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _toEmail(username),
            password: password,
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_login', _autoLogin);
      await DirectChatPref.set(_directChat);

      bool approved = true;
      try {
        final token = await credential.user!.getIdToken();
        final uid = credential.user!.uid;
        final res = await http
            .get(
              Uri.parse(
                'https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/$uid',
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5));
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
      _goAfterLogin(approved);
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

  Widget _checkRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // 웹은 회사 PC에서 볼 일이 많으니 분홍 대신 그냥 흰 화면으로 (로고·문구도 뺀다)
    final plain = kIsWeb;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: plain
            ? const BoxDecoration(color: Colors.white)
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppTheme.gradient,
            stops: AppTheme.gradientStops,
                ),
              ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                // 넓은 브라우저에서 카드가 화면 끝까지 늘어나지 않게
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    if (!plain) ...[
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
                        child: Icon(
                          Icons.favorite,
                          size: 48,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Love App',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.onGradient,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '사랑하는 연인을 위해',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.onGradientAlpha(0.85),
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],

                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(plain ? 12 : 24),
                        border: plain
                            ? Border.all(color: const Color(0xFFE0E0E0))
                            : null,
                        boxShadow: plain
                            ? null
                            : [
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
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  color: AppTheme.primary,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8F8F8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: AppTheme.primary,
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
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: AppTheme.primary,
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
                                  borderSide: BorderSide(
                                    color: AppTheme.primary,
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

                            _checkRow(
                              '자동로그인',
                              _autoLogin,
                              (v) => setState(() => _autoLogin = v),
                            ),
                            const SizedBox(height: 4),
                            // 켜두면 로그인 직후(자동로그인 포함) 바로 채팅이 열린다
                            _checkRow(
                              '채팅 바로 열기',
                              _directChat,
                              (v) => setState(() => _directChat = v),
                            ),
                            const SizedBox(height: 16),

                            // 로그인 버튼
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppTheme.primary
                                      .withValues(alpha: 0.6),
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
                                    : () => Navigator.of(
                                        context,
                                      ).push(appRoute(const RegisterScreen())),
                                // 웹에서는 눈에 안 띄게 회색으로
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: plain
                                      ? const Color(0xFF9E9E9E)
                                      : AppTheme.primary,
                                  side: BorderSide(
                                    color: plain
                                        ? const Color(0xFFE0E0E0)
                                        : AppTheme.primary,
                                    width: plain ? 1 : 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      plain ? 12 : 14,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '처음이에요 (회원가입)',
                                  style: TextStyle(
                                    fontSize: plain ? 14 : 16,
                                    fontWeight: plain
                                        ? FontWeight.normal
                                        : FontWeight.bold,
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
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'home_screen.dart';
import 'login_screen.dart';
import '../theme/app_theme.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkApproval();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkApproval());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkApproval() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents/users/${user.uid}'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        final approved = (fields['approved'] as Map<String, dynamic>?)?['booleanValue'] as bool? ?? false;
        if (approved && mounted) {
          _timer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.light, AppTheme.primary, AppTheme.dark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 8),
                child: Align(
                  alignment: Alignment.topRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      _timer?.cancel();
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                    label: const Text('로그아웃', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.white),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          '승인 대기 중이에요',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '관리자가 승인하면\n자동으로 앱이 열려요 💕',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 32),
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
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

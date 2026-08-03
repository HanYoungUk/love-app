import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

class NotificationService {
  static const _vapidKey = String.fromEnvironment(
    'VAPID_KEY',
    defaultValue: '',
  );

  static final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  static GlobalKey<ScaffoldMessengerState> get scaffoldKey => _scaffoldKey;

  static Future<void> init() async {
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }

      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if ((notification.body ?? '').isNotEmpty)
                  Text(notification.body!),
              ],
            ),
            backgroundColor: AppTheme.primary,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      });
    } catch (_) {}
  }

  // 웹(iOS Safari 포함)에서 사용자 제스처로 호출해야 함
  static Future<bool> requestWebPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  // 로그인 후 홈 화면에서 호출
  static Future<void> saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      String? token;

      if (kIsWeb) {
        if (_vapidKey.isEmpty) return;
        token = await messaging.getToken(vapidKey: _vapidKey);
      } else {
        token = await messaging.getToken();
      }

      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
      });

      // 토큰 갱신 시 자동 업데이트
      messaging.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': newToken,
        });
      });
    } catch (_) {}
  }
}

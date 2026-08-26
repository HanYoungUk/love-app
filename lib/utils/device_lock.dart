import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 계정 하나를 폰 한 대에만 묶는다.
///
/// 마지막에 로그인한 폰이 주인이 되고, 먼저 쓰던 폰은 밀려난다.
/// (비밀번호를 아는 사람이 폰을 바꿔도 관리자 손을 빌릴 필요가 없게)
///
/// 웹은 회사 PC에서 열어보는 용도라 이 제한을 받지 않는다.
/// 폰에서 밀려나도 웹은 그대로 쓸 수 있고, 웹에서 로그인해도 폰이 안 밀린다.
class DeviceLock {
  static const _prefsKey = 'device_id';
  static const _base =
      'https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents';

  static String? _cached;

  /// 이 폰에만 있는 ID.
  ///
  /// 설치할 때 한 번 만들어 두고 계속 쓴다. 앱을 지웠다 다시 깔면 새로 생기는데,
  /// 그때는 그냥 다시 로그인하면 그 폰이 새 주인이 되므로 문제되지 않는다.
  static Future<String> myId() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      id = List<int>.generate(16, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }

  /// 서버에 적힌 주인이 이 폰인지.
  ///
  /// 아직 아무도 등록 안 했으면(null/빈값) 내 것으로 친다.
  static Future<bool> isMine(String? ownerId) async {
    if (kIsWeb) return true;
    if (ownerId == null || ownerId.isEmpty) return true;
    return ownerId == await myId();
  }

  /// 이 폰을 계정 주인으로 등록한다.
  ///
  /// Firestore SDK로 쓰면 통신이 끊겼을 때 큐에 쌓인 채 await가 안 풀려서
  /// 로그인 화면이 멈춘다. 그래서 이 파일 다른 곳처럼 REST + 타임아웃을 쓴다.
  /// 실패해도 로그인 자체는 막지 않는다(다음 로그인 때 다시 시도된다).
  static Future<void> claim() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final id = await myId();
      await http
          .patch(
            Uri.parse('$_base/users/${user.uid}?updateMask.fieldPaths=deviceId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'fields': {
                'deviceId': {'stringValue': id},
              },
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

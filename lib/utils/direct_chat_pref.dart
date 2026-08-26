import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// '채팅 바로 열기' 설정 (기기 로컬 저장).
///
/// 로그인 화면의 체크박스와 채팅 헤더 ⋯ 메뉴가 같은 값을 쓴다.
/// 자동로그인 + 이 설정이 켜져 있으면 로그인 화면을 못 보게 되므로,
/// 채팅 안에서도 끌 수 있어야 한다.
class DirectChatPref {
  static const key = 'direct_chat';
  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    enabled.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  static Future<void> toggle() => set(!enabled.value);
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 채팅 알림 on/off 설정 (기기 로컬 저장).
/// home_screen 리스너가 알림을 띄울지 판단할 때, chat_screen 종 버튼이
/// 현재 상태를 표시할 때 같은 값을 공유한다.
class NotifPref {
  static final ValueNotifier<bool> enabled = ValueNotifier(true);
  static const _key = 'chat_notif_enabled';

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_key) ?? true;
    } catch (_) {}
  }

  static Future<void> toggle() => set(!enabled.value);

  static Future<void> set(bool v) async {
    enabled.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }
}

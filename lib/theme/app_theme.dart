import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 색상 테마 한 벌.
/// [light] 그라데이션 위쪽·연한 강조, [mid] 중간 강조(하트 채우기 등),
/// [primary] 메인 색(버튼·아이콘·선택 표시), [dark] 그라데이션 아래쪽.
class AppPalette {
  final String id;
  final String label;
  final String emoji;
  final Color light;
  final Color mid;
  final Color primary;
  final Color dark;

  const AppPalette({
    required this.id,
    required this.label,
    required this.emoji,
    required this.light,
    required this.mid,
    required this.primary,
    required this.dark,
  });

  /// 화면 배경 그라데이션(위 → 아래)
  List<Color> get gradient => [light, primary, dark];
}

/// 테마 선택 상태. 기기 로컬(SharedPreferences)에 저장한다.
/// 알림 종버튼(NotifPref)과 같은 방식이라 기기마다 따로 설정된다.
class AppTheme {
  static const _key = 'app_theme_id';

  static const palettes = <AppPalette>[
    AppPalette(
      id: 'pink',
      label: '핑크',
      emoji: '🌸',
      light: Color(0xFFFF6B9D),
      mid: Color(0xFFFF5A79),
      primary: Color(0xFFE91E63),
      dark: Color(0xFFC2185B),
    ),
    AppPalette(
      id: 'sky',
      label: '하늘',
      emoji: '🌊',
      light: Color(0xFF42A5F5),
      mid: Color(0xFF2196F3),
      primary: Color(0xFF1976D2),
      dark: Color(0xFF0D47A1),
    ),
    AppPalette(
      id: 'green',
      label: '초록',
      emoji: '🌿',
      light: Color(0xFF4CAF50),
      mid: Color(0xFF43A047),
      primary: Color(0xFF2E7D32),
      dark: Color(0xFF1B5E20),
    ),
    AppPalette(
      id: 'grey',
      label: '그레이',
      emoji: '🩶',
      light: Color(0xFF90A4AE),
      mid: Color(0xFF78909C),
      primary: Color(0xFF546E7A),
      dark: Color(0xFF37474F),
    ),
    AppPalette(
      id: 'purple',
      label: '보라',
      emoji: '🔮',
      light: Color(0xFF9575CD),
      mid: Color(0xFF8460C4),
      primary: Color(0xFF6A3FB5),
      dark: Color(0xFF4A2A8A),
    ),
    AppPalette(
      id: 'orange',
      label: '주황',
      emoji: '🍊',
      light: Color(0xFFFF9800),
      mid: Color(0xFFFB8C00),
      primary: Color(0xFFEF6C00),
      dark: Color(0xFFE65100),
    ),
  ];

  /// 현재 테마. 값이 바뀌면 main.dart의 ValueListenableBuilder가 앱 전체를 다시 그린다.
  static final ValueNotifier<AppPalette> current = ValueNotifier(palettes.first);

  static AppPalette get p => current.value;
  static Color get light => p.light;
  static Color get mid => p.mid;
  static Color get primary => p.primary;
  static Color get dark => p.dark;
  static List<Color> get gradient => p.gradient;

  static AppPalette byId(String? id) =>
      palettes.firstWhere((e) => e.id == id, orElse: () => palettes.first);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = byId(prefs.getString(_key));
    } catch (_) {}
  }

  static Future<void> set(AppPalette palette) async {
    current.value = palette;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, palette.id);
    } catch (_) {}
  }
}

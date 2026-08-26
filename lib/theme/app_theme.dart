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

  /// 그라데이션 배경 **위**에 얹는 글자·아이콘 색.
  /// 어두운 테마는 흰색, 밝은 테마(그레이)는 진한 회색.
  final Color onGradient;

  /// 그라데이션 배경 위 반투명 패널의 바탕색. 투명도는 쓰는 쪽에서 정한다.
  /// 어두운 테마는 흰색 계열, 밝은 테마는 검정 계열이어야 보인다.
  final Color overlay;

  /// 배경 그라데이션을 직접 지정할 때. 안 주면 [light, primary, dark].
  /// (밝은 테마는 primary가 버튼용 진한 색이라 그라데이션과 따로 간다)
  final List<Color>? gradientColors;

  /// 그라데이션 색이 바뀌는 위치(0~1). 안 주면 균등 분할.
  /// 위쪽에서만 짧게 번지고 나머지는 평평하게 두고 싶을 때 쓴다.
  final List<double>? gradientStops;

  const AppPalette({
    required this.id,
    required this.label,
    required this.emoji,
    required this.light,
    required this.mid,
    required this.primary,
    required this.dark,
    this.onGradient = Colors.white,
    this.overlay = Colors.white,
    this.gradientColors,
    this.gradientStops,
  });

  /// 화면 배경 그라데이션(위 → 아래)
  List<Color> get gradient => gradientColors ?? [light, primary, dark];

  /// 밝은 배경 테마인지 (글자를 어둡게 써야 하는 테마)
  bool get isLight => onGradient != Colors.white;
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
      // 채팅 화면과 같은 톤의 밝은 무채색. 배경이 밝으니 글자는 진하게 간다.
      light: Color(0xFFC4C4C4), // 달력 오늘 표시 등 옅은 강조
      mid: Color(0xFF9E9E9E),
      primary: Color(0xFF616161), // 버튼·아이콘 (흰 글씨가 올라감)
      dark: Color(0xFF424242), // 어두운 다이얼로그 바탕
      onGradient: Color(0xFF242424),
      overlay: Colors.black,
      // 바탕은 #F5F5F5 하나로 평평하게 두고, 맨 위에만 회색이 살짝 번진다.
      gradientColors: [Color(0xFFD9D9D9), Color(0xFFF5F5F5), Color(0xFFF5F5F5)],
      gradientStops: [0.0, 0.22, 1.0],
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
  static List<double>? get gradientStops => p.gradientStops;
  static Color get onGradient => p.onGradient;
  static Color get overlay => p.overlay;
  static bool get isLight => p.isLight;

  /// 배경 위 글자색을 흐리게 (부제·보조 문구용)
  static Color onGradientAlpha(double a) => p.onGradient.withValues(alpha: a);

  /// 배경 위 반투명 패널색.
  /// 밝은 테마는 검정을 깔기 때문에 같은 투명도면 훨씬 진해 보인다. 그래서 옅게 낮춘다.
  static Color overlayAlpha(double a) =>
      p.overlay.withValues(alpha: p.isLight ? a * 0.35 : a);

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

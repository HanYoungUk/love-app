import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 왼쪽 대화 목록 한 줄.
class FakeChat {
  final String name;
  final String initials;

  /// 마지막 메시지 미리보기. 내가 보낸 것이면 '나: ' 로 시작.
  final String preview;

  /// 오늘이면 '오후 4:13', 이전 날이면 '08-03' 형식.
  final String time;

  /// 아바타 원 색
  final Color color;

  /// 0이면 읽음, 1 이상이면 안 읽은 개수(이름 굵게 + 배지)
  final int unread;

  /// true면 이 줄이 실제 대화. 흰 배경 + 왼쪽 보라 바로 선택 표시되고,
  /// 미리보기·시각은 실제 마지막 메시지로 덮어쓴다. 목록에 딱 하나만 둔다.
  final bool isReal;

  const FakeChat({
    required this.name,
    required this.initials,
    required this.preview,
    required this.time,
    required this.color,
    this.unread = 0,
    this.isReal = false,
  });

  FakeChat copyWith({
    String? name,
    String? initials,
    String? preview,
    String? time,
    Color? color,
    int? unread,
    bool? isReal,
  }) =>
      FakeChat(
        name: name ?? this.name,
        initials: initials ?? this.initials,
        preview: preview ?? this.preview,
        time: time ?? this.time,
        color: color ?? this.color,
        unread: unread ?? this.unread,
        isReal: isReal ?? this.isReal,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'initials': initials,
        'preview': preview,
        'time': time,
        'color': color.toARGB32(),
        'unread': unread,
        'isReal': isReal,
      };

  static FakeChat fromJson(Map<String, dynamic> j) => FakeChat(
        name: j['name'] as String? ?? '',
        initials: j['initials'] as String? ?? '?',
        preview: j['preview'] as String? ?? '',
        time: j['time'] as String? ?? '',
        color: Color(j['color'] as int? ?? 0xFF6264A7),
        unread: j['unread'] as int? ?? 0,
        isReal: j['isReal'] as bool? ?? false,
      );

  /// 'Kim, KiWook' → 'KK' / '주간회의' → '주'
  static String initialsFor(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return n[0].toUpperCase();
  }
}

// ── 아바타 색 팔레트 (Teams 기본색) ─────────────────────────
const fakeAvatarPalette = <Color>[
  Color(0xFF6264A7), // purple
  Color(0xFF0078D4), // blue
  Color(0xFF038387), // teal
  Color(0xFF8764B8), // violet
  Color(0xFFCA5010), // orange
  Color(0xFF498205), // green
  Color(0xFFC239B3), // magenta
  Color(0xFF986F0B), // gold
  Color(0xFF005B70), // navy
  Color(0xFFA4262C), // red
];

/// 저장된 값이 없을 때 쓰는 기본 목록.
const defaultFakeChatList = <FakeChat>[
  FakeChat(
    name: 'TF_Inside sales',
    initials: 'J',
    preview: '나: 공유 감사합니다 !!',
    time: '오전 9:19',
    color: Color(0xFF6264A7),
  ),
  FakeChat(
    name: 'Kim, KiWook',
    initials: 'KK',
    preview: '나: 파일 보냄',
    time: '08-03',
    color: Color(0xFF0078D4),
  ),
  FakeChat(
    name: 'Nam, HunHee',
    initials: 'NH',
    preview: '나: 오더라인개수만 딱 볼 수 잇…',
    time: '오전 11:24',
    color: Color(0xFF038387),
  ),
  FakeChat(
    name: 'Oh, DongShin',
    initials: 'OD',
    preview: '나: 좋습니다..',
    time: '오전 9:18',
    color: Color(0xFF8764B8),
  ),
  FakeChat(
    name: 'Jung, Hyunseok',
    initials: 'HJ',
    preview: '나: 남자가 끊이질 않습니다',
    time: '오후 4:14',
    color: Color(0xFFCA5010),
  ),
  FakeChat(
    name: 'Girls',
    initials: 'G',
    preview: 'Park, Somi: 넵',
    time: '오후 1:44',
    color: Color(0xFF498205),
  ),
  // 실제 대화 (미리보기·시각은 마지막 메시지로 자동 갱신)
  FakeChat(
    name: 'Choi, Jiyeon',
    initials: 'JC',
    preview: '나: 감사함돠',
    time: '오후 4:13',
    color: Color(0xFF6264A7),
    isReal: true,
  ),
  FakeChat(
    name: 'Jo, SeongWon',
    initials: 'SJ',
    preview: '제말이요..',
    time: '08-03',
    color: Color(0xFFC239B3),
  ),
  FakeChat(
    name: 'Park, Somi',
    initials: 'SP',
    preview: '나: 파이팅.. !',
    time: '08-03',
    color: Color(0xFF0078D4),
  ),
];

const _fallback = FakeChat(
  name: 'Chat',
  initials: 'C',
  preview: '',
  time: '',
  color: Color(0xFF6264A7),
  isReal: true,
);

/// 대화 목록 보관소.
///
/// 기기 로컬(SharedPreferences, 웹은 localStorage)에만 저장한다.
/// 서버를 거치지 않으므로 상대방 기기에는 영향이 없고, PC/폰이 각각 따로 유지된다.
/// 테마(AppTheme)·알림(NotifPref)과 같은 방식.
class FakeChatStore {
  static const _key = 'fake_chat_list_v1';

  /// 값이 바뀌면 채팅 화면이 통째로 다시 그려진다.
  static final ValueNotifier<List<FakeChat>> current =
      ValueNotifier(defaultFakeChatList);

  static List<FakeChat> get list => current.value;

  /// 실제 대화 줄 (헤더 이름·아바타, 말풍선 아바타의 출처)
  static FakeChat get real {
    for (final c in list) {
      if (c.isReal) return c;
    }
    return list.isNotEmpty ? list.first : _fallback;
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .whereType<Map<String, dynamic>>()
          .map(FakeChat.fromJson)
          .toList();
      if (parsed.isNotEmpty) current.value = parsed;
    } catch (_) {}
  }

  static Future<void> save(List<FakeChat> value) async {
    current.value = List.unmodifiable(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(value.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// 기본 목록으로 되돌리기
  static Future<void> reset() async {
    current.value = defaultFakeChatList;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

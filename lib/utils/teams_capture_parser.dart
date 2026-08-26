import 'package:flutter/material.dart';
import '../data/fake_chat_list.dart';
import 'teams_ocr.dart';

/// OCR 결과(단어 + 좌표)를 대화 목록으로 해석한다.
///
/// 캡쳐 한 줄의 생김새:
///   [아바타]  이름                    시각
///             마지막 메시지
///
/// 글자만 보지 않고 **x좌표**를 쓴다. 실제 캡쳐로 확인한 규칙:
///  - 아바타 안 글자는 본문보다 훨씬 왼쪽에 찍힌다 → 본문 왼쪽 경계 밖은 버린다
///  - 시각은 항상 오른쪽 끝 열에 있다 → 그 열의 숫자 단어를 시각으로 본다
///  - 한글은 글자마다 따로 잡히므로 단어 사이 간격(4px 이상)으로 띄어쓰기를 복원한다
class TeamsCaptureParser {
  /// '9:19' / '918' / '0803' / '08-03' (뒤에 쉼표·마침표가 붙기도 한다)
  static final _timeWord = RegExp(
      r'^(\d{1,2}\s*[:：]\s*\d{2}|\d{3,4}|\d{1,2}\s*[-/]\s*\d{1,2})[,.]?$');
  static final _period = RegExp(r'^(오전|오후|AM|PM)$', caseSensitive: false);

  static List<FakeChat> parse(OcrResult res) {
    final lines = [...res.lines]..sort((a, b) => a.y0.compareTo(b.y0));
    if (lines.isEmpty) return [];

    // 오른쪽 시각 열의 시작 위치
    var rightEdge = 0.0;
    for (final l in lines) {
      for (final w in l.words) {
        if (w.x1 > rightEdge) rightEdge = w.x1;
      }
    }
    final timeZone = rightEdge * 0.6;
    final avatarRight = _avatarRight(lines, res.width.toDouble());

    final out = <FakeChat>[];
    for (var i = 0; i < lines.length; i++) {
      final head = lines[i];

      // 오른쪽 열에 시각처럼 생긴 단어가 있어야 대화 줄의 머리줄이다
      final right = head.words.where((w) => w.x0 > timeZone).toList();
      OcrWord? timeWord;
      OcrWord? periodWord;
      for (final w in right) {
        if (timeWord == null && _timeWord.hasMatch(w.text)) timeWord = w;
        if (periodWord == null && _period.hasMatch(w.text)) periodWord = w;
      }
      if (timeWord == null) continue;

      final name = _titleFirst(_join(
              _stripAvatar(head.words.where((w) => w.x0 <= timeZone).toList(),
                  avatarRight))
          .replaceAll(RegExp(r'[,\s]+$'), '')
          .trim());
      if (name.length < 2) continue;

      // 바로 아래 줄이 시각을 안 가지고 있으면 미리보기로 묶는다.
      // (아바타 때문에 줄 상자가 겹칠 수 있어 간격이 음수여도 허용)
      var preview = '';
      if (i + 1 < lines.length) {
        final next = lines[i + 1];
        final nextHasTime = next.words
            .any((w) => w.x0 > timeZone && _timeWord.hasMatch(w.text));
        if (!nextHasTime &&
            next.y0 > head.y0 &&
            next.y0 - head.y1 < head.height * 2.2) {
          preview = _cleanPreview(_join(_stripAvatar(next.words, avatarRight)));
          i++; // 미리보기 줄 소비
        }
      }

      out.add(FakeChat(
        name: name,
        initials: FakeChat.initialsFor(name),
        preview: preview,
        time: _normTime(periodWord?.text, timeWord.text),
        color: _avatarColor(avatarRight, head.centerY, out.length),
      ));
    }
    return out;
  }

  /// 본문 왼쪽 경계. 4글자 이상 단어들의 최소 x0을 기준으로 삼는다.
  static double _avatarRight(List<OcrLine> lines, double width) {
    var minLong = double.infinity;
    for (final l in lines) {
      for (final w in l.words) {
        if (w.text.length >= 4 && w.x0 < minLong) minLong = w.x0;
      }
    }
    return minLong.isFinite ? minLong - 3 : width * 0.15;
  }

  static List<OcrWord> _stripAvatar(List<OcrWord> words, double avatarRight) {
    final w = [...words];
    while (w.length >= 2 && w.first.x1 < avatarRight) {
      w.removeAt(0);
    }
    return w;
  }

  /// 단어 사이 간격으로 띄어쓰기를 되살린다 (한글은 글자 단위로 잡힌다)
  static String _join(List<OcrWord> words) {
    final b = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      if (i > 0 && words[i].x0 - words[i - 1].x1 >= 4) b.write(' ');
      b.write(words[i].text);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 왼쪽 여백을 훑어 아바타 원의 색을 집는다.
  ///
  /// 흰 배경·원 안의 흰 글자는 채도로 걸러내고, 남은 색 중 **가장 많이 나온 색**을
  /// 쓴다. (가장 진한 색을 쓰면 초록 접속표시 점이나 경계 픽셀에 끌려간다)
  /// 접속표시 점은 원의 오른쪽 아래에 있으므로 줄 중앙 높이만 훑으면 거의 안 걸린다.
  static Color _avatarColor(double avatarRight, double y, int fallbackIndex) {
    final counts = <int, int>{};
    final sums = <int, List<int>>{};
    for (final dy in const [-4, 0, 4]) {
      for (var x = 2.0; x < avatarRight; x += 1) {
        final argb =
            TeamsOcr.pixelAt(x.round(), (y + dy).round()).toARGB32();
        final r = (argb >> 16) & 0xFF;
        final g = (argb >> 8) & 0xFF;
        final b = argb & 0xFF;
        final maxv = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minv = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (maxv - minv < 30) continue; // 흰 배경·흰 글자·회색
        // 4비트로 뭉뚱그려 같은 색으로 세고, 평균값을 따로 모은다
        final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        counts[key] = (counts[key] ?? 0) + 1;
        final s = sums.putIfAbsent(key, () => [0, 0, 0, 0]);
        s[0] += r;
        s[1] += g;
        s[2] += b;
        s[3] += 1;
      }
    }
    if (counts.isEmpty) {
      return fakeAvatarPalette[fallbackIndex % fakeAvatarPalette.length];
    }
    var bestKey = counts.keys.first;
    for (final e in counts.entries) {
      if (e.value > counts[bestKey]!) bestKey = e.key;
    }
    final s = sums[bestKey]!;
    return Color.fromARGB(255, s[0] ~/ s[3], s[1] ~/ s[3], s[2] ~/ s[3]);
  }

  /// '918' → '9:18', '0803' → '08-03', '9:19,' → '9:19'
  static String _normTime(String? period, String digits) {
    var d = digits
        .replaceAll(RegExp(r'[,.]$'), '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('：', ':');
    final p = (period != null && _period.hasMatch(period)) ? period : '';

    final dash = RegExp(r'^(\d{1,2})[-/](\d{1,2})$').firstMatch(d);
    if (dash != null) {
      return '${dash.group(1)!.padLeft(2, '0')}-${dash.group(2)!.padLeft(2, '0')}';
    }
    // 오전/오후가 없는 네 자리는 날짜(MMDD)로 본다
    if (RegExp(r'^\d{4}$').hasMatch(d) && p.isEmpty) {
      return '${d.substring(0, 2)}-${d.substring(2)}';
    }
    if (RegExp(r'^\d{3,4}$').hasMatch(d)) {
      d = '${d.substring(0, d.length - 2)}:${d.substring(d.length - 2)}';
    }
    return p.isEmpty ? d : '$p $d';
  }

  /// 첫 단어가 소문자로 시작하면 대문자로 (OCR이 'Oh,'를 'oh,'로 읽는다)
  static String _titleFirst(String s) {
    if (s.isEmpty) return s;
    final first = s[0];
    if (RegExp(r'[a-z]').hasMatch(first)) {
      return first.toUpperCase() + s.substring(1);
    }
    return s;
  }

  /// '나 . 파일 보냄' → '나: 파일 보냄'
  static String _cleanPreview(String s) => s
      .replaceFirst(RegExp(r'^(나|Lt|4)\s*[:;.]\s*'), '나: ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

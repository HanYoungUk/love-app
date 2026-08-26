import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';

@JS('loveOcr.run')
external JSPromise<JSString> _run(JSString dataUrl, JSFunction onProgress);

@JS('loveOcr.pixel')
external int _pixel(int x, int y);

@JS('loveOcr')
external JSAny? get _loveOcr;

/// 브라우저 안에서 캡쳐 이미지를 읽는다 (tesseract.js).
/// 서버·API 키 없이 기기에서만 처리된다.
class TeamsOcr {
  static bool get isSupported => _loveOcr != null;

  /// [bytes] 이미지 → 인식된 줄 목록(JSON) 반환.
  /// [onProgress]는 0.0~1.0 진행률과 상태 문자열을 받는다.
  static Future<OcrResult> recognize(
    Uint8List bytes, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    final cb = ((JSString msg) {
      final parts = msg.toDart.split('|');
      if (parts.length == 2) {
        onProgress?.call(parts[0], double.tryParse(parts[1]) ?? 0);
      }
    }).toJS;
    final raw = await _run(dataUrl.toJS, cb).toDart;
    final map = jsonDecode(raw.toDart) as Map<String, dynamic>;
    return OcrResult.fromJson(map);
  }

  /// 인식에 쓴 이미지의 (x, y) 픽셀 색
  static Color pixelAt(int x, int y) => Color(_pixel(x, y));
}

class OcrWord {
  final String text;
  final double x0, x1;
  const OcrWord(this.text, this.x0, this.x1);
}

class OcrLine {
  final List<OcrWord> words;
  final double x0, y0, x1, y1;
  final double conf;
  const OcrLine(this.words, this.x0, this.y0, this.x1, this.y1, this.conf);

  double get centerY => (y0 + y1) / 2;
  double get height => y1 - y0;
}

class OcrResult {
  final int width;
  final int height;
  final List<OcrLine> lines;
  const OcrResult(this.width, this.height, this.lines);

  static OcrResult fromJson(Map<String, dynamic> j) => OcrResult(
        (j['width'] as num?)?.toInt() ?? 0,
        (j['height'] as num?)?.toInt() ?? 0,
        ((j['lines'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((l) => OcrLine(
                  ((l['words'] as List?) ?? [])
                      .whereType<Map<String, dynamic>>()
                      .map((w) => OcrWord(
                            w['text'] as String? ?? '',
                            (w['x0'] as num?)?.toDouble() ?? 0,
                            (w['x1'] as num?)?.toDouble() ?? 0,
                          ))
                      .toList(),
                  (l['x0'] as num?)?.toDouble() ?? 0,
                  (l['y0'] as num?)?.toDouble() ?? 0,
                  (l['x1'] as num?)?.toDouble() ?? 0,
                  (l['y1'] as num?)?.toDouble() ?? 0,
                  (l['conf'] as num?)?.toDouble() ?? 0,
                ))
            .toList(),
      );
}

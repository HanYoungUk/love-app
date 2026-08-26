import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 비웹(안드로이드/윈도우)에서는 OCR을 쓰지 않는다.
class TeamsOcr {
  static bool get isSupported => false;

  static Future<OcrResult> recognize(
    Uint8List bytes, {
    void Function(String status, double progress)? onProgress,
  }) async =>
      const OcrResult(0, 0, []);

  static Color pixelAt(int x, int y) => const Color(0xFF6264A7);
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
}

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:http/http.dart' as http;

Future<String> downloadFile(String url, String filename) async {
  final res = await http.get(Uri.parse(url));
  final blob = html.Blob([res.bodyBytes]);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: blobUrl)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(blobUrl);
  return filename;
}

Future<String> downloadAll(
  List<({String url, String filename})> files, {
  void Function(int done, int total)? onProgress,
}) async {
  final total = files.length;

  // 1단계: 모든 파일 병렬 fetch
  final blobs = await Future.wait(
    files.map((f) async {
      final res = await http.get(Uri.parse(f.url));
      return (
        blobUrl: html.Url.createObjectUrlFromBlob(html.Blob([res.bodyBytes])),
        filename: f.filename,
      );
    }),
  );

  // 2단계: 브라우저 다운로드 트리거만 순서대로 (짧은 간격)
  for (int i = 0; i < blobs.length; i++) {
    html.AnchorElement(href: blobs[i].blobUrl)
      ..setAttribute('download', blobs[i].filename)
      ..click();
    html.Url.revokeObjectUrl(blobs[i].blobUrl);
    onProgress?.call(i + 1, total);
    if (i < blobs.length - 1) {
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  return '$total장';
}

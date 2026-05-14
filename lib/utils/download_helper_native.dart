import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<String> downloadFile(String url, String filename) async {
  final res = await http.get(Uri.parse(url));
  final dir = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(res.bodyBytes);
  return file.path;
}

Future<String> downloadAll(
  List<({String url, String filename})> files, {
  void Function(int done, int total)? onProgress,
}) async {
  final dir = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  String lastPath = dir.path;

  // 네이티브는 병렬로 fetch + 저장
  await Future.wait(
    files.asMap().entries.map((entry) async {
      final res = await http.get(Uri.parse(entry.value.url));
      final file = File('${dir.path}/${entry.value.filename}');
      await file.writeAsBytes(res.bodyBytes);
      lastPath = file.path;
      onProgress?.call(entry.key + 1, files.length);
    }),
  );

  return lastPath;
}

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<String> downloadFile(String url, String filename) async {
  final res = await http.get(Uri.parse(url));
  final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(res.bodyBytes);
  return file.path;
}

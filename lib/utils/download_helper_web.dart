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

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openUrl(String url) async {
  final newWindow = html.window.open(url, '_blank');
  if (newWindow == null) {
    // 모바일 브라우저 팝업 차단 → 같은 탭으로 이동
    html.window.location.assign(url);
  }
  return true;
}

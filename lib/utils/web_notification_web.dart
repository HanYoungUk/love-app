import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// 웹: 브라우저 Notification API로 OS 네이티브 토스트(우측 하단)를 띄운다.
/// 크롬이 켜져 있으면 최소화/다른 탭/다른 프로그램 상태에서도 표시된다.
/// 권한이 'granted'가 아니면 조용히 무시한다.
void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
}) {
  try {
    if (web.Notification.permission != 'granted') return;
    final hasTag = tag != null && tag.isNotEmpty;
    final options = web.NotificationOptions(
      body: body,
      icon: icon ?? '',
      // 같은 tag면 새 토스트가 기존 것을 '교체'(쌓이지 않음).
      // renotify=true라야 교체될 때도 다시 알림(소리/팝업)이 난다.
      tag: tag ?? '',
      renotify: hasTag,
    );
    final n = web.Notification(title, options);
    // 알림 클릭 시 창을 앞으로 가져오고 알림 닫기
    n.onclick = ((web.Event _) {
      web.window.focus();
      n.close();
    }).toJS;
  } catch (_) {}
}

/// 이 탭이 다시 포그라운드(보이고+포커스)로 돌아올 때 콜백 실행.
/// 안 읽은 알림 카운트를 리셋하는 데 사용. 반환값은 해제 함수.
void Function() installForegroundListener(void Function() onForeground) {
  void handler(web.Event _) {
    if (web.document.visibilityState == 'visible' && web.document.hasFocus()) {
      onForeground();
    }
  }

  final jsHandler = handler.toJS;
  web.window.addEventListener('focus', jsHandler);
  web.document.addEventListener('visibilitychange', jsHandler);
  return () {
    web.window.removeEventListener('focus', jsHandler);
    web.document.removeEventListener('visibilitychange', jsHandler);
  };
}

bool webNotificationGranted() {
  try {
    return web.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

/// 이 페이지(탭)를 사용자가 실제로 보고 있는지(보이고 + 포커스됨).
/// 백그라운드 탭/최소화/다른 창에 포커스면 false.
bool webPageFocused() {
  try {
    return web.document.visibilityState == 'visible' && web.document.hasFocus();
  } catch (_) {
    return false;
  }
}

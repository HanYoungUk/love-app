// 비웹 플랫폼: 네이티브 OS 알림 미지원 → no-op.
void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
}) {}

bool webNotificationGranted() => false;

bool webPageFocused() => true;

void Function() installForegroundListener(void Function() onForeground) =>
    () {};

// 웹: 브라우저/OS 네이티브 알림(우측 하단 토스트)을 띄움.
// 비웹: 아무것도 하지 않음 (stub).
// 조건부 import로 플랫폼별 구현을 선택한다.
export 'web_notification_stub.dart'
    if (dart.library.js_interop) 'web_notification_web.dart';

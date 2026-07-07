// 웹: 문서 전체에 드래그앤드롭/붙여넣기(Ctrl+V) 리스너를 설치해 이미지 바이트를 받음.
// 비웹: 아무것도 하지 않음 (stub).
// 조건부 import로 플랫폼별 구현을 선택한다.
export 'image_drop_paste_stub.dart'
    if (dart.library.js_interop) 'image_drop_paste_web.dart';

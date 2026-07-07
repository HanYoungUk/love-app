import 'dart:typed_data';

typedef ImageDropCallback = void Function(Uint8List bytes);
typedef DragStateCallback = void Function(bool dragging);

/// 비웹 플랫폼: 아무것도 하지 않고 no-op 해제 함수를 반환.
void Function() installImageDropPaste({
  required ImageDropCallback onImage,
  DragStateCallback? onDragState,
}) =>
    () {};

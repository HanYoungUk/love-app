import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

typedef ImageDropCallback = void Function(Uint8List bytes);
typedef DragStateCallback = void Function(bool dragging);

/// 웹: 문서 전체에 dragover/dragleave/drop/paste 리스너를 설치.
/// - drop: 브라우저가 파일을 새 탭으로 여는 기본동작을 preventDefault로 막고 파일을 읽음
/// - paste: 클립보드(스크린샷 Ctrl+V) 이미지도 동일하게 처리
/// 반환값은 리스너 해제 함수.
void Function() installImageDropPaste({
  required ImageDropCallback onImage,
  DragStateCallback? onDragState,
}) {
  void handleFile(web.File file) {
    if (!file.type.startsWith('image/')) return;
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final res = reader.result;
      if (res == null) return;
      final bytes = (res as JSArrayBuffer).toDart.asUint8List();
      onImage(bytes);
    }).toJS;
    reader.readAsArrayBuffer(file);
  }

  void handleFileList(web.FileList? files) {
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final f = files.item(i);
      if (f != null) handleFile(f);
    }
  }

  final onDragOver = ((web.Event e) {
    e.preventDefault();
    onDragState?.call(true);
  }).toJS;

  final onDragLeave = ((web.Event e) {
    onDragState?.call(false);
  }).toJS;

  final onDrop = ((web.Event e) {
    e.preventDefault();
    onDragState?.call(false);
    handleFileList((e as web.DragEvent).dataTransfer?.files);
  }).toJS;

  final onPaste = ((web.Event e) {
    handleFileList((e as web.ClipboardEvent).clipboardData?.files);
  }).toJS;

  web.document.addEventListener('dragover', onDragOver);
  web.document.addEventListener('dragleave', onDragLeave);
  web.document.addEventListener('drop', onDrop);
  web.document.addEventListener('paste', onPaste);

  return () {
    web.document.removeEventListener('dragover', onDragOver);
    web.document.removeEventListener('dragleave', onDragLeave);
    web.document.removeEventListener('drop', onDrop);
    web.document.removeEventListener('paste', onPaste);
  };
}

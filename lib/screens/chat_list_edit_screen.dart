import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/fake_chat_list.dart';
import '../utils/image_drop_paste.dart';
import '../utils/teams_capture_parser.dart';
import '../utils/teams_ocr.dart';

// 편집 화면도 Teams 톤을 유지한다 (열려 있어도 튀지 않게)
const _brand = Color(0xFF5B5FC7);
const _text = Color(0xFF242424);
const _subText = Color(0xFF616161);
const _border = Color(0xFFE0E0E0);
const _bg = Color(0xFFF5F5F5);

/// 왼쪽 대화 목록을 직접 고치는 화면.
/// 저장하면 기기 로컬(SharedPreferences)에만 반영된다.
class ChatListEditScreen extends StatefulWidget {
  const ChatListEditScreen({super.key});

  /// 이 화면이 열려 있는 동안엔 채팅 화면이 붙여넣기 이미지를 가로채지 않게 한다.
  /// (안 그러면 캡쳐를 붙여넣는 순간 상대에게 사진이 전송된다)
  static bool isOpen = false;

  @override
  State<ChatListEditScreen> createState() => _ChatListEditScreenState();
}

class _ChatListEditScreenState extends State<ChatListEditScreen> {
  late List<FakeChat> _items;
  bool _dirty = false;

  // 캡쳐 인식 상태
  void Function()? _disposeDropPaste;
  bool _ocrBusy = false;
  String _ocrStatus = '';
  double _ocrProgress = 0;

  @override
  void initState() {
    super.initState();
    _items = List<FakeChat>.from(FakeChatStore.list);
    ChatListEditScreen.isOpen = true;
    // 화면 어디서나 Ctrl+V / 드래그앤드롭으로 캡쳐를 받는다 (웹 전용, 비웹은 no-op)
    _disposeDropPaste = installImageDropPaste(onImage: _runOcr);
  }

  @override
  void dispose() {
    ChatListEditScreen.isOpen = false;
    _disposeDropPaste?.call();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── 캡쳐 → OCR → 목록 채우기 ────────────────────────────
  Future<void> _pickCapture() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    await _runOcr(await img.readAsBytes());
  }

  Future<void> _runOcr(Uint8List bytes) async {
    if (_ocrBusy) return;
    // 편집 시트나 대화상자가 떠 있는 동안 붙여넣으면, 목록이 통째로 바뀌는 사이
    // 시트가 예전 줄 번호로 값을 써서 엉뚱한 줄이 덮이거나 범위를 벗어난다.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!TeamsOcr.isSupported) {
      _toast('캡쳐 인식은 웹에서만 됩니다');
      return;
    }
    setState(() {
      _ocrBusy = true;
      _ocrStatus = '준비 중';
      _ocrProgress = 0;
    });
    try {
      final res = await TeamsOcr.recognize(bytes, onProgress: (status, p) {
        if (!mounted) return;
        setState(() {
          _ocrStatus = _statusText(status);
          _ocrProgress = p;
        });
      });
      final parsed = TeamsCaptureParser.parse(res);
      if (!mounted) return;
      if (parsed.isEmpty) {
        _toast('대화를 찾지 못했어요. 목록 부분만 잘라서 다시 시도해보세요');
        return;
      }
      final merged = _mergeKeepingReal(parsed);
      final ok = await _confirmReplace(merged.length);
      if (ok != true || !mounted) return;
      setState(() {
        _items = merged;
        _dirty = true;
      });
      _toast('${merged.length}개를 채웠어요. 틀린 곳은 탭해서 고치세요');
    } catch (e) {
      _toast('인식 실패: $e');
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  String _statusText(String s) {
    if (s.contains('loading language')) return '한글 데이터 준비 중';
    if (s.contains('initializing')) return '엔진 준비 중';
    if (s.contains('recognizing')) return '글자 읽는 중';
    return '처리 중';
  }

  /// 인식 결과에 '기본 대화' 줄을 반드시 살려서 합친다.
  List<FakeChat> _mergeKeepingReal(List<FakeChat> parsed) {
    final oldIndex = _items.indexWhere((c) => c.isReal);
    if (oldIndex < 0) return parsed;
    final oldReal = _items[oldIndex];

    final hit = parsed.indexWhere((c) => _looksSame(c.name, oldReal.name));
    final out = List<FakeChat>.from(parsed);
    if (hit >= 0) {
      // 이름이 인식된 경우: 이니셜·색은 쓰던 값을 유지
      out[hit] = out[hit].copyWith(
        name: oldReal.name,
        initials: oldReal.initials,
        color: oldReal.color,
        isReal: true,
      );
    } else {
      out.insert(oldIndex.clamp(0, out.length), oldReal);
    }
    return out;
  }

  /// OCR이 글자를 조금 틀려도 같은 사람으로 보게 한다.
  /// (실제로 'Choi, Jiyeon'이 'Chol, Jiyeon'으로 읽히는 것을 확인)
  static bool _looksSame(String a, String b) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[\s,._-]'), '');
    final x = norm(a), y = norm(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y || x.contains(y) || y.contains(x)) return true;
    // 길이가 비슷하면 오탈자 2글자까지 같은 이름으로 인정
    if ((x.length - y.length).abs() <= 2) {
      return _distance(x, y) <= 2;
    }
    return false;
  }

  /// 편집 거리 (Levenshtein)
  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  Future<bool?> _confirmReplace(int count) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: const Text('목록을 바꿀까요?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text('캡쳐에서 $count개를 읽었습니다. 지금 목록을 이걸로 교체합니다.\n'
              '(기본 대화 줄은 그대로 유지됩니다)'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소', style: TextStyle(color: _subText)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('교체',
                  style:
                      TextStyle(color: _brand, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  Future<void> _save() async {
    await FakeChatStore.save(_items);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text('저장하지 않고 나갈까요?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 편집', style: TextStyle(color: _subText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기',
                style: TextStyle(
                    color: Color(0xFFC4314B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // 새 줄 추가 → 바로 편집 시트
  Future<void> _add() async {
    final created = await _editRow(const FakeChat(
      name: '',
      initials: '',
      preview: '',
      time: '',
      color: Color(0xFF6264A7),
    ));
    if (created == null) return;
    setState(() {
      _items.add(created);
      _dirty = true;
    });
  }

  Future<void> _openRow(int index) async {
    if (index < 0 || index >= _items.length) return;
    // 줄 번호 대신 객체로 되찾는다. 편집하는 동안 목록이 바뀌어도 안전하게.
    final target = _items[index];
    final edited = await _editRow(target, canDelete: true);
    if (edited == null || !mounted) return;
    final index2 = _items.indexOf(target);
    if (index2 < 0) return; // 그 사이 사라진 줄
    setState(() {
      if (edited.name == ' delete') {
        _items.removeAt(index2);
      } else {
        _items[index2] = edited;
        // 실제 대화는 하나만 유지
        if (edited.isReal) {
          for (var i = 0; i < _items.length; i++) {
            if (i != index2 && _items[i].isReal) {
              _items[i] = _items[i].copyWith(isReal: false);
            }
          }
        }
      }
      _dirty = true;
    });
  }

  /// 한 줄 편집 시트. 삭제를 누르면 name 이 ' delete' 인 값을 돌려준다.
  Future<FakeChat?> _editRow(FakeChat src, {bool canDelete = false}) async {
    final nameCtrl = TextEditingController(text: src.name);
    final initialsCtrl = TextEditingController(text: src.initials);
    final previewCtrl = TextEditingController(text: src.preview);
    final timeCtrl = TextEditingController(text: src.time);
    var color = src.color;
    var unread = src.unread;
    var isReal = src.isReal;

    final result = await showModalBottomSheet<FakeChat>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _AvatarPreview(
                      initials: initialsCtrl.text.isEmpty
                          ? FakeChat.initialsFor(nameCtrl.text)
                          : initialsCtrl.text,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    const Text('대화 정보',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _text)),
                  ],
                ),
                const SizedBox(height: 16),
                _Field(
                  label: '이름',
                  controller: nameCtrl,
                  hint: 'Kim, KiWook',
                  onChanged: (v) => setSheet(() {}),
                ),
                _Field(
                  label: '이니셜 (비우면 이름에서 자동)',
                  controller: initialsCtrl,
                  hint: FakeChat.initialsFor(nameCtrl.text),
                  onChanged: (v) => setSheet(() {}),
                ),
                _Field(
                  label: '마지막 메시지',
                  controller: previewCtrl,
                  hint: '나: 확인했습니다',
                ),
                _Field(
                  label: '시간',
                  controller: timeCtrl,
                  hint: '오후 4:13 또는 08-03',
                  trailing: TextButton(
                    onPressed: () {
                      final now = DateTime.now();
                      final period = now.hour < 12 ? '오전' : '오후';
                      final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
                      timeCtrl.text =
                          '$period $h:${now.minute.toString().padLeft(2, '0')}';
                      setSheet(() {});
                    },
                    child: const Text('지금', style: TextStyle(color: _brand)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('아바타 색',
                    style: TextStyle(fontSize: 12.5, color: _subText)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in fakeAvatarPalette)
                      GestureDetector(
                        onTap: () => setSheet(() => color = c),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.toARGB32() == color.toARGB32()
                                  ? _text
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('안 읽음',
                        style: TextStyle(fontSize: 13.5, color: _text)),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          setSheet(() => unread = (unread - 1).clamp(0, 99)),
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 20, color: _subText),
                    ),
                    Text('$unread',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () =>
                          setSheet(() => unread = (unread + 1).clamp(0, 99)),
                      icon: const Icon(Icons.add_circle_outline,
                          size: 20, color: _subText),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _brand,
                  value: isReal,
                  onChanged: (v) => setSheet(() => isReal = v),
                  title: const Text('기본 대화',
                      style: TextStyle(fontSize: 13.5, color: _text)),
                  subtitle: const Text(
                    '이 줄이 실제 대화가 됩니다. 이름·아바타가 상단과 말풍선에도 적용되고,\n'
                    '마지막 메시지·시간은 자동으로 갱신됩니다.',
                    style: TextStyle(fontSize: 11.5, color: _subText),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canDelete)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(
                          sheetCtx,
                          src.copyWith(name: ' delete'),
                        ),
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Color(0xFFC4314B)),
                        label: const Text('삭제',
                            style: TextStyle(color: Color(0xFFC4314B))),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('취소', style: TextStyle(color: _subText)),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          Navigator.pop(sheetCtx);
                          return;
                        }
                        Navigator.pop(
                          sheetCtx,
                          FakeChat(
                            name: name,
                            initials: initialsCtrl.text.trim().isEmpty
                                ? FakeChat.initialsFor(name)
                                : initialsCtrl.text.trim(),
                            preview: previewCtrl.text,
                            time: timeCtrl.text.trim(),
                            color: color,
                            unread: unread,
                            isReal: isReal,
                          ),
                        );
                      },
                      child: const Text('확인'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 시트가 닫힌 뒤 입력창 정리 (안 하면 편집할 때마다 조금씩 쌓인다)
    nameCtrl.dispose();
    initialsCtrl.dispose();
    previewCtrl.dispose();
    timeCtrl.dispose();
    return result;
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text('기본 목록으로 되돌릴까요?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text('직접 넣은 내용은 사라집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: _subText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('되돌리기',
                style: TextStyle(
                    color: Color(0xFFC4314B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _items = List<FakeChat>.from(defaultFakeChatList);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          shape: const Border(bottom: BorderSide(color: _border)),
          leading: IconButton(
            icon: const Icon(Icons.close, color: _subText, size: 20),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await _confirmDiscard()) nav.pop();
            },
          ),
          title: const Text('채팅 목록',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: _text)),
          actions: [
            IconButton(
              tooltip: '기본값으로',
              onPressed: _resetAll,
              icon: const Icon(Icons.restart_alt, color: _subText, size: 20),
            ),
            TextButton(
              onPressed: _save,
              child: const Text('저장',
                  style:
                      TextStyle(color: _brand, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _brand,
          onPressed: _add,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('줄 추가', style: TextStyle(color: Colors.white)),
        ),
        body: Stack(
          children: [
            Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '탭하면 수정, 오른쪽 손잡이를 끌면 순서가 바뀝니다. 이 기기에만 저장됩니다.',
                    style: TextStyle(fontSize: 12, color: _subText),
                  ),
                  if (TeamsOcr.isSupported) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickCapture,
                          icon: const Icon(Icons.image_search,
                              size: 18, color: _brand),
                          label: const Text('캡쳐에서 불러오기',
                              style: TextStyle(color: _brand)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: Text(
                            'Ctrl+V로 붙여넣거나 이미지를 끌어다 놓아도 됩니다',
                            style: TextStyle(fontSize: 11.5, color: _subText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                itemCount: _items.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    _items.insert(newIndex, _items.removeAt(oldIndex));
                    _dirty = true;
                  });
                },
                itemBuilder: (context, i) {
                  final c = _items[i];
                  return Card(
                    // 위치가 아니라 항목 자체를 키로 (위치 기반이면 드래그 후 어긋난다)
                    key: ObjectKey(c),
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(
                          color: c.isReal ? _brand : _border,
                          width: c.isReal ? 1.4 : 1),
                    ),
                    child: ListTile(
                      onTap: () => _openRow(i),
                      leading: _AvatarPreview(
                          initials: c.initials, color: c.color, size: 34),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _text),
                            ),
                          ),
                          if (c.isReal)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _brand.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('기본',
                                  style:
                                      TextStyle(fontSize: 10, color: _brand)),
                            ),
                          if (c.unread > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC4314B),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text('${c.unread}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white)),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        c.preview.isEmpty ? '(내용 없음)' : c.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: _subText),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.time,
                              style: const TextStyle(
                                  fontSize: 11.5, color: _subText)),
                          const SizedBox(width: 6),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle,
                                color: _subText, size: 20),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
            ),
            // 인식 중 진행 표시
            if (_ocrBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Container(
                      width: 260,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_ocrStatus,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _text)),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _ocrProgress == 0 ? null : _ocrProgress,
                            backgroundColor: _border,
                            color: _brand,
                            minHeight: 5,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '처음 한 번은 인식 데이터를 받느라 조금 걸립니다',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: _subText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  const _AvatarPreview(
      {required this.initials, required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.trailing,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: _subText)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(fontSize: 14, color: _text),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle:
                        const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: _border)),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: _brand)),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

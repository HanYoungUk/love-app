import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../data/fake_chat_list.dart';
import '../utils/image_drop_paste.dart';
import 'chat_list_edit_screen.dart';
import '../utils/direct_chat_pref.dart';
import '../utils/notif_pref.dart';
import '../utils/open_url.dart';

// ── Teams 위장 스타일 상수 ──────────────────────────────────
const _tBrand = Color(0xFF5B5FC7); // Teams 보라 (선택 표시·강조)
const _tWindowBg = Color(0xFFF5F5F5); // 창 배경
const _tRail = Color(0xFFEBEBEB); // 왼쪽 아이콘 레일
const _tBorder = Color(0xFFE0E0E0);
const _tText = Color(0xFF242424);
const _tSubText = Color(0xFF616161);
const _tMineBubble = Color(0xFFE8EBFA); // 내 말풍선(연보라)
const _tTheirBubble = Color(0xFFF0F0F0); // 상대 말풍선(연회색)
const _tPresence = Color(0xFF6BB700); // 온라인 표시 초록
const _tHover = Color(0xFFEDEBE9); // 목록 줄에 마우스 올렸을 때

// 표시 이름·아바타는 목록에서 선택된 줄을 따라간다.
// (기본값은 isReal: true 인 줄 = 편집 화면의 '기본 대화')

/// 사이드바를 펼칠 최소 가로폭. 이보다 좁으면 채팅 패널만 보인다.
const _wideBreakpoint = 900.0;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  // 채팅 화면이 열려 있는 동안엔 OS 알림을 띄우지 않기 위한 전역 플래그
  static bool isOpen = false;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = FirebaseFirestore.instance;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  bool _sending = false;
  bool _uploading = false;
  bool _dragging = false;

  // 상대방이 마지막으로 읽은 시각 (이 시각 이후의 내 메시지는 '안 읽음')
  DateTime? _partnerLastRead;
  StreamSubscription? _readSub;

  // 새 메시지가 실제로 도착했을 때만 스크롤/읽음처리 (매 rebuild마다 돌면 깜빡임)
  String? _lastSeenMsgId;

  // 한 번에 불러오는 최근 메시지 수. 3일치를 통째로 받으면 수백~수천 건이라
  // 열 때마다 버벅인다. 최근 것만 받고 '더 보기'로 늘린다.
  static const _pageSize = 150;
  int _limit = _pageSize;

  // '더 보기'로 스트림을 갈아끼우는 찰나에 스피너가 번쩍이지 않게 직전 목록을 들고 있는다
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsCache = const [];
  bool get _hasMore => _docsCache.length >= _limit;

  // 읽음 표시 쓰기 과다 방지 (메시지마다 쓰면 상대 화면이 그때마다 다시 그려진다)
  DateTime _lastMarkRead = DateTime.fromMillisecondsSinceEpoch(0);

  // 아직 서버가 시각을 안 찍어준 내 메시지. 화면에만 잠깐 존재한다.
  // createdAt이 serverTimestamp라 서버 응답 전에는 null인데, null은 정렬상
  // 맨 앞으로 가버려서 limitToLast 창 밖으로 밀린다. 그래서 보내도 한 박자
  // 뒤에야 떴다. 카톡처럼 누르는 즉시 뜨게 하려고 화면 쪽에서 먼저 그린다.
  final List<_Pending> _pending = [];

  // 등장 연출은 '화면을 연 뒤에 새로 도착한' 메시지에만 준다.
  // 처음 불러온 150건까지 애니메이션하면 열자마자 우수수 쏟아져 더 어수선하다.
  bool _entranceArmed = false;
  final Set<String> _entered = {};

  // 지금 맨 아래를 보고 있는지. 위로 올려 옛 대화를 읽는 중이면 새 메시지가 와도
  // 끌어내리지 않고 '새 메시지 ↓' 버튼만 띄운다.
  bool _atBottom = true;
  int _newCount = 0;
  static const _bottomSlack = 150.0;

  // 왼쪽 목록의 실제 대화 줄에 표시할 마지막 메시지 (Teams처럼 목록도 살아있게)
  String? _lastPreview;
  String? _lastStamp;

  // 목록에서 눌러 고른 줄. null이면 실제 대화(isReal) 줄.
  // 대화 내용은 그대로 두고 상단 이름·아바타만 그 사람으로 바뀐다.
  int? _selectedRow;

  // 눌러서 안 읽음 표시를 지운 줄 (화면에서만, 저장 안 함)
  final Set<int> _readRows = {};

  /// 지금 화면에 이름·아바타로 쓰는 대화
  FakeChat get _viewChat {
    final list = FakeChatStore.list;
    final i = _selectedRow;
    if (i != null && i >= 0 && i < list.length) return list[i];
    return FakeChatStore.real;
  }

  /// 목록에서 실제 대화 줄의 위치 (선택 표시 기본값)
  int get _selectedIndex {
    final i = _selectedRow;
    if (i != null) return i;
    final real = FakeChatStore.list.indexWhere((c) => c.isReal);
    return real < 0 ? 0 : real;
  }

  // 메시지 스트림은 단 한 번만 생성. build()에서 만들면 setState마다 재구독되어
  // 로딩 스피너가 번쩍이며 화면이 깜빡인다. (깜빡임의 핵심 원인)
  late Stream<QuerySnapshot<Map<String, dynamic>>> _msgStream;

  // 입력 중 표시
  bool _partnerTyping = false;
  DateTime? _partnerTypingAt;
  StreamSubscription? _typingSub;
  Timer? _typingExpireTimer;
  DateTime _lastTypingWrite = DateTime.fromMillisecondsSinceEpoch(0);

  // 답장 대상 (null이면 일반 전송)
  Map<String, String?>? _replyingTo;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _readDocPath = ('settings', 'chatRead');
  static const _typingDocPath = ('settings', 'chatTyping');

  // 표시 이름은 위장용 이름을 쓴다 (이메일 노출 방지)
  String _nameOf(String? email, {bool isMine = false}) =>
      isMine ? '나' : _viewChat.name;

  // 웹 드래그앤드롭/붙여넣기 리스너 해제 함수
  void Function()? _disposeDropPaste;

  @override
  void initState() {
    super.initState();
    ChatScreen.isOpen = true; // 채팅 보는 동안 OS 알림 억제
    _msgStream = _makeStream();
    _listenRead();
    _markRead();
    _cleanupOldMessages();
    _listenTyping();
    _ctrl.addListener(_onTextChanged);
    _scrollCtrl.addListener(_onScroll);
    // 입력 중 표시는 일정 시간 갱신 없으면 사라지게 주기적 재평가
    _typingExpireTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _refreshTyping());
    // 웹: 문서 전체에 드래그앤드롭 + Ctrl+V 붙여넣기 이미지 수신 (비웹은 no-op)
    _disposeDropPaste = installImageDropPaste(
      // 목록 편집 화면이 위에 떠 있으면 그쪽이 캡쳐를 받으므로 여기선 무시
      onImage: (bytes) {
        if (ChatListEditScreen.isOpen) return;
        _uploadAndSendImage(bytes);
      },
      onDragState: (dragging) {
        if (ChatListEditScreen.isOpen) return;
        if (mounted && dragging != _dragging) {
          setState(() => _dragging = dragging);
        }
      },
    );
  }

  @override
  void dispose() {
    ChatScreen.isOpen = false;
    _setTyping(false); // 나갈 때 입력 중 표시 제거
    _disposeDropPaste?.call();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _readSub?.cancel();
    _typingSub?.cancel();
    _typingExpireTimer?.cancel();
    super.dispose();
  }

  /// 최근 _limit건만 구독. limitToLast는 orderBy가 있어야 쓸 수 있다.
  Stream<QuerySnapshot<Map<String, dynamic>>> _makeStream() => _db
      .collection('messages')
      .orderBy('createdAt')
      .limitToLast(_limit)
      .snapshots();

  void _loadMore() {
    setState(() {
      _limit += _pageSize;
      _msgStream = _makeStream();
    });
  }

  // ── 입력 중 표시 ──────────────────────────────────────────
  void _onTextChanged() {
    final now = DateTime.now();
    if (_ctrl.text.trim().isEmpty) {
      _setTyping(false);
    } else if (now.difference(_lastTypingWrite).inMilliseconds > 1500) {
      _lastTypingWrite = now;
      _setTyping(true);
    }
  }

  Future<void> _setTyping(bool typing) async {
    try {
      await _db.collection(_typingDocPath.$1).doc(_typingDocPath.$2).set(
        {_uid: typing ? FieldValue.serverTimestamp() : null},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  void _listenTyping() {
    _typingSub = _db
        .collection(_typingDocPath.$1)
        .doc(_typingDocPath.$2)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      DateTime? latest;
      data?.forEach((uid, value) {
        if (uid == _uid) return;
        if (value is Timestamp) {
          final t = value.toDate();
          if (latest == null || t.isAfter(latest!)) latest = t;
        }
      });
      _partnerTypingAt = latest;
      _refreshTyping();
    });
  }

  // 마지막 입력 신호가 6초 이내면 '입력 중'으로 간주
  void _refreshTyping() {
    final typing = _partnerTypingAt != null &&
        DateTime.now().difference(_partnerTypingAt!) <
            const Duration(seconds: 6);
    if (mounted && typing != _partnerTyping) {
      setState(() => _partnerTyping = typing);
    }
  }

  // 채팅 열 때마다 3일 지난 메시지 정리 (이미지면 Storage 파일도 삭제)
  Future<void> _cleanupOldMessages() async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 3)),
      );
      final old = await _db
          .collection('messages')
          .where('createdAt', isLessThan: cutoff)
          .get();
      if (old.docs.isEmpty) return;
      // 한 건씩 지우면 왕복이 건수만큼 늘어 채팅 열 때 그대로 멈춘다. 배치로 묶는다.
      final paths = <String>[];
      var batch = _db.batch();
      var n = 0;
      for (final doc in old.docs) {
        final imagePath = doc.data()['imagePath'] as String?;
        if (imagePath != null && imagePath.isNotEmpty) paths.add(imagePath);
        batch.delete(doc.reference);
        if (++n % 400 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      }
      if (n % 400 != 0) await batch.commit();
      for (final p in paths) {
        try {
          await FirebaseStorage.instance.ref(p).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  // settings/chatRead 문서의 { uid: Timestamp } 맵을 구독해
  // 나를 제외한 사용자(상대방)가 읽은 가장 최근 시각을 추적
  void _listenRead() {
    _readSub = _db
        .collection(_readDocPath.$1)
        .doc(_readDocPath.$2)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;
      DateTime? latest;
      data.forEach((uid, value) {
        if (uid == _uid) return;
        if (value is Timestamp) {
          final t = value.toDate();
          if (latest == null || t.isAfter(latest!)) latest = t;
        }
      });
      // 값이 실제로 바뀐 경우에만 rebuild (불필요한 깜빡임/연산 방지)
      if (mounted && latest != _partnerLastRead) {
        setState(() => _partnerLastRead = latest);
      }
    });
  }

  // 내가 채팅을 봤다는 표시 (상대방 메시지의 읽음 표시를 켜는 신호)
  Future<void> _markRead() async {
    // 메시지마다 쓰면 상대 화면이 그때마다 다시 그려진다. 3초에 한 번으로 묶는다.
    final now = DateTime.now();
    if (now.difference(_lastMarkRead) < const Duration(seconds: 3)) return;
    _lastMarkRead = now;
    try {
      await _db
          .collection(_readDocPath.$1)
          .doc(_readDocPath.$2)
          .set({_uid: FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    // 사용자 제스처 컨텍스트 안에서 즉시 포커스 유지 (await 뒤로 미루면 웹에서 풀림)
    _focusNode.requestFocus();
    _setTyping(false);
    final reply = _consumeReply();
    // 서버가 받은 문서가 스트림으로 돌아왔을 때 화면에 먼저 그려둔 것과
    // 같은 메시지임을 알아보려고 붙이는 표식
    final clientId = '${_uid}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _pending.add(_Pending(
        clientId: clientId,
        text: text,
        at: DateTime.now(),
        replyToText: reply['replyToText'] as String?,
        replyToSender: reply['replyToSender'] as String?,
      ));
    });
    _scrollToBottom();
    try {
      await _db.collection('messages').add({
        'type': 'text',
        'text': text,
        'senderUid': _uid,
        'senderEmail': FirebaseAuth.instance.currentUser?.email,
        'clientId': clientId,
        'createdAt': FieldValue.serverTimestamp(),
        ...reply,
      });
    } catch (_) {
      // 실패 시 화면에서 걷어내고 입력 복원
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p.clientId == clientId));
      }
      _ctrl.text = text;
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        // 비동기 전송 후에도 커서가 살아있도록 한 번 더 보장
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }
  }

  // 사진 선택(갤러리) → 전송
  Future<void> _pickAndSendImage() async {
    if (_uploading) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    await _uploadAndSendImage(bytes);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // 답장 대상이 있으면 메시지에 넣을 필드를 만들고 답장 상태를 비움
  Map<String, dynamic> _consumeReply() {
    final r = _replyingTo;
    if (r == null) return {};
    if (mounted) setState(() => _replyingTo = null);
    return {
      'replyToText': r['preview'],
      'replyToSender': r['sender'],
    };
  }

  // 공용: 바이트 → Storage 업로드 → 이미지 메시지 전송
  Future<void> _uploadAndSendImage(Uint8List bytes) async {
    setState(() => _uploading = true);
    final reply = _consumeReply();
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'chat/${_uid}_$ts.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await _db.collection('messages').add({
        'type': 'image',
        'text': '',
        'imageUrl': url,
        'imagePath': path,
        'senderUid': _uid,
        'senderEmail': FirebaseAuth.instance.currentUser?.email,
        'createdAt': FieldValue.serverTimestamp(),
        ...reply,
      });
    } catch (e) {
      if (mounted) {
        _toast('파일 전송 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // 메시지 삭제 (이미지면 Storage 파일도 함께 삭제)
  Future<void> _deleteMessage(String docId, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text('메시지 삭제',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('이 메시지를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: _tSubText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제',
                style:
                    TextStyle(color: Color(0xFFC4314B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.collection('messages').doc(docId).delete();
      final imagePath = data['imagePath'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(imagePath).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static const _reactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  // 메시지 길게 누르면(데스크톱은 우클릭): 이모지 반응 / 답장 / (내 메시지면) 삭제
  void _showMessageMenu(String docId, Map<String, dynamic> data, bool isMine) {
    final myReaction =
        (data['reactions'] as Map<String, dynamic>?)?[_uid] as String?;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // 이모지 반응 줄
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _reactionEmojis.map((e) {
                final selected = myReaction == e;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _react(docId, e);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected
                          ? _tBrand.withValues(alpha: 0.12)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 20, color: _tBorder),
            ListTile(
              leading: const Icon(Icons.reply, color: _tBrand),
              title: const Text('회신'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _startReply(data);
              },
            ),
            if (isMine)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Color(0xFFC4314B)),
                title: const Text('삭제',
                    style: TextStyle(color: Color(0xFFC4314B))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _deleteMessage(docId, data);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 이모지 반응 토글 (같은 이모지 다시 누르면 해제)
  Future<void> _react(String docId, String emoji) async {
    final ref = _db.collection('messages').doc(docId);
    try {
      final snap = await ref.get();
      final reactions =
          (snap.data()?['reactions'] as Map<String, dynamic>?) ?? {};
      if (reactions[_uid] == emoji) {
        await ref.set({
          'reactions': {_uid: FieldValue.delete()}
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'reactions': {_uid: emoji}
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // 답장 시작 → 입력바 위에 미리보기 표시
  void _startReply(Map<String, dynamic> data) {
    final isImage = data['imageUrl'] != null;
    final preview = isImage ? '사진' : (data['text'] as String? ?? '');
    setState(() {
      _replyingTo = {
        'preview': preview,
        'sender': _nameOf(data['senderEmail'] as String?,
            isMine: data['senderUid'] == _uid),
      };
    });
    _focusNode.requestFocus();
  }

  /// 맨 아래 근처인지 계속 추적. 다시 아래에 닿으면 '새 메시지' 표시를 지운다.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final p = _scrollCtrl.position;
    final atBottom = p.pixels <= _bottomSlack; // 역순이라 아래쪽이 0
    if (atBottom == _atBottom) return;
    _atBottom = atBottom;
    if (atBottom && _newCount > 0) {
      if (mounted) setState(() => _newCount = 0);
    } else if (mounted) {
      setState(() {}); // 버튼 표시 조건이 바뀔 수 있어 한 번 다시 그린다
    }
  }

  /// 목록이 역순(reverse)이라 '맨 아래'는 offset 0이다.
  /// 예전엔 정방향이라 maxScrollExtent를 목표로 삼았는데, 그 값이 말풍선/사진이
  /// 그려질 때마다 바뀌어서 화면이 위아래로 튀었다. 0은 절대 안 변한다.
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (!animate) {
        _scrollCtrl.jumpTo(0);
        return;
      }
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // 이미지 전체화면 보기
  void _openImage(String url) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  String _timeText(DateTime d) {
    final h = d.hour;
    final period = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:${d.minute.toString().padLeft(2, '0')}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // 목록용 시각: 오늘이면 '오후 4:13', 이전 날이면 '08-03' (Teams 표기)
  String _stampText(DateTime d) => _sameDay(DateTime.now(), d)
      ? _timeText(d)
      : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dateText(DateTime d) {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final now = DateTime.now();
    if (_sameDay(now, d)) return '오늘';
    if (_sameDay(now.subtract(const Duration(days: 1)), d)) return '어제';
    return '${d.year}년 ${d.month}월 ${d.day}일 ${week[d.weekday - 1]}요일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tWindowBg,
      // 목록을 고치면 (헤더 이름·아바타 포함) 바로 다시 그려진다
      body: SafeArea(
        child: ValueListenableBuilder<List<FakeChat>>(
          valueListenable: FakeChatStore.current,
          builder: (context, _, __) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 넓은 화면에서만 왼쪽 레일 + 대화 목록 (위장 완성도용)
                    if (wide) const _TeamsRail(),
                    if (wide)
                      _TeamsChatList(
                        realPreview: _lastPreview,
                        realTime: _lastStamp,
                        selectedIndex: _selectedIndex,
                        readRows: _readRows,
                        onSelect: (i) => setState(() {
                          _selectedRow = i;
                          _readRows.add(i);
                        }),
                      ),
                    Expanded(child: _buildChatPane(wide)),
                  ],
                ),
                // 드래그 중 안내 오버레이
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: _tBrand.withValues(alpha: 0.12),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _tBrand),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file, color: _tBrand, size: 20),
                                SizedBox(width: 10),
                                Text('여기에 놓으면 파일이 첨부됩니다',
                                    style: TextStyle(
                                        color: _tBrand,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          ),
        ),
      ),
    );
  }

  // 대화 목록 편집 화면 열기 (헤더의 ⋯)
  Future<void> _openListEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatListEditScreen()),
    );
    // 목록이 바뀌면 줄 번호가 어긋나므로 선택을 기본(실제 대화)으로 되돌린다
    if (!mounted) return;
    setState(() {
      _selectedRow = null;
      _readRows.clear();
    });
  }

  // ── 오른쪽 채팅 패널 ─────────────────────────────────────
  Widget _buildChatPane(bool wide) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(wide),
          Expanded(
            child: Stack(
              children: [
                _buildMessageList(),
                if (_newCount > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Center(child: _newMsgPill()),
                  ),
              ],
            ),
          ),
          // '입력 중…'이 나타나고 사라질 때 대화 영역 높이가 확 바뀌면서 튀었다.
          // 상대가 전송하는 순간엔 (입력중 사라짐 + 새 말풍선 등장)이 겹쳐서 특히 심했다.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _partnerTyping
                ? Container(
                    key: const ValueKey('typingIndicator'),
                    width: double.infinity,
                    color: Colors.white,
                    padding:
                        const EdgeInsets.only(left: 28, bottom: 2, top: 2),
                    child: Text(
                      '${_viewChat.name} 님이 입력 중…',
                      style: const TextStyle(color: _tSubText, fontSize: 12),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
          if (_replyingTo != null) _buildReplyBar(),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// 위로 올려 보는 중에 새 메시지가 왔을 때 아래에 뜨는 알약 버튼
  Widget _newMsgPill() => Material(
        color: _tBrand,
        borderRadius: BorderRadius.circular(16),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _atBottom = true;
            setState(() => _newCount = 0);
            _scrollToBottom();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '새 메시지 $_newCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      );

  // 헤더: 아바타 + 이름 + 탭(채팅/공유/노트/요약) + 오른쪽 아이콘
  Widget _buildHeader(bool wide) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _tBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: '뒤로',
                icon: const Icon(Icons.chevron_left, color: _tSubText, size: 24),
              ),
              _Avatar(
                  initials: _viewChat.initials,
                  size: 32,
                  color: _viewChat.color),
              const SizedBox(width: 10),
              Text(
                _viewChat.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: _tText),
              ),
              if (wide) ...[
                const SizedBox(width: 16),
                const _HeaderTab(label: '채팅', selected: true),
                const _HeaderTab(label: '공유'),
                const _HeaderTab(label: '노트'),
                const _HeaderTab(label: '요약'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.add, color: _tSubText, size: 18),
                ),
              ],
              const Spacer(),
              if (wide) ...[
                const _HeaderIcon(icon: Icons.call_outlined),
                const _HeaderIcon(icon: Icons.person_add_alt),
                const _HeaderIcon(icon: Icons.search),
              ],
              // 알림 on/off (Teams 아이콘처럼 보이게 회색 계열 유지)
              ValueListenableBuilder<bool>(
                valueListenable: NotifPref.enabled,
                builder: (_, on, __) => IconButton(
                  tooltip: on ? '알림 켜짐 (탭하면 끔)' : '알림 꺼짐 (탭하면 켬)',
                  onPressed: () async {
                    await NotifPref.toggle();
                    _toast(NotifPref.enabled.value
                        ? '🔔 알림을 켰어요'
                        : '🔕 알림을 껐어요');
                  },
                  icon: Icon(
                    on
                        ? Icons.notifications_none
                        : Icons.notifications_off_outlined,
                    color: on ? _tSubText : const Color(0xFFBDBDBD),
                    size: 20,
                  ),
                ),
              ),
              // Teams의 ⋯ 자리 = 대화 목록 편집 + 바로 열기 설정
              PopupMenuButton<String>(
                tooltip: '옵션',
                position: PopupMenuPosition.under,
                icon: const Icon(Icons.more_horiz, color: _tSubText, size: 19),
                onSelected: (v) async {
                  if (v == 'list') {
                    await _openListEditor();
                    return;
                  }
                  // 자동로그인이 켜져 있으면 로그인 화면을 다시 못 보므로
                  // 여기서 끌 수 있어야 한다
                  await DirectChatPref.toggle();
                  if (!mounted) return;
                  _toast(DirectChatPref.enabled.value
                      ? '앞으로 켜면 바로 이 화면이 열려요'
                      : '앞으로 켜면 홈 화면이 먼저 열려요');
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'list',
                    child: Text('대화 목록', style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'direct',
                    child: Row(
                      children: [
                        Icon(
                          DirectChatPref.enabled.value
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: _tSubText,
                        ),
                        const SizedBox(width: 8),
                        const Text('채팅 바로 열기',
                            style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _msgStream,
      builder: (context, snapshot) {
        // 데이터가 아직 없을 때만 스피너. 일단 받은 뒤로는
        // 갱신 중에도 기존 목록을 유지해 깜빡이지 않게 한다.
        // '더 보기'로 스트림을 갈아끼우는 순간 잠깐 데이터가 빈다.
        // 그때 스피너로 되돌아가면 화면이 번쩍이므로 직전 목록을 그대로 쓴다.
        if (snapshot.hasData) _docsCache = snapshot.data!.docs;
        final docs = _docsCache;

        // 서버가 받아준 문서가 도착하면 화면에 먼저 그려뒀던 것을 걷어낸다.
        // 그 문서는 이미 화면에 있던 셈이니 등장 연출도 건너뛴다(두 번 뜨는 것 방지).
        if (_pending.isNotEmpty) {
          for (final d in docs) {
            final cid = d.data()['clientId'] as String?;
            if (cid == null) continue;
            if (_pending.any((p) => p.clientId == cid)) {
              _pending.removeWhere((p) => p.clientId == cid);
              _entered.add(d.id);
            }
          }
        }
        if (!snapshot.hasData && docs.isEmpty) {
          return const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _tBrand),
            ),
          );
        }
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  '대화를 시작해 보세요',
                  style: TextStyle(color: _tSubText, fontSize: 14, height: 1.6),
                ),
              ],
            ),
          );
        }

        // 마지막 메시지가 바뀐 경우(=새 메시지 도착)에만 한 번 처리.
        // _readSub의 setState로 인한 rebuild에서는 건너뛰어 루프/깜빡임 방지.
        final latestId = docs.last.id;
        if (latestId != _lastSeenMsgId) {
          final firstLoad = _lastSeenMsgId == null;
          _lastSeenMsgId = latestId;
          // 처음 받아온 목록은 그대로 그리고, 그 다음 메시지부터 연출을 켠다
          if (!firstLoad) _entranceArmed = true;

          // 왼쪽 목록에 보여줄 미리보기 계산 (내 메시지는 '나: ' 접두)
          final last = docs.last.data();
          final lastTime = (last['createdAt'] as Timestamp?)?.toDate();
          final body = last['imageUrl'] != null
              ? '사진'
              : (last['text'] as String? ?? '').replaceAll('\n', ' ');
          final mine = last['senderUid'] == _uid;
          final preview = mine ? '나: $body' : body;
          final stamp = lastTime != null ? _stampText(lastTime) : null;

          // 옛 대화를 읽는 중에 상대 메시지가 오면 끌어내리지 않는다.
          // (첫 진입과 내가 보낸 메시지는 항상 따라 내려간다)
          final follow = firstLoad || mine || _atBottom;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (follow) {
              _scrollToBottom(animate: !firstLoad);
              if (_newCount != 0) setState(() => _newCount = 0);
            } else {
              setState(() => _newCount++);
            }
            _markRead();
            if (mounted &&
                (preview != _lastPreview || stamp != _lastStamp)) {
              setState(() {
                _lastPreview = preview;
                _lastStamp = stamp;
              });
            }
          });
        }

        // SelectionArea: 메시지 텍스트를 드래그로 선택→복사 가능하게
        return SelectionArea(
          child: ListView.builder(
            controller: _scrollCtrl,
            // 역순: 최신 메시지가 offset 0. 새 메시지가 와도 보고 있던 위치가
            // 밀리지 않아 위아래로 튀는 현상이 사라진다.
            reverse: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            itemCount:
                _pending.length + docs.length + (_hasMore ? 1 : 0),
            itemBuilder: (_, slot) {
              // 역순이라 0번 칸이 화면 맨 아래 → 보내는 중인 메시지가 여기 온다
              if (slot < _pending.length) {
                return _buildPending(_pending.length - 1 - slot, docs);
              }
              final r = slot - _pending.length;
              // 역순이라 마지막 칸이 화면 맨 위 = '이전 대화 더 보기'
              if (r >= docs.length) return _moreButton();
              final i = docs.length - 1 - r;
              final data = docs[i].data();
              final docId = docs[i].id;
              final text = data['text'] as String? ?? '';
              final imageUrl = data['imageUrl'] as String?;
              final senderUid = data['senderUid'] as String?;
              final isMine = senderUid == _uid;
              final ts = data['createdAt'] as Timestamp?;
              final time = ts?.toDate();
              final reactions =
                  (data['reactions'] as Map<String, dynamic>?)
                          ?.values
                          .map((e) => e.toString())
                          .toList() ??
                      const [];
              final replyToText = data['replyToText'] as String?;
              final replyToSender = data['replyToSender'] as String?;

              // 날짜 구분선
              DateTime? prevTime;
              String? prevSender;
              if (i > 0) {
                final prev = docs[i - 1].data();
                prevTime = (prev['createdAt'] as Timestamp?)?.toDate();
                prevSender = prev['senderUid'] as String?;
              }
              final showDate = time != null &&
                  (i == 0 || prevTime == null || !_sameDay(prevTime, time));

              // Teams식 묶음: 같은 사람이 5분 안에 연달아 보내면 이름/시간/아바타 생략
              final sameGroup = !showDate &&
                  i > 0 &&
                  prevSender == senderUid &&
                  prevTime != null &&
                  time != null &&
                  time.difference(prevTime).inMinutes < 5;

              // 읽음 표시는 마지막 내 메시지에만 (Teams와 동일)
              final isLast = i == docs.length - 1;

              // 방금 도착한 메시지 한 건만 펼쳐지며 들어온다.
              // 맨 아래를 보고 있을 때만. 위에서 옛 대화를 읽는 중이면
              // 화면이 슬금슬금 밀리는 꼴이 되므로 연출 없이 넘긴다.
              final entering = _entranceArmed &&
                  isLast &&
                  !_entered.contains(docId);
              if (entering && !_atBottom) _entered.add(docId);

              final row = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDate) _TeamsDateRow(text: _dateText(time)),
                  _TeamsMsg(
                    sender: _nameOf(data['senderEmail'] as String?,
                        isMine: isMine),
                    text: text,
                    imageUrl: imageUrl,
                    isMine: isMine,
                    timeText: time != null ? _timeText(time) : '',
                    avatarInitials: _viewChat.initials,
                    avatarColor: _viewChat.color,
                    groupStart: !sameGroup,
                    // 내 마지막 메시지에만 전송/읽음 체크 표시
                    // (보내는 중인 게 아래에 더 있으면 그쪽이 마지막이다)
                    showReceipt: isMine && isLast && _pending.isEmpty,
                    read: _partnerLastRead != null &&
                        time != null &&
                        !_partnerLastRead!.isBefore(time),
                    reactions: reactions,
                    replyToText: replyToText,
                    replyToSender: replyToSender,
                    // 길게 누르기(모바일) / 우클릭(데스크톱) → 반응·회신·삭제
                    onLongPress: () => _showMessageMenu(docId, data, isMine),
                    onTapImage:
                        imageUrl != null ? () => _openImage(imageUrl) : null,
                  ),
                ],
              );

              if (entering && _atBottom) {
                return _Appear(
                  key: ValueKey('enter_$docId'),
                  onDone: () => _entered.add(docId),
                  child: row,
                );
              }
              return row;
            },
          ),
        );
      },
    );
  }

  /// 보내는 중인 내 메시지 한 건. 실제 말풍선과 똑같이 그리되
  /// 읽음 체크는 마지막 것에만 붙인다.
  Widget _buildPending(
    int idx,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final p = _pending[idx];

    // 바로 앞 메시지(보내는 중이거나 실제 메시지)가 5분 안의 내 것이면 묶는다
    DateTime? prevTime;
    bool prevMine = false;
    if (idx > 0) {
      prevTime = _pending[idx - 1].at;
      prevMine = true;
    } else if (docs.isNotEmpty) {
      final prev = docs.last.data();
      prevTime = (prev['createdAt'] as Timestamp?)?.toDate();
      prevMine = prev['senderUid'] == _uid;
    }
    final sameGroup = prevMine &&
        prevTime != null &&
        p.at.difference(prevTime).inMinutes < 5;

    return _Appear(
      key: ValueKey('pending_${p.clientId}'),
      onDone: () {},
      child: _TeamsMsg(
        sender: '나',
        text: p.text,
        isMine: true,
        timeText: _timeText(p.at),
        avatarInitials: _viewChat.initials,
        avatarColor: _viewChat.color,
        groupStart: !sameGroup,
        showReceipt: idx == _pending.length - 1,
        read: false,
        replyToText: p.replyToText,
        replyToSender: p.replyToSender,
      ),
    );
  }

  Widget _moreButton() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            style: TextButton.styleFrom(
              foregroundColor: _tBrand,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            child: const Text('이전 대화 더 보기', style: TextStyle(fontSize: 13)),
          ),
        ),
      );

  // 회신 미리보기 바
  Widget _buildReplyBar() {
    return Container(
      key: const ValueKey('replyPreview'),
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(4),
          border: const Border(left: BorderSide(color: _tBrand, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_replyingTo!['sender']} 님에게 회신',
                    style: const TextStyle(
                        color: _tBrand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _replyingTo!['preview'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _tSubText, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _replyingTo = null),
              icon: const Icon(Icons.close, color: _tSubText, size: 18),
              splashRadius: 16,
            ),
          ],
        ),
      ),
    );
  }

  // 입력 바: Teams처럼 테두리 박스 안에 입력창 + 아이콘 줄
  Widget _buildInputBar() {
    return Container(
      key: const ValueKey('inputBar'),
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 10 + MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD1D1D1)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(fontSize: 14, color: _tText),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '메시지를 입력하세요.',
                  hintStyle: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // 장식 아이콘 (서식/이모지) — 실제 동작은 첨부·전송만
            const _InputIcon(icon: Icons.text_format),
            const _InputIcon(icon: Icons.emoji_emotions_outlined),
            // 첨부(사진 전송)
            IconButton(
              onPressed: _pickAndSendImage,
              tooltip: '첨부',
              splashRadius: 18,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _tSubText),
                    )
                  : const Icon(Icons.attach_file, color: _tSubText, size: 20),
            ),
            const _InputIcon(icon: Icons.add),
            IconButton(
              onPressed: _send,
              tooltip: '보내기',
              splashRadius: 18,
              icon: Icon(
                Icons.send_outlined,
                color: _sending ? const Color(0xFFBDBDBD) : _tBrand,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 왼쪽 아이콘 레일 (장식) ─────────────────────────────────
class _TeamsRail extends StatelessWidget {
  const _TeamsRail();

  static const _icons = [
    Icons.notifications_none,
    Icons.calendar_today_outlined,
    Icons.grid_view,
    Icons.groups_outlined,
    Icons.call_outlined,
    Icons.chat_bubble, // 현재 위치(채팅)
    Icons.people_outline,
    Icons.cloud_outlined,
    Icons.hub_outlined,
    Icons.more_horiz,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      color: _tRail,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (var i = 0; i < _icons.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(
                _icons[i],
                size: 20,
                color: i == 5 ? _tBrand : const Color(0xFF616161),
              ),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Icon(Icons.add_box_outlined,
                size: 20, color: Color(0xFF616161)),
          ),
        ],
      ),
    );
  }
}

// ── 왼쪽 대화 목록 (data/fake_chat_list.dart 내용을 그대로 그림) ──
class _TeamsChatList extends StatelessWidget {
  /// 실제 대화(isReal) 줄에 덮어쓸 마지막 메시지. null이면 데이터 파일 값 사용.
  final String? realPreview;
  final String? realTime;

  /// 지금 선택된 줄
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// 클릭해서 읽음 처리한 줄 (안 읽음 배지를 지운다)
  final Set<int> readRows;

  const _TeamsChatList({
    this.realPreview,
    this.realTime,
    required this.selectedIndex,
    required this.onSelect,
    required this.readRows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: _tWindowBg,
        border: Border(right: BorderSide(color: _tBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 목록 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: const [
                Text('채팅',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: _tText)),
                Spacer(),
                Icon(Icons.more_horiz, size: 18, color: _tSubText),
                SizedBox(width: 14),
                Icon(Icons.search, size: 18, color: _tSubText),
                SizedBox(width: 14),
                Icon(Icons.edit_square, size: 18, color: _tSubText),
                SizedBox(width: 8),
              ],
            ),
          ),
          // 필터 칩
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 8, 10),
            child: Row(
              children: [
                _FilterChip(label: '읽지 않음'),
                SizedBox(width: 6),
                _FilterChip(label: '채팅'),
                SizedBox(width: 6),
                _FilterChip(label: '모임 채팅'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < FakeChatStore.list.length; i++)
                  _ChatRow(
                    chat: FakeChatStore.list[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                    // 지금 보고 있는 줄에 마지막 메시지로 미리보기/시각을 갱신.
                    // (고른 줄이 없으면 selectedIndex가 실제 대화 줄을 가리킨다)
                    previewOverride: i == selectedIndex ? realPreview : null,
                    timeOverride: i == selectedIndex ? realTime : null,
                    // 한 번 눌러본 줄은 안 읽음 배지를 없앤다 (Teams와 같게)
                    hideUnread: readRows.contains(i),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 0, 6),
                  child: Row(
                    children: [
                      Icon(Icons.expand_more, size: 16, color: _tSubText),
                      SizedBox(width: 4),
                      Text('채팅',
                          style: TextStyle(fontSize: 13, color: _tSubText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  const _FilterChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D1D1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF424242))),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final FakeChat chat;
  final bool selected;
  final VoidCallback? onTap;
  final String? previewOverride;
  final String? timeOverride;
  final bool hideUnread;
  const _ChatRow({
    required this.chat,
    this.selected = false,
    this.onTap,
    this.previewOverride,
    this.timeOverride,
    this.hideUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    final preview = previewOverride ?? chat.preview;
    final time = timeOverride ?? chat.time;
    final unread = hideUnread ? 0 : chat.unread;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          _Avatar(initials: chat.initials, size: 32, color: chat.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                unread > 0 ? FontWeight.w700 : FontWeight.w600,
                            color: _tText),
                      ),
                    ),
                    Text(time,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: unread > 0 ? _tBrand : _tSubText,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: unread > 0 ? _tText : _tSubText,
                          fontWeight:
                              unread > 0 ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    // 안 읽음 개수 배지
                    if (unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC4314B),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('$unread',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 목록 한 줄의 배경·선택 표시·클릭/호버 처리
class _RowShell extends StatefulWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  const _RowShell({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  State<_RowShell> createState() => _RowShellState();
}

class _RowShellState extends State<_RowShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? Colors.white
        : (_hover ? _tHover : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: widget.selected
                ? const Border(left: BorderSide(color: _tBrand, width: 3))
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ── 공통 소품 ──────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color color;
  const _Avatar({required this.initials, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w600),
            ),
          ),
          // 온라인(초록) 표시
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: _tPresence,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderTab extends StatelessWidget {
  final String label;
  final bool selected;
  const _HeaderTab({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: selected ? _tBrand : _tSubText,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 28,
            color: selected ? _tBrand : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  const _HeaderIcon({required this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(icon, size: 19, color: _tSubText),
      );
}

class _InputIcon extends StatelessWidget {
  final IconData icon;
  const _InputIcon({required this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Icon(icon, size: 20, color: _tSubText),
      );
}

// 날짜 구분선 (가로선 + 가운데 날짜)
class _TeamsDateRow extends StatelessWidget {
  final String text;
  const _TeamsDateRow({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: _tBorder, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: _tSubText)),
          ),
          const Expanded(child: Divider(color: _tBorder, height: 1)),
        ],
      ),
    );
  }
}

/// 보내는 중인 내 메시지 (서버 응답 전까지만 화면에 존재)
class _Pending {
  final String clientId;
  final String text;
  final DateTime at;
  final String? replyToText;
  final String? replyToSender;
  const _Pending({
    required this.clientId,
    required this.text,
    required this.at,
    this.replyToText,
    this.replyToSender,
  });
}

/// 새 메시지가 '툭' 나타나지 않고 자리를 만들며 들어오게 한다.
///
/// 목록이 역순이라 이 위젯이 높이 0에서 자라는 동안 위쪽 말풍선들이
/// 그만큼 부드럽게 밀려 올라간다. 스크롤을 건드리지 않으므로
/// 예전처럼 위아래로 튀지 않는다.
class _Appear extends StatefulWidget {
  final Widget child;
  final VoidCallback onDone;
  const _Appear({super.key, required this.child, required this.onDone});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  /// 자리를 만드는 속도. 툭 튀어나오지 않게 빠르게 시작해 천천히 멎는다.
  /// 이 값이 커지는 동안 위쪽 말풍선들이 그만큼 밀려 올라간다.
  late final Animation<double> _size =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  /// 자리가 어느 정도 생긴 뒤에 색이 차야 '아래에서 떠오르는' 느낌이 난다.
  /// 처음부터 진하게 켜지면 그냥 나타난 것처럼 보인다.
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.15, 0.75, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // axisAlignment: -1 → 말풍선 윗변이 입력창 바로 위에서 시작해 위로 올라온다.
    // (1로 두면 제자리에서 위쪽만 벗겨지듯 드러나 어색하다)
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: -1,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

// ── 메시지 1건 (Teams 말풍선) ────────────────────────────────
class _TeamsMsg extends StatefulWidget {
  final String sender;
  final String text;
  final String? imageUrl;
  final bool isMine;
  final String timeText;

  /// 묶음의 첫 메시지면 true → 이름/시간/아바타를 그린다.
  final bool groupStart;

  /// 전송/읽음 체크를 그릴지 (내 마지막 메시지에만)
  final bool showReceipt;
  final bool read;

  final List<String> reactions;
  final String? replyToText;
  final String? replyToSender;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapImage;

  /// 상대 말풍선 왼쪽 아바타 (목록에서 고른 사람)
  final String avatarInitials;
  final Color avatarColor;

  const _TeamsMsg({
    required this.sender,
    required this.text,
    this.imageUrl,
    required this.isMine,
    required this.timeText,
    required this.avatarInitials,
    required this.avatarColor,
    this.groupStart = true,
    this.showReceipt = false,
    this.read = false,
    this.reactions = const [],
    this.replyToText,
    this.replyToSender,
    this.onLongPress,
    this.onTapImage,
  });

  @override
  State<_TeamsMsg> createState() => _TeamsMsgState();
}

class _TeamsMsgState extends State<_TeamsMsg> {
  final List<TapGestureRecognizer> _linkRecognizers = [];

  static const double _avatarSize = 28;
  static const double _gutter = 38; // 아바타(28) + 간격(10)

  // http(s):// 또는 www. 로 시작하는 URL 감지
  static final RegExp _urlReg =
      RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false);

  @override
  void dispose() {
    _disposeLinkRecognizers();
    super.dispose();
  }

  void _disposeLinkRecognizers() {
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
  }

  // URL이 있으면 탭하면 열리는 파란 링크로, 없으면 일반 텍스트로 렌더링
  Widget _linkText(String body, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _urlReg.allMatches(body)) {
      if (m.start > last) {
        spans.add(TextSpan(text: body.substring(last, m.start)));
      }
      var url = m.group(0)!;
      var trailing = '';
      // URL 끝에 붙은 문장부호/괄호는 링크에서 제외
      while (url.isNotEmpty && '.,!?)]}'.contains(url[url.length - 1])) {
        trailing = url[url.length - 1] + trailing;
        url = url.substring(0, url.length - 1);
      }
      if (url.isEmpty) {
        spans.add(TextSpan(text: m.group(0)));
        last = m.end;
        continue;
      }
      final href = url.startsWith('http') ? url : 'https://$url';
      final rec = TapGestureRecognizer()..onTap = () => openUrl(href);
      _linkRecognizers.add(rec);
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(
          color: Color(0xFF0F6CBD),
          decoration: TextDecoration.underline,
        ),
        recognizer: rec,
      ));
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      last = m.end;
    }
    if (last < body.length) spans.add(TextSpan(text: body.substring(last)));
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  /// 썸네일은 크기를 고정한다.
  /// 예전엔 maxWidth/maxHeight만 줘서 사진이 다 받아지는 순간 높이가 확 바뀌었고,
  /// 그때마다 목록 전체가 밀려 화면이 위아래로 튀었다.
  /// cacheWidth로 원본(수천 px)을 그대로 디코드하지 않게 해 렉도 줄인다.
  Widget _imageContent() => GestureDetector(
        onTap: widget.onTapImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 260,
            height: 200,
            child: Image.network(
              widget.imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: 520,
              gaplessPlayback: true,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const ColoredBox(color: _tHover),
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: _tHover,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 22, color: _tSubText),
                ),
              ),
            ),
          ),
        ),
      );

  // 회신 인용 블록 (말풍선 안 위쪽)
  Widget _quote() => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(3),
          border: Border(
              left: BorderSide(
                  color: _tBrand.withValues(alpha: 0.6), width: 2.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.replyToSender ?? '',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: _tSubText)),
            Text(
              widget.replyToText ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _tSubText),
            ),
          ],
        ),
      );

  Widget _bubble() {
    return Container(
      padding: widget.imageUrl != null
          ? const EdgeInsets.all(6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMine ? _tMineBubble : _tTheirBubble,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyToText != null) _quote(),
          if (widget.imageUrl != null)
            _imageContent()
          else
            _linkText(
              widget.text,
              const TextStyle(fontSize: 14.5, color: _tText, height: 1.4),
            ),
        ],
      ),
    );
  }

  // 반응 칩 (말풍선 아래 살짝 겹치게)
  Widget _reactionChip() => Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _tBorder),
        ),
        child: Text(widget.reactions.join(' '),
            style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    // 이전 빌드에서 만든 링크 제스처를 정리하고 새로 생성
    _disposeLinkRecognizers();

    final maxBubble = MediaQuery.of(context).size.width * 0.62;

    final column = Column(
      crossAxisAlignment:
          widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 묶음 첫 메시지에만 이름/시간 줄
        if (widget.groupStart)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: widget.isMine
                ? Text(widget.timeText,
                    style: const TextStyle(fontSize: 11.5, color: _tSubText))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.sender,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _tText)),
                      const SizedBox(width: 6),
                      Text(widget.timeText,
                          style:
                              const TextStyle(fontSize: 11.5, color: _tSubText)),
                    ],
                  ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubble),
          child: Column(
            crossAxisAlignment: widget.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _bubble(),
              if (widget.reactions.isNotEmpty) _reactionChip(),
            ],
          ),
        ),
      ],
    );

    final row = Row(
      mainAxisAlignment:
          widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!widget.isMine)
          SizedBox(
            width: _gutter,
            child: widget.groupStart
                ? Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _Avatar(
                        initials: widget.avatarInitials,
                        size: _avatarSize,
                        color: widget.avatarColor),
                  )
                : null,
          ),
        Flexible(child: column),
        // 전송/읽음 체크 (Teams는 마지막 보낸 메시지 오른쪽 아래)
        if (widget.isMine)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: SizedBox(
              width: 14,
              // 안 읽었을 때 눈에 띄고, 읽으면 옅어진다
              child: widget.showReceipt
                  ? Icon(
                      widget.read
                          ? Icons.check_circle_outline
                          : Icons.check_circle,
                      size: 13,
                      color: widget.read ? const Color(0xFFB0B0B0) : _tBrand,
                    )
                  : null,
            ),
          ),
      ],
    );

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onLongPress, // 데스크톱 우클릭
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // 묶음 사이는 넓게, 묶음 안은 좁게 (Teams 리듬)
        padding: EdgeInsets.only(top: widget.groupStart ? 10 : 3, bottom: 1),
        child: row,
      ),
    );
  }
}

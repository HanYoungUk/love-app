import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/image_drop_paste.dart';
import '../utils/notif_pref.dart';
import '../utils/open_url.dart';

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

  // 상대방이 마지막으로 읽은 시각 (이 시각 이후의 내 메시지는 '안 읽음' → 1 표시)
  DateTime? _partnerLastRead;
  StreamSubscription? _readSub;

  // 새 메시지가 실제로 도착했을 때만 스크롤/읽음처리 (매 rebuild마다 돌면 깜빡임)
  String? _lastSeenMsgId;

  // 메시지 스트림은 단 한 번만 생성. build()에서 만들면 setState마다 재구독되어
  // 로딩 스피너가 번쩍이며 화면이 깜빡인다. (깜빡임의 핵심 원인)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _msgStream;

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

  // 이메일 → 표시 이름 (gksdud9685@loveapp.com → gksdud9685)
  String _nameOf(String? email) =>
      (email ?? '상대방').replaceAll('@loveapp.com', '');

  // 웹 드래그앤드롭/붙여넣기 리스너 해제 함수
  void Function()? _disposeDropPaste;

  @override
  void initState() {
    super.initState();
    ChatScreen.isOpen = true; // 채팅 보는 동안 OS 알림 억제
    _msgStream =
        _db.collection('messages').orderBy('createdAt').snapshots();
    _listenRead();
    _markRead();
    _cleanupOldMessages();
    _listenTyping();
    _ctrl.addListener(_onTextChanged);
    // 입력 중 표시는 일정 시간 갱신 없으면 사라지게 주기적 재평가
    _typingExpireTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _refreshTyping());
    // 웹: 문서 전체에 드래그앤드롭 + Ctrl+V 붙여넣기 이미지 수신 (비웹은 no-op)
    _disposeDropPaste = installImageDropPaste(
      onImage: (bytes) => _uploadAndSendImage(bytes),
      onDragState: (dragging) {
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
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _readSub?.cancel();
    _typingSub?.cancel();
    _typingExpireTimer?.cancel();
    super.dispose();
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

  // 채팅 열 때마다 2주(14일) 지난 메시지 정리 (이미지면 Storage 파일도 삭제)
  Future<void> _cleanupOldMessages() async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 14)),
      );
      final old = await _db
          .collection('messages')
          .where('createdAt', isLessThan: cutoff)
          .get();
      for (final doc in old.docs) {
        final imagePath = doc.data()['imagePath'] as String?;
        await doc.reference.delete();
        if (imagePath != null && imagePath.isNotEmpty) {
          try {
            await FirebaseStorage.instance.ref(imagePath).delete();
          } catch (_) {}
        }
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

  // 내가 채팅을 봤다는 표시 (상대방 메시지의 1을 없애는 신호)
  Future<void> _markRead() async {
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
    try {
      await _db.collection('messages').add({
        'type': 'text',
        'text': text,
        'senderUid': _uid,
        'senderEmail': FirebaseAuth.instance.currentUser?.email,
        'createdAt': FieldValue.serverTimestamp(),
        ...reply,
      });
    } catch (_) {
      // 실패 시 입력 복원
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
        _toast('사진 전송 실패: $e');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('메시지 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('이 메시지를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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

  // 메시지 길게 누르면: 이모지 반응 / 답장 / (내 메시지면) 삭제
  void _showMessageMenu(String docId, Map<String, dynamic> data, bool isMine) {
    final myReaction =
        (data['reactions'] as Map<String, dynamic>?)?[_uid] as String?;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          ? const Color(0xFFE91E63).withValues(alpha: 0.15)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 20),
            ListTile(
              leading: const Icon(Icons.reply, color: Color(0xFFE91E63)),
              title: const Text('답장'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _startReply(data);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('삭제', style: TextStyle(color: Colors.red)),
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
        'sender': _nameOf(data['senderEmail'] as String?),
      };
    });
    _focusNode.requestFocus();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      // 첫 진입은 카톡처럼 즉시 맨 아래로(애니메이션 X), 이후 새 메시지는 부드럽게
      if (!animate) {
        _scrollCtrl.jumpTo(target);
        return;
      }
      _scrollCtrl.animateTo(
        target,
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

  String _dateText(DateTime d) {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    return '${d.year}년 ${d.month}월 ${d.day}일 ${week[d.weekday - 1]}요일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
            children: [
              // 헤더 (주식 채팅방 제목처럼 위장)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E2E2)),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios,
                          color: Color(0xFF333333), size: 18),
                    ),
                    const Spacer(),
                    // 알림 on/off 종 버튼
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
                          on ? Icons.notifications_active : Icons.notifications_off,
                          color: on
                              ? const Color(0xFF2962FF)
                              : const Color(0xFFBBBBBB),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 메시지 목록 (엑셀 격자 배경 + 셀 텍스트로 위장)
              Expanded(
                child: Container(
                  color: Colors.white,
                  // 배경에 엑셀 격자무늬, 그 위에 메시지 목록
                  child: Stack(
                    children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _msgStream,
                      builder: (context, snapshot) {
                        // 데이터가 아직 없을 때만 스피너. 일단 받은 뒤로는
                        // 갱신 중에도 기존 목록을 유지해 깜빡이지 않게 한다.
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: Color(0xFFE91E63)),
                          );
                        }
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('💌', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  '아직 대화가 없어요\n첫 메시지를 보내보세요!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                    height: 1.6,
                                  ),
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
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToBottom(animate: !firstLoad);
                            _markRead();
                          });
                        }

                        // SelectionArea: 메시지 텍스트를 드래그로 선택→복사 가능하게
                        return SelectionArea(
                          child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
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
                            bool showDate = false;
                            if (time != null) {
                              if (i == 0) {
                                showDate = true;
                              } else {
                                final prevTs =
                                    docs[i - 1].data()['createdAt'] as Timestamp?;
                                final prev = prevTs?.toDate();
                                if (prev == null || !_sameDay(prev, time)) {
                                  showDate = true;
                                }
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDate && time != null)
                                  _SheetDateRow(text: _dateText(time)),
                                _SheetMsg(
                                  sender: _nameOf(data['senderEmail'] as String?),
                                  text: text,
                                  imageUrl: imageUrl,
                                  isMine: isMine,
                                  timeText: time != null ? _timeText(time) : '',
                                  // 내 메시지인데 상대가 아직 안 읽었으면 1 표시
                                  unread: isMine &&
                                      (_partnerLastRead == null ||
                                          time == null ||
                                          _partnerLastRead!.isBefore(time)),
                                  reactions: reactions,
                                  replyToText: replyToText,
                                  replyToSender: replyToSender,
                                  // 길게 누르면 반응/답장/삭제 메뉴
                                  onLongPress: () =>
                                      _showMessageMenu(docId, data, isMine),
                                  onTapImage: imageUrl != null
                                      ? () => _openImage(imageUrl)
                                      : null,
                                ),
                              ],
                            );
                          },
                          ),
                        );
                      },
                        ),
                      ],
                    ),
                  ),
                ),

              // 입력 중 표시
              if (_partnerTyping)
                Container(
                  key: const ValueKey('typingIndicator'),
                  width: double.infinity,
                  color: Colors.white.withValues(alpha: 0.95),
                  padding: const EdgeInsets.only(left: 24, bottom: 4, top: 2),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '상대가 입력 중…',
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ),

              // 답장 미리보기 바
              if (_replyingTo != null)
                Container(
                  key: const ValueKey('replyPreview'),
                  width: double.infinity,
                  color: Colors.white.withValues(alpha: 0.95),
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 32,
                        color: const Color(0xFFE91E63),
                        margin: const EdgeInsets.only(right: 10),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_replyingTo!['sender']}에게 답장',
                              style: const TextStyle(
                                  color: Color(0xFFE91E63),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _replyingTo!['preview'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _replyingTo = null),
                        icon: Icon(Icons.close, color: Colors.grey.shade500, size: 20),
                      ),
                    ],
                  ),
                ),

              // 입력 바 (엑셀/주식창처럼 밋밋하게 위장)
              Container(
                key: const ValueKey('inputBar'),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
                ),
                padding: EdgeInsets.fromLTRB(
                    8, 4, 8, 4 + MediaQuery.of(context).viewInsets.bottom),
                child: Row(
                  children: [
                    // 사진 전송 버튼 (밋밋하게)
                    GestureDetector(
                      onTap: _pickAndSendImage,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _uploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF888888)),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined,
                                color: Color(0xFF888888), size: 22),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF222222)),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '메시지 입력',
                          hintStyle: TextStyle(color: Color(0xFF999999), fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _send,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.send, color: Color(0xFF2962FF), size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
              ),
              // 드래그 중 안내 오버레이
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: const Color(0xFFE91E63).withValues(alpha: 0.18),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate,
                                  color: Color(0xFFE91E63)),
                              SizedBox(width: 10),
                              Text('여기에 놓으면 사진 전송',
                                  style: TextStyle(
                                      color: Color(0xFFE91E63),
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
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

// ── 엑셀 격자 위장 채팅 스타일 ───────────────────────────────
const _gridLine = Color(0xFFE3E3E3); // 격자선(연회색)
const _myCellColor = Color(0xFFFEF7D4); // 내 메시지 셀(연노랑)
const _myCellBorder = Color(0xFFF2E6A8); // 내 메시지 셀 테두리
const _partnerText = Color(0xFF1F4E79); // 상대 메시지 글자(진파랑)
const _timeColor = Color(0xFFB0B0B0); // 시간 글자(연회색)

// 배경 엑셀 격자무늬 (셀처럼 보이는 가로/세로 선)
class _GridPainter extends CustomPainter {
  const _GridPainter();
  static const double _cw = 92; // 셀 가로
  static const double _ch = 26; // 셀 세로
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _gridLine
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += _cw) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _ch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 날짜 구분 행
class _SheetDateRow extends StatelessWidget {
  final String text;
  const _SheetDateRow({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          color: Colors.white,
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: _timeColor),
          ),
        ),
      ),
    );
  }
}

// 메시지 1건 = 격자 위의 셀 텍스트 (말풍선 없음 / 엑셀처럼)
class _SheetMsg extends StatefulWidget {
  final String sender;
  final String text;
  final String? imageUrl;
  final bool isMine;
  final String timeText;
  final bool unread;
  final List<String> reactions;
  final String? replyToText;
  final String? replyToSender;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapImage;

  const _SheetMsg({
    required this.sender,
    required this.text,
    this.imageUrl,
    required this.isMine,
    required this.timeText,
    this.unread = false,
    this.reactions = const [],
    this.replyToText,
    this.replyToSender,
    this.onLongPress,
    this.onTapImage,
  });

  @override
  State<_SheetMsg> createState() => _SheetMsgState();
}

class _SheetMsgState extends State<_SheetMsg> {
  final List<TapGestureRecognizer> _linkRecognizers = [];

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
  Widget _linkText(String line, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _urlReg.allMatches(line)) {
      if (m.start > last) {
        spans.add(TextSpan(text: line.substring(last, m.start)));
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
          color: Color(0xFF1A73E8),
          decoration: TextDecoration.underline,
        ),
        recognizer: rec,
      ));
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  // 본문을 줄 단위 셀로 분리 (엑셀 한 줄=한 셀 느낌)
  List<String> get _lines =>
      widget.text.split('\n').where((l) => l.isNotEmpty).toList();

  Widget _imageCell() => GestureDetector(
        onTap: widget.onTapImage,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 150),
          child: Image.network(widget.imageUrl!, fit: BoxFit.cover),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // 이전 빌드에서 만든 링크 제스처를 정리하고 새로 생성
    _disposeLinkRecognizers();
    return GestureDetector(
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: widget.isMine ? _buildMine() : _buildPartner(),
      ),
    );
  }

  // 상대방: 왼쪽 "이름:" + 진파랑 텍스트 + 시간
  Widget _buildPartner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 2, bottom: 1),
          child: Text(
            '${widget.sender}:',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF222222)),
          ),
        ),
        if (widget.replyToText != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 1),
            child: Text(
              '↪ ${widget.replyToSender}: ${widget.replyToText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _timeColor),
            ),
          ),
        if (widget.imageUrl != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2, bottom: 2),
            child: _imageCell(),
          )
        else
          for (final line in _lines)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _linkText(
                line,
                const TextStyle(fontSize: 13.5, color: _partnerText),
              ),
            ),
        if (widget.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 1),
            child: Text(widget.reactions.join(' '),
                style: const TextStyle(fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 1, bottom: 2),
          child: Text(widget.timeText,
              style: const TextStyle(fontSize: 10.5, color: _timeColor)),
        ),
      ],
    );
  }

  // 나: 오른쪽 연노랑 셀 + 안읽음 1 + 시간
  Widget _buildMine() {
    Widget yellowCell(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: const BoxDecoration(
            color: _myCellColor,
            border: Border(
              top: BorderSide(color: _myCellBorder),
              bottom: BorderSide(color: _myCellBorder),
              left: BorderSide(color: _myCellBorder),
            ),
          ),
          child: child,
        );

    final cells = <Widget>[];
    if (widget.replyToText != null) {
      cells.add(yellowCell(Text(
        '↪ ${widget.replyToSender}: ${widget.replyToText}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: _timeColor),
      )));
    }
    if (widget.imageUrl != null) {
      cells.add(yellowCell(_imageCell()));
    } else {
      for (final line in _lines) {
        cells.add(yellowCell(_linkText(
          line,
          const TextStyle(fontSize: 13.5, color: Color(0xFF222222)),
        )));
      }
    }
    if (widget.reactions.isNotEmpty) {
      cells.add(yellowCell(Text(widget.reactions.join(' '),
          style: const TextStyle(fontSize: 12))));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 카톡식 안읽음 1 (셀 왼쪽)
        if (widget.unread)
          const Padding(
            padding: EdgeInsets.only(right: 4, top: 3),
            child: Text(
              '1',
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFFFB300),
                  fontWeight: FontWeight.bold),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...cells,
            Padding(
              padding: const EdgeInsets.only(right: 2, top: 1, bottom: 2),
              child: Text(widget.timeText,
                  style: const TextStyle(fontSize: 10.5, color: _timeColor)),
            ),
          ],
        ),
      ],
    );
  }
}

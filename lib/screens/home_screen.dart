import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'diary_screen.dart';
import 'login_screen.dart';
import 'memo_screen.dart';
import 'bucket_list_screen.dart';
import 'chat_screen.dart';
import '../utils/app_routes.dart';
import '../utils/web_notification.dart';
import '../utils/notif_pref.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_picker.dart';

const _projectId = 'love-app-4e2ac';
const _storageBucket = 'love-app-4e2ac.firebasestorage.app';

class _AdminPanel extends StatefulWidget {
  @override
  State<_AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<_AdminPanel> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  static const _fsBase =
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';
  static const _ownerEmail = 'gksdud9685@loveapp.com';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await _token();
      if (token == null) { setState(() { _loading = false; _error = '인증 토큰 없음'; }); return; }
      final res = await http.get(
        Uri.parse('$_fsBase/users'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final docs = (data['documents'] as List<dynamic>?) ?? [];
        final users = <Map<String, dynamic>>[];
        for (final doc in docs) {
          final d = doc as Map<String, dynamic>;
          final fields = d['fields'] as Map<String, dynamic>? ?? {};
          final emailField = fields['email'] as Map<String, dynamic>?;
          final email = emailField?['stringValue'] as String? ?? '';
          if (email == _ownerEmail) continue;
          final approvedField = fields['approved'] as Map<String, dynamic>?;
          final approved = approvedField?['booleanValue'] as bool? ?? false;
          final uid = (d['name'] as String).split('/').last;
          users.add({'uid': uid, 'email': email, 'approved': approved});
        }
        if (mounted) setState(() => _users = users);
      } else {
        if (mounted) setState(() => _error = '오류 ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(String uid) async {
    try {
      final token = await _token();
      if (token == null) return;
      await http.patch(
        Uri.parse('$_fsBase/users/$uid?updateMask.fieldPaths=approved'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'fields': {'approved': {'booleanValue': true}}}),
      );
      await _load();
    } catch (_) {}
  }

  Future<void> _delete(BuildContext context, String uid, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('회원 탈퇴', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('$email\n\n이 사용자를 탈퇴시킬까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final token = await _token();
      if (token == null) return;
      await http.delete(
        Uri.parse('$_fsBase/users/$uid'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await http.post(
        Uri.parse('https://us-central1-love-app-4e2ac.cloudfunctions.net/deleteAuthUser'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'uid': uid}),
      );
      await _load();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('탈퇴 완료! 재가입도 가능해요.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                '회원 관리 (${_users.length}명)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: Icon(Icons.refresh, color: AppTheme.primary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('로드 실패: $_error', style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          if (!_loading && _users.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('등록된 회원이 없어요', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ..._users.map((user) {
            final approved = user['approved'] as bool;
            final email = user['email'] as String;
            final uid = user['uid'] as String;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    approved ? Icons.check_circle : Icons.hourglass_top,
                    size: 16,
                    color: approved ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email, style: const TextStyle(fontSize: 13)),
                        Text(
                          approved ? '승인됨' : '대기중',
                          style: TextStyle(
                            fontSize: 11,
                            color: approved ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!approved)
                    TextButton(
                      onPressed: () => _approve(uid),
                      style: TextButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('승인', style: TextStyle(fontSize: 12)),
                    ),
                  if (!approved) const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => _delete(context, uid, email),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('탈퇴', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _photoUrl;
  bool _uploading = false;
  bool _photoError = false;
  DateTime _startDate = DateTime(2026, 4, 26);
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<String> _diaryDates = {};
  Map<String, String> _milestones = {};
  Map<String, String> _memos = {};
  StreamSubscription? _heartSub;
  StreamSubscription? _msgNotifSub;
  int _unreadNotif = 0; // 안 읽은 채팅 알림 개수 ("새 메시지 N개")
  void Function()? _disposeForeground;
  bool _heartAnimating = false;
  OverlayEntry? _heartEntry;
  bool _showInstallBanner = false;
  bool _showNotifBanner = false;

  String _toKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 달력 한 칸: 상단에 날짜(일기 있으면 하트로 감쌈), 하단에 기념일/메모 미리보기
  Widget _dayCell(DateTime day,
      {bool outside = false, bool today = false, bool selected = false}) {
    final key = _toKey(day);
    final hasDiary = _diaryDates.contains(key);
    final memo = _memos[key];
    final milestone = _milestones[key];
    final numText = '${day.day}';

    // ── 날짜 숫자 ──
    Widget number;
    if (hasDiary) {
      final fill = (selected || today)
          ? AppTheme.primary
          : AppTheme.mid;
      number = SizedBox(
        width: 36,
        height: 33,
        child: CustomPaint(
          painter: _HeartPainter(outside ? fill.withValues(alpha: 0.4) : fill),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                numText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      Color? bg;
      Color fg = outside ? Colors.black.withValues(alpha: 0.3) : Colors.black87;
      if (selected) {
        bg = AppTheme.primary;
        fg = Colors.white;
      } else if (today) {
        bg = AppTheme.light.withValues(alpha: 0.3);
        fg = AppTheme.primary;
      }
      number = Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: bg == null ? null : BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          numText,
          style: TextStyle(
            fontSize: 13,
            color: fg,
            fontWeight: (today || selected) ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    // 하트(33)/일반 숫자(26) 높이가 달라도 메모 시작 위치가 같도록 슬롯 고정
    number = SizedBox(height: 34, child: Center(child: number));

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          number,
          if (milestone != null)
            _cellChip(milestone, const Color(0xFFFF9800), Colors.white, outside, maxLines: 1),
          if (memo != null && memo.trim().isNotEmpty)
            _cellChip(memo.trim(), const Color(0xFFE1E4F5), const Color(0xFF5C6BC0), outside, maxLines: 6),
        ],
      ),
      ),
    );
  }

  /// 달력 칸 안의 작은 텍스트 칩 (기념일/메모 미리보기)
  Widget _cellChip(String text, Color bg, Color fg, bool outside, {int maxLines = 1}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: outside ? bg.withValues(alpha: 0.4) : bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          height: 1.15,
          fontWeight: FontWeight.w600,
          color: outside ? fg.withValues(alpha: 0.5) : fg,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadStartDate();
    _computeMilestones();
    NotifPref.load(); // 저장된 알림 on/off 설정 불러오기
    _listenHearts();
    _listenMessageNotifications();
    // 탭으로 돌아오면(포커스) 안 읽은 알림 카운트 리셋
    _disposeForeground = installForegroundListener(() => _unreadNotif = 0);
    NotificationService.saveToken();
    _checkInstallBanner();
    if (kIsWeb) _checkNotifPermission();
  }

  Future<void> _checkNotifPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      // 이미 허용된 경우엔 배너 숨김, 그 외(미결정/거부/불가)엔 배너 표시
      if (status != AuthorizationStatus.authorized && mounted) {
        setState(() => _showNotifBanner = true);
      }
    } catch (_) {
      // getNotificationSettings 실패 시 일단 배너 표시
      if (mounted) setState(() => _showNotifBanner = true);
    }
  }

  Future<void> _requestNotifPermission() async {
    setState(() => _showNotifBanner = false);
    final granted = await NotificationService.requestWebPermission();
    if (granted) await NotificationService.saveToken();
  }

  void _checkInstallBanner() {
    // 홈 화면 추가 안내 배너 비활성화
  }

  @override
  void dispose() {
    _heartSub?.cancel();
    _msgNotifSub?.cancel();
    _disposeForeground?.call();
    _heartEntry?.remove();
    _heartEntry = null;
    super.dispose();
  }

  Future<void> _loadAll() async {
    final token = kIsWeb ? await _getIdToken() : null;
    await Future.wait([
      _loadPhoto(token: token),
      _loadDiaryDates(token: token),
      _loadMemos(token: token),
    ]);
  }

  // ── 시작 날짜 ────────────────────────────────────────────────
  Future<void> _loadStartDate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('couple')
          .get();
      if (doc.exists && mounted) {
        final ts = doc.data()?['startDate'] as Timestamp?;
        if (ts != null) {
          setState(() => _startDate = ts.toDate());
          _computeMilestones();
        }
      }
    } catch (_) {}
  }

  Future<void> _changeStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: '사귄 날짜 선택',
    );
    if (picked == null || !mounted) return;
    try {
      await FirebaseFirestore.instance.collection('settings').doc('couple').set(
        {'startDate': Timestamp.fromDate(picked)},
        SetOptions(merge: true),
      );
      setState(() => _startDate = picked);
      _computeMilestones();
    } catch (_) {}
  }

  // ── 하트 ────────────────────────────────────────────────────
  void _listenHearts() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final appStart = Timestamp.now();
    _heartSub = FirebaseFirestore.instance
        .collection('hearts')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          final sentBy = data?['sentBy'] as String?;
          final sentAt = data?['sentAt'] as Timestamp?;
          if (sentBy != null &&
              sentBy != currentUid &&
              sentAt != null &&
              sentAt.compareTo(appStart) >= 0) {
            if (mounted) _showHeartAnimation();
          }
        }
      }
    });
  }

  // ── 채팅 메시지 OS 알림 ───────────────────────────────────────
  // 상대가 보낸 새 메시지가 오면 브라우저 네이티브 알림(우측 하단 토스트)을 띄운다.
  // 크롬이 켜져 있으면 다른 화면/다른 탭/최소화 상태에서도 표시.
  // 내 메시지, 앱 시작 전 옛 메시지, 채팅 화면을 보고 있을 때는 제외.
  void _listenMessageNotifications() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final appStart = Timestamp.now();
    _msgNotifSub = FirebaseFirestore.instance
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final senderUid = data['senderUid'] as String?;
        final createdAt = data['createdAt'] as Timestamp?;
        // 내 메시지 / 시작 전 옛 메시지 제외
        if (senderUid == null || senderUid == currentUid) continue;
        if (createdAt == null || createdAt.compareTo(appStart) < 0) continue;
        // 알림이 꺼져 있으면 띄우지 않음
        if (!NotifPref.enabled.value) continue;
        // 채팅 화면을 '실제로 보고 있을 때'만 억제(탭이 포커스 상태).
        // 탭이 백그라운드/최소화면 채팅 화면이어도 알림을 띄운다.
        if (ChatScreen.isOpen && webPageFocused()) {
          _unreadNotif = 0; // 보고 있으니 쌓인 카운트 정리
          continue;
        }
        _unreadNotif++;
        // 같은 tag로 토스트 1개에 합치고, 2개부터 "새 메시지 N개"로 표시.
        // 내용은 노출하지 않고 '메시지가 도착했습니다'만 표시.
        showWebNotification(
          title: _unreadNotif == 1 ? '새로운 메시지' : '새 메시지 $_unreadNotif개',
          body: '메시지가 도착했습니다',
          icon: 'icons/Icon-192.png',
          tag: 'love-chat',
        );
      }
    });
  }

  Future<void> _sendHeart() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('hearts').add({
        'sentBy': user.uid,
        'sentAt': FieldValue.serverTimestamp(),
      });
      _showHeartAnimation();
    } catch (_) {}
  }

  void _showHeartAnimation() {
    if (_heartAnimating) return;
    final overlay = Overlay.of(context);
    _heartEntry = OverlayEntry(
      builder: (_) => _HeartBurst(onDone: () {
        _heartEntry?.remove();
        _heartEntry = null;
        if (mounted) setState(() => _heartAnimating = false);
      }),
    );
    setState(() => _heartAnimating = true);
    overlay.insert(_heartEntry!);
  }

  // ── 다음 기념일 ──────────────────────────────────────────────
  ({String label, int daysLeft})? _nextMilestone() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String? nearestLabel;
    int nearestDays = 999999;
    for (final entry in _milestones.entries) {
      final parts = entry.key.split('-');
      final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final diff = date.difference(today).inDays;
      if (diff > 0 && diff < nearestDays) {
        nearestDays = diff;
        nearestLabel = entry.value;
      }
    }
    if (nearestLabel == null) return null;
    return (label: nearestLabel, daysLeft: nearestDays);
  }

  void _computeMilestones() {
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final map = <String, String>{};
    for (final d in [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 2000, 3000]) {
      final date = start.add(Duration(days: d - 1));
      map[_toKey(date)] = '${d}일';
    }
    for (int y = 1; y <= 10; y++) {
      final date = DateTime(start.year + y, start.month, start.day);
      map[_toKey(date)] = '${y}주년';
    }
    if (mounted) setState(() => _milestones = map);
  }

  Future<String?> _getIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMemos({String? token}) async {
    try {
      if (kIsWeb) {
        token ??= await _getIdToken();
        if (token == null) return;
        final res = await http.get(
          Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/memos'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200 && mounted) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final docs = (data['documents'] as List<dynamic>?) ?? [];
          final map = <String, String>{};
          for (final doc in docs) {
            final d = doc as Map<String, dynamic>;
            final name = (d['name'] as String).split('/').last;
            final fields = d['fields'] as Map<String, dynamic>? ?? {};
            final textField = fields['text'] as Map<String, dynamic>?;
            final text = textField?['stringValue'] as String? ?? '';
            if (text.isNotEmpty) map[name] = text;
          }
          setState(() => _memos = map);
        }
      } else {
        final snapshot = await FirebaseFirestore.instance.collection('memos').get();
        if (mounted) {
          setState(() {
            _memos = {
              for (final d in snapshot.docs)
                if ((d.data()['text'] as String? ?? '').isNotEmpty)
                  d.id: d.data()['text'] as String,
            };
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveMemo(String dateKey, String text) async {
    try {
      if (text.isEmpty) {
        if (kIsWeb) {
          final token = await _getIdToken();
          if (token == null) return;
          await http.delete(
            Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/memos/$dateKey'),
            headers: {'Authorization': 'Bearer $token'},
          );
        } else {
          await FirebaseFirestore.instance.collection('memos').doc(dateKey).delete();
        }
        if (mounted) setState(() => _memos.remove(dateKey));
      } else {
        if (kIsWeb) {
          final token = await _getIdToken();
          if (token == null) return;
          await http.patch(
            Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/memos/$dateKey'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'fields': {'text': {'stringValue': text}}}),
          );
        } else {
          await FirebaseFirestore.instance.collection('memos').doc(dateKey).set({'text': text});
        }
        if (mounted) setState(() => _memos[dateKey] = text);
      }
    } catch (_) {}
  }

  Future<void> _loadDiaryDates({String? token}) async {
    try {
      if (kIsWeb) {
        token ??= await _getIdToken();
        if (token == null) return;
        final res = await http.get(
          Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/diaries'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200 && mounted) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final docs = (data['documents'] as List<dynamic>?) ?? [];
          setState(() {
            _diaryDates = docs.map((doc) {
              final name = (doc as Map<String, dynamic>)['name'] as String;
              return name.split('/').last;
            }).toSet();
          });
        }
      } else {
        final snapshot = await FirebaseFirestore.instance.collection('diaries').get();
        if (mounted) {
          setState(() {
            _diaryDates = snapshot.docs.map((d) => d.id).toSet();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPhoto({bool clearCache = false, String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    if (clearCache) {
      await prefs.remove('photo_url');
    } else {
      final cached = prefs.getString('photo_url');
      if (cached != null && mounted) setState(() => _photoUrl = cached);
    }
    try {
      String url;
      if (kIsWeb) {
        token ??= await _getIdToken();
        if (token == null) return;
        final encoded = Uri.encodeComponent('couple/photo.jpg');
        final res = await http.get(
          Uri.parse('https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o/$encoded'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final downloadToken = (data['downloadTokens'] as String).split(',').first;
        url = 'https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o/$encoded?alt=media&token=$downloadToken';
      } else {
        url = await FirebaseStorage.instance.ref('couple/photo.jpg').getDownloadURL();
      }
      await prefs.setString('photo_url', url);
      if (mounted) setState(() { _photoUrl = url; _photoError = false; });
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _uploading = true);
    try {
      final ref = FirebaseStorage.instance.ref('couple/photo.jpg');
      try { await ref.delete(); } catch (_) {}
      final bytes = await image.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('photo_url', url);
      if (mounted) setState(() => _photoUrl = url);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  int get _dayCount {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
            .difference(DateTime(_startDate.year, _startDate.month, _startDate.day))
            .inDays +
        1;
  }

  String get _startDateText =>
      '${_startDate.year}.${_startDate.month.toString().padLeft(2, '0')}.${_startDate.day.toString().padLeft(2, '0')} 시작 ❤️';

  @override
  Widget build(BuildContext context) {
    final isAdmin = FirebaseAuth.instance.currentUser?.email == 'gksdud9685@loveapp.com';
    final next = _nextMilestone();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.light, AppTheme.primary, AppTheme.dark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 홈 화면 추가 안내 배너 (웹일 때만)
              if (kIsWeb && _showInstallBanner)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      const Icon(Icons.add_to_home_screen, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '알림을 받으려면 홈 화면에 추가하세요\n(Safari → 공유 → 홈 화면에 추가)',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showInstallBanner = false),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              // 알림 허용 배너 (웹, 권한 미설정 시)
              if (kIsWeb && _showNotifBanner)
                GestureDetector(
                  onTap: _requestNotifPermission,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '💕 알림을 받으려면 여기를 탭하세요',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showNotifBanner = false),
                          child: const Icon(Icons.close, color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              // 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Text(
                      '우리들의 일기',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Spacer(),
                    // 채팅 버튼
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        appRoute(const ChatScreen()),
                      ),
                      icon: const Text('💬', style: TextStyle(fontSize: 22)),
                      tooltip: '채팅',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    // 버킷리스트 버튼
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        appRoute(const BucketListScreen()),
                      ),
                      icon: const Text('🌟', style: TextStyle(fontSize: 22)),
                      tooltip: '버킷리스트',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    // 테마 색상 버튼
                    IconButton(
                      onPressed: () => showThemePicker(context),
                      icon: const Text('🎨', style: TextStyle(fontSize: 22)),
                      tooltip: '테마 색상',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    // 하트 보내기 버튼
                    IconButton(
                      onPressed: _sendHeart,
                      icon: const Text('❤️', style: TextStyle(fontSize: 22)),
                      tooltip: '하트 보내기',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    // 로그아웃 버튼
                    IconButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('auto_login', false);
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(appRoute(const LoginScreen()));
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // 커플 사진
                      GestureDetector(
                        onTap: _uploading ? null : _pickPhoto,
                        child: Center(
                          child: _photoUrl != null
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.network(
                                      _photoUrl!,
                                      height: 260,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        if (!_photoError) {
                                          _photoError = true;
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted) {
                                              setState(() => _photoUrl = null);
                                              _loadPhoto(clearCache: true);
                                            }
                                          });
                                        }
                                        return const SizedBox(
                                          height: 260,
                                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  child: _uploading
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 50),
                                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                        )
                                      : const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 40),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.add_a_photo, color: Colors.white, size: 40),
                                              SizedBox(height: 8),
                                              Text('사진 추가', style: TextStyle(color: Colors.white, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // D-day 카드
                      GestureDetector(
                        onLongPress: isAdmin ? _changeStartDate : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '영욱 ❤️ 소영 사귄 지',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_dayCount일',
                                style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _startDateText,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                              ),
                              if (next != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '🎉 ${next.label}까지 ${next.daysLeft}일 남았어요',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 달력
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: TableCalendar(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2030, 12, 31),
                            focusedDay: _focusedDay,
                            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            onDaySelected: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                              });
                              Navigator.push(
                                context,
                                appRoute(DiaryScreen(date: selectedDay)),
                              ).then((_) => _loadDiaryDates());
                            },
                            onDayLongPressed: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                              });
                              final key = _toKey(selectedDay);
                              Navigator.push(
                                context,
                                appRoute(MemoScreen(
                                  date: selectedDay,
                                  initialText: _memos[key],
                                )),
                              ).then((result) {
                                if (result == null) return;
                                setState(() {
                                  if (result.isEmpty) {
                                    _memos.remove(key);
                                  } else {
                                    _memos[key] = result as String;
                                  }
                                });
                              });
                            },
                            rowHeight: 104,
                            calendarBuilders: CalendarBuilders(
                              defaultBuilder: (context, day, _) => _dayCell(day),
                              outsideBuilder: (context, day, _) => _dayCell(day, outside: true),
                              todayBuilder: (context, day, _) => _dayCell(day, today: true),
                              selectedBuilder: (context, day, _) => _dayCell(day, selected: true),
                            ),
                            calendarStyle: CalendarStyle(
                              defaultTextStyle: const TextStyle(color: Colors.black87),
                              weekendTextStyle: const TextStyle(color: Colors.black87),
                              outsideTextStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                              todayDecoration: BoxDecoration(
                                color: AppTheme.light.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              todayTextStyle: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                              selectedDecoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                              selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                              titleTextStyle: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
                              leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black54),
                              rightChevronIcon: Icon(Icons.chevron_right, color: Colors.black54),
                            ),
                            daysOfWeekStyle: const DaysOfWeekStyle(
                              weekdayStyle: TextStyle(color: Colors.black54),
                              weekendStyle: TextStyle(color: Colors.black54),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (isAdmin) _AdminPanel(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 달력 일기 날짜용 하트 도형 ──────────────────────────────────
class _HeartPainter extends CustomPainter {
  final Color color;
  const _HeartPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(0.5 * w, h * 0.32)
      ..cubicTo(0.5 * w, h * 0.12, 0.16 * w, h * 0.05, 0.06 * w, h * 0.32)
      ..cubicTo(-0.05 * w, h * 0.62, 0.32 * w, h * 0.86, 0.5 * w, h)
      ..cubicTo(0.68 * w, h * 0.86, 1.05 * w, h * 0.62, 0.94 * w, h * 0.32)
      ..cubicTo(0.84 * w, h * 0.05, 0.5 * w, h * 0.12, 0.5 * w, h * 0.32)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color;
}

// ── 하트 애니메이션 ────────────────────────────────────────────
class _HeartBurst extends StatefulWidget {
  final VoidCallback onDone;
  const _HeartBurst({required this.onDone});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.55, 1.0, curve: Curves.easeIn)),
    );
    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(
          children: [
            _heart(sw * 0.5 - 40, sh * 0.45 - t * 260, 80, 1.0, t),
            _heart(sw * 0.3 - 20, sh * 0.52 - t * 200, 50, 0.75, t),
            _heart(sw * 0.65, sh * 0.50 - t * 220, 55, 0.75, t),
          ],
        );
      },
    );
  }

  Widget _heart(double left, double top, double size, double alpha, double t) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Opacity(
          opacity: (_opacity.value * alpha).clamp(0.0, 1.0),
          child: Text('❤️', style: TextStyle(fontSize: size)),
        ),
      ),
    );
  }
}

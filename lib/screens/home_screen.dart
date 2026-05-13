import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
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

      // Firestore 문서 삭제
      await http.delete(
        Uri.parse('$_fsBase/users/$uid'),
        headers: {'Authorization': 'Bearer $token'},
      );

      // Firebase Auth 계정 삭제 (Cloud Function)
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
              const Icon(Icons.admin_panel_settings, color: Color(0xFFE91E63)),
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
                icon: const Icon(Icons.refresh, color: Color(0xFFE91E63), size: 20),
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
                        backgroundColor: const Color(0xFFE91E63),
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
  final DateTime _anniversaryDate = DateTime(2026, 4, 26);
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<String> _diaryDates = {};
  Map<String, String> _milestones = {};
  Map<String, String> _memos = {};

  String _toKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadPhoto();
    _loadDiaryDates();
    _loadMemos();
    _computeMilestones();
  }

  void _computeMilestones() {
    final start = DateTime(_anniversaryDate.year, _anniversaryDate.month, _anniversaryDate.day);
    final map = <String, String>{};

    // 100일 단위 (100~1000일, 2000일, 3000일)
    for (final d in [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 2000, 3000]) {
      final date = start.add(Duration(days: d - 1));
      map[_toKey(date)] = '${d}일';
    }

    // 주년 (1~10년)
    for (int y = 1; y <= 10; y++) {
      final date = DateTime(start.year + y, start.month, start.day);
      final key = _toKey(date);
      // 주년이 이미 100일 단위와 겹치면 주년 우선
      map[key] = '${y}주년';
    }

    setState(() => _milestones = map);
  }

  Future<String?> _getIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMemos() async {
    try {
      if (kIsWeb) {
        final token = await _getIdToken();
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

  Future<void> _loadDiaryDates() async {
    try {
      if (kIsWeb) {
        final token = await _getIdToken();
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

  Future<void> _loadPhoto({bool clearCache = false}) async {
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
        final token = await _getIdToken();
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
            .difference(DateTime(_anniversaryDate.year, _anniversaryDate.month, _anniversaryDate.day))
            .inDays +
        1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B9D),
              Color(0xFFE91E63),
              Color(0xFFC2185B),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '우리들의 일기',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    IconButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('auto_login', false);
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
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
                              ? Stack(
                                  children: [
                                    Container(
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
                                    ),
                                  ],
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
                      Container(
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
                              '2026.04.26 시작 ❤️',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                            ),
                          ],
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
                                MaterialPageRoute(
                                  builder: (_) => DiaryScreen(date: selectedDay),
                                ),
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
                                MaterialPageRoute(
                                  builder: (_) => MemoScreen(
                                    date: selectedDay,
                                    initialText: _memos[key],
                                  ),
                                ),
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
                            eventLoader: (day) {
                              final key = _toKey(day);
                              final events = <String>[];
                              if (_diaryDates.contains(key)) events.add('diary');
                              if (_milestones.containsKey(key)) events.add('milestone:${_milestones[key]}');
                              if (_memos.containsKey(key)) events.add('memo');
                              return events;
                            },
                            calendarBuilders: CalendarBuilders(
                              markerBuilder: (context, day, events) {
                                if (events.isEmpty) return const SizedBox.shrink();
                                final hasDiary = events.contains('diary');
                                final hasMemo = events.contains('memo');
                                final milestoneEvent = events.cast<String>().firstWhere(
                                  (e) => e.startsWith('milestone:'), orElse: () => '');
                                final label = milestoneEvent.isNotEmpty
                                    ? milestoneEvent.substring(10) : null;
                                return Positioned(
                                  bottom: 2,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (label != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF9800),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(label,
                                              style: const TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (hasDiary) const Text('❤️', style: TextStyle(fontSize: 11)),
                                          if (hasMemo) const Text('📝', style: TextStyle(fontSize: 10)),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            calendarStyle: CalendarStyle(
                              defaultTextStyle: const TextStyle(color: Colors.black87),
                              weekendTextStyle: const TextStyle(color: Colors.black87),
                              outsideTextStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                              todayDecoration: BoxDecoration(
                                color: const Color(0xFFFF6B9D).withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              todayTextStyle: const TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold),
                              selectedDecoration: const BoxDecoration(color: Color(0xFFE91E63), shape: BoxShape.circle),
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

                      // 관리자 승인 패널 (gksdud486@gmail.com 전용)
                      if (FirebaseAuth.instance.currentUser?.email == 'gksdud9685@loveapp.com')
                        _AdminPanel(),

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

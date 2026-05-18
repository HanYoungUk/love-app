import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/kakao_service.dart';
import '../utils/open_url.dart';
import '../utils/app_routes.dart';
import 'gallery_screen.dart';

const _fsProject = 'love-app-4e2ac';
const _fsBase = 'https://firestore.googleapis.com/v1/projects/$_fsProject/databases/(default)/documents';

Future<String?> _idToken() async {
  try { return await FirebaseAuth.instance.currentUser?.getIdToken(); } catch (_) { return null; }
}

dynamic _fsVal(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return int.tryParse(v['integerValue'].toString()) ?? 0;
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('mapValue')) {
    final f = v['mapValue']['fields'] as Map<String, dynamic>?;
    return f == null ? {} : f.map((k, val) => MapEntry(k, _fsVal(val as Map<String, dynamic>)));
  }
  if (v.containsKey('arrayValue')) {
    final vals = v['arrayValue']['values'] as List<dynamic>?;
    return vals == null ? [] : vals.map((e) => _fsVal(e as Map<String, dynamic>)).toList();
  }
  return null;
}

Map<String, dynamic> _toFsVal(dynamic value) {
  if (value == null) return {'nullValue': null};
  if (value is String) return {'stringValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is bool) return {'booleanValue': value};
  if (value is List) return {'arrayValue': {'values': value.map(_toFsVal).toList()}};
  if (value is Map<String, dynamic>) return {'mapValue': {'fields': value.map((k, v) => MapEntry(k, _toFsVal(v)))}};
  return {'stringValue': '$value'};
}

class _ScheduleEntry {
  final TextEditingController timeController;
  final TextEditingController titleController;

  _ScheduleEntry([String time = '', String title = ''])
      : timeController = TextEditingController(text: time),
        titleController = TextEditingController(text: title);

  void dispose() {
    timeController.dispose();
    titleController.dispose();
  }
}

class _PlaceEntry {
  final TextEditingController nameController;
  String address;
  int meRating;
  int partnerRating;

  _PlaceEntry([String name = '', this.address = '', this.meRating = 0, this.partnerRating = 0])
      : nameController = TextEditingController(text: name);

  void dispose() => nameController.dispose();
}

class _PhotoEntry {
  String imageUrl;
  final TextEditingController controller;

  _PhotoEntry(this.imageUrl, [String initialText = ''])
      : controller = TextEditingController(text: initialText);

  void dispose() => controller.dispose();
}

List<_PhotoEntry> _parseBlocks(List<dynamic> blocks) {
  final entries = <_PhotoEntry>[];
  for (int i = 0; i < blocks.length; i++) {
    final block = blocks[i] as Map<String, dynamic>;
    if (block['type'] == 'image') {
      final url = block['url'] as String? ?? '';
      String text = '';
      if (i + 1 < blocks.length) {
        final next = blocks[i + 1] as Map<String, dynamic>;
        if (next['type'] == 'text') {
          text = next['content'] as String? ?? '';
          i++;
        }
      }
      if (url.isNotEmpty) entries.add(_PhotoEntry(url, text));
    }
  }
  return entries;
}

class DiaryScreen extends StatefulWidget {
  final DateTime date;
  const DiaryScreen({super.key, required this.date});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final _meTopController = TextEditingController();
  final _partnerTopController = TextEditingController();
  List<_PhotoEntry> _meEntries = [];
  List<_PhotoEntry> _partnerEntries = [];
  List<_ScheduleEntry> _schedules = [];
  List<_PlaceEntry> _mePlaces = [];
  bool _uploadingMe = false;
  bool _uploadingPartner = false;
  bool _saving = false;
  bool _showMe = true;
  bool _docExists = false;

  String get _dateKey =>
      '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

  String get _dateLabel =>
      '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일';

  @override
  void initState() {
    super.initState();
    _loadDiary();
  }

  @override
  void dispose() {
    _meTopController.dispose();
    _partnerTopController.dispose();
    for (final e in _meEntries) e.dispose();
    for (final e in _partnerEntries) e.dispose();
    for (final s in _schedules) s.dispose();
    for (final p in _mePlaces) p.dispose();
    super.dispose();
  }

  Future<void> _loadDiary() async {
    Map<String, dynamic> data;
    if (kIsWeb) {
      final token = await _idToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('$_fsBase/diaries/$_dateKey'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 404) return;
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final fields = body['fields'] as Map<String, dynamic>?;
      if (fields == null) return;
      data = fields.map((k, v) => MapEntry(k, _fsVal(v as Map<String, dynamic>)));
      _docExists = true;
    } else {
      final doc = await FirebaseFirestore.instance.collection('diaries').doc(_dateKey).get();
      if (!doc.exists) return;
      data = doc.data()!;
      _docExists = true;
    }

    String parseTopText(dynamic raw) {
      if (raw == null) return '';
      final map = raw as Map<String, dynamic>;
      return map['topText'] as String? ?? '';
    }

    List<_PhotoEntry> parseSection(dynamic raw) {
      if (raw == null) return [];
      final map = raw as Map<String, dynamic>;
      if (map['blocks'] != null) {
        return _parseBlocks(map['blocks'] as List<dynamic>);
      }
      // 이전 형식 호환 (photoUrls + text)
      final photos = List<String>.from(map['photoUrls'] ?? []);
      if (photos.isEmpty) return [];
      return photos.map((url) => _PhotoEntry(url)).toList();
    }

    List<_PhotoEntry> meEntries = [];
    List<_PhotoEntry> partnerEntries = [];
    List<_ScheduleEntry> schedules = [];
    List<_PlaceEntry> mePlaces = [];
    String meTopText = '';
    String partnerTopText = '';

    List<_ScheduleEntry> parseSchedules(dynamic raw) {
      if (raw == null) return [];
      return (raw as List<dynamic>).map((s) {
        final map = s as Map<String, dynamic>;
        return _ScheduleEntry(
          map['time'] as String? ?? '',
          map['title'] as String? ?? '',
        );
      }).toList();
    }

    List<_PlaceEntry> parsePlaces(dynamic raw) {
      if (raw == null) return [];
      return (raw as List<dynamic>).map((p) {
        final map = p as Map<String, dynamic>;
        return _PlaceEntry(
          map['name'] as String? ?? '',
          map['address'] as String? ?? '',
          (map['meRating'] as int?) ?? (map['rating'] as int?) ?? 0,
          (map['partnerRating'] as int?) ?? 0,
        );
      }).toList();
    }

    if (data['me'] != null || data['partner'] != null) {
      // 현재 형식
      meTopText = parseTopText(data['me']);
      partnerTopText = parseTopText(data['partner']);
      meEntries = parseSection(data['me']);
      partnerEntries = parseSection(data['partner']);
      schedules = parseSchedules(data['sharedSchedules']);
      mePlaces = data['sharedPlaces'] != null
          ? parsePlaces(data['sharedPlaces'])
          : parsePlaces(data['me']?['places']);
    } else if (data['entries'] != null) {
      // 이전 entries 형식 → me로 이전
      final entries = data['entries'] as Map<String, dynamic>;
      final values = entries.values.toList();
      if (values.isNotEmpty) {
        meEntries = parseSection(values[0]);
      }
      if (values.length > 1) {
        partnerEntries = parseSection(values[1]);
      }
    } else {
      // 아주 오래된 형식 (top-level)
      final urls = data['photoUrls'];
      final singleUrl = data['photoUrl'];
      final text = data['text'] as String? ?? '';
      List<String> photos = [];
      if (urls != null) {
        photos = List<String>.from(urls);
      } else if (singleUrl != null && singleUrl != 'null') {
        photos = [singleUrl as String];
      }
      if (photos.isNotEmpty) {
        meEntries = photos.map((url) => _PhotoEntry(url)).toList();
      }
      meTopText = (data['text'] as String? ?? '');
    }

    setState(() {
      _meTopController.text = meTopText;
      _partnerTopController.text = partnerTopText;
      for (final e in _meEntries) e.dispose();
      _meEntries = meEntries;
      for (final e in _partnerEntries) e.dispose();
      _partnerEntries = partnerEntries;
      for (final s in _schedules) s.dispose();
      _schedules = schedules;
      for (final p in _mePlaces) p.dispose();
      _mePlaces = mePlaces;
    });
  }

  Future<void> _addPhoto({required bool isMe}) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    if (isMe) {
      setState(() => _uploadingMe = true);
    } else {
      setState(() => _uploadingPartner = true);
    }
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref =
          FirebaseStorage.instance.ref('diary/$_dateKey/photo_$timestamp.jpg');
      final bytes = await image.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      setState(() {
        if (isMe) {
          _meEntries.add(_PhotoEntry(url));
        } else {
          _partnerEntries.add(_PhotoEntry(url));
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isMe) _uploadingMe = false;
          else _uploadingPartner = false;
        });
      }
    }
  }

  Future<void> _deleteEntry(int index, {required bool isMe}) async {
    final entry = isMe ? _meEntries[index] : _partnerEntries[index];
    try {
      await FirebaseStorage.instance.refFromURL(entry.imageUrl).delete();
    } catch (_) {}
    setState(() {
      if (isMe) {
        _meEntries.removeAt(index);
      } else {
        _partnerEntries.removeAt(index);
      }
      entry.dispose();
    });
  }

  bool get _hasContent =>
      _meTopController.text.trim().isNotEmpty ||
      _partnerTopController.text.trim().isNotEmpty ||
      _meEntries.isNotEmpty ||
      _partnerEntries.isNotEmpty ||
      _schedules.isNotEmpty ||
      _mePlaces.isNotEmpty;

  List<Map<String, dynamic>> _toBlocks(List<_PhotoEntry> entries) {
    final blocks = <Map<String, dynamic>>[];
    for (final entry in entries) {
      blocks.add({'type': 'image', 'url': entry.imageUrl});
      blocks.add({'type': 'text', 'content': entry.controller.text});
    }
    return blocks;
  }

  Future<void> _handleBack() async {
    if (_docExists && !_hasContent) {
      await _deleteDoc();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteDoc() async {
    if (kIsWeb) {
      final token = await _idToken();
      if (token == null) return;
      await http.delete(
        Uri.parse('$_fsBase/diaries/$_dateKey'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } else {
      await FirebaseFirestore.instance.collection('diaries').doc(_dateKey).delete();
    }
  }

  Future<void> _resetAll() async {
    setState(() => _saving = true);
    try {
      for (final entry in [..._meEntries, ..._partnerEntries]) {
        try {
          await FirebaseStorage.instance.refFromURL(entry.imageUrl).delete();
        } catch (_) {}
      }
      if (_docExists) await _deleteDoc();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmAndReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('전체 초기화', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('이 날의 글, 사진, 일정, 장소를\n모두 삭제할까요?\n\n되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _resetAll();
  }

  Future<void> _save() async {
    if (!_hasContent) {
      await _deleteDoc();
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final payload = {
        'me': {
          'topText': _meTopController.text,
          'blocks': _toBlocks(_meEntries),
        },
        'partner': {
          'topText': _partnerTopController.text,
          'blocks': _toBlocks(_partnerEntries),
        },
        'sharedSchedules': _schedules.map((s) => {
          'time': s.timeController.text.trim(),
          'title': s.titleController.text.trim(),
        }).toList(),
        'sharedPlaces': _mePlaces.map((p) => {
          'name': p.nameController.text,
          'address': p.address,
          'meRating': p.meRating,
          'partnerRating': p.partnerRating,
        }).toList(),
        'authorUid': uid,
        'authorEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      };

      if (kIsWeb) {
        final token = await _idToken();
        if (token == null) throw Exception('로그인이 필요해요');
        final fields = payload.map((k, v) => MapEntry(k, _toFsVal(v)));
        final res = await http.patch(
          Uri.parse('$_fsBase/diaries/$_dateKey'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'fields': fields}),
        );
        if (res.statusCode != 200) throw Exception('저장 실패: ${res.statusCode}');
      } else {
        await FirebaseFirestore.instance.collection('diaries').doc(_dateKey).set({
          ...payload,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('저장됐어요 💕'),
              backgroundColor: Color(0xFFE91E63)),
        );
      }

      // 카카오톡 알림 전송
      final writer = _showMe ? '영욱' : '소영';
      KakaoService.notifyPartner('$writer이 새 일기를 썼어요 💕\n\n앱을 열어서 확인해보세요!');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openFullScreen(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullScreenPhoto(url: url)),
    );
  }

  Widget _buildEntriesList(List<_PhotoEntry> entries, bool isMe, TextEditingController topController) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사진 없이도 쓸 수 있는 상단 텍스트 칸
        TextField(
          controller: topController,
          maxLines: null,
          minLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: '오늘의 이야기를 적어보세요 💕',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.only(bottom: 8),
          ),
        ),
        ...List.generate(entries.length, (i) {
          final entry = entries[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _openFullScreen(entry.imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(entry.imageUrl, width: double.infinity, fit: BoxFit.cover),
                      ),
                    ),
                    // 위/아래 순서 버튼 (왼쪽 상단)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Column(
                        children: [
                          if (i > 0)
                            GestureDetector(
                              onTap: () => setState(() {
                                final tmpUrl = entries[i].imageUrl;
                                final tmpText = entries[i].controller.text;
                                entries[i].imageUrl = entries[i - 1].imageUrl;
                                entries[i].controller.text = entries[i - 1].controller.text;
                                entries[i - 1].imageUrl = tmpUrl;
                                entries[i - 1].controller.text = tmpText;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
                              ),
                            ),
                          if (i > 0 && i < entries.length - 1)
                            const SizedBox(height: 4),
                          if (i < entries.length - 1)
                            GestureDetector(
                              onTap: () => setState(() {
                                final tmpUrl = entries[i].imageUrl;
                                final tmpText = entries[i].controller.text;
                                entries[i].imageUrl = entries[i + 1].imageUrl;
                                entries[i].controller.text = entries[i + 1].controller.text;
                                entries[i + 1].imageUrl = tmpUrl;
                                entries[i + 1].controller.text = tmpText;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.arrow_downward, color: Colors.white, size: 16),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 삭제 버튼 (오른쪽 상단)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _deleteEntry(i, isMe: isMe),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: entry.controller,
                  maxLines: null,
                  minLines: 2,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.6),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ],
            ),
          );
        }),

        // 사진 삽입 버튼
        GestureDetector(
          onTap: (isMe ? _uploadingMe : _uploadingPartner)
              ? null
              : () => _addPhoto(isMe: isMe),
          child: Row(
            children: [
              Expanded(
                  child: Divider(
                      color: Colors.white.withValues(alpha: 0.35), thickness: 1)),
              const SizedBox(width: 8),
              (isMe ? _uploadingMe : _uploadingPartner)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Icon(Icons.add_photo_alternate,
                      color: Colors.white.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 4),
              Text('사진 삽입',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                  child: Divider(
                      color: Colors.white.withValues(alpha: 0.35), thickness: 1)),
            ],
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, String>>> _fetchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.https('dapi.kakao.com', '/v2/local/search/keyword.json', {
        'query': query,
        'size': '10',
      });
      const kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_API_KEY');
      final response = await http.get(uri, headers: {
        'Authorization': 'KakaoAK $kakaoRestApiKey',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final docs = data['documents'] as List<dynamic>;
        return docs.map((item) {
          final map = item as Map<String, dynamic>;
          final name = map['place_name'] as String? ?? '';
          final address = (map['road_address_name'] as String?)?.isNotEmpty == true
              ? map['road_address_name'] as String
              : map['address_name'] as String? ?? '';
          return {'name': name, 'address': address};
        }).toList();
      } else {
        debugPrint('Kakao API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Kakao API exception: $e');
    }
    return [];
  }

  void _showPlaceSearch(_PlaceEntry entry) {
    final searchController = TextEditingController();
    List<Map<String, String>> results = [];
    bool searching = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> doSearch() async {
            setDialogState(() => searching = true);
            final found = await _fetchPlaces(searchController.text);
            setDialogState(() {
              results = found;
              searching = false;
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFFC2185B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('장소 검색', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          onSubmitted: (_) => doSearch(),
                          decoration: InputDecoration(
                            hintText: '장소 이름 검색',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: doSearch,
                        icon: const Icon(Icons.search, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('검색 결과가 없어요', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                        itemBuilder: (_, i) {
                          final r = results[i];
                          return InkWell(
                            onTap: () {
                              setState(() {
                                entry.nameController.text = r['name'] ?? '';
                                entry.address = r['address'] ?? '';
                              });
                              Navigator.pop(ctx);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  if ((r['address'] ?? '').isNotEmpty)
                                    Text(r['address']!, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('취소', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openMaps() async {
    await openUrl('https://maps.google.com/');
  }

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            const Text('오늘의 일정', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(_schedules.length, (i) {
          final s = _schedules[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final current = s.timeController.text;
                    TimeOfDay initial = TimeOfDay.now();
                    if (current.length == 5 && current.contains(':')) {
                      final parts = current.split(':');
                      initial = TimeOfDay(
                        hour: int.tryParse(parts[0]) ?? 0,
                        minute: int.tryParse(parts[1]) ?? 0,
                      );
                    }
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: initial,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      s.timeController.text =
                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                    }
                  },
                  child: SizedBox(
                    width: 52,
                    child: TextField(
                      controller: s.timeController,
                      enabled: false,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '00:00',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: s.titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: '일정 내용',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _schedules.removeAt(i)),
                  child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.6), size: 16),
                ),
              ],
            ),
          );
        }),
        GestureDetector(
          onTap: () => setState(() => _schedules.add(_ScheduleEntry())),
          child: Row(
            children: [
              Icon(Icons.add, color: Colors.white.withValues(alpha: 0.8), size: 14),
              const SizedBox(width: 4),
              Text('일정 추가', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Divider(color: Colors.white.withValues(alpha: 0.3), thickness: 1),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPlacesSection(bool isMe) {
    final places = _mePlaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            const Text('방문한 장소', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: _openMaps,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.map_outlined, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('지도 열기', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(places.length, (i) {
          final place = places[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: place.nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: '장소 이름',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showPlaceSearch(place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.8), size: 20),
                      ),
                    ),
                    ...List.generate(5, (s) {
                      final currentRating = isMe ? place.meRating : place.partnerRating;
                      return GestureDetector(
                        onTap: () => setState(() {
                          final next = s + 1 == currentRating ? 0 : s + 1;
                          if (isMe) place.meRating = next;
                          else place.partnerRating = next;
                        }),
                        child: Icon(
                          s < currentRating ? Icons.star : Icons.star_border,
                          color: Colors.yellow,
                          size: 20,
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() {
                        places.removeAt(i);
                      }),
                      child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.6), size: 18),
                    ),
                  ],
                ),
                if (place.address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Text(
                      place.address,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                    ),
                  ),
              ],
            ),
          );
        }),
        GestureDetector(
          onTap: () => setState(() => places.add(_PlaceEntry())),
          child: Row(
            children: [
              Icon(Icons.add, color: Colors.white.withValues(alpha: 0.8), size: 16),
              const SizedBox(width: 4),
              Text('장소 추가', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String label,
    required List<_PhotoEntry> entries,
    required bool isMe,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildScheduleSection(),
          _buildEntriesList(entries, isMe, isMe ? _meTopController : _partnerTopController),
          const SizedBox(height: 16),
          _buildPlacesSection(isMe),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
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
              // 상단바
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        _dateLabel,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    _saving
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                          )
                        : IconButton(
                            onPressed: _save,
                            icon: const Icon(Icons.check,
                                color: Colors.white, size: 28),
                          ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        appRoute(GalleryScreen(date: widget.date)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 26),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) {
                        if (value == 'reset') _confirmAndReset();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'reset',
                          child: Row(
                            children: [
                              Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('전체 초기화', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 탭 버튼
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showMe = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _showMe ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              '영욱 💕',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _showMe ? const Color(0xFFE91E63) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showMe = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_showMe ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              '소영 💕',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !_showMe ? const Color(0xFFE91E63) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 선택된 탭 내용
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      if (_showMe)
                        _buildSection(
                          label: '영욱 💕',
                          entries: _meEntries,
                          isMe: true,
                        )
                      else
                        _buildSection(
                          label: '소영 💕',
                          entries: _partnerEntries,
                          isMe: false,
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  final String url;
  const _FullScreenPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

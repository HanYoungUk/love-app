import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

const _bucket = 'love-app-4e2ac.firebasestorage.app';

class _Photo {
  final String storagePath;
  final String url;
  const _Photo({required this.storagePath, required this.url});
}

Future<String?> _getToken() async {
  try {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (_) {
    return null;
  }
}

Future<void> _deletePhoto(_Photo photo) async {
  if (kIsWeb) {
    final token = await _getToken();
    if (token == null) return;
    final encoded = Uri.encodeComponent(photo.storagePath);
    await http.delete(
      Uri.parse('https://firebasestorage.googleapis.com/v0/b/$_bucket/o/$encoded'),
      headers: {'Authorization': 'Bearer $token'},
    );
  } else {
    await FirebaseStorage.instance.ref(photo.storagePath).delete();
  }
}

// ─── 갤러리 화면 ─────────────────────────────────────────

class GalleryScreen extends StatefulWidget {
  final DateTime date;
  const GalleryScreen({super.key, required this.date});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<_Photo> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  String get _dateKey {
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get _prefix => 'diary/$_dateKey/';

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (kIsWeb) {
        final token = await _getToken();
        if (token == null) return;
        final encoded = Uri.encodeComponent(_prefix);
        final res = await http.get(
          Uri.parse(
              'https://firebasestorage.googleapis.com/v0/b/$_bucket/o?prefix=$encoded'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200 && mounted) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final items = (data['items'] as List<dynamic>?) ?? [];
          final photos = <_Photo>[];
          for (final item in items) {
            final map = item as Map<String, dynamic>;
            final name = map['name'] as String;
            final tokens = (map['downloadTokens'] as String? ?? '').split(',');
            if (tokens.isEmpty) continue;
            final encodedName = Uri.encodeComponent(name);
            final url =
                'https://firebasestorage.googleapis.com/v0/b/$_bucket/o/$encodedName?alt=media&token=${tokens.first}';
            photos.add(_Photo(storagePath: name, url: url));
          }
          setState(() => _photos = photos);
        }
      } else {
        final result =
            await FirebaseStorage.instance.ref(_prefix).listAll();
        final photos = <_Photo>[];
        for (final ref in result.items) {
          final url = await ref.getDownloadURL();
          photos.add(_Photo(storagePath: ref.fullPath, url: url));
        }
        if (mounted) setState(() => _photos = photos);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (image == null) return;
    setState(() => _uploading = true);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${_prefix}photo_$timestamp.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final bytes = await image.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      await _loadPhotos();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _confirmDelete(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('사진 삭제',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('이 사진을 삭제할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('삭제',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _PhotoViewer(
          photos: List.from(_photos),
          initialIndex: index,
          onDeleteConfirm: _confirmDelete,
        ),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) => _loadPhotos());
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6B9D), Color(0xFFE91E63), Color(0xFFC2185B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 헤더
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${d.year}년 ${d.month}월 ${d.day}일',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (!_loading)
                            Text(
                              '사진 ${_photos.length}장',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    _uploading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            onPressed: _upload,
                            icon: const Icon(Icons.add_photo_alternate_outlined,
                                color: Colors.white, size: 28),
                          ),
                  ],
                ),
              ),

              // 그리드
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFE91E63)))
                      : _photos.isEmpty
                          ? _buildEmpty()
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: GridView.builder(
                                padding: const EdgeInsets.all(3),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                ),
                                itemCount: _photos.length,
                                itemBuilder: (_, index) => GestureDetector(
                                  onTap: () => _openViewer(index),
                                  child: Image.network(
                                    _photos[index].url,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: Colors.grey.shade100,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFE91E63)),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('사진이 없어요',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          const SizedBox(height: 6),
          Text('오른쪽 위 + 버튼으로 추가해보세요 💕',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── 전체화면 뷰어 ────────────────────────────────────────

class _PhotoViewer extends StatefulWidget {
  final List<_Photo> photos;
  final int initialIndex;
  final Future<bool> Function(BuildContext) onDeleteConfirm;

  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDeleteConfirm,
  });

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pageController;
  late final List<_Photo> _photos;
  late int _current;
  bool _deleting = false;
  bool _barsVisible = true;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.photos);
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final confirmed = await widget.onDeleteConfirm(context);
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _deletePhoto(_photos[_current]);
      setState(() {
        _photos.removeAt(_current);
        if (_photos.isEmpty) {
          Navigator.pop(context);
          return;
        }
        if (_current >= _photos.length) {
          _current = _photos.length - 1;
          _pageController.jumpToPage(_current);
        }
      });
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _barsVisible = !_barsVisible),
        child: Stack(
          children: [
            // 사진 스와이프
            PageView.builder(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _current = i),
              itemCount: _photos.length,
              itemBuilder: (_, index) => InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Center(
                  child: Image.network(
                    _photos[index].url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                  ),
                ),
              ),
            ),

            // 상단 바
            AnimatedOpacity(
              opacity: _barsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 26),
                        ),
                        const Spacer(),
                        Text(
                          '${_current + 1} / ${_photos.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        _deleting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                onPressed: _handleDelete,
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.white, size: 26),
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

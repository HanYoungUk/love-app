import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/download_helper.dart';
import '../theme/app_theme.dart';

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
  int _uploadProgress = 0;
  int _uploadTotal = 0;
  bool _downloading = false;
  int _downloadProgress = 0;

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
      final result = await FirebaseStorage.instance.ref(_prefix).listAll();
      final photos = <_Photo>[];
      for (final ref in result.items) {
        final url = await ref.getDownloadURL();
        photos.add(_Photo(storagePath: ref.fullPath, url: url));
      }
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final images = await ImagePicker().pickMultiImage(imageQuality: 75);
    if (images.isEmpty) return;
    setState(() { _uploading = true; _uploadProgress = 0; _uploadTotal = images.length; });
    try {
      for (final image in images) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${_prefix}photo_$timestamp.jpg';
        final ref = FirebaseStorage.instance.ref(path);
        final bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        if (mounted) setState(() => _uploadProgress++);
      }
      await _loadPhotos();
    } finally {
      if (mounted) setState(() { _uploading = false; _uploadProgress = 0; _uploadTotal = 0; });
    }
  }

  Future<void> _downloadAll() async {
    if (_photos.isEmpty) return;
    setState(() { _downloading = true; _downloadProgress = 0; });
    try {
      final files = _photos.asMap().entries
          .map((e) => (url: e.value.url, filename: '${_dateKey}_${e.key + 1}.jpg'))
          .toList();
      final result = await downloadAll(
        files,
        onProgress: (done, total) {
          if (mounted) setState(() => _downloadProgress = done);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.contains('/')
              ? '${_photos.length}장 저장 완료!\n$result'
              : '${_photos.length}장 다운로드 완료!'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _downloadProgress = 0; });
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
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
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
                    if (_downloading)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            ),
                            const SizedBox(width: 6),
                            Text('$_downloadProgress/${_photos.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      )
                    else if (_photos.isNotEmpty)
                      IconButton(
                        onPressed: _downloadAll,
                        icon: const Icon(Icons.download_outlined,
                            color: Colors.white, size: 26),
                        tooltip: '전체 다운로드',
                      ),
                    _uploading
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                ),
                                const SizedBox(width: 6),
                                Text('$_uploadProgress/$_uploadTotal',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          )
                        : IconButton(
                            onPressed: _upload,
                            icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Colors.white,
                                size: 28),
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
                      ? Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary))
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
                                        child: Center(
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTheme.primary),
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

class _Photo {
  final String storagePath;
  final String url;
  const _Photo({required this.storagePath, required this.url});
}

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
  bool _downloading = false;
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

  Future<void> _handleDownload() async {
    setState(() => _downloading = true);
    try {
      final filename = '${_photos[_current].storagePath.split('/').last}';
      await downloadFile(_photos[_current].url, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('다운로드 완료!'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await widget.onDeleteConfirm(context);
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await FirebaseStorage.instance.ref(_photos[_current].storagePath).delete();
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
                        child:
                            CircularProgressIndicator(color: Colors.white),
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
                        _downloading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                onPressed: _handleDownload,
                                icon: const Icon(Icons.download_outlined,
                                    color: Colors.white, size: 26),
                              ),
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class BucketListScreen extends StatefulWidget {
  const BucketListScreen({super.key});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen> {
  final _db = FirebaseFirestore.instance;
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _db.collection('bucket_list').orderBy('createdAt').get();
      if (mounted) {
        setState(() {
          _items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final doc = await _db.collection('bucket_list').add({
      'title': title,
      'isDone': false,
      'authorUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      _items.add({'id': doc.id, 'title': title, 'isDone': false});
    });
    _ctrl.clear();
  }

  Future<void> _toggle(int index) async {
    final item = _items[index];
    final newDone = !(item['isDone'] as bool? ?? false);
    await _db.collection('bucket_list').doc(item['id'] as String).update({'isDone': newDone});
    if (mounted) setState(() => _items[index]['isDone'] = newDone);
  }

  Future<void> _delete(int index) async {
    final item = _items[index];
    await _db.collection('bucket_list').doc(item['id'] as String).delete();
    if (mounted) setState(() => _items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final done = _items.where((e) => e['isDone'] == true).length;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradient,
            stops: AppTheme.gradientStops,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: AppTheme.onGradient),
                    ),
                    Text(
                      '우리 버킷리스트 🌟',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onGradient),
                    ),
                  ],
                ),
              ),

              // 진행률
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$done / $total 완료',
                          style: TextStyle(color: AppTheme.onGradient, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: AppTheme.onGradient, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppTheme.overlayAlpha(0.3),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppTheme.onGradient),
                        minHeight: 10,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 입력 필드
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _ctrl,
                          decoration: const InputDecoration(
                            hintText: '함께 하고 싶은 것을 추가해요',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _add,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppTheme.overlayAlpha(0.25),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.overlayAlpha(0.5)),
                        ),
                        child: Icon(Icons.add, color: AppTheme.onGradient, size: 28),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 리스트
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.onGradient))
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('✨', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  '아직 버킷리스트가 없어요\n함께 하고 싶은 것들을 추가해보세요!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.onGradientAlpha(0.9),
                                    fontSize: 15,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              final isDone = item['isDone'] as bool? ?? false;
                              return Dismissible(
                                key: Key(item['id'] as String),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => _delete(i),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade400,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.delete_outline, color: Colors.white),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _toggle(i),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isDone ? AppTheme.primary : Colors.transparent,
                                            border: Border.all(
                                              color: isDone ? AppTheme.primary : Colors.grey.shade300,
                                              width: 2,
                                            ),
                                          ),
                                          child: isDone
                                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          item['title'] as String? ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: isDone ? Colors.grey : Colors.black87,
                                            decoration: isDone ? TextDecoration.lineThrough : null,
                                            decorationColor: Colors.grey,
                                          ),
                                        ),
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
        ),
      ),
    );
  }
}

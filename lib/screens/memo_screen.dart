import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

const _projectId = 'love-app-4e2ac';

class MemoScreen extends StatefulWidget {
  final DateTime date;
  final String? initialText;

  const MemoScreen({super.key, required this.date, this.initialText});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  late final TextEditingController _controller;
  bool _saving = false;

  String get _dateKey {
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String?> _getIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    setState(() => _saving = true);
    try {
      if (text.isEmpty) {
        await _delete(pop: true);
        return;
      }
      if (kIsWeb) {
        final token = await _getIdToken();
        if (token == null) return;
        await http.patch(
          Uri.parse(
              'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/memos/$_dateKey'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'fields': {
              'text': {'stringValue': text}
            }
          }),
        );
      } else {
        await FirebaseFirestore.instance
            .collection('memos')
            .doc(_dateKey)
            .set({'text': text});
      }
      if (mounted) Navigator.pop(context, text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete({bool pop = false}) async {
    try {
      if (kIsWeb) {
        final token = await _getIdToken();
        if (token == null) return;
        await http.delete(
          Uri.parse(
              'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/memos/$_dateKey'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        await FirebaseFirestore.instance
            .collection('memos')
            .doc(_dateKey)
            .delete();
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context, '');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final hasExisting = (widget.initialText ?? '').isNotEmpty;

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
                      child: Text(
                        '${d.year}년 ${d.month}월 ${d.day}일',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // 본문
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Row(
                          children: [
                            const Text('📝', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            const Text(
                              '간단 메모',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                                fontSize: 16, height: 1.6, color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: '이 날의 기억을 남겨보세요 💕',
                              hintStyle:
                                  TextStyle(color: Colors.grey.shade400, fontSize: 15),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),

                      // 버튼 영역
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: Row(
                          children: [
                            if (hasExisting) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : () => _delete(),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
                                  label: const Text('삭제',
                                      style: TextStyle(color: Colors.red)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.favorite,
                                        size: 18, color: Colors.white),
                                label: Text(
                                  _saving ? '저장 중...' : '저장',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE91E63),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

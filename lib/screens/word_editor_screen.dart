import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/word.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_glow_border.dart';

class WordEditorScreen extends StatefulWidget {
  const WordEditorScreen({super.key});

  @override
  State<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends State<WordEditorScreen> {
  static const _storageKey = 'custom_words';
  final _controller = TextEditingController();
  List<Word> _customWords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _customWords =
          list.map((e) => Word.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_customWords.map((w) => w.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  void _addWord() {
    final text = _controller.text.trim().toLowerCase();
    if (text.isEmpty || !RegExp(r'^[a-zA-Z]+$').hasMatch(text)) return;
    if (_customWords.any((w) => w.text.toLowerCase() == text)) return;

    setState(() {
      _customWords.add(Word(
        id: 'custom_${const Uuid().v4()}',
        text: text,
        level: 0,
        isCustom: true,
      ));
      _controller.clear();
    });
    _save();
  }

  void _removeWord(int index) {
    setState(() => _customWords.removeAt(index));
    _save();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGlowBorder(
        state: GlowState.idle,
        borderRadius: 0,
        strokeWidth: 2,
        glowRadius: 18,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.background, AppColors.backgroundEnd],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.primaryText),
                      ),
                      Text(
                        'Custom Words',
                        style: AppFonts.fredoka(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: TextField(
                            controller: _controller,
                            textCapitalization: TextCapitalization.none,
                            decoration: InputDecoration(
                              hintText: 'Type a word...',
                              hintStyle: AppFonts.nunito(
                                color: AppColors.secondaryText
                                    .withValues(alpha: 0.5),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            style: AppFonts.fredoka(
                              fontSize: 18,
                              color: AppColors.primaryText,
                            ),
                            onSubmitted: (_) => _addWord(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _addWord,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.electricBlue,
                                AppColors.cyan,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Note: Custom words need audio files generated. See the README for the TTS generation script.',
                    style: AppFonts.nunito(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _customWords.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.edit_note_rounded,
                                    color: AppColors.secondaryText,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No custom words yet',
                                    style: AppFonts.fredoka(
                                      fontSize: 18,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  Text(
                                    'Add words above to practice!',
                                    style: AppFonts.nunito(
                                      fontSize: 14,
                                      color: AppColors.secondaryText
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              itemCount: _customWords.length,
                              itemBuilder: (context, index) {
                                final word = _customWords[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border:
                                          Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          word.text,
                                          style: AppFonts.fredoka(
                                            fontSize: 20,
                                            color: AppColors.primaryText,
                                          ),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () => _removeWord(index),
                                          child: Icon(
                                            Icons.close_rounded,
                                            color: AppColors.error
                                                .withValues(alpha: 0.6),
                                            size: 22,
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
      ),
    );
  }
}

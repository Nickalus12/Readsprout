import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/voices.dart';
import '../data/word_data.dart';
import '../services/audio_scanner.dart';
import '../services/deepgram_service.dart';
import '../theme.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/voice_selector.dart';

/// Single word generator screen with preview and compare.
class GenerateScreen extends StatefulWidget {
  final DeepgramService deepgram;
  final AudioScanner scanner;
  final String audioBasePath;

  const GenerateScreen({
    super.key,
    required this.deepgram,
    required this.scanner,
    required this.audioBasePath,
  });

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _textController = TextEditingController();
  String _selectedVoice = Voices.defaultVoice;
  double _speed = 0.8;
  String _category = 'words'; // which subdir
  bool _isGenerating = false;
  bool _isPreviewing = false;
  Uint8List? _previewBytes;
  String? _error;
  AudioFileInfo? _existingFile;

  // Quick-pick words
  final List<String> _recentWords = [];

  void _checkExisting() {
    final word = _textController.text.trim().toLowerCase();
    if (word.isEmpty) {
      setState(() => _existingFile = null);
      return;
    }

    setState(() {
      _existingFile = widget.scanner.checkFile(
        key: word,
        displayText: word,
        category: _category,
        subdir: _category,
      );
    });
  }

  Future<void> _preview() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isPreviewing = true;
      _error = null;
      _previewBytes = null;
    });

    final result = await widget.deepgram.generate(
      text,
      voice: _selectedVoice,
      speed: _speed,
    );

    if (mounted) {
      setState(() {
        _isPreviewing = false;
        if (result.success) {
          _previewBytes = result.audioBytes;
        } else {
          _error = result.error;
        }
      });
    }
  }

  Future<void> _generateAndSave() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final key = text.toLowerCase();
    final subdir = _category;
    final path = '${widget.audioBasePath}/$subdir/$key.mp3';

    // Check if file exists and confirm overwrite
    if (File(path).existsSync()) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Overwrite?'),
          content: Text('$key.mp3 already exists. Overwrite it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    final result = await widget.deepgram.generateToFile(
      text,
      path,
      voice: _selectedVoice,
      speed: _speed,
    );

    if (mounted) {
      setState(() => _isGenerating = false);

      if (result.success) {
        _recentWords.insert(0, text);
        if (_recentWords.length > 10) _recentWords.removeLast();
        _checkExisting();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: $key.mp3'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() => _error = result.error);
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Single Word Generator',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Generate or regenerate audio for a single word or phrase.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // Quick pick
          if (_recentWords.isNotEmpty) ...[
            const Text(
              'Recent',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: _recentWords.map((w) {
                return ActionChip(
                  label: Text(w, style: const TextStyle(fontSize: 12)),
                  backgroundColor: AppTheme.surfaceLight,
                  side: BorderSide(color: AppTheme.divider),
                  onPressed: () {
                    _textController.text = w;
                    _checkExisting();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text input
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: 'Word or phrase to speak',
                        hintText: 'e.g., hello',
                      ),
                      style: const TextStyle(fontSize: 18),
                      onChanged: (_) => _checkExisting(),
                      onSubmitted: (_) => _preview(),
                    ),
                    const SizedBox(height: 12),
                    // Category selector
                    Row(
                      children: [
                        const Text(
                          'Save to:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'words', label: Text('words')),
                            ButtonSegment(value: 'letters', label: Text('letters')),
                            ButtonSegment(value: 'letter_names', label: Text('letter_names')),
                            ButtonSegment(value: 'phonics', label: Text('phonics')),
                            ButtonSegment(value: 'effects', label: Text('effects')),
                            ButtonSegment(value: 'phrases', label: Text('phrases')),
                          ],
                          selected: {_category},
                          onSelectionChanged: (s) {
                            setState(() => _category = s.first);
                            _checkExisting();
                          },
                          style: ButtonStyle(
                            textStyle: WidgetStatePropertyAll(
                              const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Voice controls
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    VoiceSelector(
                      selectedVoiceId: _selectedVoice,
                      onChanged: (v) => setState(() => _selectedVoice = v),
                    ),
                    const SizedBox(height: 8),
                    SpeedSlider(
                      value: _speed,
                      onChanged: (v) => setState(() => _speed = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                icon: _isPreviewing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Preview'),
                onPressed: _isPreviewing || _textController.text.trim().isEmpty
                    ? null
                    : _preview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Generate & Save'),
                onPressed: _isGenerating || _textController.text.trim().isEmpty
                    ? null
                    : _generateAndSave,
              ),
            ],
          ),

          // Error
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Side-by-side comparison
          if (_previewBytes != null || _existingFile?.status == AudioStatus.exists)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Existing audio
                if (_existingFile?.status == AudioStatus.exists)
                  Expanded(
                    child: AudioPlayerWidget(
                      filePath: _existingFile!.expectedPath,
                      label: 'Current (${_existingFile!.fileSizeDisplay})',
                    ),
                  ),
                if (_existingFile?.status == AudioStatus.exists &&
                    _previewBytes != null)
                  const SizedBox(width: 16),
                // Preview audio
                if (_previewBytes != null)
                  Expanded(
                    child: AudioPlayerWidget(
                      audioBytes: _previewBytes,
                      label: 'Preview (${(_previewBytes!.length / 1024).toStringAsFixed(1)}KB)',
                    ),
                  ),
              ],
            ),

          const SizedBox(height: 24),

          // Quick word lists
          const Divider(color: AppTheme.divider),
          const SizedBox(height: 12),
          const Text(
            'Quick Pick',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildQuickPicks(),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show first few levels
        for (int level = 1; level <= 5; level++) ...[
          Text(
            'Level $level',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: WordData.dolchWordsByLevel[level - 1].map((w) {
              return ActionChip(
                label: Text(w, style: const TextStyle(fontSize: 12)),
                backgroundColor: AppTheme.surfaceLight,
                side: BorderSide(color: AppTheme.divider),
                onPressed: () {
                  _textController.text = w;
                  _checkExisting();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

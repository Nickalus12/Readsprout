import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/voices.dart';
import '../data/word_data.dart';
import '../services/audio_scanner.dart';
import '../services/deepgram_service.dart';
import '../services/envelope_generator.dart';
import '../theme.dart';
import '../widgets/voice_selector.dart';

/// Batch generation screen — generate all missing or regenerate all.
class BatchScreen extends StatefulWidget {
  final DeepgramService deepgram;
  final AudioScanner scanner;
  final EnvelopeGenerator envelopeGen;
  final String audioBasePath;

  const BatchScreen({
    super.key,
    required this.deepgram,
    required this.scanner,
    required this.envelopeGen,
    required this.audioBasePath,
  });

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

enum BatchCategory {
  words('Words (Dolch + Bonus)', 'words'),
  letterNames('Letter Names', 'letter_names'),
  phonics('Phonics', 'phonics'),
  stickers('Sticker Names', 'words'),
  genericWelcomes('Generic Welcomes', 'words'),
  effects('Effects', 'effects');

  final String label;
  final String subdir;

  const BatchCategory(this.label, this.subdir);
}

class _BatchScreenState extends State<BatchScreen> {
  BatchCategory _selectedCategory = BatchCategory.words;
  String _selectedVoice = Voices.defaultVoice;
  double _speed = 0.8;
  int _workers = 3;
  bool _skipExisting = true;
  bool _isRunning = false;
  bool _isCancelled = false;

  // Progress
  int _totalItems = 0;
  int _completedItems = 0;
  int _skippedItems = 0;
  int _failedItems = 0;
  String _currentItem = '';
  final List<String> _log = [];
  DateTime? _startTime;

  List<({String key, String text, String path})> _getItemsForCategory() {
    switch (_selectedCategory) {
      case BatchCategory.words:
        final items = <({String key, String text, String path})>[];
        for (final w in WordData.allWords) {
          items.add((
            key: w,
            text: w,
            path: p.join(widget.audioBasePath, 'words', '$w.mp3'),
          ));
        }
        for (final w in WordData.extraWords) {
          items.add((
            key: w,
            text: w,
            path: p.join(widget.audioBasePath, 'words', '$w.mp3'),
          ));
        }
        return items;

      case BatchCategory.letterNames:
        return WordData.letterNames.entries.map((e) => (
          key: e.key,
          text: e.value,
          path: p.join(widget.audioBasePath, 'letter_names', '${e.key}.mp3'),
        )).toList();

      case BatchCategory.phonics:
        return WordData.letterPhonics.entries.map((e) => (
          key: e.key,
          text: e.value,
          path: p.join(widget.audioBasePath, 'phonics', '${e.key}.mp3'),
        )).toList();

      case BatchCategory.stickers:
        return WordData.stickerAudio.entries.map((e) => (
          key: e.key,
          text: e.value,
          path: p.join(widget.audioBasePath, 'words', '${e.key}.mp3'),
        )).toList();

      case BatchCategory.genericWelcomes:
        return WordData.genericWelcomes.entries.map((e) => (
          key: e.key,
          text: e.value,
          path: p.join(widget.audioBasePath, 'words', '${e.key}.mp3'),
        )).toList();

      case BatchCategory.effects:
        return WordData.effects.entries.map((e) => (
          key: e.key,
          text: e.value,
          path: p.join(widget.audioBasePath, 'effects', '${e.key}.mp3'),
        )).toList();
    }
  }

  Future<void> _startBatch() async {
    final items = _getItemsForCategory();

    setState(() {
      _isRunning = true;
      _isCancelled = false;
      _totalItems = items.length;
      _completedItems = 0;
      _skippedItems = 0;
      _failedItems = 0;
      _currentItem = '';
      _log.clear();
      _startTime = DateTime.now();
    });

    _addLog('Starting batch: ${_selectedCategory.label}');
    _addLog('Voice: $_selectedVoice, Speed: ${_speed}x, Workers: $_workers');
    _addLog('Total items: ${items.length}, Skip existing: $_skipExisting');
    _addLog('');

    // Process items with concurrency
    final pool = <Future<void>>[];
    int index = 0;

    Future<void> processItem(({String key, String text, String path}) item) async {
      if (_isCancelled) return;

      // Check if file exists
      if (_skipExisting) {
        final info = widget.scanner.checkFile(
          key: item.key,
          displayText: item.text,
          category: _selectedCategory.subdir,
          subdir: _selectedCategory.subdir,
        );
        if (info.status == AudioStatus.exists) {
          setState(() {
            _skippedItems++;
            _completedItems++;
          });
          return;
        }
      }

      setState(() => _currentItem = item.key);

      final result = await widget.deepgram.generateToFile(
        item.text,
        item.path,
        voice: _selectedVoice,
        speed: _speed,
      );

      if (mounted) {
        if (result.success) {
          setState(() => _completedItems++);
          _addLog('[OK] ${item.key}');
        } else {
          setState(() {
            _failedItems++;
            _completedItems++;
          });
          _addLog('[FAIL] ${item.key}: ${result.error}');
        }
      }
    }

    // Simple concurrency pool
    for (final item in items) {
      if (_isCancelled) break;

      pool.add(processItem(item));
      index++;

      if (pool.length >= _workers || index >= items.length) {
        await Future.wait(pool);
        pool.clear();
      }
    }

    if (mounted) {
      final elapsed = DateTime.now().difference(_startTime!);
      _addLog('');
      _addLog('Batch complete in ${elapsed.inSeconds}s');
      _addLog('Generated: ${_completedItems - _skippedItems - _failedItems}');
      _addLog('Skipped: $_skippedItems');
      _addLog('Failed: $_failedItems');

      setState(() {
        _isRunning = false;
        _currentItem = '';
      });
    }
  }

  void _cancelBatch() {
    setState(() => _isCancelled = true);
    _addLog('');
    _addLog('CANCELLED by user');
  }

  void _addLog(String message) {
    setState(() {
      _log.add(message);
    });
  }

  String get _eta {
    if (_startTime == null || _completedItems == 0) return '--';
    final elapsed = DateTime.now().difference(_startTime!);
    final remaining = _totalItems - _completedItems;
    final perItem = elapsed.inMilliseconds / _completedItems;
    final etaMs = (remaining * perItem).round();
    final eta = Duration(milliseconds: etaMs);
    if (eta.inMinutes > 0) {
      return '${eta.inMinutes}m ${eta.inSeconds % 60}s';
    }
    return '${eta.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalItems > 0 ? _completedItems / _totalItems : 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Batch Generator',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Generate all missing audio files or regenerate an entire category.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // Controls
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category + options
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<BatchCategory>(
                      initialValue: _selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      dropdownColor: AppTheme.surfaceLight,
                      items: BatchCategory.values.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(c.label),
                        );
                      }).toList(),
                      onChanged: _isRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedCategory = v);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    VoiceSelector(
                      selectedVoiceId: _selectedVoice,
                      onChanged: _isRunning
                          ? (_) {}
                          : (v) => setState(() => _selectedVoice = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Speed + workers
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Speed
                    Row(
                      children: [
                        Text(
                          'Speed: ${_speed.toStringAsFixed(2)}x',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _speed,
                            min: 0.5,
                            max: 2.0,
                            divisions: 30,
                            onChanged: _isRunning
                                ? null
                                : (v) => setState(() => _speed = v),
                          ),
                        ),
                      ],
                    ),
                    // Workers
                    Row(
                      children: [
                        Text(
                          'Workers: $_workers',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _workers.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$_workers',
                            onChanged: _isRunning
                                ? null
                                : (v) => setState(() => _workers = v.round()),
                          ),
                        ),
                      ],
                    ),
                    // Skip existing
                    CheckboxListTile(
                      title: const Text(
                        'Skip existing files',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: _skipExisting,
                      onChanged: _isRunning
                          ? null
                          : (v) => setState(() => _skipExisting = v ?? true),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(_skipExisting
                    ? 'Generate Missing'
                    : 'Regenerate All'),
                onPressed: _isRunning ? null : _startBatch,
              ),
              const SizedBox(width: 12),
              if (_isRunning)
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                  onPressed: _cancelBatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                  ),
                ),
              const Spacer(),
              // Item count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_getItemsForCategory().length} items in ${_selectedCategory.label}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress
          if (_isRunning || _log.isNotEmpty) ...[
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            // Stats
            Row(
              children: [
                _statBadge(
                    'Progress', '$_completedItems/$_totalItems', AppTheme.accent),
                const SizedBox(width: 12),
                _statBadge(
                    'Skipped', '$_skippedItems', AppTheme.textSecondary),
                const SizedBox(width: 12),
                _statBadge('Failed', '$_failedItems',
                    _failedItems > 0 ? AppTheme.error : AppTheme.textSecondary),
                const SizedBox(width: 12),
                if (_isRunning) ...[
                  _statBadge('ETA', _eta, AppTheme.textSecondary),
                  const SizedBox(width: 12),
                  Text(
                    'Current: $_currentItem',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Log
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (context, index) {
                    final line = _log[index];
                    Color color = AppTheme.textSecondary;
                    if (line.startsWith('[OK]')) {
                      color = AppTheme.success;
                    } else if (line.startsWith('[FAIL]')) {
                      color = AppTheme.error;
                    } else if (line.startsWith('CANCELLED')) {
                      color = AppTheme.warning;
                    }
                    return Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        color: color,
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.batch_prediction,
                      size: 48,
                      color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select a category and click Generate to start.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

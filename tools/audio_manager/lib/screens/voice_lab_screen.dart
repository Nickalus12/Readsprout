import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/voices.dart';
import '../services/deepgram_service.dart';
import '../theme.dart';
import '../widgets/audio_player_widget.dart';

/// Voice Lab — test and compare different voices.
class VoiceLabScreen extends StatefulWidget {
  final DeepgramService deepgram;

  const VoiceLabScreen({
    super.key,
    required this.deepgram,
  });

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _VoiceLabScreenState extends State<VoiceLabScreen> {
  final _textController = TextEditingController(text: 'Hello, how are you?');
  double _speed = 0.8;
  final Map<String, _VoiceResult> _results = {};
  final Set<String> _generating = {};

  Future<void> _generateForVoice(String voiceId) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _generating.add(voiceId));

    final result = await widget.deepgram.generate(
      text,
      voice: voiceId,
      speed: _speed,
    );

    if (mounted) {
      setState(() {
        _generating.remove(voiceId);
        if (result.success) {
          _results[voiceId] = _VoiceResult(
            bytes: result.audioBytes!,
            text: text,
            speed: _speed,
          );
        } else {
          _results[voiceId] = _VoiceResult(
            bytes: null,
            text: text,
            speed: _speed,
            error: result.error,
          );
        }
      });
    }
  }

  Future<void> _generateAll() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    for (final voice in Voices.all) {
      if (!mounted) break;
      await _generateForVoice(voice.id);
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
          const Text(
            'Voice Lab',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Compare different Deepgram Aura-2 voices side by side.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'Text to speak',
                    hintText: 'Type any word or phrase...',
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text(
                    'Speed: ${_speed.toStringAsFixed(2)}x',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Slider(
                      value: _speed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      onChanged: (v) => setState(() => _speed = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Generate All'),
                onPressed: _generating.isNotEmpty ? null : _generateAll,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Sample phrases
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _sampleChip('Hello!'),
              _sampleChip('Great job, Patience!'),
              _sampleChip('Can you read this word?'),
              _sampleChip('The cat sat on the mat.'),
              _sampleChip('Welcome!'),
              _sampleChip('Level complete!'),
              _sampleChip('ay'),
              _sampleChip('buh'),
            ],
          ),
          const SizedBox(height: 24),

          // Voice grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: Voices.all.length,
            itemBuilder: (context, index) {
              final voice = Voices.all[index];
              return _buildVoiceCard(voice);
            },
          ),
        ],
      ),
    );
  }

  Widget _sampleChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppTheme.surfaceLight,
      side: BorderSide(color: AppTheme.divider),
      onPressed: () {
        _textController.text = text;
        setState(() {
          _results.clear();
        });
      },
    );
  }

  Widget _buildVoiceCard(Voice voice) {
    final isGenerating = _generating.contains(voice.id);
    final result = _results[voice.id];
    final hasError = result?.error != null;
    final hasAudio = result?.bytes != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasAudio
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                voice.gender == 'Male' ? Icons.male : Icons.female,
                size: 16,
                color: voice.gender == 'Male'
                    ? Colors.lightBlue
                    : Colors.pinkAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voice.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      voice.description,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Generate button
              IconButton(
                icon: isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        hasAudio ? Icons.refresh : Icons.play_arrow,
                        size: 18,
                      ),
                onPressed: isGenerating
                    ? null
                    : () => _generateForVoice(voice.id),
                tooltip: 'Generate',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const Spacer(),
          // Audio player or status
          if (hasAudio)
            AudioPlayerWidget(
              audioBytes: result!.bytes,
              compact: true,
            )
          else if (hasError)
            Text(
              result!.error!,
              style: const TextStyle(fontSize: 10, color: AppTheme.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              voice.id,
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceResult {
  final Uint8List? bytes;
  final String text;
  final double speed;
  final String? error;

  const _VoiceResult({
    this.bytes,
    required this.text,
    required this.speed,
    this.error,
  });
}

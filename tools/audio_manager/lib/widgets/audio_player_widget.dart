import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../theme.dart';

/// Widget that plays an MP3 file and shows a waveform if .amp.json exists.
class AudioPlayerWidget extends StatefulWidget {
  final String? filePath;
  final Uint8List? audioBytes;
  final String label;
  final bool compact;

  const AudioPlayerWidget({
    super.key,
    this.filePath,
    this.audioBytes,
    this.label = '',
    this.compact = false,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<double>? _amplitudes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = Duration.zero;
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _loadAmplitudes();
  }

  void _loadAmplitudes() {
    if (widget.filePath == null) return;
    final ampPath = widget.filePath!.replaceAll('.mp3', '.amp.json');
    final ampFile = File(ampPath);
    if (ampFile.existsSync()) {
      try {
        final json = jsonDecode(ampFile.readAsStringSync());
        final amps = (json['amplitudes'] as List?)?.cast<num>();
        if (amps != null) {
          setState(() {
            _amplitudes = amps.map((a) => a.toDouble()).toList();
          });
        }
      } catch (_) {}
    }
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.audioBytes != widget.audioBytes) {
      _player.stop();
      _isPlaying = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      _amplitudes = null;
      _error = null;
      _loadAmplitudes();
    }
  }

  Future<void> _play() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (widget.filePath != null) {
        final file = File(widget.filePath!);
        if (!file.existsSync()) {
          setState(() {
            _error = 'File not found';
            _isLoading = false;
          });
          return;
        }
        await _player.setFilePath(widget.filePath!);
      } else if (widget.audioBytes != null) {
        // Write bytes to a temp file for playback
        final tempDir = Directory.systemTemp;
        final tempFile = File(p.join(tempDir.path, 'audio_manager_preview.mp3'));
        await tempFile.writeAsBytes(widget.audioBytes!);
        await _player.setFilePath(tempFile.path);
      }
      await _player.play();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _stop() {
    _player.pause();
    _player.seek(Duration.zero);
  }

  String _formatDuration(Duration d) {
    final seconds = d.inSeconds;
    final ms = d.inMilliseconds % 1000;
    return '${seconds}s ${(ms ~/ 100)}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSource = widget.filePath != null || widget.audioBytes != null;

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: hasSource ? AppTheme.accent : AppTheme.textSecondary,
                  ),
            onPressed: hasSource
                ? (_isPlaying ? _stop : _play)
                : null,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (_duration > Duration.zero)
            Text(
              _formatDuration(_duration),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          // Waveform
          if (_amplitudes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 40,
                child: CustomPaint(
                  size: const Size(double.infinity, 40),
                  painter: _WaveformPainter(
                    amplitudes: _amplitudes!,
                    progress: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0,
                  ),
                ),
              ),
            ),
          // Controls
          Row(
            children: [
              IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isPlaying
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: hasSource
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                onPressed: hasSource
                    ? (_isPlaying ? _stop : _play)
                    : null,
              ),
              if (_duration > Duration.zero) ...[
                Expanded(
                  child: Slider(
                    value: _position.inMilliseconds.toDouble().clamp(
                      0,
                      _duration.inMilliseconds.toDouble(),
                    ),
                    max: _duration.inMilliseconds.toDouble(),
                    onChanged: (v) {
                      _player.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;

  _WaveformPainter({required this.amplitudes, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barWidth = size.width / amplitudes.length;
    final maxHeight = size.height;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * barWidth;
      final height = (amplitudes[i] * maxHeight).clamp(2.0, maxHeight);
      final y = (maxHeight - height) / 2;

      final isPlayed = i / amplitudes.length <= progress;
      final paint = Paint()
        ..color = isPlayed
            ? AppTheme.accent.withValues(alpha: 0.9)
            : AppTheme.textSecondary.withValues(alpha: 0.3);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.5, y, barWidth - 1, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes;
  }
}

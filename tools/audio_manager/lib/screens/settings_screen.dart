import 'dart:io';

import 'package:flutter/material.dart';

import '../data/voices.dart';
import '../services/deepgram_service.dart';
import '../services/envelope_generator.dart';
import '../theme.dart';
import '../widgets/voice_selector.dart';

/// Settings screen for API key, defaults, and ffmpeg config.
class SettingsScreen extends StatefulWidget {
  final DeepgramService deepgram;
  final EnvelopeGenerator envelopeGen;
  final String audioBasePath;
  final ValueChanged<String> onAudioBasePathChanged;
  final VoidCallback onApiKeyChanged;

  const SettingsScreen({
    super.key,
    required this.deepgram,
    required this.envelopeGen,
    required this.audioBasePath,
    required this.onAudioBasePathChanged,
    required this.onApiKeyChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _audioPathController;
  late TextEditingController _ffmpegPathController;
  bool _apiKeyVisible = false;
  bool _testingConnection = false;
  bool? _connectionOk;
  bool _ffmpegAvailable = false;
  String? _ffmpegVersion;
  String _defaultVoice = Voices.defaultVoice;
  double _wordSpeed = 0.8;
  double _letterSpeed = 0.75;
  double _phraseSpeed = 0.8;

  // Envelope generation state
  bool _generatingEnvelopes = false;
  String _envelopeStatus = '';
  String _selectedEnvelopeDir = 'words';

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.deepgram.apiKey);
    _audioPathController = TextEditingController(text: widget.audioBasePath);
    _ffmpegPathController =
        TextEditingController(text: widget.envelopeGen.ffmpegPath);
    _defaultVoice = widget.deepgram.defaultVoice;
    _wordSpeed = widget.deepgram.defaultSpeed;
    _checkFfmpeg();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
    });

    widget.deepgram.apiKey = _apiKeyController.text.trim();
    final ok = await widget.deepgram.testConnection();

    if (mounted) {
      setState(() {
        _testingConnection = false;
        _connectionOk = ok;
      });
      widget.onApiKeyChanged();
    }
  }

  Future<void> _checkFfmpeg() async {
    widget.envelopeGen.ffmpegPath = _ffmpegPathController.text.trim().isEmpty
        ? 'ffmpeg'
        : _ffmpegPathController.text.trim();

    final available = await widget.envelopeGen.isAvailable();
    String? version;
    if (available) {
      version = await widget.envelopeGen.getVersion();
    }

    if (mounted) {
      setState(() {
        _ffmpegAvailable = available;
        _ffmpegVersion = version;
      });
    }
  }

  Future<void> _generateEnvelopes() async {
    setState(() {
      _generatingEnvelopes = true;
      _envelopeStatus = 'Starting...';
    });

    final dirPath = '${widget.audioBasePath}/$_selectedEnvelopeDir';

    final result = await widget.envelopeGen.generateAll(
      dirPath,
      skipExisting: true,
      onProgress: (fileName, current, total) {
        if (mounted) {
          setState(() {
            _envelopeStatus = '[$current/$total] $fileName';
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _generatingEnvelopes = false;
        _envelopeStatus =
            'Done: ${result.success} generated, ${result.skipped} skipped, ${result.failed} failed';
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _audioPathController.dispose();
    _ffmpegPathController.dispose();
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
            'Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // ── API Key ──────────────────────────────────────────────
          _sectionHeader('Deepgram API Key'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: !_apiKeyVisible,
                  decoration: InputDecoration(
                    hintText: 'Enter Deepgram API key',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _apiKeyVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () => setState(
                              () => _apiKeyVisible = !_apiKeyVisible),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: _testingConnection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('Test'),
                onPressed: _testingConnection ? null : _testConnection,
              ),
            ],
          ),
          if (_connectionOk != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    _connectionOk!
                        ? Icons.check_circle
                        : Icons.error_outline,
                    size: 16,
                    color: _connectionOk!
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _connectionOk!
                        ? 'Connection successful'
                        : 'Connection failed — check your API key',
                    style: TextStyle(
                      fontSize: 12,
                      color: _connectionOk!
                          ? AppTheme.success
                          : AppTheme.error,
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'Set via DEEPGRAM_API_KEY environment variable or enter above.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // ── Default Voice ────────────────────────────────────────
          _sectionHeader('Default Voice'),
          const SizedBox(height: 8),
          VoiceSelector(
            selectedVoiceId: _defaultVoice,
            onChanged: (v) {
              setState(() => _defaultVoice = v);
              widget.deepgram.defaultVoice = v;
            },
          ),
          const SizedBox(height: 24),

          // ── Default Speeds ───────────────────────────────────────
          _sectionHeader('Default Speeds'),
          const SizedBox(height: 8),
          _speedRow('Words', _wordSpeed, (v) {
            setState(() => _wordSpeed = v);
            widget.deepgram.defaultSpeed = v;
          }),
          _speedRow('Letters / Phonics', _letterSpeed, (v) {
            setState(() => _letterSpeed = v);
          }),
          _speedRow('Phrases', _phraseSpeed, (v) {
            setState(() => _phraseSpeed = v);
          }),
          const SizedBox(height: 24),

          // ── Audio Output Path ────────────────────────────────────
          _sectionHeader('Audio Output Directory'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _audioPathController,
                  decoration: const InputDecoration(
                    hintText: 'Path to assets/audio/',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  widget.onAudioBasePathChanged(
                    _audioPathController.text.trim(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.textPrimary,
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Currently: ${widget.audioBasePath}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // ── ffmpeg ───────────────────────────────────────────────
          _sectionHeader('ffmpeg Path'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ffmpegPathController,
                  decoration: const InputDecoration(
                    hintText: 'ffmpeg (auto-detect)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _checkFfmpeg,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.textPrimary,
                ),
                child: const Text('Check'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  _ffmpegAvailable
                      ? Icons.check_circle
                      : Icons.warning_amber,
                  size: 16,
                  color: _ffmpegAvailable
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _ffmpegAvailable
                        ? 'ffmpeg found: ${_ffmpegVersion ?? "unknown version"}'
                        : 'ffmpeg not found — envelope generation disabled',
                    style: TextStyle(
                      fontSize: 11,
                      color: _ffmpegAvailable
                          ? AppTheme.success
                          : AppTheme.warning,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Amplitude Envelope Generator ─────────────────────────
          _sectionHeader('Amplitude Envelope Generator'),
          const SizedBox(height: 8),
          const Text(
            'Generate .amp.json files for MP3s using ffmpeg. These power the waveform visualization.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DropdownButton<String>(
                value: _selectedEnvelopeDir,
                dropdownColor: AppTheme.surfaceLight,
                items: const [
                  DropdownMenuItem(value: 'words', child: Text('words')),
                  DropdownMenuItem(
                      value: 'letter_names', child: Text('letter_names')),
                  DropdownMenuItem(value: 'phonics', child: Text('phonics')),
                  DropdownMenuItem(value: 'effects', child: Text('effects')),
                  DropdownMenuItem(value: 'phrases', child: Text('phrases')),
                ],
                onChanged: _generatingEnvelopes
                    ? null
                    : (v) {
                        if (v != null) setState(() => _selectedEnvelopeDir = v);
                      },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: _generatingEnvelopes
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.graphic_eq, size: 18),
                label: const Text('Generate Envelopes'),
                onPressed:
                    (_generatingEnvelopes || !_ffmpegAvailable)
                        ? null
                        : _generateEnvelopes,
              ),
            ],
          ),
          if (_envelopeStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _envelopeStatus,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          const SizedBox(height: 32),

          // ── API Stats ────────────────────────────────────────────
          _sectionHeader('Session Stats'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              children: [
                _statRow('API Requests', '${widget.deepgram.totalRequests}'),
                _statRow(
                  'Data Generated',
                  '${(widget.deepgram.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                ),
                _statRow(
                  'Environment Key',
                  Platform.environment.containsKey('DEEPGRAM_API_KEY')
                      ? 'Set'
                      : 'Not set',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _speedRow(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label: ${value.toStringAsFixed(2)}x',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

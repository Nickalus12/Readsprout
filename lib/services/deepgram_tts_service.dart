import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/phrase_templates.dart';

/// Deepgram Aura-2 TTS client for generating personalized audio at runtime.
///
/// Generated files are saved to the app's documents directory under
/// `generated_audio/` and persist across app restarts. AudioService checks
/// these files before falling back to bundled assets.
///
/// Usage flow:
///   1. Player enters their name on profile creation
///   2. App calls [generatePhrasesForName] in the background
///   3. AudioService picks up generated files automatically
///
/// Quota:
///   Free tier: [freeGenerationsPerProfile] phrase sets (one set = ~18 phrases)
///   After that, phrases fall back to text-only (no audio).
class DeepgramTtsService {
  static const String _apiUrl = 'https://api.deepgram.com/v1/speak';
  static const String _defaultVoice = 'aura-2-cordelia-en';
  static const String _prefsKeyPrefix = 'deepgram_tts_';

  /// Max phrase sets a free user can generate (each name = 1 set).
  static const int freeGenerationsPerProfile = 3;

  late SharedPreferences _prefs;
  String? _apiKey;
  String _voice = _defaultVoice;
  late Directory _outputDir;
  bool _initialized = false;

  /// Whether the service has a valid API key configured.
  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// Whether the service is ready to generate audio.
  bool get isReady => _initialized && isConfigured;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _apiKey = _prefs.getString('${_prefsKeyPrefix}api_key');
    _voice = _prefs.getString('${_prefsKeyPrefix}voice') ?? _defaultVoice;

    final appDir = await getApplicationDocumentsDirectory();
    _outputDir = Directory('${appDir.path}/generated_audio');
    await _outputDir.create(recursive: true);

    _initialized = true;
    debugPrint('DeepgramTtsService: initialized (configured=$isConfigured)');
  }

  /// Set or update the Deepgram API key.
  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _prefs.setString('${_prefsKeyPrefix}api_key', key);
  }

  /// Set the TTS voice model.
  Future<void> setVoice(String voice) async {
    _voice = voice;
    await _prefs.setString('${_prefsKeyPrefix}voice', voice);
  }

  // ── Quota tracking ──────────────────────────────────────────────────────

  /// How many phrase sets this profile has generated.
  int generationsUsed(String profileId) {
    return _prefs.getInt('${_prefsKeyPrefix}used_$profileId') ?? 0;
  }

  /// Whether this profile can generate more phrases (within free tier).
  bool canGenerate(String profileId) {
    if (!isReady) return false;
    return generationsUsed(profileId) < freeGenerationsPerProfile;
  }

  /// Remaining free generations for this profile.
  int remainingGenerations(String profileId) {
    return (freeGenerationsPerProfile - generationsUsed(profileId)).clamp(0, freeGenerationsPerProfile);
  }

  Future<void> _incrementUsage(String profileId) async {
    final used = generationsUsed(profileId) + 1;
    await _prefs.setInt('${_prefsKeyPrefix}used_$profileId', used);
  }

  // ── File paths ──────────────────────────────────────────────────────────

  /// Base directory for a specific player's generated audio.
  Directory _playerDir(String profileId) {
    return Directory('${_outputDir.path}/$profileId');
  }

  /// Path to a generated phrase audio file.
  File phraseFile(String profileId, String category, int index) {
    return File('${_playerDir(profileId).path}/phrases/${category}_$index.mp3');
  }

  /// Path to the generated name audio file.
  File nameFile(String profileId) {
    return File('${_playerDir(profileId).path}/phrases/name.mp3');
  }

  /// Check if personalized phrases exist for a profile.
  bool hasPhrasesForProfile(String profileId) {
    final dir = Directory('${_playerDir(profileId).path}/phrases');
    if (!dir.existsSync()) return false;
    // Check if at least the welcome_0 and name files exist
    return phraseFile(profileId, 'welcome', 0).existsSync() &&
        nameFile(profileId).existsSync();
  }

  // ── Generation ──────────────────────────────────────────────────────────

  /// Generate all personalized phrases for a player name.
  ///
  /// Returns a [GenerationResult] with success/failure counts.
  /// Skips files that already exist (safe to re-call).
  ///
  /// The [onProgress] callback fires after each file with (completed, total).
  Future<GenerationResult> generatePhrasesForName({
    required String profileId,
    required String name,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (!isReady) {
      return const GenerationResult(generated: 0, skipped: 0, failed: 0, error: 'Service not configured');
    }

    if (!canGenerate(profileId)) {
      return const GenerationResult(generated: 0, skipped: 0, failed: 0, error: 'Free generation limit reached');
    }

    final phrasesDir = Directory('${_playerDir(profileId).path}/phrases');
    await phrasesDir.create(recursive: true);

    // Build the list of phrases to generate
    final items = <_GenerationItem>[];

    for (final entry in PhraseTemplates.allCategories.entries) {
      final category = entry.key;
      final templates = entry.value;
      for (int i = 0; i < templates.length; i++) {
        final text = templates[i].replaceAll('{name}', name);
        final file = phraseFile(profileId, category, i);
        items.add(_GenerationItem(text: text, file: file, label: '${category}_$i'));
      }
    }

    // Also generate the standalone name audio
    items.add(_GenerationItem(
      text: name,
      file: nameFile(profileId),
      label: 'name',
    ));

    final total = items.length;
    int generated = 0;
    int skipped = 0;
    int failed = 0;
    int completed = 0;

    for (final item in items) {
      if (item.file.existsSync()) {
        skipped++;
        completed++;
        onProgress?.call(completed, total);
        continue;
      }

      final ok = await _generateSingle(item.text, item.file);
      if (ok) {
        generated++;
      } else {
        failed++;
      }
      completed++;
      onProgress?.call(completed, total);
    }

    // Track usage only if we actually generated something
    if (generated > 0) {
      await _incrementUsage(profileId);
    }

    debugPrint('DeepgramTTS: $generated generated, $skipped skipped, $failed failed for "$name"');
    return GenerationResult(generated: generated, skipped: skipped, failed: failed);
  }

  /// Generate a single audio file via Deepgram API.
  ///
  /// Retries up to [_maxRetries] times on transient errors (429, 5xx).
  static const int _maxRetries = 3;
  static const List<int> _retryBackoff = [2, 5, 10];

  Future<bool> _generateSingle(String text, File outputFile, [int attempt = 0]) async {
    if (_apiKey == null || _apiKey!.isEmpty) return false;

    final client = HttpClient();
    try {
      final uri = Uri.parse('$_apiUrl?model=$_voice&encoding=mp3');
      final request = await client.postUrl(uri);

      request.headers.set('Authorization', 'Token $_apiKey');
      request.headers.set('Content-Type', 'text/plain');
      request.add(utf8.encode(text));

      final response = await request.close().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.length < 100) {
          debugPrint('DeepgramTTS: suspiciously small audio for "$text" (${bytes.length} bytes)');
          return false;
        }
        await outputFile.writeAsBytes(bytes);
        return true;
      }

      // Drain response body to free resources
      await consolidateHttpClientResponseBytes(response);

      if (response.statusCode == 401) {
        debugPrint('DeepgramTTS: invalid API key (401)');
        return false;
      }

      if (response.statusCode == 402) {
        debugPrint('DeepgramTTS: insufficient credits (402)');
        return false;
      }

      if (response.statusCode == 429 && attempt < _maxRetries) {
        final wait = _retryBackoff[attempt.clamp(0, _retryBackoff.length - 1)];
        debugPrint('DeepgramTTS: rate limited, waiting ${wait}s (attempt ${attempt + 1})...');
        await Future.delayed(Duration(seconds: wait));
        return _generateSingle(text, outputFile, attempt + 1);
      }

      if (response.statusCode >= 500 && attempt < _maxRetries) {
        final wait = _retryBackoff[attempt.clamp(0, _retryBackoff.length - 1)];
        debugPrint('DeepgramTTS: server error ${response.statusCode}, retrying in ${wait}s...');
        await Future.delayed(Duration(seconds: wait));
        return _generateSingle(text, outputFile, attempt + 1);
      }

      debugPrint('DeepgramTTS: API error ${response.statusCode} for "$text"');
      return false;
    } on TimeoutException {
      if (attempt < _maxRetries) {
        debugPrint('DeepgramTTS: timeout for "$text", retrying...');
        return _generateSingle(text, outputFile, attempt + 1);
      }
      debugPrint('DeepgramTTS: timeout after ${_maxRetries + 1} attempts for "$text"');
      return false;
    } catch (e) {
      debugPrint('DeepgramTTS: error generating "$text": $e');
      return false;
    } finally {
      client.close();
    }
  }
}

/// Result of a phrase generation batch.
class GenerationResult {
  final int generated;
  final int skipped;
  final int failed;
  final String? error;

  const GenerationResult({
    required this.generated,
    required this.skipped,
    required this.failed,
    this.error,
  });

  bool get hasError => error != null;
  int get total => generated + skipped + failed;
}

class _GenerationItem {
  final String text;
  final File file;
  final String label;

  const _GenerationItem({
    required this.text,
    required this.file,
    required this.label,
  });
}

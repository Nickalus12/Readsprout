import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

/// Pre-computed amplitude envelope for an audio file.
///
/// Each envelope is a list of RMS amplitude values (0.0-1.0) sampled
/// at [frameDuration] intervals. Use [getAmplitude] with a playback
/// position to get the interpolated mouth-open value for lip sync.
class AmplitudeEnvelope {
  /// Duration of each amplitude frame.
  final Duration frameDuration;

  /// Normalized amplitude values (0.0-1.0), one per frame.
  final List<double> frames;

  /// Total duration of the envelope.
  late final Duration totalDuration;

  AmplitudeEnvelope({
    required this.frameDuration,
    required this.frames,
  }) {
    totalDuration = frameDuration * frames.length;
  }

  /// Parse from JSON decoded map.
  factory AmplitudeEnvelope.fromJson(Map<String, dynamic> json) {
    final frameMs = (json['frameMs'] as num).toInt();
    final rawFrames = json['frames'] as List;
    return AmplitudeEnvelope(
      frameDuration: Duration(milliseconds: frameMs),
      frames: rawFrames.map((v) => (v as num).toDouble()).toList(),
    );
  }

  /// Get the interpolated amplitude at a given playback position.
  ///
  /// Returns 0.0 if the position is out of range or the envelope is empty.
  double getAmplitude(Duration position) {
    if (frames.isEmpty) return 0.0;

    final ms = position.inMilliseconds;
    final frameMs = frameDuration.inMilliseconds;
    if (frameMs <= 0 || ms < 0) return 0.0;

    final exactFrame = ms / frameMs;
    final frameIndex = exactFrame.floor();

    if (frameIndex >= frames.length) return 0.0;
    if (frameIndex < 0) return 0.0;

    // Interpolate between current and next frame
    final nextIndex = frameIndex + 1;
    if (nextIndex >= frames.length) return frames[frameIndex];

    final t = exactFrame - frameIndex;
    return frames[frameIndex] * (1.0 - t) + frames[nextIndex] * t;
  }
}

/// Loads and caches [AmplitudeEnvelope] files from assets.
///
/// Envelopes are loaded lazily on first request and cached in memory.
/// Call [preloadForLevel] during level load to warm the cache.
class AmplitudeEnvelopeCache {
  final Map<String, AmplitudeEnvelope?> _cache = {};

  /// Load an envelope for the given audio asset path.
  ///
  /// [assetPath] should be the same path used for audio playback,
  /// e.g. `audio/words/the.mp3`. The `.mp3` extension is replaced
  /// with `.amp.json`.
  ///
  /// Returns null if the envelope file doesn't exist or can't be parsed.
  Future<AmplitudeEnvelope?> load(String assetPath) async {
    // Normalize: ensure we work with the .amp.json path
    final jsonPath = assetPath.replaceFirst(RegExp(r'\.mp3$'), '.amp.json');

    if (_cache.containsKey(jsonPath)) {
      return _cache[jsonPath];
    }

    try {
      final jsonStr = await rootBundle.loadString('assets/$jsonPath');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final envelope = AmplitudeEnvelope.fromJson(data);
      _cache[jsonPath] = envelope;
      return envelope;
    } catch (e) {
      // File doesn't exist or can't be parsed — cache null to avoid re-trying
      debugPrint('AmplitudeEnvelope: no envelope for $jsonPath');
      _cache[jsonPath] = null;
      return null;
    }
  }

  /// Pre-load envelopes for a list of words (e.g., a level's word list).
  ///
  /// Runs in parallel without blocking the UI.
  Future<void> preloadWords(List<String> words) async {
    await Future.wait(
      words.map((w) => load('audio/words/${w.toLowerCase()}.mp3')),
    );
  }

  /// Pre-load envelopes for letter names.
  Future<void> preloadLetters(List<String> letters) async {
    await Future.wait(
      letters.map((l) => load('audio/letter_names/${l.toLowerCase()}.mp3')),
    );
  }

  /// Remove all cached envelopes.
  void clear() {
    _cache.clear();
  }

  /// Number of envelopes currently cached.
  int get size => _cache.length;
}

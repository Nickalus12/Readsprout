import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../data/phrase_templates.dart';

/// Manages playback of pre-generated TTS audio clips.
///
/// Audio files are expected at:
///   assets/audio/words/{word}.mp3     — full word pronunciation
///   assets/audio/letters/{letter}.mp3 — phonetic letter sound
///   assets/audio/phrases/{cat}_{i}.mp3 — personalized encouragement
///   assets/audio/effects/*.mp3        — UI sound effects
///
/// Each letter file contains the PHONETIC sound, not the letter name:
///   a.mp3 → "ah" (short a sound)
///   b.mp3 → "buh"
///   etc.
class AudioService {
  final AudioPlayer _wordPlayer = AudioPlayer();
  final AudioPlayer _letterPlayer = AudioPlayer();
  final AudioPlayer _effectPlayer = AudioPlayer();
  final AudioPlayer _phrasePlayer = AudioPlayer();

  final _rng = Random();

  bool _initialized = false;

  Future<void> init() async {
    // setReleaseMode hangs on Windows — configure non-blocking instead
    _wordPlayer.setReleaseMode(ReleaseMode.stop);
    _letterPlayer.setReleaseMode(ReleaseMode.stop);
    _effectPlayer.setReleaseMode(ReleaseMode.stop);
    _phrasePlayer.setReleaseMode(ReleaseMode.stop);
    _initialized = true;
  }

  /// Play the full word pronunciation.
  /// Returns `true` if audio played successfully, `false` on failure.
  Future<bool> playWord(String word) async {
    if (!_initialized) return false;
    try {
      await _wordPlayer.stop();
      await _wordPlayer.play(
        AssetSource('audio/words/${word.toLowerCase()}.mp3'),
      );
      return true;
    } catch (e) {
      debugPrint('Audio error (word: $word): $e');
      return false;
    }
  }

  /// Play the phonetic sound for a single letter.
  /// Returns `true` if audio played successfully, `false` on failure.
  Future<bool> playLetter(String letter) async {
    if (!_initialized) return false;
    try {
      await _letterPlayer.stop();
      await _letterPlayer.play(
        AssetSource('audio/letters/${letter.toLowerCase()}.mp3'),
      );
      return true;
    } catch (e) {
      debugPrint('Audio error (letter: $letter): $e');
      return false;
    }
  }

  /// Play a random personalized phrase from a category.
  ///
  /// Categories: 'word_complete', 'level_complete', 'welcome'.
  /// Returns the phrase text for display, or null if no name set.
  Future<String?> playPhrase(String category, String playerName) async {
    if (!_initialized || playerName.isEmpty) return null;

    final List<String> templates;
    switch (category) {
      case 'word_complete':
        templates = PhraseTemplates.wordComplete;
      case 'level_complete':
        templates = PhraseTemplates.levelComplete;
      case 'welcome':
        templates = PhraseTemplates.welcome;
      default:
        return null;
    }

    final index = _rng.nextInt(templates.length);
    final text = templates[index].replaceAll('{name}', playerName);
    final audioPath = 'audio/phrases/${category}_$index.mp3';

    try {
      await _phrasePlayer.stop();
      await _phrasePlayer.play(AssetSource(audioPath));
    } catch (e) {
      debugPrint('Audio error (phrase: $audioPath): $e');
    }

    return text;
  }

  /// Play a welcome phrase for the player.
  Future<String?> playWelcome(String playerName) async {
    return playPhrase('welcome', playerName);
  }

  /// Play a word-complete encouragement phrase.
  Future<String?> playWordComplete(String playerName) async {
    return playPhrase('word_complete', playerName);
  }

  /// Play a level-complete celebration phrase.
  Future<String?> playLevelComplete(String playerName) async {
    return playPhrase('level_complete', playerName);
  }

  /// Play a success chime.
  Future<void> playSuccess() async {
    if (!_initialized) return;
    try {
      await _effectPlayer.stop();
      await _effectPlayer.play(
        AssetSource('audio/effects/success.mp3'),
      );
    } catch (e) {
      debugPrint('Audio error (success): $e');
    }
  }

  /// Play error/wrong feedback sound.
  Future<void> playError() async {
    if (!_initialized) return;
    try {
      await _effectPlayer.stop();
      await _effectPlayer.play(
        AssetSource('audio/effects/error.mp3'),
      );
    } catch (e) {
      debugPrint('Audio error (error): $e');
    }
  }

  /// Play level complete fanfare.
  Future<void> playLevelCompleteEffect() async {
    if (!_initialized) return;
    try {
      await _effectPlayer.stop();
      await _effectPlayer.play(
        AssetSource('audio/effects/level_complete.mp3'),
      );
    } catch (e) {
      debugPrint('Audio error (level_complete): $e');
    }
  }

  void dispose() {
    _wordPlayer.dispose();
    _letterPlayer.dispose();
    _effectPlayer.dispose();
    _phrasePlayer.dispose();
  }
}

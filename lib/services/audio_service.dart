import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../data/phrase_templates.dart';

/// Manages playback of pre-generated TTS audio clips.
///
/// Audio files are expected at:
///   assets/audio/words/{word}.mp3          — full word pronunciation
///   assets/audio/letter_names/{letter}.mp3 — spoken letter name (e.g. "ay", "bee")
///   assets/audio/phonics/{letter}.mp3      — phonetic letter sound (e.g. "ah", "buh")
///   assets/audio/phrases/{cat}_{i}.mp3     — personalized encouragement
///   assets/audio/effects/*.mp3             — UI sound effects
///
/// Letter NAME files (default for playLetter):
///   letter_names/a.mp3 → "ay"
///   letter_names/b.mp3 → "bee"
///
/// Phonics files (old phonetic sounds):
///   phonics/a.mp3 → "ah" (short a sound)
///   phonics/b.mp3 → "buh"
class AudioService {
  final AudioPlayer _wordPlayer = AudioPlayer();
  final AudioPlayer _letterPlayer = AudioPlayer();
  final AudioPlayer _letterNamePlayer = AudioPlayer();
  final AudioPlayer _effectPlayer = AudioPlayer();
  final AudioPlayer _phrasePlayer = AudioPlayer();

  final _rng = Random();

  bool _initialized = false;

  Future<void> init() async {
    // Fire-and-forget — don't await because setReleaseMode can hang on Windows
    try {
      _wordPlayer.setReleaseMode(ReleaseMode.stop);
      _letterPlayer.setReleaseMode(ReleaseMode.stop);
      _letterNamePlayer.setReleaseMode(ReleaseMode.stop);
      _effectPlayer.setReleaseMode(ReleaseMode.stop);
      _phrasePlayer.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('AudioService setReleaseMode error: $e');
    }
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

  /// Play the spoken letter NAME (e.g. "ay" for A, "bee" for B).
  /// This is the default for all letter playback in the app.
  /// Returns `true` if audio played successfully, `false` on failure.
  Future<bool> playLetter(String letter) async {
    if (!_initialized) return false;
    try {
      await _letterPlayer.stop();
      await _letterPlayer.play(
        AssetSource('audio/letter_names/${letter.toLowerCase()}.mp3'),
      );
      return true;
    } catch (e) {
      debugPrint('Audio error (letter: $letter): $e');
      return false;
    }
  }

  /// Play the phonetic sound for a single letter (e.g. "ah" for A, "buh" for B).
  /// Returns `true` if audio played successfully, `false` on failure.
  Future<bool> playLetterPhonics(String letter) async {
    if (!_initialized) return false;
    try {
      await _letterNamePlayer.stop();
      await _letterNamePlayer.play(
        AssetSource('audio/phonics/${letter.toLowerCase()}.mp3'),
      );
      return true;
    } catch (e) {
      debugPrint('Audio error (letter phonics: $letter): $e');
      return false;
    }
  }

  /// Alias for [playLetter] — plays the letter name.
  Future<bool> playLetterName(String letter) => playLetter(letter);

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
  /// Mixes in generic greetings that don't require a name.
  Future<String?> playWelcome(String playerName) async {
    // 40% chance of generic welcome (works for any name / no name)
    if (_rng.nextDouble() < 0.4 || playerName.isEmpty) {
      const genericFiles = [
        'welcome_generic_1',  // "Welcome!"
        'welcome_generic_2',  // "Hi there!"
        'welcome_generic_3',  // "Ready to learn?"
        'welcome_generic_4',  // "Let's get started!"
        'welcome_generic_5',  // "Time to learn!"
        'welcome_generic_6',  // "Here we go!"
        'welcome_generic_7',  // "Let's have fun!"
        'welcome_generic_8',  // "You're going to do great!"
        'welcome_generic_9',  // "Learning time!"
        'welcome_generic_10', // "Let's do this!"
        'welcome_generic_11', // "Good to see you!"
        'welcome_generic_12', // "Let's read some words!"
        'welcome_generic_13', // "Are you ready?"
      ];
      final file = genericFiles[_rng.nextInt(genericFiles.length)];
      try {
        await _phrasePlayer.stop();
        await _phrasePlayer.play(AssetSource('audio/words/$file.mp3'));
      } catch (e) {
        debugPrint('Audio error (generic welcome: $file): $e');
      }
      return file.replaceAll('_', ' ');
    }
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
    _letterNamePlayer.dispose();
    _effectPlayer.dispose();
    _phrasePlayer.dispose();
  }
}

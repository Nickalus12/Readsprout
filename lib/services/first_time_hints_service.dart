import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which screens/features the user has seen for the first time.
/// Used to show pulsing visual hints and one-time guidance.
class FirstTimeHintsService {
  static const _prefix = 'first_time_hint_';

  late SharedPreferences _prefs;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
  }

  /// Returns true if this is the first time the user sees this hint.
  /// Automatically marks it as seen.
  bool checkAndMark(String hintKey) {
    final key = '$_prefix$hintKey';
    final seen = _prefs.getBool(key) ?? false;
    if (!seen) {
      _prefs.setBool(key, true);
      return true;
    }
    return false;
  }

  /// Check without marking (for repeated checks in build methods).
  bool hasBeenSeen(String hintKey) {
    return _prefs.getBool('$_prefix$hintKey') ?? false;
  }

  /// Mark a hint as seen without checking.
  void markSeen(String hintKey) {
    _prefs.setBool('$_prefix$hintKey', true);
  }

  /// Reset all hints (useful for parent settings).
  Future<void> resetAll() async {
    final keys =
        _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  // Common hint keys
  static const adventureMode = 'adventure_mode';
  static const gameScreen = 'game_screen';
  static const tierSelection = 'tier_selection';
  static const miniGames = 'mini_games';
  static const alphabet = 'alphabet';
}

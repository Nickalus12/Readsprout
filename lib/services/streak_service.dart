import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks daily practice streaks and milestone achievements.
///
/// Data is stored as a JSON string in SharedPreferences, matching
/// the existing persistence pattern used by [ProgressService].
class StreakService {
  static const _key = 'streak_data';

  late SharedPreferences _prefs;

  int _currentStreak = 0;
  int _longestStreak = 0;
  String _lastPracticeDate = '';
  bool _streakFreezeAvailable = false;

  int get currentStreak => _currentStreak;
  int get longestStreak => _longestStreak;
  String get lastPracticeDate => _lastPracticeDate;
  bool get streakFreezeAvailable => _streakFreezeAvailable;
  bool get hasStreak => _currentStreak >= 1;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _currentStreak = data['currentStreak'] as int? ?? 0;
      _longestStreak = data['longestStreak'] as int? ?? 0;
      _lastPracticeDate = data['lastPracticeDate'] as String? ?? '';
      _streakFreezeAvailable = data['streakFreezeAvailable'] as bool? ?? false;
    }
  }

  Future<void> _save() async {
    final data = jsonEncode({
      'currentStreak': _currentStreak,
      'longestStreak': _longestStreak,
      'lastPracticeDate': _lastPracticeDate,
      'streakFreezeAvailable': _streakFreezeAvailable,
    });
    await _prefs.setString(_key, data);
  }

  /// Called on app open to handle streak reset if the user missed a day.
  Future<void> checkStreak() async {
    if (_lastPracticeDate.isEmpty) return;

    final today = _todayString();
    if (_lastPracticeDate == today) return;

    final lastDate = DateTime.tryParse(_lastPracticeDate);
    if (lastDate == null) return;

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final diff = todayDate.difference(lastDate).inDays;

    if (diff > 1) {
      // Missed at least one day
      if (_streakFreezeAvailable && diff == 2) {
        // Use streak freeze — one grace day
        _streakFreezeAvailable = false;
      } else {
        _currentStreak = 0;
      }
      await _save();
    }
  }

  /// Record that the player practiced today.
  ///
  /// Returns a milestone message if a streak milestone is reached,
  /// or `null` otherwise.
  Future<String?> recordPractice() async {
    final today = _todayString();

    // Already recorded today — nothing to do
    if (_lastPracticeDate == today) {

      return null;
    }

    final lastDate = DateTime.tryParse(_lastPracticeDate);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    if (lastDate != null) {
      final diff = todayDate.difference(lastDate).inDays;
      if (diff == 1) {
        // Consecutive day — extend streak
        _currentStreak++;
      } else if (diff == 0) {
        // Same day (shouldn't reach here, but guard)
        return null;
      } else {
        // Gap > 1 day — start fresh
        _currentStreak = 1;
      }
    } else {
      // First ever practice
      _currentStreak = 1;
    }

    _lastPracticeDate = today;

    if (_currentStreak > _longestStreak) {
      _longestStreak = _currentStreak;
    }

    await _save();
    return _milestoneMessage(_currentStreak);
  }

  /// Returns a celebration message for milestone streaks, or `null`.
  String? _milestoneMessage(int streak) {
    return switch (streak) {
      3 => '3 Day Streak!',
      7 => '1 Week Streak!',
      14 => '2 Week Streak!',
      30 => '30 Day Streak! LEGENDARY!',
      _ => null,
    };
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

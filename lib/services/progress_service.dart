import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/progress.dart';
import '../data/dolch_words.dart';

class ProgressService {
  static const _baseKey = 'sight_words_progress';
  static const _starCoinsKey = 'star_coins';
  late SharedPreferences _prefs;
  late Map<int, LevelProgress> _progress;
  String _profileId = '';

  static const _freePlayKey = 'free_play_mode';

  String get _key => _profileId.isEmpty ? _baseKey : '${_baseKey}_$_profileId';
  String get _coinsKey => _profileId.isEmpty
      ? _starCoinsKey
      : '${_starCoinsKey}_$_profileId';
  String get _freePlayModeKey => _profileId.isEmpty
      ? _freePlayKey
      : '${_freePlayKey}_$_profileId';

  // ── Free Play Mode ─────────────────────────────────────────────────────

  /// Whether free play mode is enabled (skips coin costs and time limits).
  bool get freePlayMode => _prefs.getBool(_freePlayModeKey) ?? false;

  /// Enable or disable free play mode.
  set freePlayMode(bool value) => _prefs.setBool(_freePlayModeKey, value);

  // ── Star Coins ──────────────────────────────────────────────────────────

  /// Current star coin balance for the active profile.
  int get starCoins => _prefs.getInt(_coinsKey) ?? 0;

  /// Set star coin balance directly.
  set starCoins(int value) => _prefs.setInt(_coinsKey, value);

  /// Add coins (e.g. reward). Returns the new balance.
  int addStarCoins(int amount) {
    final newBalance = starCoins + amount;
    starCoins = newBalance;
    return newBalance;
  }

  /// Spend coins if affordable. Returns true if successful.
  bool spendStarCoins(int amount) {
    final current = starCoins;
    if (current < amount) return false;
    starCoins = current - amount;
    return true;
  }

  Map<int, LevelProgress> get progress => Map.unmodifiable(_progress);

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _loadProgress();
  }

  /// Reload progress for a different profile.
  /// Flushes any pending saves for the previous profile first.
  void switchProfile(String profileId) {
    _saveTimer?.cancel();
    if (_dirty) _flushSave();
    _profileId = profileId;
    _loadProgress();
  }

  void _loadProgress() {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _progress = decoded.map((key, value) => MapEntry(
            int.parse(key),
            LevelProgress.fromJson(value as Map<String, dynamic>),
          ));
      _migrateOldProgress();
    } else {
      _progress = {};
    }

    // Ensure level 1 is always unlocked
    _progress.putIfAbsent(
        1, () => const LevelProgress(level: 1, unlocked: true));
    if (!_progress[1]!.unlocked) {
      _progress[1] = _progress[1]!.copyWith(unlocked: true);
    }
  }

  /// Migrate old progress data that has wordStats but no tierProgress.
  /// Moves existing wordStats into tierProgress[1] (Explorer).
  void _migrateOldProgress() {
    for (final entry in _progress.entries) {
      final lp = entry.value;
      if (lp.tierProgress.isEmpty && lp.wordStats.isNotEmpty) {
        final tier1 = TierProgress(
          tier: 1,
          wordsCompleted: lp.wordsCompleted,
          perfectWords:
              lp.wordStats.values.where((s) => s.perfectAttempts > 0).length,
          wordStats: Map<String, WordStats>.from(lp.wordStats),
        );
        final newTierProgress = {1: tier1};
        final newHighest = tier1.isComplete ? 1 : 0;
        _progress[entry.key] = lp.copyWith(
          tierProgress: newTierProgress,
          highestCompletedTier: newHighest,
        );
      }
    }
  }

  Timer? _saveTimer;
  bool _dirty = false;

  /// Debounced save — coalesces rapid writes (e.g., multiple words in a session).
  /// Flushes after 500ms of inactivity or immediately on profile switch.
  Future<void> _save() async {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _flushSave);
  }

  Future<void> _flushSave() async {
    if (!_dirty) return;
    try {
      final encoded = jsonEncode(
        _progress.map((key, value) => MapEntry(key.toString(), value.toJson())),
      );
      await _prefs.setString(_key, encoded);
      _dirty = false;
    } catch (e) {
      // Leave _dirty=true so the next flush retries
      debugPrint('ProgressService save failed: $e');
    }
  }

  LevelProgress getLevel(int level) {
    return _progress[level] ??
        LevelProgress(level: level, unlocked: level == 1);
  }

  bool isLevelUnlocked(int level) {
    if (level == 1) return true;
    return _progress[level]?.unlocked ?? false;
  }

  /// Whether a specific tier is unlocked for a level.
  /// Tier 1 is unlocked if the level is unlocked.
  /// Tier 2 is unlocked if tier 1 of that level is complete.
  /// Tier 3 is unlocked if tier 2 of that level is complete.
  bool isTierUnlocked(int level, int tier) {
    if (!isLevelUnlocked(level)) return false;
    if (tier <= 1) return true;
    final lp = getLevel(level);
    final previousTier = lp.tierProgress[tier - 1];
    return previousTier?.isComplete ?? false;
  }

  int get highestUnlockedLevel {
    int highest = 1;
    for (final entry in _progress.entries) {
      if (entry.value.unlocked && entry.key > highest) {
        highest = entry.key;
      }
    }
    return highest;
  }

  /// Whether every level in [zoneStartLevel..zoneEndLevel] has all 3 tiers
  /// complete (highestCompletedTier >= 3).
  bool isZoneFullyMastered(int zoneStartLevel, int zoneEndLevel) {
    for (int l = zoneStartLevel; l <= zoneEndLevel; l++) {
      if (getLevel(l).highestCompletedTier < 3) return false;
    }
    return true;
  }

  /// Returns the tier the player should be working on for a given level,
  /// based on zone-wide progress.
  ///
  /// - If NOT all levels in the zone have tier 1 complete -> 1
  /// - If all have tier 1 but not all have tier 2 -> 2
  /// - If all have tier 2 but not all have tier 3 -> 3
  /// - If all have tier 3 (fully mastered) -> 3
  int suggestedTierForLevel(int level) {
    final zone = DolchWords.zoneForLevel(level);
    for (int t = 1; t <= 3; t++) {
      for (int l = zone.startLevel; l <= zone.endLevel; l++) {
        if (getLevel(l).highestCompletedTier < t) return t;
      }
    }
    return 3; // All mastered
  }

  /// Record that a word was completed in a specific tier of a level.
  /// For champion tier (3), a word only counts as complete with <= 1 mistake.
  /// Returns true if this completed the tier (all 10 words done).
  Future<bool> recordTierWordComplete({
    required int level,
    required int tier,
    required String wordText,
    required int mistakes,
  }) async {
    final current = getLevel(level);

    // Champion quality gate: word doesn't count with > 1 mistake
    final isChampion = tier == 3;
    final wordCountsAsComplete = !isChampion || mistakes <= 1;

    // Get or create tier progress
    final currentTier =
        current.tierProgress[tier] ?? TierProgress(tier: tier);
    final stats = currentTier.wordStats[wordText] ?? const WordStats();

    final updatedStats = stats.copyWith(
      attempts: stats.attempts + 1,
      perfectAttempts:
          mistakes == 0 ? stats.perfectAttempts + 1 : stats.perfectAttempts,
      totalMistakes: stats.totalMistakes + mistakes,
      bestMistakes: mistakes < stats.bestMistakes ? mistakes : stats.bestMistakes,
    );

    final newWordStats = Map<String, WordStats>.from(currentTier.wordStats);
    newWordStats[wordText] = updatedStats;

    // Count completed words for this tier
    int completedCount;
    if (isChampion) {
      // For champion, count words that have at least one attempt with <= 1 mistake
      completedCount = newWordStats.values
          .where((s) => s.attempts > 0 && s.bestMistakes <= 1)
          .length
          .clamp(0, 10);
    } else {
      completedCount = newWordStats.values
          .where((s) => s.attempts > 0)
          .length
          .clamp(0, 10);
    }

    final perfectCount =
        newWordStats.values.where((s) => s.perfectAttempts > 0).length;

    final updatedTierProgress = currentTier.copyWith(
      wordsCompleted: wordCountsAsComplete ? completedCount : currentTier.wordsCompleted,
      perfectWords: perfectCount,
      wordStats: newWordStats,
    );

    final newTierMap = Map<int, TierProgress>.from(current.tierProgress);
    newTierMap[tier] = updatedTierProgress;

    // Determine highest completed tier
    int highestCompleted = current.highestCompletedTier;
    if (updatedTierProgress.isComplete && tier > highestCompleted) {
      highestCompleted = tier;
    }

    // Also update legacy wordsCompleted field (from tier 1 for compat)
    final tier1 = newTierMap[1];
    final legacyWordsCompleted = tier1?.wordsCompleted ?? current.wordsCompleted;

    // Also update legacy wordStats from tier 1
    final legacyWordStats = tier1?.wordStats ?? current.wordStats;

    _progress[level] = current.copyWith(
      wordsCompleted: legacyWordsCompleted,
      wordStats: legacyWordStats,
      unlocked: true,
      highestCompletedTier: highestCompleted,
      tierProgress: newTierMap,
    );

    // Only count as "just completed" if it wasn't complete before
    final wasAlreadyComplete = currentTier.isComplete;
    final tierComplete = updatedTierProgress.isComplete && !wasAlreadyComplete;
    if (tierComplete) {
      if (tier == 1) {
        // Tier 1 complete → unlock Tier 1 of next level, but ONLY within
        // the same zone. Cross-zone unlocking requires full zone mastery.
        if (level < DolchWords.totalLevels) {
          final nextLevel = level + 1;
          final currentZone = DolchWords.zoneForLevel(level);
          final nextZone = DolchWords.zoneForLevel(nextLevel);

          if (currentZone.startLevel == nextZone.startLevel) {
            // Same zone — unlock as before
            _progress.putIfAbsent(
              nextLevel,
              () => LevelProgress(level: nextLevel, unlocked: true),
            );
            if (!_progress[nextLevel]!.unlocked) {
              _progress[nextLevel] =
                  _progress[nextLevel]!.copyWith(unlocked: true);
            }
          }
        }
      }
      // Tiers 2 and 3 of the same level are auto-unlocked via isTierUnlocked
      // (no persistent flag needed — the check is computed)

      // Check if this completion causes the zone to be fully mastered,
      // and if so, unlock the first level of the next zone.
      final zone = DolchWords.zoneForLevel(level);
      if (isZoneFullyMastered(zone.startLevel, zone.endLevel)) {
        if (zone.endLevel < DolchWords.totalLevels) {
          final nextZoneFirstLevel = zone.endLevel + 1;
          _progress.putIfAbsent(
            nextZoneFirstLevel,
            () => LevelProgress(
                level: nextZoneFirstLevel, unlocked: true),
          );
          if (!_progress[nextZoneFirstLevel]!.unlocked) {
            _progress[nextZoneFirstLevel] =
                _progress[nextZoneFirstLevel]!.copyWith(unlocked: true);
          }
        }
      }
    }

    // Award star coins: 1 per word completed, 5 bonus per tier completed
    if (wordCountsAsComplete) addStarCoins(1);
    if (tierComplete) addStarCoins(5);

    await _save();
    return tierComplete;
  }

  /// Legacy method: Record a word completion for tier 1 (backward compat).
  /// Returns true if this was the LAST word in the level (level complete!).
  Future<bool> recordWordComplete({
    required int level,
    required String wordText,
    required int mistakes,
  }) async {
    return recordTierWordComplete(
      level: level,
      tier: 1,
      wordText: wordText,
      mistakes: mistakes,
    );
  }

  /// Get total stars: sum of highestCompletedTier across all levels.
  /// Maximum is 66 (22 levels x 3 tiers).
  int get totalStars {
    int count = 0;
    for (final lp in _progress.values) {
      count += lp.highestCompletedTier;
    }
    return count;
  }

  /// Get total words completed across all levels (tier 1 / legacy).
  int get totalWordsCompleted {
    int count = 0;
    for (final lp in _progress.values) {
      count += lp.wordStats.values.where((s) => s.attempts > 0).length;
    }
    return count;
  }

  /// Reset all progress
  Future<void> resetAll() async {
    _progress.clear();
    _progress[1] = const LevelProgress(level: 1, unlocked: true);
    await _save();
  }
}

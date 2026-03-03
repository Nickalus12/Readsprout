import 'package:flutter/material.dart';

/// The three tiers a player can complete for each level.
enum WordTier {
  explorer(1),
  adventurer(2),
  champion(3);

  const WordTier(this.value);
  final int value;

  String get displayName {
    switch (this) {
      case WordTier.explorer:
        return 'Explorer';
      case WordTier.adventurer:
        return 'Adventurer';
      case WordTier.champion:
        return 'Champion';
    }
  }

  String get description {
    switch (this) {
      case WordTier.explorer:
        return 'Learn each word at your own pace';
      case WordTier.adventurer:
        return 'Spell each word from memory';
      case WordTier.champion:
        return 'Master each word with no mistakes';
    }
  }

  String get icon {
    switch (this) {
      case WordTier.explorer:
        return '🥉';
      case WordTier.adventurer:
        return '🥈';
      case WordTier.champion:
        return '🥇';
    }
  }

  Color get color {
    switch (this) {
      case WordTier.explorer:
        return const Color(0xFFCD7F32); // bronze
      case WordTier.adventurer:
        return const Color(0xFFC0C0C0); // silver
      case WordTier.champion:
        return const Color(0xFFFFD700); // gold
    }
  }

  static WordTier? fromValue(int value) {
    switch (value) {
      case 1:
        return WordTier.explorer;
      case 2:
        return WordTier.adventurer;
      case 3:
        return WordTier.champion;
      default:
        return null;
    }
  }
}

/// Tracks progress within a single tier of a level.
class TierProgress {
  final int tier; // 1, 2, or 3
  final int wordsCompleted; // out of 10
  final int perfectWords; // words completed with 0 mistakes
  final Map<String, WordStats> wordStats;

  const TierProgress({
    required this.tier,
    this.wordsCompleted = 0,
    this.perfectWords = 0,
    this.wordStats = const {},
  });

  bool get isComplete => wordsCompleted >= 10;

  double get completionPercent => (wordsCompleted / 10).clamp(0.0, 1.0);

  TierProgress copyWith({
    int? wordsCompleted,
    int? perfectWords,
    Map<String, WordStats>? wordStats,
  }) {
    return TierProgress(
      tier: tier,
      wordsCompleted: wordsCompleted ?? this.wordsCompleted,
      perfectWords: perfectWords ?? this.perfectWords,
      wordStats: wordStats ?? this.wordStats,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier,
        'wordsCompleted': wordsCompleted,
        'perfectWords': perfectWords,
        'wordStats': wordStats.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory TierProgress.fromJson(Map<String, dynamic> json) {
    final statsMap = (json['wordStats'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, WordStats.fromJson(v as Map<String, dynamic>)),
        ) ??
        {};
    return TierProgress(
      tier: json['tier'] as int? ?? 1,
      wordsCompleted: json['wordsCompleted'] as int? ?? 0,
      perfectWords: json['perfectWords'] as int? ?? 0,
      wordStats: statsMap,
    );
  }
}

class LevelProgress {
  final int level;
  final int wordsCompleted; // out of 10 (legacy, kept for backward compat)
  final int bestStreak;
  final bool unlocked;
  final Map<String, WordStats> wordStats; // word text -> stats (legacy tier-1)
  final int highestCompletedTier; // 0 = none, 1 = explorer, 2 = adventurer, 3 = champion
  final Map<int, TierProgress> tierProgress; // tier number -> progress

  const LevelProgress({
    required this.level,
    this.wordsCompleted = 0,
    this.bestStreak = 0,
    this.unlocked = false,
    this.wordStats = const {},
    this.highestCompletedTier = 0,
    this.tierProgress = const {},
  });

  bool get isComplete => wordsCompleted >= 10;

  double get completionPercent => (wordsCompleted / 10).clamp(0.0, 1.0);

  /// Stars earned for this level: 0-3 based on highest completed tier.
  int get starsEarned => highestCompletedTier;

  /// True if all three tiers are completed.
  bool get isFullyMastered => highestCompletedTier >= 3;

  /// Overall progress across all tiers (0.0 to 1.0).
  /// Each tier contributes 1/3 of the total.
  double get overallProgress {
    double total = 0.0;
    for (int t = 1; t <= 3; t++) {
      final tp = tierProgress[t];
      if (tp != null) {
        total += tp.completionPercent / 3.0;
      }
    }
    return total.clamp(0.0, 1.0);
  }

  LevelProgress copyWith({
    int? wordsCompleted,
    int? bestStreak,
    bool? unlocked,
    Map<String, WordStats>? wordStats,
    int? highestCompletedTier,
    Map<int, TierProgress>? tierProgress,
  }) {
    return LevelProgress(
      level: level,
      wordsCompleted: wordsCompleted ?? this.wordsCompleted,
      bestStreak: bestStreak ?? this.bestStreak,
      unlocked: unlocked ?? this.unlocked,
      wordStats: wordStats ?? this.wordStats,
      highestCompletedTier:
          highestCompletedTier ?? this.highestCompletedTier,
      tierProgress: tierProgress ?? this.tierProgress,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level,
        'wordsCompleted': wordsCompleted,
        'bestStreak': bestStreak,
        'unlocked': unlocked,
        'wordStats': wordStats.map((k, v) => MapEntry(k, v.toJson())),
        'highestCompletedTier': highestCompletedTier,
        'tierProgress': tierProgress.map(
          (k, v) => MapEntry(k.toString(), v.toJson()),
        ),
      };

  factory LevelProgress.fromJson(Map<String, dynamic> json) {
    final statsMap = (json['wordStats'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, WordStats.fromJson(v as Map<String, dynamic>)),
        ) ??
        {};

    final tierMap = <int, TierProgress>{};
    final rawTier = json['tierProgress'] as Map<String, dynamic>?;
    if (rawTier != null) {
      for (final entry in rawTier.entries) {
        final tierNum = int.tryParse(entry.key);
        if (tierNum != null) {
          tierMap[tierNum] =
              TierProgress.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }

    return LevelProgress(
      level: json['level'] as int,
      wordsCompleted: json['wordsCompleted'] as int? ?? 0,
      bestStreak: json['bestStreak'] as int? ?? 0,
      unlocked: json['unlocked'] as bool? ?? false,
      wordStats: statsMap,
      highestCompletedTier: json['highestCompletedTier'] as int? ?? 0,
      tierProgress: tierMap,
    );
  }
}

class WordStats {
  final int attempts;
  final int perfectAttempts; // No mistakes
  final int totalMistakes;

  const WordStats({
    this.attempts = 0,
    this.perfectAttempts = 0,
    this.totalMistakes = 0,
  });

  bool get mastered => perfectAttempts >= 3; // Mastered after 3 perfect runs

  WordStats copyWith({
    int? attempts,
    int? perfectAttempts,
    int? totalMistakes,
  }) {
    return WordStats(
      attempts: attempts ?? this.attempts,
      perfectAttempts: perfectAttempts ?? this.perfectAttempts,
      totalMistakes: totalMistakes ?? this.totalMistakes,
    );
  }

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'perfectAttempts': perfectAttempts,
        'totalMistakes': totalMistakes,
      };

  factory WordStats.fromJson(Map<String, dynamic> json) => WordStats(
        attempts: json['attempts'] as int? ?? 0,
        perfectAttempts: json['perfectAttempts'] as int? ?? 0,
        totalMistakes: json['totalMistakes'] as int? ?? 0,
      );
}

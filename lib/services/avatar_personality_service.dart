import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../avatar/avatar_widget.dart' show AvatarExpression;

// ══════════════════════════════════════════════════════════════════════
//  AVATAR PERSONALITY — Hive-persisted, evolves over weeks of play
// ══════════════════════════════════════════════════════════════════════

@HiveType(typeId: 3)
class AvatarPersonality extends HiveObject {
  // ── Learned traits (0.0-1.0, evolve over time) ──

  @HiveField(0)
  double energy; // idle fidget intensity

  @HiveField(1)
  double confidence; // grows with streaks, dips with errors (floor 0.3)

  @HiveField(2)
  double playfulness; // grows with mini-game play

  @HiveField(3)
  double patience; // grows with slow careful play

  // ── Observed patterns ──

  @HiveField(4)
  int preferredPlayHour; // most common hour (0-23)

  @HiveField(5)
  double avgSessionMinutes; // running average (EMA, alpha=0.1)

  @HiveField(6)
  int favoriteGameIndex; // most played game (-1 = none)

  @HiveField(7)
  double accuracyTrend; // -1.0 declining, 0 stable, 1.0 improving

  @HiveField(8)
  int totalSessions; // lifetime session count

  @HiveField(9)
  int lastPlayTimestamp; // epoch ms of last session

  @HiveField(10)
  List<int> playHourHistogram; // 24-element array, count per hour

  // ── Recent game history for favorite tracking ──

  @HiveField(11)
  List<int> recentGames; // last 20 game indices

  // ── Accuracy tracking ──

  @HiveField(12)
  double accuracyEma; // exponential moving average of per-word accuracy

  @HiveField(13)
  int totalWordsAttempted; // for seeding the EMA

  AvatarPersonality({
    required this.energy,
    required this.confidence,
    required this.playfulness,
    required this.patience,
    required this.preferredPlayHour,
    required this.avgSessionMinutes,
    required this.favoriteGameIndex,
    required this.accuracyTrend,
    required this.totalSessions,
    required this.lastPlayTimestamp,
    required this.playHourHistogram,
    required this.recentGames,
    required this.accuracyEma,
    required this.totalWordsAttempted,
  });

  /// Brand new personality with neutral traits.
  AvatarPersonality.fresh()
      : energy = 0.5,
        confidence = 0.5,
        playfulness = 0.3,
        patience = 0.5,
        preferredPlayHour = 12,
        avgSessionMinutes = 5.0,
        favoriteGameIndex = -1,
        accuracyTrend = 0.0,
        totalSessions = 0,
        lastPlayTimestamp = 0,
        playHourHistogram = List.filled(24, 0),
        recentGames = [],
        accuracyEma = 0.5,
        totalWordsAttempted = 0;

  /// Clamp all traits to valid range. Confidence never below 0.3.
  void clampTraits() {
    energy = energy.clamp(0.0, 1.0);
    confidence = confidence.clamp(0.3, 1.0);
    playfulness = playfulness.clamp(0.0, 1.0);
    patience = patience.clamp(0.0, 1.0);
    accuracyTrend = accuracyTrend.clamp(-1.0, 1.0);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  MANUAL HIVE ADAPTER (avoids build_runner dependency)
// ══════════════════════════════════════════════════════════════════════

class AvatarPersonalityAdapter extends TypeAdapter<AvatarPersonality> {
  @override
  final int typeId = 3;

  @override
  AvatarPersonality read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AvatarPersonality(
      energy: (fields[0] as num?)?.toDouble() ?? 0.5,
      confidence: (fields[1] as num?)?.toDouble() ?? 0.5,
      playfulness: (fields[2] as num?)?.toDouble() ?? 0.3,
      patience: (fields[3] as num?)?.toDouble() ?? 0.5,
      preferredPlayHour: (fields[4] as int?) ?? 12,
      avgSessionMinutes: (fields[5] as num?)?.toDouble() ?? 5.0,
      favoriteGameIndex: (fields[6] as int?) ?? -1,
      accuracyTrend: (fields[7] as num?)?.toDouble() ?? 0.0,
      totalSessions: (fields[8] as int?) ?? 0,
      lastPlayTimestamp: (fields[9] as int?) ?? 0,
      playHourHistogram: (fields[10] as List?)?.cast<int>() ?? List.filled(24, 0),
      recentGames: (fields[11] as List?)?.cast<int>() ?? [],
      accuracyEma: (fields[12] as num?)?.toDouble() ?? 0.5,
      totalWordsAttempted: (fields[13] as int?) ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AvatarPersonality obj) {
    writer.writeByte(14); // number of fields
    // 0: energy
    writer.writeByte(0);
    writer.write(obj.energy);
    // 1: confidence
    writer.writeByte(1);
    writer.write(obj.confidence);
    // 2: playfulness
    writer.writeByte(2);
    writer.write(obj.playfulness);
    // 3: patience
    writer.writeByte(3);
    writer.write(obj.patience);
    // 4: preferredPlayHour
    writer.writeByte(4);
    writer.write(obj.preferredPlayHour);
    // 5: avgSessionMinutes
    writer.writeByte(5);
    writer.write(obj.avgSessionMinutes);
    // 6: favoriteGameIndex
    writer.writeByte(6);
    writer.write(obj.favoriteGameIndex);
    // 7: accuracyTrend
    writer.writeByte(7);
    writer.write(obj.accuracyTrend);
    // 8: totalSessions
    writer.writeByte(8);
    writer.write(obj.totalSessions);
    // 9: lastPlayTimestamp
    writer.writeByte(9);
    writer.write(obj.lastPlayTimestamp);
    // 10: playHourHistogram
    writer.writeByte(10);
    writer.write(obj.playHourHistogram);
    // 11: recentGames
    writer.writeByte(11);
    writer.write(obj.recentGames);
    // 12: accuracyEma
    writer.writeByte(12);
    writer.write(obj.accuracyEma);
    // 13: totalWordsAttempted
    writer.writeByte(13);
    writer.write(obj.totalWordsAttempted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarPersonalityAdapter && typeId == other.typeId;
}

// ══════════════════════════════════════════════════════════════════════
//  AVATAR MOOD — computed output that drives avatar behavior
// ══════════════════════════════════════════════════════════════════════

class AvatarMood {
  /// Energy level to feed into ProceduralIdleSystem.energyLevel.
  final double energyLevel;

  /// Default facial expression for idle state.
  final AvatarExpression defaultExpression;

  /// 0.3-1.0, scales animation clip speed and amplitude.
  final double reactionIntensity;

  /// Whether to play a wave animation on screen open.
  final bool shouldWave;

  /// Which animation clip to play as greeting.
  final String greetingClip;

  const AvatarMood({
    required this.energyLevel,
    required this.defaultExpression,
    required this.reactionIntensity,
    required this.shouldWave,
    required this.greetingClip,
  });

  static const resting = AvatarMood(
    energyLevel: 0.4,
    defaultExpression: AvatarExpression.neutral,
    reactionIntensity: 0.5,
    shouldWave: false,
    greetingClip: 'nod',
  );
}

// ══════════════════════════════════════════════════════════════════════
//  PERSONALITY SERVICE — evolves personality over time
// ══════════════════════════════════════════════════════════════════════

class AvatarPersonalityService {
  late Box<AvatarPersonality> _box;
  AvatarPersonality? _active;
  String? _activeProfileId;

  /// Accuracy tracking within the current session.
  int _sessionCorrect = 0;
  int _sessionTotal = 0;
  double _previousAccuracyEma = 0.5;

  Future<void> init() async {
    _box = await Hive.openBox<AvatarPersonality>('personality');
    debugPrint('AvatarPersonalityService: initialized (${_box.length} profiles)');
  }

  /// Get or create personality for a profile.
  AvatarPersonality forProfile(String profileId) {
    return _box.get(profileId) ?? AvatarPersonality.fresh();
  }

  // ── Event handlers ─────────────────────────────────────────────────

  /// Call when a profile's play session begins.
  void onSessionStart(String profileId) {
    _activeProfileId = profileId;
    _sessionCorrect = 0;
    _sessionTotal = 0;

    final p = forProfile(profileId);
    _previousAccuracyEma = p.accuracyEma;

    // Update play hour histogram
    final hour = DateTime.now().hour;
    if (p.playHourHistogram.length == 24) {
      p.playHourHistogram[hour]++;
    }

    // Update session count
    p.totalSessions++;

    // Recalculate preferred play hour from histogram
    p.preferredPlayHour = _modeHour(p.playHourHistogram);

    // Energy decay for days not played
    final daysSince = _daysSinceLastPlay(p);
    if (daysSince > 0) {
      p.energy = (p.energy - 0.01 * daysSince).clamp(0.0, 1.0);
    }

    // Reunion excitement is handled in computeMood, not here

    _active = p;
    _save(profileId, p);
  }

  /// Call when the play session ends.
  void onSessionEnd(String profileId, Duration sessionLength) {
    final p = forProfile(profileId);

    // Update avgSessionMinutes (EMA, alpha=0.1)
    final sessionMin = sessionLength.inSeconds / 60.0;
    if (p.totalSessions <= 1) {
      p.avgSessionMinutes = sessionMin;
    } else {
      p.avgSessionMinutes =
          p.avgSessionMinutes * 0.9 + sessionMin * 0.1;
    }

    // Save last play timestamp
    p.lastPlayTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Patience grows with longer sessions (slow careful play)
    if (sessionMin > 5) {
      p.patience = (p.patience + 0.005 * (sessionMin / 10).clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
    }

    // Update accuracy trend from EMA change
    if (p.totalWordsAttempted > 5) {
      final emaDelta = p.accuracyEma - _previousAccuracyEma;
      // EMA of trend itself (alpha=0.2)
      p.accuracyTrend = (p.accuracyTrend * 0.8 + emaDelta * 5.0 * 0.2)
          .clamp(-1.0, 1.0);
    }

    // Session-level accuracy for debug logging
    final sessionAcc = _sessionTotal > 0
        ? _sessionCorrect / _sessionTotal
        : 0.0;
    debugPrint('AvatarPersonality: session end '
        '($_sessionCorrect/$_sessionTotal = ${sessionAcc.toStringAsFixed(2)}) '
        'trend=${p.accuracyTrend.toStringAsFixed(3)}');

    p.clampTraits();
    _save(profileId, p);
    _active = null;
    _activeProfileId = null;
  }

  /// Record a correct word attempt.
  void onWordCorrect(String profileId) {
    final p = _activeOrLoad(profileId);
    _sessionCorrect++;
    _sessionTotal++;

    // Nudge confidence up
    p.confidence += 0.01;
    // Nudge energy up
    p.energy += 0.005;

    // Update accuracy EMA (alpha=0.1)
    p.totalWordsAttempted++;
    p.accuracyEma = p.accuracyEma * 0.9 + 1.0 * 0.1;

    p.clampTraits();
    _save(profileId, p);
  }

  /// Record an incorrect word attempt.
  void onWordIncorrect(String profileId) {
    final p = _activeOrLoad(profileId);
    _sessionTotal++;

    // Confidence dips slightly (floor at 0.3 — always encouraging)
    p.confidence -= 0.005;
    // Patience grows — avatar learns to be patient with struggling child
    p.patience += 0.01;

    // Update accuracy EMA
    p.totalWordsAttempted++;
    p.accuracyEma = p.accuracyEma * 0.9 + 0.0 * 0.1;

    p.clampTraits();
    _save(profileId, p);
  }

  /// Record a mini game played.
  void onMiniGamePlayed(String profileId, int gameIndex) {
    final p = _activeOrLoad(profileId);

    // Playfulness grows with mini-game engagement
    p.playfulness = (p.playfulness + 0.02).clamp(0.0, 1.0);

    // Track recent games for favorite calculation
    p.recentGames.add(gameIndex);
    if (p.recentGames.length > 20) {
      p.recentGames.removeAt(0);
    }

    // Update favorite game (mode of recent 20)
    p.favoriteGameIndex = _modeValue(p.recentGames);

    p.clampTraits();
    _save(profileId, p);
  }

  /// Record a streak day milestone.
  void onStreakDay(String profileId, int streakCount) {
    final p = _activeOrLoad(profileId);

    // Confidence boost proportional to streak (capped at 10 days)
    final boost = 0.02 * streakCount.clamp(0, 10);
    p.confidence = (p.confidence + boost).clamp(0.3, 1.0);
    p.energy = (p.energy + 0.02 * streakCount.clamp(0, 10)).clamp(0.0, 1.0);

    p.clampTraits();
    _save(profileId, p);
  }

  // ── Mood computation ───────────────────────────────────────────────

  /// Compute the current mood for a profile based on personality + context.
  AvatarMood computeMood(String profileId) {
    final p = forProfile(profileId);
    final hourNow = DateTime.now().hour;
    final daysSince = _daysSinceLastPlay(p);

    // Time-of-day modifiers
    final isLateNight = hourNow >= 21 || hourNow <= 5;
    final isPreferredTime =
        (hourNow - p.preferredPlayHour).abs() <= 1 ||
        (hourNow - p.preferredPlayHour).abs() >= 23; // wrap-around

    // Reunion excitement: haven't played in 3+ days
    final isReunion = daysSince >= 3;

    // Energy level
    final double moodEnergy;
    if (isLateNight) {
      moodEnergy = (p.energy * 0.4).clamp(0.1, 0.4); // sleepy at night
    } else if (isReunion) {
      moodEnergy = 0.9; // super excited to see you again
    } else {
      moodEnergy = p.energy;
    }

    // Default expression
    final AvatarExpression expression;
    if (isLateNight) {
      expression = AvatarExpression.neutral; // calm
    } else if (isReunion) {
      expression = AvatarExpression.excited;
    } else if (p.confidence > 0.7) {
      expression = AvatarExpression.happy;
    } else {
      expression = AvatarExpression.neutral;
    }

    // Greeting behavior
    final shouldWave = isReunion || isPreferredTime;
    final String greetingClip;
    if (isReunion) {
      greetingClip = 'celebrate';
    } else if (isPreferredTime) {
      greetingClip = 'wave';
    } else {
      greetingClip = 'nod';
    }

    return AvatarMood(
      energyLevel: moodEnergy.clamp(0.05, 1.0),
      defaultExpression: expression,
      reactionIntensity: p.playfulness.clamp(0.3, 1.0),
      shouldWave: shouldWave,
      greetingClip: greetingClip,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  AvatarPersonality _activeOrLoad(String profileId) {
    if (_active != null && _activeProfileId == profileId) return _active!;
    _active = forProfile(profileId);
    _activeProfileId = profileId;
    return _active!;
  }

  void _save(String profileId, AvatarPersonality p) {
    _box.put(profileId, p);
  }

  int _daysSinceLastPlay(AvatarPersonality p) {
    if (p.lastPlayTimestamp == 0) return 0;
    final last = DateTime.fromMillisecondsSinceEpoch(p.lastPlayTimestamp);
    return DateTime.now().difference(last).inDays;
  }

  /// Find the mode (most common value) in a list.
  int _modeValue(List<int> values) {
    if (values.isEmpty) return -1;
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Find the hour with the highest count in the histogram.
  int _modeHour(List<int> histogram) {
    if (histogram.isEmpty) return 12;
    int maxIdx = 0;
    for (int i = 1; i < histogram.length; i++) {
      if (histogram[i] > histogram[maxIdx]) maxIdx = i;
    }
    return maxIdx;
  }

  /// Debug string showing current personality state for a profile.
  String debugSummary(String profileId) {
    final p = forProfile(profileId);
    final mood = computeMood(profileId);
    return 'Personality('
        'E:${p.energy.toStringAsFixed(2)}, '
        'C:${p.confidence.toStringAsFixed(2)}, '
        'P:${p.playfulness.toStringAsFixed(2)}, '
        'Pa:${p.patience.toStringAsFixed(2)}) '
        'Mood:${mood.defaultExpression.name} '
        'Energy:${mood.energyLevel.toStringAsFixed(2)} '
        'Greet:${mood.greetingClip}';
  }
}

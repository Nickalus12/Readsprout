import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks detailed interaction statistics per profile.
///
/// Persists to SharedPreferences as JSON. Profile-scoped so each child
/// has their own stats.
class StatsService {
  static const _baseKey = 'player_stats';
  late SharedPreferences _prefs;
  String _profileId = '';
  late PlayerStats _stats;

  String get _key =>
      _profileId.isEmpty ? _baseKey : '${_baseKey}_$_profileId';

  PlayerStats get stats => _stats;

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _load();
  }

  void switchProfile(String profileId) {
    _profileId = profileId;
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _stats = PlayerStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _stats = PlayerStats();
      }
    } else {
      _stats = PlayerStats();
    }
  }

  Future<void> _save() async {
    final encoded = jsonEncode(_stats.toJson());
    await _prefs.setString(_key, encoded);
  }

  // ── Recording Methods ──────────────────────────────────────────────

  /// Record a correct letter tap (adventure mode or mini games).
  Future<void> recordLetterTap(String letter) async {
    final l = letter.toLowerCase();
    _stats.letterTaps[l] = (_stats.letterTaps[l] ?? 0) + 1;
    _stats.totalLetterTaps++;
    await _save();
  }

  /// Record a wrong letter tap.
  Future<void> recordWrongTap(String tappedLetter, String expectedLetter) async {
    _stats.totalWrongTaps++;
    final t = tappedLetter.toLowerCase();
    _stats.wrongLetterTaps[t] = (_stats.wrongLetterTaps[t] ?? 0) + 1;
    // Track common confusions: "tapped X when expected Y"
    final key = '${t}_for_${expectedLetter.toLowerCase()}';
    _stats.confusions[key] = (_stats.confusions[key] ?? 0) + 1;
    await _save();
  }

  /// Record a word completed (spelled correctly).
  Future<void> recordWordCompleted(String word, int mistakes) async {
    final w = word.toLowerCase();
    final entry = _stats.wordAttempts[w] ?? const WordAttemptStats();
    _stats.wordAttempts[w] = WordAttemptStats(
      attempts: entry.attempts + 1,
      perfectAttempts: mistakes == 0
          ? entry.perfectAttempts + 1
          : entry.perfectAttempts,
      totalMistakes: entry.totalMistakes + mistakes,
    );
    _stats.totalWordsCompleted++;
    if (mistakes == 0) _stats.totalPerfectWords++;
    await _save();
  }

  /// Record a mini game played.
  Future<void> recordMiniGamePlayed(String gameId, int score) async {
    final entry = _stats.miniGameStats[gameId] ?? const MiniGameAttemptStats();
    _stats.miniGameStats[gameId] = MiniGameAttemptStats(
      timesPlayed: entry.timesPlayed + 1,
      highScore: score > entry.highScore ? score : entry.highScore,
      totalScore: entry.totalScore + score,
    );
    _stats.totalMiniGamesPlayed++;
    await _save();
  }

  /// Record total play time in seconds for a session.
  Future<void> recordPlayTime(int seconds) async {
    _stats.totalPlayTimeSeconds += seconds;
    _stats.totalSessions++;
    await _save();
  }

  /// Record a word heard (tapped speaker icon).
  Future<void> recordWordHeard(String word) async {
    _stats.totalWordsHeard++;
    await _save();
  }

  // ── Query Methods ──────────────────────────────────────────────────

  /// Get tap count for a specific letter.
  int letterTapCount(String letter) =>
      _stats.letterTaps[letter.toLowerCase()] ?? 0;

  /// Get the most tapped letters, sorted descending.
  List<MapEntry<String, int>> get topLetters {
    final entries = _stats.letterTaps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Get letters never tapped.
  List<String> get untappedLetters {
    const all = 'abcdefghijklmnopqrstuvwxyz';
    return all.split('').where((l) => !_stats.letterTaps.containsKey(l)).toList();
  }

  /// Get most confused letter pairs.
  List<MapEntry<String, int>> get topConfusions {
    final entries = _stats.confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Get hardest words (most mistakes per attempt).
  List<MapEntry<String, double>> get hardestWords {
    final entries = <MapEntry<String, double>>[];
    for (final e in _stats.wordAttempts.entries) {
      if (e.value.attempts > 0) {
        entries.add(MapEntry(
          e.key,
          e.value.totalMistakes / e.value.attempts,
        ));
      }
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Get easiest words (highest perfect rate).
  List<MapEntry<String, double>> get easiestWords {
    final entries = <MapEntry<String, double>>[];
    for (final e in _stats.wordAttempts.entries) {
      if (e.value.attempts > 0) {
        entries.add(MapEntry(
          e.key,
          e.value.perfectAttempts / e.value.attempts,
        ));
      }
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Overall accuracy (correct taps / total taps).
  double get accuracy {
    final total = _stats.totalLetterTaps + _stats.totalWrongTaps;
    if (total == 0) return 1.0;
    return _stats.totalLetterTaps / total;
  }

  /// Reset all stats.
  Future<void> resetAll() async {
    _stats = PlayerStats();
    await _save();
  }
}

// ── Data Models ──────────────────────────────────────────────────────

class PlayerStats {
  /// Per-letter correct tap counts: {'a': 42, 'b': 15, ...}
  Map<String, int> letterTaps;

  /// Per-letter wrong tap counts.
  Map<String, int> wrongLetterTaps;

  /// Confusion pairs: {'b_for_d': 5} means tapped 'b' when 'd' was expected.
  Map<String, int> confusions;

  /// Per-word attempt stats.
  Map<String, WordAttemptStats> wordAttempts;

  /// Per-mini-game stats.
  Map<String, MiniGameAttemptStats> miniGameStats;

  int totalLetterTaps;
  int totalWrongTaps;
  int totalWordsCompleted;
  int totalPerfectWords;
  int totalMiniGamesPlayed;
  int totalWordsHeard;
  int totalPlayTimeSeconds;
  int totalSessions;

  PlayerStats({
    Map<String, int>? letterTaps,
    Map<String, int>? wrongLetterTaps,
    Map<String, int>? confusions,
    Map<String, WordAttemptStats>? wordAttempts,
    Map<String, MiniGameAttemptStats>? miniGameStats,
    this.totalLetterTaps = 0,
    this.totalWrongTaps = 0,
    this.totalWordsCompleted = 0,
    this.totalPerfectWords = 0,
    this.totalMiniGamesPlayed = 0,
    this.totalWordsHeard = 0,
    this.totalPlayTimeSeconds = 0,
    this.totalSessions = 0,
  })  : letterTaps = letterTaps ?? {},
        wrongLetterTaps = wrongLetterTaps ?? {},
        confusions = confusions ?? {},
        wordAttempts = wordAttempts ?? {},
        miniGameStats = miniGameStats ?? {};

  Map<String, dynamic> toJson() => {
        'letterTaps': letterTaps,
        'wrongLetterTaps': wrongLetterTaps,
        'confusions': confusions,
        'wordAttempts': wordAttempts
            .map((k, v) => MapEntry(k, v.toJson())),
        'miniGameStats': miniGameStats
            .map((k, v) => MapEntry(k, v.toJson())),
        'totalLetterTaps': totalLetterTaps,
        'totalWrongTaps': totalWrongTaps,
        'totalWordsCompleted': totalWordsCompleted,
        'totalPerfectWords': totalPerfectWords,
        'totalMiniGamesPlayed': totalMiniGamesPlayed,
        'totalWordsHeard': totalWordsHeard,
        'totalPlayTimeSeconds': totalPlayTimeSeconds,
        'totalSessions': totalSessions,
      };

  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        letterTaps: _intMap(json['letterTaps']),
        wrongLetterTaps: _intMap(json['wrongLetterTaps']),
        confusions: _intMap(json['confusions']),
        wordAttempts: (json['wordAttempts'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(
                  k, WordAttemptStats.fromJson(v as Map<String, dynamic>)),
            ) ??
            {},
        miniGameStats:
            (json['miniGameStats'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(k,
                      MiniGameAttemptStats.fromJson(v as Map<String, dynamic>)),
                ) ??
                {},
        totalLetterTaps: json['totalLetterTaps'] as int? ?? 0,
        totalWrongTaps: json['totalWrongTaps'] as int? ?? 0,
        totalWordsCompleted: json['totalWordsCompleted'] as int? ?? 0,
        totalPerfectWords: json['totalPerfectWords'] as int? ?? 0,
        totalMiniGamesPlayed: json['totalMiniGamesPlayed'] as int? ?? 0,
        totalWordsHeard: json['totalWordsHeard'] as int? ?? 0,
        totalPlayTimeSeconds: json['totalPlayTimeSeconds'] as int? ?? 0,
        totalSessions: json['totalSessions'] as int? ?? 0,
      );

  static Map<String, int> _intMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw.map((k, v) => MapEntry(k, v as int? ?? 0));
    }
    return {};
  }
}

class WordAttemptStats {
  final int attempts;
  final int perfectAttempts;
  final int totalMistakes;

  const WordAttemptStats({
    this.attempts = 0,
    this.perfectAttempts = 0,
    this.totalMistakes = 0,
  });

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'perfectAttempts': perfectAttempts,
        'totalMistakes': totalMistakes,
      };

  factory WordAttemptStats.fromJson(Map<String, dynamic> json) =>
      WordAttemptStats(
        attempts: json['attempts'] as int? ?? 0,
        perfectAttempts: json['perfectAttempts'] as int? ?? 0,
        totalMistakes: json['totalMistakes'] as int? ?? 0,
      );
}

class MiniGameAttemptStats {
  final int timesPlayed;
  final int highScore;
  final int totalScore;

  const MiniGameAttemptStats({
    this.timesPlayed = 0,
    this.highScore = 0,
    this.totalScore = 0,
  });

  double get averageScore =>
      timesPlayed > 0 ? totalScore / timesPlayed : 0;

  Map<String, dynamic> toJson() => {
        'timesPlayed': timesPlayed,
        'highScore': highScore,
        'totalScore': totalScore,
      };

  factory MiniGameAttemptStats.fromJson(Map<String, dynamic> json) =>
      MiniGameAttemptStats(
        timesPlayed: json['timesPlayed'] as int? ?? 0,
        highScore: json['highScore'] as int? ?? 0,
        totalScore: json['totalScore'] as int? ?? 0,
      );
}

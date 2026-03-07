import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HighScoreEntry {
  final int score;
  final String playerName;
  final DateTime date;

  const HighScoreEntry({
    required this.score,
    required this.playerName,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'score': score,
        'playerName': playerName,
        'date': date.toIso8601String(),
      };

  factory HighScoreEntry.fromJson(Map<String, dynamic> json) => HighScoreEntry(
        score: json['score'] as int,
        playerName: json['playerName'] as String,
        date: DateTime.parse(json['date'] as String),
      );
}

class HighScoreService {
  static const _basePrefix = 'high_scores_';
  static const _maxEntries = 10;
  late SharedPreferences _prefs;
  String _profileId = '';

  String get _prefix => _profileId.isEmpty ? _basePrefix : '$_basePrefix${_profileId}_';

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
  }

  /// Switch to a different profile's high scores.
  void switchProfile(String profileId) {
    _profileId = profileId;
  }

  /// Save a score. Returns true if it's a new personal best.
  Future<bool> saveScore(String gameId, int score, String playerName) async {
    final scores = getHighScores(gameId);
    final previousBest = scores.isEmpty ? 0 : scores.first.score;

    final entry = HighScoreEntry(
      score: score,
      playerName: playerName,
      date: DateTime.now(),
    );

    scores.add(entry);
    scores.sort((a, b) => b.score.compareTo(a.score));

    if (scores.length > _maxEntries) {
      scores.removeRange(_maxEntries, scores.length);
    }

    final encoded = jsonEncode(scores.map((e) => e.toJson()).toList());
    await _prefs.setString('$_prefix$gameId', encoded);

    return score > 0 && score > previousBest;
  }

  /// Get top scores for a game, sorted descending. Max [limit].
  List<HighScoreEntry> getHighScores(String gameId, {int limit = 10}) {
    final raw = _prefs.getString('$_prefix$gameId');
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final entries = decoded
        .map((e) => HighScoreEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.score.compareTo(a.score));

    if (entries.length > limit) {
      return entries.sublist(0, limit);
    }
    return entries;
  }

  /// Get the highest score for a game.
  int getPersonalBest(String gameId) {
    final scores = getHighScores(gameId);
    if (scores.isEmpty) return 0;
    return scores.first.score;
  }

  /// Check if a score would make the leaderboard.
  bool isHighScore(String gameId, int score) {
    if (score <= 0) return false;
    final scores = getHighScores(gameId);
    if (scores.length < _maxEntries) return true;
    return score > scores.last.score;
  }
}

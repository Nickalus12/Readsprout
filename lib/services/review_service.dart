import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/review_data.dart';

class ReviewSummary {
  final int totalTracked;
  final int dueToday;
  final int mastered; // interval > 21 days

  const ReviewSummary({
    required this.totalTracked,
    required this.dueToday,
    required this.mastered,
  });
}

class ReviewService {
  static const _key = 'review_data';
  late SharedPreferences _prefs;
  late Map<String, ReviewData> _reviews; // word text -> review data

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadReviews();
  }

  void _loadReviews() {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _reviews = decoded.map((key, value) => MapEntry(
            key,
            ReviewData.fromJson(value as Map<String, dynamic>),
          ));
    } else {
      _reviews = {};
    }
  }

  Future<void> _save() async {
    final encoded = jsonEncode(
      _reviews.map((key, value) => MapEntry(key, value.toJson())),
    );
    await _prefs.setString(_key, encoded);
  }

  /// Record a word review, converting mistake count to SM-2 quality score.
  ///   0 mistakes = quality 5
  ///   1 mistake  = quality 4
  ///   2 mistakes = quality 3
  ///   3 mistakes = quality 2
  ///   4+ mistakes = quality 1
  Future<void> recordWordReview(String word, int mistakes) async {
    final quality = _mistakesToQuality(mistakes);
    final current = _reviews[word] ?? ReviewData.initial(word);
    _reviews[word] = current.recordReview(quality);
    await _save();
  }

  int _mistakesToQuality(int mistakes) {
    if (mistakes <= 0) return 5;
    if (mistakes == 1) return 4;
    if (mistakes == 2) return 3;
    if (mistakes == 3) return 2;
    return 1;
  }

  /// Returns words most overdue for review, up to [limit].
  List<String> getDueWords({int limit = 10}) {
    final due = _reviews.entries
        .where((e) => e.value.isDue)
        .toList()
      ..sort((a, b) {
        // Sort by priority — most overdue first
        final aPriority = getWordPriority(a.key);
        final bPriority = getWordPriority(b.key);
        return bPriority.compareTo(aPriority);
      });
    return due.take(limit).map((e) => e.key).toList();
  }

  /// Returns a priority score for a word (higher = more urgent).
  /// Words that are more overdue and have lower ease factors get higher priority.
  double getWordPriority(String word) {
    final review = _reviews[word];
    if (review == null) return 0.0;

    final daysSinceReview =
        DateTime.now().difference(review.lastReviewDate).inDays;
    final overdueDays = daysSinceReview - review.interval;

    if (overdueDays < 0) return 0.0; // Not yet due

    // Higher priority for: more overdue, lower ease factor, fewer repetitions
    return (overdueDays + 1) * (3.0 / review.easeFactor);
  }

  /// Reorders a word list putting due-for-review words first.
  List<String> orderWordsForPractice(List<String> words) {
    final sorted = List<String>.from(words);
    sorted.sort((a, b) {
      final aPriority = getWordPriority(a);
      final bPriority = getWordPriority(b);
      return bPriority.compareTo(aPriority);
    });
    return sorted;
  }

  /// Returns a summary of the review state.
  ReviewSummary getReviewSummary() {
    int dueCount = 0;
    int masteredCount = 0;

    for (final review in _reviews.values) {
      if (review.isDue) dueCount++;
      if (review.interval > 21) masteredCount++;
    }

    return ReviewSummary(
      totalTracked: _reviews.length,
      dueToday: dueCount,
      mastered: masteredCount,
    );
  }
}

class ReviewData {
  final String word;
  final DateTime lastReviewDate;
  final double easeFactor; // SM-2 ease factor, default 2.5
  final int interval; // days until next review
  final int repetitionCount;

  const ReviewData({
    required this.word,
    required this.lastReviewDate,
    this.easeFactor = 2.5,
    this.interval = 0,
    this.repetitionCount = 0,
  });

  factory ReviewData.initial(String word) {
    return ReviewData(
      word: word,
      lastReviewDate: DateTime.now(),
      easeFactor: 2.5,
      interval: 0,
      repetitionCount: 0,
    );
  }

  /// Whether this word is due for review.
  bool get isDue =>
      DateTime.now().difference(lastReviewDate).inDays >= interval;

  /// Calculate the next review state based on SM-2 quality score (0-5).
  ReviewData recordReview(int quality) {
    final q = quality.clamp(0, 5);

    int newRepetitions;
    int newInterval;

    if (q >= 3) {
      // Correct response
      if (repetitionCount == 0) {
        newInterval = 1;
      } else if (repetitionCount == 1) {
        newInterval = 6;
      } else {
        newInterval = (interval * easeFactor).round();
      }
      newRepetitions = repetitionCount + 1;
    } else {
      // Incorrect — reset
      newRepetitions = 0;
      newInterval = 1;
    }

    // Update ease factor (never below 1.3)
    final newEase = (easeFactor +
            (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
        .clamp(1.3, double.infinity);

    return ReviewData(
      word: word,
      lastReviewDate: DateTime.now(),
      easeFactor: newEase,
      interval: newInterval,
      repetitionCount: newRepetitions,
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'lastReviewDate': lastReviewDate.toIso8601String(),
        'easeFactor': easeFactor,
        'interval': interval,
        'repetitionCount': repetitionCount,
      };

  factory ReviewData.fromJson(Map<String, dynamic> json) {
    return ReviewData(
      word: json['word'] as String,
      lastReviewDate: DateTime.parse(json['lastReviewDate'] as String),
      easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
      interval: json['interval'] as int? ?? 0,
      repetitionCount: json['repetitionCount'] as int? ?? 0,
    );
  }
}

/// Per-game difficulty parameters that games consume.
///
/// Created by [AdaptiveDifficultyService.getParamsForGame] with values
/// interpolated between "easy" and "hard" extremes based on the player's
/// current difficulty level.
class GameDifficultyParams {
  final double difficulty; // 0.0-1.0 raw value
  final int lives;
  final double gameSpeed;
  final double gameDurationSeconds;
  final int distractorCount;
  final double spawnInterval;
  final int wordCount;

  const GameDifficultyParams({
    this.difficulty = 0.2,
    this.lives = 3,
    this.gameSpeed = 1.0,
    this.gameDurationSeconds = 60,
    this.distractorCount = 3,
    this.spawnInterval = 2.0,
    this.wordCount = 10,
  });

  /// Linearly interpolate a value between easy and hard based on difficulty.
  static double lerp(double easy, double hard, double difficulty) {
    return easy + (hard - easy) * difficulty;
  }

  /// Linearly interpolate an integer between easy and hard based on difficulty.
  static int lerpInt(int easy, int hard, double difficulty) {
    return (easy + (hard - easy) * difficulty).round();
  }

  /// Generate params tuned for a specific mini game.
  factory GameDifficultyParams.forGame(String gameId, double difficulty) {
    switch (gameId) {
      case 'unicorn_flight':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 3, difficulty),
          gameSpeed: lerp(0.8, 1.6, difficulty),
          spawnInterval: lerp(2.5, 1.0, difficulty),
          distractorCount: lerpInt(2, 6, difficulty),
          wordCount: lerpInt(8, 20, difficulty),
        );
      case 'lightning_speller':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameSpeed: lerp(0.8, 1.4, difficulty),
          distractorCount: lerpInt(1, 4, difficulty),
          wordCount: lerpInt(6, 15, difficulty),
        );
      case 'word_bubbles':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(90, 45, difficulty),
          spawnInterval: lerp(2.5, 0.8, difficulty),
          gameSpeed: lerp(0.5, 1.5, difficulty),
          wordCount: lerpInt(5, 8, difficulty),
        );
      case 'memory_match':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(8, 4, difficulty),
          gameSpeed: lerp(3.0, 0.5, difficulty), // preview time
          wordCount: lerpInt(4, 8, difficulty), // pair count
        );
      case 'falling_letters':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameSpeed: lerp(0.6, 1.5, difficulty),
          spawnInterval: lerp(2.0, 0.8, difficulty),
          wordCount: lerpInt(6, 15, difficulty),
        );
      case 'cat_letter_toss':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameSpeed: lerp(0.7, 1.5, difficulty),
          wordCount: lerpInt(6, 14, difficulty),
        );
      case 'letter_drop':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(120, 60, difficulty),
          wordCount: lerpInt(5, 12, difficulty),
        );
      case 'rhyme_time':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(90, 40, difficulty),
          distractorCount: lerpInt(2, 6, difficulty),
        );
      case 'star_catcher':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(90, 40, difficulty),
          gameSpeed: lerp(0.5, 1.8, difficulty),
          distractorCount: lerpInt(2, 8, difficulty),
        );
      case 'paint_splash':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(90, 40, difficulty),
          gameSpeed: lerp(0.5, 1.5, difficulty),
          distractorCount: lerpInt(2, 8, difficulty),
        );
      case 'word_rocket':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameSpeed: lerp(0.8, 1.5, difficulty),
          wordCount: lerpInt(8, 15, difficulty),
        );
      case 'sight_word_safari':
        return GameDifficultyParams(
          difficulty: difficulty,
          gameDurationSeconds: lerp(10, 5, difficulty),
          distractorCount: lerpInt(3, 6, difficulty),
          wordCount: lerpInt(10, 18, difficulty),
        );
      case 'word_ninja':
        return GameDifficultyParams(
          difficulty: difficulty,
          lives: lerpInt(5, 2, difficulty),
          gameDurationSeconds: lerp(60, 30, difficulty),
          spawnInterval: lerp(1.5, 0.6, difficulty),
          distractorCount: lerpInt(2, 5, difficulty),
        );
      case 'spelling_bee':
        return GameDifficultyParams(
          difficulty: difficulty,
          wordCount: lerpInt(8, 15, difficulty),
          distractorCount: lerpInt(3, 6, difficulty),
        );
      case 'word_train':
        return GameDifficultyParams(
          difficulty: difficulty,
          wordCount: lerpInt(6, 12, difficulty),
          distractorCount: lerpInt(2, 5, difficulty),
        );
      default:
        return GameDifficultyParams(difficulty: difficulty);
    }
  }
}

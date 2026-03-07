import 'package:flutter/material.dart';

/// Categories for sticker grouping.
enum StickerCategory {
  level,
  milestone,
  streak,
  perfect,
  evolution,
  special,
  miniGame,
}

/// Definition of a single sticker that can be earned.
class StickerDefinition {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final StickerCategory category;
  final Color color;

  /// Filename (without extension) for the spoken sticker name audio.
  /// Maps to `assets/audio/words/<audioKey>.mp3`.
  final String audioKey;

  const StickerDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.color,
    required this.audioKey,
  });
}

/// All sticker definitions for the app.
class StickerDefinitions {
  StickerDefinitions._();

  // ── Level Completion (22 stickers) ────────────────────────────────

  static final List<StickerDefinition> levelStickers = List.generate(
    22,
    (i) => StickerDefinition(
      id: 'level_${i + 1}',
      name: 'Level ${i + 1}',
      description: 'Completed all words in Level ${i + 1}!',
      icon: Icons.local_florist,
      category: StickerCategory.level,
      color: _levelColors[i % _levelColors.length],
      audioKey: 'level_${i + 1}',
    ),
  );

  static const List<Color> _levelColors = [
    Color(0xFFFF9A76), // Peach
    Color(0xFFB794F6), // Lavender
    Color(0xFF7BD4A8), // Mint
    Color(0xFF6BB8F0), // Sky
    Color(0xFFD680A8), // Rose
    Color(0xFFFFBF69), // Honey
    Color(0xFFFF7085), // Coral
    Color(0xFF8FD4B8), // Sage
    Color(0xFFA5B0D9), // Periwinkle
    Color(0xFFFFAFCC), // Blush
    Color(0xFF9B8FE0), // Iris
  ];

  // ── Milestone Stickers (8) ────────────────────────────────────────

  static const List<StickerDefinition> milestoneStickers = [
    StickerDefinition(
      id: 'milestone_1',
      name: 'First Word!',
      description: 'Mastered your very first word!',
      icon: Icons.emoji_events,
      category: StickerCategory.milestone,
      color: Color(0xFFFFD700),
      audioKey: 'first_word',
    ),
    StickerDefinition(
      id: 'milestone_10',
      name: '10 Words!',
      description: 'Mastered 10 words -- great start!',
      icon: Icons.star,
      category: StickerCategory.milestone,
      color: Color(0xFF7BD4A8),
      audioKey: 'ten_words',
    ),
    StickerDefinition(
      id: 'milestone_25',
      name: '25 Words!',
      description: 'Mastered 25 words -- keep it up!',
      icon: Icons.star,
      category: StickerCategory.milestone,
      color: Color(0xFF6BB8F0),
      audioKey: 'twenty_five_words',
    ),
    StickerDefinition(
      id: 'milestone_50',
      name: '50 Words!',
      description: 'Mastered 50 words -- amazing!',
      icon: Icons.star_half,
      category: StickerCategory.milestone,
      color: Color(0xFFB794F6),
      audioKey: 'fifty_words',
    ),
    StickerDefinition(
      id: 'milestone_100',
      name: '100 Words!',
      description: 'Mastered 100 words -- halfway there!',
      icon: Icons.stars,
      category: StickerCategory.milestone,
      color: Color(0xFFEC4899),
      audioKey: 'one_hundred_words',
    ),
    StickerDefinition(
      id: 'milestone_150',
      name: '150 Words!',
      description: 'Mastered 150 words -- incredible!',
      icon: Icons.auto_awesome,
      category: StickerCategory.milestone,
      color: Color(0xFFFF8C42),
      audioKey: 'one_hundred_fifty_words',
    ),
    StickerDefinition(
      id: 'milestone_200',
      name: '200 Words!',
      description: 'Mastered 200 words -- almost done!',
      icon: Icons.workspace_premium,
      category: StickerCategory.milestone,
      color: Color(0xFF00D4FF),
      audioKey: 'two_hundred_words',
    ),
    StickerDefinition(
      id: 'milestone_all',
      name: 'All Words!',
      description: 'Mastered every single word! You are a superstar!',
      icon: Icons.military_tech,
      category: StickerCategory.milestone,
      color: Color(0xFFFFD700),
      audioKey: 'all_words',
    ),
  ];

  // ── Streak Stickers (4) ───────────────────────────────────────────

  static const List<StickerDefinition> streakStickers = [
    StickerDefinition(
      id: 'streak_3',
      name: '3 Day Streak',
      description: 'Practiced 3 days in a row!',
      icon: Icons.local_fire_department,
      category: StickerCategory.streak,
      color: Color(0xFFFF8C42),
      audioKey: 'three_day_streak',
    ),
    StickerDefinition(
      id: 'streak_7',
      name: '7 Day Streak',
      description: 'A whole week of reading -- wow!',
      icon: Icons.local_fire_department,
      category: StickerCategory.streak,
      color: Color(0xFFFF4444),
      audioKey: 'seven_day_streak',
    ),
    StickerDefinition(
      id: 'streak_14',
      name: '14 Day Streak',
      description: 'Two weeks of reading every day!',
      icon: Icons.whatshot,
      category: StickerCategory.streak,
      color: Color(0xFF8B5CF6),
      audioKey: 'fourteen_day_streak',
    ),
    StickerDefinition(
      id: 'streak_30',
      name: '30 Day Streak',
      description: 'A whole month -- you are unstoppable!',
      icon: Icons.whatshot,
      category: StickerCategory.streak,
      color: Color(0xFFFFD700),
      audioKey: 'thirty_day_streak',
    ),
  ];

  // ── Perfect Sticker (1) ───────────────────────────────────────────

  static const List<StickerDefinition> perfectStickers = [
    StickerDefinition(
      id: 'perfect_level',
      name: 'Perfect Level',
      description: 'Completed a level with zero mistakes!',
      icon: Icons.verified,
      category: StickerCategory.perfect,
      color: Color(0xFF00E68A),
      audioKey: 'perfect_level',
    ),
  ];

  // ── Evolution Stickers (5) ────────────────────────────────────────

  static const List<StickerDefinition> evolutionStickers = [
    StickerDefinition(
      id: 'evo_sprout',
      name: 'Word Sprout',
      description: 'Your bookworm has hatched!',
      icon: Icons.eco,
      category: StickerCategory.evolution,
      color: Color(0xFF10B981),
      audioKey: 'word_sprout',
    ),
    StickerDefinition(
      id: 'evo_explorer',
      name: 'Word Explorer',
      description: 'Your bookworm is exploring! (21+ words)',
      icon: Icons.explore,
      category: StickerCategory.evolution,
      color: Color(0xFF06B6D4),
      audioKey: 'word_explorer',
    ),
    StickerDefinition(
      id: 'evo_wizard',
      name: 'Word Wizard',
      description: 'Your bookworm learned magic! (61+ words)',
      icon: Icons.auto_fix_high,
      category: StickerCategory.evolution,
      color: Color(0xFF8B5CF6),
      audioKey: 'word_wizard',
    ),
    StickerDefinition(
      id: 'evo_champion',
      name: 'Word Champion',
      description: 'Your bookworm became a butterfly! (121+ words)',
      icon: Icons.flutter_dash,
      category: StickerCategory.evolution,
      color: Color(0xFF00D4FF),
      audioKey: 'word_champion',
    ),
    StickerDefinition(
      id: 'evo_superstar',
      name: 'Reading Superstar',
      description: 'Your bookworm is a superstar! (181+ words)',
      icon: Icons.auto_awesome,
      category: StickerCategory.evolution,
      color: Color(0xFFFFD700),
      audioKey: 'reading_superstar',
    ),
  ];

  // ── Special Stickers (1) ──────────────────────────────────────────

  static const List<StickerDefinition> specialStickers = [
    StickerDefinition(
      id: 'speed_reader',
      name: 'Speed Reader',
      description: 'Completed 5 words in under 2 minutes!',
      icon: Icons.bolt,
      category: StickerCategory.special,
      color: Color(0xFFFFBF69),
      audioKey: 'speed_reader',
    ),
  ];

  // ── Mini-Game Stickers ────────────────────────────────────────────

  static const List<StickerDefinition> miniGameStickers = [
    // Unicorn Flight (score-based flying/spelling)
    StickerDefinition(
      id: 'mg_unicorn_first_flight',
      name: 'First Flight',
      description: 'Completed your first Unicorn Flight game!',
      icon: Icons.flight,
      category: StickerCategory.miniGame,
      color: Color(0xFFE0B0FF),
      audioKey: 'first_flight',
    ),
    StickerDefinition(
      id: 'mg_unicorn_rider',
      name: 'Unicorn Rider',
      description: 'Spelled 10+ words in Unicorn Flight!',
      icon: Icons.flight_takeoff,
      category: StickerCategory.miniGame,
      color: Color(0xFFD070FF),
      audioKey: 'unicorn_rider',
    ),
    StickerDefinition(
      id: 'mg_unicorn_sky_champion',
      name: 'Sky Champion',
      description: 'Spelled 25+ words in Unicorn Flight!',
      icon: Icons.cloud,
      category: StickerCategory.miniGame,
      color: Color(0xFFC040FF),
      audioKey: 'sky_champion',
    ),

    // Lightning Speller (spell words as letters fall from storm clouds)
    StickerDefinition(
      id: 'mg_lightning_starter',
      name: 'Storm Speller',
      description: 'Completed your first Lightning Speller game!',
      icon: Icons.flash_on,
      category: StickerCategory.miniGame,
      color: Color(0xFF6BB8F0),
      audioKey: 'storm_speller',
    ),
    StickerDefinition(
      id: 'mg_lightning_fast',
      name: 'Lightning Fast',
      description: 'Scored 20+ in Lightning Speller!',
      icon: Icons.bolt,
      category: StickerCategory.miniGame,
      color: Color(0xFF4A9FE0),
      audioKey: 'lightning_fast',
    ),
    StickerDefinition(
      id: 'mg_lightning_thunder',
      name: 'Thunder Brain',
      description: 'Scored 40+ in Lightning Speller!',
      icon: Icons.electric_bolt,
      category: StickerCategory.miniGame,
      color: Color(0xFF2A80D0),
      audioKey: 'thunder_brain',
    ),

    // Word Bubbles (pop bubbles with correct letters)
    StickerDefinition(
      id: 'mg_bubbles_popper',
      name: 'Bubble Popper',
      description: 'Completed your first Word Bubbles game!',
      icon: Icons.bubble_chart,
      category: StickerCategory.miniGame,
      color: Color(0xFF80DFFF),
      audioKey: 'bubble_popper',
    ),
    StickerDefinition(
      id: 'mg_bubbles_master',
      name: 'Bubble Master',
      description: 'Scored 15+ in Word Bubbles!',
      icon: Icons.bubble_chart_outlined,
      category: StickerCategory.miniGame,
      color: Color(0xFF40CFFF),
      audioKey: 'bubble_master',
    ),

    // Memory Match (match word pairs)
    StickerDefinition(
      id: 'mg_memory_starter',
      name: 'Memory Maker',
      description: 'Completed your first Memory Match game!',
      icon: Icons.grid_view,
      category: StickerCategory.miniGame,
      color: Color(0xFFC4A8F0),
      audioKey: 'memory_maker',
    ),
    StickerDefinition(
      id: 'mg_memory_sharp',
      name: 'Sharp Memory',
      description: 'Matched all pairs with 5 or fewer misses!',
      icon: Icons.psychology,
      category: StickerCategory.miniGame,
      color: Color(0xFFAA80E8),
      audioKey: 'sharp_memory',
    ),
    StickerDefinition(
      id: 'mg_memory_perfect',
      name: 'Perfect Recall',
      description: 'Matched all pairs with zero misses!',
      icon: Icons.psychology_alt,
      category: StickerCategory.miniGame,
      color: Color(0xFF9060E0),
      audioKey: 'perfect_recall',
    ),

    // Falling Letters (catch falling letters to spell words)
    StickerDefinition(
      id: 'mg_falling_catcher',
      name: 'Letter Catcher',
      description: 'Completed your first Falling Letters game!',
      icon: Icons.catching_pokemon,
      category: StickerCategory.miniGame,
      color: Color(0xFFFFD060),
      audioKey: 'letter_catcher',
    ),
    StickerDefinition(
      id: 'mg_falling_pro',
      name: 'Falling Star',
      description: 'Scored 15+ in Falling Letters!',
      icon: Icons.star_rate,
      category: StickerCategory.miniGame,
      color: Color(0xFFFFBF30),
      audioKey: 'falling_star',
    ),

    // Cat Letter Toss (toss letters at targets)
    StickerDefinition(
      id: 'mg_cat_tosser',
      name: 'Cat Tosser',
      description: 'Completed your first Cat Letter Toss game!',
      icon: Icons.pets,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF8EC8),
      audioKey: 'cat_tosser',
    ),
    StickerDefinition(
      id: 'mg_cat_purrfect',
      name: 'Purrfect Aim',
      description: 'Scored 300+ in Cat Letter Toss!',
      icon: Icons.gps_fixed,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF60B0),
      audioKey: 'purrfect_aim',
    ),
    StickerDefinition(
      id: 'mg_cat_champion',
      name: 'Cat Champion',
      description: 'Scored 600+ in Cat Letter Toss!',
      icon: Icons.emoji_events,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF40A0),
      audioKey: 'cat_champion',
    ),

    // Letter Drop (drop letters into slots)
    StickerDefinition(
      id: 'mg_drop_starter',
      name: 'Letter Dropper',
      description: 'Completed your first Letter Drop game!',
      icon: Icons.arrow_downward,
      category: StickerCategory.miniGame,
      color: Color(0xFF7BD4A8),
      audioKey: 'letter_dropper',
    ),
    StickerDefinition(
      id: 'mg_drop_expert',
      name: 'Drop Expert',
      description: 'Completed all 8 words in Letter Drop!',
      icon: Icons.download_done,
      category: StickerCategory.miniGame,
      color: Color(0xFF50C490),
      audioKey: 'drop_expert',
    ),

    // Rhyme Time (tap bubbles that rhyme with target word)
    StickerDefinition(
      id: 'mg_rhyme_rookie',
      name: 'Rhyme Rookie',
      description: 'Completed your first Rhyme Time game!',
      icon: Icons.music_note,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF80C0),
      audioKey: 'rhyme_rookie',
    ),
    StickerDefinition(
      id: 'mg_rhyme_master',
      name: 'Rhyme Master',
      description: 'Scored 1000+ in Rhyme Time!',
      icon: Icons.music_note_outlined,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF50A8),
      audioKey: 'rhyme_master',
    ),
    StickerDefinition(
      id: 'mg_rhyme_poet',
      name: 'Super Poet',
      description: 'Scored 2500+ in Rhyme Time!',
      icon: Icons.library_music,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF2090),
      audioKey: 'super_poet',
    ),

    // Star Catcher (space-themed constellation game)
    StickerDefinition(
      id: 'mg_star_first_catch',
      name: 'First Catch',
      description: 'Completed your first Star Catcher game!',
      icon: Icons.star,
      category: StickerCategory.miniGame,
      color: Color(0xFF6366F1),
      audioKey: 'first_catch',
    ),
    StickerDefinition(
      id: 'mg_star_constellation',
      name: 'Constellation Maker',
      description: 'Scored 15+ in Star Catcher!',
      icon: Icons.auto_awesome,
      category: StickerCategory.miniGame,
      color: Color(0xFF818CF8),
      audioKey: 'constellation_maker',
    ),
    StickerDefinition(
      id: 'mg_star_astronaut',
      name: 'Super Astronaut',
      description: 'Scored 30+ in Star Catcher!',
      icon: Icons.rocket_launch,
      category: StickerCategory.miniGame,
      color: Color(0xFF4F46E5),
      audioKey: 'super_astronaut',
    ),

    // Paint Splash (art-themed color mixing game)
    StickerDefinition(
      id: 'mg_paint_first_splash',
      name: 'First Splash',
      description: 'Completed your first Paint Splash game!',
      icon: Icons.brush,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF6B8A),
      audioKey: 'first_splash',
    ),
    StickerDefinition(
      id: 'mg_paint_artist',
      name: 'Little Artist',
      description: 'Scored 15+ in Paint Splash!',
      icon: Icons.palette,
      category: StickerCategory.miniGame,
      color: Color(0xFFFF4D6A),
      audioKey: 'little_artist',
    ),
    StickerDefinition(
      id: 'mg_paint_masterpiece',
      name: 'Masterpiece!',
      description: 'Scored 30+ in Paint Splash!',
      icon: Icons.auto_fix_high,
      category: StickerCategory.miniGame,
      color: Color(0xFFE11D48),
      audioKey: 'masterpiece',
    ),
  ];

  // ── All stickers combined ─────────────────────────────────────────

  static List<StickerDefinition> get all => [
        ...levelStickers,
        ...milestoneStickers,
        ...streakStickers,
        ...perfectStickers,
        ...evolutionStickers,
        ...specialStickers,
        ...miniGameStickers,
      ];

  /// Look up a sticker definition by its ID.
  static StickerDefinition? byId(String id) {
    for (final sticker in all) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }

  /// Milestone word counts for easy checking.
  static const List<int> milestoneWordCounts = [1, 10, 25, 50, 100, 150, 200, 269];

  /// Returns the milestone sticker ID for a given word count, or null.
  static String? milestoneIdForWordCount(int count) {
    switch (count) {
      case 1:
        return 'milestone_1';
      case 10:
        return 'milestone_10';
      case 25:
        return 'milestone_25';
      case 50:
        return 'milestone_50';
      case 100:
        return 'milestone_100';
      case 150:
        return 'milestone_150';
      case 200:
        return 'milestone_200';
      case 269:
        return 'milestone_all';
      default:
        return null;
    }
  }

  /// Returns the streak sticker ID for a given streak count, or null.
  static String? streakIdForCount(int streak) {
    switch (streak) {
      case 3:
        return 'streak_3';
      case 7:
        return 'streak_7';
      case 14:
        return 'streak_14';
      case 30:
        return 'streak_30';
      default:
        return null;
    }
  }

  /// Returns the evolution sticker ID for a given word count threshold.
  static String? evolutionIdForWordCount(int count) {
    if (count >= 181) return 'evo_superstar';
    if (count >= 121) return 'evo_champion';
    if (count >= 61) return 'evo_wizard';
    if (count >= 21) return 'evo_explorer';
    if (count >= 0) return 'evo_sprout';
    return null;
  }

  // ── Mini-Game Score Thresholds ────────────────────────────────────

  /// Game ID to sticker threshold mapping.
  /// Each entry maps a game identifier to a list of (threshold, stickerId) pairs
  /// sorted ascending by threshold. A threshold of 0 means "completed one game".
  static const Map<String, List<_MiniGameThreshold>> _miniGameThresholds = {
    'unicorn_flight': [
      _MiniGameThreshold(0, 'mg_unicorn_first_flight'),
      _MiniGameThreshold(10, 'mg_unicorn_rider'),
      _MiniGameThreshold(25, 'mg_unicorn_sky_champion'),
    ],
    'lightning_speller': [
      _MiniGameThreshold(0, 'mg_lightning_starter'),
      _MiniGameThreshold(20, 'mg_lightning_fast'),
      _MiniGameThreshold(40, 'mg_lightning_thunder'),
    ],
    'word_bubbles': [
      _MiniGameThreshold(0, 'mg_bubbles_popper'),
      _MiniGameThreshold(15, 'mg_bubbles_master'),
    ],
    'memory_match': [
      _MiniGameThreshold(0, 'mg_memory_starter'),
      _MiniGameThreshold(5, 'mg_memory_sharp'),
      _MiniGameThreshold(0, 'mg_memory_perfect'),
    ],
    'falling_letters': [
      _MiniGameThreshold(0, 'mg_falling_catcher'),
      _MiniGameThreshold(15, 'mg_falling_pro'),
    ],
    'cat_letter_toss': [
      _MiniGameThreshold(0, 'mg_cat_tosser'),
      _MiniGameThreshold(300, 'mg_cat_purrfect'),
      _MiniGameThreshold(600, 'mg_cat_champion'),
    ],
    'letter_drop': [
      _MiniGameThreshold(0, 'mg_drop_starter'),
      _MiniGameThreshold(8, 'mg_drop_expert'),
    ],
    'rhyme_time': [
      _MiniGameThreshold(0, 'mg_rhyme_rookie'),
      _MiniGameThreshold(1000, 'mg_rhyme_master'),
      _MiniGameThreshold(2500, 'mg_rhyme_poet'),
    ],
    'star_catcher': [
      _MiniGameThreshold(0, 'mg_star_first_catch'),
      _MiniGameThreshold(15, 'mg_star_constellation'),
      _MiniGameThreshold(30, 'mg_star_astronaut'),
    ],
    'paint_splash': [
      _MiniGameThreshold(0, 'mg_paint_first_splash'),
      _MiniGameThreshold(15, 'mg_paint_artist'),
      _MiniGameThreshold(30, 'mg_paint_masterpiece'),
    ],
  };

  /// Returns a list of sticker IDs earned for the given mini-game and score.
  ///
  /// [gameId] is one of: `unicorn_flight`, `lightning_speller`, `word_bubbles`,
  /// `memory_match`, `falling_letters`, `cat_letter_toss`, `letter_drop`,
  /// `rhyme_time`.
  ///
  /// [score] is the player's score in that game session.
  ///
  /// Returns all sticker IDs whose threshold the score meets or exceeds.
  static List<String> miniGameStickersForScore(String gameId, int score) {
    final thresholds = _miniGameThresholds[gameId];
    if (thresholds == null) return [];
    return thresholds
        .where((t) => score >= t.scoreThreshold)
        .map((t) => t.stickerId)
        .toList();
  }

  /// Returns the sticker ID for a perfect memory match game (zero misses).
  /// Use this separately since perfect recall is tracked by misses, not score.
  static String? memoryMatchPerfectId(int misses) {
    if (misses == 0) return 'mg_memory_perfect';
    if (misses <= 5) return 'mg_memory_sharp';
    return null;
  }
}

/// Score threshold for a mini-game sticker.
class _MiniGameThreshold {
  final int scoreThreshold;
  final String stickerId;

  const _MiniGameThreshold(this.scoreThreshold, this.stickerId);
}

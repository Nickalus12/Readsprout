import 'package:hive/hive.dart';

part 'player_profile.g.dart';

/// The player's profile data, persisted in the 'profile' Hive box.
@HiveType(typeId: 0)
class PlayerProfile extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final AvatarConfig avatar;

  @HiveField(2)
  final int currentStreak;

  @HiveField(3)
  final int bestStreak;

  @HiveField(4)
  final DateTime? lastPlayDate;

  @HiveField(5)
  final List<String> unlockedItems;

  @HiveField(6)
  final List<String> earnedStickers;

  @HiveField(7)
  final int totalWordsEverCompleted;

  PlayerProfile({
    required this.name,
    required this.avatar,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastPlayDate,
    List<String>? unlockedItems,
    List<String>? earnedStickers,
    this.totalWordsEverCompleted = 0,
  })  : unlockedItems = unlockedItems ?? [],
        earnedStickers = earnedStickers ?? [];

  /// Determine reading level from total mastered word count.
  ReadingLevel get readingLevel =>
      ReadingLevel.forWordCount(totalWordsEverCompleted);

  PlayerProfile copyWith({
    String? name,
    AvatarConfig? avatar,
    int? currentStreak,
    int? bestStreak,
    DateTime? lastPlayDate,
    List<String>? unlockedItems,
    List<String>? earnedStickers,
    int? totalWordsEverCompleted,
  }) {
    return PlayerProfile(
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastPlayDate: lastPlayDate ?? this.lastPlayDate,
      unlockedItems: unlockedItems ?? this.unlockedItems,
      earnedStickers: earnedStickers ?? this.earnedStickers,
      totalWordsEverCompleted:
          totalWordsEverCompleted ?? this.totalWordsEverCompleted,
    );
  }
}

/// Avatar customization configuration.
///
/// Fields 0-10 are the original avatar properties (backwards compatible).
/// Fields 11-18 were added in the avatar overhaul update and default to 0
/// for existing saved profiles.
@HiveType(typeId: 1)
class AvatarConfig extends HiveObject {
  @HiveField(0)
  final int faceShape; // 0-4

  @HiveField(1)
  final int skinTone; // 0-9

  @HiveField(2)
  final int hairStyle; // 0-15

  @HiveField(3)
  final int hairColor; // 0-13

  @HiveField(4)
  final int eyeStyle; // 0-7

  @HiveField(5)
  final int mouthStyle; // 0-7

  @HiveField(6)
  final int accessory; // 0-21

  @HiveField(7)
  final int bgColor; // 0-7

  @HiveField(8)
  final bool hasSparkle; // unlockable effect

  @HiveField(9)
  final bool hasRainbowSparkle;

  @HiveField(10)
  final bool hasGoldenGlow;

  // ── New fields (avatar overhaul) ──────────────────────────────────

  @HiveField(11)
  final int eyeColor; // 0-7

  @HiveField(12)
  final int eyelashStyle; // 0-5

  @HiveField(13)
  final int eyebrowStyle; // 0-5

  @HiveField(14)
  final int lipColor; // 0-7

  @HiveField(15)
  final int cheekStyle; // 0-6

  @HiveField(16)
  final int noseStyle; // 0-4

  @HiveField(17)
  final int glassesStyle; // 0-6

  @HiveField(18)
  final int facePaint; // 0-9

  AvatarConfig({
    required this.faceShape,
    required this.skinTone,
    required this.hairStyle,
    required this.hairColor,
    required this.eyeStyle,
    required this.mouthStyle,
    required this.accessory,
    required this.bgColor,
    this.hasSparkle = false,
    this.hasRainbowSparkle = false,
    this.hasGoldenGlow = false,
    this.eyeColor = 0,
    this.eyelashStyle = 0,
    this.eyebrowStyle = 0,
    this.lipColor = 0,
    this.cheekStyle = 0,
    this.noseStyle = 0,
    this.glassesStyle = 0,
    this.facePaint = 0,
  });

  /// Default avatar for first-time users.
  factory AvatarConfig.defaultAvatar() => AvatarConfig(
        faceShape: 0,
        skinTone: 2,
        hairStyle: 0,
        hairColor: 1,
        eyeStyle: 0,
        mouthStyle: 0,
        accessory: 0,
        bgColor: 0,
      );

  AvatarConfig copyWith({
    int? faceShape,
    int? skinTone,
    int? hairStyle,
    int? hairColor,
    int? eyeStyle,
    int? mouthStyle,
    int? accessory,
    int? bgColor,
    bool? hasSparkle,
    bool? hasRainbowSparkle,
    bool? hasGoldenGlow,
    int? eyeColor,
    int? eyelashStyle,
    int? eyebrowStyle,
    int? lipColor,
    int? cheekStyle,
    int? noseStyle,
    int? glassesStyle,
    int? facePaint,
  }) {
    return AvatarConfig(
      faceShape: faceShape ?? this.faceShape,
      skinTone: skinTone ?? this.skinTone,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      eyeStyle: eyeStyle ?? this.eyeStyle,
      mouthStyle: mouthStyle ?? this.mouthStyle,
      accessory: accessory ?? this.accessory,
      bgColor: bgColor ?? this.bgColor,
      hasSparkle: hasSparkle ?? this.hasSparkle,
      hasRainbowSparkle: hasRainbowSparkle ?? this.hasRainbowSparkle,
      hasGoldenGlow: hasGoldenGlow ?? this.hasGoldenGlow,
      eyeColor: eyeColor ?? this.eyeColor,
      eyelashStyle: eyelashStyle ?? this.eyelashStyle,
      eyebrowStyle: eyebrowStyle ?? this.eyebrowStyle,
      lipColor: lipColor ?? this.lipColor,
      cheekStyle: cheekStyle ?? this.cheekStyle,
      noseStyle: noseStyle ?? this.noseStyle,
      glassesStyle: glassesStyle ?? this.glassesStyle,
      facePaint: facePaint ?? this.facePaint,
    );
  }
}

/// Record of an earned sticker.
@HiveType(typeId: 2)
class StickerRecord extends HiveObject {
  @HiveField(0)
  final String stickerId;

  @HiveField(1)
  final DateTime dateEarned;

  @HiveField(2)
  final String category; // 'milestone', 'streak', 'perfect', 'evolution', 'level'

  @HiveField(3)
  final bool isNew; // true until viewed on profile screen

  StickerRecord({
    required this.stickerId,
    required this.dateEarned,
    required this.category,
    this.isNew = true,
  });

  StickerRecord copyWith({bool? isNew}) {
    return StickerRecord(
      stickerId: stickerId,
      dateEarned: dateEarned,
      category: category,
      isNew: isNew ?? this.isNew,
    );
  }
}

/// Reading level based on total words mastered.
/// Not stored in Hive — computed at runtime.
enum ReadingLevel {
  wordSprout(0, 20, 'Word Sprout'),
  wordExplorer(21, 60, 'Word Explorer'),
  wordWizard(61, 120, 'Word Wizard'),
  wordChampion(121, 180, 'Word Champion'),
  readingSuperstar(181, 269, 'Reading Superstar');

  final int minWords;
  final int maxWords;
  final String title;

  const ReadingLevel(this.minWords, this.maxWords, this.title);

  /// Determine the reading level for a given total word count.
  static ReadingLevel forWordCount(int count) {
    for (final level in values.reversed) {
      if (count >= level.minWords) return level;
    }
    return wordSprout;
  }

  /// Progress toward the next level as a 0.0-1.0 fraction.
  double progressToNext(int count) {
    if (this == readingSuperstar) return 1.0;
    final range = maxWords - minWords + 1;
    return ((count - minWords) / range).clamp(0.0, 1.0);
  }

  /// The next reading level, or null if already at max.
  ReadingLevel? get next {
    final idx = index + 1;
    return idx < values.length ? values[idx] : null;
  }
}

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Metadata for all avatar customization options: labels, colors, and unlock conditions.
///
/// The avatar overhaul supports 16 customization categories with hundreds of
/// billions of unique combinations. All options are indexed by int for Hive
/// storage compatibility.

// ── Face Shapes ───────────────────────────────────────────────────────

class FaceShapeOption {
  final int index;
  final String label;
  final double borderRadius; // fraction of size (0.0 = square, 0.5 = circle)
  final double heightRatio; // face height relative to face width

  const FaceShapeOption(this.index, this.label, this.borderRadius,
      [this.heightRatio = 1.0]);
}

const List<FaceShapeOption> faceShapeOptions = [
  FaceShapeOption(0, 'Round', 0.50, 0.88),
  FaceShapeOption(1, 'Square', 0.28, 0.88),
  FaceShapeOption(2, 'Oval', 0.45, 1.0),
  FaceShapeOption(3, 'Heart', 0.42, 0.92),
  FaceShapeOption(4, 'Diamond', 0.38, 0.95),
];

// ── Skin Tones ────────────────────────────────────────────────────────

class SkinToneOption {
  final int index;
  final String label;
  final Color color;

  const SkinToneOption(this.index, this.label, this.color);
}

const List<SkinToneOption> skinToneOptions = [
  SkinToneOption(0, 'Porcelain', Color(0xFFFFF0E0)),
  SkinToneOption(1, 'Fair', Color(0xFFF5DEC4)),
  SkinToneOption(2, 'Light', Color(0xFFF5D6B8)),
  SkinToneOption(3, 'Peach', Color(0xFFE8BC98)),
  SkinToneOption(4, 'Medium', Color(0xFFD4A57B)),
  SkinToneOption(5, 'Warm', Color(0xFFCB9A6B)),
  SkinToneOption(6, 'Tan', Color(0xFFC08C5A)),
  SkinToneOption(7, 'Brown', Color(0xFFA0714B)),
  SkinToneOption(8, 'Dark', Color(0xFF8D5524)),
  SkinToneOption(9, 'Deep', Color(0xFF5C3310)),
];

/// Quick lookup from index to skin color.
Color skinColorForIndex(int index) {
  return skinToneOptions[index.clamp(0, skinToneOptions.length - 1)].color;
}

/// Anchor points for the continuous skin tone gradient.
const List<_SkinAnchor> _skinAnchors = [
  _SkinAnchor(0.0, Color(0xFFFFE8D0)),
  _SkinAnchor(0.2, Color(0xFFF5D0A9)),
  _SkinAnchor(0.4, Color(0xFFD4A574)),
  _SkinAnchor(0.6, Color(0xFFB07D50)),
  _SkinAnchor(0.8, Color(0xFF8B5E3C)),
  _SkinAnchor(1.0, Color(0xFF5C3A21)),
];

class _SkinAnchor {
  final double position;
  final Color color;
  const _SkinAnchor(this.position, this.color);
}

/// Convert a continuous slider value (0.0-1.0) to a skin color.
/// Interpolates through realistic skin tone anchor points using HSL blending.
Color skinColorFromSlider(double value) {
  final v = value.clamp(0.0, 1.0);
  // Find the two anchors that bracket this value.
  for (int i = 0; i < _skinAnchors.length - 1; i++) {
    final a = _skinAnchors[i];
    final b = _skinAnchors[i + 1];
    if (v >= a.position && v <= b.position) {
      final t = (v - a.position) / (b.position - a.position);
      // Interpolate in HSL for perceptually smoother transitions.
      final hslA = HSLColor.fromColor(a.color);
      final hslB = HSLColor.fromColor(b.color);
      return HSLColor.lerp(hslA, hslB, t)!.toColor();
    }
  }
  return _skinAnchors.last.color;
}

/// The full skin tone gradient as a list of colors for painting slider tracks.
List<Color> get skinToneGradientColors =>
    _skinAnchors.map((a) => a.color).toList();

/// The stops matching each anchor point.
List<double> get skinToneGradientStops =>
    _skinAnchors.map((a) => a.position).toList();

// ── Hair Styles ───────────────────────────────────────────────────────

class HairStyleOption {
  final int index;
  final String label;

  const HairStyleOption(this.index, this.label);
}

const List<HairStyleOption> hairStyleOptions = [
  HairStyleOption(0, 'Short'),
  HairStyleOption(1, 'Long'),
  HairStyleOption(2, 'Curly'),
  HairStyleOption(3, 'Braids'),
  HairStyleOption(4, 'Ponytail'),
  HairStyleOption(5, 'Buzz'),
  HairStyleOption(6, 'Afro'),
  HairStyleOption(7, 'Bun'),
  HairStyleOption(8, 'Pigtails'),
  HairStyleOption(9, 'Bob'),
  HairStyleOption(10, 'Wavy'),
  HairStyleOption(11, 'Side Swept'),
  HairStyleOption(12, 'Mohawk'),
  HairStyleOption(13, 'Space Buns'),
  HairStyleOption(14, 'Long Wavy'),
  HairStyleOption(15, 'Fishtail'),
];

// ── Hair Colors ───────────────────────────────────────────────────────

class HairColorOption {
  final int index;
  final String label;
  final Color color;
  final UnlockRequirement? unlock;

  const HairColorOption(this.index, this.label, this.color, [this.unlock]);

  bool get isLocked => unlock != null;
  String get unlockId => 'hair_color_$index';
}

final List<HairColorOption> hairColorOptions = [
  const HairColorOption(0, 'Black', Color(0xFF1A1A2E)),
  const HairColorOption(1, 'Brown', Color(0xFF6B4226)),
  const HairColorOption(2, 'Blonde', Color(0xFFE8C872)),
  const HairColorOption(3, 'Red', Color(0xFFB5332E)),
  const HairColorOption(4, 'Auburn', Color(0xFF8B4513)),
  const HairColorOption(5, 'Strawberry', Color(0xFFE0926A)),
  const HairColorOption(6, 'Orange', Color(0xFFE87430)),
  const HairColorOption(7, 'White', Color(0xFFE8E8E8)),
  const HairColorOption(8, 'Silver', Color(0xFFC0C0C8)),
  const HairColorOption(
    9,
    'Blue',
    Color(0xFF4A90D9),
    UnlockRequirement(
        type: UnlockType.wordsMastered, threshold: 25, hint: '25 words!'),
  ),
  const HairColorOption(
    10,
    'Purple',
    Color(0xFF9B59B6),
    UnlockRequirement(
        type: UnlockType.wordsMastered, threshold: 50, hint: '50 words!'),
  ),
  const HairColorOption(
    11,
    'Pink',
    Color(0xFFFF7EB3),
    UnlockRequirement(
        type: UnlockType.wordsMastered, threshold: 75, hint: '75 words!'),
  ),
  const HairColorOption(
    12,
    'Green',
    Color(0xFF4CBB8A),
    UnlockRequirement(
        type: UnlockType.wordsMastered, threshold: 100, hint: '100 words!'),
  ),
  const HairColorOption(
    13,
    'Rainbow',
    Color(0xFFFF6B8A), // preview color; rendered as gradient
    UnlockRequirement(
        type: UnlockType.wordsMastered, threshold: 150, hint: '150 words!'),
  ),
];

/// Whether the hair color is the special rainbow gradient.
bool isRainbowHair(int index) => index == 13;

// ── Eye Styles ────────────────────────────────────────────────────────

class EyeStyleOption {
  final int index;
  final String label;

  const EyeStyleOption(this.index, this.label);
}

const List<EyeStyleOption> eyeStyleOptions = [
  EyeStyleOption(0, 'Round'),
  EyeStyleOption(1, 'Star'),
  EyeStyleOption(2, 'Hearts'),
  EyeStyleOption(3, 'Happy'),
  EyeStyleOption(4, 'Sparkle'),
  EyeStyleOption(5, 'Almond'),
  EyeStyleOption(6, 'Wink'),
  EyeStyleOption(7, 'Sleepy'),
];

// ── Eye Colors ────────────────────────────────────────────────────────

class EyeColorOption {
  final int index;
  final String label;
  final Color color;

  const EyeColorOption(this.index, this.label, this.color);
}

const List<EyeColorOption> eyeColorOptions = [
  EyeColorOption(0, 'Brown', Color(0xFF6B4226)),
  EyeColorOption(1, 'Blue', Color(0xFF4A90D9)),
  EyeColorOption(2, 'Green', Color(0xFF3B9B6E)),
  EyeColorOption(3, 'Hazel', Color(0xFF9B7B3C)),
  EyeColorOption(4, 'Amber', Color(0xFFD4A040)),
  EyeColorOption(5, 'Violet', Color(0xFF8B5CF6)),
  EyeColorOption(6, 'Teal', Color(0xFF2BA8A0)),
  EyeColorOption(7, 'Pink', Color(0xFFE06090)),
];

// ── Eyelash Styles ────────────────────────────────────────────────────

class EyelashStyleOption {
  final int index;
  final String label;

  const EyelashStyleOption(this.index, this.label);
}

const List<EyelashStyleOption> eyelashStyleOptions = [
  EyelashStyleOption(0, 'None'),
  EyelashStyleOption(1, 'Natural'),
  EyelashStyleOption(2, 'Long'),
  EyelashStyleOption(3, 'Dramatic'),
  EyelashStyleOption(4, 'Flutter'),
  EyelashStyleOption(5, 'Sparkle'),
];

// ── Eyebrow Styles ────────────────────────────────────────────────────

class EyebrowStyleOption {
  final int index;
  final String label;

  const EyebrowStyleOption(this.index, this.label);
}

const List<EyebrowStyleOption> eyebrowStyleOptions = [
  EyebrowStyleOption(0, 'Natural'),
  EyebrowStyleOption(1, 'Thin'),
  EyebrowStyleOption(2, 'Thick'),
  EyebrowStyleOption(3, 'Arched'),
  EyebrowStyleOption(4, 'Straight'),
  EyebrowStyleOption(5, 'Bushy'),
];

// ── Mouth Styles ──────────────────────────────────────────────────────

class MouthStyleOption {
  final int index;
  final String label;

  const MouthStyleOption(this.index, this.label);
}

const List<MouthStyleOption> mouthStyleOptions = [
  MouthStyleOption(0, 'Smile'),
  MouthStyleOption(1, 'Big Grin'),
  MouthStyleOption(2, 'Tongue Out'),
  MouthStyleOption(3, 'Surprised'),
  MouthStyleOption(4, 'Kissy'),
  MouthStyleOption(5, 'Cat Smile'),
  MouthStyleOption(6, 'Smirk'),
  MouthStyleOption(7, 'Tiny Smile'),
];

// ── Lip Colors ────────────────────────────────────────────────────────

class LipColorOption {
  final int index;
  final String label;
  final Color color;

  const LipColorOption(this.index, this.label, this.color);
}

const List<LipColorOption> lipColorOptions = [
  LipColorOption(0, 'Natural', Color(0x00000000)), // transparent = use default
  LipColorOption(1, 'Pink', Color(0xFFFF9EC0)),
  LipColorOption(2, 'Rose', Color(0xFFE06080)),
  LipColorOption(3, 'Red', Color(0xFFE03040)),
  LipColorOption(4, 'Berry', Color(0xFFA0306B)),
  LipColorOption(5, 'Coral', Color(0xFFFF7070)),
  LipColorOption(6, 'Peach', Color(0xFFFFB090)),
  LipColorOption(7, 'Plum', Color(0xFF8B3070)),
];

// ── Cheek Styles ──────────────────────────────────────────────────────

class CheekStyleOption {
  final int index;
  final String label;

  const CheekStyleOption(this.index, this.label);
}

const List<CheekStyleOption> cheekStyleOptions = [
  CheekStyleOption(0, 'None'),
  CheekStyleOption(1, 'Rosy'),
  CheekStyleOption(2, 'Freckles'),
  CheekStyleOption(3, 'Blush'),
  CheekStyleOption(4, 'Sparkle'),
  CheekStyleOption(5, 'Hearts'),
  CheekStyleOption(6, 'Stars'),
];

// ── Nose Styles ───────────────────────────────────────────────────────

class NoseStyleOption {
  final int index;
  final String label;

  const NoseStyleOption(this.index, this.label);
}

const List<NoseStyleOption> noseStyleOptions = [
  NoseStyleOption(0, 'Button'),
  NoseStyleOption(1, 'Small'),
  NoseStyleOption(2, 'Round'),
  NoseStyleOption(3, 'Pointed'),
  NoseStyleOption(4, 'Snub'),
];

// ── Glasses ───────────────────────────────────────────────────────────

class GlassesStyleOption {
  final int index;
  final String label;

  const GlassesStyleOption(this.index, this.label);
}

const List<GlassesStyleOption> glassesStyleOptions = [
  GlassesStyleOption(0, 'None'),
  GlassesStyleOption(1, 'Round'),
  GlassesStyleOption(2, 'Square'),
  GlassesStyleOption(3, 'Cat Eye'),
  GlassesStyleOption(4, 'Star'),
  GlassesStyleOption(5, 'Heart'),
  GlassesStyleOption(6, 'Aviator'),
];

// ── Face Paint / Stickers ─────────────────────────────────────────────

class FacePaintOption {
  final int index;
  final String label;

  const FacePaintOption(this.index, this.label);
}

const List<FacePaintOption> facePaintOptions = [
  FacePaintOption(0, 'None'),
  FacePaintOption(1, 'Star'),
  FacePaintOption(2, 'Butterfly'),
  FacePaintOption(3, 'Heart'),
  FacePaintOption(4, 'Rainbow'),
  FacePaintOption(5, 'Whiskers'),
  FacePaintOption(6, 'Tiger'),
  FacePaintOption(7, 'Flower'),
  FacePaintOption(8, 'Lightning'),
  FacePaintOption(9, 'Dots'),
];

// ── Shirt Colors ─────────────────────────────────────────────────────

class ShirtColorOption {
  final int index;
  final String label;
  final Color color;

  const ShirtColorOption(this.index, this.label, this.color);
}

const List<ShirtColorOption> shirtColorOptions = [
  ShirtColorOption(0, 'Red', Color(0xFFE53E3E)),
  ShirtColorOption(1, 'Blue', Color(0xFF3B82F6)),
  ShirtColorOption(2, 'Green', Color(0xFF38A169)),
  ShirtColorOption(3, 'Purple', Color(0xFF805AD5)),
  ShirtColorOption(4, 'Orange', Color(0xFFED8936)),
  ShirtColorOption(5, 'Pink', Color(0xFFED64A6)),
  ShirtColorOption(6, 'Yellow', Color(0xFFECC94B)),
  ShirtColorOption(7, 'White', Color(0xFFF7FAFC)),
];

// ── Shirt Styles ─────────────────────────────────────────────────────

class ShirtStyleOption {
  final int index;
  final String label;

  const ShirtStyleOption(this.index, this.label);
}

const List<ShirtStyleOption> shirtStyleOptions = [
  ShirtStyleOption(0, 'Crew Neck'),
  ShirtStyleOption(1, 'V-Neck'),
  ShirtStyleOption(2, 'Collared'),
];

// ── Accessories ───────────────────────────────────────────────────────

class AccessoryOption {
  final int index;
  final String label;
  final UnlockRequirement? unlock;

  const AccessoryOption(this.index, this.label, [this.unlock]);

  bool get isLocked => unlock != null;
  String get unlockId => 'accessory_$index';
}

const List<AccessoryOption> accessoryOptions = [
  // Free accessories (0-5)
  AccessoryOption(0, 'None'),
  AccessoryOption(1, 'Glasses'), // legacy — kept for backwards compat
  AccessoryOption(2, 'Crown'),
  AccessoryOption(3, 'Flower'),
  AccessoryOption(4, 'Bow'),
  AccessoryOption(5, 'Cap'),
  // Evolution unlocks (6-8)
  AccessoryOption(
    6,
    'Wizard Hat',
    UnlockRequirement(
        type: UnlockType.evolutionStage, threshold: 3, hint: 'Word Wizard!'),
  ),
  AccessoryOption(
    7,
    'Wings',
    UnlockRequirement(
        type: UnlockType.evolutionStage,
        threshold: 4,
        hint: 'Word Champion!'),
  ),
  AccessoryOption(
    8,
    'Royal Crown',
    UnlockRequirement(
        type: UnlockType.evolutionStage,
        threshold: 5,
        hint: 'Reading Superstar!'),
  ),
  // Treasure chest unlocks (9-13)
  AccessoryOption(
    9,
    'Tiara',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    10,
    'Bunny Ears',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    11,
    'Cat Ears',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    12,
    'Unicorn Horn',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    13,
    'Star Band',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  // New accessories (14-21)
  AccessoryOption(14, 'Halo'),
  AccessoryOption(15, 'Headband'),
  AccessoryOption(16, 'Flower Crown'),
  AccessoryOption(
    17,
    'Devil Horns',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    18,
    'Pirate Hat',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    19,
    'Antennae',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    20,
    'Propeller',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
  AccessoryOption(
    21,
    'Ninja Mask',
    UnlockRequirement(
        type: UnlockType.treasureChest, threshold: 0, hint: 'Treasure!'),
  ),
];

// ── Background Colors ─────────────────────────────────────────────────

class BgColorOption {
  final int index;
  final String label;
  final Color color;

  const BgColorOption(this.index, this.label, this.color);
}

final List<BgColorOption> bgColorOptions = [
  BgColorOption(0, 'Peach', AppColors.avatarBgColors[0]),
  BgColorOption(1, 'Mint', AppColors.avatarBgColors[1]),
  BgColorOption(2, 'Sky', AppColors.avatarBgColors[2]),
  BgColorOption(3, 'Lavender', AppColors.avatarBgColors[3]),
  BgColorOption(4, 'Honey', AppColors.avatarBgColors[4]),
  BgColorOption(5, 'Coral', AppColors.avatarBgColors[5]),
  BgColorOption(6, 'Aqua', AppColors.avatarBgColors[6]),
  BgColorOption(7, 'Mauve', AppColors.avatarBgColors[7]),
];

// ── Unlock System ─────────────────────────────────────────────────────

enum UnlockType {
  wordsMastered,
  evolutionStage,
  streakDays,
  treasureChest,
}

class UnlockRequirement {
  final UnlockType type;
  final int threshold;
  final String hint;

  const UnlockRequirement({
    required this.type,
    required this.threshold,
    required this.hint,
  });
}

/// Check whether a lockable item is unlocked given the player's progress.
/// For treasure items, check `unlockedItems` on the profile instead.
bool isUnlocked({
  required UnlockRequirement? requirement,
  required int wordsMastered,
  required int evolutionStage,
  required int streakDays,
  List<String> unlockedItems = const [],
}) {
  if (requirement == null) return true;
  switch (requirement.type) {
    case UnlockType.wordsMastered:
      return wordsMastered >= requirement.threshold;
    case UnlockType.evolutionStage:
      return evolutionStage >= requirement.threshold;
    case UnlockType.streakDays:
      return streakDays >= requirement.threshold;
    case UnlockType.treasureChest:
      // Treasure items are unlocked when their ID appears in the profile's unlockedItems
      return false; // Caller must check unlockedItems list directly
  }
}

// ── Treasure Reward Definitions ──────────────────────────────────────

/// Categories of visual rewards from the treasure chest.
enum TreasureCategory {
  accessory,
  bgColor,
  effect,
  sticker,
  facePaint,
  glasses,
}

/// Rarity tiers for treasure rewards.
/// Wooden chests give common only, silver adds uncommon, golden adds rare.
enum RewardRarity {
  common,
  uncommon,
  rare,
}

/// A single treasure reward the child can win.
class TreasureReward {
  final String id;
  final TreasureCategory category;
  final RewardRarity rarity;

  /// The icon shown when the reward is revealed.
  final IconData icon;

  /// Color used for the icon and glow.
  final Color color;

  /// For accessories: the accessory index in [accessoryOptions].
  final int? accessoryIndex;

  /// For bg colors: the bg color index in [bgColorOptions].
  final int? bgColorIndex;

  /// For effects: which boolean flag on AvatarConfig to enable.
  final String? effectFlag;

  /// For face paints: the face paint index on AvatarConfig.
  final int? facePaintIndex;

  /// For glasses: the glasses style index on AvatarConfig.
  final int? glassesIndex;

  const TreasureReward({
    required this.id,
    required this.category,
    required this.icon,
    required this.color,
    this.rarity = RewardRarity.common,
    this.accessoryIndex,
    this.bgColorIndex,
    this.effectFlag,
    this.facePaintIndex,
    this.glassesIndex,
  });
}

/// All possible treasure chest rewards.
/// The system picks a random un-owned reward filtered by chest tier rarity.
final List<TreasureReward> allTreasureRewards = [
  // ── Accessories 9-13 (common) ──
  const TreasureReward(
    id: 'accessory_9',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.common,
    icon: Icons.auto_awesome,
    color: Color(0xFFFFB6C1),
    accessoryIndex: 9,
  ),
  const TreasureReward(
    id: 'accessory_10',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.common,
    icon: Icons.cruelty_free,
    color: Color(0xFFF5F5F5),
    accessoryIndex: 10,
  ),
  const TreasureReward(
    id: 'accessory_11',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.common,
    icon: Icons.pets,
    color: Color(0xFFB794F6),
    accessoryIndex: 11,
  ),
  const TreasureReward(
    id: 'accessory_12',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.common,
    icon: Icons.diamond,
    color: Color(0xFFE0C3FC),
    accessoryIndex: 12,
  ),
  const TreasureReward(
    id: 'accessory_13',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.common,
    icon: Icons.star,
    color: AppColors.starGold,
    accessoryIndex: 13,
  ),

  // ── Accessories 17-21 (uncommon) ──
  const TreasureReward(
    id: 'accessory_17',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.uncommon,
    icon: Icons.whatshot,
    color: Color(0xFFFF4444),
    accessoryIndex: 17,
  ),
  const TreasureReward(
    id: 'accessory_18',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.uncommon,
    icon: Icons.sailing,
    color: Color(0xFF4A4A4A),
    accessoryIndex: 18,
  ),
  const TreasureReward(
    id: 'accessory_19',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.uncommon,
    icon: Icons.sensors,
    color: Color(0xFF00E68A),
    accessoryIndex: 19,
  ),
  const TreasureReward(
    id: 'accessory_20',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.uncommon,
    icon: Icons.toys,
    color: Color(0xFF4A90D9),
    accessoryIndex: 20,
  ),
  const TreasureReward(
    id: 'accessory_21',
    category: TreasureCategory.accessory,
    rarity: RewardRarity.uncommon,
    icon: Icons.visibility_off,
    color: Color(0xFF1A1A2E),
    accessoryIndex: 21,
  ),

  // ── Background Colors (uncommon) ──
  const TreasureReward(
    id: 'treasure_bg_rainbow',
    category: TreasureCategory.bgColor,
    rarity: RewardRarity.uncommon,
    icon: Icons.palette,
    color: Color(0xFFFF6B8A),
    bgColorIndex: 8,
  ),
  const TreasureReward(
    id: 'treasure_bg_galaxy',
    category: TreasureCategory.bgColor,
    rarity: RewardRarity.uncommon,
    icon: Icons.nightlight_round,
    color: Color(0xFF6366F1),
    bgColorIndex: 9,
  ),

  // ── Effects (rare) ──
  const TreasureReward(
    id: 'effect_sparkle',
    category: TreasureCategory.effect,
    rarity: RewardRarity.rare,
    icon: Icons.auto_awesome,
    color: AppColors.starGold,
    effectFlag: 'hasSparkle',
  ),
  const TreasureReward(
    id: 'effect_rainbow_sparkle',
    category: TreasureCategory.effect,
    rarity: RewardRarity.rare,
    icon: Icons.looks,
    color: Color(0xFFFF6B8A),
    effectFlag: 'hasRainbowSparkle',
  ),
  const TreasureReward(
    id: 'effect_golden_glow',
    category: TreasureCategory.effect,
    rarity: RewardRarity.rare,
    icon: Icons.wb_sunny,
    color: AppColors.starGold,
    effectFlag: 'hasGoldenGlow',
  ),

  // ── Face Paints (common) ──
  const TreasureReward(
    id: 'face_paint_1',
    category: TreasureCategory.facePaint,
    rarity: RewardRarity.common,
    icon: Icons.brush_rounded,
    color: Color(0xFFFF6B8A),
    facePaintIndex: 1,
  ),
  const TreasureReward(
    id: 'face_paint_2',
    category: TreasureCategory.facePaint,
    rarity: RewardRarity.common,
    icon: Icons.brush_rounded,
    color: Color(0xFF6BB8F0),
    facePaintIndex: 2,
  ),
  const TreasureReward(
    id: 'face_paint_3',
    category: TreasureCategory.facePaint,
    rarity: RewardRarity.common,
    icon: Icons.brush_rounded,
    color: Color(0xFF00E68A),
    facePaintIndex: 3,
  ),
  const TreasureReward(
    id: 'face_paint_4',
    category: TreasureCategory.facePaint,
    rarity: RewardRarity.common,
    icon: Icons.brush_rounded,
    color: Color(0xFFB794F6),
    facePaintIndex: 4,
  ),
  const TreasureReward(
    id: 'face_paint_5',
    category: TreasureCategory.facePaint,
    rarity: RewardRarity.common,
    icon: Icons.brush_rounded,
    color: Color(0xFFFFB347),
    facePaintIndex: 5,
  ),

  // ── Glasses Styles (uncommon) ──
  const TreasureReward(
    id: 'glasses_1',
    category: TreasureCategory.glasses,
    rarity: RewardRarity.uncommon,
    icon: Icons.visibility_rounded,
    color: Color(0xFF4A90D9),
    glassesIndex: 1,
  ),
  const TreasureReward(
    id: 'glasses_2',
    category: TreasureCategory.glasses,
    rarity: RewardRarity.uncommon,
    icon: Icons.visibility_rounded,
    color: Color(0xFFFF4444),
    glassesIndex: 2,
  ),
  const TreasureReward(
    id: 'glasses_3',
    category: TreasureCategory.glasses,
    rarity: RewardRarity.uncommon,
    icon: Icons.visibility_rounded,
    color: Color(0xFF00E68A),
    glassesIndex: 3,
  ),
  const TreasureReward(
    id: 'glasses_4',
    category: TreasureCategory.glasses,
    rarity: RewardRarity.uncommon,
    icon: Icons.visibility_rounded,
    color: Color(0xFFE0C3FC),
    glassesIndex: 4,
  ),

  // ── Sticker Awards (common) ──
  const TreasureReward(
    id: 'sticker_treasure_star',
    category: TreasureCategory.sticker,
    rarity: RewardRarity.common,
    icon: Icons.star_rounded,
    color: AppColors.starGold,
  ),
  const TreasureReward(
    id: 'sticker_treasure_heart',
    category: TreasureCategory.sticker,
    rarity: RewardRarity.common,
    icon: Icons.favorite_rounded,
    color: Color(0xFFFF4D6A),
  ),
  const TreasureReward(
    id: 'sticker_treasure_diamond',
    category: TreasureCategory.sticker,
    rarity: RewardRarity.common,
    icon: Icons.diamond_rounded,
    color: AppColors.electricBlue,
  ),
  const TreasureReward(
    id: 'sticker_treasure_flower',
    category: TreasureCategory.sticker,
    rarity: RewardRarity.common,
    icon: Icons.local_florist_rounded,
    color: Color(0xFFFF7EB3),
  ),
  const TreasureReward(
    id: 'sticker_treasure_rainbow',
    category: TreasureCategory.sticker,
    rarity: RewardRarity.common,
    icon: Icons.looks_rounded,
    color: Color(0xFF00E68A),
  ),
];

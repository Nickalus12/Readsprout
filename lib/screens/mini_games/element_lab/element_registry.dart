import 'dart:typed_data';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Element Registry — Element type constants, colors, names, and metadata
// ---------------------------------------------------------------------------

/// Element types stored in the grid as byte values.
class El {
  static const int empty = 0;
  static const int sand = 1;
  static const int water = 2;
  static const int fire = 3;
  static const int ice = 4;
  static const int lightning = 5;
  static const int seed = 6; // was "plant" — now falls like sand, sprouts into plant
  static const int stone = 7;
  static const int tnt = 8;
  static const int rainbow = 9;
  static const int mud = 10;
  static const int steam = 11;
  static const int ant = 12;
  static const int oil = 13;
  static const int acid = 14;
  static const int glass = 15;
  static const int dirt = 16;
  static const int plant = 17; // sprouted plant — static, grows upward
  static const int lava = 18;
  static const int snow = 19;
  static const int wood = 20;
  static const int metal = 21;
  static const int smoke = 22;
  static const int bubble = 23;
  static const int ash = 24;
  static const int eraser = 99; // UI-only, never stored in grid
  static const int count = 25; // number of real element types
}

/// Per-element base colors (index = element type).
///
/// The renderer uses custom color logic for several elements instead of these
/// base values:
///   - fire (3): animated orange→yellow→red gradient based on life
///   - rainbow (9): HSL hue cycling per frame
///   - ant (12): tinted by behavioral state (explorer/digger/carrier/etc.)
///   - plant (17): green tint varies by growth stage and seed type
///   - lava (18): animated glow with brightness oscillation
///   - steam (11), smoke (22), bubble (23): alpha fading based on life
///
/// All other elements use their base color directly, with optional per-pixel
/// noise for visual variety (sand, dirt, stone, etc.).
const List<Color> baseColors = [
  Color(0x00000000), // 0  empty (transparent)
  Color(0xFFDEB887), // 1  sand — tan
  Color(0xFF3399FF), // 2  water — blue
  Color(0xFFFF6600), // 3  fire — orange
  Color(0xFFAADDFF), // 4  ice — light blue
  Color(0xFFFFFF66), // 5  lightning — yellow
  Color(0xFF8B7355), // 6  seed — woody brown
  Color(0xFF888888), // 7  stone — gray
  Color(0xFFCC2222), // 8  TNT — red
  Color(0xFFFF00FF), // 9  rainbow — magenta (cycles)
  Color(0xFF6B4226), // 10 mud — dark brown
  Color(0xFFDDDDDD), // 11 steam — white
  Color(0xFF222222), // 12 ant — dark
  Color(0xFF4A3728), // 13 oil — dark brown
  Color(0xFF33FF33), // 14 acid — neon green
  Color(0xFFDDEEFF), // 15 glass — transparent white
  Color(0xFF8B6914), // 16 dirt — earthy brown
  Color(0xFF33CC33), // 17 plant — green
  Color(0xFFFF4500), // 18 lava — orange-red
  Color(0xFFF0F0FF), // 19 snow — white
  Color(0xFFA0522D), // 20 wood — warm brown
  Color(0xFFA8A8B0), // 21 metal — silver-gray
  Color(0xFF808080), // 22 smoke — gray
  Color(0xFFADD8E6), // 23 bubble — light blue
  Color(0xFFB0B0B0), // 24 ash — light grey
];

/// Element display names for the palette.
const List<String> elementNames = [
  '', 'Sand', 'Water', 'Fire', 'Ice', 'Zap',
  'Seed', 'Stone', 'TNT', 'Rainbow', 'Mud', 'Steam', 'Ant',
  'Oil', 'Acid', 'Glass', 'Dirt', 'Plant', 'Lava', 'Snow',
  'Wood', 'Metal', 'Smoke', 'Bubble', 'Ash',
];

/// Element descriptions for long-press info.
const Map<int, String> elementDescriptions = {
  El.sand: 'Falls down and piles up.\nMixes with water to make mud.\nSinks through water.',
  El.water: 'Flows and fills containers.\nFreezes near ice.\nPuts out fire (makes steam).',
  El.fire: 'Rises up and burns out.\nSpreads to plants and oil.\nMelts ice into water.',
  El.ice: 'Solid and cold.\nFreezes nearby water.\nMelts from fire.',
  El.lightning: 'Zaps down fast!\nExplodes TNT.\nElectrifies water.',
  El.seed: 'Pick a seed type and plant in moist dirt!\n5 types: Grass, Flower, Tree, Mushroom, Vine.\nNeeds moist soil to grow!',
  El.stone: 'Solid and immovable.\nNothing can destroy it.\nAcid dissolves it slowly.',
  El.tnt: 'Falls like sand.\nExplodes when hit by fire or lightning!\nMore TNT = bigger boom!',
  El.rainbow: 'Floats upward with sparkles.\nChanges colors!',
  El.mud: 'Thick and slow.\nMade from dirt + lots of water.',
  El.steam: 'Rises up fast.\nCondenses back to water at the top.',
  El.ant: 'Smart colony builders!\nLeave scent trails to find food.\nDrowns in water.\nRuns from fire.\nDissolved by acid.',
  El.oil: 'Floats on water.\nVery flammable!\nBurns longer than plant.',
  El.acid: 'Dissolves stone slowly.\nKills ants.\nMixes with water.\nDangerous!',
  El.glass: 'Made when lightning hits sand.\nSolid like stone but see-through.',
  El.dirt: 'Falls and piles up.\nAbsorbs water.\nToo much water turns it to mud!',
  El.plant: 'Grows upward from seeds.\nBurns when touched by fire.\nDissolved by acid.',
  El.lava: 'Hot liquid rock!\nTurns water to stone and steam.\nCools into stone over time.',
  El.snow: 'Falls softly and piles up.\nMelts near fire or lava.\nFreezes nearby water!',
  El.wood: 'Solid and sturdy.\nBurns when touched by fire.\nAcid dissolves it slowly.',
  El.metal: 'Super strong metal!\nConducts lightning to all connected metal.\nImmune to fire and acid.',
  El.smoke: 'Rises and fades away.\nMade when things burn.\nDrifts in the wind.',
  El.bubble: 'Rises through water.\nPops into droplets at the surface!\nAcid in water makes bubbles.',
  El.ash: 'Very light — drifts in the wind.\nFloats on water, then sinks.\nFertilizes dirt!',
};

/// Element palette tab definitions.
const List<List<int>> tabElements = [
  [El.sand, El.dirt, El.stone, El.ice, El.glass, El.snow, El.wood, El.metal, El.ash], // Solids
  [El.water, El.oil, El.acid, El.mud, El.lava, El.bubble],  // Liquids
  [El.fire, El.lightning, El.tnt, El.steam, El.smoke],       // Energy
  [El.seed, El.ant],                                            // Life
  [El.rainbow, El.eraser],                                    // Tools
];

/// Tab icons for the palette.
const List<IconData> tabIcons = [
  Icons.landscape_rounded,
  Icons.water_drop_rounded,
  Icons.bolt_rounded,
  Icons.eco_rounded,
  Icons.auto_fix_high_rounded,
];

/// Lightweight elements affected fully by wind.
const Set<int> lightWindElements = {
  El.sand, El.snow, El.smoke, El.fire, El.steam, El.bubble, El.seed, El.ash,
};

/// Heavy liquids affected partially by wind.
const Set<int> heavyWindElements = {
  El.water, El.oil, El.acid,
};

/// Static elements unaffected by wind or shake.
const Set<int> staticElements = {
  El.stone, El.metal, El.wood, El.glass, El.ice,
};

// Wind sensitivity per element: 0 = unaffected, 1 = heavy, 2 = light, 3 = ash
// Pre-computed lookup for O(1) access instead of Set.contains
final Uint8List windSensitivity = () {
  final t = Uint8List(32); // enough for all element IDs
  for (final el in lightWindElements) { t[el] = 2; }
  for (final el in heavyWindElements) { t[el] = 1; }
  t[El.ash] = 3;
  return t;
}();

/// Element names that have dedicated word audio files.
/// Others will be spelled letter-by-letter.
/// Element names that have dedicated word audio files in assets/audio/words/.
/// Others will be spelled letter-by-letter until TTS audio is generated.
const Set<String> speakableWords = {
  'sand', 'water', 'fire', 'ice', 'plant', 'stone',
  'mud', 'steam', 'ant', 'oil', 'acid', 'glass', 'rainbow',
  'snow', 'lightning', 'tnt',
  // Missing audio (spelled letter-by-letter for now):
  // seed, dirt, lava, wood, metal, smoke, bubble, ash
};

// ── Plant data constants ─────────────────────────────────────────────
const int kPlantGrass = 1, kPlantFlower = 2, kPlantTree = 3;
const int kPlantMushroom = 4, kPlantVine = 5;
const int kStSprout = 0, kStGrowing = 1, kStMature = 2;
const int kStWilting = 3, kStDead = 4;
const List<int> plantMaxH = [0, 3, 6, 15, 3, 12];
const List<int> plantMinMoist = [0, 1, 2, 3, 4, 2];
const List<int> plantGrowRate = [0, 25, 35, 20, 40, 30];

// ── Element category bitmasks (for AI sensing API) ──────────────────
/// Category flags for O(1) element classification in sensing queries.
class ElCat {
  static const int solid      = 0x01; // stone, glass, metal, ice, wood
  static const int liquid     = 0x02; // water, oil, acid, lava, mud
  static const int gas        = 0x04; // fire, steam, smoke
  static const int organic    = 0x08; // dirt, mud, sand, plant, seed, ash, snow
  static const int danger     = 0x10; // fire, lava, acid, lightning, tnt
  static const int flammable  = 0x20; // wood, oil, plant, seed
  static const int conductive = 0x40; // metal, water
}

/// Pre-computed category bitmask per element type. Index = element type.
final Uint8List elCategory = () {
  final t = Uint8List(El.count);
  //                                sol liq gas org dan flm con
  // El.empty (0)  — no flags
  t[El.sand]      = ElCat.organic;
  t[El.water]     = ElCat.liquid | ElCat.conductive;
  t[El.fire]      = ElCat.gas | ElCat.danger;
  t[El.ice]       = ElCat.solid;
  t[El.lightning]  = ElCat.danger;
  t[El.seed]      = ElCat.organic | ElCat.flammable;
  t[El.stone]     = ElCat.solid;
  t[El.tnt]       = ElCat.danger;
  // El.rainbow (9) — no meaningful category
  t[El.mud]       = ElCat.liquid | ElCat.organic;
  t[El.steam]     = ElCat.gas;
  // El.ant (12)   — living entity, not categorized
  t[El.oil]       = ElCat.liquid | ElCat.flammable;
  t[El.acid]      = ElCat.liquid | ElCat.danger;
  t[El.glass]     = ElCat.solid;
  t[El.dirt]      = ElCat.organic;
  t[El.plant]     = ElCat.organic | ElCat.flammable;
  t[El.lava]      = ElCat.liquid | ElCat.danger;
  t[El.snow]      = ElCat.organic;
  t[El.wood]      = ElCat.solid | ElCat.flammable;
  t[El.metal]     = ElCat.solid | ElCat.conductive;
  t[El.smoke]     = ElCat.gas;
  // El.bubble (23) — transient, no category
  t[El.ash]       = ElCat.organic;
  return t;
}();

// ── Ant state constants ──────────────────────────────────────────────
const int antExplorerState = 0;
const int antDiggerState = 1;
const int antCarrierState = 2;
const int antReturningState = 3;
const int antForagerState = 4;
const int antDrowningBase = 10;

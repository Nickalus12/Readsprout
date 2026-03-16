import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/audio_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Element Lab — A kid-friendly physics sandbox (inspired by Powder Game)
// ---------------------------------------------------------------------------

/// Cost in star coins for initial 3-minute session.
const int kElementLabCost = 5;

/// Cost in star coins for a 2-minute extension.
const int kExtensionCost = 3;

/// Initial session duration.
const Duration kSessionDuration = Duration(minutes: 3);

/// Extension duration.
const Duration kExtensionDuration = Duration(minutes: 2);

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
const List<Color> _baseColors = [
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
const List<String> _elementNames = [
  '', 'Sand', 'Water', 'Fire', 'Ice', 'Zap',
  'Seed', 'Stone', 'TNT', 'Rainbow', 'Mud', 'Steam', 'Ant',
  'Oil', 'Acid', 'Glass', 'Dirt', 'Plant', 'Lava', 'Snow',
  'Wood', 'Metal', 'Smoke', 'Bubble', 'Ash',
];

/// Element descriptions for long-press info.
const Map<int, String> _elementDescriptions = {
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
  El.ant: 'Walks along surfaces.\nDrowns in water.\nRuns from fire.\nDissolved by acid.',
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

class ElementLabGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final bool freePlay;

  const ElementLabGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.freePlay = false,
  });

  @override
  State<ElementLabGame> createState() => _ElementLabGameState();
}

class _ElementLabGameState extends State<ElementLabGame>
    with SingleTickerProviderStateMixin {
  // -- Grid dimensions (set in _initGrid based on screen size) ---------------
  int _gridW = 160;
  int _gridH = 240;

  // -- Grid data (typed arrays for performance) ------------------------------
  late Uint8List _grid; // element type per cell
  late Uint8List _life; // lifetime/state counter per cell
  late Uint8List _flags; // per-cell flags (updated-this-frame, direction, etc.)
  late Int8List _velX; // horizontal velocity (ants, etc.)
  late Int8List _velY; // vertical velocity

  // -- Rendering buffer (RGBA pixels) ----------------------------------------
  late Uint8List _pixels;
  final ValueNotifier<ui.Image?> _frameImageNotifier = ValueNotifier(null);

  // -- Animation / ticker ---------------------------------------------------
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _frameCount = 0;
  final _rng = Random();

  // -- UI state --------------------------------------------------------------
  int _selectedElement = El.sand;
  int _brushSize = 1; // 1, 3, or 5
  int _brushMode = 0; // 0=circle, 1=line, 2=spray
  int _lineStartX = -1;
  int _lineStartY = -1;
  int _lineEndX = -1;
  int _lineEndY = -1;
  bool _isDrawing = false;
  bool _isPaused = false;
  bool _showElementInfo = false;
  int _infoElement = El.sand;
  int _selectedTab = 0; // palette tab index

  // Element palette tab definitions
  static const List<List<int>> _tabElements = [
    [El.sand, El.dirt, El.stone, El.ice, El.glass, El.snow, El.wood, El.metal, El.ash], // Solids
    [El.water, El.oil, El.acid, El.mud, El.lava, El.bubble],  // Liquids
    [El.fire, El.lightning, El.tnt, El.steam, El.smoke],       // Energy
    [El.seed, El.ant],                                            // Life
    [El.rainbow, El.eraser],                                    // Tools
  ];
  static const List<IconData> _tabIcons = [
    Icons.landscape_rounded,
    Icons.water_drop_rounded,
    Icons.bolt_rounded,
    Icons.eco_rounded,
    Icons.auto_fix_high_rounded,
  ];

  // -- Canvas layout ---------------------------------------------------------
  double _canvasTop = 0;
  double _canvasLeft = 0;
  double _cellSize = 1.0;
  double _canvasPixelW = 0;
  double _canvasPixelH = 0;

  // -- Physics manipulation --------------------------------------------------
  int _gravityDir = 1; // 1 = down, -1 = up
  int _windForce = 0; // -3..+3
  int _shakeCooldown = 0; // frames remaining
  Offset _shakeOffset = Offset.zero;

  // -- Day/Night system -------------------------------------------------------
  bool _isNight = false;
  double _dayNightT = 0.0; // 0.0 = day, 1.0 = night (smooth transition)
  // Star positions (generated once, twinkle via frame counter)
  late List<int> _starPositions; // grid indices for star cells
  bool _starsGenerated = false;

  // -- Rainbow color cycling -------------------------------------------------
  int _rainbowHue = 0;

  // -- Explosion queue -------------------------------------------------------
  final List<_Explosion> _pendingExplosions = [];

  // -- Lightning flash -------------------------------------------------------
  int _lightningFlashFrames = 0;

  // -- Session timer ---------------------------------------------------------
  late int _remainingSeconds;
  Timer? _sessionTimer;
  bool _sessionExpired = false;
  bool _showTimeWarning = false;
  String _timeWarningText = '';

  // -- Undo history ----------------------------------------------------------
  final List<_UndoSnapshot> _undoHistory = [];
  static const int _maxUndoHistory = 10;
  bool _isCapturingStroke = false;

  // -- Audio narration (mute toggle) ----------------------------------------
  bool _isMuted = false;

  /// Element names that have dedicated word audio files.
  /// Others will be spelled letter-by-letter.
  static const Set<String> _speakableWords = {
    'sand', 'water', 'fire', 'ice', 'plant', 'stone',
    'mud', 'steam', 'ant', 'oil', 'acid', 'glass', 'rainbow',
    'seed', 'dirt', 'lava', 'snow', 'wood', 'metal', 'smoke', 'bubble', 'ash',
  };

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.freePlay
        ? const Duration(minutes: 999).inSeconds
        : kSessionDuration.inSeconds;
    _ticker = createTicker(_onTick);
    _startSessionTimer();
    _loadMutePreference();
  }

  String get _muteKey => 'element_lab_muted_${widget.playerName}';

  Future<void> _loadMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isMuted = prefs.getBool(_muteKey) ?? false;
      });
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    Haptics.tap();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteKey, _isMuted);
  }

  void _toggleDayNight() {
    setState(() => _isNight = !_isNight);
    Haptics.tap();
  }

  void _generateStars() {
    if (_starsGenerated) return;
    _starsGenerated = true;
    // Place ~30 stars in the top 10% of the grid
    final topRows = (_gridH * 0.10).floor().clamp(3, 30);
    _starPositions = [];
    for (int i = 0; i < 30; i++) {
      final sx = _rng.nextInt(_gridW);
      final sy = _rng.nextInt(topRows);
      _starPositions.add(sy * _gridW + sx);
    }
  }

  /// Speak an element name aloud. Uses playWord() for known words,
  /// spells letter-by-letter for others (lightning, TNT, zap).
  Future<void> _speakElementName(int elType) async {
    if (_isMuted || elType == El.empty || elType == El.eraser) return;
    final name = _elementNames[elType.clamp(0, _elementNames.length - 1)].toLowerCase();
    if (name.isEmpty) return;

    if (_speakableWords.contains(name)) {
      await widget.audioService.playWord(name);
    } else {
      // Spell letter-by-letter for non-word names (TNT, Zap, Lightning)
      for (final letter in name.split('')) {
        if (!mounted || _isMuted) break;
        await widget.audioService.playLetter(letter);
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  /// Speak a simple word using playWord.
  Future<void> _speakWord(String word) async {
    if (_isMuted) return;
    await widget.audioService.playWord(word);
  }

  bool _gridInitialized = false;

  void _initGrid(double canvasW, double canvasH) {
    // Compute a cell size that gives ~160 columns, clamped for readability
    final baseCellSize = (canvasW / 160).clamp(1.0, 4.0);
    _gridW = (canvasW / baseCellSize).floor().clamp(40, 400);
    _gridH = (canvasH / baseCellSize).floor().clamp(40, 600);

    // Display values will be computed dynamically in _buildCanvas each frame,
    // but set initial values for the first tick before build runs.
    _cellSize = baseCellSize;
    _canvasPixelW = _gridW * baseCellSize;
    _canvasPixelH = _gridH * baseCellSize;
    _canvasLeft = (canvasW - _canvasPixelW) / 2;
    _canvasTop = (canvasH - _canvasPixelH) / 2;

    final totalCells = _gridW * _gridH;
    _grid = Uint8List(totalCells);
    _life = Uint8List(totalCells);
    _flags = Uint8List(totalCells);
    _velX = Int8List(totalCells);
    _velY = Int8List(totalCells);
    _pixels = Uint8List(totalCells * 4); // RGBA

    _generateStars();
    _gridInitialized = true;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused || _sessionExpired) return;
      setState(() {
        _remainingSeconds--;
        // Time warnings
        if (_remainingSeconds == 60) {
          _showTimeWarning = true;
          _timeWarningText = '1 Minute Left!';
          if (!_isMuted) {
            _speakWord('one');
            Future.delayed(const Duration(milliseconds: 400), () => _speakWord('minute'));
          }
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        } else if (_remainingSeconds == 30) {
          _showTimeWarning = true;
          _timeWarningText = '30 Seconds Left!';
          if (!_isMuted) {
            _speakWord('thirty');
            Future.delayed(const Duration(milliseconds: 400), () => _speakWord('seconds'));
          }
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        }

        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _sessionExpired = true;
          if (!_isMuted) {
            _speakWord('time');
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _ticker.dispose();
    _frameImageNotifier.value?.dispose();
    _frameImageNotifier.dispose();
    super.dispose();
  }

  // ── Tick callback ────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_gridInitialized || _isPaused || _sessionExpired) return;

    // Throttle to ~30 fps
    final dt = elapsed - _lastTick;
    if (dt.inMilliseconds < 30) return;
    _lastTick = elapsed;
    _frameCount++;

    if (_shakeCooldown > 0) _shakeCooldown--;

    // Smooth day/night transition (60 frames = 2 seconds at 30fps)
    final targetT = _isNight ? 1.0 : 0.0;
    if ((_dayNightT - targetT).abs() > 0.001) {
      _dayNightT += (_isNight ? 1.0 : -1.0) / 60.0;
      _dayNightT = _dayNightT.clamp(0.0, 1.0);
    }

    _applyWind();
    _simulate();
    _renderPixels();
    _buildImage();
  }

  // ── Wind & shake ─────────────────────────────────────────────────────

  /// Lightweight elements affected fully by wind.
  static const Set<int> _lightWindElements = {
    El.sand, El.snow, El.smoke, El.fire, El.steam, El.bubble, El.seed, El.ash,
  };
  /// Heavy liquids affected partially by wind.
  static const Set<int> _heavyWindElements = {
    El.water, El.oil, El.acid,
  };
  /// Static elements unaffected by wind or shake.
  static const Set<int> _staticElements = {
    El.stone, El.metal, El.wood, El.glass, El.ice,
  };

  // Wind sensitivity per element: 0 = unaffected, 1 = heavy, 2 = light, 3 = ash
  // Pre-computed lookup for O(1) access instead of Set.contains
  static final Uint8List _windSensitivity = () {
    final t = Uint8List(32); // enough for all element IDs
    for (final el in _lightWindElements) { t[el] = 2; }
    for (final el in _heavyWindElements) { t[el] = 1; }
    t[El.ash] = 3;
    return t;
  }();

  void _applyWind() {
    if (_windForce == 0) return;
    final absWind = _windForce.abs();
    final dir = _windForce > 0 ? 1 : -1;
    final w = _gridW;
    final g = _grid;

    // Pre-compute thresholds (avoid repeated division in inner loop)
    // Using int random (nextInt(100)) instead of nextDouble for speed
    final ashThresh = (absWind * 25).clamp(0, 100);   // /4.0 → 25%
    final lightThresh = (absWind * 10).clamp(0, 100);  // /10.0 → 10%
    final heavyThresh = (absWind * 3).clamp(0, 100);   // /30.0 → ~3%

    for (int y = 0; y < _gridH; y++) {
      final startX = dir > 0 ? w - 1 : 0;
      final endX = dir > 0 ? -1 : w;
      final step = dir > 0 ? -1 : 1;
      final rowOff = y * w;
      for (int x = startX; x != endX; x += step) {
        final el = g[rowOff + x];
        if (el == El.empty) continue;
        final sens = el < 32 ? _windSensitivity[el] : 0;
        if (sens == 0) continue;

        final thresh = sens == 3 ? ashThresh : (sens == 2 ? lightThresh : heavyThresh);
        if (_rng.nextInt(100) < thresh) {
          final nx = x + dir;
          if (nx >= 0 && nx < w && g[rowOff + nx] == El.empty) {
            _swap(rowOff + x, rowOff + nx);
          }
        }
      }
    }
  }

  void _doShake() {
    if (_shakeCooldown > 0) return;
    _shakeCooldown = 60; // 2 second cooldown at 30fps
    Haptics.tap();

    // Random displacement
    for (int y = _gridH - 1; y >= 0; y--) {
      for (int x = 0; x < _gridW; x++) {
        final idx = y * _gridW + x;
        final el = _grid[idx];
        if (el == El.empty || _staticElements.contains(el)) continue;
        if (_rng.nextInt(100) < 30) {
          final dx = _rng.nextInt(3) - 1;
          final dy = _rng.nextInt(3) - 1;
          final nx = x + dx;
          final ny = y + dy;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.empty) {
            _swap(idx, ny * _gridW + nx);
          }
        }
      }
    }

    // Brief screen shake animation
    _shakeOffset = Offset(
      (_rng.nextDouble() - 0.5) * 6,
      (_rng.nextDouble() - 0.5) * 6,
    );
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _shakeOffset = Offset(-_shakeOffset.dx, -_shakeOffset.dy));
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _shakeOffset = Offset.zero);
    });
  }

  // ── Physics simulation (single pass) ────────────────────────────────────

  void _simulate() {
    // Clear update flags
    _flags.fillRange(0, _flags.length, 0);

    // Process pending explosions
    _processExplosions();

    // Advance rainbow hue
    _rainbowHue = (_rainbowHue + 3) % 360;

    // Decrease lightning flash
    if (_lightningFlashFrames > 0) _lightningFlashFrames--;

    // Scan from gravity-bottom to top, left-right alternating
    final leftToRight = _frameCount.isEven;
    final yStart = _gravityDir == 1 ? _gridH - 2 : 1;
    final yEnd = _gravityDir == 1 ? -1 : _gridH;
    final yStep = _gravityDir == 1 ? -1 : 1;
    for (int y = yStart; y != yEnd; y += yStep) {
      final startX = leftToRight ? 0 : _gridW - 1;
      final endX = leftToRight ? _gridW : -1;
      final dx = leftToRight ? 1 : -1;
      for (int x = startX; x != endX; x += dx) {
        final idx = y * _gridW + x;
        if (_flags[idx] == 1) continue; // already moved this frame

        final el = _grid[idx];
        if (el == El.empty) {
          // Pheromone evaporation for empty cells (every 8 frames)
          if (_frameCount % 8 == 0 && _life[idx] > 0) {
            _life[idx]--;
          }
          continue;
        }

        switch (el) {
          case El.sand:
            _simSand(x, y, idx);
          case El.water:
            _simWater(x, y, idx);
          case El.fire:
            _simFire(x, y, idx);
          case El.ice:
            _simIce(x, y, idx);
          case El.lightning:
            _simLightning(x, y, idx);
          case El.seed:
            _simSeed(x, y, idx);
          case El.tnt:
            _simTNT(x, y, idx);
          case El.rainbow:
            _simRainbow(x, y, idx);
          case El.mud:
            _simMud(x, y, idx);
          case El.steam:
            _simSteam(x, y, idx);
          case El.ant:
            _simAnt(x, y, idx);
          case El.oil:
            _simOil(x, y, idx);
          case El.acid:
            _simAcid(x, y, idx);
          case El.dirt:
            _simDirt(x, y, idx);
          case El.plant:
            _simPlant(x, y, idx);
          case El.lava:
            _simLava(x, y, idx);
          case El.snow:
            _simSnow(x, y, idx);
          case El.wood:
            _simWood(x, y, idx);
          case El.metal:
            _simMetal(x, y, idx);
          case El.smoke:
            _simSmoke(x, y, idx);
          case El.bubble:
            _simBubble(x, y, idx);
          case El.ash:
            _simAsh(x, y, idx);
          // stone and glass do nothing (immovable)
        }
      }
    }
  }

  // ── Element behaviors ───────────────────────────────────────────────────

  void _simSand(int x, int y, int idx) {
    // Lightning hitting sand -> glass
    if (_checkAdjacent(x, y, El.lightning)) {
      _grid[idx] = El.glass;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Check for water below or adjacent -> become mud
    if (_checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.mud;
      _removeOneAdjacent(x, y, El.water);
      _flags[idx] = 1;
      return;
    }

    _fallGranular(x, y, idx, El.sand);
  }

  void _simWater(int x, int y, int idx) {
    final g = _gravityDir;
    final by = y + g;
    final uy = y - g;

    // ── Neighbor reactions ──────────────────────────────────────────────

    // Check for adjacent ice → freeze (1 in 60 chance, slower than before)
    if (_rng.nextInt(60) == 0 && _checkAdjacent(x, y, El.ice)) {
      _grid[idx] = El.ice;
      _flags[idx] = 1;
      return;
    }

    // Evaporation: water near heat source (fire/lava within 2-cell radius)
    // At night: half evaporation rate
    final evapChance = _isNight ? 30 : 15;
    if (_rng.nextInt(evapChance) == 0) {
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!_inBounds(nx, ny)) continue;
          final neighbor = _grid[ny * _gridW + nx];
          if (neighbor == El.fire || neighbor == El.lava) {
            _grid[idx] = El.steam;
            _life[idx] = 0;
            _flags[idx] = 1;
            return;
          }
        }
      }
    }

    // Water + Oil: oil floats — only swap if water is BELOW oil (water sinks under oil)
    // The oil sim handles rising through water, so water just needs to sink past oil above it.
    final uy2 = y - _gravityDir;
    if (_inBounds(x, uy2) && _grid[uy2 * _gridW + x] == El.oil && !(_flags[uy2 * _gridW + x] == 1)) {
      final ui2 = uy2 * _gridW + x;
      _grid[idx] = El.oil;
      _grid[ui2] = El.water;
      _life[ui2] = 0;
      _flags[idx] = 1;
      _flags[ui2] = 1;
      return;
    }

    // Water defuses TNT (TNT becomes sand over ~30 frames)
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];
        // Defuse TNT
        if (neighbor == El.tnt && _rng.nextInt(10) == 0) {
          _grid[ni] = El.sand;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Water absorbs smoke
        if (neighbor == El.smoke && _rng.nextInt(10) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Water + Rainbow → prismatic refraction (spawn extra rainbow)
        if (neighbor == El.rainbow && _rng.nextInt(40) == 0) {
          // Find an empty cell nearby and spawn rainbow
          final rx = x + _rng.nextInt(3) - 1;
          final ry = uy;
          if (_inBounds(rx, ry) && _grid[ry * _gridW + rx] == El.empty) {
            _grid[ry * _gridW + rx] = El.rainbow;
            _life[ry * _gridW + rx] = 0;
            _flags[ry * _gridW + rx] = 1;
          }
        }
        // Water nourishes plant (handled by making plant grow faster — set flag)
        if (neighbor == El.plant && _rng.nextInt(20) == 0) {
          // Boost plant growth by decrementing its life timer
          if (_life[ni] > 2) _life[ni] -= 2;
        }
      }
    }

    // ── Water column height (for leveling) ──────────────────────────────
    // Count how tall this water column is (downward from this cell)
    int colHeight = 1;
    for (int cy = y + g; _inBounds(x, cy) && colHeight < 12; cy += g) {
      final c = _grid[cy * _gridW + x];
      if (c == El.water) {
        colHeight++;
      } else {
        break;
      }
    }
    // Count water above too for total column
    int above = 0;
    for (int cy = y - g; _inBounds(x, cy) && above < 12; cy -= g) {
      final c = _grid[cy * _gridW + x];
      if (c == El.water || c == El.oil) {
        above++;
      } else {
        break;
      }
    }
    final totalCol = colHeight + above;

    // ── Movement ──────────────────────────────────────────────────────

    // Fall in gravity direction
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _velY[idx] = (_velY[idx] + 1).clamp(0, 10).toInt();
      _swap(idx, by * _gridW + x);
      return;
    }

    // Splash: if falling fast onto a solid, scatter sideways
    if (_velY[idx] >= 3 && _inBounds(x, by) && _grid[by * _gridW + x] != El.empty) {
      for (int i = 0; i < (_velY[idx] ~/ 2).clamp(1, 3); i++) {
        final sx = x + (_rng.nextBool() ? 1 : -1) * (1 + _rng.nextInt(2));
        final sy = y - g * _rng.nextInt(2);
        if (_inBounds(sx, sy) && _grid[sy * _gridW + sx] == El.empty) {
          _grid[sy * _gridW + sx] = El.water;
          _life[sy * _gridW + sx] = 0;
          _flags[sy * _gridW + sx] = 1;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _velY[idx] = 0;
          return;
        }
      }
    }
    _velY[idx] = 0;

    // Use momentum: prefer previous flow direction
    final momentum = _velX[idx];
    final dl = momentum != 0 ? (momentum > 0) : _rng.nextBool();
    final x1 = dl ? x + 1 : x - 1;
    final x2 = dl ? x - 1 : x + 1;

    // Try diagonal in gravity direction
    if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
      _velX[idx] = dl ? 1 : -1;
      _swap(idx, by * _gridW + x1);
      return;
    }
    if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
      _velX[idx] = dl ? -1 : 1;
      _swap(idx, by * _gridW + x2);
      return;
    }

    // Flow sideways — base 2 + pressure from column height
    final flowDist = 2 + (totalCol ~/ 2).clamp(0, 5);
    for (int d = 1; d <= flowDist; d++) {
      final sx1 = dl ? x + d : x - d;
      final sx2 = dl ? x - d : x + d;
      if (_inBounds(sx1, y) && _grid[y * _gridW + sx1] == El.empty) {
        _velX[idx] = dl ? 1 : -1;
        _swap(idx, y * _gridW + sx1);
        return;
      }
      if (_inBounds(sx2, y) && _grid[y * _gridW + sx2] == El.empty) {
        _velX[idx] = dl ? -1 : 1;
        _swap(idx, y * _gridW + sx2);
        return;
      }
    }

    // ── Surface leveling — actively seek lower adjacent columns ────────
    // If this cell is at the surface (empty above), check if adjacent
    // columns are shorter. If so, move there to equalize water level.
    final aboveIdx = _inBounds(x, uy) ? _grid[uy * _gridW + x] : -1;
    if (aboveIdx == El.empty || aboveIdx == -1) {
      // We're at the water surface — count adjacent column heights
      for (final dir in [1, -1]) {
        final nx = x + dir;
        if (!_inBounds(nx, y)) continue;
        final nIdx = y * _gridW + nx;
        // Adjacent cell at same level must be empty (we'd flow there)
        if (_grid[nIdx] != El.empty) continue;
        // Check: is there a solid or water below that empty cell?
        final belowNx = y + g;
        if (!_inBounds(nx, belowNx)) continue;
        final belowCell = _grid[belowNx * _gridW + nx];
        if (belowCell == El.empty) continue; // would fall, not level
        // Count adjacent column height
        int adjCol = 0;
        for (int cy = y + g; _inBounds(nx, cy) && adjCol < 12; cy += g) {
          if (_grid[cy * _gridW + nx] == El.water) {
            adjCol++;
          } else {
            break;
          }
        }
        // Move if our column is taller
        if (totalCol > adjCol + 1) {
          _velX[idx] = dir;
          _swap(idx, nIdx);
          return;
        }
      }
      // Also try 2-3 cells out for faster leveling on flat surfaces
      for (final dir in [1, -1]) {
        for (int d = 2; d <= 3; d++) {
          final nx = x + dir * d;
          if (!_inBounds(nx, y)) continue;
          // All cells between must be empty
          bool pathClear = true;
          for (int pd = 1; pd < d; pd++) {
            final px = x + dir * pd;
            if (!_inBounds(px, y) || _grid[y * _gridW + px] != El.empty) {
              pathClear = false;
              break;
            }
          }
          if (!pathClear) continue;
          if (_grid[y * _gridW + nx] != El.empty) continue;
          final belowNx = y + g;
          if (!_inBounds(nx, belowNx)) continue;
          if (_grid[belowNx * _gridW + nx] == El.empty) continue;
          _velX[idx] = dir;
          _swap(idx, y * _gridW + nx);
          return;
        }
      }
    }

    // Stuck — decay momentum
    if (_rng.nextInt(4) == 0) _velX[idx] = 0;
  }

  void _simFire(int x, int y, int idx) {
    _life[idx]++;
    // Fire dies after 40-80 frames → becomes ash (sometimes smoke rises)
    if (_life[idx] > 40 + _rng.nextInt(40)) {
      _grid[idx] = El.ash;
      _life[idx] = 0;
      _flags[idx] = 1;
      // Spawn smoke above ~50% of the time
      final uy = y - _gravityDir;
      if (_rng.nextBool() && _inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        _grid[uy * _gridW + x] = El.smoke;
        _life[uy * _gridW + x] = 0;
        _flags[uy * _gridW + x] = 1;
      }
      return;
    }

    // Check for adjacent reactions
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];
        if (neighbor == El.water) {
          _grid[ni] = El.steam;
          _life[ni] = 0;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _flags[ni] = 1;
          return;
        }
        if ((neighbor == El.plant || neighbor == El.seed) && _rng.nextInt(2) == 0) {
          // Fire spreads to plant/seed aggressively
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.wood && _rng.nextInt(4) == 0) {
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.oil) {
          // Oil is very flammable — always ignites
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Ash is already burned — fire does nothing to it
        if (neighbor == El.ice) {
          _grid[ni] = El.water;
          _life[ni] = 150; // melting visual
          _flags[ni] = 1;
        }
        if (neighbor == El.snow) {
          // Snow melts into water (not just disappears)
          _grid[ni] = El.water;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.bubble) {
          // Bubble pops into steam when touching fire
          _grid[ni] = El.steam;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.tnt) {
          _pendingExplosions.add(_Explosion(nx, ny, _calculateTNTRadius(nx, ny)));
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
      }
    }

    // Rise opposite to gravity with random drift
    final uy = y - _gravityDir;
    if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
      _swap(idx, uy * _gridW + x);
      return;
    }
    final drift = _rng.nextInt(3) - 1;
    final driftX = x + drift;
    if (_inBounds(driftX, uy) &&
        _grid[uy * _gridW + driftX] == El.empty) {
      _swap(idx, uy * _gridW + driftX);
    }
  }

  void _simIce(int x, int y, int idx) {
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      _grid[idx] = El.water;
      _life[idx] = 150; // melting visual flag
      _flags[idx] = 1;
      return;
    }
    // Temperature balance: ice surrounded by 3+ water cells melts (slower at night)
    final ambientMeltChance = _isNight ? 60 : 20;
    if (_rng.nextInt(ambientMeltChance) == 0) {
      int waterCount = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.water) {
            waterCount++;
          }
        }
      }
      if (waterCount >= 3) {
        _grid[idx] = El.water;
        _life[idx] = 150;
        _flags[idx] = 1;
      }
    }
  }

  void _simLightning(int x, int y, int idx) {
    _life[idx]++;
    if (_life[idx] > 8) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }

    _lightningFlashFrames = 3;

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];
        if (neighbor == El.tnt) {
          _pendingExplosions.add(_Explosion(nx, ny, _calculateTNTRadius(nx, ny)));
        }
        if (neighbor == El.ice) {
          _grid[ni] = El.water;
          _life[ni] = 150;
          _flags[ni] = 1;
        }
        if (neighbor == El.water) {
          _electrifyWater(nx, ny);
        }
        if (neighbor == El.sand) {
          _grid[ni] = El.glass;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.metal) {
          _conductMetal(nx, ny);
        }
      }
    }

    // Move in gravity direction rapidly
    final dist = 2 + _rng.nextInt(3);
    final ndx = _rng.nextInt(3) - 1;
    final targetY = y + _gravityDir * dist;
    final targetX = x + ndx;
    if (!_inBounds(targetX, targetY)) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }
    final ni = targetY * _gridW + targetX;
    if (_grid[ni] == El.empty) {
      _grid[ni] = El.lightning;
      _life[ni] = _life[idx];
      _flags[ni] = 1;
      _grid[idx] = El.empty;
      _life[idx] = 0;
    }
  }

  // ── Plant data encoding ─────────────────────────────────────────────
  static const int kPlantGrass = 1, kPlantFlower = 2, kPlantTree = 3;
  static const int kPlantMushroom = 4, kPlantVine = 5;
  static const int kStSprout = 0, kStGrowing = 1, kStMature = 2;
  static const int kStWilting = 3, kStDead = 4;
  int _plantType(int idx) => _velX[idx] & 0x0F;
  int _plantStage(int idx) => (_velX[idx] >> 4) & 0x0F;
  void _setPlantData(int idx, int t, int s) => _velX[idx] = ((s & 0xF) << 4) | (t & 0xF);
  static const _plantMaxH = [0, 4, 10, 25, 4, 15];
  static const _plantMinMoist = [0, 1, 2, 3, 4, 2];
  static const _plantGrowRate = [0, 25, 35, 20, 40, 30];
  int _selectedSeedType = 1; // kPlantGrass

  void _simSeed(int x, int y, int idx) {
    final sType = _velX[idx].clamp(1, 5);
    _life[idx]++;
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      _grid[idx] = El.ash; _life[idx] = 0; _velX[idx] = 0; _flags[idx] = 1; return;
    }
    if (_checkAdjacent(x, y, El.acid)) {
      _grid[idx] = El.empty; _life[idx] = 0; _velX[idx] = 0; return;
    }
    final by = y + _gravityDir;
    bool onDirt = _inBounds(x, by) && _grid[by * _gridW + x] == El.dirt;
    if (onDirt) {
      final soilM = _life[by * _gridW + x];
      if (soilM >= _plantMinMoist[sType]) {
        if (_life[idx] > 30) {
          _grid[idx] = El.plant; _life[idx] = 50;
          _setPlantData(idx, sType, kStSprout); _velY[idx] = 1; _flags[idx] = 1; return;
        }
        return;
      } else if (_life[idx] > 60) {
        _grid[idx] = El.empty; _life[idx] = 0; _velX[idx] = 0; return;
      }
    } else {
      bool onSolid = _inBounds(x, by) && _grid[by * _gridW + x] != El.empty;
      if (onSolid) { if (_life[idx] > 60) { _grid[idx] = El.empty; _life[idx] = 0; _velX[idx] = 0; return; } return; }
    }
    _fallGranular(x, y, idx, El.seed);
  }

  void _simDirt(int x, int y, int idx) {
    // _life[idx] = soil moisture level (0-5)

    // --- Soil moisture: gain from adjacent water (every ~10 frames) ---
    if (_frameCount % 10 == 0 && _life[idx] < 5 && _checkAdjacent(x, y, El.water)) {
      _life[idx]++;
    }

    // --- Moisture propagation from wetter dirt neighbors (every ~20 frames) ---
    if (_frameCount % 20 == 0 && _life[idx] < 4) {
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.dirt && _life[ni] > _life[idx] + 1) {
            _life[idx]++;
            break;
          }
        }
      }
    }

    // --- Lose moisture when not near water (every ~30 frames) ---
    if (_frameCount % 30 == 0 && _life[idx] > 0 && !_checkAdjacent(x, y, El.water)) {
      bool nearWetDirt = false;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.dirt &&
              _life[ny * _gridW + nx] > _life[idx]) {
            nearWetDirt = true;
            break;
          }
        }
        if (nearWetDirt) break;
      }
      if (!nearWetDirt) _life[idx]--;
    }

    // --- Saturated + lots of water → mud ---
    if (_life[idx] >= 5) {
      int wc = 0;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          if (_inBounds(x + dx2, y + dy2) &&
              _grid[(y + dy2) * _gridW + (x + dx2)] == El.water) {
            wc++;
          }
        }
      }
      if (wc >= 3) {
        _grid[idx] = El.mud;
        _life[idx] = 0;
        _flags[idx] = 1;
        return;
      }
    }

    // --- Ash fertilizer: ash on dirt consumed, moisture +1 ---
    if (_rng.nextInt(10) == 0) {
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.ash) {
            final ni = ny * _gridW + nx;
            _grid[ni] = El.empty;
            _life[ni] = 0;
            _flags[ni] = 1;
            _life[idx] = (_life[idx] + 1).clamp(0, 5);
            break;
          }
        }
      }
    }

    // --- Fall with water displacement (Task #1) ---
    _fallGranularDisplace(x, y, idx, El.dirt);
  }

  /// Check if a water cell is trapped (surrounded, 0-1 water neighbors, no empty).
  bool _isTrappedWater(int wx, int wy) {
    int waterN = 0, emptyN = 0;
    for (int dy2 = -1; dy2 <= 1; dy2++) {
      for (int dx2 = -1; dx2 <= 1; dx2++) {
        if (dx2 == 0 && dy2 == 0) continue;
        final nx = wx + dx2;
        final ny = wy + dy2;
        if (!_inBounds(nx, ny)) continue;
        final n = _grid[ny * _gridW + nx];
        if (n == El.water) waterN++;
        if (n == El.empty) emptyN++;
      }
    }
    return emptyN == 0 && waterN <= 1;
  }

  /// Push a water cell to the nearest empty cell above or beside.
  void _displaceWater(int wx, int wy) {
    final wi = wy * _gridW + wx;
    for (int r = 1; r <= 10; r++) {
      final uy = wy - _gravityDir * r;
      if (_inBounds(wx, uy) && _grid[uy * _gridW + wx] == El.empty) {
        _grid[uy * _gridW + wx] = El.water;
        _life[uy * _gridW + wx] = 0;
        _flags[uy * _gridW + wx] = 1;
        _grid[wi] = El.empty;
        _life[wi] = 0;
        _flags[wi] = 1;
        return;
      }
      for (final dx in [r, -r]) {
        final nx = wx + dx;
        if (_inBounds(nx, wy) && _grid[wy * _gridW + nx] == El.empty) {
          _grid[wy * _gridW + nx] = El.water;
          _life[wy * _gridW + nx] = 0;
          _flags[wy * _gridW + nx] = 1;
          _grid[wi] = El.empty;
          _life[wi] = 0;
          _flags[wi] = 1;
          return;
        }
        final uy2 = wy - _gravityDir * r;
        if (_inBounds(nx, uy2) && _grid[uy2 * _gridW + nx] == El.empty) {
          _grid[uy2 * _gridW + nx] = El.water;
          _life[uy2 * _gridW + nx] = 0;
          _flags[uy2 * _gridW + nx] = 1;
          _grid[wi] = El.empty;
          _life[wi] = 0;
          _flags[wi] = 1;
          return;
        }
      }
    }
  }

  /// Granular fall with water displacement (dirt pushes water up, not absorbs).
  void _fallGranularDisplace(int x, int y, int idx, int elType) {
    final by = y + _gravityDir;
    if (_inBounds(x, by)) {
      final below = by * _gridW + x;
      final belowEl = _grid[below];
      if (belowEl == El.empty) {
        _swap(idx, below);
        return;
      }
      if (belowEl == El.water) {
        if (_isTrappedWater(x, by)) {
          _grid[below] = elType;
          _life[below] = (_life[idx] + 1).clamp(0, 5);
          _velY[below] = _velY[idx];
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _velY[idx] = 0;
          _flags[idx] = 1;
          _flags[below] = 1;
        } else {
          _displaceWater(x, by);
          if (_grid[below] == El.empty) {
            _grid[below] = elType;
            _life[below] = _life[idx];
            _velY[below] = _velY[idx];
            _grid[idx] = El.empty;
            _life[idx] = 0;
            _velY[idx] = 0;
            _flags[idx] = 1;
            _flags[below] = 1;
          } else {
            _grid[idx] = El.water;
            _grid[below] = elType;
            _life[below] = _life[idx];
            _life[idx] = 0;
            _flags[idx] = 1;
            _flags[below] = 1;
          }
        }
        return;
      }
    }
    final goLeft = _rng.nextBool();
    final x1 = goLeft ? x - 1 : x + 1;
    final x2 = goLeft ? x + 1 : x - 1;
    if (_inBounds(x, by)) {
      if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
        _swap(idx, by * _gridW + x1);
        return;
      }
      if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
        _swap(idx, by * _gridW + x2);
        return;
      }
    }
  }

  void _simPlant(int x, int y, int idx) {
    final pType = _plantType(idx);
    final pStage = _plantStage(idx);
    final hydration = _life[idx]; // 0-100

    // ── Instant death: fire, lava, lightning → ash ──
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      _grid[idx] = El.fire; _life[idx] = 0; _velX[idx] = 0; _velY[idx] = 0;
      _flags[idx] = 1; return;
    }
    // Acid dissolves over ~20 frames
    if (_checkAdjacent(x, y, El.acid) && _rng.nextInt(3) == 0) {
      _grid[idx] = El.empty; _life[idx] = 0; _velX[idx] = 0; _velY[idx] = 0;
      _flags[idx] = 1; return;
    }

    // ── Dead plant decomposes to dirt after ~120 frames ──
    if (pStage == kStDead) {
      _velY[idx] = (_velY[idx] + 1).clamp(0, 127).toInt();
      if (_velY[idx] > 120) {
        _grid[idx] = El.dirt; _life[idx] = 0; _velX[idx] = 0; _velY[idx] = 0;
        _flags[idx] = 1;
      }
      return;
    }

    // ── Hydration: check soil moisture below/around ──
    if (_frameCount % 5 == 0) {
      bool hasMoisture = false;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          final nx = x + dx2; final ny = y + dy2;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.dirt && _life[ni] >= _plantMinMoist[pType.clamp(1, 5)]) {
            hasMoisture = true; break;
          }
          if (_grid[ni] == El.water) { hasMoisture = true; break; }
        }
        if (hasMoisture) break;
      }
      if (hasMoisture) {
        _life[idx] = (hydration + 2).clamp(0, 100);
      } else {
        _life[idx] = (hydration - 1).clamp(0, 100);
      }
    }

    // ── Wilting / recovery ──
    if (_life[idx] < 30 && pStage < kStWilting) {
      _setPlantData(idx, pType, kStWilting);
    } else if (_life[idx] >= 30 && pStage == kStWilting) {
      _setPlantData(idx, pType, _velY[idx] >= _plantMaxH[pType.clamp(1, 5)] ? kStMature : kStGrowing);
    }
    // Death from dehydration
    if (_life[idx] <= 0 && pStage == kStWilting) {
      _setPlantData(idx, pType, kStDead);
      _velY[idx] = 0; // reuse as decompose timer
      return;
    }

    // ── Growth (only if sprout/growing, not wilting/dead) ──
    if (pStage > kStMature) return; // wilting or dead — no growth

    final maxH = _plantMaxH[pType.clamp(1, 5)];
    final curSize = _velY[idx].clamp(0, 127).toInt();
    if (curSize >= maxH) {
      if (pStage != kStMature) _setPlantData(idx, pType, kStMature);
      return;
    }

    // Ash nearby = fertilizer bonus (1.5x growth)
    bool fertilized = _checkAdjacent(x, y, El.ash);
    int growRate = _plantGrowRate[pType.clamp(1, 5)];
    if (_isNight && pType != kPlantMushroom) growRate = (growRate * 5); // 20% rate
    if (fertilized) growRate = (growRate * 2) ~/ 3; // 1.5x faster

    if (_frameCount % growRate != 0) return;

    // Advance from sprout to growing after first growth
    if (pStage == kStSprout) _setPlantData(idx, pType, kStGrowing);

    // ── Growth patterns per plant type (Task #6) ──
    switch (pType) {
      case kPlantGrass:
        _growGrass(x, y, idx, curSize);
      case kPlantFlower:
        _growFlower(x, y, idx, curSize);
      case kPlantTree:
        _growTree(x, y, idx, curSize);
      case kPlantMushroom:
        _growMushroom(x, y, idx, curSize);
      case kPlantVine:
        _growVine(x, y, idx, curSize);
    }
  }

  // ── Plant growth patterns (Task #6) ──────────────────────────────────

  void _growGrass(int x, int y, int idx, int curSize) {
    // Grass: 2-4 tall, spreads sideways aggressively, varied heights
    // Vary max height per blade (2-4) based on position for natural look
    final bladeMaxH = 2 + (idx % 3); // 2, 3, or 4
    if (curSize < bladeMaxH) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        _setPlantData(ni, kPlantGrass, kStGrowing); _velY[ni] = (curSize + 1);
        _flags[ni] = 1;
        _velY[idx] = (curSize + 1);
      }
    }
    // Spread sideways more aggressively — both directions, higher chance
    if (_rng.nextInt(20) == 0) {
      // Try both sides for denser turf
      for (final side in [x - 1, x + 1]) {
        if (_rng.nextInt(2) == 0) continue; // 50% chance each side
        final by = y + _gravityDir;
        if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty &&
            _inBounds(side, by) && _grid[by * _gridW + side] == El.dirt) {
          final ni = y * _gridW + side;
          _grid[ni] = El.plant; _life[ni] = _life[idx];
          _setPlantData(ni, kPlantGrass, kStSprout); _velY[ni] = 1;
          _flags[ni] = 1;
        }
      }
    }
    // Fill in density: grow additional blades in gaps adjacent to existing grass
    if (_rng.nextInt(30) == 0 && curSize >= 2) {
      final side = _rng.nextBool() ? x - 1 : x + 1;
      final uy = y - _gravityDir;
      if (_inBounds(side, uy) && _grid[uy * _gridW + side] == El.empty &&
          _inBounds(side, y) && _grid[y * _gridW + side] == El.plant) {
        final ni = uy * _gridW + side;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        _setPlantData(ni, kPlantGrass, kStGrowing); _velY[ni] = 2;
        _flags[ni] = 1;
      }
    }
  }

  void _growFlower(int x, int y, int idx, int curSize) {
    // Flower: grows up 7-10 cells, leaves along stem, multi-cell bloom at top
    if (curSize < 10) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        final newSize = curSize + 1;
        // Top 2-3 cells are bloom (mature stage marks bloom)
        _setPlantData(ni, kPlantFlower, newSize >= 7 ? kStMature : kStGrowing);
        _velY[ni] = newSize;
        _flags[ni] = 1;
        _velY[idx] = newSize;
      }
      // Add leaves along the stem every 3-4 cells, alternating left/right
      if (curSize >= 3 && curSize % 3 == 0) {
        final leafSide = (curSize ~/ 3) % 2 == 0 ? x - 1 : x + 1;
        if (_inBounds(leafSide, y) && _grid[y * _gridW + leafSide] == El.empty) {
          final ni = y * _gridW + leafSide;
          _grid[ni] = El.plant; _life[ni] = _life[idx];
          // Use kStSprout to mark leaf cells (distinct from stem/bloom)
          _setPlantData(ni, kPlantFlower, kStSprout); _velY[ni] = curSize;
          _flags[ni] = 1;
        }
      }
    }
    // Bloom expansion: at mature height, spread bloom sideways (2-3 cells wide)
    if (curSize >= 8 && _rng.nextInt(3) == 0) {
      for (final side in [x - 1, x + 1]) {
        if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
          final ni = y * _gridW + side;
          _grid[ni] = El.plant; _life[ni] = _life[idx];
          _setPlantData(ni, kPlantFlower, kStMature); _velY[ni] = curSize;
          _flags[ni] = 1;
        }
      }
    }
  }

  void _growTree(int x, int y, int idx, int curSize) {
    // Tree: 10-25 tall, trunk with branches, wide canopy, root system
    if (curSize < 25) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        final newSize = curSize + 1;
        // Canopy starts at ~50% height (12 of 25)
        final isTrunk = newSize < 12;
        _setPlantData(ni, kPlantTree, isTrunk ? kStGrowing : kStMature);
        _velY[ni] = newSize;
        _flags[ni] = 1;
        _velY[idx] = newSize;
      }
      // Root system: at early growth, grow roots downward into dirt
      if (curSize <= 4 && curSize >= 2 && _rng.nextInt(8) == 0) {
        final rootX = x + (_rng.nextBool() ? -1 : 1);
        final rootY = y + _gravityDir;
        if (_inBounds(rootX, rootY) && _grid[rootY * _gridW + rootX] == El.dirt) {
          final ni = rootY * _gridW + rootX;
          _grid[ni] = El.plant; _life[ni] = _life[idx];
          _setPlantData(ni, kPlantTree, kStSprout); _velY[ni] = 1;
          _flags[ni] = 1;
        }
      }
      // Branches: at height 8-11, spawn side branches (2-4 cells long)
      if (curSize >= 8 && curSize < 12 && _rng.nextInt(10) < 3) {
        final branchDir = _rng.nextBool() ? -1 : 1;
        final branchLen = 2 + _rng.nextInt(3);
        for (int b = 1; b <= branchLen; b++) {
          final bx = x + branchDir * b;
          final by = y - (_gravityDir * (b > 2 ? 1 : 0));
          if (_inBounds(bx, by) && _grid[by * _gridW + bx] == El.empty) {
            final ni = by * _gridW + bx;
            _grid[ni] = El.plant; _life[ni] = _life[idx];
            _setPlantData(ni, kPlantTree, kStGrowing); _velY[ni] = curSize;
            _flags[ni] = 1;
          } else {
            break;
          }
        }
      }
      // Canopy: spread sideways, wider at greater height (up to 4 cells)
      if (curSize >= 12) {
        for (final side in [x - 1, x + 1]) {
          if (_rng.nextInt(3) == 0) continue;
          for (final sy in [y, y - _gravityDir]) {
            if (_inBounds(side, sy) && _grid[sy * _gridW + side] == El.empty) {
              final ni = sy * _gridW + side;
              _grid[ni] = El.plant; _life[ni] = _life[idx];
              _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
              _flags[ni] = 1;
              break;
            }
          }
        }
        if (curSize >= 16 && _rng.nextInt(3) == 0) {
          for (final side in [x - 2, x + 2]) {
            if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
              final ni = y * _gridW + side;
              _grid[ni] = El.plant; _life[ni] = _life[idx];
              _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
              _flags[ni] = 1;
            }
          }
        }
        if (curSize >= 20 && _rng.nextInt(4) == 0) {
          for (final side in [x - 3, x + 3]) {
            if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
              final ni = y * _gridW + side;
              _grid[ni] = El.plant; _life[ni] = _life[idx];
              _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
              _flags[ni] = 1;
            }
          }
          if (curSize >= 23) {
            for (final side in [x - 4, x + 4]) {
              if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
                final ni = y * _gridW + side;
                _grid[ni] = El.plant; _life[ni] = _life[idx];
                _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
                _flags[ni] = 1;
              }
            }
          }
        }
      }
    }
  }

  void _growMushroom(int x, int y, int idx, int curSize) {
    // Mushroom: 2-3 tall, cap at top, spreads in wet soil
    if (curSize < 3) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        final newSize = curSize + 1;
        _setPlantData(ni, kPlantMushroom, newSize >= 2 ? kStMature : kStGrowing);
        _velY[ni] = newSize;
        _flags[ni] = 1;
        _velY[idx] = newSize;
      }
    }
    // Spread to nearby wet soil
    if (_rng.nextInt(80) == 0) {
      for (int r = 1; r <= 3; r++) {
        final sx = x + (_rng.nextBool() ? r : -r);
        final by = y + _gravityDir;
        if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty &&
            _inBounds(sx, by) && _grid[by * _gridW + sx] == El.dirt &&
            _life[by * _gridW + sx] >= 4) {
          final ni = y * _gridW + sx;
          _grid[ni] = El.plant; _life[ni] = _life[idx];
          _setPlantData(ni, kPlantMushroom, kStSprout); _velY[ni] = 1;
          _flags[ni] = 1;
          break;
        }
      }
    }
  }

  void _growVine(int x, int y, int idx, int curSize) {
    // Vine: climbs surfaces (dirt, stone, wood, metal)
    if (curSize < 12) {
      // Find adjacent solid surface to climb along
      final directions = <List<int>>[];
      // Prioritize upward, then sideways
      for (final d in [[-1, -_gravityDir], [1, -_gravityDir], [-1, 0], [1, 0], [0, -_gravityDir]]) {
        final nx = x + d[0]; final ny = y + d[1];
        if (!_inBounds(nx, ny)) continue;
        if (_grid[ny * _gridW + nx] != El.empty) continue;
        // Check if adjacent to a solid surface
        bool nearSolid = false;
        for (int dy2 = -1; dy2 <= 1; dy2++) {
          for (int dx2 = -1; dx2 <= 1; dx2++) {
            final sx = nx + dx2; final sy = ny + dy2;
            if (!_inBounds(sx, sy)) continue;
            final se = _grid[sy * _gridW + sx];
            if (se == El.dirt || se == El.stone || se == El.wood || se == El.metal) {
              nearSolid = true; break;
            }
          }
          if (nearSolid) break;
        }
        if (nearSolid) directions.add(d);
      }
      if (directions.isNotEmpty) {
        final d = directions[_rng.nextInt(directions.length)];
        final nx = x + d[0]; final ny = y + d[1];
        final ni = ny * _gridW + nx;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        _setPlantData(ni, kPlantVine, kStGrowing);
        _velY[ni] = (curSize + 1); _flags[ni] = 1;
        _velY[idx] = (curSize + 1);
      }
    }
  }

  void _simLava(int x, int y, int idx) {
    _life[idx]++;

    // Slowly cools into stone over time
    if (_life[idx] > 200 + _rng.nextInt(50)) {
      _grid[idx] = El.stone;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Check neighbor reactions
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];
        // Lava + Water → Stone + Steam (explosive evaporation)
        if (neighbor == El.water) {
          _grid[idx] = El.stone;
          _life[idx] = 0;
          _flags[idx] = 1;
          _grid[ni] = El.steam;
          _life[ni] = 0;
          _flags[ni] = 1;
          // Spawn 2-3 extra steam cells nearby (explosive evaporation)
          final extraSteam = 2 + _rng.nextInt(2);
          for (int s = 0; s < extraSteam; s++) {
            final sx = x + _rng.nextInt(5) - 2;
            final sy = y - _gravityDir * (1 + _rng.nextInt(2));
            if (_inBounds(sx, sy) && _grid[sy * _gridW + sx] == El.empty) {
              _grid[sy * _gridW + sx] = El.steam;
              _life[sy * _gridW + sx] = 0;
              _flags[sy * _gridW + sx] = 1;
            }
          }
          return;
        }
        // Lava + Ice → Stone + Water
        if (neighbor == El.ice) {
          _grid[idx] = El.stone;
          _life[idx] = 0;
          _flags[idx] = 1;
          _grid[ni] = El.water;
          _life[ni] = 0;
          _flags[ni] = 1;
          return;
        }
        // Ignite flammables
        if ((neighbor == El.plant || neighbor == El.seed ||
             neighbor == El.oil || neighbor == El.wood) &&
            _rng.nextInt(2) == 0) {
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Melt snow
        if (neighbor == El.snow) {
          _grid[ni] = El.water;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
      }
    }

    // Viscous flow — only every 2nd frame
    if (_frameCount.isOdd) return;

    final by = y + _gravityDir;
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }

    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
      _swap(idx, by * _gridW + x1);
      return;
    }
    if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
      _swap(idx, by * _gridW + x2);
      return;
    }

    // Slow sideways flow
    if (_inBounds(x1, y) && _grid[y * _gridW + x1] == El.empty) {
      _swap(idx, y * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y) && _grid[y * _gridW + x2] == El.empty) {
      _swap(idx, y * _gridW + x2);
    }
  }

  void _simSnow(int x, int y, int idx) {
    // Melt near fire or lava (slower at night — 50% chance to resist)
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      if (!_isNight || _rng.nextBool()) {
        _grid[idx] = El.water;
        _life[idx] = 0;
        _flags[idx] = 1;
        return;
      }
    }

    // Freeze adjacent water into ice (rarely)
    if (_rng.nextInt(30) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.water) {
            _grid[ny * _gridW + nx] = El.ice;
            _life[ny * _gridW + nx] = 0;
            _flags[ny * _gridW + nx] = 1;
            break;
          }
        }
      }
    }

    // Compression: 3+ snow "above" (opposite to gravity) → become ice
    final ug = -_gravityDir;
    int snowAbove = 0;
    for (int d = 1; d <= 4; d++) {
      final cy = y + ug * d;
      if (!_inBounds(x, cy)) break;
      if (_grid[cy * _gridW + x] == El.snow) {
        snowAbove++;
      } else {
        break;
      }
    }
    if (snowAbove >= 3) {
      _grid[idx] = El.ice;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Fall slowly (every 2nd frame), spread wider than sand
    if (_frameCount.isOdd) return;

    final by = y + _gravityDir;
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }

    // Spread wider — try 2 cells to each side
    final dl = _rng.nextBool();
    for (int d = 1; d <= 2; d++) {
      final sx1 = dl ? x - d : x + d;
      final sx2 = dl ? x + d : x - d;
      if (_inBounds(sx1, by) && _grid[by * _gridW + sx1] == El.empty) {
        _swap(idx, by * _gridW + sx1);
        return;
      }
      if (_inBounds(sx2, by) && _grid[by * _gridW + sx2] == El.empty) {
        _swap(idx, by * _gridW + sx2);
        return;
      }
    }
  }

  void _simWood(int x, int y, int idx) {
    // Wood is static — no gravity (unless waterlogged).
    // _life[idx]: 0 = dry, 1..40 = burning, velY used as waterlog counter (0..3)
    // _velY[idx]: waterlog level (0=dry, 1-3=absorbing, 3=waterlogged)

    // If life > 0, wood is burning (set by fire contact)
    if (_life[idx] > 0) {
      _life[idx]++;
      // Spread fire to adjacent wood (15% chance)
      if (_rng.nextInt(100) < 15) {
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            final ny = y + dy;
            if (!_inBounds(nx, ny)) continue;
            final ni = ny * _gridW + nx;
            if (_grid[ni] == El.wood && _life[ni] == 0) {
              _life[ni] = 1; // ignite neighbor
              break;
            }
          }
        }
      }
      // Burn out after ~40 frames → ash (smoke rises from burning)
      if (_life[idx] > 40 + _rng.nextInt(20)) {
        _grid[idx] = El.ash;
        _life[idx] = 0;
        _velY[idx] = 0;
        _flags[idx] = 1;
        // Spawn smoke above
        final uy = y - _gravityDir;
        if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
          _grid[uy * _gridW + x] = El.smoke;
          _life[uy * _gridW + x] = 0;
          _flags[uy * _gridW + x] = 1;
        }
      }
      return;
    }

    // Waterlogging: absorb adjacent water slowly
    if (_checkAdjacent(x, y, El.water) && _velY[idx] < 3) {
      if (_rng.nextInt(30) == 0) {
        _velY[idx] = (_velY[idx] + 1).clamp(0, 3).toInt();
        // Remove one adjacent water cell
        _removeOneAdjacent(x, y, El.water);
      }
    }

    // Waterlogged wood sinks through water
    if (_velY[idx] >= 3) {
      final by = y + _gravityDir;
      if (_inBounds(x, by)) {
        final bi = by * _gridW + x;
        if (_grid[bi] == El.water) {
          _grid[idx] = El.water;
          _life[idx] = 0;
          _grid[bi] = El.wood;
          _life[bi] = 0;
          _velY[bi] = 3; // keep waterlogged
          _flags[idx] = 1;
          _flags[bi] = 1;
          return;
        }
      }
    }

    // Check if adjacent fire should ignite this wood
    // Waterlogged wood is harder to ignite (1 in 5 chance vs always)
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      if (_velY[idx] < 3 || _rng.nextInt(5) == 0) {
        _life[idx] = 1; // start burning
        _velY[idx] = 0; // dry out when burning
      }
    }
  }

  void _simMetal(int x, int y, int idx) {
    // Skip if electrified (visual only, decays in _getElementColor)
    if (_life[idx] >= 200) return;

    // Rust: metal touching water slowly corrodes
    if (_checkAdjacent(x, y, El.water)) {
      _life[idx]++; // rust counter
      // After ~120 frames of water contact → crumble to dirt
      if (_life[idx] > 120) {
        _grid[idx] = El.dirt;
        _life[idx] = 0;
        _flags[idx] = 1;
        return;
      }
    }

    // Condensation: empty cell adjacent to metal+water → water (rare)
    if (_rng.nextInt(100) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.empty && _checkAdjacent(nx, ny, El.water)) {
            _grid[ni] = El.water;
            _life[ni] = 0;
            _flags[ni] = 1;
            return;
          }
        }
      }
    }
  }

  /// Flood-fill connected water body and electrify all cells.
  /// Destroys ants and plants in the electrified water.
  void _electrifyWater(int startX, int startY) {
    final visited = <int>{};
    final queue = <int>[startY * _gridW + startX];
    int count = 0;
    while (queue.isNotEmpty && count < 50) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (_grid[curIdx] != El.water) continue;
      _life[curIdx] = 200; // electrified visual
      _flags[curIdx] = 1;
      count++;
      final cx = curIdx % _gridW;
      final cy = curIdx ~/ _gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.water && !visited.contains(ni)) {
            queue.add(ni);
          } else if (_grid[ni] == El.ant || _grid[ni] == El.plant || _grid[ni] == El.seed) {
            // Destroy life in electrified water
            _grid[ni] = El.empty;
            _life[ni] = 0;
            _flags[ni] = 1;
          }
        }
      }
    }
    _lightningFlashFrames = 5;
  }

  /// Flood-fill connected metal and electrify neighbors.
  void _conductMetal(int startX, int startY) {
    final visited = <int>{};
    final queue = <int>[startY * _gridW + startX];
    int sparks = 0;
    while (queue.isNotEmpty && sparks < 30) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (_grid[curIdx] != El.metal) continue;
      _life[curIdx] = 200; // electrified visual
      final cx = curIdx % _gridW;
      final cy = curIdx ~/ _gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.metal && !visited.contains(ni)) {
            queue.add(ni);
          } else if (_grid[ni] == El.water) {
            _life[ni] = 200; // electrify water
            _flags[ni] = 1;
            sparks++;
          } else if (_grid[ni] == El.tnt) {
            _pendingExplosions.add(_Explosion(nx, ny, _calculateTNTRadius(nx, ny)));
            sparks++;
          } else if (_rng.nextInt(100) < 30) {
            // Spark reactions (30% chance)
            if (_grid[ni] == El.sand) {
              _grid[ni] = El.glass;
              _life[ni] = 0;
              _flags[ni] = 1;
              sparks++;
            } else if (_grid[ni] == El.ice) {
              _grid[ni] = El.water;
              _life[ni] = 150;
              _flags[ni] = 1;
              sparks++;
            } else if (_grid[ni] == El.plant || _grid[ni] == El.seed ||
                       _grid[ni] == El.oil || _grid[ni] == El.wood) {
              _grid[ni] = El.fire;
              _life[ni] = 0;
              _flags[ni] = 1;
              sparks++;
            }
          }
        }
      }
    }
    _lightningFlashFrames = 3;
  }

  void _simSmoke(int x, int y, int idx) {
    _life[idx]++;
    if (_life[idx] > 60) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }

    // Rise opposite to gravity with random drift
    final uy = y - _gravityDir;
    if (_inBounds(x, uy)) {
      final drift = _rng.nextInt(3) - 1;
      final nx = x + drift;
      if (_inBounds(nx, uy) && _grid[uy * _gridW + nx] == El.empty) {
        _swap(idx, uy * _gridW + nx);
        return;
      }
      if (_grid[uy * _gridW + x] == El.empty) {
        _swap(idx, uy * _gridW + x);
        return;
      }
    }
    // Drift sideways
    final side = _rng.nextBool() ? x - 1 : x + 1;
    if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
      _swap(idx, y * _gridW + side);
    }
  }

  void _simBubble(int x, int y, int idx) {
    _life[idx]++;

    // Check if in water
    final inWater = _checkAdjacent(x, y, El.water);
    final uy = y - _gravityDir; // "up" = opposite gravity

    if (inWater) {
      // Rise through water every 3 frames
      if (_life[idx] % 3 == 0 && _inBounds(x, uy)) {
        final ai = uy * _gridW + x;
        if (_grid[ai] == El.water) {
          _grid[ai] = El.bubble;
          _life[ai] = _life[idx];
          _grid[idx] = El.water;
          _life[idx] = 0;
          _flags[ai] = 1;
          _flags[idx] = 1;
          return;
        }
        // Reached surface — pop!
        if (_grid[ai] == El.empty) {
          _grid[idx] = El.empty;
          _life[idx] = 0;
          for (int i = 0; i < 2 + _rng.nextInt(2); i++) {
            final dx = _rng.nextInt(5) - 2;
            final dy = -_gravityDir * (_rng.nextInt(3) + 1);
            final nx = x + dx;
            final ny = y + dy;
            if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.empty) {
              _grid[ny * _gridW + nx] = El.water;
              _life[ny * _gridW + nx] = 0;
              _flags[ny * _gridW + nx] = 1;
            }
          }
          return;
        }
      }
    } else {
      if (_life[idx] > 30) {
        _grid[idx] = El.empty;
        _life[idx] = 0;
      }
    }
  }

  void _simAsh(int x, int y, int idx) {
    _life[idx]++;
    final g = _gravityDir;
    final by = y + g;

    // ── Interaction: ash on dirt = fertilizer ──────────────────────────
    if (_checkAdjacent(x, y, El.dirt)) {
      // Find the adjacent dirt cell and increase its moisture
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] == El.dirt) {
            _life[ni] = (_life[ni] + 1).clamp(0, 4); // increase moisture
            _grid[idx] = El.empty; // ash consumed
            _life[idx] = 0;
            _flags[idx] = 1;
            return;
          }
        }
      }
    }

    // ── Interaction: ash in water ──────────────────────────────────────
    final inWater = _checkAdjacent(x, y, El.water);
    if (inWater) {
      // _velX[idx] tracks water contact frames for ash
      _velX[idx] = (_velX[idx] + 1).clamp(0, 127).toInt();

      // Count surrounding water cells to estimate water body size
      int waterCount = 0;
      for (int dy2 = -3; dy2 <= 3; dy2++) {
        for (int dx2 = -3; dx2 <= 3; dx2++) {
          final nx = x + dx2;
          final ny = y + dy2;
          if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.water) {
            waterCount++;
          }
        }
      }

      final isLargeBody = waterCount > 20;

      if (isLargeBody) {
        // Large water body: dissipate after ~15 frames
        if (_velX[idx] > 15) {
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _velX[idx] = 0;
          return;
        }
      } else {
        // Small water body: float on surface ~30 frames, then sink slowly
        if (_velX[idx] < 30) {
          // Float — don't fall through water
          // Drift sideways
          if (_rng.nextInt(3) == 0) {
            final side = _rng.nextBool() ? x - 1 : x + 1;
            if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
              _swap(idx, y * _gridW + side);
            }
          }
          return;
        }
        // After floating, sink slowly (1 cell per 3 frames)
        if (_life[idx] % 3 == 0 && _inBounds(x, by)) {
          final bi = by * _gridW + x;
          if (_grid[bi] == El.water) {
            _grid[idx] = El.water;
            _grid[bi] = El.ash;
            _life[bi] = _life[idx];
            _velX[bi] = _velX[idx];
            _life[idx] = 0;
            _velX[idx] = 0;
            _flags[idx] = 1;
            _flags[bi] = 1;
            return;
          }
        }
      }
      return;
    } else {
      _velX[idx] = 0; // reset water contact timer when not in water
    }

    // ── Movement: very slow fall (1 cell per ~3 frames) ───────────────
    if (_life[idx] % 3 != 0) return;

    if (_inBounds(x, by)) {
      final below = by * _gridW + x;
      if (_grid[below] == El.empty) {
        _swap(idx, below);
        return;
      }
      // Float on water surface
      if (_grid[below] == El.water) {
        // Stay on top — don't fall through (handled above when in water)
        return;
      }
    }

    // Diagonal drift (wider than sand due to lightness)
    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
      _swap(idx, by * _gridW + x1);
      return;
    }
    if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
      _swap(idx, by * _gridW + x2);
      return;
    }

    // Extra sideways drift (ash is very floaty)
    if (_rng.nextInt(3) == 0) {
      final sx = _rng.nextBool() ? x - 1 : x + 1;
      if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty) {
        _swap(idx, y * _gridW + sx);
      }
    }
  }

  void _simTNT(int x, int y, int idx) {
    _fallGranular(x, y, idx, El.tnt);
  }

  /// Calculate TNT explosion radius based on cluster size (chain reactions).
  int _calculateTNTRadius(int cx, int cy) {
    int count = 0;
    final visited = <int>{};
    final queue = <int>[cy * _gridW + cx];
    while (queue.isNotEmpty && count < 50) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (_grid[curIdx] != El.tnt) continue;
      count++;
      final qx = curIdx % _gridW;
      final qy = curIdx ~/ _gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = qx + dx;
          final ny = qy + dy;
          if (_inBounds(nx, ny)) queue.add(ny * _gridW + nx);
        }
      }
    }
    // Base radius 6, +2 per additional TNT block
    return (6 + (count - 1) * 2).clamp(6, 30);
  }

  void _simRainbow(int x, int y, int idx) {
    final uy = y - _gravityDir;
    if (_rng.nextInt(3) == 0 && _inBounds(x, uy)) {
      if (_grid[uy * _gridW + x] == El.empty) {
        _swap(idx, uy * _gridW + x);
        _life[idx] = (_life[idx] + 1) % 255;
        return;
      }
      final side = _rng.nextBool() ? x - 1 : x + 1;
      if (_inBounds(side, uy) &&
          _grid[uy * _gridW + side] == El.empty) {
        _swap(idx, uy * _gridW + side);
      }
    }
    _life[idx] = (_life[idx] + 1) % 255;
  }

  void _simMud(int x, int y, int idx) {
    if (_frameCount.isOdd) return;
    _fallGranular(x, y, idx, El.mud);
  }

  void _simSteam(int x, int y, int idx) {
    _life[idx]++;
    final uy = y - _gravityDir;
    final atEdge = _gravityDir == 1 ? y <= 2 : y >= _gridH - 3;
    // Steam condenses faster at night (half lifetime)
    final steamLife = _isNight ? 40 + _rng.nextInt(20) : 80 + _rng.nextInt(40);
    if (atEdge || _life[idx] > steamLife) {
      // At night, steam is more likely to condense back to water
      final waterChance = _isNight ? 2 : 3;
      _grid[idx] = _rng.nextInt(waterChance) == 0 ? El.water : El.empty;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Condensation: steam touching water → back to water (night: 2x faster)
    final condenseChance = _isNight ? 15 : 30;
    if (_rng.nextInt(condenseChance) == 0 && _checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.water;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    if (_inBounds(x, uy)) {
      final drift = _rng.nextInt(3) - 1;
      final nx = x + drift;
      if (_inBounds(nx, uy) && _grid[uy * _gridW + nx] == El.empty) {
        _swap(idx, uy * _gridW + nx);
        return;
      }
      if (_grid[uy * _gridW + x] == El.empty) {
        _swap(idx, uy * _gridW + x);
        return;
      }
    }
    final side = _rng.nextBool() ? x - 1 : x + 1;
    if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
      _swap(idx, y * _gridW + side);
    }
  }

  // Ant states stored in _velY:
  //   0 = explorer (searching for dirt to dig)
  //   1 = digger (actively tunneling into dirt)
  //   2 = carrier (carrying dirt to surface to build mound)
  //   3 = returning (heading back to colony after depositing)
  //   4 = forager (found a seed, carrying it to moist dirt to plant)
  //  10+ = drowning counter (in water)
  // _life stores "home X" coordinate (0-159) so ants remember their colony.
  // _velX stores movement direction (-1 or 1).
  //
  // Pheromone system: for EMPTY cells, _life[idx] stores pheromone intensity
  // (0-255). Ants deposit pheromones as they walk; they evaporate over time.
  // Carriers deposit stronger pheromones (~200) than explorers (~100).
  //
  // Colony organization: for DIRT cells at tunnel entrances, _life values
  // of 250 mark entrance points so returning ants can find tunnels.

  /// Check if a cell is "underground" (has solid above it, toward surface).
  bool _isUnderground(int x, int y) {
    final g = _gravityDir;
    final aboveY = y - g;
    if (!_inBounds(x, aboveY)) return false;
    final above = _grid[aboveY * _gridW + x];
    return above == El.dirt || above == El.mud || above == El.stone ||
           above == El.sand || above == El.ant;
  }

  void _simAnt(int x, int y, int idx) {
    if (_frameCount % 2 != 0) return;

    final g = _gravityDir;
    final by = y + g;
    final uy = y - g;
    int state = _velY[idx];
    final homeX = _life[idx]; // colony X position

    // ── Hazards ──────────────────────────────────────────────────────

    // Acid kills instantly
    if (_checkAdjacent(x, y, El.acid)) {
      _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      return;
    }

    // Fire — flee (search 5 cells in all directions) or die
    if (_checkAdjacent(x, y, El.fire)) {
      int bestDist = 999;
      int bestIdx = -1;
      for (int dy = -5; dy <= 5; dy++) {
        for (int dx = -5; dx <= 5; dx++) {
          final nx2 = x + dx, ny2 = y + dy;
          if (!_inBounds(nx2, ny2)) continue;
          final dist = dx.abs() + dy.abs();
          if (dist >= bestDist) continue;
          if (_grid[ny2 * _gridW + nx2] == El.empty && !_checkAdjacent(nx2, ny2, El.fire)) {
            bestDist = dist;
            bestIdx = ny2 * _gridW + nx2;
          }
        }
      }
      if (bestIdx >= 0) {
        // Move one step toward safe cell
        final safeX = bestIdx % _gridW;
        final safeY = bestIdx ~/ _gridW;
        final stepX = (safeX - x).sign;
        final stepY = (safeY - y).sign;
        final nx2 = x + stepX;
        final ny2 = y + stepY;
        if (_inBounds(nx2, ny2) && _grid[ny2 * _gridW + nx2] == El.empty) {
          _swap(idx, ny2 * _gridW + nx2);
          return;
        }
        if (_inBounds(nx2, y) && _grid[y * _gridW + nx2] == El.empty) {
          _swap(idx, y * _gridW + nx2);
          return;
        }
        if (_inBounds(x, ny2) && _grid[ny2 * _gridW + x] == El.empty) {
          _swap(idx, ny2 * _gridW + x);
          return;
        }
      }
      _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      return;
    }

    // Drowning in water — swim toward nearest surface
    if (_checkAdjacent(x, y, El.water)) {
      if (state < 10) {
        _velY[idx] = 10; // enter drowning state
        state = 10;
      }
      // Actively swim upward toward surface (check cells above, prefer empty)
      if (_inBounds(x, uy)) {
        final ac = _grid[uy * _gridW + x];
        if (ac == El.empty) { _swap(idx, uy * _gridW + x); return; }
        if (ac == El.water && _rng.nextInt(2) == 0) { _swap(idx, uy * _gridW + x); return; }
      }
      // Try diagonal up — find closest path to surface
      for (final dir in [1, -1]) {
        final sx = x + dir;
        if (_inBounds(sx, uy)) {
          final diagCell = _grid[uy * _gridW + sx];
          if (diagCell == El.empty) { _swap(idx, uy * _gridW + sx); return; }
          if (diagCell == El.water && _rng.nextInt(2) == 0) { _swap(idx, uy * _gridW + sx); return; }
        }
      }
      // Try sideways escape to empty cell
      for (final dir in [1, -1]) {
        final sx = x + dir;
        if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty) {
          _swap(idx, y * _gridW + sx); return;
        }
      }
      _velY[idx] = (state + 1);
      if (_velY[idx] > 100) {
        _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      }
      return;
    }
    // Exited water — restore previous state
    if (state >= 10) { _velY[idx] = 0; state = 0; }

    // ── Initialize home position ──────────────────────────────────────
    if (_life[idx] == 0) {
      // New ant — set home X to current position
      _life[idx] = x.clamp(1, 255);
    }
    if (_velX[idx] == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;

    // ── Gravity — fall if no ground ───────────────────────────────────
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }

    // ── STATE MACHINE ─────────────────────────────────────────────────

    final underground = _isUnderground(x, y);
    final nearDirt = _checkAdjacent(x, y, El.dirt);

    // Deposit pheromones: leave a trail on the cell we just came from
    // Carriers/foragers leave stronger pheromones for others to follow
    _antDepositPheromone(x, y, state);

    switch (state) {
      case 0: // EXPLORER — search for dirt to dig
        _antExplore(x, y, idx, homeX, nearDirt, underground);
      case 1: // DIGGER — tunnel into dirt, pick up material
        _antDig(x, y, idx, underground);
      case 2: // CARRIER — bring dirt to surface, build mound
        _antCarry(x, y, idx, homeX);
      case 3: // RETURNING — head back to colony entrance, then explore again
        _antReturn(x, y, idx, homeX);
      case 4: // FORAGER — carrying a seed to plant in moist dirt
        _antForage(x, y, idx, homeX);
    }
  }

  void _antExplore(int x, int y, int idx, int homeX, bool nearDirt, bool underground) {
    final dir = _velX[idx];

    // Check for nearby seeds — switch to forager if found within 5 cells
    for (int scanD = 1; scanD <= 5; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!_inBounds(sx, y)) continue;
        if (_grid[y * _gridW + sx] == El.seed) {
          // Pick up the seed
          _grid[y * _gridW + sx] = El.empty;
          _life[y * _gridW + sx] = 0;
          _velY[idx] = 4; // switch to forager
          _velX[idx] = sd;
          return;
        }
        // Also check one row below for seeds
        final sy = y + _gravityDir;
        if (_inBounds(sx, sy) && _grid[sy * _gridW + sx] == El.seed) {
          _grid[sy * _gridW + sx] = El.empty;
          _life[sy * _gridW + sx] = 0;
          _velY[idx] = 4;
          _velX[idx] = sd;
          return;
        }
      }
    }

    // If adjacent to dirt and not too many ants nearby, start digging
    if (nearDirt && _rng.nextInt(4) == 0) {
      // Crowd avoidance: count nearby ants in 3-cell radius
      int nearbyAnts = 0;
      for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
          if (_inBounds(x + dx, y + dy) && _grid[(y + dy) * _gridW + (x + dx)] == El.ant) nearbyAnts++;
        }
      }
      if (nearbyAnts < 3) {
        _velY[idx] = 1; // switch to digger
        return;
      }
    }

    // Scan for dirt, pheromone trails, and hazards
    int targetDir = dir;
    bool foundTarget = false;
    int bestPheromone = 0;
    int pheromoneDir = 0;

    for (int scanD = 1; scanD <= 8; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!_inBounds(sx, y)) continue;
        final si = y * _gridW + sx;
        final sc = _grid[si];
        if (sc == El.dirt || sc == El.mud) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        // Follow pheromone trails (empty cells with pheromone > 0)
        if (sc == El.empty && _life[si] > bestPheromone) {
          bestPheromone = _life[si];
          pheromoneDir = sd;
        }
        // Also follow other ants (social behavior)
        if (sc == El.ant && _rng.nextInt(3) == 0) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        // Hazard avoidance: look 2 cells ahead for dangers
        if (sc == El.water || sc == El.acid || sc == El.fire) {
          if (sd == dir) targetDir = -dir;
          break;
        }
        // Lava has larger avoidance radius
        if (sc == El.lava) {
          if (sd == dir) targetDir = -dir;
          foundTarget = true;
          break;
        }
      }
      if (foundTarget) break;
    }

    // If no dirt found but pheromone trail exists, follow it
    if (!foundTarget && bestPheromone > 20 && pheromoneDir != 0 && _rng.nextInt(3) != 0) {
      targetDir = pheromoneDir;
    }

    _antMove(x, y, idx, targetDir);
  }

  void _antDig(int x, int y, int idx, bool underground) {
    final g = _gravityDir;
    final by = y + g;
    final dir = _velX[idx];

    // Prefer to use existing tunnels (follow pheromone trails) instead of
    // digging new ones — check if there's a strong trail to follow
    if (_rng.nextInt(3) == 0) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd;
        if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty) {
          final pheromone = _life[y * _gridW + sx];
          if (pheromone > 50) {
            // Follow existing tunnel instead of digging new one
            _velX[idx] = sd;
            _swap(idx, y * _gridW + sx);
            return;
          }
        }
      }
    }

    // Try to dig downward first (create vertical shafts)
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.dirt) {
      if (_rng.nextInt(3) == 0) {
        // Mark entrance if this is near the surface (tunnel entrance marker)
        final aboveY = y - g;
        if (_inBounds(x, aboveY) && _grid[aboveY * _gridW + x] == El.empty) {
          // This dirt cell borders the surface — mark adjacent dirt as entrance
          for (final edx in [-1, 1]) {
            final ex = x + edx;
            if (_inBounds(ex, y) && _grid[y * _gridW + ex] == El.dirt) {
              _life[y * _gridW + ex] = 250; // entrance marker
            }
          }
        }
        _grid[by * _gridW + x] = El.empty;
        _life[by * _gridW + x] = 0;
        _swap(idx, by * _gridW + x);
        _velY[idx] = 2; // picked up dirt, now carry it
        return;
      }
    }

    // Dig sideways (create horizontal tunnels)
    final nx = x + dir;
    if (_inBounds(nx, y) && _grid[y * _gridW + nx] == El.dirt) {
      if (_rng.nextInt(4) == 0) {
        _grid[y * _gridW + nx] = El.empty;
        _life[y * _gridW + nx] = 0;
        _swap(idx, y * _gridW + nx);
        _velY[idx] = 2; // carrying dirt
        return;
      }
    }

    // Dig diagonally down (creates branching tunnels)
    if (_inBounds(nx, by) && _grid[by * _gridW + nx] == El.dirt && _rng.nextInt(5) == 0) {
      _grid[by * _gridW + nx] = El.empty;
      _life[by * _gridW + nx] = 0;
      _swap(idx, by * _gridW + nx);
      _velY[idx] = 2; // carrying dirt
      return;
    }

    // Create chambers — occasionally dig a wider space
    if (underground && _rng.nextInt(12) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final cx = x + dx, cy = y + dy;
          if (_inBounds(cx, cy) && _grid[cy * _gridW + cx] == El.dirt) {
            _grid[cy * _gridW + cx] = El.empty;
            _life[cy * _gridW + cx] = 0;
          }
        }
      }
    }

    // No dirt to dig — either explore for more or switch to carrier
    if (!_checkAdjacent(x, y, El.dirt)) {
      _velY[idx] = 0; // back to explorer
    }

    _antMove(x, y, idx, dir);
  }

  void _antCarry(int x, int y, int idx, int homeX) {
    final g = _gravityDir;
    final uy = y - g;

    // Head toward surface (move upward)
    if (_inBounds(x, uy)) {
      final aboveCell = _grid[uy * _gridW + x];
      if (aboveCell == El.empty) {
        _swap(idx, uy * _gridW + x);
        return;
      }
    }

    // At surface or can't go higher — deposit dirt
    final atSurface = !_inBounds(x, uy) ||
        (_grid[uy * _gridW + x] == El.empty && !_isUnderground(x, y));

    if (atSurface || !_inBounds(x, uy)) {
      // Structured mound building: prefer to deposit next to existing dirt
      // to create a cohesive mound shape rather than scattered deposits
      final depositY = uy;
      final toHome = (homeX - x).sign;

      int bestX = -1;
      int bestScore = -1;
      for (final depositX in [x + toHome, x, x - toHome, x + toHome * 2, x - toHome * 2]) {
        if (!_inBounds(depositX, depositY) || _grid[depositY * _gridW + depositX] != El.empty) continue;
        int score = 0;
        for (int ddx = -1; ddx <= 1; ddx++) {
          final checkX = depositX + ddx;
          if (_inBounds(checkX, depositY) && _grid[depositY * _gridW + checkX] == El.dirt) score += 3;
          final checkBelow = depositY + g;
          if (_inBounds(checkX, checkBelow) && _grid[checkBelow * _gridW + checkX] == El.dirt) score += 5;
        }
        score += (5 - (depositX - homeX).abs().clamp(0, 5));
        if (score > bestScore) {
          bestScore = score;
          bestX = depositX;
        }
      }

      if (bestX >= 0) {
        _grid[depositY * _gridW + bestX] = El.dirt;
        _life[depositY * _gridW + bestX] = 0;
        _velY[idx] = 3; // switch to returning
        return;
      }

      // Fallback: try sideways
      for (final dx in [1, -1]) {
        final sx = x + dx;
        if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty) {
          _grid[y * _gridW + sx] = El.dirt;
          _life[y * _gridW + sx] = 0;
          _velY[idx] = 3;
          return;
        }
      }
      // Stuck with dirt — just drop state
      _velY[idx] = 0;
      return;
    }

    // Move toward home X while heading up
    final toHome = (homeX - x).sign;
    final moveDir = toHome != 0 ? toHome : _velX[idx];
    _antMove(x, y, idx, moveDir);
  }

  void _antReturn(int x, int y, int idx, int homeX) {
    final g = _gravityDir;
    final by = y + g;

    // Head back toward home X and down into the colony
    final toHome = (homeX - x).sign;

    // If near home X, head back underground
    if ((x - homeX).abs() <= 3) {
      // Try to go down into the tunnels
      if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
        _swap(idx, by * _gridW + x);
        _velY[idx] = 0; // back to explorer once underground
        return;
      }
      // Look for a tunnel entrance nearby — check for entrance markers (life==250)
      for (final dx in [0, 1, -1, 2, -2, 3, -3]) {
        final tx = x + dx;
        // Check for entrance-marked dirt cells
        if (_inBounds(tx, y) && _grid[y * _gridW + tx] == El.dirt && _life[y * _gridW + tx] == 250) {
          // Found an entrance marker — move toward it
          if (dx != 0) {
            final moveToward = dx.sign;
            final mx = x + moveToward;
            if (_inBounds(mx, y) && _grid[y * _gridW + mx] == El.empty) {
              _swap(idx, y * _gridW + mx);
              return;
            }
          }
        }
        if (_inBounds(tx, by) && _grid[by * _gridW + tx] == El.empty) {
          if (_inBounds(tx, y) && _grid[y * _gridW + tx] == El.empty) {
            _swap(idx, y * _gridW + tx);
            return;
          }
        }
      }
      _velY[idx] = 0; // can't find tunnel, explore again
      return;
    }

    // Follow pheromone trails back toward home
    int moveDir = toHome != 0 ? toHome : _velX[idx];
    // Check if there's a strong pheromone trail to follow
    for (final sd in [toHome, -toHome]) {
      if (sd == 0) continue;
      final sx = x + sd;
      if (_inBounds(sx, y) && _grid[y * _gridW + sx] == El.empty) {
        final pheromone = _life[y * _gridW + sx];
        if (pheromone > 80) {
          moveDir = sd;
          break;
        }
      }
    }
    _antMove(x, y, idx, moveDir);
  }

  /// Shared ant movement: walk, climb, wall-follow, hazard-avoid.
  void _antMove(int x, int y, int idx, int moveDir) {
    final g = _gravityDir;
    final uy = y - g;
    final by = y + g;
    final nx = x + moveDir;

    // Hazard lookahead: check 2 cells ahead for fire/acid/lava
    for (int look = 1; look <= 2; look++) {
      final lx = x + moveDir * look;
      if (!_inBounds(lx, y)) break;
      final lookCell = _grid[y * _gridW + lx];
      if (lookCell == El.fire || lookCell == El.acid) {
        _velX[idx] = -moveDir;
        // Try to move away
        final escX = x - moveDir;
        if (_inBounds(escX, y) && _grid[y * _gridW + escX] == El.empty) {
          _swap(idx, y * _gridW + escX);
        }
        return;
      }
      // Lava has larger avoidance — treat any lava within 2 cells as danger
      if (lookCell == El.lava) {
        _velX[idx] = -moveDir;
        final escX = x - moveDir;
        if (_inBounds(escX, y) && _grid[y * _gridW + escX] == El.empty) {
          _swap(idx, y * _gridW + escX);
        }
        return;
      }
    }
    // Also check lava diagonally (larger avoidance radius)
    for (int dy = -2; dy <= 2; dy++) {
      for (int ddx = -2; ddx <= 2; ddx++) {
        if (ddx == 0 && dy == 0) continue;
        final lx = x + ddx, ly = y + dy;
        if (_inBounds(lx, ly) && _grid[ly * _gridW + lx] == El.lava) {
          // Move away from lava
          _velX[idx] = ddx > 0 ? -1 : 1;
          final escX = x + _velX[idx];
          if (_inBounds(escX, y) && _grid[y * _gridW + escX] == El.empty) {
            _swap(idx, y * _gridW + escX);
          }
          return;
        }
      }
    }

    // Walk along surface
    if (_inBounds(nx, y) && _grid[y * _gridW + nx] == El.empty) {
      _velX[idx] = moveDir;
      _swap(idx, y * _gridW + nx);
      return;
    }

    // Step up 1 cell (climb over obstacle)
    if (_inBounds(nx, uy) && _grid[uy * _gridW + nx] == El.empty) {
      _velX[idx] = moveDir;
      _swap(idx, uy * _gridW + nx);
      return;
    }

    // Wall climb straight up
    if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
      if (!_inBounds(nx, y) || _grid[y * _gridW + nx] != El.empty) {
        _swap(idx, uy * _gridW + x);
        return;
      }
    }

    // Wall following: instead of random reversal, try to follow the wall
    // Try going down along the wall (clockwise/counterclockwise)
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }
    // Try the opposite side going up
    final ox = x - moveDir;
    if (_inBounds(ox, uy) && _grid[uy * _gridW + ox] == El.empty) {
      _velX[idx] = -moveDir;
      _swap(idx, uy * _gridW + ox);
      return;
    }

    // Truly blocked — reverse direction
    _velX[idx] = -moveDir;
    if (_rng.nextInt(6) == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;
  }

  /// Deposit pheromones on adjacent empty cells as the ant walks.
  /// Carriers and foragers deposit stronger pheromones (~200) than explorers (~100).
  void _antDepositPheromone(int x, int y, int state) {
    final intensity = (state == 2 || state == 4) ? 200 : (state == 3 ? 150 : 100);
    // Deposit on current position's neighboring empty cells
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        if (_grid[ni] == El.empty && _life[ni] < intensity) {
          _life[ni] = intensity;
        }
      }
    }
  }

  /// Forager behavior: carry a seed to moist dirt and plant it.
  void _antForage(int x, int y, int idx, int homeX) {
    final g = _gravityDir;
    final dir = _velX[idx];

    // Search for moist dirt (moisture >= 2) within scanning range
    int bestDx = 0;
    int bestDy = 0;
    int bestDist = 999;
    for (int scanY = -5; scanY <= 5; scanY++) {
      for (int scanX = -5; scanX <= 5; scanX++) {
        final nx = x + scanX, ny = y + scanY;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        if (_grid[ni] == El.dirt && _life[ni] >= 2) {
          // Found moist dirt — check if there's an empty cell adjacent to it
          for (int pdy = -1; pdy <= 1; pdy++) {
            for (int pdx = -1; pdx <= 1; pdx++) {
              final px = nx + pdx, py = ny + pdy;
              if (!_inBounds(px, py)) continue;
              if (_grid[py * _gridW + px] == El.empty) {
                final dist = (px - x).abs() + (py - y).abs();
                if (dist < bestDist) {
                  bestDist = dist;
                  bestDx = (px - x).sign;
                  bestDy = (py - y).sign;
                }
              }
            }
          }
        }
      }
    }

    // If we're adjacent to moist dirt, plant the seed
    if (bestDist <= 2) {
      for (int pdy = -1; pdy <= 1; pdy++) {
        for (int pdx = -1; pdx <= 1; pdx++) {
          final px = x + pdx, py = y + pdy;
          if (!_inBounds(px, py)) continue;
          final pi = py * _gridW + px;
          if (_grid[pi] == El.empty) {
            // Check if this empty cell is adjacent to moist dirt
            bool nearMoistDirt = false;
            for (int cdy = -1; cdy <= 1; cdy++) {
              for (int cdx = -1; cdx <= 1; cdx++) {
                final cx = px + cdx, cy = py + cdy;
                if (!_inBounds(cx, cy)) continue;
                final ci = cy * _gridW + cx;
                if (_grid[ci] == El.dirt && _life[ci] >= 2) {
                  nearMoistDirt = true;
                  break;
                }
              }
              if (nearMoistDirt) break;
            }
            if (nearMoistDirt) {
              _grid[pi] = El.seed;
              _life[pi] = 0;
              _velY[idx] = 0; // back to explorer
              return;
            }
          }
        }
      }
    }

    // Move toward the best target
    if (bestDist < 999) {
      final moveDir = bestDx != 0 ? bestDx : dir;
      _antMove(x, y, idx, moveDir);
      return;
    }

    // No moist dirt found — wander toward home area
    final toHome = (homeX - x).sign;
    final moveDir = toHome != 0 ? toHome : dir;
    _antMove(x, y, idx, moveDir);

    // If wandering too long without finding moist dirt, drop the seed
    // (Use a probabilistic timeout — 1 in 60 chance per step)
    if (_rng.nextInt(60) == 0) {
      // Drop seed at current position if empty neighbor exists
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (!_inBounds(nx, ny)) continue;
          if (_grid[ny * _gridW + nx] == El.empty) {
            _grid[ny * _gridW + nx] = El.seed;
            _life[ny * _gridW + nx] = 0;
            _velY[idx] = 0; // back to explorer
            return;
          }
        }
      }
    }
  }

  void _simOil(int x, int y, int idx) {
    // Oil burns when near fire
    if (_checkAdjacent(x, y, El.fire)) {
      _grid[idx] = El.fire;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Fall through empty
    final by = y + _gravityDir;
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }

    // Float on water: if oil is sitting ON water (water is above), rise upward
    final uy = y - _gravityDir;
    if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.water && _flags[uy * _gridW + x] != 1) {
      final ui = uy * _gridW + x;
      _grid[ui] = El.oil;
      _life[ui] = _life[idx];
      _grid[idx] = El.water;
      _life[idx] = 0;
      _flags[ui] = 1;
      _flags[idx] = 1;
      return;
    }

    // Diagonal fall
    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
      _swap(idx, by * _gridW + x1);
      return;
    }
    if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
      _swap(idx, by * _gridW + x2);
      return;
    }

    // Flow sideways like water but slower
    if (_frameCount.isEven) {
      if (_inBounds(x1, y) && _grid[y * _gridW + x1] == El.empty) {
        _swap(idx, y * _gridW + x1);
        return;
      }
      if (_inBounds(x2, y) && _grid[y * _gridW + x2] == El.empty) {
        _swap(idx, y * _gridW + x2);
      }
    }
  }

  void _simAcid(int x, int y, int idx) {
    _life[idx]++;

    // Acid dissolves over time
    if (_life[idx] > 120 + _rng.nextInt(60)) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }

    // Check for reactions with neighbors
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];

        // Dissolve stone slowly
        if (neighbor == El.stone && _rng.nextInt(15) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Dissolve glass
        if (neighbor == El.glass && _rng.nextInt(10) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Kill ants
        if (neighbor == El.ant) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Mix with water — dilutes
        if (neighbor == El.water && _rng.nextInt(8) == 0) {
          _grid[idx] = El.water;
          _life[idx] = 0;
          _flags[idx] = 1;
          return;
        }
        // Dissolve plant/seed
        if ((neighbor == El.plant || neighbor == El.seed) && _rng.nextInt(3) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        // Dissolve wood slowly
        if (neighbor == El.wood && _rng.nextInt(12) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Acid in water generates bubbles
        if (neighbor == El.water && _rng.nextInt(20) == 0) {
          _grid[ni] = El.bubble;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
      }
    }

    // Flow like water
    final by = y + _gravityDir;
    if (_inBounds(x, by) && _grid[by * _gridW + x] == El.empty) {
      _swap(idx, by * _gridW + x);
      return;
    }

    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, by) && _grid[by * _gridW + x1] == El.empty) {
      _swap(idx, by * _gridW + x1);
      return;
    }
    if (_inBounds(x2, by) && _grid[by * _gridW + x2] == El.empty) {
      _swap(idx, by * _gridW + x2);
      return;
    }

    if (_inBounds(x1, y) && _grid[y * _gridW + x1] == El.empty) {
      _swap(idx, y * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y) && _grid[y * _gridW + x2] == El.empty) {
      _swap(idx, y * _gridW + x2);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _fallGranular(int x, int y, int idx, int elType) {
    final by = y + _gravityDir;
    if (_inBounds(x, by)) {
      final below = by * _gridW + x;
      final belowEl = _grid[below];
      if (belowEl == El.empty) {
        _swap(idx, below);
        return;
      }
      // Sink through water — with splash effect
      if ((elType == El.sand || elType == El.dirt || elType == El.seed) && belowEl == El.water) {
        _grid[idx] = El.water;
        _grid[below] = elType;
        _flags[idx] = 1;
        _flags[below] = 1;
        // Splash: convert 1-2 water cells above impact to bubble (visual splash)
        if (_rng.nextInt(3) == 0) {
          final splashCount = 1 + _rng.nextInt(2);
          for (int s = 0; s < splashCount; s++) {
            final sy = y - _gravityDir * (s + 1);
            final sx = x + _rng.nextInt(3) - 1;
            if (_inBounds(sx, sy)) {
              final si = sy * _gridW + sx;
              if (_grid[si] == El.water) {
                _grid[si] = El.bubble;
                _life[si] = 0;
                _flags[si] = 1;
              }
            }
          }
        }
        return;
      }
    }

    final goLeft = _rng.nextBool();
    final x1 = goLeft ? x - 1 : x + 1;
    final x2 = goLeft ? x + 1 : x - 1;
    if (_inBounds(x, by)) {
      if (_inBounds(x1, by) &&
          _grid[by * _gridW + x1] == El.empty) {
        _swap(idx, by * _gridW + x1);
        return;
      }
      if (_inBounds(x2, by) &&
          _grid[by * _gridW + x2] == El.empty) {
        _swap(idx, by * _gridW + x2);
        return;
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _swap(int a, int b) {
    final tmpEl = _grid[a];
    final tmpLife = _life[a];
    final tmpVx = _velX[a];
    final tmpVy = _velY[a];

    _grid[a] = _grid[b];
    _life[a] = _life[b];
    _velX[a] = _velX[b];
    _velY[a] = _velY[b];

    _grid[b] = tmpEl;
    _life[b] = tmpLife;
    _velX[b] = tmpVx;
    _velY[b] = tmpVy;

    _flags[a] = 1;
    _flags[b] = 1;
  }

  // Inlined for hot-path performance — avoid function call overhead.
  @pragma('vm:prefer-inline')
  bool _inBounds(int x, int y) =>
      x >= 0 && x < _gridW && y >= 0 && y < _gridH;

  /// Optimized 8-neighbor check. Unrolled for performance.
  @pragma('vm:prefer-inline')
  bool _checkAdjacent(int x, int y, int elType) {
    final w = _gridW;
    final g = _grid;
    final maxX = w - 1;
    final maxY = _gridH - 1;
    // Unrolled: check all 8 neighbors without loop overhead
    if (y > 0) {
      final rowAbove = (y - 1) * w;
      if (x > 0    && g[rowAbove + x - 1] == elType) return true;
                       if (g[rowAbove + x]     == elType) return true;
      if (x < maxX && g[rowAbove + x + 1] == elType) return true;
    }
    if (x > 0    && g[y * w + x - 1] == elType) return true;
    if (x < maxX && g[y * w + x + 1] == elType) return true;
    if (y < maxY) {
      final rowBelow = (y + 1) * w;
      if (x > 0    && g[rowBelow + x - 1] == elType) return true;
                       if (g[rowBelow + x]     == elType) return true;
      if (x < maxX && g[rowBelow + x + 1] == elType) return true;
    }
    return false;
  }

  void _removeOneAdjacent(int x, int y, int elType) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (_inBounds(nx, ny)) {
          final ni = ny * _gridW + nx;
          if (_grid[ni] == elType) {
            _grid[ni] = El.empty;
            _life[ni] = 0;
            _flags[ni] = 1;
            return;
          }
        }
      }
    }
  }

  void _processExplosions() {
    for (final exp in _pendingExplosions) {
      final r = exp.radius;
      for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > r * r) continue;
          final nx = exp.x + dx;
          final ny = exp.y + dy;
          if (!_inBounds(nx, ny)) continue;
          final ni = ny * _gridW + nx;
          if (_grid[ni] != El.stone && _grid[ni] != El.glass && _grid[ni] != El.metal) {
            _grid[ni] = El.empty;
            _life[ni] = 0;
          }
        }
      }
      // Create some fire around the edges
      for (int i = 0; i < r * 4; i++) {
        final angle = _rng.nextDouble() * 2 * pi;
        final dist = r * 0.6 + _rng.nextDouble() * r * 0.5;
        final fx = exp.x + (cos(angle) * dist).round();
        final fy = exp.y + (sin(angle) * dist).round();
        if (_inBounds(fx, fy)) {
          final fi = fy * _gridW + fx;
          if (_grid[fi] == El.empty) {
            _grid[fi] = El.fire;
            _life[fi] = 0;
          }
        }
      }
    }
    _pendingExplosions.clear();
  }

  // ── Pixel rendering ─────────────────────────────────────────────────────

  void _renderPixels() {
    final total = _gridW * _gridH;
    final w = _gridW;
    final h = _gridH;
    final g = _grid;
    final t = _dayNightT;

    // Pre-computed background colors
    final bgR = (10 - t * 6).round().clamp(0, 255);
    final bgG = (10 - t * 6).round().clamp(0, 255);
    final bgB = (26 - t * 10).round().clamp(0, 255);

    // Night glow multiplier for fire/lava halos
    final glowMul = 1.0 + t * 1.5;
    final glowIntR = (12 * glowMul).round();
    final glowIntG = (4 * glowMul).round();

    // Star set for quick lookup (only at night)
    final starSet = t > 0.05 ? Set<int>.from(_starPositions) : <int>{};

    // Pre-compute glow only every 3rd frame (fire moves slowly)
    final doGlow = _frameCount % 3 == 0;

    // Pre-compute integer night factors (avoid per-pixel float math)
    final nightBoost = (t * 30).round();
    final nightBoostG = (nightBoost * 0.2).round();
    final nightShimmer = (t * 50).round();
    final nightSmokeBoost = (t * 20).round();
    // Fixed-point 8-bit: 256 = 1.0, so (1-dim)*256
    final nightDimWater = (256 * (1.0 - t * 0.15)).round();
    final nightDimGeneral = (256 * (1.0 - t * 0.2)).round();

    for (int i = 0; i < total; i++) {
      final el = g[i];
      final pi4 = i * 4;
      if (el == El.empty) {
        // Lightweight glow check: only check cardinal neighbors (4 not 8)
        int glowR = 0, glowG = 0;
        if (doGlow) {
          final x = i % w;
          final y = i ~/ w;
          // Check 4 cardinal neighbors only (much faster than 8)
          if (y > 0)     { final n = g[i - w]; if (n == El.fire || n == El.lava) { glowR += glowIntR; if (n == El.fire) glowG += glowIntG; } }
          if (y < h - 1) { final n = g[i + w]; if (n == El.fire || n == El.lava) { glowR += glowIntR; if (n == El.fire) glowG += glowIntG; } }
          if (x > 0)     { final n = g[i - 1]; if (n == El.fire || n == El.lava) { glowR += glowIntR; if (n == El.fire) glowG += glowIntG; } }
          if (x < w - 1) { final n = g[i + 1]; if (n == El.fire || n == El.lava) { glowR += glowIntR; if (n == El.fire) glowG += glowIntG; } }
        }
        if (glowR > 0) {
          _pixels[pi4] = (bgR + glowR.clamp(0, 60)).clamp(0, 255);
          _pixels[pi4 + 1] = (bgG + glowG.clamp(0, 20)).clamp(0, 255);
          _pixels[pi4 + 2] = bgB;
          _pixels[pi4 + 3] = 255;
        } else if (starSet.contains(i)) {
          // Twinkling stars at night
          final twinkle = ((_frameCount + i * 17) % 40);
          if (twinkle < 6) {
            final brightness = twinkle < 3 ? 200 : 140;
            final starBright = (brightness * t).round();
            _pixels[pi4] = (bgR + starBright).clamp(0, 255);
            _pixels[pi4 + 1] = (bgG + starBright).clamp(0, 255);
            _pixels[pi4 + 2] = (bgB + starBright).clamp(0, 255);
            _pixels[pi4 + 3] = 255;
          } else {
            _pixels[pi4] = bgR;
            _pixels[pi4 + 1] = bgG;
            _pixels[pi4 + 2] = bgB;
            _pixels[pi4 + 3] = 255;
          }
        } else {
          _pixels[pi4] = bgR;
          _pixels[pi4 + 1] = bgG;
          _pixels[pi4 + 2] = bgB;
          _pixels[pi4 + 3] = 255;
        }
        continue;
      }

      final c = _getElementColor(el, i);

      int r = (c.r * 255.0).round();
      int g2 = (c.g * 255.0).round();
      int b = (c.b * 255.0).round();
      final int a = (c.a * 255.0).round();

      // Night lighting adjustments (pre-computed int factors)
      if (nightBoost > 0) {
        if (el == El.fire || el == El.lava) {
          r = (r + nightBoost).clamp(0, 255);
          g2 = (g2 + nightBoostG).clamp(0, 255);
        } else if (el == El.lightning) {
          // stays bright
        } else if (el == El.water) {
          final wx = i % w;
          final isTop = i >= w && g[i - w] != El.water;
          if (isTop && ((_frameCount + wx * 3) % 12 < 3)) {
            r = (r + nightShimmer).clamp(0, 255);
            g2 = (g2 + nightShimmer).clamp(0, 255);
            b = (b + nightShimmer).clamp(0, 255);
          } else {
            r = (r * nightDimWater) >> 8;
            g2 = (g2 * nightDimWater) >> 8;
          }
        } else if (el == El.smoke) {
          r = (r + nightSmokeBoost).clamp(0, 255);
          g2 = (g2 + nightSmokeBoost).clamp(0, 255);
          b = (b + nightSmokeBoost).clamp(0, 255);
        } else {
          r = (r * nightDimGeneral) >> 8;
          g2 = (g2 * nightDimGeneral) >> 8;
          b = (b * nightDimGeneral) >> 8;
        }
      }

      _pixels[pi4] = r.clamp(0, 255);
      _pixels[pi4 + 1] = g2.clamp(0, 255);
      _pixels[pi4 + 2] = b.clamp(0, 255);
      _pixels[pi4 + 3] = a;
    }
  }

  Color _getElementColor(int el, int idx) {
    // Pheromone visualization for empty cells
    if (el == El.empty && _life[idx] > 0) {
      // Subtle warm amber tint showing ant trails
      final life = _life[idx];
      final a = (life ~/ 10).clamp(0, 25);
      if (a > 0) {
        return Color.fromARGB(a, 255, 180, 60);
      }
      return const Color(0x00000000);
    }

    // Slight random hue variation per particle using idx as seed
    final variation = ((idx * 7 + idx ~/ _gridW * 3) % 11) - 5; // -5 to +5

    switch (el) {
      case El.fire:
        final phase = (_life[idx] + _frameCount) % 20;
        if (phase < 7) {
          return Color.fromARGB(255, (255 + variation).clamp(200, 255), (102 + variation).clamp(60, 140), 0);
        }
        if (phase < 14) {
          return Color.fromARGB(255, (255 + variation).clamp(200, 255), (34 + variation).clamp(0, 80), 0);
        }
        return Color.fromARGB(255, 255, (170 + variation).clamp(130, 210), 0);

      case El.lightning:
        return _frameCount.isEven
            ? const Color(0xFFFFFF66)
            : const Color(0xFFFFFFFF);

      case El.rainbow:
        // Fast HSV→RGB for rainbow (avoids HSVColor object creation)
        final hue = ((_rainbowHue + _life[idx] * 7) % 360).toDouble();
        final h6 = hue / 60.0;
        final hi = h6.floor() % 6;
        final f = h6 - h6.floor();
        const v = 255; // v=1.0*255, s=0.8 → p = v*(1-s) = 51
        const p = 51;
        final q = (v * (1.0 - 0.8 * f)).round();
        final t2 = (v * (1.0 - 0.8 * (1.0 - f))).round();
        switch (hi) {
          case 0: return Color.fromARGB(255, v, t2, p);
          case 1: return Color.fromARGB(255, q, v, p);
          case 2: return Color.fromARGB(255, p, v, t2);
          case 3: return Color.fromARGB(255, p, q, v);
          case 4: return Color.fromARGB(255, t2, p, v);
          default: return Color.fromARGB(255, v, p, q);
        }

      case El.steam:
        final alpha = (180 - _life[idx] * 2).clamp(60, 180);
        return Color.fromARGB(alpha, 220 + variation, 220 + variation, 240);

      case El.water:
        // Electrified water
        if (_life[idx] >= 200) {
          _life[idx]--;
          if (_life[idx] < 200) _life[idx] = 0;
          return const Color(0xFFFFFF66);
        }
        // Melting transition from ice
        if (_life[idx] >= 140 && _life[idx] < 200) {
          _life[idx]--;
          final blend = (_life[idx] - 140) / 10.0;
          return Color.fromARGB(
            255,
            (30 + blend * 140).round().clamp(0, 255),
            (100 + blend * 120).round().clamp(0, 255),
            255,
          );
        }
        // Water with depth-based darkening
        final wx = idx % _gridW;
        final wy = idx ~/ _gridW;
        final isTop = wy > 0 && _grid[(wy - 1) * _gridW + wx] != El.water &&
            _grid[(wy - 1) * _gridW + wx] != El.oil;
        if (isTop) {
          // Surface water — bright highlight
          return Color.fromARGB(255, (90 + variation).clamp(60, 120), 190, 255);
        }
        // Depth-based darkening: count water cells above (capped at 5)
        int depthAbove = 0;
        for (int dy = 1; dy <= 5; dy++) {
          final cy = wy - dy;
          if (cy < 0) break;
          final ce = _grid[cy * _gridW + wx];
          if (ce == El.water || ce == El.oil) {
            depthAbove++;
          } else {
            break;
          }
        }
        // Deeper = darker blue (each depth level darkens by ~8)
        final depthDarken = depthAbove * 8;
        return Color.fromARGB(255,
            (30 + variation - depthDarken).clamp(5, 60),
            (100 + variation - depthDarken).clamp(50, 130),
            (255 - depthDarken * 2).clamp(180, 255));

      case El.sand:
        // 5-shade variation: tan, golden, darker grains, light, warm
        final sandShade = (idx * 7 + idx ~/ _gridW * 3) % 5;
        switch (sandShade) {
          case 0: return Color.fromARGB(255, (222 + variation).clamp(200, 240), (184 + variation).clamp(160, 200), (135 + variation).clamp(110, 155)); // tan
          case 1: return Color.fromARGB(255, (235 + variation).clamp(215, 250), (200 + variation).clamp(180, 220), (120 + variation).clamp(100, 145)); // golden
          case 2: return Color.fromARGB(255, (190 + variation).clamp(170, 210), (155 + variation).clamp(135, 175), (110 + variation).clamp(90, 130)); // darker grain
          case 3: return Color.fromARGB(255, (230 + variation).clamp(210, 250), (195 + variation).clamp(175, 215), (145 + variation).clamp(125, 165)); // light
          default: return Color.fromARGB(255, (215 + variation).clamp(195, 235), (175 + variation).clamp(155, 195), (125 + variation).clamp(105, 145)); // warm
        }

      case El.tnt:
        final tx = idx % _gridW;
        final ty = idx ~/ _gridW;
        if ((tx + ty) % 4 == 0) return const Color(0xFF440000);
        return Color.fromARGB(255, (204 + variation).clamp(180, 230), (34 + variation).clamp(10, 60), (34 + variation).clamp(10, 60));

      case El.ant:
        final antState = _velY[idx];
        if (antState == 4) {
          // Forager — greenish tint (carrying a seed)
          return const Color(0xFF2B3D1F);
        }
        if (antState == 2) {
          // Carrier — brownish tint (carrying dirt)
          return const Color(0xFF3D2B1F);
        }
        if (antState == 1) {
          // Digger — slightly reddish (active worker)
          return const Color(0xFF2A1111);
        }
        // Explorer/returning — normal dark ant
        return (idx % 3 == 0)
            ? const Color(0xFF333333)
            : const Color(0xFF111111);

      case El.seed:
        final v = ((idx % 5) * 4 + variation).clamp(0, 25);
        final seedType = _velX[idx].clamp(1, 5);
        switch (seedType) {
          case kPlantGrass:
            // Light green-brown
            return Color.fromARGB(255, (120 - v).clamp(90, 130), (135 - v).clamp(100, 145), (70 - v).clamp(40, 80));
          case kPlantFlower:
            // Pink/magenta tint seed coat
            return Color.fromARGB(255, (165 - v).clamp(130, 175), (95 - v).clamp(70, 110), (120 - v).clamp(90, 135));
          case kPlantTree:
            // Dark brown acorn-like
            return Color.fromARGB(255, (95 - v).clamp(60, 105), (65 - v).clamp(35, 75), (30 - v).clamp(10, 40));
          case kPlantMushroom:
            // Pale cream/white ghostly spore
            return Color.fromARGB(230, (235 - v).clamp(210, 245), (230 - v).clamp(205, 240), (215 - v).clamp(190, 225));
          case kPlantVine:
            // Green-brown with slight green tint
            return Color.fromARGB(255, (110 - v).clamp(80, 120), (125 - v).clamp(95, 135), (65 - v).clamp(35, 75));
          default:
            return Color.fromARGB(255, (139 - v).clamp(100, 150), (115 - v).clamp(80, 130), (85 - v).clamp(50, 100));
        }

      case El.dirt:
        // Rich earth tones with moisture gradient and 5-shade variation
        final moisture = _life[idx].clamp(0, 5);
        final mFrac = moisture / 5.0;
        final dirtShade = (idx * 7 + idx ~/ _gridW * 3) % 5;
        // Base colors per shade: dark brown, reddish-brown, lighter fleck, warm, cool
        int baseR, baseG, baseB;
        switch (dirtShade) {
          case 0: baseR = 139; baseG = 105; baseB = 22; // standard brown
          case 1: baseR = 148; baseG = 90;  baseB = 28; // reddish-brown
          case 2: baseR = 155; baseG = 120; baseB = 35; // lighter fleck
          case 3: baseR = 135; baseG = 100; baseB = 18; // warm earth
          default: baseR = 125; baseG = 95;  baseB = 30; // cool earth
        }
        // Moisture darkens: dry -> normal, wet -> much darker and richer
        final dr = (baseR - mFrac * 55 + variation).round().clamp(55, 165);
        final dg = (baseG - mFrac * 45 + variation).round().clamp(35, 130);
        final db = (baseB - mFrac * 10 + variation).round().clamp(8, 50);
        return Color.fromARGB(255, dr, dg, db);

      case El.plant:
        final pType = _plantType(idx);
        final pStage = _plantStage(idx);
        // Dead plant: dark brown
        if (pStage == kStDead) {
          return Color.fromARGB(255, (80 + variation).clamp(60, 100), (50 + variation).clamp(30, 70), 20);
        }
        // Wilting: faded yellowish green
        if (pStage == kStWilting) {
          return Color.fromARGB(255, (120 + variation).clamp(100, 150), (130 + variation).clamp(110, 160), (40 + variation).clamp(20, 60));
        }
        final shade = ((idx % 5) * 8 + variation).clamp(0, 50);
        switch (pType) {
          case kPlantGrass:
            return Color.fromARGB(255, 30 + shade, 170 + shade ~/ 2, 30 + shade);
          case kPlantFlower:
            // Stem green, bloom uses position hash for color variety
            if (pStage == kStMature) {
              final hue = ((idx * 37) % 5);
              const bloomColors = [Color(0xFFFF4488), Color(0xFFFFDD44), Color(0xFFFF88CC), Color(0xFF9944FF), Color(0xFF4488FF)];
              return bloomColors[hue];
            }
            return Color.fromARGB(255, 20 + shade, 160 + shade, 20 + shade);
          case kPlantTree:
            // Trunk (growing) = brown, canopy (mature) = dark green
            if (pStage == kStGrowing) {
              return Color.fromARGB(255, (100 + variation).clamp(80, 120), (60 + variation).clamp(40, 80), (25 + variation).clamp(10, 40));
            }
            return Color.fromARGB(255, 15 + shade ~/ 2, 120 + shade, 15 + shade ~/ 2);
          case kPlantMushroom:
            // Cap (mature) = red/brown with white, stem = beige
            if (pStage == kStMature) {
              final spot = (idx * 13) % 7 == 0;
              if (spot) return const Color(0xFFF0F0E0); // white spots
              return Color.fromARGB(255, (180 + variation).clamp(160, 210), (50 + variation).clamp(30, 70), (30 + variation).clamp(10, 50));
            }
            return Color.fromARGB(255, (220 + variation).clamp(200, 240), (210 + variation).clamp(190, 230), (180 + variation).clamp(160, 200));
          case kPlantVine:
            // Green with leaf nodes every few cells
            final isLeaf = _velY[idx] % 4 == 0;
            if (isLeaf) return Color.fromARGB(255, 10 + shade, 180 + shade ~/ 2, 10 + shade);
            return Color.fromARGB(255, 30 + shade, 140 + shade, 30 + shade);
          default:
            return Color.fromARGB(255, 20 + shade, 160 + shade, 20 + shade);
        }

      case El.ice:
        return Color.fromARGB(255, (170 + variation).clamp(150, 200), (221 + variation).clamp(200, 240), 255);

      case El.stone:
        // 5-shade natural variation: grey, dark grey, lighter speckles
        final stoneShade = (idx * 7 + idx ~/ _gridW * 3) % 5;
        switch (stoneShade) {
          case 0: return Color.fromARGB(255, (130 + variation).clamp(110, 155), (130 + variation).clamp(110, 155), (135 + variation).clamp(115, 160)); // medium grey
          case 1: return Color.fromARGB(255, (105 + variation).clamp(85, 125), (105 + variation).clamp(85, 125), (110 + variation).clamp(90, 130)); // dark grey
          case 2: return Color.fromARGB(255, (150 + variation).clamp(130, 175), (150 + variation).clamp(130, 175), (155 + variation).clamp(135, 180)); // lighter speckle
          case 3: return Color.fromARGB(255, (118 + variation).clamp(98, 140), (115 + variation).clamp(95, 137), (120 + variation).clamp(100, 142)); // cool grey
          default: return Color.fromARGB(255, (138 + variation).clamp(118, 160), (136 + variation).clamp(116, 158), (140 + variation).clamp(120, 162)); // warm grey
        }

      case El.mud:
        final v = ((idx % 5) * 5 + variation).clamp(0, 30);
        return Color.fromARGB(255, (139 - v).clamp(100, 150), (105 - v).clamp(70, 120), 20);

      case El.oil:
        final ox = idx % _gridW;
        final oy = idx ~/ _gridW;
        final isTop = oy > 0 && _grid[(oy - 1) * _gridW + ox] != El.oil;
        if (isTop) {
          final shimmer = (_frameCount + ox) % 8 < 2 ? 20 : 0;
          return Color.fromARGB(255, 74 + shimmer, 55 + shimmer, 40 + shimmer);
        }
        return Color.fromARGB(255, (50 + variation).clamp(30, 70), (37 + variation).clamp(20, 55), (28 + variation).clamp(10, 45));

      case El.acid:
        final bubble = (_frameCount + idx) % 12 < 3 ? 40 : 0;
        return Color.fromARGB(255, (30 + variation + bubble).clamp(0, 100), (255 + variation).clamp(200, 255), (30 + variation).clamp(0, 80));

      case El.glass:
        final sparkle = (_frameCount + idx * 3) % 20 < 2 ? 30 : 0;
        return Color.fromARGB(200, (210 + variation + sparkle).clamp(180, 255), (225 + variation + sparkle).clamp(200, 255), 255);

      case El.lava:
        final flicker = (_frameCount + idx) % 6;
        final bright = flicker < 3 ? 30 : 0;
        return Color.fromARGB(255, (255 + variation).clamp(220, 255), (69 + bright + variation).clamp(40, 120), 0);

      case El.snow:
        final sparkle = (_frameCount + idx * 5) % 15 < 2 ? 15 : 0;
        return Color.fromARGB(255, (240 + sparkle).clamp(230, 255), (240 + sparkle).clamp(230, 255), 255);

      case El.wood:
        // Burning wood — shifts to red/orange
        if (_life[idx] > 0) {
          final burnPhase = (_life[idx] + _frameCount) % 6;
          final bright = burnPhase < 3 ? 40 : 0;
          return Color.fromARGB(255, (200 + bright).clamp(180, 255), (80 + bright - _life[idx]).clamp(20, 120), 10);
        }
        // Grain pattern: alternate lighter/darker based on position
        final wx = idx % _gridW;
        final wy = idx ~/ _gridW;
        final grain = (wx + wy * 3) % 5 < 2 ? 15 : 0;
        // Waterlogged wood is darker (velY tracks waterlog level 0..3)
        final waterlog = _velY[idx].clamp(0, 3) * 20;
        return Color.fromARGB(255, (160 - grain - waterlog + variation).clamp(60, 180), (82 - grain - waterlog + variation).clamp(30, 110), (45 - grain - waterlog + variation).clamp(10, 70));

      case El.metal:
        // Electrified glow when _life >= 200
        if (_life[idx] >= 200) {
          _life[idx]--;
          if (_life[idx] < 200) _life[idx] = 0;
          return const Color(0xFFFFFF88);
        }
        // Rust: darken and shift to orange-brown based on life counter (0..120)
        final rustLevel = _life[idx].clamp(0, 120);
        if (rustLevel > 0) {
          final rustFrac = rustLevel / 120.0;
          // Shift from silver (168,168,176) toward rust-brown (139,90,43)
          final r = (168 - rustFrac * 29 + variation).round().clamp(100, 200);
          final g = (168 - rustFrac * 78 + variation).round().clamp(60, 200);
          final b = (176 - rustFrac * 133 + variation).round().clamp(30, 210);
          return Color.fromARGB(255, r, g, b);
        }
        final sheen = (_frameCount + idx * 2) % 12 < 2 ? 20 : 0;
        return Color.fromARGB(255, (168 + sheen + variation).clamp(140, 200), (168 + sheen + variation).clamp(140, 200), (176 + sheen + variation).clamp(150, 210));

      case El.smoke:
        final fade = (60 - _life[idx]).clamp(0, 60);
        final alpha = (fade * 3 + 60).clamp(60, 200);
        return Color.fromARGB(alpha, (128 + variation).clamp(100, 160), (128 + variation).clamp(100, 160), (128 + variation).clamp(100, 160));

      case El.bubble:
        final bright = (_frameCount + idx) % 8 < 3 ? 30 : 0;
        return Color.fromARGB(180, (173 + bright + variation).clamp(150, 220), (216 + bright + variation).clamp(190, 255), (230 + bright).clamp(210, 255));

      case El.ash:
        final v = ((idx % 7) * 3 + variation).clamp(0, 20);
        // Semi-transparent feel — slightly varied grey
        return Color.fromARGB(220, (176 - v).clamp(150, 200), (176 - v).clamp(150, 200), (180 - v).clamp(155, 205));

      default:
        return _baseColors[el.clamp(0, _baseColors.length - 1)];
    }
  }

  Future<void> _buildImage() async {
    _frameImageNotifier.value?.dispose();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixels,
      _gridW,
      _gridH,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    final newImage = await completer.future;
    if (mounted) {
      _frameImageNotifier.value = newImage;
    }
  }

  // ── Drawing input ───────────────────────────────────────────────────────

  void _captureUndoSnapshot() {
    if (!_isCapturingStroke) {
      _isCapturingStroke = true;
      _undoHistory.add(_UndoSnapshot(
        grid: Uint8List.fromList(_grid),
        life: Uint8List.fromList(_life),
      ));
      if (_undoHistory.length > _maxUndoHistory) {
        _undoHistory.removeAt(0);
      }
    }
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    final snapshot = _undoHistory.removeLast();
    _grid.setAll(0, snapshot.grid);
    _life.setAll(0, snapshot.life);
    Haptics.tap();
  }

  void _handlePanStart(DragStartDetails details) {
    if (_sessionExpired) return;
    _captureUndoSnapshot();
    _isDrawing = true;
    if (_brushMode == 1) {
      _lineStartX = ((details.localPosition.dx - _canvasLeft) / _cellSize).floor();
      _lineStartY = ((details.localPosition.dy - _canvasTop) / _cellSize).floor();
      _lineEndX = _lineStartX;
      _lineEndY = _lineStartY;
    } else {
      _placeElement(details.localPosition);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_sessionExpired) return;
    if (_isDrawing) {
      if (_brushMode == 1) {
        _lineEndX = ((details.localPosition.dx - _canvasLeft) / _cellSize).floor();
        _lineEndY = ((details.localPosition.dy - _canvasTop) / _cellSize).floor();
      } else {
        _placeElement(details.localPosition);
      }
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_brushMode == 1 && _lineStartX >= 0) {
      _drawLine(_lineStartX, _lineStartY, _lineEndX, _lineEndY);
    }
    _isDrawing = false;
    _isCapturingStroke = false;
    _lineStartX = -1;
    _lineStartY = -1;
  }

  void _handleTapDown(TapDownDetails details) {
    if (_sessionExpired) return;
    if (_showSeedPopup) setState(() => _showSeedPopup = false);
    _captureUndoSnapshot();
    _placeElement(details.localPosition);
    _isCapturingStroke = false;
    Haptics.tap();
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_sessionExpired) return;
    _captureUndoSnapshot();
    _isDrawing = true;
    _placeElement(details.localPosition, burst: true);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_sessionExpired) return;
    if (_isDrawing) {
      _placeElement(details.localPosition, burst: true);
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _isDrawing = false;
    _isCapturingStroke = false;
  }

  void _placeElement(Offset pos, {bool burst = false}) {
    final gx = ((pos.dx - _canvasLeft) / _cellSize).floor();
    final gy = ((pos.dy - _canvasTop) / _cellSize).floor();

    // Seeds always place a single cell (no brush size scaling)
    if (_selectedElement == El.seed) {
      if (!_inBounds(gx, gy)) return;
      final ni = gy * _gridW + gx;
      if (_grid[ni] != El.empty) return;
      _grid[ni] = El.seed;
      _life[ni] = 0;
      _velX[ni] = _selectedSeedType;
      _velY[ni] = 0;
      return;
    }

    final radius = burst ? _brushSize + 2 : _brushSize;
    final halfR = radius ~/ 2;

    for (int dy = -halfR; dy <= halfR; dy++) {
      for (int dx = -halfR; dx <= halfR; dx++) {
        final nx = gx + dx;
        final ny = gy + dy;
        if (!_inBounds(nx, ny)) continue;

        if (radius > 1 && dx * dx + dy * dy > halfR * halfR + 1) continue;

        // Spray mode: 40% chance per cell
        if (_brushMode == 2 && _rng.nextInt(100) >= 40) continue;

        final ni = ny * _gridW + nx;

        if (_selectedElement == El.eraser) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _velX[ni] = 0;
          _velY[ni] = 0;
          continue;
        }

        if (_grid[ni] != El.empty && _selectedElement != El.lightning) continue;

        _grid[ni] = _selectedElement;
        _life[ni] = 0;
        _velY[ni] = 0;
      }
    }
  }

  /// Bresenham line drawing from (x0,y0) to (x1,y1).
  void _drawLine(int x0, int y0, int x1, int y1) {
    int dx = (x1 - x0).abs();
    int dy = -(y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    int cx = x0;
    int cy = y0;

    while (true) {
      _placeAt(cx, cy);
      if (cx == x1 && cy == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        cx += sx;
      }
      if (e2 <= dx) {
        err += dx;
        cy += sy;
      }
    }
  }

  /// Place element at a single grid cell (for line drawing).
  void _placeAt(int gx, int gy) {
    // Seeds always place a single cell
    if (_selectedElement == El.seed) {
      if (!_inBounds(gx, gy)) return;
      final ni = gy * _gridW + gx;
      if (_grid[ni] != El.empty) return;
      _grid[ni] = El.seed;
      _life[ni] = 0;
      _velX[ni] = _selectedSeedType;
      _velY[ni] = 0;
      return;
    }

    final halfR = _brushSize ~/ 2;
    for (int dy = -halfR; dy <= halfR; dy++) {
      for (int dx = -halfR; dx <= halfR; dx++) {
        final nx = gx + dx;
        final ny = gy + dy;
        if (!_inBounds(nx, ny)) continue;
        if (_brushSize > 1 && dx * dx + dy * dy > halfR * halfR + 1) continue;
        final ni = ny * _gridW + nx;
        if (_selectedElement == El.eraser) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _velX[ni] = 0;
          _velY[ni] = 0;
          continue;
        }
        if (_grid[ni] != El.empty && _selectedElement != El.lightning) continue;
        _grid[ni] = _selectedElement;
        _life[ni] = 0;
        _velY[ni] = 0;
      }
    }
  }

  void _clearGrid() {
    _captureUndoSnapshot();
    _isCapturingStroke = false;
    _grid.fillRange(0, _grid.length, El.empty);
    _life.fillRange(0, _life.length, 0);
    _flags.fillRange(0, _flags.length, 0);
    _velX.fillRange(0, _velX.length, 0);
    _velY.fillRange(0, _velY.length, 0);
    Haptics.tap();
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    Haptics.tap();
  }

  void _addMoreTime() {
    if (!widget.freePlay) {
      final balance = widget.progressService.starCoins;
      if (balance < kExtensionCost) return;
      widget.progressService.spendStarCoins(kExtensionCost);
    }
    setState(() {
      _remainingSeconds += widget.freePlay
          ? const Duration(minutes: 999).inSeconds
          : kExtensionDuration.inSeconds;
      _sessionExpired = false;
    });
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _timerColor() {
    if (_remainingSeconds > 60) return AppColors.emerald;
    if (_remainingSeconds > 30) return const Color(0xFFFFBB33);
    return AppColors.error;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Transform.translate(
              offset: _shakeOffset,
              child: Column(
              children: [
                RepaintBoundary(child: _buildTopBar()),
                Expanded(
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (!_gridInitialized) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _initGrid(constraints.maxWidth, constraints.maxHeight);
                          });
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.electricBlue,
                            ),
                          );
                        }
                        return _buildCanvas(constraints);
                      },
                    ),
                  ),
                ),
                RepaintBoundary(child: _buildPalette()),
                RepaintBoundary(child: _buildBottomBar()),
              ],
            ),
            ),
            // Time warning overlay
            if (_showTimeWarning) _buildTimeWarningOverlay(),
            // Session expired overlay
            if (_sessionExpired) _buildSessionExpiredOverlay(),
            // Element info overlay
            if (_showElementInfo) _buildElementInfoOverlay(),
            // Pause overlay
            if (_isPaused && !_sessionExpired) _buildPauseOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final timerColor = _timerColor();
    final isPulsing = _remainingSeconds <= 30 && !_sessionExpired;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final iconSz = compact ? 18.0 : 22.0;
    final btnSz = compact ? 32.0 : 40.0;
    final fontSz = compact ? 14.0 : 18.0;
    final smallFont = compact ? 11.0 : 14.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primaryText,
              iconSize: iconSz,
              padding: EdgeInsets.zero,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 2),
            Text(
              'Element Lab',
              style: AppFonts.fredoka(
                fontSize: fontSz,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: _toggleMute,
              icon: Icon(
                _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: _isMuted
                    ? AppColors.secondaryText.withValues(alpha: 0.5)
                    : AppColors.electricBlue,
              ),
              iconSize: iconSz,
              padding: EdgeInsets.zero,
              tooltip: _isMuted ? 'Sound on' : 'Sound off',
            ),
          ),
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: _toggleDayNight,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: 0.0, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  key: ValueKey(_isNight),
                  color: _isNight
                      ? const Color(0xFF8888CC)
                      : const Color(0xFFFFAA33),
                ),
              ),
              iconSize: iconSz,
              padding: EdgeInsets.zero,
              tooltip: _isNight ? 'Switch to day' : 'Switch to night',
            ),
          ),
          const Spacer(),
          // Session timer
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: isPulsing ? 1.15 : 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: isPulsing
                    ? 1.0 + 0.15 * sin(_frameCount * 0.15)
                    : 1.0,
                child: child,
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 3),
              decoration: BoxDecoration(
                color: timerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: timerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_rounded, color: timerColor, size: compact ? 13 : 16),
                  const SizedBox(width: 3),
                  Text(
                    _formatTime(_remainingSeconds),
                    style: AppFonts.fredoka(
                      fontSize: smallFont,
                      fontWeight: FontWeight.w700,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 4 : 8),
          // Star coin balance
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.starGold.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded,
                    color: AppColors.starGold, size: compact ? 13 : 16),
                const SizedBox(width: 3),
                Text(
                  '${widget.progressService.starCoins}',
                  style: AppFonts.fredoka(
                    fontSize: smallFont,
                    fontWeight: FontWeight.w600,
                    color: AppColors.starGold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    // Dynamically compute display rect so the grid scales to fit any layout size.
    // The grid dimensions (_gridW x _gridH) stay fixed after init, but the display
    // cell size and offsets adapt to current constraints (handles window resize,
    // orientation change, etc.).
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;
    final displayCellW = viewW / _gridW;
    final displayCellH = viewH / _gridH;
    final displayCell = displayCellW < displayCellH ? displayCellW : displayCellH;
    final displayW = _gridW * displayCell;
    final displayH = _gridH * displayCell;
    final displayLeft = (viewW - displayW) / 2;
    final displayTop = (viewH - displayH) / 2;

    // Keep _cellSize/_canvasLeft/_canvasTop in sync for touch mapping
    _cellSize = displayCell;
    _canvasLeft = displayLeft;
    _canvasTop = displayTop;
    _canvasPixelW = displayW;
    _canvasPixelH = displayH;

    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      onTapDown: _handleTapDown,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      child: Container(
        color: AppColors.background,
        width: viewW,
        height: viewH,
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: _frameImageNotifier,
          builder: (context, frameImage, _) {
            return CustomPaint(
              painter: _GridPainter(
                image: frameImage,
                canvasLeft: displayLeft,
                canvasTop: displayTop,
                canvasPixelW: displayW,
                canvasPixelH: displayH,
                lightningFlash: _lightningFlashFrames > 0,
              ),
              size: Size(viewW, viewH),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPalette() {
    final tabElements = _tabElements[_selectedTab];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final tabH = compact ? 26.0 : 32.0;
    final chipH = compact ? 48.0 : 60.0;
    final tabIconSz = compact ? 13.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar
          SizedBox(
            height: tabH,
            child: Row(
              children: [
                for (int i = 0; i < _tabIcons.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedTab = i);
                        Haptics.tap();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedTab == i
                              ? AppColors.electricBlue.withValues(alpha: 0.15)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: _selectedTab == i
                                  ? AppColors.electricBlue
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _tabIcons[i],
                            size: tabIconSz,
                            color: _selectedTab == i
                                ? AppColors.electricBlue
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Element chips for selected tab — scrollable
          SizedBox(
            height: chipH,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final elType in tabElements)
                    if (elType == El.eraser)
                      _buildEraserChip()
                    else if (elType == El.seed)
                      _buildSeedChip()
                    else
                      _buildElementChip(elType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElementChip(int elType) {
    final isSelected = _selectedElement == elType;
    final color = _baseColors[elType.clamp(0, _baseColors.length - 1)];
    final name = _elementNames[elType.clamp(0, _elementNames.length - 1)];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedElement = elType);
        Haptics.tap();
        _speakElementName(elType);
      },
      onLongPress: () {
        setState(() {
          _showElementInfo = true;
          _infoElement = elType;
        });
        Haptics.tap();
        _speakElementName(elType);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: hMargin),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.3)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSz,
              height: dotSz,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: AppFonts.fredoka(
                fontSize: labelSz,
                fontWeight: FontWeight.w500,
                color: isSelected ? color : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEraserChip() {
    final isSelected = _selectedElement == El.eraser;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final iconSz = compact ? 11.0 : 14.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedElement = El.eraser);
        Haptics.tap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: hMargin),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.error.withValues(alpha: 0.2)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.error : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSz,
              height: dotSz,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.cleaning_services_rounded,
                size: iconSz,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Erase',
              style: AppFonts.fredoka(
                fontSize: labelSz,
                fontWeight: FontWeight.w500,
                color:
                    isSelected ? AppColors.error : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _showSeedPopup = false;

  Widget _buildSeedChip() {
    final isSelected = _selectedElement == El.seed;
    final color = _baseColors[El.seed];
    const seedNames = ['', 'Grass', 'Flower', 'Tree', 'Shroom', 'Vine'];
    const seedColors = [
      Colors.transparent,
      Color(0xFF33CC33), // grass
      Color(0xFFFF88CC), // flower
      Color(0xFF8B6914), // tree
      Color(0xFFCC4444), // mushroom
      Color(0xFF33AA33), // vine
    ];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final iconSz = compact ? 11.0 : 14.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;
    final popupItemW = compact ? 34.0 : 40.0;
    final popupItemH = compact ? 40.0 : 48.0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedElement = El.seed;
          _showSeedPopup = !_showSeedPopup;
        });
        Haptics.tap();
        _speakElementName(El.seed);
      },
      onLongPress: () {
        setState(() { _showElementInfo = true; _infoElement = El.seed; });
        Haptics.tap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.symmetric(horizontal: hMargin),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.3) : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: dotSz, height: dotSz,
                  decoration: BoxDecoration(
                    color: seedColors[_selectedSeedType.clamp(1, 5)],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: seedColors[_selectedSeedType.clamp(1, 5)].withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ] : null,
                  ),
                  child: Icon(Icons.eco_rounded, size: iconSz, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  seedNames[_selectedSeedType.clamp(1, 5)],
                  style: AppFonts.fredoka(fontSize: labelSz, fontWeight: FontWeight.w500,
                    color: isSelected
                        ? seedColors[_selectedSeedType.clamp(1, 5)]
                        : AppColors.secondaryText),
                ),
              ],
            ),
          ),
          // Seed type popup — use OverlayEntry-style approach via Positioned
          if (_showSeedPopup && isSelected)
            Positioned(
              bottom: compact ? 52 : 64,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.4), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int st = 1; st <= 5; st++)
                      GestureDetector(
                        onTap: () {
                          setState(() { _selectedSeedType = st; _showSeedPopup = false; });
                          Haptics.tap();
                        },
                        child: Container(
                          width: popupItemW, height: popupItemH,
                          margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
                          decoration: BoxDecoration(
                            color: _selectedSeedType == st
                                ? seedColors[st].withValues(alpha: 0.25)
                                : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedSeedType == st ? seedColors[st] : AppColors.border,
                              width: _selectedSeedType == st ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CustomPaint(
                                size: Size(compact ? 18 : 24, compact ? 18 : 24),
                                painter: _SeedIconPainter(st),
                              ),
                              Text(
                                seedNames[st],
                                style: AppFonts.fredoka(fontSize: compact ? 6 : 7, fontWeight: FontWeight.w500,
                                  color: _selectedSeedType == st ? seedColors[st] : AppColors.secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final btnBox = compact ? 26.0 : 32.0;
    final btnIcon = compact ? 15.0 : 18.0;
    final smallBtnBox = compact ? 22.0 : 28.0;
    final smallBtnIcon = compact ? 13.0 : 16.0;
    final chipSz = compact ? 22.0 : 26.0;
    final brushChipIcon = compact ? 12.0 : 14.0;
    final barH = compact ? 36.0 : 44.0;
    final hPad = compact ? 6.0 : 12.0;

    Widget buildBrushSizeBtn(int size) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
        child: GestureDetector(
          onTap: () {
            setState(() => _brushSize = size);
            Haptics.tap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: chipSz,
            height: chipSz,
            decoration: BoxDecoration(
              color: _brushSize == size
                  ? AppColors.electricBlue.withValues(alpha: 0.2)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _brushSize == size
                    ? AppColors.electricBlue
                    : AppColors.border,
                width: _brushSize == size ? 2 : 1,
              ),
            ),
            child: Center(
              child: Container(
                width: size.toDouble() * 2 + 2,
                height: size.toDouble() * 2 + 2,
                decoration: BoxDecoration(
                  color: _brushSize == size
                      ? AppColors.electricBlue
                      : AppColors.secondaryText,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildBrushModeBtn(int mode, IconData icon) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: GestureDetector(
          onTap: () {
            setState(() => _brushMode = mode);
            Haptics.tap();
          },
          child: Container(
            width: chipSz,
            height: chipSz,
            decoration: BoxDecoration(
              color: _brushMode == mode
                  ? AppColors.electricBlue.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _brushMode == mode
                    ? AppColors.electricBlue
                    : AppColors.border.withValues(alpha: 0.3),
                width: _brushMode == mode ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: brushChipIcon,
              color: _brushMode == mode
                  ? AppColors.electricBlue
                  : AppColors.secondaryText,
            ),
          ),
        ),
      );
    }

    Widget buildIconBtn({
      required VoidCallback? onPressed,
      required IconData icon,
      required Color color,
      double? size,
      double? box,
    }) {
      final bSz = box ?? btnBox;
      final iSz = size ?? btnIcon;
      return SizedBox(
        width: bSz,
        height: bSz,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          iconSize: iSz,
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Container(
      height: barH,
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Brush sizes
            for (final size in const [1, 3, 5])
              buildBrushSizeBtn(size),
            SizedBox(width: compact ? 4 : 6),
            // Brush modes
            buildBrushModeBtn(0, Icons.circle),
            buildBrushModeBtn(1, Icons.horizontal_rule_rounded),
            buildBrushModeBtn(2, Icons.grain_rounded),
            SizedBox(width: compact ? 3 : 4),
            // Gravity flip
            buildIconBtn(
              onPressed: () {
                setState(() => _gravityDir = -_gravityDir);
                Haptics.tap();
              },
              icon: Icons.swap_vert_rounded,
              color: _gravityDir == -1
                  ? AppColors.starGold
                  : AppColors.secondaryText,
            ),
            // Wind left
            buildIconBtn(
              onPressed: () {
                setState(() => _windForce = (_windForce - 1).clamp(-3, 3));
                Haptics.tap();
              },
              icon: Icons.arrow_back_rounded,
              color: _windForce < 0
                  ? AppColors.electricBlue
                  : AppColors.secondaryText.withValues(alpha: 0.4),
              size: smallBtnIcon,
              box: smallBtnBox,
            ),
            // Wind indicator
            SizedBox(
              width: compact ? 16 : 20,
              child: Center(
                child: Text(
                  _windForce == 0 ? '0' : '${_windForce > 0 ? "+" : ""}$_windForce',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    color: _windForce != 0
                        ? AppColors.electricBlue
                        : AppColors.secondaryText.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            // Wind right
            buildIconBtn(
              onPressed: () {
                setState(() => _windForce = (_windForce + 1).clamp(-3, 3));
                Haptics.tap();
              },
              icon: Icons.arrow_forward_rounded,
              color: _windForce > 0
                  ? AppColors.electricBlue
                  : AppColors.secondaryText.withValues(alpha: 0.4),
              size: smallBtnIcon,
              box: smallBtnBox,
            ),
            // Shake
            buildIconBtn(
              onPressed: _shakeCooldown <= 0 ? _doShake : null,
              icon: Icons.vibration_rounded,
              color: _shakeCooldown <= 0
                  ? AppColors.electricBlue
                  : AppColors.secondaryText.withValues(alpha: 0.3),
            ),
            SizedBox(width: compact ? 4 : 8),
            // Undo
            buildIconBtn(
              onPressed: _undoHistory.isNotEmpty ? _undo : null,
              icon: Icons.undo_rounded,
              color: _undoHistory.isNotEmpty
                  ? AppColors.electricBlue
                  : AppColors.secondaryText.withValues(alpha: 0.3),
            ),
            // Pause/Play
            buildIconBtn(
              onPressed: _togglePause,
              icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.electricBlue,
            ),
            // Clear
            buildIconBtn(
              onPressed: _clearGrid,
              icon: Icons.delete_outline_rounded,
              color: AppColors.error.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  // ── Overlay widgets ────────────────────────────────────────────────────

  Widget _buildTimeWarningOverlay() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 32, vertical: compact ? 10 : 16),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _timerColor().withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: Text(
              _timeWarningText,
              style: AppFonts.fredoka(
                fontSize: compact ? 20 : 28,
                fontWeight: FontWeight.w700,
                color: _timerColor(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionExpiredOverlay() {
    final canAfford = widget.progressService.starCoins >= kExtensionCost;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final hMargin = compact ? 16.0 : 32.0;
    final pad = compact ? 16.0 : 24.0;

    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.9),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: hMargin),
            padding: EdgeInsets.all(pad),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.electricBlue.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_rounded,
                  color: AppColors.starGold,
                  size: compact ? 36 : 48,
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  "Time's Up!",
                  style: AppFonts.fredoka(
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Text(
                  'Your Element Lab session has ended.',
                  textAlign: TextAlign.center,
                  style: AppFonts.fredoka(
                    fontSize: compact ? 12 : 14,
                    color: AppColors.secondaryText,
                  ),
                ),
                SizedBox(height: compact ? 14 : 20),
                // Add More Time button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAfford ? _addMoreTime : null,
                    icon: Icon(Icons.add_rounded, size: compact ? 16 : 20),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add 2 Min  ',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.star_rounded,
                            color: AppColors.starGold, size: compact ? 14 : 16),
                        Text(
                          ' $kExtensionCost',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.starGold,
                          ),
                        ),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? AppColors.electricBlue
                          : AppColors.surfaceVariant,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (!canAfford) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Complete words in Adventure Mode\nto earn more Star Coins!',
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 10 : 12,
                      color: AppColors.starGold.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 8 : 12),
                // Exit button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Exit',
                      style: AppFonts.fredoka(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElementInfoOverlay() {
    final elType = _infoElement;
    final color = _baseColors[elType.clamp(0, _baseColors.length - 1)];
    final name = _elementNames[elType.clamp(0, _elementNames.length - 1)];
    final desc = _elementDescriptions[elType] ?? 'A mysterious element.';
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final hMargin = compact ? 24.0 : 48.0;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showElementInfo = false),
        child: Container(
          color: AppColors.background.withValues(alpha: 0.7),
          child: Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: hMargin),
              padding: EdgeInsets.all(compact ? 14 : 20),
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: compact ? 30 : 40,
                    height: compact ? 30 : 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    name,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 8),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 11 : 13,
                      color: AppColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  Text(
                    'Tap anywhere to close',
                    style: AppFonts.fredoka(
                      fontSize: compact ? 9 : 11,
                      color: AppColors.secondaryText.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pause_circle_filled_rounded,
                color: AppColors.electricBlue,
                size: compact ? 48 : 64,
              ),
              SizedBox(height: compact ? 10 : 16),
              Text(
                'Paused',
                style: AppFonts.fredoka(
                  fontSize: compact ? 24 : 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                '${_formatTime(_remainingSeconds)} remaining',
                style: AppFonts.fredoka(
                  fontSize: compact ? 13 : 16,
                  color: AppColors.secondaryText,
                ),
              ),
              SizedBox(height: compact ? 16 : 24),
              ElevatedButton.icon(
                onPressed: _togglePause,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Resume',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 24 : 32,
                    vertical: compact ? 8 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Exit Lab',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 12 : 14,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Grid painter (renders the pixel buffer image) ─────────────────────────

class _GridPainter extends CustomPainter {
  final ui.Image? image;
  final double canvasLeft;
  final double canvasTop;
  final double canvasPixelW;
  final double canvasPixelH;
  final bool lightningFlash;

  const _GridPainter({
    required this.image,
    required this.canvasLeft,
    required this.canvasTop,
    required this.canvasPixelW,
    required this.canvasPixelH,
    required this.lightningFlash,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;

    final src = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(canvasLeft, canvasTop, canvasPixelW, canvasPixelH);

    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    canvas.drawImageRect(image!, src, dst, paint);

    if (lightningFlash) {
      canvas.drawRect(
        dst,
        Paint()
          ..color = const Color(0x18FFFFFF)
          ..blendMode = BlendMode.screen,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => true;
}

// ── Data classes ──────────────────────────────────────────────────────────

class _Explosion {
  final int x;
  final int y;
  final int radius;
  const _Explosion(this.x, this.y, this.radius);
}

class _UndoSnapshot {
  final Uint8List grid;
  final Uint8List life;
  const _UndoSnapshot({required this.grid, required this.life});
}

// ── Beaker icon painter for the hub ──────────────────────────────────────

class BeakerIconPainter extends CustomPainter {
  const BeakerIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Beaker body
    final beakerPath = Path()
      ..moveTo(cx - 10, cy - 16)
      ..lineTo(cx - 10, cy - 4)
      ..lineTo(cx - 16, cy + 14)
      ..lineTo(cx + 16, cy + 14)
      ..lineTo(cx + 10, cy - 4)
      ..lineTo(cx + 10, cy - 16)
      ..close();

    // Glass outline
    canvas.drawPath(
      beakerPath,
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      beakerPath,
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // Liquid inside (bottom half)
    final liquidPath = Path()
      ..moveTo(cx - 13, cy + 4)
      ..quadraticBezierTo(cx, cy + 1, cx + 13, cy + 4)
      ..lineTo(cx + 16, cy + 14)
      ..lineTo(cx - 16, cy + 14)
      ..close();
    canvas.drawPath(
      liquidPath,
      Paint()
        ..color = const Color(0xFF33CC33).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    // Bubbles inside liquid
    canvas.drawCircle(
      Offset(cx - 4, cy + 8),
      2.5,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(cx + 5, cy + 6),
      1.8,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(cx - 1, cy + 12),
      1.5,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.4),
    );

    // Beaker rim
    canvas.drawLine(
      Offset(cx - 12, cy - 16),
      Offset(cx + 12, cy - 16),
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Sparkle at top
    _drawSparkle(canvas, Offset(cx + 2, cy - 22), 3, AppColors.starGold);
    _drawSparkle(canvas, Offset(cx - 8, cy - 6), 2, AppColors.electricBlue);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Seed type icon painter ───────────────────────────────────────────────

class _SeedIconPainter extends CustomPainter {
  final int seedType;
  const _SeedIconPainter(this.seedType);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    switch (seedType) {
      case 1: // Grass — small green blades
        final p = Paint()..color = const Color(0xFF33CC33)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx - 4, cy + 6), Offset(cx - 5, cy - 4), p);
        canvas.drawLine(Offset(cx, cy + 6), Offset(cx, cy - 6), p);
        canvas.drawLine(Offset(cx + 4, cy + 6), Offset(cx + 5, cy - 4), p);
      case 2: // Flower — stem + bloom
        final stem = Paint()..color = const Color(0xFF33AA33)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 7), Offset(cx, cy - 1), stem);
        final bloom = Paint()..color = const Color(0xFFFF88CC);
        for (int i = 0; i < 5; i++) {
          final a = i * 3.14159 * 2 / 5 - 1.57;
          canvas.drawCircle(Offset(cx + cos(a) * 3.5, cy - 4 + sin(a) * 3.5), 2, bloom);
        }
        canvas.drawCircle(Offset(cx, cy - 4), 1.5, Paint()..color = const Color(0xFFFFDD44));
      case 3: // Tree — trunk + canopy
        final trunk = Paint()..color = const Color(0xFF8B6914)..strokeWidth = 2.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 7), Offset(cx, cy - 1), trunk);
        final canopy = Paint()..color = const Color(0xFF228B22);
        canvas.drawCircle(Offset(cx, cy - 5), 5, canopy);
      case 4: // Mushroom — cap + stem
        final stem = Paint()..color = const Color(0xFFF0E0D0)..strokeWidth = 2..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 6), Offset(cx, cy - 1), stem);
        final cap = Paint()..color = const Color(0xFFCC3333);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy - 2), width: 14, height: 10), 3.14159, 3.14159, true, cap);
        // White spots
        final spot = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(cx - 2, cy - 4), 1.2, spot);
        canvas.drawCircle(Offset(cx + 3, cy - 3), 1, spot);
      case 5: // Vine — curling tendril
        final p = Paint()..color = const Color(0xFF33AA33)..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(cx - 4, cy + 6)
          ..quadraticBezierTo(cx - 6, cy, cx - 2, cy - 2)
          ..quadraticBezierTo(cx + 4, cy - 5, cx + 2, cy - 8);
        canvas.drawPath(path, p);
        // Leaf
        final leaf = Paint()..color = const Color(0xFF33CC33);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx + 3, cy - 4), width: 5, height: 3), leaf);
    }
  }

  @override
  bool shouldRepaint(_SeedIconPainter old) => old.seedType != seedType;
}

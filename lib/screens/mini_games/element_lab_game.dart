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

  // -- Dirty chunk system (Optimization 1) ------------------------------------
  // 16x16 chunks — dimensions computed in _initGrid based on grid size
  int _chunkCols = 0; // number of chunks horizontally
  int _chunkRows = 0; // number of chunks vertically
  late Uint8List _dirtyChunks;     // 1 = dirty this frame
  late Uint8List _nextDirtyChunks; // accumulates dirty for next frame

  // -- Clock bit for double-simulation prevention (Optimization 2) -----------
  bool _simClock = false; // toggles each frame; bit 7 of _flags stores cell clock

  // -- Pheromone grids (dual pheromone system for ant AI) ---------------------
  late Uint8List _pheroFood; // food pheromone intensity per cell (0-255)
  late Uint8List _pheroHome; // home pheromone intensity per cell (0-255)

  // -- Colony tracking -------------------------------------------------------
  int _colonyX = -1; // colony centroid X
  int _colonyY = -1; // colony centroid Y
  int _colonyUpdateFrame = 0; // last frame colony was recalculated

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

  // -- Micro-particle effects (rendered in pixel buffer, not grid) ----------
  // Each particle: [x, y, r, g, b, framesLeft]
  final List<Int32List> _microParticles = [];
  static const int _maxMicroParticles = 120;

  // -- Cached glow buffers (rebuilt every 3rd frame) -----------------------
  Uint8List? _cachedGlowR;
  Uint8List? _cachedGlowG;
  Uint8List? _cachedGlowB;

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
    _markAllDirty();
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

    // Initialize dirty chunk system (16x16 chunks)
    _chunkCols = (_gridW + 15) ~/ 16; // ceil division
    _chunkRows = (_gridH + 15) ~/ 16;
    final totalChunks = _chunkCols * _chunkRows;
    _dirtyChunks = Uint8List(totalChunks);
    _nextDirtyChunks = Uint8List(totalChunks);
    // Mark all chunks dirty on first frame
    _dirtyChunks.fillRange(0, totalChunks, 1);

    // Initialize pheromone grids for ant AI
    _pheroFood = Uint8List(totalCells);
    _pheroHome = Uint8List(totalCells);
    _colonyX = -1;
    _colonyY = -1;

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
    _tickMicroParticles();
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
    _markAllDirty();

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
    // Toggle simulation clock (Optimization 2: clock bit)
    _simClock = !_simClock;
    final currentClockBit = _simClock ? 0x80 : 0;

    // Process pending explosions
    _processExplosions();

    // ── Pheromone evaporation (every 8 frames) ──────────────────────────
    if (_frameCount % 8 == 0) {
      _evaporatePheromones();
    }

    // ── Pheromone diffusion (every 4 frames) ────────────────────────────
    if (_frameCount % 4 == 0) {
      _diffusePheromones();
    }

    // ── Colony centroid update (every 30 frames ≈ 1 second) ─────────────
    if (_frameCount % 30 == 0) {
      _updateColonyCentroid();
    }

    // Advance rainbow hue
    _rainbowHue = (_rainbowHue + 3) % 360;

    // Decrease lightning flash
    if (_lightningFlashFrames > 0) _lightningFlashFrames--;

    // Cache dirty chunks for read, nextDirty for write
    final dc = _dirtyChunks;
    final cols = _chunkCols;
    final w = _gridW;

    // Scan from gravity-bottom to top, left-right alternating
    final leftToRight = _frameCount.isEven;
    final yStart = _gravityDir == 1 ? _gridH - 2 : 1;
    final yEnd = _gravityDir == 1 ? -1 : _gridH;
    final yStep = _gravityDir == 1 ? -1 : 1;
    for (int y = yStart; y != yEnd; y += yStep) {
      final chunkY = y >> 4; // y ~/ 16
      final startX = leftToRight ? 0 : _gridW - 1;
      final endX = leftToRight ? _gridW : -1;
      final dx = leftToRight ? 1 : -1;
      for (int x = startX; x != endX; x += dx) {
        // Optimization 1: Skip cells in clean chunks
        final chunkIdx = chunkY * cols + (x >> 4);
        if (dc[chunkIdx] == 0) continue;

        final idx = y * w + x;

        // Optimization 2: Clock bit — skip if already processed this frame
        // Check bit 7 matches current clock
        final flagVal = _flags[idx];
        if ((flagVal & 0x80) == currentClockBit) continue;

        final el = _grid[idx];
        if (el == El.empty) continue;

        // Optimization 3: Static cell detection using bits 4-6 of _flags
        // Bit 6 (0x40) = settled flag
        // Bits 4-5 = stable counter (0-3)
        if ((flagVal & 0x40) != 0) {
          // Cell is settled — skip simulation but propagate dirty to next frame
          // (chunk is already dirty so neighbors get checked)
          continue;
        }

        // Save pre-simulation state for settled detection
        final preEl = el;
        final preIdx = idx;

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

        // Optimization 3: Static cell detection — check if cell moved or changed
        // If the cell is still at the same index with the same element type,
        // it didn't move. Increment stable counter (bits 4-5).
        if (_grid[preIdx] == preEl && (_flags[preIdx] & 0x80) != currentClockBit) {
          // Cell didn't move (wasn't swapped — _swap sets clock bit)
          final oldStable = (flagVal >> 4) & 0x03; // bits 4-5
          final newStable = (oldStable + 1).clamp(0, 3);
          if (newStable >= 3) {
            // Mark as settled (bit 6) — preserve bits 4-5 at max
            _flags[preIdx] = (_flags[preIdx] & 0x80) | 0x70; // settled + stable=3
          } else {
            // Increment stable counter, preserve clock bit
            _flags[preIdx] = (_flags[preIdx] & 0x80) | (newStable << 4);
          }
          // Still mark chunk dirty since neighbors may need processing
          _markDirty(x, y);
        } else if (_grid[preIdx] != preEl) {
          // Cell changed type (e.g. fire→ash, steam→empty, element died)
          // Mark dirty and unsettle neighbors so they react next frame
          _markDirty(x, y);
          _unsettleNeighbors(x, y);
        }
      }
    }

    // Swap dirty chunk buffers for next frame
    final tmp = _dirtyChunks;
    _dirtyChunks = _nextDirtyChunks;
    _nextDirtyChunks = tmp;
    _nextDirtyChunks.fillRange(0, _nextDirtyChunks.length, 0);
  }

  // ── Element behaviors ───────────────────────────────────────────────────

  void _simSand(int x, int y, int idx) {
    // Lightning hitting sand -> glass
    if (_checkAdjacent(x, y, El.lightning)) {
      _grid[idx] = El.glass;
      _life[idx] = 0;
      _markProcessed(idx);
      return;
    }

    // Check for water below or adjacent -> become mud
    if (_checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.mud;
      _removeOneAdjacent(x, y, El.water);
      _markProcessed(idx);
      return;
    }

    _fallGranular(x, y, idx, El.sand);
  }

  void _simWater(int x, int y, int idx) {
    final g = _gravityDir;
    final by = y + g;
    final uy = y - g;

    // ── Mass initialization (upgrade legacy water with _life==0) ────────
    // _life for water stores mass (20-240, 100=normal).
    // Special values: 140-199 = ice-melt visual, 200+ = electrified.
    final lifeVal = _life[idx];
    final bool isSpecialState = lifeVal >= 140;
    int mass = isSpecialState ? 100 : (lifeVal < 20 ? 100 : lifeVal);
    // Fix legacy water that has _life=0
    if (!isSpecialState && lifeVal < 20) {
      _life[idx] = 100;
    }

    // ── Neighbor reactions ──────────────────────────────────────────────

    // Check for adjacent ice → freeze (1 in 60 chance, slower than before)
    if (_rng.nextInt(60) == 0 && _checkAdjacent(x, y, El.ice)) {
      _grid[idx] = El.ice;
      _markProcessed(idx);
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
            _markProcessed(idx);
            return;
          }
        }
      }
    }

    // Water + Oil: oil floats — only swap if water is BELOW oil (water sinks under oil)
    final uy2 = y - _gravityDir;
    if (_inBounds(x, uy2) && _grid[uy2 * _gridW + x] == El.oil && !((_flags[uy2 * _gridW + x] & 0x80) == (_simClock ? 0x80 : 0))) {
      final ui2 = uy2 * _gridW + x;
      _grid[idx] = El.oil;
      _grid[ui2] = El.water;
      _life[ui2] = mass; // preserve mass through oil swap
      _markProcessed(idx);
      _markProcessed(ui2);
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
          _markProcessed(ni);
        }
        // Water absorbs smoke
        if (neighbor == El.smoke && _rng.nextInt(10) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        // Water + Rainbow → prismatic refraction (spawn extra rainbow)
        if (neighbor == El.rainbow && _rng.nextInt(40) == 0) {
          final rx = x + _rng.nextInt(3) - 1;
          final ry = uy;
          if (_inBounds(rx, ry) && _grid[ry * _gridW + rx] == El.empty) {
            _grid[ry * _gridW + rx] = El.rainbow;
            _life[ry * _gridW + rx] = 0;
            _markProcessed(ry * _gridW + rx);
          }
        }
        // Water nourishes plant
        if (neighbor == El.plant && _rng.nextInt(20) == 0) {
          if (_life[ni] > 2) _life[ni] -= 2;
        }
      }
    }

    // ── Pressure calculation (scan down, max 8 cells) ───────────────────
    // Each water cell below adds ~10 to pressure; clamped for performance
    int pressure = 0;
    for (int cy = y + g, depth = 0; depth < 8 && _inBounds(x, cy); cy += g, depth++) {
      if (_grid[cy * _gridW + x] == El.water) {
        pressure += 10;
      } else {
        break;
      }
    }
    // Also count water above for total column (used for leveling)
    int colAbove = 0;
    for (int cy = y - g; _inBounds(x, cy) && colAbove < 12; cy -= g) {
      final c = _grid[cy * _gridW + x];
      if (c == El.water || c == El.oil) {
        colAbove++;
      } else {
        break;
      }
    }
    final totalCol = (pressure ~/ 10) + 1 + colAbove;

    // ── Pressure-based mass compression ─────────────────────────────────
    if (!isSpecialState) {
      final targetMass = (100 + (pressure * 0.5).round()).clamp(20, 139);
      if (mass < targetMass) {
        mass = (mass + 3).clamp(20, 139);
      } else if (mass > targetMass) {
        mass = (mass - 3).clamp(20, 139);
      }
      _life[idx] = mass;
    }

    // ── Bubble generation under high pressure ───────────────────────────
    if (mass > 130 && _rng.nextInt(500) == 0) {
      final bubbleY = y - g;
      if (_inBounds(x, bubbleY)) {
        final bubbleIdx = bubbleY * _gridW + x;
        if (_grid[bubbleIdx] == El.water) {
          _grid[bubbleIdx] = El.bubble;
          _life[bubbleIdx] = 0;
          _markProcessed(bubbleIdx);
        }
      }
    }

    // ── Pressure-based vertical mass transfer ───────────────────────────
    if (!isSpecialState && mass > 110 && _inBounds(x, uy)) {
      final aboveI = uy * _gridW + x;
      if (_grid[aboveI] == El.water && _life[aboveI] < 140) {
        final aboveMass = _life[aboveI] < 20 ? 100 : _life[aboveI];
        final diff = mass - aboveMass;
        if (diff > 8) {
          final transfer = (diff ~/ 4).clamp(1, 20);
          mass = (mass - transfer).clamp(20, 139);
          final newAbove = (aboveMass + transfer).clamp(20, 139);
          _life[idx] = mass;
          _life[aboveI] = newAbove;
        }
      }
    }

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
          final splashIdx = sy * _gridW + sx;
          _grid[splashIdx] = El.water;
          // Split mass between splash droplets
          final splashMass = (mass ~/ 2).clamp(20, 139);
          _life[splashIdx] = splashMass;
          _markProcessed(splashIdx);
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _velY[idx] = 0;
          return;
        }
      }
    }
    _velY[idx] = 0;

    // Use momentum: prefer previous flow direction
    // Random bias each frame to prevent oscillation
    final momentum = _velX[idx];
    final frameBias = _rng.nextBool();
    final dl = momentum != 0 ? (momentum > 0) : frameBias;
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

    // ── Pressure-driven lateral flow ────────────────────────────────────
    final flowDist = 2 + (pressure ~/ 15).clamp(0, 5);

    // Mass-differential flow: prefer flowing toward lower-mass neighbors
    if (!isSpecialState) {
      for (final dir in dl ? [1, -1] : [-1, 1]) {
        final nx = x + dir;
        if (!_inBounds(nx, y)) continue;
        final ni = y * _gridW + nx;
        if (_grid[ni] == El.water && _life[ni] < 140) {
          final neighborMass = _life[ni] < 20 ? 100 : _life[ni];
          final diff = mass - neighborMass;
          if (diff > 5) {
            final transfer = (diff ~/ 3).clamp(1, 20);
            _life[idx] = (mass - transfer).clamp(20, 139);
            _life[ni] = (neighborMass + transfer).clamp(20, 139);
          }
        }
      }
    }

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

    // ── Surface leveling — water seeks its own level ────────────────────
    final aboveEl = _inBounds(x, uy) ? _grid[uy * _gridW + x] : -1;
    if (aboveEl == El.empty || aboveEl == -1) {
      for (final dir in [1, -1]) {
        final nx = x + dir;
        if (!_inBounds(nx, y)) continue;
        final nIdx = y * _gridW + nx;
        if (_grid[nIdx] != El.empty) continue;
        final belowNx = y + g;
        if (!_inBounds(nx, belowNx)) continue;
        final belowCell = _grid[belowNx * _gridW + nx];
        if (belowCell == El.empty) continue;
        int adjCol = 0;
        for (int cy = y + g; _inBounds(nx, cy) && adjCol < 12; cy += g) {
          if (_grid[cy * _gridW + nx] == El.water) {
            adjCol++;
          } else {
            break;
          }
        }
        if (totalCol > adjCol + 1) {
          _velX[idx] = dir;
          _swap(idx, nIdx);
          return;
        }
      }
      // Extended surface leveling: scan up to 4 cells out
      for (final dir in [1, -1]) {
        for (int d = 2; d <= 4; d++) {
          final nx = x + dir * d;
          if (!_inBounds(nx, y)) continue;
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

          // Count target column height for mass-aware leveling
          int targetCol = 0;
          for (int cy = y + g; _inBounds(nx, cy) && targetCol < 12; cy += g) {
            if (_grid[cy * _gridW + nx] == El.water) {
              targetCol++;
            } else {
              break;
            }
          }
          if (totalCol > targetCol + 1) {
            _velX[idx] = dir;
            _swap(idx, y * _gridW + nx);
            return;
          }
        }
      }

      // ── Smooth mass-based surface leveling ──────────────────────────
      if (!isSpecialState) {
        for (final dir in [1, -1]) {
          for (int d = 1; d <= 4; d++) {
            final nx = x + dir * d;
            if (!_inBounds(nx, y)) break;
            final ni = y * _gridW + nx;
            if (_grid[ni] != El.water) break;
            final naboveY = y - g;
            if (!_inBounds(nx, naboveY)) continue;
            if (_grid[naboveY * _gridW + nx] != El.empty) continue;
            final nlife = _life[ni];
            if (nlife >= 140) continue;
            final nMass = nlife < 20 ? 100 : nlife;
            final mDiff = mass - nMass;
            if (mDiff.abs() > 3) {
              final transfer = (mDiff ~/ 3).clamp(-5, 5);
              final newMass = (mass - transfer).clamp(20, 139);
              final newNMass = (nMass + transfer).clamp(20, 139);
              _life[idx] = newMass;
              _life[ni] = newNMass;
              mass = newMass;
            }
          }
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
      _markProcessed(idx);
      // Spawn smoke above ~50% of the time
      final uy = y - _gravityDir;
      if (_rng.nextBool() && _inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        _grid[uy * _gridW + x] = El.smoke;
        _life[uy * _gridW + x] = 0;
        _markProcessed(uy * _gridW + x);
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
          _markProcessed(ni);
          return;
        }
        if ((neighbor == El.plant || neighbor == El.seed) && _rng.nextInt(2) == 0) {
          // Fire spreads to plant/seed aggressively
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        if (neighbor == El.wood && _rng.nextInt(4) == 0) {
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        if (neighbor == El.oil) {
          // Oil is very flammable — always ignites
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        // Ash is already burned — fire does nothing to it
        if (neighbor == El.ice) {
          _grid[ni] = El.water;
          _life[ni] = 150; // melting visual
          _markProcessed(ni);
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
      _markProcessed(idx);
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
        _markProcessed(idx);
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
          _markProcessed(ni);
        }
        if (neighbor == El.water) {
          _electrifyWater(nx, ny);
        }
        if (neighbor == El.sand) {
          _grid[ni] = El.glass;
          _life[ni] = 0;
          _markProcessed(ni);
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
      _markProcessed(ni);
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
  static const _plantMaxH = [0, 3, 6, 15, 3, 12];
  static const _plantMinMoist = [0, 1, 2, 3, 4, 2];
  static const _plantGrowRate = [0, 25, 35, 20, 40, 30];
  int _selectedSeedType = 1; // kPlantGrass

  void _simSeed(int x, int y, int idx) {
    final sType = _velX[idx].clamp(1, 5);
    _life[idx]++;
    if (_checkAdjacent(x, y, El.fire) || _checkAdjacent(x, y, El.lava)) {
      _grid[idx] = El.ash; _life[idx] = 0; _velX[idx] = 0; _markProcessed(idx); return;
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
          _setPlantData(idx, sType, kStSprout); _velY[idx] = 1; _markProcessed(idx); return;
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
        _markProcessed(idx);
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
            _markProcessed(ni);
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
    final preservedMass = _life[wi]; // preserve water mass
    for (int r = 1; r <= 10; r++) {
      final uy = wy - _gravityDir * r;
      if (_inBounds(wx, uy) && _grid[uy * _gridW + wx] == El.empty) {
        _grid[uy * _gridW + wx] = El.water;
        _life[uy * _gridW + wx] = preservedMass;
        _markProcessed(uy * _gridW + wx);
        _grid[wi] = El.empty;
        _life[wi] = 0;
        _markProcessed(wi);
        return;
      }
      for (final dx in [r, -r]) {
        final nx = wx + dx;
        if (_inBounds(nx, wy) && _grid[wy * _gridW + nx] == El.empty) {
          _grid[wy * _gridW + nx] = El.water;
          _life[wy * _gridW + nx] = preservedMass;
          _markProcessed(wy * _gridW + nx);
          _grid[wi] = El.empty;
          _life[wi] = 0;
          _markProcessed(wi);
          return;
        }
        final uy2 = wy - _gravityDir * r;
        if (_inBounds(nx, uy2) && _grid[uy2 * _gridW + nx] == El.empty) {
          _grid[uy2 * _gridW + nx] = El.water;
          _life[uy2 * _gridW + nx] = preservedMass;
          _markProcessed(uy2 * _gridW + nx);
          _grid[wi] = El.empty;
          _life[wi] = 0;
          _markProcessed(wi);
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
          _markProcessed(idx);
          _markProcessed(below);
        } else {
          _displaceWater(x, by);
          if (_grid[below] == El.empty) {
            _grid[below] = elType;
            _life[below] = _life[idx];
            _velY[below] = _velY[idx];
            _grid[idx] = El.empty;
            _life[idx] = 0;
            _velY[idx] = 0;
            _markProcessed(idx);
            _markProcessed(below);
          } else {
            _grid[idx] = El.water;
            _grid[below] = elType;
            _life[below] = _life[idx];
            _life[idx] = 100; // water mass
            _markProcessed(idx);
            _markProcessed(below);
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
      _markProcessed(idx); return;
    }
    // Acid dissolves over ~20 frames
    if (_checkAdjacent(x, y, El.acid) && _rng.nextInt(3) == 0) {
      _grid[idx] = El.empty; _life[idx] = 0; _velX[idx] = 0; _velY[idx] = 0;
      _markProcessed(idx); return;
    }

    // ── Dead plant decomposes to dirt after ~120 frames ──
    if (pStage == kStDead) {
      _velY[idx] = (_velY[idx] + 1).clamp(0, 127).toInt();
      if (_velY[idx] > 120) {
        _grid[idx] = El.dirt; _life[idx] = 0; _velX[idx] = 0; _velY[idx] = 0;
        _markProcessed(idx);
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
    // Grass: 2-3 tall, spreads sideways
    if (curSize < 3) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        _setPlantData(ni, kPlantGrass, kStGrowing); _velY[ni] = (curSize + 1);
        _markProcessed(ni);
        _velY[idx] = (curSize + 1);
      }
    }
    // Spread sideways on dirt surface
    if (_rng.nextInt(40) == 0) {
      final side = _rng.nextBool() ? x - 1 : x + 1;
      final by = y + _gravityDir;
      if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty &&
          _inBounds(side, by) && _grid[by * _gridW + side] == El.dirt) {
        final ni = y * _gridW + side;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        _setPlantData(ni, kPlantGrass, kStSprout); _velY[ni] = 1;
        _markProcessed(ni);
      }
    }
  }

  void _growFlower(int x, int y, int idx, int curSize) {
    // Flower: grows up 4-6 cells, bloom at top
    if (curSize < 6) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        // Top 1-2 cells are bloom (stage = mature marks bloom)
        final newSize = curSize + 1;
        _setPlantData(ni, kPlantFlower, newSize >= 4 ? kStMature : kStGrowing);
        _velY[ni] = newSize;
        _markProcessed(ni);
        _velY[idx] = newSize;
      }
    }
  }

  void _growTree(int x, int y, int idx, int curSize) {
    // Tree: 8-15 tall, trunk then canopy
    if (curSize < 15) {
      final uy = y - _gravityDir;
      if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
        final ni = uy * _gridW + x;
        _grid[ni] = El.plant; _life[ni] = _life[idx];
        final newSize = curSize + 1;
        // Canopy starts at ~50% height
        final isTrunk = newSize < 7;
        _setPlantData(ni, kPlantTree, isTrunk ? kStGrowing : kStMature);
        _velY[ni] = newSize;
        _markProcessed(ni);
        _velY[idx] = newSize;
      }
      // Canopy: spread sideways — wider spread at greater height
      if (curSize >= 6) {
        // Try both sides for a fuller canopy
        for (final side in [x - 1, x + 1]) {
          if (_rng.nextInt(2) == 0) continue; // 50% chance each side
          // Spread at current level and one above
          for (final sy in [y, y - _gravityDir]) {
            if (_inBounds(side, sy) && _grid[sy * _gridW + side] == El.empty) {
              final ni = sy * _gridW + side;
              _grid[ni] = El.plant; _life[ni] = _life[idx];
              _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
              _markProcessed(ni);
              break; // one per side per tick
            }
          }
        }
        // At tall heights, spread 2 cells wide for a rounder canopy
        if (curSize >= 10 && _rng.nextInt(3) == 0) {
          for (final side in [x - 2, x + 2]) {
            if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
              final ni = y * _gridW + side;
              _grid[ni] = El.plant; _life[ni] = _life[idx];
              _setPlantData(ni, kPlantTree, kStMature); _velY[ni] = curSize;
              _markProcessed(ni);
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
        _markProcessed(ni);
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
          _markProcessed(ni);
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
        _velY[ni] = (curSize + 1); _markProcessed(ni);
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
      _markProcessed(idx);
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
          _markProcessed(idx);
          _grid[ni] = El.steam;
          _life[ni] = 0;
          _markProcessed(ni);
          // Spawn 2-3 extra steam cells nearby (explosive evaporation)
          final extraSteam = 2 + _rng.nextInt(2);
          for (int s = 0; s < extraSteam; s++) {
            final sx = x + _rng.nextInt(5) - 2;
            final sy = y - _gravityDir * (1 + _rng.nextInt(2));
            if (_inBounds(sx, sy) && _grid[sy * _gridW + sx] == El.empty) {
              _grid[sy * _gridW + sx] = El.steam;
              _life[sy * _gridW + sx] = 0;
              _markProcessed(sy * _gridW + sx);
            }
          }
          return;
        }
        // Lava + Ice → Stone + Water
        if (neighbor == El.ice) {
          _grid[idx] = El.stone;
          _life[idx] = 0;
          _markProcessed(idx);
          _grid[ni] = El.water;
          _life[ni] = 0;
          _markProcessed(ni);
          return;
        }
        // Ignite flammables
        if ((neighbor == El.plant || neighbor == El.seed ||
             neighbor == El.oil || neighbor == El.wood) &&
            _rng.nextInt(2) == 0) {
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        // Melt snow
        if (neighbor == El.snow) {
          _grid[ni] = El.water;
          _life[ni] = 100; // water mass
          _markProcessed(ni);
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
        _life[idx] = 100; // water mass
        _markProcessed(idx);
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
            _markProcessed(ny * _gridW + nx);
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
      _markProcessed(idx);
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
        _markProcessed(idx);
        // Spawn smoke above
        final uy = y - _gravityDir;
        if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.empty) {
          _grid[uy * _gridW + x] = El.smoke;
          _life[uy * _gridW + x] = 0;
          _markProcessed(uy * _gridW + x);
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
          final waterMass = _life[bi]; // preserve water mass
          _grid[idx] = El.water;
          _life[idx] = waterMass < 20 ? 100 : waterMass;
          _grid[bi] = El.wood;
          _life[bi] = 0;
          _velY[bi] = 3; // keep waterlogged
          _markProcessed(idx);
          _markProcessed(bi);
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
        _markProcessed(idx);
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
            _life[ni] = 100; // water mass
            _markProcessed(ni);
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
      _markProcessed(curIdx);
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
            _markProcessed(ni);
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
            _markProcessed(ni);
            sparks++;
          } else if (_grid[ni] == El.tnt) {
            _pendingExplosions.add(_Explosion(nx, ny, _calculateTNTRadius(nx, ny)));
            sparks++;
          } else if (_rng.nextInt(100) < 30) {
            // Spark reactions (30% chance)
            if (_grid[ni] == El.sand) {
              _grid[ni] = El.glass;
              _life[ni] = 0;
              _markProcessed(ni);
              sparks++;
            } else if (_grid[ni] == El.ice) {
              _grid[ni] = El.water;
              _life[ni] = 150;
              _markProcessed(ni);
              sparks++;
            } else if (_grid[ni] == El.plant || _grid[ni] == El.seed ||
                       _grid[ni] == El.oil || _grid[ni] == El.wood) {
              _grid[ni] = El.fire;
              _life[ni] = 0;
              _markProcessed(ni);
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
          _life[idx] = 100; // water mass
          _markProcessed(ai);
          _markProcessed(idx);
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
              _life[ny * _gridW + nx] = 60; // small droplet mass
              _markProcessed(ny * _gridW + nx);
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
            _markProcessed(idx);
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
            final waterMass2 = _life[bi]; // preserve water mass
            _grid[idx] = El.water;
            _grid[bi] = El.ash;
            _life[bi] = _life[idx];
            _velX[bi] = _velX[idx];
            _life[idx] = waterMass2 < 20 ? 100 : waterMass2;
            _velX[idx] = 0;
            _markProcessed(idx);
            _markProcessed(bi);
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
      _markProcessed(idx);
      return;
    }

    // Condensation: steam touching water → back to water (night: 2x faster)
    final condenseChance = _isNight ? 15 : 30;
    if (_rng.nextInt(condenseChance) == 0 && _checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.water;
      _life[idx] = 100; // water mass
      _markProcessed(idx);
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

  // ── Pheromone system ──────────────────────────────────────────────────────

  /// Evaporate both pheromone grids — decay each cell by 1 (called every 8 frames).
  void _evaporatePheromones() {
    final total = _gridW * _gridH;
    final pf = _pheroFood;
    final ph = _pheroHome;
    for (int i = 0; i < total; i++) {
      if (pf[i] > 0) pf[i] = pf[i] - 1;
      if (ph[i] > 0) ph[i] = ph[i] - 1;
    }
  }

  /// Diffuse pheromones to cardinal neighbors (called every 4 frames).
  /// Each cell with pheromone > 2 spreads 1/8 of its value to 4 neighbors.
  void _diffusePheromones() {
    final w = _gridW;
    final h = _gridH;
    final g = _grid;
    final pf = _pheroFood;
    final ph = _pheroHome;

    // Process food pheromone diffusion
    for (int y = 1; y < h - 1; y++) {
      final row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final i = row + x;
        final fv = pf[i];
        if (fv > 2) {
          final spread = fv >> 3; // 1/8
          if (spread > 0) {
            // Only spread to empty cells
            if (g[i - 1] == El.empty) pf[i - 1] = (pf[i - 1] + spread).clamp(0, 255);
            if (g[i + 1] == El.empty) pf[i + 1] = (pf[i + 1] + spread).clamp(0, 255);
            if (g[i - w] == El.empty) pf[i - w] = (pf[i - w] + spread).clamp(0, 255);
            if (g[i + w] == El.empty) pf[i + w] = (pf[i + w] + spread).clamp(0, 255);
          }
        }
        final hv = ph[i];
        if (hv > 2) {
          final spread = hv >> 3;
          if (spread > 0) {
            if (g[i - 1] == El.empty) ph[i - 1] = (ph[i - 1] + spread).clamp(0, 255);
            if (g[i + 1] == El.empty) ph[i + 1] = (ph[i + 1] + spread).clamp(0, 255);
            if (g[i - w] == El.empty) ph[i - w] = (ph[i - w] + spread).clamp(0, 255);
            if (g[i + w] == El.empty) ph[i + w] = (ph[i + w] + spread).clamp(0, 255);
          }
        }
      }
    }
  }

  /// Update colony centroid by averaging positions of all ants.
  void _updateColonyCentroid() {
    int sumX = 0, sumY = 0, count = 0;
    final w = _gridW;
    final total = w * _gridH;
    for (int i = 0; i < total; i++) {
      if (_grid[i] == El.ant) {
        sumX += i % w;
        sumY += i ~/ w;
        count++;
      }
    }
    if (count > 0) {
      _colonyX = sumX ~/ count;
      _colonyY = sumY ~/ count;
    }
  }

  // ── Ant AI system ──────────────────────────────────────────────────────────
  // Ant states stored in _velY:
  //   0 = explorer (searching outward for dirt/food)
  //   1 = digger (actively tunneling into dirt)
  //   2 = carrier (carrying dirt to surface to build mound)
  //   3 = returning (heading back to colony after depositing)
  //   4 = forager (recruited, following food pheromone to food source)
  //  10+ = drowning counter (in water)
  // _life stores "home X" coordinate (0-159) so ants remember their colony.
  // _velX stores movement direction (-1 or 1).
  //
  // Dual pheromone system:
  //   _pheroFood[idx] — deposited by returning/carrier ants; guides explorers to food
  //   _pheroHome[idx] — deposited by exploring/foraging ants; guides returners home

  /// Check if a cell is "underground" (has solid above it, toward surface).
  bool _isUnderground(int x, int y) {
    final g = _gravityDir;
    final aboveY = y - g;
    if (!_inBounds(x, aboveY)) return false;
    final above = _grid[aboveY * _gridW + x];
    return above == El.dirt || above == El.mud || above == El.stone ||
           above == El.sand || above == El.ant;
  }

  // Ant state constants
  static const int _antExplorerState = 0;
  static const int _antDiggerState = 1;
  static const int _antCarrierState = 2;
  static const int _antReturningState = 3;
  static const int _antForagerState = 4;
  static const int _antDrowningBase = 10;

  void _simAnt(int x, int y, int idx) {
    int state = _velY[idx];

    // Carrier ants (hasFood) move every frame; others every 2 frames
    final isCarrying = (state == _antCarrierState);
    if (!isCarrying && _frameCount % 2 != 0) return;

    final g = _gravityDir;
    final by = y + g;
    final uy = y - g;
    final homeX = _life[idx]; // colony X position
    final w = _gridW;

    // ── Hazards ──────────────────────────────────────────────────────

    // Acid kills instantly
    if (_checkAdjacent(x, y, El.acid)) {
      _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      return;
    }

    // Fire — flee or die
    if (_checkAdjacent(x, y, El.fire)) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx2 = x + dx, ny2 = y + dy;
          if (!_inBounds(nx2, ny2)) continue;
          if (_grid[ny2 * w + nx2] == El.empty && !_checkAdjacent(nx2, ny2, El.fire)) {
            _swap(idx, ny2 * w + nx2);
            return;
          }
        }
      }
      _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      return;
    }

    // Drowning in water
    if (_checkAdjacent(x, y, El.water)) {
      if (state < _antDrowningBase) {
        _velY[idx] = _antDrowningBase;
        state = _antDrowningBase;
      }
      if (_inBounds(x, uy) && _rng.nextInt(3) == 0) {
        final ac = _grid[uy * w + x];
        if (ac == El.empty || ac == El.water) { _swap(idx, uy * w + x); return; }
      }
      for (final dir in [1, -1]) {
        final sx = x + dir;
        if (_inBounds(sx, y) && _grid[y * w + sx] == El.empty) {
          _swap(idx, y * w + sx); return;
        }
      }
      _velY[idx] = (state + 1);
      if (_velY[idx] > 100) {
        _grid[idx] = El.empty; _life[idx] = 0; _velY[idx] = 0;
      }
      return;
    }
    if (state >= _antDrowningBase) { _velY[idx] = 0; state = 0; }

    // ── Initialize home position ──────────────────────────────────────
    if (_life[idx] == 0) {
      _life[idx] = x.clamp(1, 255);
      // Set initial colony position from first ant
      if (_colonyX < 0) { _colonyX = x; _colonyY = y; }
    }
    if (_velX[idx] == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;

    // ── Gravity — fall if no ground ───────────────────────────────────
    if (_inBounds(x, by) && _grid[by * w + x] == El.empty) {
      _swap(idx, by * w + x);
      return;
    }

    // ── Pheromone deposit ─────────────────────────────────────────────
    // Explorers/foragers deposit home pheromone as they move outward
    if (state == _antExplorerState || state == _antForagerState) {
      if (_pheroHome[idx] < 120) _pheroHome[idx] = 120;
    }
    // Carriers/returners deposit food pheromone as they head home
    if (state == _antCarrierState || state == _antReturningState) {
      if (_pheroFood[idx] < 120) _pheroFood[idx] = 120;
    }

    // ── Colony distance check — far ants tend to return ───────────────
    if (_colonyX >= 0 && state == _antExplorerState) {
      final dist = (x - _colonyX).abs() + (y - _colonyY).abs();
      if (dist > 60 && _rng.nextInt(8) == 0) {
        _velY[idx] = _antReturningState;
        state = _antReturningState;
      }
    }

    // ── Recruitment: nearby ants detect strong food pheromone ─────────
    if (state == _antExplorerState && _frameCount % 4 == 0) {
      // Check 5-cell radius for strong food pheromone → become forager
      int bestPhero = 0;
      for (int dy = -5; dy <= 5; dy++) {
        for (int dx = -5; dx <= 5; dx++) {
          final nx2 = x + dx, ny2 = y + dy;
          if (!_inBounds(nx2, ny2)) continue;
          final ni = ny2 * w + nx2;
          if (_pheroFood[ni] > bestPhero) bestPhero = _pheroFood[ni];
        }
      }
      if (bestPhero > 100 && _rng.nextInt(3) == 0) {
        _velY[idx] = _antForagerState;
        state = _antForagerState;
      }
    }

    // ── STATE MACHINE ─────────────────────────────────────────────────
    final underground = _isUnderground(x, y);
    final nearDirt = _checkAdjacent(x, y, El.dirt);

    switch (state) {
      case _antExplorerState:
        _antExplore(x, y, idx, homeX, nearDirt, underground);
      case _antDiggerState:
        _antDig(x, y, idx, underground);
      case _antCarrierState:
        _antCarry(x, y, idx, homeX);
      case _antReturningState:
        _antReturn(x, y, idx, homeX);
      case _antForagerState:
        _antForage(x, y, idx, homeX, nearDirt);
    }
  }

  /// Choose direction using weighted pheromone sampling.
  /// Checks 3 forward-facing cells and picks the one with highest
  /// (pheromone + random noise). Returns chosen direction or current dir.
  int _antPheromoneDir(int x, int y, int dir, Uint8List pheroGrid) {
    final w = _gridW;
    // 5% exploration noise — random direction
    if (_rng.nextInt(20) == 0) return _rng.nextBool() ? 1 : -1;

    // Forward cells: straight, forward-left, forward-right
    // "Forward" = in direction of dir horizontally
    final candidates = <int, int>{}; // direction → weighted score
    // Straight ahead
    final fwdX = x + dir;
    if (_inBounds(fwdX, y)) {
      final fi = y * w + fwdX;
      candidates[dir] = pheroGrid[fi] + _rng.nextInt(10);
    }
    // Forward-up (diagonal)
    final uy = y - _gravityDir;
    if (_inBounds(fwdX, uy)) {
      final fi = uy * w + fwdX;
      // Use dir as key (biased toward forward)
      final score = pheroGrid[fi] + _rng.nextInt(10);
      if (!candidates.containsKey(dir) || score > candidates[dir]!) {
        candidates[dir] = score;
      }
    }
    // Opposite side (to consider turning)
    final bwdX = x - dir;
    if (_inBounds(bwdX, y)) {
      final fi = y * w + bwdX;
      candidates[-dir] = pheroGrid[fi] + _rng.nextInt(10);
    }

    if (candidates.isEmpty) return dir;

    // Pick highest-scored direction
    int bestDir = dir;
    int bestScore = -1;
    for (final entry in candidates.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestDir = entry.key;
      }
    }
    // Only follow pheromone if the signal is meaningful
    return bestScore > 5 ? bestDir : dir;
  }

  void _antExplore(int x, int y, int idx, int homeX, bool nearDirt, bool underground) {
    int dir = _velX[idx];

    // If adjacent to dirt and not too many ants nearby, start digging
    if (nearDirt && _rng.nextInt(4) == 0) {
      int nearbyAnts = 0;
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          if (_inBounds(x + dx, y + dy) && _grid[(y + dy) * _gridW + (x + dx)] == El.ant) nearbyAnts++;
        }
      }
      if (nearbyAnts < 5) {
        _velY[idx] = _antDiggerState;
        return;
      }
    }

    // Use food pheromone to guide toward food sources
    dir = _antPheromoneDir(x, y, dir, _pheroFood);

    // Scan for dirt — prefer it over empty space
    int targetDir = dir;
    bool foundTarget = false;
    for (int scanD = 1; scanD <= 8; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!_inBounds(sx, y)) continue;
        final sc = _grid[y * _gridW + sx];
        if (sc == El.dirt || sc == El.mud) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        if (sc == El.ant && _rng.nextInt(3) == 0) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        if (sc == El.water || sc == El.acid || sc == El.lava || sc == El.fire) {
          if (sd == dir) targetDir = -dir;
          break;
        }
      }
      if (foundTarget) break;
    }

    // Near colony with no food found? Bias away from strong home pheromone
    if (!foundTarget && _colonyX >= 0) {
      final dist = (x - _colonyX).abs() + (y - _colonyY).abs();
      if (dist < 10 && _rng.nextInt(3) == 0) {
        // Head away from colony (toward unexplored)
        targetDir = (x >= _colonyX) ? 1 : -1;
      }
    }

    _antMove(x, y, idx, targetDir);
  }

  void _antForage(int x, int y, int idx, int homeX, bool nearDirt) {
    int dir = _velX[idx];

    // Forager found dirt — deposit food pheromone burst and start digging
    if (nearDirt) {
      _pheroFood[idx] = 200; // strong burst at food source
      // Recruit nearby ants
      _antRecruitNearby(x, y);
      _velY[idx] = _antDiggerState;
      return;
    }

    // Follow food pheromone toward food sources
    dir = _antPheromoneDir(x, y, dir, _pheroFood);

    // Scan for dirt like explorer but with more determination
    int targetDir = dir;
    bool foundTarget = false;
    for (int scanD = 1; scanD <= 12; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!_inBounds(sx, y)) continue;
        final sc = _grid[y * _gridW + sx];
        if (sc == El.dirt || sc == El.mud) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        if (sc == El.water || sc == El.acid || sc == El.lava || sc == El.fire) {
          if (sd == dir) targetDir = -dir;
          break;
        }
      }
      if (foundTarget) break;
    }

    // If wandering too long as forager without finding food, revert to explorer
    if (!foundTarget && _rng.nextInt(60) == 0) {
      _velY[idx] = _antExplorerState;
    }

    _antMove(x, y, idx, targetDir);
  }

  /// Recruit nearby ants within 5 cells to become foragers.
  void _antRecruitNearby(int x, int y) {
    final w = _gridW;
    for (int dy = -5; dy <= 5; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        final nx2 = x + dx, ny2 = y + dy;
        if (!_inBounds(nx2, ny2)) continue;
        final ni = ny2 * w + nx2;
        if (_grid[ni] == El.ant && _velY[ni] == _antExplorerState) {
          if (_rng.nextInt(2) == 0) {
            _velY[ni] = _antForagerState;
            // Point recruited ant toward the food
            _velX[ni] = dx >= 0 ? 1 : -1;
          }
        }
      }
    }
  }

  void _antDig(int x, int y, int idx, bool underground) {
    final g = _gravityDir;
    final by = y + g;
    final dir = _velX[idx];
    final w = _gridW;

    // Try to dig downward first (create vertical shafts)
    if (_inBounds(x, by) && _grid[by * w + x] == El.dirt) {
      if (_rng.nextInt(3) == 0) {
        _grid[by * w + x] = El.empty;
        _life[by * w + x] = 0;
        _swap(idx, by * w + x);
        _velY[idx] = _antCarrierState;
        // Deposit strong food pheromone at dig site
        _pheroFood[by * w + x] = 200;
        return;
      }
    }

    // Dig sideways (create horizontal tunnels)
    final nx = x + dir;
    if (_inBounds(nx, y) && _grid[y * w + nx] == El.dirt) {
      if (_rng.nextInt(4) == 0) {
        _grid[y * w + nx] = El.empty;
        _life[y * w + nx] = 0;
        _swap(idx, y * w + nx);
        _velY[idx] = _antCarrierState;
        _pheroFood[y * w + nx] = 200;
        return;
      }
    }

    // Dig diagonally down (creates branching tunnels)
    if (_inBounds(nx, by) && _grid[by * w + nx] == El.dirt && _rng.nextInt(5) == 0) {
      _grid[by * w + nx] = El.empty;
      _life[by * w + nx] = 0;
      _swap(idx, by * w + nx);
      _velY[idx] = _antCarrierState;
      _pheroFood[by * w + nx] = 200;
      return;
    }

    // Create chambers — occasionally dig a wider space
    if (underground && _rng.nextInt(12) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final cx = x + dx, cy = y + dy;
          if (_inBounds(cx, cy) && _grid[cy * w + cx] == El.dirt) {
            _grid[cy * w + cx] = El.empty;
            _life[cy * w + cx] = 0;
            _markDirty(cx, cy);
          }
        }
      }
    }

    // No dirt to dig — either explore for more or switch to carrier
    if (!_checkAdjacent(x, y, El.dirt)) {
      _velY[idx] = _antExplorerState;
    }

    _antMove(x, y, idx, dir);
  }

  void _antCarry(int x, int y, int idx, int homeX) {
    final g = _gravityDir;
    final uy = y - g;
    final w = _gridW;

    // Deposit food pheromone as carrier moves (breadcrumb trail)
    if (_pheroFood[idx] < 80) _pheroFood[idx] = 80;

    // Head toward surface (move upward)
    if (_inBounds(x, uy)) {
      final aboveCell = _grid[uy * w + x];
      if (aboveCell == El.empty) {
        _swap(idx, uy * w + x);
        return;
      }
    }

    // At surface or can't go higher — deposit dirt
    final atSurface = !_inBounds(x, uy) ||
        (_grid[uy * w + x] == El.empty && !_isUnderground(x, y));

    if (atSurface || !_inBounds(x, uy)) {
      final depositY = uy;
      final toHome = (homeX - x).sign;
      for (final depositX in [x + toHome, x, x - toHome]) {
        if (_inBounds(depositX, depositY) && _grid[depositY * w + depositX] == El.empty) {
          _grid[depositY * w + depositX] = El.dirt;
          _life[depositY * w + depositX] = 0;
          _markDirty(depositX, depositY);
          _velY[idx] = _antReturningState;
          return;
        }
      }
      for (final dx in [1, -1]) {
        final sx = x + dx;
        if (_inBounds(sx, y) && _grid[y * w + sx] == El.empty) {
          _grid[y * w + sx] = El.dirt;
          _life[y * w + sx] = 0;
          _markDirty(sx, y);
          _velY[idx] = _antReturningState;
          return;
        }
      }
      _velY[idx] = _antExplorerState;
      return;
    }

    // Move toward home X while heading up — follow home pheromone
    final pheroDir = _antPheromoneDir(x, y, _velX[idx], _pheroHome);
    final toHome = (homeX - x).sign;
    final moveDir = toHome != 0 ? toHome : pheroDir;
    _antMove(x, y, idx, moveDir);
  }

  void _antReturn(int x, int y, int idx, int homeX) {
    final g = _gravityDir;
    final by = y + g;
    final w = _gridW;

    // Follow home pheromone to find way back
    final toHome = (homeX - x).sign;

    // If near home X, head back underground
    if ((x - homeX).abs() <= 2) {
      if (_inBounds(x, by) && _grid[by * w + x] == El.empty) {
        _swap(idx, by * w + x);
        _velY[idx] = _antExplorerState;
        return;
      }
      for (final dx in [0, 1, -1, 2, -2]) {
        final tx = x + dx;
        if (_inBounds(tx, by) && _grid[by * w + tx] == El.empty) {
          if (_inBounds(tx, y) && _grid[y * w + tx] == El.empty) {
            _swap(idx, y * w + tx);
            return;
          }
        }
      }
      _velY[idx] = _antExplorerState;
      return;
    }

    // Use home pheromone for navigation with homeX as fallback
    final pheroDir = _antPheromoneDir(x, y, _velX[idx], _pheroHome);
    final moveDir = toHome != 0 ? toHome : pheroDir;
    _antMove(x, y, idx, moveDir);
  }

  /// Shared ant movement: walk, climb, reverse. Avoids hazards.
  void _antMove(int x, int y, int idx, int moveDir) {
    final g = _gravityDir;
    final uy = y - g;
    final w = _gridW;
    final nx = x + moveDir;

    // Walk along surface
    if (_inBounds(nx, y) && _grid[y * w + nx] == El.empty) {
      _velX[idx] = moveDir;
      _swap(idx, y * w + nx);
      return;
    }

    // Step up 1 cell (climb over obstacle)
    if (_inBounds(nx, uy) && _grid[uy * w + nx] == El.empty) {
      _velX[idx] = moveDir;
      _swap(idx, uy * w + nx);
      return;
    }

    // Wall climb straight up
    if (_inBounds(x, uy) && _grid[uy * w + x] == El.empty) {
      if (!_inBounds(nx, y) || _grid[y * w + nx] != El.empty) {
        _swap(idx, uy * w + x);
        return;
      }
    }

    // Blocked — reverse direction
    _velX[idx] = -moveDir;
    if (_rng.nextInt(6) == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;
  }

  void _simOil(int x, int y, int idx) {
    // Oil burns when near fire
    if (_checkAdjacent(x, y, El.fire)) {
      _grid[idx] = El.fire;
      _life[idx] = 0;
      _markProcessed(idx);
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
    if (_inBounds(x, uy) && _grid[uy * _gridW + x] == El.water && ((_flags[uy * _gridW + x] & 0x80) != (_simClock ? 0x80 : 0))) {
      final ui = uy * _gridW + x;
      final waterMass3 = _life[ui]; // preserve water mass
      _grid[ui] = El.oil;
      _life[ui] = _life[idx];
      _grid[idx] = El.water;
      _life[idx] = waterMass3 < 20 ? 100 : waterMass3;
      _markProcessed(ui);
      _markProcessed(idx);
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
          _markProcessed(ni);
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Dissolve glass
        if (neighbor == El.glass && _rng.nextInt(10) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _markProcessed(ni);
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Kill ants
        if (neighbor == El.ant) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        // Mix with water — dilutes
        if (neighbor == El.water && _rng.nextInt(8) == 0) {
          _grid[idx] = El.water;
          _life[idx] = 100; // water mass
          _markProcessed(idx);
          return;
        }
        // Dissolve plant/seed
        if ((neighbor == El.plant || neighbor == El.seed) && _rng.nextInt(3) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _markProcessed(ni);
        }
        // Dissolve wood slowly
        if (neighbor == El.wood && _rng.nextInt(12) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _markProcessed(ni);
          _grid[idx] = El.empty;
          _life[idx] = 0;
          return;
        }
        // Acid in water generates bubbles
        if (neighbor == El.water && _rng.nextInt(20) == 0) {
          _grid[ni] = El.bubble;
          _life[ni] = 0;
          _markProcessed(ni);
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
      // Sink through water
      if ((elType == El.sand || elType == El.dirt || elType == El.seed) && belowEl == El.water) {
        final sinkWaterMass = _life[below]; // preserve water mass
        _grid[idx] = El.water;
        _life[idx] = sinkWaterMass < 20 ? 100 : sinkWaterMass;
        _grid[below] = elType;
        _markProcessed(idx);
        _markProcessed(below);
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

    // Set clock bit to current _simClock and clear settled bits for both cells
    final clockBit = _simClock ? 0x80 : 0;
    _flags[a] = clockBit;
    _flags[b] = clockBit;

    // Mark both source and destination chunks dirty
    final w = _gridW;
    _markDirty(a % w, a ~/ w);
    _markDirty(b % w, b ~/ w);
  }

  // Inlined for hot-path performance — avoid function call overhead.
  @pragma('vm:prefer-inline')
  bool _inBounds(int x, int y) =>
      x >= 0 && x < _gridW && y >= 0 && y < _gridH;

  /// Mark the chunk containing (x,y) as dirty for the next frame.
  /// Also marks adjacent chunks if the cell is on a chunk boundary (within 1 cell of edge).
  @pragma('vm:prefer-inline')
  void _markDirty(int x, int y) {
    final cx = x >> 4; // x ~/ 16
    final cy = y >> 4; // y ~/ 16
    final cols = _chunkCols;
    final nd = _nextDirtyChunks;
    nd[cy * cols + cx] = 1;
    // Check chunk boundary adjacency (within 1 cell of edge)
    final lx = x & 15; // x % 16
    final ly = y & 15; // y % 16
    if (lx == 0 && cx > 0) nd[cy * cols + cx - 1] = 1;
    if (lx == 15 && cx < cols - 1) nd[cy * cols + cx + 1] = 1;
    final rows = _chunkRows;
    if (ly == 0 && cy > 0) nd[(cy - 1) * cols + cx] = 1;
    if (ly == 15 && cy < rows - 1) nd[(cy + 1) * cols + cx] = 1;
    // Corner adjacency
    if (lx == 0 && ly == 0 && cx > 0 && cy > 0) nd[(cy - 1) * cols + cx - 1] = 1;
    if (lx == 15 && ly == 0 && cx < cols - 1 && cy > 0) nd[(cy - 1) * cols + cx + 1] = 1;
    if (lx == 0 && ly == 15 && cx > 0 && cy < rows - 1) nd[(cy + 1) * cols + cx - 1] = 1;
    if (lx == 15 && ly == 15 && cx < cols - 1 && cy < rows - 1) nd[(cy + 1) * cols + cx + 1] = 1;
  }

  /// Mark all chunks dirty (used on reset, clear, undo, etc.)
  void _markAllDirty() {
    _dirtyChunks.fillRange(0, _dirtyChunks.length, 1);
    _nextDirtyChunks.fillRange(0, _nextDirtyChunks.length, 1);
  }

  /// Mark a cell as processed this frame (sets clock bit, clears settled/stable bits)
  /// and marks the chunk dirty. Replaces all direct `_flags[idx] = 1` in element behaviors.
  @pragma('vm:prefer-inline')
  void _markProcessed(int idx) {
    _flags[idx] = _simClock ? 0x80 : 0;
    final w = _gridW;
    _markDirty(idx % w, idx ~/ w);
  }

  /// Clear settled flag on all 8 neighbors of (x,y) — called when a cell changes state
  /// so neighbors re-evaluate.
  @pragma('vm:prefer-inline')
  void _unsettleNeighbors(int x, int y) {
    final w = _gridW;
    final maxX = w - 1;
    final maxY = _gridH - 1;
    if (y > 0) {
      final rowAbove = (y - 1) * w;
      if (x > 0)    _flags[rowAbove + x - 1] &= 0x80; // keep clock, clear rest
                     _flags[rowAbove + x]     &= 0x80;
      if (x < maxX) _flags[rowAbove + x + 1] &= 0x80;
    }
    if (x > 0)    _flags[y * w + x - 1] &= 0x80;
    if (x < maxX) _flags[y * w + x + 1] &= 0x80;
    if (y < maxY) {
      final rowBelow = (y + 1) * w;
      if (x > 0)    _flags[rowBelow + x - 1] &= 0x80;
                     _flags[rowBelow + x]     &= 0x80;
      if (x < maxX) _flags[rowBelow + x + 1] &= 0x80;
    }
  }

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
            _markProcessed(ni);
            return;
          }
        }
      }
    }
  }

  void _processExplosions() {
    if (_pendingExplosions.isEmpty) return;
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
            _markDirty(nx, ny);
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
            _markDirty(fx, fy);
          }
        }
      }
    }
    _pendingExplosions.clear();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Linearly interpolate between two RGB colors. [t] ranges 0..255.
  static int _lerpC(int a, int b, int t) => (a + ((b - a) * t) ~/ 255).clamp(0, 255);

  /// Spawn a micro-particle (rendered in pixel buffer only, not in _grid).
  void _spawnParticle(int x, int y, int r, int g, int b, int frames) {
    if (_microParticles.length >= _maxMicroParticles) return;
    _microParticles.add(Int32List.fromList([x, y, r, g, b, frames]));
  }

  /// Advance micro-particles: move upward, fade, remove expired.
  void _tickMicroParticles() {
    for (int i = _microParticles.length - 1; i >= 0; i--) {
      final p = _microParticles[i];
      p[5]--; // frames left
      if (p[5] <= 0) {
        _microParticles.removeAt(i);
        continue;
      }
      // Move upward (most particles rise)
      p[1] -= 1;
      // Slight horizontal drift
      if (_rng.nextInt(3) == 0) p[0] += _rng.nextInt(3) - 1;
      // Fade brightness
      p[2] = (p[2] * 220) ~/ 256;
      p[3] = (p[3] * 220) ~/ 256;
      p[4] = (p[4] * 220) ~/ 256;
    }
  }

  // ── Pixel rendering ─────────────────────────────────────────────────────

  void _renderPixels() {
    final total = _gridW * _gridH;
    final w = _gridW;
    final h = _gridH;
    final g = _grid;
    final t = _dayNightT;
    final fc = _frameCount;

    // Pre-computed background colors (base: near-black, not pure black)
    final baseBgR = (12 - t * 6).round().clamp(0, 255);
    final baseBgG = (12 - t * 6).round().clamp(0, 255);
    final baseBgB = (28 - t * 10).round().clamp(0, 255);

    // Night glow multiplier for fire/lava halos
    final glowMul = 1.0 + t * 1.5;
    // Glow intensities for ring-1 (adjacent) and ring-2 (diagonal/2-cell)
    final glow1R = (14 * glowMul).round();
    final glow1G = (5 * glowMul).round();
    final glow2R = (7 * glowMul).round();
    final glow2G = (2 * glowMul).round();
    // Lightning glow — bright white-blue, 3-cell radius
    final lGlow1 = (25 * glowMul).round();
    final lGlow2 = (14 * glowMul).round();
    final lGlow3 = (6 * glowMul).round();

    // Star set for quick lookup (only at night)
    final starSet = t > 0.05 ? Set<int>.from(_starPositions) : <int>{};

    // Pre-compute glow only every 3rd frame (fire moves slowly)
    final doGlow = fc % 3 == 0;

    // Pre-compute integer night factors (avoid per-pixel float math)
    final nightBoost = (t * 30).round();
    final nightBoostG = (nightBoost * 0.2).round();
    final nightShimmer = (t * 50).round();
    final nightSmokeBoost = (t * 20).round();
    // Fixed-point 8-bit: 256 = 1.0, so (1-dim)*256
    final nightDimWater = (256 * (1.0 - t * 0.15)).round();
    final nightDimGeneral = (256 * (1.0 - t * 0.2)).round();

    // ── Build glow map for emissive cells (fire, lava, lightning) ──
    // Only rebuild every 3rd frame. Uses a flat int buffer for R/G/B additive glow.
    Uint8List? glowR8, glowG8, glowB8;
    if (doGlow) {
      glowR8 = Uint8List(total);
      glowG8 = Uint8List(total);
      glowB8 = Uint8List(total);
      for (int i = 0; i < total; i++) {
        final el = g[i];
        if (el != El.fire && el != El.lava && el != El.lightning) continue;
        final ex = i % w;
        final ey = i ~/ w;
        if (el == El.lightning) {
          // Lightning: white-blue glow, 3-cell radius
          for (int dy = -3; dy <= 3; dy++) {
            final ny = ey + dy;
            if (ny < 0 || ny >= h) continue;
            for (int dx = -3; dx <= 3; dx++) {
              final nx = ex + dx;
              if (nx < 0 || nx >= w) continue;
              final dist = dx.abs() + dy.abs(); // Manhattan distance
              if (dist == 0) continue;
              final ni = ny * w + nx;
              if (g[ni] != El.empty) continue;
              int intensity;
              if (dist <= 1) intensity = lGlow1;
              else if (dist <= 2) intensity = lGlow2;
              else intensity = lGlow3;
              glowR8![ni] = (glowR8[ni] + intensity).clamp(0, 255);
              glowG8![ni] = (glowG8[ni] + intensity).clamp(0, 255);
              glowB8![ni] = (glowB8[ni] + (intensity * 2 ~/ 3)).clamp(0, 255);
            }
          }
        } else {
          // Fire/Lava: warm orange glow, 2-cell radius
          final isFire = el == El.fire;
          for (int dy = -2; dy <= 2; dy++) {
            final ny = ey + dy;
            if (ny < 0 || ny >= h) continue;
            for (int dx = -2; dx <= 2; dx++) {
              final nx = ex + dx;
              if (nx < 0 || nx >= w) continue;
              final dist = dx.abs() + dy.abs();
              if (dist == 0) continue;
              final ni = ny * w + nx;
              if (g[ni] != El.empty) continue;
              if (dist <= 1) {
                glowR8![ni] = (glowR8[ni] + glow1R).clamp(0, 255);
                if (isFire) glowG8![ni] = (glowG8[ni] + glow1G).clamp(0, 255);
              } else {
                glowR8![ni] = (glowR8[ni] + glow2R).clamp(0, 255);
                if (isFire) glowG8![ni] = (glowG8[ni] + glow2G).clamp(0, 255);
              }
            }
          }
        }
      }
      // Cache for non-glow frames
      _cachedGlowR = glowR8;
      _cachedGlowG = glowG8;
      _cachedGlowB = glowB8;
    } else {
      glowR8 = _cachedGlowR;
      glowG8 = _cachedGlowG;
      glowB8 = _cachedGlowB;
    }

    for (int i = 0; i < total; i++) {
      final el = g[i];
      final pi4 = i * 4;
      if (el == El.empty) {
        // Background gradient: slightly lighter at top (sky), darker at bottom
        final y = i ~/ w;
        final gradientShift = (4 - (y * 6) ~/ h).clamp(0, 6); // +4 at top, ~0 at bottom
        int emptyR = (baseBgR + gradientShift).clamp(0, 30);
        int emptyG = (baseBgG + gradientShift).clamp(0, 30);
        int emptyB = (baseBgB + gradientShift + 2).clamp(0, 40); // slightly more blue at top

        // Apply glow from nearby emissive cells
        if (glowR8 != null) {
          final gr = glowR8[i];
          final gg = glowG8![i];
          final gb = glowB8![i];
          if (gr > 0 || gg > 0 || gb > 0) {
            emptyR = (emptyR + gr).clamp(0, 255);
            emptyG = (emptyG + gg).clamp(0, 255);
            emptyB = (emptyB + gb).clamp(0, 255);
          }
        }

        // Apply pheromone trail tints
        final foodP = _pheroFood[i];
        final homeP = _pheroHome[i];
        if (foodP > 8 || homeP > 8) {
          final foodR = foodP > 8 ? (foodP >> 4) : 0;
          final foodG2 = foodP > 8 ? (foodP >> 3) : 0;
          final homeB = homeP > 8 ? (homeP >> 4) : 0;
          emptyR = (emptyR + foodR).clamp(0, 255);
          emptyG = (emptyG + foodG2).clamp(0, 255);
          emptyB = (emptyB + homeB).clamp(0, 255);
        }

        if (starSet.contains(i)) {
          // Twinkling stars at night
          final twinkle = ((fc + i * 17) % 40);
          if (twinkle < 6) {
            final brightness = twinkle < 3 ? 200 : 140;
            final starBright = (brightness * t).round();
            emptyR = (emptyR + starBright).clamp(0, 255);
            emptyG = (emptyG + starBright).clamp(0, 255);
            emptyB = (emptyB + starBright).clamp(0, 255);
          }
        }

        _pixels[pi4] = emptyR;
        _pixels[pi4 + 1] = emptyG;
        _pixels[pi4 + 2] = emptyB;
        _pixels[pi4 + 3] = 255;
        continue;
      }

      // ── Spawn micro-particles from active elements ──
      if (fc % 2 == 0) {
        final x = i % w;
        final y = i ~/ w;
        if (el == El.fire || el == El.lava) {
          // Spark scatter: occasional bright pixel upward
          if (_rng.nextInt(200) < 2 && y > 1) {
            // Lava: orange-yellow sparks; Fire: bright yellow-white sparks
            final sparkG = el == El.lava ? 160 : 240;
            final sparkB = el == El.lava ? 30 : 100;
            _spawnParticle(x + _rng.nextInt(3) - 1, y - 1, 255, sparkG, sparkB, 4 + _rng.nextInt(3));
          }
        } else if (el == El.sand) {
          // Dust motes: when sand is falling (cell below is empty or we just arrived)
          if (_rng.nextInt(400) < 1 && y > 1 && y < h - 1 && g[(y + 1) * w + x] == El.empty) {
            _spawnParticle(x, y - 1, 194, 178, 128, 3);
          }
        }
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
          if (isTop && ((fc + wx * 3) % 12 < 3)) {
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

    // ── Render micro-particles on top (additive blend into pixel buffer) ──
    for (final p in _microParticles) {
      final px = p[0];
      final py = p[1];
      if (px < 0 || px >= w || py < 0 || py >= h) continue;
      final pi4 = (py * w + px) * 4;
      // Additive blend: brighten existing pixel
      _pixels[pi4] = (_pixels[pi4] + p[2]).clamp(0, 255);
      _pixels[pi4 + 1] = (_pixels[pi4 + 1] + p[3]).clamp(0, 255);
      _pixels[pi4 + 2] = (_pixels[pi4 + 2] + p[4]).clamp(0, 255);
    }
  }

  Color _getElementColor(int el, int idx) {
    // Slight random hue variation per particle using idx as seed
    final variation = ((idx * 7 + idx ~/ _gridW * 3) % 11) - 5; // -5 to +5

    switch (el) {
      case El.fire:
        // Life increases 0->40-80 then dies. Low=fresh(hot), high=dying(cool tips)
        final fireLife = _life[idx];
        final flicker = (_frameCount + idx * 3) % 6;
        if (fireLife < 8) {
          // Just spawned — bright yellow-white core (bottom of flame)
          final wb = flicker < 3 ? 30 : 0;
          return Color.fromARGB(255, 255, (240 + wb + variation).clamp(210, 255), (140 + wb).clamp(100, 180));
        }
        if (fireLife < 20) {
          // Middle flame: bright orange
          return Color.fromARGB(255, (255 + variation).clamp(230, 255), (130 + variation + (flicker < 3 ? 20 : 0)).clamp(80, 170), 0);
        }
        if (fireLife < 35) {
          // Upper flame: orange-red
          return Color.fromARGB(255, (240 + variation).clamp(200, 255), (60 + variation).clamp(20, 90), 0);
        }
        // Dying tips: dark red, fading out
        final remaining = (80 - fireLife).clamp(1, 45);
        final tipAlpha = (remaining * 5 + 55).clamp(55, 255);
        return Color.fromARGB(tipAlpha, (180 + variation).clamp(140, 210), (20 + variation).clamp(0, 40), 0);

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
        final steamLife = _life[idx];
        final alpha = (180 - steamLife * 2).clamp(60, 180);
        // Wispy bright spots that shimmer as steam rises
        final wisp = (_frameCount + idx * 5) % 8 < 2 ? 20 : 0;
        return Color.fromARGB(alpha, (220 + variation + wisp).clamp(200, 255), (220 + variation + wisp).clamp(200, 255), (240 + wisp).clamp(230, 255));

      case El.water:
        // Electrified water
        if (_life[idx] >= 200) {
          _life[idx]--;
          if (_life[idx] < 200) _life[idx] = 0;
          return const Color(0xFFFFFF66);
        }
        // Melting transition from ice (smooth thermal transition)
        if (_life[idx] >= 140 && _life[idx] < 200) {
          _life[idx]--;
          final tFrac = ((_life[idx] - 140) * 255 ~/ 60).clamp(0, 255);
          return Color.fromARGB(
            255,
            _lerpC(30, 170, tFrac),
            _lerpC(100, 220, tFrac),
            255,
          );
        }
        // Depth-based blue gradient with shimmer
        final wx = idx % _gridW;
        final wy = idx ~/ _gridW;
        final isTop = wy > 0 && _grid[(wy - 1) * _gridW + wx] != El.water &&
            _grid[(wy - 1) * _gridW + wx] != El.oil;
        if (isTop) {
          // Surface: lighter, cyan-tinted, with subtle shimmer
          final shimmer = ((_frameCount + wx * 3) % 10 < 2) ? 20 : 0;
          return Color.fromARGB(255, (80 + shimmer).clamp(50, 120), (190 + shimmer).clamp(170, 220), 255);
        }
        // Measure depth: count water cells above
        int depth = 0;
        for (int cy = wy - 1; cy >= 0 && depth < 8; cy--) {
          if (_grid[cy * _gridW + wx] == El.water) depth++;
          else break;
        }
        // Surface->deep: lighter cyan -> standard blue -> dark saturated
        if (depth < 2) {
          return Color.fromARGB(255, (50 + variation).clamp(30, 70), (140 + variation).clamp(120, 160), 255);
        } else if (depth < 5) {
          return Color.fromARGB(255, (30 + variation).clamp(10, 50), (100 + variation).clamp(80, 120), 240);
        } else {
          return Color.fromARGB(255, (15 + variation).clamp(5, 30), (70 + variation).clamp(50, 90), 210);
        }

      case El.sand:
        // 4 warm tones for rich pixel-art sand texture
        final sx = idx % _gridW;
        final sy = idx ~/ _gridW;
        switch ((sx + sy) % 4) {
          case 0: return const Color.fromARGB(255, 194, 178, 128); // base
          case 1: return const Color.fromARGB(255, 210, 190, 138); // lighter
          case 2: return const Color.fromARGB(255, 182, 162, 112); // darker
          default: return const Color.fromARGB(255, 200, 172, 120); // yellower
        }

      case El.tnt:
        final tx = idx % _gridW;
        final ty = idx ~/ _gridW;
        if ((tx + ty) % 4 == 0) return const Color(0xFF440000);
        return Color.fromARGB(255, (204 + variation).clamp(180, 230), (34 + variation).clamp(10, 60), (34 + variation).clamp(10, 60));

      case El.ant:
        final antState = _velY[idx];
        if (antState == _antCarrierState) {
          // Carrier — brownish tint (carrying dirt) with bright food pixel
          final ay = idx ~/ _gridW;
          final aboveIdx = idx - _gridW;
          // Render bright dirt-colored pixel "on top" if this is top pixel of ant
          if (ay > 0 && _grid[aboveIdx] != El.ant) {
            return const Color(0xFF8B6914); // food color on head
          }
          return const Color(0xFF3D2B1F);
        }
        if (antState == _antDiggerState) {
          // Digger — slightly reddish (active worker)
          return const Color(0xFF2A1111);
        }
        if (antState == _antForagerState) {
          // Forager — slightly greenish tint (on a mission)
          return const Color(0xFF1A2A11);
        }
        if (antState == _antReturningState) {
          // Returning — slight blue tint
          return const Color(0xFF111122);
        }
        // Explorer — normal dark ant
        return (idx % 3 == 0)
            ? const Color(0xFF333333)
            : const Color(0xFF111111);

      case El.seed:
        final v = ((idx % 5) * 4 + variation).clamp(0, 25);
        return Color.fromARGB(255, (139 - v).clamp(100, 150), (115 - v).clamp(80, 130), (85 - v).clamp(50, 100));

      case El.dirt:
        // 3 brown tones + moisture gradient: 0=dry, 5=dark/muddy
        final moisture = _life[idx].clamp(0, 5);
        final mFrac = moisture / 5.0;
        final dx = idx % _gridW;
        final dy = idx ~/ _gridW;
        final dirtVar = (dx * 3 + dy * 5) % 3;
        // Base tones: rich brown, dark brown, reddish brown
        int baseR, baseG, baseB;
        switch (dirtVar) {
          case 0: baseR = 139; baseG = 105; baseB = 20; // rich brown
          case 1: baseR = 120; baseG = 85;  baseB = 18; // dark brown
          default: baseR = 145; baseG = 95;  baseB = 25; // reddish brown
        }
        // Apply moisture darkening
        final dr = (baseR - mFrac * 59).round().clamp(60, 150);
        final dg = (baseG - mFrac * 50).round().clamp(40, 120);
        final db = (baseB - mFrac * 5).round().clamp(10, 50);
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
        // Crystalline texture: pale blue base with white highlight facets
        final ix = idx % _gridW;
        final iy = idx ~/ _gridW;
        if ((ix + iy) % 3 == 0) {
          // White crystal highlights
          return const Color.fromARGB(255, 230, 240, 255);
        }
        // Slightly different blue shades for crystal facets
        final facet = (ix * 5 + iy * 9) % 3;
        switch (facet) {
          case 0: return Color.fromARGB(255, (175 + variation).clamp(155, 200), (225 + variation).clamp(205, 245), 255);
          case 1: return Color.fromARGB(255, (160 + variation).clamp(140, 185), (210 + variation).clamp(190, 230), 248);
          default: return Color.fromARGB(255, (185 + variation).clamp(165, 210), (230 + variation).clamp(210, 250), 255);
        }

      case El.stone:
        // 4 gray tones for natural rock texture
        final stx = idx % _gridW;
        final sty = idx ~/ _gridW;
        switch ((stx * 7 + sty * 13) % 4) {
          case 0: return const Color.fromARGB(255, 140, 140, 140); // light gray
          case 1: return const Color.fromARGB(255, 118, 118, 118); // medium gray
          case 2: return const Color.fromARGB(255, 100, 100, 105); // dark gray
          default: return const Color.fromARGB(255, 125, 128, 135); // blue-gray
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
        // Life increases over time: 0=fresh(hot) -> 200+=cooling into stone
        final lavaLife = _life[idx];
        final flicker = (_frameCount + idx) % 6;
        final flickerBright = flicker < 3 ? 20 : 0;
        // Bright spot: 1-pixel molten sparkle
        final isBrightSpot = (idx * 17 + _frameCount) % 40 == 0;
        if (isBrightSpot && lavaLife < 150) {
          return const Color.fromARGB(255, 255, 255, 180); // hot white-yellow
        }
        if (lavaLife < 40) {
          // Fresh/hot core: yellow-white
          return Color.fromARGB(255, 255, (220 + flickerBright).clamp(200, 255), (100 + flickerBright).clamp(80, 140));
        } else if (lavaLife < 120) {
          // Medium: bright orange, cooling gradually
          final t2 = ((lavaLife - 40) * 255 ~/ 80).clamp(0, 255);
          return Color.fromARGB(255, 255, _lerpC(180, 69, t2) + flickerBright, flickerBright);
        } else {
          // Old/cooling: darker red-brown approaching stone
          final t2 = ((lavaLife - 120) * 255 ~/ 80).clamp(0, 255);
          return Color.fromARGB(255, _lerpC(255, 140, t2), _lerpC(69, 30, t2) + flickerBright, 0);
        }

      case El.snow:
        // Near-white with subtle blue shadows at random positions
        final snowX = idx % _gridW;
        final snowY = idx ~/ _gridW;
        final isShadow = (snowX * 7 + snowY * 11) % 5 == 0;
        final sparkle = (_frameCount + idx * 5) % 15 < 2 ? 12 : 0;
        if (isShadow) {
          return Color.fromARGB(255, (220 + sparkle).clamp(215, 240), (225 + sparkle).clamp(220, 245), 240);
        }
        return Color.fromARGB(255, (240 + sparkle).clamp(235, 255), (243 + sparkle).clamp(238, 255), 255);

      case El.wood:
        // Burning wood — shifts to red/orange
        if (_life[idx] > 0) {
          final burnPhase = (_life[idx] + _frameCount) % 6;
          final bright = burnPhase < 3 ? 40 : 0;
          return Color.fromARGB(255, (200 + bright).clamp(180, 255), (80 + bright - _life[idx]).clamp(20, 120), 10);
        }
        final woodX = idx % _gridW;
        final woodY = idx ~/ _gridW;
        // Horizontal grain lines based on y%2
        final grainDark = woodY % 2 == 0;
        // "Knot" positions — darker spots
        final isKnot = (woodX * 11 + woodY * 7) % 17 == 0;
        // Waterlogged wood is darker (velY tracks waterlog level 0..3)
        final waterlog = _velY[idx].clamp(0, 3) * 20;
        if (isKnot) {
          return Color.fromARGB(255, (110 - waterlog).clamp(50, 130), (55 - waterlog).clamp(25, 75), (30 - waterlog).clamp(10, 50));
        }
        if (grainDark) {
          return Color.fromARGB(255, (150 - waterlog + variation).clamp(60, 170), (76 - waterlog + variation).clamp(30, 100), (40 - waterlog + variation).clamp(10, 60));
        }
        return Color.fromARGB(255, (168 - waterlog + variation).clamp(70, 185), (88 - waterlog + variation).clamp(35, 115), (48 - waterlog + variation).clamp(15, 72));

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
    _pheroFood.fillRange(0, _pheroFood.length, 0);
    _pheroHome.fillRange(0, _pheroHome.length, 0);
    _colonyX = -1;
    _colonyY = -1;
    _microParticles.clear();
    _markAllDirty();
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
      _markDirty(gx, gy);
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
          _markDirty(nx, ny);
          continue;
        }

        if (_grid[ni] != El.empty && _selectedElement != El.lightning) continue;

        _grid[ni] = _selectedElement;
        _life[ni] = _selectedElement == El.water ? 100 : 0; // water uses mass
        _velY[ni] = 0;
        _markDirty(nx, ny);
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
      _markDirty(gx, gy);
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
          _markDirty(nx, ny);
          continue;
        }
        if (_grid[ni] != El.empty && _selectedElement != El.lightning) continue;
        _grid[ni] = _selectedElement;
        _life[ni] = _selectedElement == El.water ? 100 : 0; // water uses mass
        _velY[ni] = 0;
        _markDirty(nx, ny);
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
    _pheroFood.fillRange(0, _pheroFood.length, 0);
    _pheroHome.fillRange(0, _pheroHome.length, 0);
    _colonyX = -1;
    _colonyY = -1;
    _microParticles.clear();
    _markAllDirty();
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
                Container(
                  width: dotSz, height: dotSz,
                  decoration: BoxDecoration(
                    color: seedColors[_selectedSeedType.clamp(1, 5)],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Icon(Icons.eco_rounded, size: iconSz, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  'Seed',
                  style: AppFonts.fredoka(fontSize: labelSz, fontWeight: FontWeight.w500,
                    color: isSelected ? color : AppColors.secondaryText),
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
                _markAllDirty();
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
                _markAllDirty();
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
                _markAllDirty();
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

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  static const int plant = 6;
  static const int stone = 7;
  static const int tnt = 8;
  static const int rainbow = 9;
  static const int mud = 10;
  static const int steam = 11;
  static const int ant = 12;
  static const int oil = 13;
  static const int acid = 14;
  static const int glass = 15;
  static const int eraser = 99; // UI-only, never stored in grid
  static const int count = 16; // number of real element types
}

/// Per-element base colors (index = element type).
const List<Color> _baseColors = [
  Color(0x00000000), // empty (transparent)
  Color(0xFFDEB887), // sand — tan
  Color(0xFF3399FF), // water — blue
  Color(0xFFFF6600), // fire — orange
  Color(0xFFAADDFF), // ice — light blue
  Color(0xFFFFFF66), // lightning — yellow
  Color(0xFF33CC33), // plant — green
  Color(0xFF888888), // stone — gray
  Color(0xFFCC2222), // TNT — red
  Color(0xFFFF00FF), // rainbow — magenta (cycles)
  Color(0xFF8B6914), // mud — brown
  Color(0xFFDDDDDD), // steam — white
  Color(0xFF222222), // ant — dark
  Color(0xFF4A3728), // oil — dark brown
  Color(0xFF33FF33), // acid — neon green
  Color(0xFFDDEEFF), // glass — transparent white
];

/// Element display names for the palette.
const List<String> _elementNames = [
  '', 'Sand', 'Water', 'Fire', 'Ice', 'Zap',
  'Plant', 'Stone', 'TNT', 'Rainbow', 'Mud', 'Steam', 'Ant',
  'Oil', 'Acid', 'Glass',
];

/// Element descriptions for long-press info.
const Map<int, String> _elementDescriptions = {
  El.sand: 'Falls down and piles up.\nMixes with water to make mud.\nSinks through water.',
  El.water: 'Flows and fills containers.\nFreezes near ice.\nPuts out fire (makes steam).',
  El.fire: 'Rises up and burns out.\nSpreads to plants and oil.\nMelts ice into water.',
  El.ice: 'Solid and cold.\nFreezes nearby water.\nMelts from fire.',
  El.lightning: 'Zaps down fast!\nExplodes TNT.\nElectrifies water.',
  El.plant: 'Grows upward when watered.\nBurns when touched by fire.',
  El.stone: 'Solid and immovable.\nNothing can destroy it.\nAcid dissolves it slowly.',
  El.tnt: 'Falls like sand.\nExplodes when hit by fire or lightning!\nMore TNT = bigger boom!',
  El.rainbow: 'Floats upward with sparkles.\nChanges colors!',
  El.mud: 'Like slow sand.\nMade from sand + water.',
  El.steam: 'Rises up fast.\nCondenses back to water at the top.',
  El.ant: 'Walks along surfaces.\nDrowns in water.\nRuns from fire.\nDissolved by acid.',
  El.oil: 'Floats on water.\nVery flammable!\nBurns longer than plant.',
  El.acid: 'Dissolves stone slowly.\nKills ants.\nMixes with water.\nDangerous!',
  El.glass: 'Made when lightning hits sand.\nSolid like stone but see-through.',
};

class ElementLabGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;

  const ElementLabGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
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
  ui.Image? _frameImage;

  // -- Animation / ticker ---------------------------------------------------
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _frameCount = 0;
  final _rng = Random();

  // -- UI state --------------------------------------------------------------
  int _selectedElement = El.sand;
  int _brushSize = 1; // 1, 3, or 5
  bool _isDrawing = false;
  bool _isPaused = false;
  bool _showElementInfo = false;
  int _infoElement = El.sand;

  // -- Canvas layout ---------------------------------------------------------
  double _canvasTop = 0;
  double _canvasLeft = 0;
  double _cellSize = 1.0;
  double _canvasPixelW = 0;
  double _canvasPixelH = 0;

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

  @override
  void initState() {
    super.initState();
    _remainingSeconds = kSessionDuration.inSeconds;
    _ticker = createTicker(_onTick);
    _startSessionTimer();
  }

  bool _gridInitialized = false;

  void _initGrid(double canvasW, double canvasH) {
    _cellSize = (canvasW / 160).clamp(1.0, 4.0);
    _gridW = (canvasW / _cellSize).floor();
    _gridH = (canvasH / _cellSize).floor();
    if (_gridW < 40) _gridW = 40;
    if (_gridH < 60) _gridH = 60;

    _canvasPixelW = _gridW * _cellSize;
    _canvasPixelH = _gridH * _cellSize;
    _canvasLeft = (canvasW - _canvasPixelW) / 2;
    _canvasTop = 0;

    final totalCells = _gridW * _gridH;
    _grid = Uint8List(totalCells);
    _life = Uint8List(totalCells);
    _flags = Uint8List(totalCells);
    _velX = Int8List(totalCells);
    _velY = Int8List(totalCells);
    _pixels = Uint8List(totalCells * 4); // RGBA

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
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        } else if (_remainingSeconds == 30) {
          _showTimeWarning = true;
          _timeWarningText = '30 Seconds Left!';
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        }

        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _sessionExpired = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _ticker.dispose();
    _frameImage?.dispose();
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

    _simulate();
    _renderPixels();
    _buildImage();
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

    // Bottom-up scan for gravity-affected elements, left-right alternating
    final leftToRight = _frameCount.isEven;
    for (int y = _gridH - 2; y >= 0; y--) {
      final startX = leftToRight ? 0 : _gridW - 1;
      final endX = leftToRight ? _gridW : -1;
      final dx = leftToRight ? 1 : -1;
      for (int x = startX; x != endX; x += dx) {
        final idx = y * _gridW + x;
        if (_flags[idx] == 1) continue; // already moved this frame

        final el = _grid[idx];
        if (el == El.empty) continue;

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
          case El.plant:
            _simPlant(x, y, idx);
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
    // Check for adjacent ice -> freeze
    if (_checkAdjacent(x, y, El.ice)) {
      _grid[idx] = El.ice;
      _flags[idx] = 1;
      return;
    }

    // Water pressure: deeper water pushes sideways harder
    int depth = 0;
    for (int cy = y - 1; cy >= max(0, y - 8); cy--) {
      final cellAbove = _grid[cy * _gridW + x];
      if (cellAbove == El.water || cellAbove == El.oil) {
        depth++;
      } else {
        break;
      }
    }

    // Fall down first
    final below = (y + 1) * _gridW + x;
    if (y + 1 < _gridH && _grid[below] == El.empty) {
      _swap(idx, below);
      return;
    }

    // Try diagonal down
    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, y + 1) && _grid[(y + 1) * _gridW + x1] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y + 1) && _grid[(y + 1) * _gridW + x2] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x2);
      return;
    }

    // Flow sideways — pressure increases flow distance
    final flowDist = 1 + (depth ~/ 2).clamp(0, 4);
    for (int d = 1; d <= flowDist; d++) {
      final sx1 = dl ? x - d : x + d;
      final sx2 = dl ? x + d : x - d;
      if (_inBounds(sx1, y) && _grid[y * _gridW + sx1] == El.empty) {
        _swap(idx, y * _gridW + sx1);
        return;
      }
      if (_inBounds(sx2, y) && _grid[y * _gridW + sx2] == El.empty) {
        _swap(idx, y * _gridW + sx2);
        return;
      }
    }
  }

  void _simFire(int x, int y, int idx) {
    _life[idx]++;
    // Fire dies after 40-80 frames
    if (_life[idx] > 40 + _rng.nextInt(40)) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
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
        if (neighbor == El.plant && _rng.nextInt(2) == 0) {
          // Fire spreads to plant more aggressively
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
        if (neighbor == El.ice) {
          _grid[ni] = El.water;
          _life[ni] = 150; // melting visual
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

    // Rise upward with random drift
    final upIdx = (y - 1) * _gridW + x;
    if (y > 0 && _grid[upIdx] == El.empty) {
      _swap(idx, upIdx);
      return;
    }
    final drift = _rng.nextInt(3) - 1;
    final driftX = x + drift;
    if (_inBounds(driftX, y - 1) &&
        _grid[(y - 1) * _gridW + driftX] == El.empty) {
      _swap(idx, (y - 1) * _gridW + driftX);
    }
  }

  void _simIce(int x, int y, int idx) {
    if (_checkAdjacent(x, y, El.fire)) {
      _grid[idx] = El.water;
      _life[idx] = 150; // melting visual flag
      _flags[idx] = 1;
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
          _life[ni] = 200; // electrified
          _flags[ni] = 1;
        }
        if (neighbor == El.sand) {
          _grid[ni] = El.glass;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
      }
    }

    // Move downward rapidly
    final dist = 2 + _rng.nextInt(3);
    final ndx = _rng.nextInt(3) - 1;
    final targetY = y + dist;
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

  void _simPlant(int x, int y, int idx) {
    if (_rng.nextInt(20) != 0) return;

    if (_checkAdjacent(x, y, El.water)) {
      if (y > 0) {
        final above = (y - 1) * _gridW + x;
        if (_grid[above] == El.empty) {
          _grid[above] = El.plant;
          _flags[above] = 1;
          _removeOneAdjacent(x, y, El.water);
        }
      }
      if (_rng.nextInt(3) == 0) {
        final side = _rng.nextBool() ? x - 1 : x + 1;
        if (_inBounds(side, y - 1)) {
          final sideIdx = (y - 1) * _gridW + side;
          if (_grid[sideIdx] == El.empty) {
            _grid[sideIdx] = El.plant;
            _flags[sideIdx] = 1;
          }
        }
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
    if (_rng.nextInt(3) == 0 && y > 0) {
      final above = (y - 1) * _gridW + x;
      if (_grid[above] == El.empty) {
        _swap(idx, above);
        return;
      }
      final side = _rng.nextBool() ? x - 1 : x + 1;
      if (_inBounds(side, y - 1) &&
          _grid[(y - 1) * _gridW + side] == El.empty) {
        _swap(idx, (y - 1) * _gridW + side);
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
    if (y <= 2 || _life[idx] > 80 + _rng.nextInt(40)) {
      _grid[idx] = _rng.nextInt(3) == 0 ? El.water : El.empty;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    if (y > 0) {
      final drift = _rng.nextInt(3) - 1;
      final nx = x + drift;
      final ny = y - 1;
      if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.empty) {
        _swap(idx, ny * _gridW + nx);
        return;
      }
      final above = (y - 1) * _gridW + x;
      if (_grid[above] == El.empty) {
        _swap(idx, above);
        return;
      }
    }
    final side = _rng.nextBool() ? x - 1 : x + 1;
    if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
      _swap(idx, y * _gridW + side);
    }
  }

  void _simAnt(int x, int y, int idx) {
    if (_frameCount % 2 != 0) return;

    // Acid kills ants
    if (_checkAdjacent(x, y, El.acid)) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }

    // Check for dangers
    if (_checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }
    if (_checkAdjacent(x, y, El.fire)) {
      _life[idx] = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (!_inBounds(nx, ny)) continue;
          if (!_checkAdjacent(nx, ny, El.fire) &&
              _grid[ny * _gridW + nx] == El.empty) {
            _swap(idx, ny * _gridW + nx);
            return;
          }
        }
      }
      return;
    }

    if (_velX[idx] == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;

    // Apply gravity if no ground
    if (y + 1 < _gridH && _grid[(y + 1) * _gridW + x] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x);
      return;
    }

    // Trail-following: check if other ants are nearby and tend toward them
    bool foundFriend = false;
    for (int scanD = 1; scanD <= 5; scanD++) {
      final scanX = x + _velX[idx] * scanD;
      if (_inBounds(scanX, y) && _grid[y * _gridW + scanX] == El.ant) {
        foundFriend = true;
        break;
      }
    }

    // Walk along surfaces
    final nx = x + _velX[idx];
    if (_inBounds(nx, y) && _grid[y * _gridW + nx] == El.empty) {
      _swap(idx, y * _gridW + nx);
      return;
    }

    // Try climbing 1 cell
    if (_inBounds(nx, y - 1) && _grid[(y - 1) * _gridW + nx] == El.empty) {
      _swap(idx, (y - 1) * _gridW + nx);
      return;
    }

    // Try climbing straight up (wall climb)
    if (y > 0 && _grid[(y - 1) * _gridW + x] == El.empty) {
      if (!_inBounds(nx, y) || _grid[y * _gridW + nx] != El.empty) {
        _swap(idx, (y - 1) * _gridW + x);
        return;
      }
    }

    // Reverse direction (but if following a friend trail, less random)
    if (!foundFriend) {
      _velX[idx] = -_velX[idx];
      if (_rng.nextInt(5) == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;
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
    final below = (y + 1) * _gridW + x;
    if (y + 1 < _gridH && _grid[below] == El.empty) {
      _swap(idx, below);
      return;
    }

    // Float on water: if sitting on water, swap (oil rises through water)
    if (y + 1 < _gridH && _grid[below] == El.water) {
      _grid[below] = El.oil;
      _life[below] = _life[idx];
      _grid[idx] = El.water;
      _life[idx] = 0;
      _flags[below] = 1;
      _flags[idx] = 1;
      return;
    }

    // Diagonal fall
    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, y + 1) && _grid[(y + 1) * _gridW + x1] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y + 1) && _grid[(y + 1) * _gridW + x2] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x2);
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
        // Dissolve plant
        if (neighbor == El.plant && _rng.nextInt(3) == 0) {
          _grid[ni] = El.empty;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
      }
    }

    // Flow like water
    final below = (y + 1) * _gridW + x;
    if (y + 1 < _gridH && _grid[below] == El.empty) {
      _swap(idx, below);
      return;
    }

    final dl = _rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (_inBounds(x1, y + 1) && _grid[(y + 1) * _gridW + x1] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y + 1) && _grid[(y + 1) * _gridW + x2] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x2);
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
    if (y + 1 < _gridH) {
      final below = (y + 1) * _gridW + x;
      final belowEl = _grid[below];
      if (belowEl == El.empty) {
        _swap(idx, below);
        return;
      }
      // Sink through water
      if (elType == El.sand && belowEl == El.water) {
        _grid[idx] = El.water;
        _grid[below] = El.sand;
        _flags[idx] = 1;
        _flags[below] = 1;
        return;
      }
    }

    final goLeft = _rng.nextBool();
    final x1 = goLeft ? x - 1 : x + 1;
    final x2 = goLeft ? x + 1 : x - 1;
    if (y + 1 < _gridH) {
      if (_inBounds(x1, y + 1) &&
          _grid[(y + 1) * _gridW + x1] == El.empty) {
        _swap(idx, (y + 1) * _gridW + x1);
        return;
      }
      if (_inBounds(x2, y + 1) &&
          _grid[(y + 1) * _gridW + x2] == El.empty) {
        _swap(idx, (y + 1) * _gridW + x2);
        return;
      }
    }
  }

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

  bool _inBounds(int x, int y) =>
      x >= 0 && x < _gridW && y >= 0 && y < _gridH;

  bool _checkAdjacent(int x, int y, int elType) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == elType) {
          return true;
        }
      }
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
          if (_grid[ni] != El.stone && _grid[ni] != El.glass) {
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
    for (int i = 0; i < total; i++) {
      final el = _grid[i];
      final pi4 = i * 4;
      if (el == El.empty) {
        // Check for fire glow from neighbors
        final x = i % _gridW;
        final y = i ~/ _gridW;
        int glowIntensity = 0;
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (_inBounds(nx, ny)) {
              final ni = ny * _gridW + nx;
              if (_grid[ni] == El.fire) {
                final dist = dx.abs() + dy.abs();
                glowIntensity += (3 - dist).clamp(0, 3) * 8;
              }
            }
          }
        }
        if (glowIntensity > 0) {
          glowIntensity = glowIntensity.clamp(0, 60);
          _pixels[pi4] = 10 + glowIntensity;
          _pixels[pi4 + 1] = 10 + (glowIntensity ~/ 3);
          _pixels[pi4 + 2] = 26;
          _pixels[pi4 + 3] = 255;
        } else {
          _pixels[pi4] = 10;
          _pixels[pi4 + 1] = 10;
          _pixels[pi4 + 2] = 26;
          _pixels[pi4 + 3] = 255;
        }
        continue;
      }

      final c = _getElementColor(el, i);

      _pixels[pi4] = (c.r * 255.0).round().clamp(0, 255);
      _pixels[pi4 + 1] = (c.g * 255.0).round().clamp(0, 255);
      _pixels[pi4 + 2] = (c.b * 255.0).round().clamp(0, 255);
      _pixels[pi4 + 3] = (c.a * 255.0).round().clamp(0, 255);
    }
  }

  Color _getElementColor(int el, int idx) {
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
        final hue = (_rainbowHue + _life[idx] * 7) % 360;
        return HSVColor.fromAHSV(1.0, hue.toDouble(), 0.8, 1.0).toColor();

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
        // Water shimmer — top edge is lighter
        final wx = idx % _gridW;
        final wy = idx ~/ _gridW;
        final isTop = wy > 0 && _grid[(wy - 1) * _gridW + wx] != El.water &&
            _grid[(wy - 1) * _gridW + wx] != El.oil;
        if (isTop) {
          return Color.fromARGB(255, (80 + variation).clamp(50, 110), 180, 255);
        }
        return Color.fromARGB(255, (30 + variation).clamp(10, 60), (100 + variation).clamp(80, 130), 255);

      case El.sand:
        final v = ((idx % 7) * 3 + variation).clamp(0, 30);
        return Color.fromARGB(255, 222 - v, 184 - v, 135 - v);

      case El.tnt:
        final tx = idx % _gridW;
        final ty = idx ~/ _gridW;
        if ((tx + ty) % 4 == 0) return const Color(0xFF440000);
        return Color.fromARGB(255, (204 + variation).clamp(180, 230), (34 + variation).clamp(10, 60), (34 + variation).clamp(10, 60));

      case El.ant:
        return (_life[idx] % 3 == 0)
            ? const Color(0xFF333333)
            : const Color(0xFF111111);

      case El.plant:
        final shade = ((idx % 5) * 8 + variation).clamp(0, 50);
        return Color.fromARGB(255, 20 + shade, 160 + shade, 20 + shade);

      case El.ice:
        return Color.fromARGB(255, (170 + variation).clamp(150, 200), (221 + variation).clamp(200, 240), 255);

      case El.stone:
        final v = ((idx % 3) * 10 + variation).clamp(0, 40);
        return Color.fromARGB(255, 120 + v, 120 + v, 120 + v);

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

      default:
        return _baseColors[el.clamp(0, _baseColors.length - 1)];
    }
  }

  Future<void> _buildImage() async {
    _frameImage?.dispose();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixels,
      _gridW,
      _gridH,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    _frameImage = await completer.future;
    if (mounted) setState(() {});
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
    _placeElement(details.localPosition);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_sessionExpired) return;
    if (_isDrawing) {
      _placeElement(details.localPosition);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDrawing = false;
    _isCapturingStroke = false;
  }

  void _handleTapDown(TapDownDetails details) {
    if (_sessionExpired) return;
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

    final radius = burst ? _brushSize + 2 : _brushSize;
    final halfR = radius ~/ 2;

    for (int dy = -halfR; dy <= halfR; dy++) {
      for (int dx = -halfR; dx <= halfR; dx++) {
        final nx = gx + dx;
        final ny = gy + dy;
        if (!_inBounds(nx, ny)) continue;

        if (radius > 1 && dx * dx + dy * dy > halfR * halfR + 1) continue;

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
        _velX[ni] = 0;
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
    final balance = widget.progressService.starCoins;
    if (balance < kExtensionCost) return;
    widget.progressService.spendStarCoins(kExtensionCost);
    setState(() {
      _remainingSeconds += kExtensionDuration.inSeconds;
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
            Column(
              children: [
                _buildTopBar(),
                Expanded(
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
                _buildPalette(),
                _buildBottomBar(),
              ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: 24,
          ),
          const SizedBox(width: 4),
          Text(
            'Element Lab',
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  Icon(Icons.timer_rounded, color: timerColor, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(_remainingSeconds),
                    style: AppFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Star coin balance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                const Icon(Icons.star_rounded,
                    color: AppColors.starGold, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${widget.progressService.starCoins}',
                  style: AppFonts.fredoka(
                    fontSize: 14,
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
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: CustomPaint(
          painter: _GridPainter(
            image: _frameImage,
            canvasLeft: _canvasLeft,
            canvasTop: _canvasTop,
            canvasPixelW: _canvasPixelW,
            canvasPixelH: _canvasPixelH,
            lightningFlash: _lightningFlashFrames > 0,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        ),
      ),
    );
  }

  Widget _buildPalette() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: El.count + 1, // +1 for eraser
        itemBuilder: (context, index) {
          if (index == 0) return _buildEraserChip();
          return _buildElementChip(index); // index 1..15 maps to El types 1..15
        },
      ),
    );
  }

  Widget _buildElementChip(int elType) {
    final isSelected = _selectedElement == elType;
    final color = _baseColors[elType.clamp(0, _baseColors.length - 1)];
    final name = _elementNames[elType.clamp(0, _elementNames.length - 1)];

    return GestureDetector(
      onTap: () {
        setState(() => _selectedElement = elType);
        Haptics.tap();
      },
      onLongPress: () {
        setState(() {
          _showElementInfo = true;
          _infoElement = elType;
        });
        Haptics.tap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              width: 24,
              height: 24,
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
                fontSize: 9,
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
    return GestureDetector(
      onTap: () {
        setState(() => _selectedElement = El.eraser);
        Haptics.tap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.cleaning_services_rounded,
                size: 14,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Erase',
              style: AppFonts.fredoka(
                fontSize: 9,
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

  Widget _buildBottomBar() {
    return Container(
      height: 44,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Brush size controls
          Text(
            'Brush:',
            style: AppFonts.fredoka(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(width: 8),
          for (final size in const [1, 3, 5])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () {
                  setState(() => _brushSize = size);
                  Haptics.tap();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
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
            ),
          const Spacer(),
          // Undo button
          IconButton(
            onPressed: _undoHistory.isNotEmpty ? _undo : null,
            icon: const Icon(Icons.undo_rounded),
            color: _undoHistory.isNotEmpty
                ? AppColors.electricBlue
                : AppColors.secondaryText.withValues(alpha: 0.3),
            iconSize: 20,
            tooltip: 'Undo',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // Pause/Play button
          IconButton(
            onPressed: _togglePause,
            icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            color: AppColors.electricBlue,
            iconSize: 20,
            tooltip: _isPaused ? 'Resume' : 'Pause',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // Clear button
          IconButton(
            onPressed: _clearGrid,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.error.withValues(alpha: 0.8),
            iconSize: 20,
            tooltip: 'Clear all',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  // ── Overlay widgets ────────────────────────────────────────────────────

  Widget _buildTimeWarningOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
                fontSize: 28,
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

    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.9),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
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
                const Icon(
                  Icons.timer_off_rounded,
                  color: AppColors.starGold,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  "Time's Up!",
                  style: AppFonts.fredoka(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your Element Lab session has ended.',
                  textAlign: TextAlign.center,
                  style: AppFonts.fredoka(
                    fontSize: 14,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 20),
                // Add More Time button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAfford ? _addMoreTime : null,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add 2 Minutes  ',
                          style: AppFonts.fredoka(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(Icons.star_rounded,
                            color: AppColors.starGold, size: 16),
                        Text(
                          ' $kExtensionCost',
                          style: AppFonts.fredoka(
                            fontSize: 14,
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                      fontSize: 12,
                      color: AppColors.starGold.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Exit',
                      style: AppFonts.fredoka(
                        fontSize: 15,
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

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showElementInfo = false),
        child: Container(
          color: AppColors.background.withValues(alpha: 0.7),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              padding: const EdgeInsets.all(20),
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    style: AppFonts.fredoka(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: 13,
                      color: AppColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap anywhere to close',
                    style: AppFonts.fredoka(
                      fontSize: 11,
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
    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                color: AppColors.electricBlue,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Paused',
                style: AppFonts.fredoka(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatTime(_remainingSeconds)} remaining',
                style: AppFonts.fredoka(
                  fontSize: 16,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _togglePause,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Resume',
                  style: AppFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Exit Lab',
                  style: AppFonts.fredoka(
                    fontSize: 14,
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

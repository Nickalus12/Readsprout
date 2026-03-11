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

/// Cost in star coins to enter the game.
const int kElementLabCost = 5;

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
  static const int eraser = 99; // UI-only, never stored in grid
  static const int count = 13; // number of real element types
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
];

/// Element display names for the palette.
const List<String> _elementNames = [
  '', 'Sand', 'Water', 'Fire', 'Ice', 'Zap',
  'Plant', 'Stone', 'TNT', 'Rainbow', 'Mud', 'Steam', 'Ant',
];

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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  bool _gridInitialized = false;

  void _initGrid(double canvasW, double canvasH) {
    // Determine cell size so grid fits nicely
    // Target ~160 wide on phones; scale up proportionally
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

  @override
  void dispose() {
    _ticker.dispose();
    _frameImage?.dispose();
    super.dispose();
  }

  // ── Tick callback ────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_gridInitialized) return;

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
          // stone does nothing (immovable)
        }
      }
    }
  }

  // ── Element behaviors ───────────────────────────────────────────────────

  void _simSand(int x, int y, int idx) {
    // Check for water below or adjacent → become mud
    if (_checkAdjacent(x, y, El.water)) {
      _grid[idx] = El.mud;
      // Remove one adjacent water
      _removeOneAdjacent(x, y, El.water);
      _flags[idx] = 1;
      return;
    }

    _fallGranular(x, y, idx, El.sand);
  }

  void _simWater(int x, int y, int idx) {
    // Check for adjacent ice → freeze
    if (_checkAdjacent(x, y, El.ice)) {
      _grid[idx] = El.ice;
      _flags[idx] = 1;
      return;
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

    // Flow sideways (water behavior)
    if (_inBounds(x1, y) && _grid[y * _gridW + x1] == El.empty) {
      _swap(idx, y * _gridW + x1);
      return;
    }
    if (_inBounds(x2, y) && _grid[y * _gridW + x2] == El.empty) {
      _swap(idx, y * _gridW + x2);
      return;
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
          // Fire + Water → Steam
          _grid[ni] = El.steam;
          _life[ni] = 0;
          _grid[idx] = El.empty;
          _life[idx] = 0;
          _flags[ni] = 1;
          return;
        }
        if (neighbor == El.plant && _rng.nextInt(4) == 0) {
          // Fire + Plant → Fire spreads
          _grid[ni] = El.fire;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.ice) {
          // Fire + Ice → Water
          _grid[ni] = El.water;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.tnt) {
          // Fire + TNT → Explosion!
          _pendingExplosions.add(_Explosion(nx, ny, 6 + _rng.nextInt(3)));
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
    // Random horizontal drift
    final drift = _rng.nextInt(3) - 1; // -1, 0, or 1
    final driftX = x + drift;
    if (_inBounds(driftX, y - 1) &&
        _grid[(y - 1) * _gridW + driftX] == El.empty) {
      _swap(idx, (y - 1) * _gridW + driftX);
    }
  }

  void _simIce(int x, int y, int idx) {
    // Ice is mostly static; reactions handled by fire/water neighbors
    // But check: adjacent fire melts it
    if (_checkAdjacent(x, y, El.fire)) {
      _grid[idx] = El.water;
      _life[idx] = 0;
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

    // Check interactions at current cell neighbors
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!_inBounds(nx, ny)) continue;
        final ni = ny * _gridW + nx;
        final neighbor = _grid[ni];
        if (neighbor == El.tnt) {
          _pendingExplosions.add(_Explosion(nx, ny, 7 + _rng.nextInt(3)));
        }
        if (neighbor == El.ice) {
          _grid[ni] = El.water;
          _life[ni] = 0;
          _flags[ni] = 1;
        }
        if (neighbor == El.water) {
          // Electrify water — turn it yellow briefly by setting life
          _life[ni] = 200; // special "electrified" flag
          _flags[ni] = 1;
        }
      }
    }

    // Move downward rapidly — pick a landing spot
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
    // Lightning that can't move just dies next frame
  }

  void _simPlant(int x, int y, int idx) {
    // Grow upward if touching water (slow: 1 in 20 frames)
    if (_rng.nextInt(20) != 0) return;

    if (_checkAdjacent(x, y, El.water)) {
      // Grow upward
      if (y > 0) {
        final above = (y - 1) * _gridW + x;
        if (_grid[above] == El.empty) {
          _grid[above] = El.plant;
          _flags[above] = 1;
          // Consume one water
          _removeOneAdjacent(x, y, El.water);
        }
      }
      // Also try growing to the side occasionally
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
    // TNT just sits there until fire or lightning hits it
    // Falls like sand
    _fallGranular(x, y, idx, El.tnt);
  }

  void _simRainbow(int x, int y, int idx) {
    // Float upward slowly
    if (_rng.nextInt(3) == 0 && y > 0) {
      final above = (y - 1) * _gridW + x;
      if (_grid[above] == El.empty) {
        _swap(idx, above);
        return;
      }
      // Drift sideways
      final side = _rng.nextBool() ? x - 1 : x + 1;
      if (_inBounds(side, y - 1) &&
          _grid[(y - 1) * _gridW + side] == El.empty) {
        _swap(idx, (y - 1) * _gridW + side);
      }
    }
    // Increment life for sparkle timing
    _life[idx] = (_life[idx] + 1) % 255;
  }

  void _simMud(int x, int y, int idx) {
    // Like sand but slower — only moves every other frame
    if (_frameCount.isOdd) return;
    _fallGranular(x, y, idx, El.mud);
  }

  void _simSteam(int x, int y, int idx) {
    _life[idx]++;
    // Steam condenses back to water at the top or after lifetime
    if (y <= 2 || _life[idx] > 80 + _rng.nextInt(40)) {
      _grid[idx] = _rng.nextInt(3) == 0 ? El.water : El.empty;
      _life[idx] = 0;
      _flags[idx] = 1;
      return;
    }

    // Rise fast with drift
    if (y > 0) {
      final drift = _rng.nextInt(3) - 1;
      final nx = x + drift;
      final ny = y - 1;
      if (_inBounds(nx, ny) && _grid[ny * _gridW + nx] == El.empty) {
        _swap(idx, ny * _gridW + nx);
        return;
      }
      // Try straight up
      final above = (y - 1) * _gridW + x;
      if (_grid[above] == El.empty) {
        _swap(idx, above);
        return;
      }
    }
    // Drift sideways if stuck
    final side = _rng.nextBool() ? x - 1 : x + 1;
    if (_inBounds(side, y) && _grid[y * _gridW + side] == El.empty) {
      _swap(idx, y * _gridW + side);
    }
  }

  void _simAnt(int x, int y, int idx) {
    // Only move every 2 frames (slower than particles)
    if (_frameCount % 2 != 0) return;

    // Check for dangers
    if (_checkAdjacent(x, y, El.water)) {
      // Drown!
      _grid[idx] = El.empty;
      _life[idx] = 0;
      return;
    }
    if (_checkAdjacent(x, y, El.fire)) {
      // Run away from fire — move in opposite direction
      _life[idx] = 0;
      // Try to move away
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

    // Walk along surfaces (needs ground below or to the side)
    // Direction stored in velX: -1 or 1
    if (_velX[idx] == 0) _velX[idx] = _rng.nextBool() ? 1 : -1;

    // Apply gravity if no ground
    if (y + 1 < _gridH && _grid[(y + 1) * _gridW + x] == El.empty) {
      _swap(idx, (y + 1) * _gridW + x);
      return;
    }

    // Walk horizontally
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

    // Reverse direction
    _velX[idx] = -_velX[idx];
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _fallGranular(int x, int y, int idx, int elType) {
    // Down
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

    // Diagonal down
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
          // Don't destroy stone
          if (_grid[ni] != El.stone) {
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
      final pi = i * 4;
      if (el == El.empty) {
        // Dark background
        _pixels[pi] = 10;
        _pixels[pi + 1] = 10;
        _pixels[pi + 2] = 26;
        _pixels[pi + 3] = 255;
        continue;
      }

      Color c = _getElementColor(el, i);

      _pixels[pi] = (c.r * 255.0).round().clamp(0, 255);
      _pixels[pi + 1] = (c.g * 255.0).round().clamp(0, 255);
      _pixels[pi + 2] = (c.b * 255.0).round().clamp(0, 255);
      _pixels[pi + 3] = (c.a * 255.0).round().clamp(0, 255);
    }
  }

  Color _getElementColor(int el, int idx) {
    switch (el) {
      case El.fire:
        // Animated fire: orange → red → yellow
        final phase = (_life[idx] + _frameCount) % 20;
        if (phase < 7) return const Color(0xFFFF6600);
        if (phase < 14) return const Color(0xFFFF2200);
        return const Color(0xFFFFAA00);

      case El.lightning:
        return _frameCount.isEven
            ? const Color(0xFFFFFF66)
            : const Color(0xFFFFFFFF);

      case El.rainbow:
        final hue = (_rainbowHue + _life[idx] * 7) % 360;
        return HSVColor.fromAHSV(1.0, hue.toDouble(), 0.8, 1.0).toColor();

      case El.steam:
        final alpha = (180 - _life[idx] * 2).clamp(60, 180);
        return Color.fromARGB(alpha, 220, 220, 240);

      case El.water:
        // Electrified water shows yellow flash
        if (_life[idx] >= 200) {
          _life[idx]--;
          if (_life[idx] < 200) _life[idx] = 0;
          return const Color(0xFFFFFF66);
        }
        // Slight variation for visual interest
        final variation = (_rng.nextInt(3) == 0) ? 15 : 0;
        return Color.fromARGB(255, 30, 100 + variation, 255);

      case El.sand:
        final v = (idx % 7) * 3;
        return Color.fromARGB(255, 222 - v, 184 - v, 135 - v);

      case El.tnt:
        // Red with black lines pattern
        final x = idx % _gridW;
        final y = idx ~/ _gridW;
        if ((x + y) % 4 == 0) return const Color(0xFF440000);
        return const Color(0xFFCC2222);

      case El.ant:
        // Tiny dark bodies with occasional lighter segments
        return (_life[idx] % 3 == 0)
            ? const Color(0xFF333333)
            : const Color(0xFF111111);

      case El.plant:
        final shade = (idx % 5) * 8;
        return Color.fromARGB(255, 20 + shade, 160 + shade, 20 + shade);

      case El.ice:
        return const Color(0xFFAADDFF);

      case El.stone:
        final v = (idx % 3) * 10;
        return Color.fromARGB(255, 120 + v, 120 + v, 120 + v);

      case El.mud:
        final v = (idx % 5) * 5;
        return Color.fromARGB(255, 139 - v, 105 - v, 20);

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

  void _handlePanStart(DragStartDetails details) {
    _isDrawing = true;
    _placeElement(details.localPosition);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isDrawing) {
      _placeElement(details.localPosition);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDrawing = false;
  }

  void _handleTapDown(TapDownDetails details) {
    _placeElement(details.localPosition);
    Haptics.tap();
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _isDrawing = true;
    // Place a bigger burst
    _placeElement(details.localPosition, burst: true);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_isDrawing) {
      _placeElement(details.localPosition, burst: true);
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _isDrawing = false;
  }

  void _placeElement(Offset pos, {bool burst = false}) {
    // Convert screen position to grid coordinates
    final gx = ((pos.dx - _canvasLeft) / _cellSize).floor();
    final gy = ((pos.dy - _canvasTop) / _cellSize).floor();

    final radius = burst ? _brushSize + 2 : _brushSize;
    final halfR = radius ~/ 2;

    for (int dy = -halfR; dy <= halfR; dy++) {
      for (int dx = -halfR; dx <= halfR; dx++) {
        final nx = gx + dx;
        final ny = gy + dy;
        if (!_inBounds(nx, ny)) continue;

        // For circular brush, skip corners of larger sizes
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
    _grid.fillRange(0, _grid.length, El.empty);
    _life.fillRange(0, _life.length, 0);
    _flags.fillRange(0, _flags.length, 0);
    _velX.fillRange(0, _velX.length, 0);
    _velY.fillRange(0, _velY.length, 0);
    Haptics.tap();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_gridInitialized) {
                    // First build — initialize grid to fit available space
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
            _buildBrushSizeBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
          const SizedBox(width: 4),
          IconButton(
            onPressed: _clearGrid,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.error.withValues(alpha: 0.8),
            iconSize: 22,
            tooltip: 'Clear all',
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
          return _buildElementChip(index); // index 1..12 maps to El types 1..12
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

  Widget _buildBrushSizeBar() {
    return Container(
      height: 40,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _brushSize = size);
                  Haptics.tap();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 28,
                  height: 28,
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
        ],
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

    // Draw the pixel grid scaled to fit the canvas area
    final src = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(canvasLeft, canvasTop, canvasPixelW, canvasPixelH);

    // Use nearest-neighbor for crisp pixels
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    canvas.drawImageRect(image!, src, dst, paint);

    // Lightning flash overlay
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
  bool shouldRepaint(_GridPainter oldDelegate) => true; // repaints every frame
}

// ── Explosion data ────────────────────────────────────────────────────────

class _Explosion {
  final int x;
  final int y;
  final int radius;
  const _Explosion(this.x, this.y, this.radius);
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

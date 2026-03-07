import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Falling Letters — Tap anywhere to emit a shockwave that captures nearby letters
// ─────────────────────────────────────────────────────────────────────────────

class FallingLettersGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;
  final bool hintsEnabled;

  const FallingLettersGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
  });

  @override
  State<FallingLettersGame> createState() => _FallingLettersGameState();
}

// ── Data models ──────────────────────────────────────────────────────────────

enum _PowerUpType { shield, slowdown, reveal }

class _FallingItem {
  String letter;
  double x; // 0..1 normalised column position
  double y; // 0..1 normalised vertical (0 = top, 1 = bottom)
  double speed; // normalised units per tick
  double rotation; // radians
  double rotationSpeed;
  bool isNeeded; // is it the NEXT required letter?
  bool captured = false; // tapped correctly — flying to slot
  bool shattered = false; // tapped wrong — breaking apart
  bool missed = false; // fell off bottom while needed
  double captureAnimT = 0; // 0..1 fly-to-slot animation
  Offset? captureTarget; // slot position to fly toward
  double shatterT = 0; // 0..1 shatter anim
  _PowerUpType? powerUp; // non-null means it's a power-up
  double pulsePhase; // for glow pulse
  final int id;
  double vx = 0; // horizontal velocity from shockwave push (normalised/s)
  double extraVy = 0; // extra vertical velocity from shockwave push (normalised/s)

  _FallingItem({
    required this.letter,
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    this.isNeeded = false,
    this.powerUp,
    this.pulsePhase = 0,
    required this.id,
  });
}

class _ShatterFragment {
  double x, y;
  double vx, vy;
  double rotation;
  double rotationSpeed;
  double opacity = 1.0;
  String letter;

  _ShatterFragment({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.rotationSpeed,
    required this.letter,
  });
}

class _DustParticle {
  double x, y;
  double vx, vy;
  double opacity = 1.0;
  double size;

  _DustParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
  });
}

class _SparkleParticle {
  double x, y;
  double vx, vy;
  double opacity = 1.0;
  double size;
  Color color;

  _SparkleParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
  });
}

class _Star {
  double x, y;
  double size;
  double opacity;
  double speed; // parallax layer speed
  double twinklePhase;
  double twinkleSpeed;
  final int layer; // 0 = far, 1 = mid, 2 = near

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.twinklePhase,
    this.twinkleSpeed = 2.0,
    this.layer = 0,
  });
}

class _ShootingStar {
  double x, y;
  double vx, vy;
  double opacity = 1.0;
  double length;
  double life = 0;

  _ShootingStar({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.length,
  });
}

class _Shockwave {
  final double cx, cy; // center in pixels
  double radius; // current radius in pixels
  final double maxRadius;
  double opacity;
  final Set<int> hitIds; // items already affected by this wave

  _Shockwave({
    required this.cx,
    required this.cy,
    required this.maxRadius,
  })  : radius = 0,
        opacity = 1.0,
        hitIds = {};
}

class _DisintegrationParticle {
  double x, y;
  double vx, vy;
  double size;
  double opacity = 1.0;
  Color color;
  double rotation;
  double rotationSpeed;

  _DisintegrationParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    this.rotation = 0,
    this.rotationSpeed = 0,
  });
}

// ── State ────────────────────────────────────────────────────────────────────

class _FallingLettersGameState extends State<FallingLettersGame>
    with TickerProviderStateMixin {
  final _rng = Random();

  // Game config
  static const int _columns = 6;
  static const int _maxLives = 3;
  static const double _baseSpeed = 0.0025;
  static const double _speedIncrease = 0.00008; // per word completed
  static const double _letterSpawnInterval = 0.8; // seconds base
  static const double _neededLetterRatio = 0.42;
  static const double _powerUpChance = 0.06;

  // Shockwave config
  static const double _shockwaveSpeed = 600.0; // px/s
  static const double _shockwaveRadiusFraction = 0.12; // 12% of screen width
  static const double _itemHitRadius = 16.0; // tighter capture radius
  static const double _pushMagnitude = 0.35; // normalised push strength

  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _lives = _maxLives;
  int _wordsCompleted = 0;

  // Word state
  List<String> _wordPool = [];
  int _wordPoolIndex = 0;
  String _currentWord = '';
  int _nextLetterIndex = 0; // index into _currentWord
  List<bool> _slotsFilled = [];

  // Falling items
  final List<_FallingItem> _items = [];
  int _nextItemId = 0;
  double _spawnAccumulator = 0;

  // Shockwaves
  final List<_Shockwave> _shockwaves = [];

  // Effects
  final List<_ShatterFragment> _fragments = [];
  final List<_DustParticle> _dustParticles = [];
  final List<_SparkleParticle> _sparkles = [];
  final List<_DisintegrationParticle> _disintegrationParticles = [];

  // Background
  final List<_Star> _stars = [];
  _ShootingStar? _shootingStar;
  double _shootingStarTimer = 0;

  // Power-up state
  bool _slowActive = false;
  double _slowTimer = 0;
  bool _revealActive = false;
  double _revealTimer = 0;

  // Screen flash
  Color? _flashColor;
  double _flashOpacity = 0;

  // Screen shake
  Offset _screenShakeOffset = Offset.zero;
  double _screenShakeTimer = 0;

  // Word complete celebration
  bool _wordCelebrating = false;
  double _wordCelebrateT = 0;

  // Animation
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Slot positions (calculated in layout)
  List<Rect> _slotRects = [];
  final GlobalKey _slotRowKey = GlobalKey();

  // Warning flash for missed needed letter
  bool _warningFlash = false;
  double _warningFlashT = 0;

  // Screen size cache (set each frame from LayoutBuilder)
  Size _screenSize = Size.zero;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _buildWordPool();
    _initStars();
    _ticker = createTicker(_onTick);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _gameStarted = true);
        _nextWord();
        _ticker.start();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sessionTimer.stop();
    super.dispose();
  }

  // ── Word pool ──────────────────────────────────────────────────────────

  void _buildWordPool() {
    final highest = widget.progressService.highestUnlockedLevel;
    final pool = <String>[];
    for (int lvl = 1; lvl <= highest; lvl++) {
      final words = DolchWords.wordsForLevel(lvl);
      for (final w in words) {
        pool.add(w.text.toLowerCase());
      }
    }
    if (pool.isEmpty) {
      pool.addAll(
          DolchWords.wordsForLevel(1).map((w) => w.text.toLowerCase()));
    }
    pool.shuffle(_rng);
    _wordPool = pool;
    _wordPoolIndex = 0;
  }

  void _nextWord() {
    if (_gameOver) return;
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle(_rng);
      _wordPoolIndex = 0;
    }
    _currentWord = _wordPool[_wordPoolIndex++];
    _nextLetterIndex = 0;
    _slotsFilled = List.filled(_currentWord.length, false);
    _wordCelebrating = false;
    _wordCelebrateT = 0;

    // Ensure a needed letter spawns soon
    _ensureNeededLetterExists();
  }

  // ── Stars ──────────────────────────────────────────────────────────────

  void _initStars() {
    // Layer 0: far stars (tiny, slow, many)
    for (int i = 0; i < 40; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 0.5 + _rng.nextDouble() * 0.7,
        opacity: 0.2 + _rng.nextDouble() * 0.3,
        speed: 0.00005 + _rng.nextDouble() * 0.0001,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 0.5 + _rng.nextDouble() * 1.0,
        layer: 0,
      ));
    }
    // Layer 1: mid stars (medium, moderate speed)
    for (int i = 0; i < 25; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 1.0 + _rng.nextDouble() * 1.0,
        opacity: 0.3 + _rng.nextDouble() * 0.4,
        speed: 0.0002 + _rng.nextDouble() * 0.0003,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 1.0 + _rng.nextDouble() * 2.0,
        layer: 1,
      ));
    }
    // Layer 2: near stars (larger, faster, brighter)
    for (int i = 0; i < 15; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 1.5 + _rng.nextDouble() * 1.5,
        opacity: 0.4 + _rng.nextDouble() * 0.5,
        speed: 0.0005 + _rng.nextDouble() * 0.0005,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 1.5 + _rng.nextDouble() * 2.5,
        layer: 2,
      ));
    }
  }

  // ── Game tick ──────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_gameStarted || _gameOver) return;

    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    // Clamp dt to avoid jumps
    final cdt = dt.clamp(0.0, 0.05);

    setState(() {
      _updateStars(cdt);
      _updateShootingStar(cdt);
      _updateSpawning(cdt);
      _updateFallingItems(cdt);
      _updateShockwaves(cdt);
      _updateFragments(cdt);
      _updateDust(cdt);
      _updateSparkles(cdt);
      _updateDisintegrationParticles(cdt);
      _updateFlash(cdt);
      _updateScreenShake(cdt);
      _updatePowerUpTimers(cdt);
      _updateWordCelebration(cdt);
      _updateWarningFlash(cdt);
    });
  }

  void _updateStars(double dt) {
    for (final s in _stars) {
      s.y += s.speed;
      if (s.y > 1.0) {
        s.y = 0;
        s.x = _rng.nextDouble();
      }
      s.twinklePhase += dt * s.twinkleSpeed;
    }
    // Shooting star timer
    _shootingStarTimer += dt;
    if (_shootingStar == null &&
        _shootingStarTimer > 4 + _rng.nextDouble() * 8) {
      _shootingStarTimer = 0;
      _spawnShootingStar();
    }
  }

  void _spawnShootingStar() {
    _shootingStar = _ShootingStar(
      x: _rng.nextDouble() * 0.6 + 0.2,
      y: _rng.nextDouble() * 0.3,
      vx: (_rng.nextBool() ? 1 : -1) * (0.3 + _rng.nextDouble() * 0.4),
      vy: 0.15 + _rng.nextDouble() * 0.2,
      length: 0.06 + _rng.nextDouble() * 0.04,
    );
  }

  void _updateShootingStar(double dt) {
    if (_shootingStar == null) return;
    final s = _shootingStar!;
    s.x += s.vx * dt;
    s.y += s.vy * dt;
    s.life += dt;
    s.opacity = (1.0 - s.life / 1.5).clamp(0.0, 1.0);
    if (s.opacity <= 0 || s.x < -0.1 || s.x > 1.1 || s.y > 1.1) {
      _shootingStar = null;
    }
  }

  void _updateSpawning(double dt) {
    final interval = _letterSpawnInterval *
        (1.0 - (_wordsCompleted * 0.02).clamp(0.0, 0.4));
    _spawnAccumulator += dt;
    if (_spawnAccumulator >= interval) {
      _spawnAccumulator -= interval;
      _spawnItem();
    }
  }

  void _spawnItem() {
    if (_gameOver || _wordCelebrating) return;

    final neededLetter = _nextLetterIndex < _currentWord.length
        ? _currentWord[_nextLetterIndex]
        : null;

    // Decide if this should be a power-up
    if (_rng.nextDouble() < _powerUpChance) {
      _spawnPowerUp();
      return;
    }

    // Decide if needed or decoy
    bool makeNeeded = false;
    if (neededLetter != null) {
      // Check if a needed letter is already on screen
      final hasNeeded = _items
          .any((i) => i.isNeeded && !i.captured && !i.shattered && !i.missed);
      if (!hasNeeded) {
        makeNeeded = true; // Force spawn needed
      } else {
        makeNeeded = _rng.nextDouble() < _neededLetterRatio;
      }
    }

    String letter;
    if (makeNeeded && neededLetter != null) {
      letter = neededLetter;
    } else {
      // Decoy: random a-z
      letter = String.fromCharCode(97 + _rng.nextInt(26));
    }

    final col = _rng.nextInt(_columns);
    const colWidth = 1.0 / _columns;
    final x = col * colWidth + colWidth * 0.5;
    final speed = _currentSpeed * (0.8 + _rng.nextDouble() * 0.4);

    _items.add(_FallingItem(
      letter: letter,
      x: x,
      y: -0.08,
      speed: _slowActive ? speed * 0.4 : speed,
      rotation: (_rng.nextDouble() - 0.5) * 0.4,
      rotationSpeed: (_rng.nextDouble() - 0.5) * 1.5,
      isNeeded: makeNeeded,
      id: _nextItemId++,
      pulsePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  void _spawnPowerUp() {
    const types = _PowerUpType.values;
    final type = types[_rng.nextInt(types.length)];
    final col = _rng.nextInt(_columns);
    const colWidth = 1.0 / _columns;
    final x = col * colWidth + colWidth * 0.5;

    _items.add(_FallingItem(
      letter: '',
      x: x,
      y: -0.08,
      speed: _currentSpeed * 0.6,
      rotation: 0,
      rotationSpeed: 0.5,
      powerUp: type,
      id: _nextItemId++,
      pulsePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  void _ensureNeededLetterExists() {
    if (_nextLetterIndex >= _currentWord.length) return;
    final hasNeeded = _items
        .any((i) => i.isNeeded && !i.captured && !i.shattered && !i.missed);
    if (!hasNeeded) {
      // Force spawn one
      final neededLetter = _currentWord[_nextLetterIndex];
      final col = _rng.nextInt(_columns);
      const colWidth = 1.0 / _columns;
      final x = col * colWidth + colWidth * 0.5;

      _items.add(_FallingItem(
        letter: neededLetter,
        x: x,
        y: -0.05,
        speed: _currentSpeed * (0.8 + _rng.nextDouble() * 0.4),
        rotation: (_rng.nextDouble() - 0.5) * 0.4,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 1.5,
        isNeeded: true,
        id: _nextItemId++,
        pulsePhase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  double get _currentSpeed => _baseSpeed + _wordsCompleted * _speedIncrease;

  void _updateFallingItems(double dt) {
    final toRemove = <int>[];

    for (final item in _items) {
      if (item.captured) {
        // Fly to slot
        item.captureAnimT += dt * 3.5;
        if (item.captureAnimT >= 1.0) {
          toRemove.add(item.id);
        }
        continue;
      }
      if (item.shattered) {
        item.shatterT += dt * 3.0;
        if (item.shatterT >= 1.0) {
          toRemove.add(item.id);
        }
        continue;
      }
      if (item.missed) {
        toRemove.add(item.id);
        continue;
      }

      // Fall + apply push velocities
      item.y += item.speed * (dt / 0.016) + item.extraVy * dt;
      item.x += item.vx * dt;
      item.rotation += item.rotationSpeed * dt;
      item.pulsePhase += dt * 3.0;

      // Dampen push velocities
      item.vx *= (1.0 - dt * 3.0).clamp(0.0, 1.0);
      item.extraVy *= (1.0 - dt * 3.0).clamp(0.0, 1.0);

      // Clamp x to stay on screen
      item.x = item.x.clamp(0.05, 0.95);

      // Hit bottom?
      if (item.y > 1.05) {
        if (item.powerUp != null) {
          toRemove.add(item.id);
          continue;
        }
        if (item.isNeeded) {
          // Missed a needed letter!
          item.missed = true;
          _onNeededLetterMissed(item);
        } else {
          toRemove.add(item.id);
        }
      }
    }

    _items.removeWhere((i) => toRemove.contains(i.id));

    // Keep ensuring a needed letter exists
    if (!_wordCelebrating && _nextLetterIndex < _currentWord.length) {
      _ensureNeededLetterExists();
    }
  }

  // ── Shockwave logic ─────────────────────────────────────────────────────

  void _updateShockwaves(double dt) {
    if (_screenSize == Size.zero) return;

    final sw = _screenSize.width;
    final sh = _screenSize.height;
    final neededLetter = _nextLetterIndex < _currentWord.length
        ? _currentWord[_nextLetterIndex]
        : null;

    for (final wave in _shockwaves) {
      wave.radius += _shockwaveSpeed * dt;
      wave.opacity = (1.0 - wave.radius / wave.maxRadius).clamp(0.0, 1.0);

      // Check collisions with items
      for (final item in _items) {
        if (item.captured || item.shattered || item.missed) continue;
        if (wave.hitIds.contains(item.id)) continue;

        final itemPx = item.x * sw;
        final itemPy = item.y * sh;
        final dx = itemPx - wave.cx;
        final dy = itemPy - wave.cy;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < wave.radius + _itemHitRadius) {
          wave.hitIds.add(item.id);

          if (item.powerUp != null) {
            _activatePowerUp(item);
          } else if (neededLetter != null && item.letter == neededLetter) {
            _onShockwaveHitCorrect(item, wave);
          } else {
            _onShockwaveHitWrong(item, wave, dist);
          }
        }
      }
    }

    _shockwaves.removeWhere(
        (w) => w.opacity <= 0 || w.radius >= w.maxRadius);
  }

  void _onShockwaveHitCorrect(_FallingItem item, _Shockwave wave) {
    final sw = _screenSize.width;
    final sh = _screenSize.height;
    final itemPx = item.x * sw;
    final itemPy = item.y * sh;

    // Spawn disintegration particles (8-12)
    final particleCount = 8 + _rng.nextInt(5);
    for (int i = 0; i < particleCount; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 80.0 + _rng.nextDouble() * 180.0;
      _disintegrationParticles.add(_DisintegrationParticle(
        x: itemPx + (_rng.nextDouble() - 0.5) * 20,
        y: itemPy + (_rng.nextDouble() - 0.5) * 20,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40, // slight upward bias
        size: 3.0 + _rng.nextDouble() * 5.0,
        color: AppColors.electricBlue
            .withValues(alpha: 0.7 + _rng.nextDouble() * 0.3),
        rotation: _rng.nextDouble() * pi * 2,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 8.0,
      ));
    }

    // Calculate slot target
    Offset target = Offset(sw / 2, 80);
    if (_slotRects.isNotEmpty && _nextLetterIndex < _slotRects.length) {
      final rect = _slotRects[_nextLetterIndex];
      target = rect.center;
    }

    item.captured = true;
    item.isNeeded = false;
    item.captureAnimT = 0;
    item.captureTarget = target;

    // Un-need all other copies of this letter
    for (final other in _items) {
      if (other.id != item.id &&
          other.isNeeded &&
          !other.captured &&
          !other.shattered) {
        other.isNeeded = false;
      }
    }

    // Sparkle trail
    for (int i = 0; i < 8; i++) {
      _sparkles.add(_SparkleParticle(
        x: itemPx + (_rng.nextDouble() - 0.5) * 20,
        y: itemPy + (_rng.nextDouble() - 0.5) * 20,
        vx: (_rng.nextDouble() - 0.5) * 60,
        vy: -40 - _rng.nextDouble() * 80,
        size: 3 + _rng.nextDouble() * 4,
        color: AppColors
            .confettiColors[_rng.nextInt(AppColors.confettiColors.length)],
      ));
    }

    _slotsFilled[_nextLetterIndex] = true;
    _nextLetterIndex++;

    // Blue flash
    _flashColor = AppColors.electricBlue;
    _flashOpacity = 0.15;

    widget.audioService.playLetter(item.letter);

    // Word complete?
    if (_nextLetterIndex >= _currentWord.length) {
      _onWordComplete();
    }
  }

  void _onShockwaveHitWrong(
      _FallingItem item, _Shockwave wave, double dist) {
    final sw = _screenSize.width;
    final sh = _screenSize.height;
    final itemPx = item.x * sw;
    final itemPy = item.y * sh;

    // Push direction: away from shockwave center
    final dx = itemPx - wave.cx;
    final dy = itemPy - wave.cy;
    final d = max(dist, 1.0);
    final nx = dx / d;
    final ny = dy / d;

    // Push magnitude inversely proportional to distance
    final strength =
        _pushMagnitude * (1.0 - (dist / wave.maxRadius).clamp(0.0, 1.0));
    item.vx += nx * strength;
    item.extraVy += ny * strength * 0.5; // less vertical push
    item.rotationSpeed += (_rng.nextDouble() - 0.5) * 4.0; // spin it
  }

  void _updateDisintegrationParticles(double dt) {
    for (final p in _disintegrationParticles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 200 * dt; // gravity
      p.rotation += p.rotationSpeed * dt;
      p.opacity -= dt * 2.0; // fade over ~0.5s
    }
    _disintegrationParticles.removeWhere((p) => p.opacity <= 0);
    if (_disintegrationParticles.length > 30) {
      _disintegrationParticles.removeRange(
          0, _disintegrationParticles.length - 30);
    }
  }

  void _updateScreenShake(double dt) {
    if (_screenShakeTimer > 0) {
      _screenShakeTimer -= dt;
      if (_screenShakeTimer <= 0) {
        _screenShakeTimer = 0;
        _screenShakeOffset = Offset.zero;
      } else {
        _screenShakeOffset = Offset(
          (_rng.nextDouble() - 0.5) * 4.0,
          (_rng.nextDouble() - 0.5) * 4.0,
        );
      }
    }
  }

  // ── Screen tap ──────────────────────────────────────────────────────────

  void _onScreenTap(Offset position) {
    if (_gameOver || !_gameStarted || _wordCelebrating) return;
    // Limit concurrent shockwaves to prevent performance issues
    if (_shockwaves.length >= 3) return;

    final maxRadius = _screenSize.width * _shockwaveRadiusFraction;

    _shockwaves.add(_Shockwave(
      cx: position.dx,
      cy: position.dy,
      maxRadius: maxRadius,
    ));

    // Screen shake
    _screenShakeTimer = 0.1;

    Haptics.correct();
  }

  // ── Existing update methods ─────────────────────────────────────────────

  void _updateFragments(double dt) {
    for (final f in _fragments) {
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.vy += 600 * dt; // gravity
      f.rotation += f.rotationSpeed * dt;
      f.opacity -= dt * 1.8;
    }
    _fragments.removeWhere((f) => f.opacity <= 0);
    // Hard cap to prevent performance issues
    if (_fragments.length > 30) {
      _fragments.removeRange(0, _fragments.length - 30);
    }
  }

  void _updateDust(double dt) {
    for (final d in _dustParticles) {
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vy -= 30 * dt; // float up
      d.opacity -= dt * 2.5;
    }
    _dustParticles.removeWhere((d) => d.opacity <= 0);
    if (_dustParticles.length > 20) {
      _dustParticles.removeRange(0, _dustParticles.length - 20);
    }
  }

  void _updateSparkles(double dt) {
    for (final s in _sparkles) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.opacity -= dt * 2.0;
      s.size *= (1.0 - dt * 1.5).clamp(0.5, 1.0);
    }
    _sparkles.removeWhere((s) => s.opacity <= 0);
    if (_sparkles.length > 20) {
      _sparkles.removeRange(0, _sparkles.length - 20);
    }
  }

  void _updateFlash(double dt) {
    if (_flashOpacity > 0) {
      _flashOpacity -= dt * 4.0;
      if (_flashOpacity <= 0) {
        _flashOpacity = 0;
        _flashColor = null;
      }
    }
  }

  void _updatePowerUpTimers(double dt) {
    if (_slowActive) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) {
        _slowActive = false;
        // Restore speeds
        for (final item in _items) {
          if (!item.captured && !item.shattered) {
            item.speed /= 0.4;
          }
        }
      }
    }
    if (_revealActive) {
      _revealTimer -= dt;
      if (_revealTimer <= 0) {
        _revealActive = false;
      }
    }
  }

  void _updateWordCelebration(double dt) {
    if (_wordCelebrating) {
      _wordCelebrateT += dt;
      if (_wordCelebrateT > 1.2) {
        _nextWord();
      }
    }
  }

  void _updateWarningFlash(double dt) {
    if (_warningFlash) {
      _warningFlashT += dt;
      if (_warningFlashT > 0.5) {
        _warningFlash = false;
        _warningFlashT = 0;
      }
    }
  }

  // ── Event handlers ──────────────────────────────────────────────────────

  void _onNeededLetterMissed(_FallingItem item) {
    _lives--;
    _warningFlash = true;
    _warningFlashT = 0;

    // Dust puff at bottom
    final px = item.x * (_slotRowKey.currentContext?.size?.width ?? 400);
    for (int i = 0; i < 6; i++) {
      _dustParticles.add(_DustParticle(
        x: px + (_rng.nextDouble() - 0.5) * 30,
        y: (_slotRowKey.currentContext?.size?.height ?? 600) - 20,
        vx: (_rng.nextDouble() - 0.5) * 40,
        vy: -20 - _rng.nextDouble() * 30,
        size: 3 + _rng.nextDouble() * 5,
      ));
    }

    _flashColor = AppColors.error;
    _flashOpacity = 0.3;

    widget.audioService.playError();
    Haptics.wrong();

    if (_lives <= 0) {
      _gameOver = true;
      _awardMiniGameStickers();
      widget.audioService.playError();
    }
  }

  void _onWordComplete() {
    _wordCelebrating = true;
    _wordCelebrateT = 0;
    _wordsCompleted++;
    _score += _currentWord.length * 10;

    widget.audioService.playWord(_currentWord);
    widget.audioService.playSuccess();
    Haptics.success();

    // Golden flash
    _flashColor = AppColors.starGold;
    _flashOpacity = 0.25;

    // Clear remaining items
    _items.removeWhere((i) => !i.captured);
  }

  void _activatePowerUp(_FallingItem item) {
    switch (item.powerUp!) {
      case _PowerUpType.shield:
        _lives = (_lives + 1).clamp(0, _maxLives + 1);
        _flashColor = AppColors.emerald;
        _flashOpacity = 0.2;
        break;
      case _PowerUpType.slowdown:
        _slowActive = true;
        _slowTimer = 5.0;
        for (final it in _items) {
          if (!it.captured && !it.shattered) {
            it.speed *= 0.4;
          }
        }
        _flashColor = AppColors.cyan;
        _flashOpacity = 0.2;
        break;
      case _PowerUpType.reveal:
        _revealActive = true;
        _revealTimer = 3.0;
        _flashColor = AppColors.violet;
        _flashOpacity = 0.2;
        break;
    }
    item.captured = true;
    item.captureAnimT = 0;
    widget.audioService.playSuccess();
    Haptics.correct();
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('falling_letters', _wordsCompleted);
    for (final id in earned) {
      if (!ps.hasSticker(id)) {
        final def = StickerDefinitions.byId(id);
        if (def != null) {
          ps.awardSticker(StickerRecord(
            stickerId: id,
            dateEarned: DateTime.now(),
            category: def.category.name,
          ));
        }
      }
    }
  }

  void _restartGame() {
    _items.clear();
    _fragments.clear();
    _dustParticles.clear();
    _sparkles.clear();
    _disintegrationParticles.clear();
    _shockwaves.clear();
    _score = 0;
    _lives = _maxLives;
    _wordsCompleted = 0;
    _gameOver = false;
    _slowActive = false;
    _revealActive = false;
    _spawnAccumulator = 0;
    _nextItemId = 0;
    _lastTick = Duration.zero;
    _screenShakeTimer = 0;
    _screenShakeOffset = Offset.zero;
    _buildWordPool();
    _nextWord();
    if (!_ticker.isActive) _ticker.start();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF050510),
              Color(0xFF0A0A2E),
              Color(0xFF0A0A1A),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: _gameOver ? _buildGameOver() : _buildGame(),
        ),
      ),
    );
  }

  Widget _buildGame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _screenSize = size;
        return Transform.translate(
          offset: _screenShakeOffset,
          child: Stack(
            children: [
              // Stars background
              CustomPaint(
                size: size,
                painter: _StarFieldPainter(
                  stars: _stars,
                  shootingStar: _shootingStar,
                ),
              ),

              // Tap-anywhere detector for shockwave
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) =>
                      _onScreenTap(details.localPosition),
                ),
              ),

              // Falling items (no individual GestureDetectors)
              ..._items.where((i) => !i.missed).map(
                    (item) => _buildFallingItem(item, size)),

              // All particles + shockwaves in one painter (avoids per-particle widgets)
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _EffectsPainter(
                    fragments: _fragments,
                    dustParticles: _dustParticles,
                    sparkles: _sparkles,
                    disintegrationParticles: _disintegrationParticles,
                    shockwaves: _shockwaves,
                  ),
                ),
              ),

              // Screen flash overlay
              if (_flashColor != null && _flashOpacity > 0)
                IgnorePointer(
                  child: Container(
                    color: _flashColor!
                        .withValues(alpha: _flashOpacity.clamp(0.0, 1.0)),
                  ),
                ),

              // Warning flash
              if (_warningFlash)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.error.withValues(
                            alpha:
                                (1.0 - _warningFlashT * 2).clamp(0.0, 0.8)),
                        width: 4,
                      ),
                    ),
                  ),
                ),

              // HUD
              _buildHUD(size),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallingItem(_FallingItem item, Size screenSize) {
    if (item.captured && item.captureTarget != null) {
      // Animate flying to slot
      final startX = item.x * screenSize.width;
      final startY = item.y * screenSize.height;
      final t =
          Curves.easeInBack.transform(item.captureAnimT.clamp(0.0, 1.0));
      final cx = startX + (item.captureTarget!.dx - startX) * t;
      final cy = startY + (item.captureTarget!.dy - startY) * t;
      final scale = 1.0 + sin(t * pi) * 0.3;

      return Positioned(
        left: cx - 22,
        top: cy - 22,
        child: Transform.scale(
          scale: scale,
          child: _letterTile(item, highlight: true),
        ),
      );
    }

    if (item.captured && item.powerUp != null) {
      // Power-up fades out
      return const SizedBox.shrink();
    }

    final px = item.x * screenSize.width;
    final py = item.y * screenSize.height;

    return Positioned(
      left: px - 22,
      top: py - 22,
      child: Transform.rotate(
        angle: item.rotation,
        child: item.powerUp != null
            ? _powerUpTile(item)
            : _letterTile(item, highlight: widget.hintsEnabled && item.isNeeded),
      ),
    );
  }

  Widget _letterTile(_FallingItem item, {bool highlight = false}) {
    final isRevealed = _revealActive &&
        _nextLetterIndex < _currentWord.length &&
        item.letter == _currentWord[_nextLetterIndex];
    final shouldGlow = highlight || isRevealed;
    final pulseVal = (sin(item.pulsePhase) * 0.5 + 0.5);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: shouldGlow
              ? AppColors.electricBlue
                  .withValues(alpha: 0.6 + pulseVal * 0.4)
              : AppColors.border.withValues(alpha: 0.5),
          width: shouldGlow ? 2.0 : 1.0,
        ),
        boxShadow: shouldGlow
            ? [
                BoxShadow(
                  color: AppColors.electricBlue
                      .withValues(alpha: 0.3 + pulseVal * 0.3),
                  blurRadius: 12 + pulseVal * 8,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Text(
        item.letter.toUpperCase(),
        style: AppFonts.fredoka(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: shouldGlow ? AppColors.electricBlue : AppColors.primaryText,
          shadows: shouldGlow
              ? [
                  Shadow(
                    color:
                        AppColors.electricBlue.withValues(alpha: 0.8),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _powerUpTile(_FallingItem item) {
    final pulseVal = sin(item.pulsePhase) * 0.5 + 0.5;
    IconData icon;
    Color color;
    switch (item.powerUp!) {
      case _PowerUpType.shield:
        icon = Icons.favorite;
        color = AppColors.error;
        break;
      case _PowerUpType.slowdown:
        icon = Icons.ac_unit;
        color = AppColors.cyan;
        break;
      case _PowerUpType.reveal:
        icon = Icons.visibility;
        color = AppColors.violet;
        break;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.6 + pulseVal * 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4 + pulseVal * 0.3),
            blurRadius: 16 + pulseVal * 8,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 26),
    );
  }

  Widget _buildHUD(Size screenSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // Top bar: back button, score, lives
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: AppColors.primaryText, size: 18),
                ),
              ),
              const SizedBox(width: 12),

              // Score
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.starGold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.starGold, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '$_score',
                      style: AppFonts.fredoka(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.starGold,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Words completed
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color:
                          AppColors.electricBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Words: $_wordsCompleted',
                  style: AppFonts.fredoka(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.electricBlue,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Lives
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_maxLives, (i) {
                  final alive = i < _lives;
                  return Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      alive ? Icons.favorite : Icons.favorite_border,
                      color: alive
                          ? AppColors.error
                          : AppColors.error.withValues(alpha: 0.3),
                      size: 22,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Word assembly area
        _buildWordSlots(screenSize),

        // Power-up indicators
        if (_slowActive || _revealActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_slowActive)
                  _powerUpIndicator(
                      Icons.ac_unit, AppColors.cyan, _slowTimer),
                if (_slowActive && _revealActive)
                  const SizedBox(width: 8),
                if (_revealActive)
                  _powerUpIndicator(
                      Icons.visibility, AppColors.violet, _revealTimer),
              ],
            ),
          ),
      ],
    );
  }

  Widget _powerUpIndicator(IconData icon, Color color, double timer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            '${timer.ceil()}s',
            style: AppFonts.fredoka(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordSlots(Size screenSize) {
    // Calculate slot rects after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateSlotRects();
    });

    final celebrating = _wordCelebrating;
    final celebrateProgress = _wordCelebrateT.clamp(0.0, 1.0);

    return Container(
      key: _slotRowKey,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_currentWord.length, (i) {
          final filled = _slotsFilled.length > i && _slotsFilled[i];
          final isNext = i == _nextLetterIndex && !celebrating;

          Color borderColor;
          Color bgColor;
          Color textColor;
          double glowRadius = 0;

          if (celebrating) {
            final goldenPulse =
                sin(celebrateProgress * pi * 3 + i * 0.5) * 0.5 + 0.5;
            borderColor = AppColors.starGold
                .withValues(alpha: 0.6 + goldenPulse * 0.4);
            bgColor = AppColors.starGold
                .withValues(alpha: 0.1 + goldenPulse * 0.1);
            textColor = AppColors.starGold;
            glowRadius = 8 + goldenPulse * 12;
          } else if (filled) {
            borderColor =
                AppColors.electricBlue.withValues(alpha: 0.6);
            bgColor =
                AppColors.electricBlue.withValues(alpha: 0.08);
            textColor = AppColors.electricBlue;
            glowRadius = 6;
          } else if (isNext) {
            borderColor =
                AppColors.electricBlue.withValues(alpha: 0.4);
            bgColor = AppColors.surface;
            textColor = AppColors.secondaryText;
          } else {
            borderColor = AppColors.border.withValues(alpha: 0.4);
            bgColor = AppColors.surface.withValues(alpha: 0.5);
            textColor = AppColors.secondaryText;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 38,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: glowRadius > 0
                    ? [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.3),
                          blurRadius: glowRadius,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: filled
                  ? Text(
                      _currentWord[i].toUpperCase(),
                      style: AppFonts.fredoka(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        shadows: [
                          Shadow(
                            color: textColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: 18,
                      height: 3,
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }

  void _calculateSlotRects() {
    final box =
        _slotRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final rowPos = box.localToGlobal(Offset.zero);
    const slotWidth = 38.0;
    const slotHeight = 44.0;
    const spacing = 6.0;
    final totalWidth = _currentWord.length * slotWidth +
        (_currentWord.length - 1) * spacing;
    final startX = rowPos.dx + (box.size.width - totalWidth) / 2;
    final topPadding = MediaQuery.of(context).padding.top;

    _slotRects = List.generate(_currentWord.length, (i) {
      final x = startX + i * (slotWidth + spacing);
      return Rect.fromLTWH(
          x, rowPos.dy + 8 - topPadding, slotWidth, slotHeight);
    });
  }

  Widget _buildGameOver() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Game over title
          Text(
            'GAME OVER',
            style: AppFonts.fredoka(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: AppColors.electricBlue,
              shadows: [
                Shadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Score display
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.starGold.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.starGold, size: 32),
                    const SizedBox(width: 8),
                    Text(
                      '$_score',
                      style: AppFonts.fredoka(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.starGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$_wordsCompleted words completed',
                  style: AppFonts.nunito(
                    fontSize: 16,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Play again button
          GestureDetector(
            onTap: () {
              setState(() => _restartGame());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.electricBlue, AppColors.violet],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.electricBlue.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'Play Again',
                style: AppFonts.fredoka(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Back to menu
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              'Back to Menu',
              style: AppFonts.nunito(
                fontSize: 16,
                color: AppColors.secondaryText,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Combined effects painter (particles + shockwaves) ──────────────────────

class _EffectsPainter extends CustomPainter {
  final List<_ShatterFragment> fragments;
  final List<_DustParticle> dustParticles;
  final List<_SparkleParticle> sparkles;
  final List<_DisintegrationParticle> disintegrationParticles;
  final List<_Shockwave> shockwaves;

  _EffectsPainter({
    required this.fragments,
    required this.dustParticles,
    required this.sparkles,
    required this.disintegrationParticles,
    required this.shockwaves,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Dust particles — simple circles
    for (final d in dustParticles) {
      final a = d.opacity.clamp(0.0, 1.0);
      if (a <= 0) continue;
      paint
        ..color = AppColors.secondaryText.withValues(alpha: a)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(d.x, d.y), d.size / 2, paint);
    }

    // Sparkle particles — circles with a tiny glow
    for (final s in sparkles) {
      final a = s.opacity.clamp(0.0, 1.0);
      if (a <= 0) continue;
      paint
        ..color = s.color.withValues(alpha: a)
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawCircle(Offset(s.x, s.y), s.size / 2, paint);
      // small glow halo
      paint
        ..color = s.color.withValues(alpha: a * 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.size);
      canvas.drawCircle(Offset(s.x, s.y), s.size, paint);
      paint.maskFilter = null;
    }

    // Disintegration particles — small rectangles
    for (final p in disintegrationParticles) {
      final a = p.opacity.clamp(0.0, 1.0);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      paint
        ..color = p.color.withValues(alpha: a)
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: p.size, height: p.size * 0.7),
        paint,
      );
      canvas.restore();
    }

    // Shatter fragments — letter pieces (drawn as small colored squares)
    for (final f in fragments) {
      final a = f.opacity.clamp(0.0, 1.0);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(f.x, f.y);
      canvas.rotate(f.rotation);
      paint
        ..color = AppColors.error.withValues(alpha: a)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 8),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }

    // Shockwave rings — thin expanding ring, no fill
    for (final w in shockwaves) {
      if (w.opacity <= 0) continue;

      final progress = (w.radius / w.maxRadius).clamp(0.0, 1.0);
      final ringColor = Color.lerp(
        Colors.white,
        const Color(0xFF00D4FF),
        progress,
      )!;

      // Outer ring — thin stroke
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * w.opacity
        ..color = ringColor.withValues(alpha: w.opacity * 0.7)
        ..maskFilter = null;
      canvas.drawCircle(Offset(w.cx, w.cy), w.radius, paint);

      // Subtle glow — thinner than before
      paint
        ..strokeWidth = 4.0 * w.opacity
        ..color = ringColor.withValues(alpha: w.opacity * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(w.cx, w.cy), w.radius, paint);
      paint.maskFilter = null;
    }
  }

  @override
  bool shouldRepaint(covariant _EffectsPainter old) => true;
}

// ─── Star field painter ──────────────────────────────────────────────────────

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final _ShootingStar? shootingStar;

  _StarFieldPainter({required this.stars, this.shootingStar});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Nebula glow accents
    final nebulaPaint1 = Paint()
      ..color = const Color(0xFF1A0040).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(
        Offset(size.width * 0.75, size.height * 0.25), 120, nebulaPaint1);
    final nebulaPaint2 = Paint()
      ..color = const Color(0xFF001040).withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    canvas.drawCircle(
        Offset(size.width * 0.2, size.height * 0.55), 100, nebulaPaint2);

    // Draw stars by layer (far first, near last)
    for (final s in stars) {
      final twinkle = (sin(s.twinklePhase) * 0.3 + 0.7).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: s.opacity * twinkle);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        paint,
      );
      // Soft glow for bigger stars (near layer)
      if (s.size > 1.5) {
        final glowPaint = Paint()
          ..color = const Color(0xFF8899FF)
              .withValues(alpha: s.opacity * twinkle * 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(
          Offset(s.x * size.width, s.y * size.height),
          s.size * 2.5,
          glowPaint,
        );
      }
    }

    // Draw shooting star
    if (shootingStar != null) {
      final ss = shootingStar!;
      final sx = ss.x * size.width;
      final sy = ss.y * size.height;
      final len = ss.length * size.width;
      final angle = atan2(ss.vy, ss.vx);

      // Trail
      final trailPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: ss.opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromPoints(
          Offset(sx, sy),
          Offset(sx - cos(angle) * len, sy - sin(angle) * len),
        ))
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(sx, sy),
        Offset(sx - cos(angle) * len, sy - sin(angle) * len),
        trailPaint,
      );

      // Head glow
      paint.color = Colors.white.withValues(alpha: ss.opacity * 0.8);
      canvas.drawCircle(Offset(sx, sy), 2.5, paint);
      paint.color = Colors.white.withValues(alpha: ss.opacity * 0.2);
      canvas.drawCircle(Offset(sx, sy), 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter old) => true;
}

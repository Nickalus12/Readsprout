import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../models/game_difficulty_params.dart';
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
  final GameDifficultyParams? difficultyParams;

  const FallingLettersGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
    this.difficultyParams,
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

// ── Simulation ──────────────────────────────────────────────────────────────

class _FallingLettersSimulation extends ChangeNotifier {
  final Random rng;

  final List<_Star> stars = [];
  _ShootingStar? shootingStar;
  double shootingStarTimer = 0;

  final List<_ShatterFragment> fragments = [];
  final List<_DustParticle> dustParticles = [];
  final List<_SparkleParticle> sparkles = [];
  final List<_DisintegrationParticle> disintegrationParticles = [];
  final List<_Shockwave> shockwaves = [];
  final List<_FallingItem> items = [];

  Offset screenShakeOffset = Offset.zero;
  double screenShakeTimer = 0;

  Color? flashColor;
  double flashOpacity = 0;

  bool warningFlash = false;
  double warningFlashT = 0;

  bool wordCelebrating = false;
  double wordCelebrateT = 0;

  bool slowActive = false;
  double slowTimer = 0;
  bool revealActive = false;
  double revealTimer = 0;

  int nextItemId = 0;
  double spawnAccumulator = 0;

  _FallingLettersSimulation({required this.rng});

  void tick(double dt, _FallingLettersTickContext ctx) {
    _updateStars(dt);
    _updateShootingStar(dt);
    ctx.updateSpawning(dt);
    ctx.updateFallingItems(dt);
    ctx.updateShockwaves(dt);
    _updateFragments(dt);
    _updateDust(dt);
    _updateSparkles(dt);
    _updateDisintegrationParticles(dt);
    _updateFlash(dt);
    _updateScreenShake(dt);
    _updatePowerUpTimers(dt);
    _updateWordCelebration(dt, ctx);
    _updateWarningFlash(dt);
    notifyListeners();
  }

  void _updateStars(double dt) {
    for (final s in stars) {
      s.y += s.speed;
      if (s.y > 1.0) {
        s.y = 0;
        s.x = rng.nextDouble();
      }
      s.twinklePhase += dt * s.twinkleSpeed;
    }
    shootingStarTimer += dt;
    if (shootingStar == null && shootingStarTimer > 4 + rng.nextDouble() * 8) {
      shootingStarTimer = 0;
      shootingStar = _ShootingStar(
        x: rng.nextDouble() * 0.6 + 0.2,
        y: rng.nextDouble() * 0.3,
        vx: (rng.nextBool() ? 1 : -1) * (0.3 + rng.nextDouble() * 0.4),
        vy: 0.15 + rng.nextDouble() * 0.2,
        length: 0.06 + rng.nextDouble() * 0.04,
      );
    }
  }

  void _updateShootingStar(double dt) {
    if (shootingStar == null) return;
    final s = shootingStar!;
    s.x += s.vx * dt;
    s.y += s.vy * dt;
    s.life += dt;
    s.opacity = (1.0 - s.life / 1.5).clamp(0.0, 1.0);
    if (s.opacity <= 0 || s.x < -0.1 || s.x > 1.1 || s.y > 1.1) {
      shootingStar = null;
    }
  }

  void _updateFragments(double dt) {
    for (final f in fragments) {
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.vy += 600 * dt;
      f.rotation += f.rotationSpeed * dt;
      f.opacity -= dt * 1.8;
    }
    fragments.removeWhere((f) => f.opacity <= 0);
    if (fragments.length > 30) {
      fragments.removeRange(0, fragments.length - 30);
    }
  }

  void _updateDust(double dt) {
    for (final d in dustParticles) {
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vy -= 30 * dt;
      d.opacity -= dt * 2.5;
    }
    dustParticles.removeWhere((d) => d.opacity <= 0);
    if (dustParticles.length > 20) {
      dustParticles.removeRange(0, dustParticles.length - 20);
    }
  }

  void _updateSparkles(double dt) {
    for (final s in sparkles) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.opacity -= dt * 2.0;
      s.size *= (1.0 - dt * 1.5).clamp(0.5, 1.0);
    }
    sparkles.removeWhere((s) => s.opacity <= 0);
    if (sparkles.length > 20) {
      sparkles.removeRange(0, sparkles.length - 20);
    }
  }

  void _updateDisintegrationParticles(double dt) {
    for (final p in disintegrationParticles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 200 * dt;
      p.rotation += p.rotationSpeed * dt;
      p.opacity -= dt * 2.0;
    }
    disintegrationParticles.removeWhere((p) => p.opacity <= 0);
    if (disintegrationParticles.length > 30) {
      disintegrationParticles.removeRange(0, disintegrationParticles.length - 30);
    }
  }

  void _updateFlash(double dt) {
    if (flashOpacity > 0) {
      flashOpacity -= dt * 4.0;
      if (flashOpacity <= 0) {
        flashOpacity = 0;
        flashColor = null;
      }
    }
  }

  void _updateScreenShake(double dt) {
    if (screenShakeTimer > 0) {
      screenShakeTimer -= dt;
      if (screenShakeTimer <= 0) {
        screenShakeTimer = 0;
        screenShakeOffset = Offset.zero;
      } else {
        screenShakeOffset = Offset(
          (rng.nextDouble() - 0.5) * 4.0,
          (rng.nextDouble() - 0.5) * 4.0,
        );
      }
    }
  }

  void _updatePowerUpTimers(double dt) {
    if (slowActive) {
      slowTimer -= dt;
      if (slowTimer <= 0) {
        slowActive = false;
        for (final item in items) {
          if (!item.captured && !item.shattered) {
            item.speed /= 0.4;
          }
        }
      }
    }
    if (revealActive) {
      revealTimer -= dt;
      if (revealTimer <= 0) {
        revealActive = false;
      }
    }
  }

  void _updateWordCelebration(double dt, _FallingLettersTickContext ctx) {
    if (wordCelebrating) {
      wordCelebrateT += dt;
      if (wordCelebrateT > 1.2) {
        ctx.nextWord();
      }
    }
  }

  void _updateWarningFlash(double dt) {
    if (warningFlash) {
      warningFlashT += dt;
      if (warningFlashT > 0.5) {
        warningFlash = false;
        warningFlashT = 0;
      }
    }
  }

  void reset(int maxLives) {
    items.clear();
    fragments.clear();
    dustParticles.clear();
    sparkles.clear();
    disintegrationParticles.clear();
    shockwaves.clear();
    slowActive = false;
    revealActive = false;
    spawnAccumulator = 0;
    nextItemId = 0;
    screenShakeTimer = 0;
    screenShakeOffset = Offset.zero;
    flashColor = null;
    flashOpacity = 0;
    warningFlash = false;
    warningFlashT = 0;
    wordCelebrating = false;
    wordCelebrateT = 0;
  }
}

abstract class _FallingLettersTickContext {
  void updateSpawning(double dt);
  void updateFallingItems(double dt);
  void updateShockwaves(double dt);
  void nextWord();
}

// ── State ────────────────────────────────────────────────────────────────────

class _FallingLettersGameState extends State<FallingLettersGame>
    with TickerProviderStateMixin
    implements _FallingLettersTickContext {
  final _rng = Random();
  late final _FallingLettersSimulation _sim;

  static const int _columns = 6;
  late final int _maxLives;
  static const double _baseSpeed = 0.0025;
  static const double _speedIncrease = 0.00008;
  static const double _letterSpawnInterval = 0.8;
  static const double _neededLetterRatio = 0.42;
  static const double _powerUpChance = 0.06;

  static const double _shockwaveSpeed = 600.0;
  static const double _shockwaveRadiusFraction = 0.12;
  static const double _itemHitRadius = 16.0;
  static const double _pushMagnitude = 0.35;

  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  late int _lives;
  int _wordsCompleted = 0;

  List<String> _wordPool = [];
  int _wordPoolIndex = 0;
  String _currentWord = '';
  int _nextLetterIndex = 0;
  List<bool> _slotsFilled = [];

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  List<Rect> _slotRects = [];
  final GlobalKey _slotRowKey = GlobalKey();

  Size _screenSize = Size.zero;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _maxLives = widget.difficultyParams?.lives ?? 3;
    _lives = _maxLives;
    _sessionTimer = Stopwatch()..start();
    _sim = _FallingLettersSimulation(rng: _rng);
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
    _sim.dispose();
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

  @override
  void nextWord() {
    _nextWord();
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
    _sim.wordCelebrating = false;
    _sim.wordCelebrateT = 0;

    _ensureNeededLetterExists();
  }

  // ── Stars ──────────────────────────────────────────────────────────────

  void _initStars() {
    for (int i = 0; i < 40; i++) {
      _sim.stars.add(_Star(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
        size: 0.5 + _rng.nextDouble() * 0.7,
        opacity: 0.2 + _rng.nextDouble() * 0.3,
        speed: 0.00005 + _rng.nextDouble() * 0.0001,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 0.5 + _rng.nextDouble() * 1.0,
        layer: 0,
      ));
    }
    for (int i = 0; i < 25; i++) {
      _sim.stars.add(_Star(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
        size: 1.0 + _rng.nextDouble() * 1.0,
        opacity: 0.3 + _rng.nextDouble() * 0.4,
        speed: 0.0002 + _rng.nextDouble() * 0.0003,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 1.0 + _rng.nextDouble() * 2.0,
        layer: 1,
      ));
    }
    for (int i = 0; i < 15; i++) {
      _sim.stars.add(_Star(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
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
    if (!mounted || !_gameStarted || _gameOver) return;

    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    final cdt = dt.clamp(0.0, 0.05);

    _sim.tick(cdt, this);
  }

  @override
  void updateSpawning(double dt) {
    _updateSpawning(dt);
  }

  @override
  void updateFallingItems(double dt) {
    _updateFallingItems(dt);
  }

  @override
  void updateShockwaves(double dt) {
    _updateShockwaves(dt);
  }

  void _updateSpawning(double dt) {
    final interval = _letterSpawnInterval *
        (1.0 - (_wordsCompleted * 0.02).clamp(0.0, 0.4));
    _sim.spawnAccumulator += dt;
    if (_sim.spawnAccumulator >= interval) {
      _sim.spawnAccumulator -= interval;
      _spawnItem();
    }
  }

  void _spawnItem() {
    if (_gameOver || _sim.wordCelebrating) return;

    final neededLetter = _nextLetterIndex < _currentWord.length
        ? _currentWord[_nextLetterIndex]
        : null;

    if (_rng.nextDouble() < _powerUpChance) {
      _spawnPowerUp();
      return;
    }

    bool makeNeeded = false;
    if (neededLetter != null) {
      final hasNeeded = _sim.items
          .any((i) => i.isNeeded && !i.captured && !i.shattered && !i.missed);
      if (!hasNeeded) {
        makeNeeded = true;
      } else {
        makeNeeded = _rng.nextDouble() < _neededLetterRatio;
      }
    }

    String letter;
    if (makeNeeded && neededLetter != null) {
      letter = neededLetter;
    } else {
      letter = String.fromCharCode(97 + _rng.nextInt(26));
    }

    final col = _rng.nextInt(_columns);
    const colWidth = 1.0 / _columns;
    final x = col * colWidth + colWidth * 0.5;
    final speed = _currentSpeed * (0.8 + _rng.nextDouble() * 0.4);

    _sim.items.add(_FallingItem(
      letter: letter,
      x: x,
      y: -0.08,
      speed: _sim.slowActive ? speed * 0.4 : speed,
      rotation: (_rng.nextDouble() - 0.5) * 0.4,
      rotationSpeed: (_rng.nextDouble() - 0.5) * 1.5,
      isNeeded: makeNeeded,
      id: _sim.nextItemId++,
      pulsePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  void _spawnPowerUp() {
    const types = _PowerUpType.values;
    final type = types[_rng.nextInt(types.length)];
    final col = _rng.nextInt(_columns);
    const colWidth = 1.0 / _columns;
    final x = col * colWidth + colWidth * 0.5;

    _sim.items.add(_FallingItem(
      letter: '',
      x: x,
      y: -0.08,
      speed: _currentSpeed * 0.6,
      rotation: 0,
      rotationSpeed: 0.5,
      powerUp: type,
      id: _sim.nextItemId++,
      pulsePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  void _ensureNeededLetterExists() {
    if (_nextLetterIndex >= _currentWord.length) return;
    final hasNeeded = _sim.items
        .any((i) => i.isNeeded && !i.captured && !i.shattered && !i.missed);
    if (!hasNeeded) {
      final neededLetter = _currentWord[_nextLetterIndex];
      final col = _rng.nextInt(_columns);
      const colWidth = 1.0 / _columns;
      final x = col * colWidth + colWidth * 0.5;

      _sim.items.add(_FallingItem(
        letter: neededLetter,
        x: x,
        y: -0.05,
        speed: _currentSpeed * (0.8 + _rng.nextDouble() * 0.4),
        rotation: (_rng.nextDouble() - 0.5) * 0.4,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 1.5,
        isNeeded: true,
        id: _sim.nextItemId++,
        pulsePhase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  double get _currentSpeed => _baseSpeed + _wordsCompleted * _speedIncrease;

  void _updateFallingItems(double dt) {
    final toRemove = <int>[];

    for (final item in _sim.items) {
      if (item.captured) {
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

      item.y += item.speed * (dt / 0.016) + item.extraVy * dt;
      item.x += item.vx * dt;
      item.rotation += item.rotationSpeed * dt;
      item.pulsePhase += dt * 3.0;
      item.vx *= (1.0 - dt * 3.0).clamp(0.0, 1.0);
      item.extraVy *= (1.0 - dt * 3.0).clamp(0.0, 1.0);
      item.x = item.x.clamp(0.05, 0.95);

      if (item.y > 1.05) {
        if (item.powerUp != null) {
          toRemove.add(item.id);
          continue;
        }
        if (item.isNeeded) {
          item.missed = true;
          _onNeededLetterMissed(item);
        } else {
          toRemove.add(item.id);
        }
      }
    }

    _sim.items.removeWhere((i) => toRemove.contains(i.id));

    if (!_sim.wordCelebrating && _nextLetterIndex < _currentWord.length) {
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

    for (final wave in _sim.shockwaves) {
      wave.radius += _shockwaveSpeed * dt;
      wave.opacity = (1.0 - wave.radius / wave.maxRadius).clamp(0.0, 1.0);

      for (final item in _sim.items) {
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

    _sim.shockwaves.removeWhere(
        (w) => w.opacity <= 0 || w.radius >= w.maxRadius);
  }

  void _onShockwaveHitCorrect(_FallingItem item, _Shockwave wave) {
    final sw = _screenSize.width;
    final sh = _screenSize.height;
    final itemPx = item.x * sw;
    final itemPy = item.y * sh;

    final particleCount = 8 + _rng.nextInt(5);
    for (int i = 0; i < particleCount; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 80.0 + _rng.nextDouble() * 180.0;
      _sim.disintegrationParticles.add(_DisintegrationParticle(
        x: itemPx + (_rng.nextDouble() - 0.5) * 20,
        y: itemPy + (_rng.nextDouble() - 0.5) * 20,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40,
        size: 3.0 + _rng.nextDouble() * 5.0,
        color: AppColors.electricBlue
            .withValues(alpha: 0.7 + _rng.nextDouble() * 0.3),
        rotation: _rng.nextDouble() * pi * 2,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 8.0,
      ));
    }

    Offset target = Offset(sw / 2, 80);
    if (_slotRects.isNotEmpty && _nextLetterIndex < _slotRects.length) {
      final rect = _slotRects[_nextLetterIndex];
      target = rect.center;
    }

    item.captured = true;
    item.isNeeded = false;
    item.captureAnimT = 0;
    item.captureTarget = target;

    for (final other in _sim.items) {
      if (other.id != item.id &&
          other.isNeeded &&
          !other.captured &&
          !other.shattered) {
        other.isNeeded = false;
      }
    }

    for (int i = 0; i < 8; i++) {
      _sim.sparkles.add(_SparkleParticle(
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

    _sim.flashColor = AppColors.electricBlue;
    _sim.flashOpacity = 0.15;

    widget.audioService.playLetter(item.letter);

    if (_nextLetterIndex >= _currentWord.length) {
      _onWordComplete();
    }
    setState(() {});
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


  // ── Screen tap ──────────────────────────────────────────────────────────

  void _onScreenTap(Offset position) {
    if (_gameOver || !_gameStarted || _sim.wordCelebrating) return;
    if (_sim.shockwaves.length >= 3) return;

    final maxRadius = _screenSize.width * _shockwaveRadiusFraction;

    _sim.shockwaves.add(_Shockwave(
      cx: position.dx,
      cy: position.dy,
      maxRadius: maxRadius,
    ));

    _sim.screenShakeTimer = 0.1;

    Haptics.correct();
  }


  // ── Event handlers ──────────────────────────────────────────────────────

  void _onNeededLetterMissed(_FallingItem item) {
    _lives--;
    _sim.warningFlash = true;
    _sim.warningFlashT = 0;

    final px = item.x * (_slotRowKey.currentContext?.size?.width ?? 400);
    for (int i = 0; i < 6; i++) {
      _sim.dustParticles.add(_DustParticle(
        x: px + (_rng.nextDouble() - 0.5) * 30,
        y: (_slotRowKey.currentContext?.size?.height ?? 600) - 20,
        vx: (_rng.nextDouble() - 0.5) * 40,
        vy: -20 - _rng.nextDouble() * 30,
        size: 3 + _rng.nextDouble() * 5,
      ));
    }

    _sim.flashColor = AppColors.error;
    _sim.flashOpacity = 0.3;

    widget.audioService.playError();
    Haptics.wrong();

    if (_lives <= 0) {
      _gameOver = true;
      _awardMiniGameStickers();
      widget.audioService.playError();
    }
    setState(() {});
  }

  void _onWordComplete() {
    _sim.wordCelebrating = true;
    _sim.wordCelebrateT = 0;
    _wordsCompleted++;
    _score += _currentWord.length * 10;

    widget.audioService.playWord(_currentWord);
    widget.audioService.playSuccess();
    Haptics.success();

    _sim.flashColor = AppColors.starGold;
    _sim.flashOpacity = 0.25;

    _sim.items.removeWhere((i) => !i.captured);
    setState(() {});
  }

  void _activatePowerUp(_FallingItem item) {
    switch (item.powerUp!) {
      case _PowerUpType.shield:
        _lives = (_lives + 1).clamp(0, _maxLives + 1);
        _sim.flashColor = AppColors.emerald;
        _sim.flashOpacity = 0.2;
        break;
      case _PowerUpType.slowdown:
        _sim.slowActive = true;
        _sim.slowTimer = 5.0;
        for (final it in _sim.items) {
          if (!it.captured && !it.shattered) {
            it.speed *= 0.4;
          }
        }
        _sim.flashColor = AppColors.cyan;
        _sim.flashOpacity = 0.2;
        break;
      case _PowerUpType.reveal:
        _sim.revealActive = true;
        _sim.revealTimer = 3.0;
        _sim.flashColor = AppColors.violet;
        _sim.flashOpacity = 0.2;
        break;
    }
    item.captured = true;
    item.captureAnimT = 0;
    widget.audioService.playSuccess();
    Haptics.correct();
    setState(() {});
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
    _sim.reset(_maxLives);
    _score = 0;
    _lives = _maxLives;
    _wordsCompleted = 0;
    _gameOver = false;
    _lastTick = Duration.zero;
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
        return ListenableBuilder(
          listenable: _sim,
          builder: (context, _) => Transform.translate(
            offset: _sim.screenShakeOffset,
            child: Stack(
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: _StarFieldPainter(
                      stars: _sim.stars,
                      shootingStar: _sim.shootingStar,
                      repaintSignal: _sim,
                    ),
                  ),
                ),

                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) =>
                        _onScreenTap(details.localPosition),
                  ),
                ),

                ..._sim.items.where((i) => !i.missed).map(
                      (item) => _buildFallingItem(item, size)),

                RepaintBoundary(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: size,
                      painter: _EffectsPainter(
                        fragments: _sim.fragments,
                        dustParticles: _sim.dustParticles,
                        sparkles: _sim.sparkles,
                        disintegrationParticles: _sim.disintegrationParticles,
                        shockwaves: _sim.shockwaves,
                        repaintSignal: _sim,
                      ),
                    ),
                  ),
                ),

                if (_sim.flashColor != null && _sim.flashOpacity > 0)
                  IgnorePointer(
                    child: Container(
                      color: _sim.flashColor!
                          .withValues(alpha: _sim.flashOpacity.clamp(0.0, 1.0)),
                    ),
                  ),

                if (_sim.warningFlash)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.error.withValues(
                              alpha:
                                  (1.0 - _sim.warningFlashT * 2).clamp(0.0, 0.8)),
                          width: 4,
                        ),
                      ),
                    ),
                  ),

                _buildHUD(size),
              ],
            ),
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
    final isRevealed = _sim.revealActive &&
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
        if (_sim.slowActive || _sim.revealActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_sim.slowActive)
                  _powerUpIndicator(
                      Icons.ac_unit, AppColors.cyan, _sim.slowTimer),
                if (_sim.slowActive && _sim.revealActive)
                  const SizedBox(width: 8),
                if (_sim.revealActive)
                  _powerUpIndicator(
                      Icons.visibility, AppColors.violet, _sim.revealTimer),
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

    final celebrating = _sim.wordCelebrating;
    final celebrateProgress = _sim.wordCelebrateT.clamp(0.0, 1.0);

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
    Listenable? repaintSignal,
  }) : super(repaint: repaintSignal);

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
  bool shouldRepaint(covariant _EffectsPainter old) => false;
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

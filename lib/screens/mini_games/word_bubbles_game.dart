import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Word Bubbles — An underwater bubble-popping sight word mini game
// ---------------------------------------------------------------------------

class WordBubblesGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;
  final bool hintsEnabled;

  const WordBubblesGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
  });

  @override
  State<WordBubblesGame> createState() => _WordBubblesGameState();
}

class _WordBubblesGameState extends State<WordBubblesGame>
    with TickerProviderStateMixin {
  final _rng = Random();

  // -- Word pool -----------------------------------------------------------
  List<String> _wordPool = [];
  String _targetWord = '';

  // -- Bubbles on screen ---------------------------------------------------
  final List<_Bubble> _bubbles = [];
  int _nextBubbleId = 0;

  // -- Score / lives / combo -----------------------------------------------
  int _score = 0;
  int _lives = 3;
  int _combo = 0;
  int _comboMultiplier = 1;

  // -- Timer (60 seconds) --------------------------------------------------
  static const int _gameDuration = 60;
  int _secondsLeft = _gameDuration;
  Timer? _countdownTimer;

  // -- Pop effects ---------------------------------------------------------
  final List<_PopEffect> _popEffects = [];

  // -- Game loop -----------------------------------------------------------
  late AnimationController _loopController;

  // -- Background particles ------------------------------------------------
  final List<_Particle> _bgParticles = [];

  // -- Light rays ----------------------------------------------------------
  final List<_LightRay> _lightRays = [];

  // -- Seaweed -------------------------------------------------------------
  late AnimationController _seaweedController;

  // -- Fish ----------------------------------------------------------------
  final List<_Fish> _fishList = [];

  // -- Ambient bubble streams ----------------------------------------------
  final List<_AmbientBubble> _ambientBubbles = [];

  // -- Water current -------------------------------------------------------
  double _waterCurrentTime = 0.0;
  double _waterCurrentPhase = 0.0; // sinusoidal shift direction

  // -- Game state ----------------------------------------------------------
  bool _gameStarted = false;
  bool _gameOver = false;

  // -- Best combo ----------------------------------------------------------
  int _bestCombo = 0;

  // -- Spawn timing --------------------------------------------------------
  double _spawnAccumulator = 0.0;
  double _spawnInterval = 1.8; // seconds between spawns

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _buildWordPool();
    _initBackgroundElements();
    _initFish();
    _initAmbientBubbles();

    _seaweedController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // runs forever
    );
    _loopController.addListener(_gameLoop);

    // Start after a brief intro
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _gameStarted = true);
        _pickNewTarget();
        _startCountdown();
        _loopController.forward();
      }
    });
  }

  // ── Word pool ──────────────────────────────────────────────────────────

  void _buildWordPool() {
    final unlocked = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        final words = DolchWords.wordsForLevel(level);
        unlocked.addAll(words.map((w) => w.text.toLowerCase()));
      }
    }
    if (unlocked.isEmpty) {
      unlocked
          .addAll(DolchWords.wordsForLevel(1).map((w) => w.text.toLowerCase()));
    }
    unlocked.shuffle(_rng);
    _wordPool = unlocked;
  }

  void _pickNewTarget() {
    if (_wordPool.isEmpty) _buildWordPool();
    _targetWord = _wordPool[_rng.nextInt(_wordPool.length)];
    widget.audioService.playWord(_targetWord);
  }

  // ── Background elements ────────────────────────────────────────────────

  void _initBackgroundElements() {
    // Floating particles (plankton / underwater dust)
    for (int i = 0; i < 40; i++) {
      _bgParticles.add(_Particle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 1.0 + _rng.nextDouble() * 2.5,
        speedX: (_rng.nextDouble() - 0.5) * 0.0003,
        speedY: -0.0001 - _rng.nextDouble() * 0.0004,
        opacity: 0.15 + _rng.nextDouble() * 0.25,
      ));
    }
    // Light rays from above
    for (int i = 0; i < 5; i++) {
      _lightRays.add(_LightRay(
        x: 0.1 + _rng.nextDouble() * 0.8,
        width: 0.04 + _rng.nextDouble() * 0.06,
        opacity: 0.03 + _rng.nextDouble() * 0.04,
        angle: -0.15 + _rng.nextDouble() * 0.3,
      ));
    }
  }

  // ── Fish initialization ────────────────────────────────────────────────

  void _initFish() {
    const fishTypes = [0, 1, 2, 3]; // orange, blue, yellow, green
    for (int i = 0; i < 6; i++) {
      _fishList.add(_Fish(
        x: 0.1 + _rng.nextDouble() * 0.8,
        y: 0.3 + _rng.nextDouble() * 0.55,
        direction: _rng.nextBool() ? 1.0 : -1.0,
        speed: 0.03 + _rng.nextDouble() * 0.04,
        type: fishTypes[i % fishTypes.length],
        tailPhase: _rng.nextDouble() * pi * 2,
        scatterTimer: 0.0,
        age: _rng.nextDouble() * 10.0,
        turnTimer: 2.0 + _rng.nextDouble() * 6.0,
        verticalOffset: 0.0,
      ));
    }
  }

  // ── Ambient bubble streams ────────────────────────────────────────────

  void _initAmbientBubbles() {
    for (int i = 0; i < 12; i++) {
      _ambientBubbles.add(_AmbientBubble(
        x: 0.05 + _rng.nextDouble() * 0.9,
        y: 0.5 + _rng.nextDouble() * 0.6,
        size: 1.5 + _rng.nextDouble() * 3.5,
        speed: 0.02 + _rng.nextDouble() * 0.04,
        wobblePhase: _rng.nextDouble() * pi * 2,
        opacity: 0.15 + _rng.nextDouble() * 0.25,
      ));
    }
  }

  // ── Countdown timer ────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _endGame();
        }
      });
    });
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _loopController.stop();
    setState(() => _gameOver = true);
    _awardMiniGameStickers();
    if (_score > 0) {
      widget.audioService.playSuccess();
    }
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('word_bubbles', _score);
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

  // ── Game loop (called every frame via AnimationController) ─────────────

  DateTime _lastFrameTime = DateTime.now();

  void _gameLoop() {
    if (_gameOver || !_gameStarted) return;

    final now = DateTime.now();
    final dt = (now.difference(_lastFrameTime).inMicroseconds) / 1000000.0;
    _lastFrameTime = now;

    // Clamp dt to avoid huge jumps if app was suspended
    final clampedDt = dt.clamp(0.0, 0.05);

    _updateBubbles(clampedDt);
    _updatePopEffects(clampedDt);
    _updateBackgroundParticles(clampedDt);
    _updateFish(clampedDt);
    _updateAmbientBubbles(clampedDt);
    _updateWaterCurrent(clampedDt);
    _maybeSpawnBubble(clampedDt);

    if (mounted) setState(() {});
  }

  // ── Bubble spawning ────────────────────────────────────────────────────

  void _maybeSpawnBubble(double dt) {
    _spawnAccumulator += dt;

    // 3-5 bubbles on screen at once
    final currentCount = _bubbles.length;

    if (_spawnAccumulator >= _spawnInterval && currentCount < 5) {
      _spawnAccumulator = 0.0;
      _spawnBubble();

      // Speed up spawning if we have fewer bubbles than minimum
      if (currentCount < 3) {
        _spawnInterval = 0.6 + _rng.nextDouble() * 0.5;
      } else {
        _spawnInterval = 1.4 + _rng.nextDouble() * 1.0;
      }
    }
  }

  void _spawnBubble() {
    // Decide if this bubble is the correct word (~35%) or a distractor (~65%)
    final isCorrect = _rng.nextDouble() < 0.35;
    String word;
    if (isCorrect) {
      word = _targetWord;
    } else {
      // Pick a distractor that is NOT the target
      int tries = 0;
      do {
        word = _wordPool[_rng.nextInt(_wordPool.length)];
        tries++;
      } while (word == _targetWord && tries < 20);
    }

    // Random size
    final radius = 36.0 + _rng.nextDouble() * 20.0; // 36-56
    final speed = 0.12 - (radius - 36) / 20 * 0.05; // larger = slower

    // Pick an x position that avoids overlapping existing bubbles
    double x = 0.15 + _rng.nextDouble() * 0.7;
    for (int attempt = 0; attempt < 10; attempt++) {
      bool overlaps = false;
      for (final b in _bubbles) {
        final dist = (b.x - x).abs();
        if (dist < (b.radius + radius) / 400) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) break;
      x = 0.15 + _rng.nextDouble() * 0.7;
    }

    // Horizontal wobble parameters
    final wobbleSpeed = 0.5 + _rng.nextDouble() * 1.0;
    final wobbleAmount = 0.01 + _rng.nextDouble() * 0.02;
    final wobblePhase = _rng.nextDouble() * pi * 2;

    // Iridescent hue offset
    final hueOffset = _rng.nextDouble() * 360;

    _bubbles.add(_Bubble(
      id: _nextBubbleId++,
      word: word,
      isTarget: word == _targetWord,
      x: x,
      y: 1.15, // start below screen
      radius: radius,
      speed: speed,
      wobbleSpeed: wobbleSpeed,
      wobbleAmount: wobbleAmount,
      wobblePhase: wobblePhase,
      hueOffset: hueOffset,
      age: 0,
    ));
  }

  // ── Bubble update ──────────────────────────────────────────────────────

  void _updateBubbles(double dt) {
    final toRemove = <int>[];

    // Water current: sinusoidal horizontal drift
    final currentDrift = sin(_waterCurrentPhase) * 0.015 * dt;

    for (final bubble in _bubbles) {
      bubble.age += dt;
      bubble.y -= bubble.speed * dt;
      bubble.x += sin(bubble.age * bubble.wobbleSpeed * pi * 2 +
              bubble.wobblePhase) *
          bubble.wobbleAmount *
          dt *
          5;

      // Apply water current
      bubble.x += currentDrift;

      // Size oscillation: subtle radius pulsing
      bubble.displayRadius = bubble.radius +
          sin(bubble.age * 3 + bubble.hueOffset) * 1.5;

      // Clamp x
      bubble.x = bubble.x.clamp(0.05, 0.95);

      // If bubble floated off the top
      if (bubble.y < -0.15) {
        if (bubble.isTarget) {
          // Lose a life for missing the correct bubble
          _lives--;
          if (_lives <= 0) {
            _endGame();
            return;
          }
          // Reset combo
          _combo = 0;
          _comboMultiplier = 1;
        }
        toRemove.add(bubble.id);
      }
    }

    // Soft repulsion between bubble pairs
    for (int i = 0; i < _bubbles.length; i++) {
      for (int j = i + 1; j < _bubbles.length; j++) {
        final a = _bubbles[i];
        final b = _bubbles[j];
        final dx = a.x - b.x;
        final dy = a.y - b.y;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = (a.radius + b.radius) / 400 * 1.5;
        if (dist < minDist && dist > 0.001) {
          final pushStrength = (minDist - dist) * 0.3 * dt;
          final nx = dx / dist;
          final ny = dy / dist;
          a.x += nx * pushStrength;
          a.y += ny * pushStrength;
          b.x -= nx * pushStrength;
          b.y -= ny * pushStrength;
        }
      }
    }

    _bubbles.removeWhere((b) => toRemove.contains(b.id));

    // If no target bubble exists on screen, ensure next spawn is soon
    final hasTarget = _bubbles.any((b) => b.isTarget);
    if (!hasTarget && _spawnAccumulator < _spawnInterval - 0.3) {
      _spawnAccumulator = _spawnInterval - 0.3;
    }
  }

  // ── Pop effects update ─────────────────────────────────────────────────

  void _updatePopEffects(double dt) {
    for (final effect in _popEffects) {
      effect.age += dt;
      for (final droplet in effect.droplets) {
        droplet.x += droplet.vx * dt;
        droplet.y += droplet.vy * dt;
        droplet.vy += 200 * dt; // gravity
      }
    }
    _popEffects.removeWhere((e) => e.age > 0.6);
  }

  // ── Background particles update ────────────────────────────────────────

  void _updateBackgroundParticles(double dt) {
    for (final p in _bgParticles) {
      p.x += p.speedX;
      p.y += p.speedY;
      if (p.y < -0.05) {
        p.y = 1.05;
        p.x = _rng.nextDouble();
      }
      if (p.x < 0) p.x = 1.0;
      if (p.x > 1) p.x = 0.0;
    }
  }

  // ── Fish update ────────────────────────────────────────────────────────

  void _updateFish(double dt) {
    for (final fish in _fishList) {
      fish.age += dt;
      fish.tailPhase += dt * 8; // tail flapping speed

      // Scatter behavior (when a bubble pops nearby)
      if (fish.scatterTimer > 0) {
        fish.scatterTimer -= dt;
        // Move fast in current direction during scatter
        fish.x += fish.direction * fish.speed * 4 * dt;
        fish.y += sin(fish.age * 5) * 0.08 * dt;
      } else {
        // Normal swimming: sine-wave vertical + steady horizontal
        fish.turnTimer -= dt;
        if (fish.turnTimer <= 0) {
          // Occasionally change direction
          if (_rng.nextDouble() < 0.4) {
            fish.direction = -fish.direction;
          }
          fish.turnTimer = 3.0 + _rng.nextDouble() * 5.0;
        }

        fish.x += fish.direction * fish.speed * dt;
        fish.verticalOffset = sin(fish.age * 1.2 + fish.tailPhase * 0.1) * 0.02;
        fish.y += fish.verticalOffset * dt * 2;

        // Bubble avoidance: steer away from nearby game bubbles
        for (final bubble in _bubbles) {
          final dx = fish.x - bubble.x;
          final dy = fish.y - bubble.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist < 0.12 && dist > 0.001) {
            fish.x += (dx / dist) * 0.05 * dt;
            fish.y += (dy / dist) * 0.05 * dt;
          }
        }
      }

      // Wrap around screen edges
      if (fish.x < -0.05) {
        fish.x = 1.05;
      } else if (fish.x > 1.05) {
        fish.x = -0.05;
      }
      fish.y = fish.y.clamp(0.15, 0.92);
    }

    // Simple schooling: nearby fish tend to align direction
    for (int i = 0; i < _fishList.length; i++) {
      for (int j = i + 1; j < _fishList.length; j++) {
        final a = _fishList[i];
        final b = _fishList[j];
        final dist = sqrt(
            (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
        if (dist < 0.15 && a.scatterTimer <= 0 && b.scatterTimer <= 0) {
          // Gently align directions
          if (a.direction != b.direction && _rng.nextDouble() < 0.01) {
            b.direction = a.direction;
          }
        }
      }
    }
  }

  // ── Ambient bubbles update ────────────────────────────────────────────

  void _updateAmbientBubbles(double dt) {
    for (final ab in _ambientBubbles) {
      ab.y -= ab.speed * dt;
      ab.x += sin(ab.wobblePhase + ab.y * 10) * 0.003 * dt;

      if (ab.y < -0.05) {
        ab.y = 1.05;
        ab.x = 0.05 + _rng.nextDouble() * 0.9;
        ab.size = 1.5 + _rng.nextDouble() * 3.5;
      }
    }
  }

  // ── Water current update ──────────────────────────────────────────────

  void _updateWaterCurrent(double dt) {
    _waterCurrentTime += dt;
    // Change direction every ~10 seconds with smooth sine
    _waterCurrentPhase = _waterCurrentTime * 0.6;
  }

  // ── Bubble tap handler ─────────────────────────────────────────────────

  void _onBubbleTap(_Bubble bubble) {
    if (_gameOver) return;

    if (bubble.isTarget) {
      // Correct!
      widget.audioService.playSuccess();
      Haptics.success();
      _combo++;
      if (_combo > _bestCombo) _bestCombo = _combo;
      if (_combo >= 6) {
        _comboMultiplier = 3;
      } else if (_combo >= 3) {
        _comboMultiplier = 2;
      }
      _score += 1 * _comboMultiplier;

      _spawnPopEffect(bubble, true);
      _applyPopPressureWave(bubble);
      _bubbles.removeWhere((b) => b.id == bubble.id);

      // Pick a new target word
      _pickNewTarget();

      // Update existing bubbles' isTarget status
      for (final b in _bubbles) {
        b.isTarget = (b.word == _targetWord);
      }
    } else {
      // Wrong!
      widget.audioService.playError();
      Haptics.wrong();
      _combo = 0;
      _comboMultiplier = 1;

      _spawnPopEffect(bubble, false);
      _applyPopPressureWave(bubble);
      _bubbles.removeWhere((b) => b.id == bubble.id);
    }
  }

  /// Push nearby bubbles outward and scatter nearby fish
  void _applyPopPressureWave(_Bubble popped) {
    // Push nearby bubbles
    for (final b in _bubbles) {
      if (b.id == popped.id) continue;
      final dx = b.x - popped.x;
      final dy = b.y - popped.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.25 && dist > 0.001) {
        final force = (0.25 - dist) * 0.08;
        b.x += (dx / dist) * force;
        b.y += (dy / dist) * force;
      }
    }

    // Scatter nearby fish
    for (final fish in _fishList) {
      final dx = fish.x - popped.x;
      final dy = fish.y - popped.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.3) {
        fish.scatterTimer = 0.5 + _rng.nextDouble() * 0.5;
        // Dart away from pop
        fish.direction = dx >= 0 ? 1.0 : -1.0;
      }
    }
  }

  void _spawnPopEffect(_Bubble bubble, bool isCorrect) {
    final droplets = <_Droplet>[];
    final count = (isCorrect && widget.hintsEnabled) ? 16 : 10;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * pi * 2 + _rng.nextDouble() * 0.3;
      final speed = 80 + _rng.nextDouble() * 150;
      droplets.add(_Droplet(
        x: 0,
        y: 0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40,
        size: 1.5 + _rng.nextDouble() * 3.5,
      ));
    }

    // Add small rising air bubbles from the pop
    for (int i = 0; i < 5; i++) {
      droplets.add(_Droplet(
        x: (_rng.nextDouble() - 0.5) * 20,
        y: 0,
        vx: (_rng.nextDouble() - 0.5) * 30,
        vy: -(60 + _rng.nextDouble() * 80), // rise upward
        size: 1.0 + _rng.nextDouble() * 2.0,
      ));
    }

    _popEffects.add(_PopEffect(
      x: bubble.x,
      y: bubble.y,
      isCorrect: isCorrect,
      droplets: droplets,
      age: 0,
      rippleCount: (isCorrect && widget.hintsEnabled) ? 3 : 2,
    ));
  }

  void _replayTarget() {
    widget.audioService.playWord(_targetWord);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _loopController.removeListener(_gameLoop);
    _loopController.dispose();
    _seaweedController.dispose();
    _sessionTimer.stop();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040820),
      body: Stack(
        children: [
          // Underwater background
          _buildBackground(context),
          // Sandy bottom
          _buildSandyBottom(context),
          // Light rays
          _buildLightRays(context),
          // Background particles
          _buildBackgroundParticles(context),
          // Ambient bubble streams
          _buildAmbientBubbles(context),
          // Seaweed
          _buildSeaweed(context),
          // Fish (decorative, behind game bubbles)
          IgnorePointer(child: _buildFish(context)),
          // Bubbles
          ..._buildBubbles(context),
          // Pop effects (IgnorePointer so it doesn't block bubble taps)
          IgnorePointer(child: _buildPopEffects(context)),
          // Caustics overlay
          IgnorePointer(child: _buildCaustics(context)),
          // HUD
          SafeArea(child: _buildHUD(context)),
          // Game over overlay
          if (_gameOver) _buildGameOver(context),
          // Pre-game overlay
          if (!_gameStarted) _buildGetReady(context),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────

  Widget _buildBackground(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1628), // Deep ocean top
            Color(0xFF061224), // Mid
            Color(0xFF040E1E), // Darker
            Color(0xFF030918), // Abyss
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }

  Widget _buildLightRays(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _LightRayPainter(rays: _lightRays),
    );
  }

  Widget _buildBackgroundParticles(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _ParticlePainter(particles: _bgParticles),
    );
  }

  Widget _buildSeaweed(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _seaweedController,
      builder: (context, _) {
        return CustomPaint(
          size: size,
          painter: _SeaweedPainter(
            swayPhase: _seaweedController.value,
          ),
        );
      },
    );
  }

  // ── Sandy bottom ───────────────────────────────────────────────────────

  Widget _buildSandyBottom(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _SandyBottomPainter(),
    );
  }

  // ── Fish ───────────────────────────────────────────────────────────────

  Widget _buildFish(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _FishPainter(fish: _fishList),
    );
  }

  // ── Ambient bubbles ───────────────────────────────────────────────────

  Widget _buildAmbientBubbles(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _AmbientBubblePainter(bubbles: _ambientBubbles),
    );
  }

  // ── Caustics overlay ──────────────────────────────────────────────────

  Widget _buildCaustics(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _CausticsPainter(time: _waterCurrentTime),
    );
  }

  // ── Bubbles ────────────────────────────────────────────────────────────

  List<Widget> _buildBubbles(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return _bubbles.map((bubble) {
      final r = bubble.displayRadius;
      final left = bubble.x * size.width - r;
      final top = bubble.y * size.height - r;

      return Positioned(
        left: left,
        top: top,
        child: GestureDetector(
          onTap: () => _onBubbleTap(bubble),
          child: CustomPaint(
            size: Size(r * 2, r * 2),
            painter: _BubblePainter(
              hueOffset: bubble.hueOffset,
              age: bubble.age,
            ),
            child: SizedBox(
              width: r * 2,
              height: r * 2,
              child: Center(
                child: Text(
                  bubble.word,
                  textAlign: TextAlign.center,
                  style: AppFonts.fredoka(
                    fontSize: (r * 0.42).clamp(12.0, 22.0),
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Pop effects ────────────────────────────────────────────────────────

  Widget _buildPopEffects(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return CustomPaint(
      size: size,
      painter: _PopEffectPainter(effects: _popEffects, screenSize: size, hintsEnabled: widget.hintsEnabled),
    );
  }

  // ── HUD ────────────────────────────────────────────────────────────────

  Widget _buildHUD(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: back, timer bar, score, lives
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.primaryText),
              ),
              const SizedBox(width: 8),
              // Timer bar
              Expanded(child: _buildTimerBar()),
              const SizedBox(width: 12),
              // Score
              _buildScoreBadge(),
              const SizedBox(width: 8),
              // Lives
              _buildLives(),
            ],
          ),
          const SizedBox(height: 8),
          // Second row: target word bubble + combo + replay
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_comboMultiplier > 1) ...[
                _buildComboIndicator(),
                const SizedBox(width: 12),
              ],
              _buildTargetWordBubble(),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _replayTarget,
                icon: const Icon(Icons.volume_up_rounded,
                    color: AppColors.secondaryText, size: 24),
                tooltip: 'Hear word again',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimerBar() {
    final fraction = _secondsLeft / _gameDuration;
    Color barColor;
    if (fraction > 0.5) {
      barColor = AppColors.emerald;
    } else if (fraction > 0.25) {
      barColor = AppColors.starGold;
    } else {
      barColor = AppColors.error;
    }

    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          const Icon(Icons.star_rounded, color: AppColors.starGold, size: 18),
          const SizedBox(width: 4),
          Text(
            '$_score',
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLives() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final alive = i < _lives;
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(
            alive ? Icons.favorite : Icons.favorite_border,
            color: alive
                ? AppColors.error
                : AppColors.error.withValues(alpha: 0.3),
            size: 20,
          ),
        );
      }),
    );
  }

  Widget _buildComboIndicator() {
    final glowColor = _comboMultiplier >= 3
        ? AppColors.starGold
        : AppColors.electricBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department,
              color: glowColor, size: 16),
          const SizedBox(width: 3),
          Text(
            '${_comboMultiplier}x',
            style: AppFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: glowColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetWordBubble() {
    if (!_gameStarted || _targetWord.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A3A5C).withValues(alpha: 0.9),
            const Color(0xFF0F2840).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF60C0FF).withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF40A0FF).withValues(alpha: 0.3),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Text(
        _targetWord,
        style: AppFonts.fredoka(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 2,
          shadows: [
            Shadow(
              color: const Color(0xFF80D0FF).withValues(alpha: 0.7),
              blurRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  // ── Get Ready overlay ──────────────────────────────────────────────────

  Widget _buildGetReady(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Text(
          'Get Ready!',
          style: AppFonts.fredoka(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF60C0FF),
            shadows: [
              Shadow(
                color: const Color(0xFF40A0FF).withValues(alpha: 0.6),
                blurRadius: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Game Over overlay ──────────────────────────────────────────────────

  Widget _buildGameOver(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.electricBlue.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.electricBlue.withValues(alpha: 0.15),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _lives <= 0 ? 'Out of Lives!' : "Time's Up!",
                style: AppFonts.fredoka(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 20),
              // Score
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.starGold, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    '$_score',
                    style: AppFonts.fredoka(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: AppColors.starGold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Great job, ${widget.playerName}!',
                style: AppFonts.nunito(
                  fontSize: 16,
                  color: AppColors.secondaryText,
                ),
              ),
              if (_bestCombo > 1) ...[
                const SizedBox(height: 6),
                Text(
                  'Best Combo: ${_bestCombo}x',
                  style: AppFonts.nunito(
                    fontSize: 14,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Play again
                  ElevatedButton(
                    onPressed: _restartGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.electricBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Play Again',
                      style: AppFonts.fredoka(
                          fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Back
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: BorderSide(
                          color:
                              AppColors.secondaryText.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: AppFonts.fredoka(
                          fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restartGame() {
    setState(() {
      _score = 0;
      _lives = 3;
      _combo = 0;
      _comboMultiplier = 1;
      _bestCombo = 0;
      _secondsLeft = _gameDuration;
      _bubbles.clear();
      _popEffects.clear();
      _spawnAccumulator = 0;
      _waterCurrentTime = 0;
      _waterCurrentPhase = 0;
      _gameOver = false;
      _lastFrameTime = DateTime.now();
      // Reset fish to calm state
      for (final fish in _fishList) {
        fish.scatterTimer = 0;
      }
    });
    _pickNewTarget();
    _startCountdown();
    _loopController.forward();
  }
}

// ===========================================================================
// Data models
// ===========================================================================

class _Bubble {
  final int id;
  final String word;
  bool isTarget;
  double x; // 0..1 normalized
  double y; // 0..1 normalized (1 = bottom, 0 = top)
  final double radius;
  double displayRadius; // radius + oscillation
  final double speed; // units per second (in normalized coords)
  final double wobbleSpeed;
  final double wobbleAmount;
  final double wobblePhase;
  final double hueOffset;
  double age;

  _Bubble({
    required this.id,
    required this.word,
    required this.isTarget,
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.wobbleSpeed,
    required this.wobbleAmount,
    required this.wobblePhase,
    required this.hueOffset,
    required this.age,
    double? displayRadius,
  }) : displayRadius = displayRadius ?? radius;
}

class _PopEffect {
  final double x; // normalized
  final double y; // normalized
  final bool isCorrect;
  final List<_Droplet> droplets;
  final int rippleCount;
  double age;

  _PopEffect({
    required this.x,
    required this.y,
    required this.isCorrect,
    required this.droplets,
    required this.age,
    this.rippleCount = 2,
  });
}

class _Droplet {
  double x;
  double y;
  double vx;
  double vy;
  final double size;

  _Droplet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
  });
}

class _Particle {
  double x;
  double y;
  final double size;
  final double speedX;
  final double speedY;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
  });
}

class _LightRay {
  final double x; // 0..1
  final double width; // 0..1
  final double opacity;
  final double angle;

  _LightRay({
    required this.x,
    required this.width,
    required this.opacity,
    required this.angle,
  });
}

class _Fish {
  double x; // 0..1
  double y; // 0..1
  double direction; // -1 or 1
  double speed;
  final int type; // 0=orange, 1=blue, 2=yellow, 3=green
  double tailPhase;
  double scatterTimer;
  double age;
  double turnTimer;
  double verticalOffset;

  _Fish({
    required this.x,
    required this.y,
    required this.direction,
    required this.speed,
    required this.type,
    required this.tailPhase,
    required this.scatterTimer,
    required this.age,
    required this.turnTimer,
    required this.verticalOffset,
  });
}

class _AmbientBubble {
  double x;
  double y;
  double size;
  final double speed;
  final double wobblePhase;
  final double opacity;

  _AmbientBubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.wobblePhase,
    required this.opacity,
  });
}

// ===========================================================================
// Bubble Painter — iridescent sheen with highlight
// ===========================================================================

class _BubblePainter extends CustomPainter {
  final double hueOffset;
  final double age;

  _BubblePainter({required this.hueOffset, required this.age});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Animated hue shift for iridescence
    final hueShift = hueOffset + age * 20;

    // Base bubble fill — translucent with iridescent sweep gradient
    final baseColor1 = HSLColor.fromAHSL(
            0.35, (hueShift + 190) % 360, 0.6, 0.65)
        .toColor();
    final baseColor2 = HSLColor.fromAHSL(
            0.3, (hueShift + 290) % 360, 0.5, 0.7)
        .toColor();
    final baseColor3 = HSLColor.fromAHSL(
            0.25, (hueShift + 140) % 360, 0.55, 0.6)
        .toColor();

    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: pi * 2,
      colors: [baseColor1, baseColor2, baseColor3, baseColor1],
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    final basePaint = Paint()
      ..shader = sweepGradient
          .createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // Rim/edge highlight — a thin bright ring
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(center, radius - 1, rimPaint);

    // Inner radial gradient for depth (darker center, lighter edges)
    final depthGradient = RadialGradient(
      center: const Alignment(-0.2, -0.2),
      radius: 1.0,
      colors: [
        Colors.white.withValues(alpha: 0.08),
        Colors.transparent,
        Colors.black.withValues(alpha: 0.1),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final depthPaint = Paint()
      ..shader = depthGradient
          .createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, depthPaint);

    // Highlight reflection (upper-left circle)
    final highlightCenter = Offset(
      center.dx - radius * 0.3,
      center.dy - radius * 0.3,
    );
    final highlightRadius = radius * 0.22;
    final highlightGradient = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: 0.7),
        Colors.white.withValues(alpha: 0.0),
      ],
    );
    final highlightPaint = Paint()
      ..shader = highlightGradient.createShader(
          Rect.fromCircle(center: highlightCenter, radius: highlightRadius));
    canvas.drawCircle(highlightCenter, highlightRadius, highlightPaint);

    // Secondary smaller highlight
    final highlight2Center = Offset(
      center.dx - radius * 0.15,
      center.dy - radius * 0.5,
    );
    final highlight2Radius = radius * 0.1;
    final highlight2Paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4);
    canvas.drawCircle(highlight2Center, highlight2Radius, highlight2Paint);

    // Outer glow
    final glowPaint = Paint()
      ..color = HSLColor.fromAHSL(
              0.08, (hueShift + 200) % 360, 0.7, 0.7)
          .toColor()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius + 4, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      (old.age - age).abs() > 0.05;
}

// ===========================================================================
// Pop Effect Painter
// ===========================================================================

class _PopEffectPainter extends CustomPainter {
  final List<_PopEffect> effects;
  final Size screenSize;
  final bool hintsEnabled;

  _PopEffectPainter({required this.effects, required this.screenSize, this.hintsEnabled = true});

  @override
  void paint(Canvas canvas, Size size) {
    for (final effect in effects) {
      final cx = effect.x * size.width;
      final cy = effect.y * size.height;
      final progress = (effect.age / 0.6).clamp(0.0, 1.0);
      final fadeOut = (1.0 - progress).clamp(0.0, 1.0);

      // Center flash
      if (progress < 0.3) {
        final flashAlpha = (1.0 - progress / 0.3) * 0.7;
        final flashRadius = 20 + progress * 60;
        final flashColor = (!hintsEnabled || effect.isCorrect)
            ? const Color(0xFF80E0FF)
            : const Color(0xFFFF6060);
        final flashPaint = Paint()
          ..color = flashColor.withValues(alpha: flashAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(Offset(cx, cy), flashRadius, flashPaint);
      }

      // Expanding ripple rings (multiple)
      final ringColor = (!hintsEnabled || effect.isCorrect)
          ? const Color(0xFF60C0FF)
          : const Color(0xFFFF4040);
      for (int r = 0; r < effect.rippleCount; r++) {
        final delay = r * 0.12;
        final ringTime = (effect.age - delay).clamp(0.0, 0.6);
        if (ringTime <= 0) continue;
        final ringProgress = (ringTime / 0.5).clamp(0.0, 1.0);
        if (ringProgress >= 1.0) continue;
        final ringRadius = 15 + ringProgress * 60;
        final ringAlpha = (1.0 - ringProgress) * 0.4;
        final ringPaint = Paint()
          ..color = ringColor.withValues(alpha: ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 - ringProgress * 1.5;
        canvas.drawCircle(Offset(cx, cy), ringRadius, ringPaint);
      }

      // Droplets
      final dropletColor = (!hintsEnabled || effect.isCorrect)
          ? const Color(0xFF80D0FF)
          : const Color(0xFFFF5050);
      for (final d in effect.droplets) {
        final dx = cx + d.x;
        final dy = cy + d.y;
        final dPaint = Paint()
          ..color = dropletColor.withValues(alpha: fadeOut * 0.8);
        canvas.drawCircle(Offset(dx, dy), d.size * fadeOut, dPaint);
      }

      // Sparkles for correct pops (hidden when hints disabled to avoid giving away answer)
      if (effect.isCorrect && progress < 0.5 && hintsEnabled) {
        final sparkleAlpha = (1.0 - progress / 0.5) * 0.9;
        final sparklePaint = Paint()
          ..color = Colors.white.withValues(alpha: sparkleAlpha);
        for (int i = 0; i < 6; i++) {
          final angle = (i / 6) * pi * 2 + progress * pi;
          final dist = 20 + progress * 80;
          final sx = cx + cos(angle) * dist;
          final sy = cy + sin(angle) * dist;
          _drawSparkle(canvas, Offset(sx, sy), 3 * (1 - progress), sparklePaint);
        }
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double size, Paint paint) {
    // 4-point star
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx + size * 0.3, center.dy);
    path.lineTo(center.dx, center.dy + size);
    path.lineTo(center.dx - size * 0.3, center.dy);
    path.close();
    path.moveTo(center.dx - size, center.dy);
    path.lineTo(center.dx, center.dy + size * 0.3);
    path.lineTo(center.dx + size, center.dy);
    path.lineTo(center.dx, center.dy - size * 0.3);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PopEffectPainter old) => true;
}

// ===========================================================================
// Light Ray Painter
// ===========================================================================

class _LightRayPainter extends CustomPainter {
  final List<_LightRay> rays;

  _LightRayPainter({required this.rays});

  @override
  void paint(Canvas canvas, Size size) {
    for (final ray in rays) {
      final x = ray.x * size.width;
      final w = ray.width * size.width;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF80C0FF).withValues(alpha: ray.opacity),
            const Color(0xFF80C0FF).withValues(alpha: ray.opacity * 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.save();
      canvas.translate(x, 0);
      canvas.skew(ray.angle, 0);

      final path = Path()
        ..moveTo(-w / 2, 0)
        ..lineTo(w / 2, 0)
        ..lineTo(w * 1.5, size.height)
        ..lineTo(-w * 1.5, size.height)
        ..close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LightRayPainter old) => false;
}

// ===========================================================================
// Particle Painter
// ===========================================================================

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = const Color(0xFF80C0DD).withValues(alpha: p.opacity);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}

// ===========================================================================
// Seaweed Painter
// ===========================================================================

class _SeaweedPainter extends CustomPainter {
  final double swayPhase;

  _SeaweedPainter({required this.swayPhase});

  @override
  void paint(Canvas canvas, Size size) {
    final positions = [
      (x: size.width * 0.03, height: 100.0, lean: 1.0),
      (x: size.width * 0.10, height: 70.0, lean: -0.7),
      (x: size.width * 0.07, height: 55.0, lean: 0.5),
      (x: size.width * 0.18, height: 45.0, lean: 0.8),
      (x: size.width * 0.40, height: 40.0, lean: -0.4),
      (x: size.width * 0.60, height: 35.0, lean: 0.6),
      (x: size.width * 0.82, height: 50.0, lean: -0.5),
      (x: size.width * 0.88, height: 90.0, lean: -1.0),
      (x: size.width * 0.93, height: 65.0, lean: 0.8),
      (x: size.width * 0.97, height: 80.0, lean: -0.6),
    ];

    for (final pos in positions) {
      _drawSeaweedStrand(
        canvas,
        Offset(pos.x, size.height),
        pos.height,
        pos.lean,
        swayPhase,
      );
    }
  }

  void _drawSeaweedStrand(
    Canvas canvas,
    Offset base,
    double height,
    double lean,
    double phase,
  ) {
    final sway = sin(phase * pi * 2 + lean) * 8;

    final paint = Paint()
      ..color = const Color(0xFF0A4030).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(base.dx, base.dy);
    final cp1 = Offset(
      base.dx + lean * 10 + sway * 0.5,
      base.dy - height * 0.4,
    );
    final cp2 = Offset(
      base.dx + lean * 15 + sway,
      base.dy - height * 0.7,
    );
    final end = Offset(
      base.dx + lean * 8 + sway * 1.3,
      base.dy - height,
    );
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);

    // Lighter inner stroke
    final innerPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _SeaweedPainter old) =>
      old.swayPhase != swayPhase;
}

// ===========================================================================
// Fish Painter — draws decorative swimming fish
// ===========================================================================

class _FishPainter extends CustomPainter {
  final List<_Fish> fish;

  _FishPainter({required this.fish});

  static const _fishColors = [
    // type 0: orange clownfish
    (body: Color(0xFFFF8C42), stripe: Color(0xFFFFFFFF), fin: Color(0xFFFF6B1A)),
    // type 1: blue tang
    (body: Color(0xFF2196F3), stripe: Color(0xFF0D47A1), fin: Color(0xFF64B5F6)),
    // type 2: yellow butterfly fish
    (body: Color(0xFFFFD54F), stripe: Color(0xFFF57F17), fin: Color(0xFFFFECB3)),
    // type 3: green puffer
    (body: Color(0xFF66BB6A), stripe: Color(0xFF2E7D32), fin: Color(0xFFA5D6A7)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fish) {
      final cx = f.x * size.width;
      final cy = f.y * size.height;
      final colors = _fishColors[f.type % _fishColors.length];
      final fishSize = 14.0 + (f.type % 2) * 4.0;
      final dir = f.direction;

      canvas.save();
      canvas.translate(cx, cy);
      if (dir < 0) {
        canvas.scale(-1, 1);
      }

      // Tail (flapping triangle)
      final tailFlap = sin(f.tailPhase) * 5;
      final tailPath = Path()
        ..moveTo(-fishSize * 0.8, 0)
        ..lineTo(-fishSize * 1.4, -fishSize * 0.35 + tailFlap)
        ..lineTo(-fishSize * 1.4, fishSize * 0.35 + tailFlap)
        ..close();
      canvas.drawPath(
        tailPath,
        Paint()..color = colors.fin.withValues(alpha: 0.8),
      );

      // Body (ellipse)
      final bodyRect = Rect.fromCenter(
        center: Offset.zero,
        width: fishSize * 1.6,
        height: fishSize * 0.9,
      );
      canvas.drawOval(
        bodyRect,
        Paint()..color = colors.body.withValues(alpha: 0.85),
      );

      // White stripe (clownfish style) for type 0
      if (f.type == 0) {
        final stripePaint = Paint()
          ..color = colors.stripe.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(fishSize * 0.1, -fishSize * 0.4),
          Offset(fishSize * 0.1, fishSize * 0.4),
          stripePaint,
        );
      }

      // Dorsal fin
      final finPath = Path()
        ..moveTo(-fishSize * 0.2, -fishSize * 0.4)
        ..quadraticBezierTo(
          fishSize * 0.1,
          -fishSize * 0.75,
          fishSize * 0.4,
          -fishSize * 0.35,
        );
      canvas.drawPath(
        finPath,
        Paint()
          ..color = colors.fin.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );

      // Eye
      canvas.drawCircle(
        Offset(fishSize * 0.45, -fishSize * 0.08),
        fishSize * 0.12,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        Offset(fishSize * 0.48, -fishSize * 0.08),
        fishSize * 0.06,
        Paint()..color = Colors.black.withValues(alpha: 0.8),
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FishPainter old) => true;
}

// ===========================================================================
// Sandy Bottom Painter — seabed with rocks and shells
// ===========================================================================

class _SandyBottomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bottomY = size.height;

    // Sandy gradient at the bottom
    final sandGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        const Color(0xFF1A1510).withValues(alpha: 0.4),
        const Color(0xFF2A2015).withValues(alpha: 0.7),
        const Color(0xFF3A2E1A).withValues(alpha: 0.85),
      ],
      stops: const [0.0, 0.3, 0.6, 1.0],
    );

    final sandRect = Rect.fromLTWH(0, bottomY - 60, size.width, 60);
    canvas.drawRect(
      sandRect,
      Paint()..shader = sandGradient.createShader(sandRect),
    );

    // Small rocks
    final rng = Random(42); // fixed seed for consistent rocks
    const rockColor = Color(0xFF3D3525);
    for (int i = 0; i < 8; i++) {
      final rx = rng.nextDouble() * size.width;
      final ry = bottomY - 8 - rng.nextDouble() * 20;
      final rw = 6 + rng.nextDouble() * 12;
      final rh = 4 + rng.nextDouble() * 6;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rx, ry), width: rw, height: rh),
        Paint()..color = rockColor.withValues(alpha: 0.5 + rng.nextDouble() * 0.3),
      );
    }

    // Small shells (simple spiral-like circles)
    for (int i = 0; i < 4; i++) {
      final sx = size.width * 0.15 + rng.nextDouble() * size.width * 0.7;
      final sy = bottomY - 6 - rng.nextDouble() * 12;
      final shellSize = 3 + rng.nextDouble() * 4;
      final shellColor = Color.lerp(
        const Color(0xFFD4C5A9),
        const Color(0xFFAA9070),
        rng.nextDouble(),
      )!;
      canvas.drawCircle(
        Offset(sx, sy),
        shellSize,
        Paint()..color = shellColor.withValues(alpha: 0.4),
      );
      // Inner spiral hint
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(sx, sy),
            width: shellSize * 1.2,
            height: shellSize * 1.2),
        0,
        pi * 1.3,
        false,
        Paint()
          ..color = shellColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SandyBottomPainter old) => false;
}

// ===========================================================================
// Ambient Bubble Painter — small rising bubble streams
// ===========================================================================

class _AmbientBubblePainter extends CustomPainter {
  final List<_AmbientBubble> bubbles;

  _AmbientBubblePainter({required this.bubbles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      final bx = b.x * size.width;
      final by = b.y * size.height;
      final paint = Paint()
        ..color = const Color(0xFF80D0FF).withValues(alpha: b.opacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(Offset(bx, by), b.size, paint);

      // Tiny highlight on ambient bubble
      final hlPaint = Paint()
        ..color = Colors.white.withValues(alpha: b.opacity * 0.3);
      canvas.drawCircle(
        Offset(bx - b.size * 0.25, by - b.size * 0.25),
        b.size * 0.25,
        hlPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientBubblePainter old) => true;
}

// ===========================================================================
// Caustics Painter — subtle light pattern overlay at the top
// ===========================================================================

class _CausticsPainter extends CustomPainter {
  final double time;

  _CausticsPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle caustic-like light patches at the top ~20% of screen
    final causticHeight = size.height * 0.2;
    final rng = Random(17); // fixed seed for consistent pattern

    for (int i = 0; i < 12; i++) {
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * causticHeight;
      final drift = sin(time * 0.5 + i * 1.7) * 15;
      final cx = baseX + drift;
      final cy = baseY + cos(time * 0.3 + i * 2.3) * 8;
      final radius = 20 + rng.nextDouble() * 40;
      final alpha = 0.02 + sin(time * 0.8 + i * 1.1).abs() * 0.03;

      final gradient = RadialGradient(
        colors: [
          const Color(0xFF60D0FF).withValues(alpha: alpha),
          Colors.transparent,
        ],
      );
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = gradient.createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: radius)),
      );
    }

    // Very subtle blue-green color overlay that shifts slowly
    final overlayAlpha = 0.015 + sin(time * 0.2).abs() * 0.01;
    final overlayColor = Color.lerp(
      const Color(0xFF0088AA),
      const Color(0xFF006644),
      (sin(time * 0.15) + 1) / 2,
    )!;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, causticHeight),
      Paint()..color = overlayColor.withValues(alpha: overlayAlpha),
    );
  }

  @override
  bool shouldRepaint(covariant _CausticsPainter old) =>
      (old.time - time).abs() > 0.05;
}

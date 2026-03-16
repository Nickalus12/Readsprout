import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Bubble Pop Zoo — Pop bubbles to free cute animals!
// A delightful mini game for young children (ages 3-5).
// ---------------------------------------------------------------------------

/// Animal data: emoji, word (must have audio), and a fun color.
class _AnimalData {
  final String emoji;
  final String word;
  final Color bubbleColor;

  const _AnimalData(this.emoji, this.word, this.bubbleColor);
}

const _animals = [
  _AnimalData('🐶', 'dog', Color(0xFF64B5F6)),
  _AnimalData('🐱', 'cat', Color(0xFFFFB74D)),
  _AnimalData('🐸', 'frog', Color(0xFF81C784)),
  _AnimalData('🐻', 'bear', Color(0xFFA1887F)),
  _AnimalData('🐟', 'fish', Color(0xFF4FC3F7)),
  _AnimalData('🐦', 'bird', Color(0xFFE57373)),
  _AnimalData('🐷', 'pig', Color(0xFFF48FB1)),
  _AnimalData('🐔', 'hen', Color(0xFFFFD54F)),
  _AnimalData('🦇', 'bat', Color(0xFFB39DDB)),
  _AnimalData('🐛', 'bug', Color(0xFFA5D6A7)),
];

class BubblePopZooGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;

  const BubblePopZooGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
  });

  @override
  State<BubblePopZooGame> createState() => _BubblePopZooGameState();
}

class _BubblePopZooGameState extends State<BubblePopZooGame>
    with TickerProviderStateMixin {
  final _rng = Random();
  final List<_Bubble> _bubbles = [];
  final List<_PopEffect> _popEffects = [];
  final List<_FreedAnimal> _freedAnimals = [];
  final List<_BackgroundBubble> _bgBubbles = [];

  late AnimationController _ticker;
  double _lastTime = 0;
  double _spawnTimer = 0;
  double _gameTime = 0;
  static const _gameDuration = 60.0;

  int _score = 0;
  int _combo = 0;
  double _comboTimer = 0;
  int _bestCombo = 0;
  bool _gameStarted = false;
  bool _gameOver = false;
  bool _showCountdown = true;
  int _countdownValue = 3;
  int _nextBubbleId = 0;

  // Wave system: introduce new animals over time
  int _waveIndex = 0;
  int _animalsInWave = 0;
  static const _waveSize = 8;

  // Animals available in current wave
  List<_AnimalData> _availableAnimals = [];

  @override
  void initState() {
    super.initState();
    _initBackgroundBubbles();
    _availableAnimals = [_animals[0], _animals[1]]; // Start with dog & cat
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..addListener(_onTick);

    // Start countdown
    _startCountdown();
  }

  void _initBackgroundBubbles() {
    for (int i = 0; i < 15; i++) {
      _bgBubbles.add(_BackgroundBubble(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 2 + _rng.nextDouble() * 6,
        speed: 0.01 + _rng.nextDouble() * 0.03,
        wobblePhase: _rng.nextDouble() * pi * 2,
        opacity: 0.1 + _rng.nextDouble() * 0.2,
      ));
    }
  }

  void _startCountdown() {
    _countdownValue = 3;
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownValue--;
        if (_countdownValue <= 0) {
          timer.cancel();
          _showCountdown = false;
          _gameStarted = true;
          _ticker.forward();
          _lastTime = 0;
        }
      });
    });
  }

  void _onTick() {
    final elapsed = _ticker.lastElapsedDuration?.inMicroseconds ?? 0;
    final currentTime = elapsed / 1000000.0;
    final dt = (currentTime - _lastTime).clamp(0.0, 0.05);
    _lastTime = currentTime;

    if (!_gameStarted || _gameOver) return;

    setState(() {
      _gameTime += dt;

      // Check game over
      if (_gameTime >= _gameDuration) {
        _gameOver = true;
        return;
      }

      // Update combo timer
      if (_combo > 0) {
        _comboTimer -= dt;
        if (_comboTimer <= 0) {
          _combo = 0;
        }
      }

      // Spawn bubbles
      _spawnTimer += dt;
      final spawnInterval = _bubbles.length < 3 ? 0.8 : 1.5;
      if (_spawnTimer >= spawnInterval && _bubbles.length < 6) {
        _spawnTimer = 0;
        _spawnBubble();
      }

      // Update bubbles
      _updateBubbles(dt);

      // Update pop effects
      _updatePopEffects(dt);

      // Update freed animals
      _updateFreedAnimals(dt);

      // Update background
      _updateBackgroundBubbles(dt);
    });
  }

  void _spawnBubble() {
    // Wave progression: add new animal every _waveSize pops
    if (_waveIndex < _animals.length - 2) {
      // Check if wave is complete
      if (_animalsInWave >= _waveSize) {
        _waveIndex++;
        _animalsInWave = 0;
        if (_waveIndex + 2 <= _animals.length) {
          _availableAnimals = _animals.sublist(0, _waveIndex + 2);
        }
      }
    }

    final animal = _availableAnimals[_rng.nextInt(_availableAnimals.length)];
    final radius = 38.0 + _rng.nextDouble() * 16.0;
    final speed = 0.06 + _rng.nextDouble() * 0.04;

    // Find non-overlapping x position
    double x = 0.15 + _rng.nextDouble() * 0.7;
    for (int attempt = 0; attempt < 10; attempt++) {
      bool overlaps = false;
      for (final b in _bubbles) {
        if ((b.x - x).abs() < 0.18) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) break;
      x = 0.15 + _rng.nextDouble() * 0.7;
    }

    _bubbles.add(_Bubble(
      id: _nextBubbleId++,
      animal: animal,
      x: x,
      y: 1.15,
      radius: radius,
      speed: speed,
      wobblePhase: _rng.nextDouble() * pi * 2,
      wobbleSpeed: 0.8 + _rng.nextDouble() * 0.6,
      shimmerPhase: _rng.nextDouble() * pi * 2,
      scale: 0.0,
    ));
  }

  void _updateBubbles(double dt) {
    for (final b in _bubbles) {
      b.y -= b.speed * dt;
      b.x += sin(b.wobblePhase + b.y * 6) * 0.003;
      b.wobblePhase += b.wobbleSpeed * dt;
      b.shimmerPhase += dt * 2;
      // Scale in animation
      if (b.scale < 1.0) {
        b.scale = (b.scale + dt * 4).clamp(0.0, 1.0);
      }
    }
    // Remove bubbles that float off screen (no penalty — this is a kids game!)
    _bubbles.removeWhere((b) => b.y < -0.15);
  }

  void _updatePopEffects(double dt) {
    for (final e in _popEffects) {
      e.age += dt;
      for (final p in e.particles) {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 120 * dt; // gravity
      }
    }
    _popEffects.removeWhere((e) => e.age > 0.8);
  }

  void _updateFreedAnimals(double dt) {
    for (final a in _freedAnimals) {
      a.age += dt;
      // Float upward and wobble
      a.y -= 0.12 * dt;
      a.x += sin(a.age * 4) * 0.002;
      a.rotation += a.spinSpeed * dt;
    }
    _freedAnimals.removeWhere((a) => a.age > 2.0);
  }

  void _updateBackgroundBubbles(double dt) {
    for (final b in _bgBubbles) {
      b.y -= b.speed * dt;
      b.x += sin(b.wobblePhase + b.y * 8) * 0.001;
      if (b.y < -0.05) {
        b.y = 1.05;
        b.x = _rng.nextDouble();
      }
    }
  }

  void _onTapDown(TapDownDetails details, Size size) {
    if (_gameOver || !_gameStarted) return;

    final tapX = details.localPosition.dx / size.width;
    final tapY = details.localPosition.dy / size.height;

    // Find closest bubble within tap radius
    _Bubble? tapped;
    double bestDist = double.infinity;

    for (final b in _bubbles) {
      final dx = tapX - b.x;
      final dy = tapY - b.y;
      final dist = sqrt(dx * dx + dy * dy);
      final hitRadius = (b.radius * b.scale) / min(size.width, size.height) * 1.4;

      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        tapped = b;
      }
    }

    if (tapped != null) {
      _popBubble(tapped, size);
    }
  }

  void _popBubble(_Bubble bubble, Size size) {
    Haptics.correct();

    // Score
    _combo++;
    _comboTimer = 1.5;
    if (_combo > _bestCombo) _bestCombo = _combo;
    final points = _combo >= 3 ? 3 : (_combo >= 2 ? 2 : 1);
    _score += points;
    _animalsInWave++;

    // Play the animal's word
    widget.audioService.playWord(bubble.animal.word);

    // Create pop effect
    final particles = <_PopParticle>[];
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * pi * 2 + _rng.nextDouble() * 0.3;
      final speed = 80 + _rng.nextDouble() * 120;
      particles.add(_PopParticle(
        x: bubble.x * size.width,
        y: bubble.y * size.height,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40,
        color: bubble.animal.bubbleColor,
        size: 3 + _rng.nextDouble() * 4,
      ));
    }

    // Add sparkles for combos
    if (_combo >= 2) {
      for (int i = 0; i < 8; i++) {
        final angle = _rng.nextDouble() * pi * 2;
        final speed = 60 + _rng.nextDouble() * 100;
        particles.add(_PopParticle(
          x: bubble.x * size.width,
          y: bubble.y * size.height,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed - 30,
          color: AppColors.starGold,
          size: 2 + _rng.nextDouble() * 3,
        ));
      }
    }

    _popEffects.add(_PopEffect(particles: particles));

    // Create freed animal animation
    _freedAnimals.add(_FreedAnimal(
      emoji: bubble.animal.emoji,
      word: bubble.animal.word,
      x: bubble.x,
      y: bubble.y,
      spinSpeed: (_rng.nextDouble() - 0.5) * 3,
      startSize: bubble.radius * 2,
    ));

    // Play success sound for combos
    if (_combo >= 3) {
      widget.audioService.playSuccess();
    }

    _bubbles.remove(bubble);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0A2E),
                  Color(0xFF1A0A3E),
                  Color(0xFF0A1A2E),
                ],
              ),
            ),
          ),

          // Game canvas
          if (!_gameOver)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapDown: (d) => _onTapDown(d, size),
                  child: CustomPaint(
                    painter: _BubblePopZooPainter(
                      bubbles: _bubbles,
                      popEffects: _popEffects,
                      freedAnimals: _freedAnimals,
                      bgBubbles: _bgBubbles,
                      gameTime: _gameTime,
                    ),
                    size: size,
                  ),
                );
              },
            ),

          // HUD — timer and score
          if (_gameStarted && !_gameOver)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.primaryText,
                      iconSize: 28,
                    ),
                    // Timer
                    _TimerPill(
                      secondsLeft: (_gameDuration - _gameTime).ceil().clamp(0, 60),
                    ),
                    // Score
                    _ScorePill(score: _score, combo: _combo),
                  ],
                ),
              ),
            ),

          // Combo indicator
          if (_combo >= 2 && !_gameOver)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 0,
              right: 0,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_combo),
                  tween: Tween(begin: 1.5, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.starGold.withValues(alpha: 0.8),
                          AppColors.magenta.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.starGold.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Text(
                      '${_combo}x COMBO!',
                      style: AppFonts.fredoka(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Freed animal word display
          for (final animal in _freedAnimals)
            if (animal.age < 1.2)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height * animal.y - 60,
                child: Center(
                  child: Opacity(
                    opacity: (1.0 - animal.age / 1.2).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -animal.age * 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            animal.emoji,
                            style: TextStyle(
                              fontSize: 40 + (animal.age * 10),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.electricBlue.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              animal.word.toUpperCase(),
                              style: AppFonts.fredoka(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

          // Countdown overlay
          if (_showCountdown)
            Container(
              color: AppColors.background.withValues(alpha: 0.8),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_countdownValue),
                  tween: Tween(begin: 2.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🫧',
                        style: const TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _countdownValue > 0 ? '$_countdownValue' : 'POP!',
                        style: AppFonts.fredoka(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: AppColors.electricBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bubble Pop Zoo',
                        style: AppFonts.fredoka(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Game over screen
          if (_gameOver) _buildGameOver(),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    return Container(
      color: AppColors.background.withValues(alpha: 0.9),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animals freed header
              Text(
                '🎉',
                style: const TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 12),
              Text(
                'Great job, ${widget.playerName}!',
                style: AppFonts.fredoka(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 24),

              // Score card
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.electricBlue.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.1),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Animals Freed',
                      style: AppFonts.fredoka(
                        fontSize: 16,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_score',
                      style: AppFonts.fredoka(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: AppColors.starGold,
                      ),
                    ),
                    if (_bestCombo >= 3) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.starGold.withValues(alpha: 0.3),
                              AppColors.magenta.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Best Combo: ${_bestCombo}x',
                          style: AppFonts.fredoka(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.starGold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Play again button
              GestureDetector(
                onTap: _playAgain,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.electricBlue,
                        AppColors.cyan,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    'Play Again!',
                    style: AppFonts.fredoka(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Back button
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Back to Games',
                  style: AppFonts.fredoka(
                    fontSize: 16,
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

  void _playAgain() {
    setState(() {
      _bubbles.clear();
      _popEffects.clear();
      _freedAnimals.clear();
      _score = 0;
      _combo = 0;
      _comboTimer = 0;
      _bestCombo = 0;
      _gameTime = 0;
      _spawnTimer = 0;
      _gameOver = false;
      _gameStarted = false;
      _showCountdown = true;
      _waveIndex = 0;
      _animalsInWave = 0;
      _availableAnimals = [_animals[0], _animals[1]];
      _nextBubbleId = 0;
    });
    _ticker.reset();
    _lastTime = 0;
    _startCountdown();
  }
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class _Bubble {
  final int id;
  final _AnimalData animal;
  double x, y;
  final double radius;
  final double speed;
  double wobblePhase;
  final double wobbleSpeed;
  double shimmerPhase;
  double scale;

  _Bubble({
    required this.id,
    required this.animal,
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.wobblePhase,
    required this.wobbleSpeed,
    required this.shimmerPhase,
    this.scale = 0.0,
  });
}

class _PopEffect {
  final List<_PopParticle> particles;
  double age = 0;

  _PopEffect({required this.particles});
}

class _PopParticle {
  double x, y, vx, vy;
  final Color color;
  final double size;

  _PopParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
  });
}

class _FreedAnimal {
  final String emoji;
  final String word;
  double x, y;
  double age = 0;
  double rotation = 0;
  final double spinSpeed;
  final double startSize;

  _FreedAnimal({
    required this.emoji,
    required this.word,
    required this.x,
    required this.y,
    required this.spinSpeed,
    required this.startSize,
  });
}

class _BackgroundBubble {
  double x, y;
  final double size;
  final double speed;
  final double wobblePhase;
  final double opacity;

  _BackgroundBubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.wobblePhase,
    required this.opacity,
  });
}

// ---------------------------------------------------------------------------
// Custom painter — renders bubbles, pop effects, and background
// ---------------------------------------------------------------------------

class _BubblePopZooPainter extends CustomPainter {
  final List<_Bubble> bubbles;
  final List<_PopEffect> popEffects;
  final List<_FreedAnimal> freedAnimals;
  final List<_BackgroundBubble> bgBubbles;
  final double gameTime;

  _BubblePopZooPainter({
    required this.bubbles,
    required this.popEffects,
    required this.freedAnimals,
    required this.bgBubbles,
    required this.gameTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawBubbles(canvas, size);
    _drawPopEffects(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Ambient background bubbles
    for (final b in bgBubbles) {
      final paint = Paint()
        ..color = AppColors.electricBlue.withValues(alpha: b.opacity * 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(b.x * size.width, b.y * size.height),
        b.size,
        paint,
      );
    }
  }

  void _drawBubbles(Canvas canvas, Size size) {
    for (final b in bubbles) {
      final cx = b.x * size.width;
      final cy = b.y * size.height;
      final r = b.radius * b.scale;

      // Bubble outer glow
      canvas.drawCircle(
        Offset(cx, cy),
        r + 4,
        Paint()
          ..color = b.animal.bubbleColor.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // Bubble body — translucent with gradient
      final gradient = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 0.9,
        colors: [
          b.animal.bubbleColor.withValues(alpha: 0.35),
          b.animal.bubbleColor.withValues(alpha: 0.15),
          b.animal.bubbleColor.withValues(alpha: 0.08),
        ],
        stops: const [0.0, 0.6, 1.0],
      );
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = gradient.createShader(rect)
          ..style = PaintingStyle.fill,
      );

      // Bubble border (soap film look)
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = b.animal.bubbleColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Shimmer highlight — moves with time
      final shimmerAngle = b.shimmerPhase;
      final shimmerX = cx + cos(shimmerAngle) * r * 0.3 - r * 0.2;
      final shimmerY = cy + sin(shimmerAngle) * r * 0.2 - r * 0.3;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(shimmerX, shimmerY),
          width: r * 0.45,
          height: r * 0.25,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Animal emoji — drawn as text
      final emojiPainter = TextPainter(
        text: TextSpan(
          text: b.animal.emoji,
          style: TextStyle(fontSize: r * 0.7),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      emojiPainter.paint(
        canvas,
        Offset(cx - emojiPainter.width / 2, cy - emojiPainter.height / 2 - 2),
      );

      // Word label below emoji
      final wordPainter = TextPainter(
        text: TextSpan(
          text: b.animal.word,
          style: TextStyle(
            fontSize: r * 0.3,
            fontWeight: FontWeight.bold,
            color: Colors.white.withValues(alpha: 0.9),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      wordPainter.paint(
        canvas,
        Offset(cx - wordPainter.width / 2, cy + r * 0.2),
      );
    }
  }

  void _drawPopEffects(Canvas canvas, Size size) {
    for (final effect in popEffects) {
      final alpha = (1.0 - effect.age / 0.8).clamp(0.0, 1.0);
      for (final p in effect.particles) {
        final paint = Paint()
          ..color = p.color.withValues(alpha: alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.size * alpha,
          paint,
        );
        // Glow
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.size * alpha * 2,
          Paint()
            ..color = p.color.withValues(alpha: alpha * 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePopZooPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// HUD widgets
// ---------------------------------------------------------------------------

class _TimerPill extends StatelessWidget {
  final int secondsLeft;
  const _TimerPill({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: urgent
              ? AppColors.error.withValues(alpha: 0.6)
              : AppColors.electricBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            size: 18,
            color: urgent ? AppColors.error : AppColors.electricBlue,
          ),
          const SizedBox(width: 6),
          Text(
            '$secondsLeft',
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: urgent ? AppColors.error : AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final int score;
  final int combo;
  const _ScorePill({required this.score, required this.combo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.starGold.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🐾',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            '$score',
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.starGold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon painter for the mini games hub
// ---------------------------------------------------------------------------

class BubblePopZooIconPainter extends CustomPainter {
  const BubblePopZooIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Draw 3 bubbles
    final bubbleData = [
      (cx - 12.0, cy - 8.0, 14.0, const Color(0xFF64B5F6)),
      (cx + 10.0, cy - 4.0, 12.0, const Color(0xFFFFB74D)),
      (cx - 2.0, cy + 10.0, 10.0, const Color(0xFF81C784)),
    ];

    for (final (bx, by, r, color) in bubbleData) {
      // Bubble body
      canvas.drawCircle(
        Offset(bx, by),
        r,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill,
      );
      // Bubble border
      canvas.drawCircle(
        Offset(bx, by),
        r,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Shimmer
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx - r * 0.25, by - r * 0.3),
          width: r * 0.4,
          height: r * 0.2,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }

    // Draw tiny animal emojis inside
    final emojis = ['🐶', '🐱', '🐸'];
    final sizes = [10.0, 9.0, 8.0];
    for (int i = 0; i < 3; i++) {
      final (bx, by, _, _) = bubbleData[i];
      final tp = TextPainter(
        text: TextSpan(
          text: emojis[i],
          style: TextStyle(fontSize: sizes[i]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(bx - tp.width / 2, by - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

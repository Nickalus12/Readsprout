import 'dart:math';
import 'dart:ui' as ui;

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

// ─── Data models ───────────────────────────────────────────────────────────

class _WordBubble {
  String text;
  bool isCorrect;
  double x;
  double y;
  double speed;
  double wobblePhase;
  double opacity = 1.0;
  bool collected = false;
  double collectAnimProgress = 0.0;

  _WordBubble({
    required this.text,
    required this.isCorrect,
    required this.x,
    required this.y,
    required this.speed,
    required this.wobblePhase,
  });
}

class _Sparkle {
  double x, y;
  double vx, vy;
  double life;
  double maxLife;
  Color color;
  double size;

  _Sparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
    required this.size,
  }) : maxLife = life;
}

class _Star {
  double x, y;
  double size;
  double twinklePhase;
  double twinkleSpeed;
  double brightness;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.twinklePhase,
    required this.twinkleSpeed,
    required this.brightness,
  });
}

class _Cloud {
  double x, y;
  double width, height;
  double speed;
  double opacity;

  _Cloud({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.speed,
    required this.opacity,
  });
}

// ─── Main Widget ───────────────────────────────────────────────────────────

class UnicornFlightGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const UnicornFlightGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<UnicornFlightGame> createState() => _UnicornFlightGameState();
}

class _UnicornFlightGameState extends State<UnicornFlightGame>
    with TickerProviderStateMixin {
  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _hearts = 3;
  String _targetWord = '';
  double _gameSpeed = 1.0;

  // Unicorn position
  double _unicornY = 0.5; // 0..1 normalized
  double _unicornTargetY = 0.5;
  double _unicornVelocityY = 0.0;

  // Animation state
  double _wingAngle = 0.0;
  double _hornGlow = 0.0;
  double _stumbleTimer = 0.0;
  double _flashTimer = 0.0;
  double _totalTime = 0.0;

  // Game objects
  final List<_WordBubble> _bubbles = [];
  final List<_Sparkle> _sparkles = [];
  final List<_Sparkle> _trailSparkles = [];
  final List<_Star> _stars = [];
  final List<_Cloud> _clouds = [];

  // Word pool
  late List<String> _wordPool;
  final _rng = Random();

  // Timing
  double _bubbleSpawnTimer = 0.0;
  final double _bubbleSpawnInterval = 2.0;
  double _trailSpawnTimer = 0.0;

  // Ticker
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;

  // Layout
  static const double _unicornX = 0.15; // Fraction of screen width

  // Feedback text
  String _feedbackText = '';
  double _feedbackTimer = 0.0;
  Color _feedbackColor = AppColors.success;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _buildWordPool();
    _pickNewTarget();
    _initBackground();
  }

  void _buildWordPool() {
    final words = <String>{};
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        for (final w in DolchWords.wordsForLevel(level)) {
          words.add(w.text.toLowerCase());
        }
      }
    }
    if (words.length < 5) {
      // Fallback: use first two levels
      for (final w in DolchWords.wordsForLevel(1)) {
        words.add(w.text.toLowerCase());
      }
      for (final w in DolchWords.wordsForLevel(2)) {
        words.add(w.text.toLowerCase());
      }
    }
    _wordPool = words.toList()..shuffle(_rng);
  }

  void _initBackground() {
    // Stars
    for (int i = 0; i < 80; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: _rng.nextDouble() * 2.5 + 0.5,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: _rng.nextDouble() * 2 + 1,
        brightness: _rng.nextDouble() * 0.5 + 0.5,
      ));
    }
    // Clouds
    for (int i = 0; i < 6; i++) {
      _clouds.add(_Cloud(
        x: _rng.nextDouble() * 1.5,
        y: _rng.nextDouble() * 0.8 + 0.1,
        width: _rng.nextDouble() * 120 + 80,
        height: _rng.nextDouble() * 30 + 20,
        speed: _rng.nextDouble() * 20 + 10,
        opacity: _rng.nextDouble() * 0.15 + 0.05,
      ));
    }
  }

  void _pickNewTarget() {
    if (_wordPool.isEmpty) return;
    String newWord;
    do {
      newWord = _wordPool[_rng.nextInt(_wordPool.length)];
    } while (newWord == _targetWord && _wordPool.length > 1);
    _targetWord = newWord;
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('unicorn_flight', _score);
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

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _gameOver = false;
      _score = 0;
      _hearts = 3;
      _gameSpeed = 1.0;
      _bubbles.clear();
      _sparkles.clear();
      _trailSparkles.clear();
      _unicornY = 0.5;
      _unicornTargetY = 0.5;
      _stumbleTimer = 0.0;
      _flashTimer = 0.0;
      _bubbleSpawnTimer = 0.0;
      _feedbackText = '';
      _feedbackTimer = 0.0;
      _pickNewTarget();
    });

    _lastTickTime = Duration.zero;
    _ticker?.dispose();
    _ticker = createTicker(_onTick);
    _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }
    final dt = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
    _lastTickTime = elapsed;

    // Cap delta to prevent jumps
    final cappedDt = dt.clamp(0.0, 0.05);

    if (!_gameOver) {
      _updateGame(cappedDt);
    }

    setState(() {});
  }

  void _updateGame(double dt) {
    _totalTime += dt;

    // Increase game speed over time
    _gameSpeed = 1.0 + (_score * 0.03).clamp(0.0, 1.5);

    // Wing flap animation
    _wingAngle = sin(_totalTime * 6) * 0.4;

    // Horn glow pulse
    _hornGlow = (sin(_totalTime * 3) + 1) / 2;

    // Unicorn physics — smooth follow with spring
    final diff = _unicornTargetY - _unicornY;
    _unicornVelocityY += diff * 8.0 * dt;
    _unicornVelocityY *= 0.9; // damping
    _unicornY += _unicornVelocityY;
    _unicornY = _unicornY.clamp(0.05, 0.95);

    // Stumble timer
    if (_stumbleTimer > 0) {
      _stumbleTimer -= dt;
    }

    // Flash timer
    if (_flashTimer > 0) {
      _flashTimer -= dt;
    }

    // Feedback timer
    if (_feedbackTimer > 0) {
      _feedbackTimer -= dt;
    }

    // Spawn bubbles
    _bubbleSpawnTimer += dt;
    if (_bubbleSpawnTimer >= _bubbleSpawnInterval / _gameSpeed) {
      _bubbleSpawnTimer = 0;
      _spawnBubble();
    }

    // Update bubbles
    _updateBubbles(dt);

    // Check collisions
    _checkCollisions();

    // Update sparkles
    _updateSparkles(dt);

    // Spawn trail sparkles
    _trailSpawnTimer += dt;
    if (_trailSpawnTimer >= 0.05) {
      _trailSpawnTimer = 0;
      _spawnTrailSparkle();
    }

    // Update background
    _updateBackground(dt);
  }

  void _spawnBubble() {
    // Decide type: ~40% correct, ~30% misspelled, ~30% random other word
    final roll = _rng.nextDouble();
    String text;
    bool isCorrect;

    if (roll < 0.4) {
      text = _targetWord;
      isCorrect = true;
    } else if (roll < 0.7) {
      text = _generateMisspelling(_targetWord);
      isCorrect = false;
    } else {
      // Random other word
      String other;
      do {
        other = _wordPool[_rng.nextInt(_wordPool.length)];
      } while (other == _targetWord && _wordPool.length > 1);
      text = other;
      isCorrect = false;
    }

    _bubbles.add(_WordBubble(
      text: text,
      isCorrect: isCorrect,
      x: 1.1,
      y: _rng.nextDouble() * 0.7 + 0.15,
      speed: (80 + _rng.nextDouble() * 40) * _gameSpeed,
      wobblePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  String _generateMisspelling(String word) {
    if (word.length < 2) return '${word}z';

    final methods = <String Function()>[
      // Swap two adjacent letters
      () {
        if (word.length < 2) return word;
        final i = _rng.nextInt(word.length - 1);
        final chars = word.split('');
        final tmp = chars[i];
        chars[i] = chars[i + 1];
        chars[i + 1] = tmp;
        final result = chars.join();
        return result == word ? '${word}e' : result;
      },
      // Double a letter
      () {
        final i = _rng.nextInt(word.length);
        return word.substring(0, i) + word[i] + word.substring(i);
      },
      // Remove a letter (only if word > 2 chars)
      () {
        if (word.length <= 2) return '${word}s';
        final i = _rng.nextInt(word.length);
        return word.substring(0, i) + word.substring(i + 1);
      },
      // Common letter substitution
      () {
        const swaps = {
          'b': 'd',
          'd': 'b',
          'm': 'n',
          'n': 'm',
          'p': 'q',
          'q': 'p',
          'a': 'e',
          'e': 'a',
          'i': 'y',
          'y': 'i',
          'u': 'o',
          'o': 'u',
        };
        for (int i = 0; i < word.length; i++) {
          final swap = swaps[word[i]];
          if (swap != null) {
            return word.substring(0, i) + swap + word.substring(i + 1);
          }
        }
        // No substitution found, add a letter
        return '${word}r';
      },
    ];

    final result = methods[_rng.nextInt(methods.length)]();
    // Make sure it's actually different
    return result == word ? '${word}e' : result;
  }

  void _updateBubbles(double dt) {
    for (final bubble in _bubbles) {
      if (bubble.collected) {
        bubble.collectAnimProgress += dt * 3;
        bubble.opacity = (1.0 - bubble.collectAnimProgress).clamp(0.0, 1.0);
        bubble.y -= dt * 100; // Float up
      } else {
        bubble.x -= (bubble.speed * dt) / 800; // Normalize by screen width
        bubble.y += sin(_totalTime * 2 + bubble.wobblePhase) * dt * 0.02;
      }
    }
    _bubbles.removeWhere(
        (b) => b.x < -0.2 || b.collectAnimProgress > 1.0);
  }

  void _checkCollisions() {
    final unicornCenterY = _unicornY;
    const collisionRadius = 0.07;

    for (final bubble in _bubbles) {
      if (bubble.collected) continue;

      final dx = bubble.x - _unicornX;
      final dy = bubble.y - unicornCenterY;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < collisionRadius) {
        bubble.collected = true;

        if (bubble.isCorrect) {
          _onCorrectHit(bubble);
        } else {
          _onWrongHit(bubble);
        }
      }
    }
  }

  void _onCorrectHit(_WordBubble bubble) {
    _score++;
    _feedbackText = 'Great job!';
    _feedbackColor = AppColors.starGold;
    _feedbackTimer = 1.5;

    // Say the word aloud
    widget.audioService.playWord(bubble.text);

    // Spawn golden sparkle burst
    for (int i = 0; i < 20; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = _rng.nextDouble() * 200 + 50;
      _sparkles.add(_Sparkle(
        x: bubble.x,
        y: bubble.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: _rng.nextDouble() * 0.8 + 0.4,
        color: [
          AppColors.starGold,
          const Color(0xFFFFE066),
          const Color(0xFFFFF9C4),
          AppColors.electricBlue,
        ][_rng.nextInt(4)],
        size: _rng.nextDouble() * 4 + 2,
      ));
    }

    widget.audioService.playSuccess();
    Haptics.success();
    _pickNewTarget();
  }

  void _onWrongHit(_WordBubble bubble) {
    _hearts--;
    _stumbleTimer = 0.6;
    _flashTimer = 0.3;
    _feedbackText = 'Oops! Try again!';
    _feedbackColor = AppColors.error;
    _feedbackTimer = 1.5;

    // Red sparkle burst
    for (int i = 0; i < 12; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = _rng.nextDouble() * 150 + 30;
      _sparkles.add(_Sparkle(
        x: bubble.x,
        y: bubble.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: _rng.nextDouble() * 0.5 + 0.3,
        color: [
          AppColors.error,
          const Color(0xFFFF6B6B),
          const Color(0xFFFF8A8A),
        ][_rng.nextInt(3)],
        size: _rng.nextDouble() * 3 + 2,
      ));
    }

    widget.audioService.playError();
    Haptics.wrong();

    if (_hearts <= 0) {
      _gameOver = true;
      _ticker?.stop();
      _awardMiniGameStickers();
    }
  }

  void _spawnTrailSparkle() {
    if (_gameOver) return;
    final colors = [
      const Color(0xFFFFB6C1), // Light pink
      const Color(0xFFE6E6FA), // Lavender
      const Color(0xFFADD8E6), // Light blue
      AppColors.starGold.withValues(alpha: 0.7),
      const Color(0xFFDDA0DD), // Plum
    ];
    _trailSparkles.add(_Sparkle(
      x: _unicornX - 0.02,
      y: _unicornY + (_rng.nextDouble() - 0.5) * 0.03,
      vx: -(_rng.nextDouble() * 30 + 10),
      vy: (_rng.nextDouble() - 0.5) * 20,
      life: _rng.nextDouble() * 0.6 + 0.3,
      color: colors[_rng.nextInt(colors.length)],
      size: _rng.nextDouble() * 3 + 1.5,
    ));
  }

  void _updateSparkles(double dt) {
    for (final s in _sparkles) {
      s.x += s.vx * dt / 800;
      s.y += s.vy * dt / 600;
      s.vy += 100 * dt / 600; // Gravity
      s.life -= dt;
    }
    _sparkles.removeWhere((s) => s.life <= 0);

    for (final s in _trailSparkles) {
      s.x += s.vx * dt / 800;
      s.y += s.vy * dt / 600;
      s.life -= dt;
    }
    _trailSparkles.removeWhere((s) => s.life <= 0);
  }

  void _updateBackground(double dt) {
    // Move stars slowly
    for (final star in _stars) {
      star.x -= dt * 0.005 * _gameSpeed;
      if (star.x < -0.01) {
        star.x = 1.01;
        star.y = _rng.nextDouble();
      }
    }

    // Move clouds
    for (final cloud in _clouds) {
      cloud.x -= dt * cloud.speed / 800 * _gameSpeed;
      if (cloud.x < -0.3) {
        cloud.x = 1.2;
        cloud.y = _rng.nextDouble() * 0.8 + 0.1;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sessionTimer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _gameStarted ? _buildGameView() : _buildStartScreen(),
    );
  }

  Widget _buildStartScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A0533), Color(0xFF0A0A1A)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Unicorn preview
              SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(
                  painter: _UnicornPainter(
                    wingAngle: 0.2,
                    hornGlow: 0.8,
                    stumble: false,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Unicorn Flight',
                style: GoogleFonts.fredoka(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Fly your unicorn into the correct sight words!\nAvoid misspelled words and wrong answers.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    color: AppColors.secondaryText,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: Text(
                  'Take Flight!',
                  style: GoogleFonts.fredoka(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Back',
                  style: GoogleFonts.nunito(
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

  Widget _buildGameView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        return GestureDetector(
          onPanUpdate: (details) {
            if (_gameOver) return;
            _unicornTargetY =
                (details.localPosition.dy / screenH).clamp(0.05, 0.95);
          },
          onTapDown: (details) {
            if (_gameOver) return;
            _unicornTargetY =
                (details.localPosition.dy / screenH).clamp(0.05, 0.95);
          },
          child: Stack(
            children: [
              // Game canvas
              CustomPaint(
                size: Size(screenW, screenH),
                painter: _GamePainter(
                  stars: _stars,
                  clouds: _clouds,
                  bubbles: _bubbles,
                  sparkles: _sparkles,
                  trailSparkles: _trailSparkles,
                  unicornY: _unicornY,
                  unicornX: _unicornX,
                  wingAngle: _wingAngle,
                  hornGlow: _hornGlow,
                  stumble: _stumbleTimer > 0,
                  flashTimer: _flashTimer,
                  totalTime: _totalTime,
                ),
              ),
              // HUD
              _buildHUD(screenW),
              // Target word
              _buildTargetWord(screenW),
              // Feedback text
              if (_feedbackTimer > 0) _buildFeedback(screenW, screenH),
              // Game over overlay
              if (_gameOver) _buildGameOver(screenW, screenH),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHUD(double screenW) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.primaryText),
                onPressed: () {
                  _ticker?.stop();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 8),
              // Hearts
              Row(
                children: List.generate(3, (i) {
                  final filled = i < _hearts;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.favorite : Icons.favorite_border,
                      color: filled ? AppColors.error : AppColors.secondaryText,
                      size: 28,
                    ),
                  );
                }),
              ),
              const Spacer(),
              // Score
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.starGold.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.starGold, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      '$_score',
                      style: GoogleFonts.fredoka(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.starGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetWord(double screenW) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.violet.withValues(alpha: 0.3),
                    AppColors.magenta.withValues(alpha: 0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: AppColors.violet.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.violet.withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Find: ',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  Text(
                    _targetWord,
                    style: GoogleFonts.fredoka(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

  Widget _buildFeedback(double screenW, double screenH) {
    final opacity = (_feedbackTimer / 1.5).clamp(0.0, 1.0);
    return Positioned(
      top: screenH * 0.35,
      left: 0,
      right: 0,
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -20 * (1.0 - opacity)),
            child: Text(
              _feedbackText,
              style: GoogleFonts.fredoka(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: _feedbackColor,
                shadows: [
                  Shadow(
                    color: _feedbackColor.withValues(alpha: 0.5),
                    blurRadius: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameOver(double screenW, double screenH) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.violet.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.2),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Flight Complete!',
                style: GoogleFonts.fredoka(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.starGold, size: 36),
                  const SizedBox(width: 8),
                  Text(
                    '$_score',
                    style: GoogleFonts.fredoka(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: AppColors.starGold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _score == 0
                    ? 'Keep practicing, ${widget.playerName}!'
                    : _score < 5
                        ? 'Good try, ${widget.playerName}!'
                        : _score < 10
                            ? 'Amazing flying, ${widget.playerName}!'
                            : 'You are a superstar, ${widget.playerName}!',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _startGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.violet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Fly Again',
                      style: GoogleFonts.fredoka(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: GoogleFonts.fredoka(fontSize: 18),
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
}

// ─── Game Painter ──────────────────────────────────────────────────────────

class _GamePainter extends CustomPainter {
  final List<_Star> stars;
  final List<_Cloud> clouds;
  final List<_WordBubble> bubbles;
  final List<_Sparkle> sparkles;
  final List<_Sparkle> trailSparkles;
  final double unicornY;
  final double unicornX;
  final double wingAngle;
  final double hornGlow;
  final bool stumble;
  final double flashTimer;
  final double totalTime;

  _GamePainter({
    required this.stars,
    required this.clouds,
    required this.bubbles,
    required this.sparkles,
    required this.trailSparkles,
    required this.unicornY,
    required this.unicornX,
    required this.wingAngle,
    required this.hornGlow,
    required this.stumble,
    required this.flashTimer,
    required this.totalTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSky(canvas, size);
    _drawMoon(canvas, size);
    _drawStars(canvas, size);
    _drawClouds(canvas, size);
    _drawTrailSparkles(canvas, size);
    _drawUnicorn(canvas, size);
    _drawBubbles(canvas, size);
    _drawSparkles(canvas, size);

    // Red flash overlay on wrong hit
    if (flashTimer > 0) {
      final flashOpacity = (flashTimer / 0.3).clamp(0.0, 1.0) * 0.15;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = AppColors.error.withValues(alpha: flashOpacity),
      );
    }
  }

  void _drawSky(Canvas canvas, Size size) {
    final skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [
          const Color(0xFF0D0221),
          const Color(0xFF150734),
          const Color(0xFF1A0A3E),
          const Color(0xFF0A0A1A),
        ],
        [0.0, 0.3, 0.7, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyPaint);
  }

  void _drawMoon(Canvas canvas, Size size) {
    final moonX = size.width * 0.82;
    final moonY = size.height * 0.12;
    const moonRadius = 30.0;

    // Moon glow
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(moonX, moonY),
        moonRadius * 3,
        [
          const Color(0x30FFFDE7),
          const Color(0x15FFFDE7),
          const Color(0x00FFFDE7),
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawCircle(Offset(moonX, moonY), moonRadius * 3, glowPaint);

    // Moon body
    canvas.drawCircle(
      Offset(moonX, moonY),
      moonRadius,
      Paint()..color = const Color(0xFFFFFDE7),
    );

    // Crescent shadow
    canvas.drawCircle(
      Offset(moonX + 10, moonY - 4),
      moonRadius * 0.85,
      Paint()..color = const Color(0xFF0D0221),
    );
  }

  void _drawStars(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle =
          (sin(totalTime * star.twinkleSpeed + star.twinklePhase) + 1) / 2;
      final alpha = (star.brightness * twinkle).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size,
        paint,
      );
      // Add small glow to bigger stars
      if (star.size > 1.5) {
        final glowPaint = Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(
          Offset(star.x * size.width, star.y * size.height),
          star.size * 2,
          glowPaint,
        );
      }
    }
  }

  void _drawClouds(Canvas canvas, Size size) {
    for (final cloud in clouds) {
      final cx = cloud.x * size.width;
      final cy = cloud.y * size.height;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: cloud.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

      // Draw cloud as overlapping ovals
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: cloud.width,
          height: cloud.height,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - cloud.width * 0.25, cy + 5),
          width: cloud.width * 0.6,
          height: cloud.height * 0.8,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + cloud.width * 0.2, cy - 3),
          width: cloud.width * 0.5,
          height: cloud.height * 0.7,
        ),
        paint,
      );
    }
  }

  void _drawTrailSparkles(Canvas canvas, Size size) {
    for (final s in trailSparkles) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = s.color.withValues(alpha: alpha * 0.8);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size * alpha,
        paint,
      );
    }
  }

  void _drawUnicorn(Canvas canvas, Size size) {
    final ux = unicornX * size.width;
    final uy = unicornY * size.height;

    canvas.save();
    canvas.translate(ux, uy);

    // Stumble shake
    if (stumble) {
      final shake = sin(totalTime * 40) * 4;
      canvas.translate(shake, shake * 0.5);
    }

    // Scale to appropriate size
    final scale = size.height / 600 * 1.0;
    canvas.scale(scale);

    // Draw the unicorn using the dedicated painter
    final unicornPainter = _UnicornPainter(
      wingAngle: wingAngle,
      hornGlow: hornGlow,
      stumble: stumble,
    );
    // Paint centered at origin, size 120x100
    const unicornRect = Rect.fromLTWH(-60, -50, 120, 100);
    canvas.save();
    unicornPainter._paintUnicorn(canvas, unicornRect);
    canvas.restore();

    canvas.restore();
  }

  void _drawBubbles(Canvas canvas, Size size) {
    for (final bubble in bubbles) {
      if (bubble.opacity <= 0) continue;

      final bx = bubble.x * size.width;
      final by = bubble.y * size.height;

      // Bubble background
      final bubbleRadius = 40.0 + bubble.text.length * 4;

      if (bubble.isCorrect) {
        // Correct: soft violet glow border
        final glowPaint = Paint()
          ..color = AppColors.violet.withValues(alpha: 0.2 * bubble.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(bx, by),
                width: bubbleRadius * 2 + 8,
                height: 52),
            const Radius.circular(26),
          ),
          glowPaint,
        );
      }

      // Background pill
      final bgColor = bubble.isCorrect
          ? AppColors.surface.withValues(alpha: 0.9 * bubble.opacity)
          : AppColors.surfaceVariant.withValues(alpha: 0.85 * bubble.opacity);
      final borderColor = bubble.isCorrect
          ? AppColors.violet.withValues(alpha: 0.5 * bubble.opacity)
          : AppColors.border.withValues(alpha: 0.4 * bubble.opacity);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(bx, by),
            width: bubbleRadius * 2,
            height: 46),
        const Radius.circular(23),
      );

      canvas.drawRRect(rrect, Paint()..color = bgColor);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Word text
      final textSpan = TextSpan(
        text: bubble.text,
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: bubble.opacity),
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(bx - textPainter.width / 2, by - textPainter.height / 2),
      );
    }
  }

  void _drawSparkles(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = s.color.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size * alpha,
        paint,
      );
      // Glow
      final glowPaint = Paint()
        ..color = s.color.withValues(alpha: alpha * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size * alpha * 2,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Unicorn Painter ───────────────────────────────────────────────────────

class _UnicornPainter extends CustomPainter {
  final double wingAngle;
  final double hornGlow;
  final bool stumble;

  _UnicornPainter({
    required this.wingAngle,
    required this.hornGlow,
    required this.stumble,
  });

  // Rainbow palette for mane/tail
  static const _rainbowColors = [
    Color(0xFFFF69B4), // Pink
    Color(0xFFFF1493), // Deep pink / magenta
    Color(0xFFBA55D3), // Medium orchid
    Color(0xFF8A2BE2), // Blue violet
    Color(0xFF4169E1), // Royal blue
    Color(0xFF00CED1), // Dark turquoise / cyan
    Color(0xFF00FA9A), // Medium spring green
    Color(0xFF7CFC00), // Lawn green
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = min(size.width / 120, size.height / 100);
    canvas.scale(scale);
    _paintUnicorn(canvas, const Rect.fromLTWH(-60, -50, 120, 100));
    canvas.restore();
  }

  void _paintUnicorn(Canvas canvas, Rect rect) {
    // Layer order: back wing -> tail -> back legs -> body -> front legs
    //              -> mane -> neck & head -> horn -> eye -> front wing -> horn sparkles

    _drawWing(canvas, isBack: true);
    _drawTail(canvas);
    _drawLegs(canvas, isFront: false);
    _drawBody(canvas);
    _drawLegs(canvas, isFront: true);
    _drawMane(canvas);
    _drawNeckAndHead(canvas);
    _drawHorn(canvas);
    _drawEye(canvas);
    _drawWing(canvas, isBack: false);
    _drawHornSparkles(canvas);
  }

  // ── BODY ──────────────────────────────────────────────────────────────────

  void _drawBody(Canvas canvas) {
    // Anatomical horse torso using bezier curves
    final bodyPath = Path();
    // Start at chest
    bodyPath.moveTo(20, -12);
    // Chest curve up to withers
    bodyPath.cubicTo(18, -22, 8, -26, 0, -24);
    // Withers to back (slight dip then rise)
    bodyPath.cubicTo(-8, -22, -16, -23, -22, -20);
    // Back to croup (hip)
    bodyPath.cubicTo(-28, -18, -32, -14, -30, -8);
    // Croup down to hindquarters
    bodyPath.cubicTo(-30, -2, -28, 6, -26, 10);
    // Belly — slightly rounded
    bodyPath.cubicTo(-22, 16, -10, 20, 2, 18);
    // Belly to chest underside
    bodyPath.cubicTo(12, 16, 20, 10, 22, 2);
    // Chest underside back up to start
    bodyPath.cubicTo(24, -4, 23, -8, 20, -12);
    bodyPath.close();

    // Main body gradient: white-lavender on top, deeper lavender below
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(-5, -26),
        const Offset(-5, 20),
        [
          const Color(0xFFFCF8FF), // Near-white top
          const Color(0xFFF0E6FF), // Soft lavender
          const Color(0xFFE4D6F8), // Medium lavender
          const Color(0xFFDBC8F0), // Deeper at belly
        ],
        [0.0, 0.3, 0.7, 1.0],
      );
    canvas.drawPath(bodyPath, bodyPaint);

    // Belly highlight — lighter underside reflection
    final bellyHighlight = Path();
    bellyHighlight.moveTo(-20, 8);
    bellyHighlight.cubicTo(-12, 14, 0, 15, 10, 12);
    bellyHighlight.cubicTo(4, 16, -8, 16, -20, 8);
    bellyHighlight.close();
    canvas.drawPath(
      bellyHighlight,
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );

    // Back sheen — glossy highlight along the spine
    final sheenPath = Path();
    sheenPath.moveTo(16, -16);
    sheenPath.cubicTo(10, -24, 0, -24, -10, -22);
    sheenPath.cubicTo(-18, -21, -24, -19, -28, -16);
    sheenPath.cubicTo(-20, -20, -8, -24, 2, -23);
    sheenPath.cubicTo(10, -23, 16, -20, 16, -16);
    sheenPath.close();
    canvas.drawPath(
      sheenPath,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // Shoulder definition — subtle shadow
    final shoulderPath = Path();
    shoulderPath.moveTo(14, -8);
    shoulderPath.cubicTo(10, -16, 6, -18, 4, -12);
    shoulderPath.cubicTo(6, -6, 10, -4, 14, -8);
    shoulderPath.close();
    canvas.drawPath(
      shoulderPath,
      Paint()..color = const Color(0xFFD0BEE8).withValues(alpha: 0.25),
    );

    // Hip definition — subtle shadow on hindquarters
    final hipPath = Path();
    hipPath.moveTo(-22, -6);
    hipPath.cubicTo(-26, -10, -28, -14, -26, -16);
    hipPath.cubicTo(-24, -12, -22, -8, -22, -6);
    hipPath.close();
    canvas.drawPath(
      hipPath,
      Paint()..color = const Color(0xFFD0BEE8).withValues(alpha: 0.2),
    );
  }

  // ── LEGS ──────────────────────────────────────────────────────────────────

  void _drawLegs(Canvas canvas, {required bool isFront}) {
    // Gallop motion based on wingAngle
    final gallopPhase = wingAngle * 1.5;

    if (isFront) {
      // Front-right (farther, slightly behind body)
      _drawSingleLeg(
        canvas,
        shoulderX: 10,
        shoulderY: 12,
        gallopOffset: sin(gallopPhase + pi) * 6,
        isNear: false,
      );
      // Front-left (nearer)
      _drawSingleLeg(
        canvas,
        shoulderX: 14,
        shoulderY: 12,
        gallopOffset: sin(gallopPhase) * 6,
        isNear: true,
      );
    } else {
      // Back-right (farther)
      _drawSingleLeg(
        canvas,
        shoulderX: -20,
        shoulderY: 8,
        gallopOffset: sin(gallopPhase + pi * 0.7) * 5,
        isNear: false,
      );
      // Back-left (nearer)
      _drawSingleLeg(
        canvas,
        shoulderX: -16,
        shoulderY: 8,
        gallopOffset: sin(gallopPhase + pi * 1.7) * 5,
        isNear: true,
      );
    }
  }

  void _drawSingleLeg(
    Canvas canvas, {
    required double shoulderX,
    required double shoulderY,
    required double gallopOffset,
    required bool isNear,
  }) {
    final alpha = isNear ? 1.0 : 0.7;

    // Thigh
    final kneeX = shoulderX + gallopOffset * 0.5;
    final kneeY = shoulderY + 14;
    // Shin
    final hoofX = shoulderX + gallopOffset;
    final hoofY = kneeY + 14;

    // Thigh segment
    final thighPath = Path();
    thighPath.moveTo(shoulderX - 3, shoulderY);
    thighPath.cubicTo(
      shoulderX - 3.5, shoulderY + 5,
      kneeX - 2.5, kneeY - 3,
      kneeX - 2, kneeY,
    );
    thighPath.lineTo(kneeX + 2, kneeY);
    thighPath.cubicTo(
      kneeX + 2.5, kneeY - 3,
      shoulderX + 3.5, shoulderY + 5,
      shoulderX + 3, shoulderY,
    );
    thighPath.close();

    canvas.drawPath(
      thighPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(shoulderX - 3, shoulderY),
          Offset(shoulderX + 3, shoulderY),
          [
            Color.fromRGBO(220, 208, 240, alpha),
            Color.fromRGBO(240, 232, 255, alpha),
            Color.fromRGBO(220, 208, 240, alpha),
          ],
          const [0.0, 0.4, 1.0],
        ),
    );

    // Knee joint circle
    canvas.drawCircle(
      Offset(kneeX, kneeY),
      2.5,
      Paint()..color = Color.fromRGBO(232, 222, 255, alpha),
    );

    // Shin segment
    final shinPath = Path();
    shinPath.moveTo(kneeX - 2, kneeY);
    shinPath.cubicTo(
      kneeX - 2, kneeY + 5,
      hoofX - 1.8, hoofY - 4,
      hoofX - 1.5, hoofY,
    );
    shinPath.lineTo(hoofX + 1.5, hoofY);
    shinPath.cubicTo(
      hoofX + 1.8, hoofY - 4,
      kneeX + 2, kneeY + 5,
      kneeX + 2, kneeY,
    );
    shinPath.close();

    canvas.drawPath(
      shinPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(kneeX - 2, kneeY),
          Offset(kneeX + 2, kneeY),
          [
            Color.fromRGBO(215, 200, 238, alpha),
            Color.fromRGBO(235, 228, 250, alpha),
            Color.fromRGBO(215, 200, 238, alpha),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // Hoof — darker rounded rectangle
    final hoofPath = Path();
    hoofPath.moveTo(hoofX - 2.5, hoofY);
    hoofPath.cubicTo(
      hoofX - 2.5, hoofY + 1.5,
      hoofX - 2, hoofY + 3,
      hoofX, hoofY + 3.5,
    );
    hoofPath.cubicTo(
      hoofX + 2, hoofY + 3,
      hoofX + 2.5, hoofY + 1.5,
      hoofX + 2.5, hoofY,
    );
    hoofPath.close();

    canvas.drawPath(
      hoofPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(hoofX, hoofY),
          Offset(hoofX, hoofY + 3.5),
          [
            Color.fromRGBO(200, 185, 225, alpha),
            Color.fromRGBO(170, 150, 200, alpha),
          ],
        ),
    );

    // Hoof shine
    canvas.drawCircle(
      Offset(hoofX - 0.5, hoofY + 1),
      1.0,
      Paint()..color = Colors.white.withValues(alpha: 0.2 * alpha),
    );
  }

  // ── TAIL ──────────────────────────────────────────────────────────────────

  void _drawTail(Canvas canvas) {
    const strandCount = 8;
    for (int i = 0; i < strandCount; i++) {
      final t = i / (strandCount - 1); // 0..1
      final colorIdx = (t * (_rainbowColors.length - 1)).round();
      final color = _rainbowColors[colorIdx];

      final spread = (i - strandCount / 2) * 2.0;
      final wave1 = sin(wingAngle * 2.5 + i * 0.6) * 6;
      final wave2 = sin(wingAngle * 3.2 + i * 0.9) * 8;
      final wave3 = cos(wingAngle * 2.0 + i * 0.4) * 10;

      final tailPath = Path();
      // Start at croup
      tailPath.moveTo(-28, -4 + spread * 0.5);
      tailPath.cubicTo(
        -36, -10 + spread + wave1,
        -48, -6 + spread * 1.2 + wave2,
        -56, -14 + spread * 0.8 + wave3,
      );

      canvas.drawPath(
        tailPath,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 3.0 + (1.0 - (i - strandCount / 2).abs() / strandCount) * 1.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // ── MANE ──────────────────────────────────────────────────────────────────

  void _drawMane(Canvas canvas) {
    // 10 flowing strands from poll (top of head) down neck
    const strandCount = 10;
    for (int i = 0; i < strandCount; i++) {
      final t = i / (strandCount - 1); // 0..1
      final colorIdx = (t * (_rainbowColors.length - 1)).round();
      final color = _rainbowColors[colorIdx];

      // Each strand starts along the crest line, spaces out
      final startX = 14 - t * 20; // from near ears to mid-back
      final startY = -30 + t * 10; // follows neck line down

      final wave = sin(wingAngle * 3.0 + i * 0.7) * (3 + t * 2);
      final wave2 = cos(wingAngle * 2.2 + i * 0.5) * (2 + t * 1.5);

      final manePath = Path();
      manePath.moveTo(startX, startY);
      manePath.cubicTo(
        startX - 6 + wave,
        startY - 6 + wave2,
        startX - 10 + wave * 0.8,
        startY - 2 + wave2 * 1.2,
        startX - 8 - t * 4 + wave * 0.5,
        startY + 6 + t * 4,
      );

      final thickness = 3.0 + sin(t * pi) * 1.5; // thicker in middle
      canvas.drawPath(
        manePath,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    // Forelock — two strands between/in front of ears
    final forelockWave = sin(wingAngle * 2.8) * 3;
    final forelock1 = Path();
    forelock1.moveTo(18, -36);
    forelock1.cubicTo(22, -44 + forelockWave, 27, -42 + forelockWave, 25, -34);
    canvas.drawPath(
      forelock1,
      Paint()
        ..color = const Color(0xFFFF69B4).withValues(alpha: 0.75)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    final forelock2 = Path();
    forelock2.moveTo(16, -35);
    forelock2.cubicTo(
      20, -45 + forelockWave * 0.8,
      28, -43 + forelockWave * 0.6,
      26, -35,
    );
    canvas.drawPath(
      forelock2,
      Paint()
        ..color = const Color(0xFF9370DB).withValues(alpha: 0.65)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  // ── NECK & HEAD ───────────────────────────────────────────────────────────

  void _drawNeckAndHead(Canvas canvas) {
    // Neck — muscular, arched shape
    final neckPath = Path();
    neckPath.moveTo(18, -14); // chest attachment
    neckPath.cubicTo(20, -20, 20, -28, 16, -32); // back of neck up
    neckPath.cubicTo(14, -34, 10, -34, 8, -32); // top of neck/poll
    neckPath.lineTo(4, -22); // throat line down
    neckPath.cubicTo(4, -18, 8, -14, 12, -12); // throat to chest
    neckPath.cubicTo(14, -12, 16, -12, 18, -14);
    neckPath.close();

    canvas.drawPath(
      neckPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(4, -34),
          const Offset(20, -12),
          [
            const Color(0xFFFAF6FF),
            const Color(0xFFF0E8FF),
            const Color(0xFFE8DEFF),
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Neck muscle sheen
    final neckSheen = Path();
    neckSheen.moveTo(16, -18);
    neckSheen.cubicTo(18, -24, 18, -28, 15, -30);
    neckSheen.cubicTo(16, -26, 16, -22, 16, -18);
    neckSheen.close();
    canvas.drawPath(
      neckSheen,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // ── Head — proper horse head with muzzle ──
    final headPath = Path();
    // Start at forehead
    headPath.moveTo(14, -38);
    // Forehead curve up
    headPath.cubicTo(18, -42, 24, -42, 26, -38);
    // Down the face
    headPath.cubicTo(28, -34, 30, -30, 32, -28);
    // Muzzle — broader, rounded
    headPath.cubicTo(34, -26, 34, -24, 32, -23);
    // Under jaw
    headPath.cubicTo(28, -22, 24, -24, 20, -26);
    // Jaw line back to throat
    headPath.cubicTo(16, -28, 12, -32, 14, -38);
    headPath.close();

    canvas.drawPath(
      headPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(12, -42),
          const Offset(34, -23),
          [
            const Color(0xFFFCFAFF), // Bright forehead
            const Color(0xFFF5EDFF), // Mid face
            const Color(0xFFEDE4FF), // Lower face
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Forehead highlight
    final foreheadHighlight = Path();
    foreheadHighlight.moveTo(18, -40);
    foreheadHighlight.cubicTo(20, -42, 24, -41, 24, -38);
    foreheadHighlight.cubicTo(22, -39, 20, -39, 18, -40);
    foreheadHighlight.close();
    canvas.drawPath(
      foreheadHighlight,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // Muzzle — soft pink area
    final muzzlePath = Path();
    muzzlePath.moveTo(30, -28);
    muzzlePath.cubicTo(33, -27, 34, -25, 33, -24);
    muzzlePath.cubicTo(31, -23, 28, -24, 28, -26);
    muzzlePath.cubicTo(28, -27, 29, -28, 30, -28);
    muzzlePath.close();
    canvas.drawPath(
      muzzlePath,
      Paint()..color = const Color(0xFFFFD1DC).withValues(alpha: 0.7),
    );

    // Nostril
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(31, -25.5),
        width: 2.0,
        height: 1.5,
      ),
      Paint()..color = const Color(0xFFDDA0B0),
    );

    // Ear — pointed, elegant
    final earPath = Path();
    earPath.moveTo(16, -40);
    earPath.cubicTo(15, -44, 13, -50, 14, -52);
    earPath.cubicTo(15, -52, 17, -48, 20, -42);
    earPath.close();
    canvas.drawPath(
      earPath,
      Paint()..color = const Color(0xFFF0E8FF),
    );

    // Inner ear — pink
    final innerEarPath = Path();
    innerEarPath.moveTo(16.2, -42);
    innerEarPath.cubicTo(15.5, -45, 14.5, -49, 15, -50);
    innerEarPath.cubicTo(16, -49, 17, -46, 18.5, -43);
    innerEarPath.close();
    canvas.drawPath(
      innerEarPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(15, -50),
          const Offset(17, -42),
          [
            const Color(0xFFFFB8D0),
            const Color(0xFFFFD1DC),
          ],
        ),
    );
  }

  // ── EYE ───────────────────────────────────────────────────────────────────

  void _drawEye(Canvas canvas) {
    const eyeCenter = Offset(24, -34);

    // Eye white (sclera) — almond shape
    final scleraPath = Path();
    scleraPath.moveTo(eyeCenter.dx - 4, eyeCenter.dy);
    scleraPath.cubicTo(
      eyeCenter.dx - 3, eyeCenter.dy - 4,
      eyeCenter.dx + 3, eyeCenter.dy - 4,
      eyeCenter.dx + 4, eyeCenter.dy,
    );
    scleraPath.cubicTo(
      eyeCenter.dx + 3, eyeCenter.dy + 3,
      eyeCenter.dx - 3, eyeCenter.dy + 3,
      eyeCenter.dx - 4, eyeCenter.dy,
    );
    scleraPath.close();
    canvas.drawPath(scleraPath, Paint()..color = Colors.white);

    // Iris — deep purple with radial gradient
    canvas.drawCircle(
      Offset(eyeCenter.dx + 0.5, eyeCenter.dy),
      2.8,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(eyeCenter.dx + 0.3, eyeCenter.dy - 0.5),
          2.8,
          [
            const Color(0xFF9B6FCF), // Lighter purple center
            const Color(0xFF6B3FA0), // Mid purple
            const Color(0xFF4A2080), // Deep purple edge
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Pupil
    canvas.drawCircle(
      Offset(eyeCenter.dx + 0.5, eyeCenter.dy),
      1.4,
      Paint()..color = const Color(0xFF0D0020),
    );

    // Primary highlight sparkle
    canvas.drawCircle(
      Offset(eyeCenter.dx + 1.5, eyeCenter.dy - 1.2),
      1.0,
      Paint()..color = Colors.white,
    );

    // Secondary highlight sparkle (smaller)
    canvas.drawCircle(
      Offset(eyeCenter.dx - 0.8, eyeCenter.dy + 0.8),
      0.5,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );

    // Upper eyelid line
    final eyelidPaint = Paint()
      ..color = const Color(0xFF3D2060)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final upperLidPath = Path();
    upperLidPath.moveTo(eyeCenter.dx - 4, eyeCenter.dy);
    upperLidPath.cubicTo(
      eyeCenter.dx - 3, eyeCenter.dy - 4.2,
      eyeCenter.dx + 3, eyeCenter.dy - 4.2,
      eyeCenter.dx + 4, eyeCenter.dy,
    );
    canvas.drawPath(upperLidPath, eyelidPaint);

    // Upper lashes — 3 elegant curved lashes
    final lashPaint = Paint()
      ..color = const Color(0xFF2D1050)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Left lash
    final lash1 = Path();
    lash1.moveTo(eyeCenter.dx - 2.5, eyeCenter.dy - 3.2);
    lash1.cubicTo(
      eyeCenter.dx - 4, eyeCenter.dy - 5,
      eyeCenter.dx - 5, eyeCenter.dy - 6,
      eyeCenter.dx - 5.5, eyeCenter.dy - 7.5,
    );
    canvas.drawPath(lash1, lashPaint);

    // Center lash (longest)
    final lash2 = Path();
    lash2.moveTo(eyeCenter.dx, eyeCenter.dy - 3.8);
    lash2.cubicTo(
      eyeCenter.dx - 0.5, eyeCenter.dy - 5.5,
      eyeCenter.dx - 1, eyeCenter.dy - 7,
      eyeCenter.dx - 1.5, eyeCenter.dy - 8.5,
    );
    canvas.drawPath(lash2, lashPaint);

    // Right lash
    final lash3 = Path();
    lash3.moveTo(eyeCenter.dx + 2.5, eyeCenter.dy - 2.8);
    lash3.cubicTo(
      eyeCenter.dx + 3, eyeCenter.dy - 4.5,
      eyeCenter.dx + 3, eyeCenter.dy - 6,
      eyeCenter.dx + 2.5, eyeCenter.dy - 7,
    );
    canvas.drawPath(lash3, lashPaint);

    // Lower lash (single, subtle)
    final lowerLashPaint = Paint()
      ..color = const Color(0xFF3D2060).withValues(alpha: 0.4)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(eyeCenter.dx + 1, eyeCenter.dy + 2.5),
      Offset(eyeCenter.dx + 2.5, eyeCenter.dy + 4),
      lowerLashPaint,
    );

    // Blush — rosy cheek glow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(eyeCenter.dx + 4, eyeCenter.dy + 5),
        width: 6,
        height: 3.5,
      ),
      Paint()
        ..color = const Color(0xFFFF9EC6).withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  // ── HORN ──────────────────────────────────────────────────────────────────

  void _drawHorn(Canvas canvas) {
    // Golden spiral cone horn
    const baseX = 19.0;
    const baseY = -42.0;
    const tipX = 16.0;
    const tipY = -60.0;
    const baseHalfW = 3.0;

    // Horn silhouette — tapered cone
    final hornPath = Path();
    hornPath.moveTo(baseX - baseHalfW, baseY);
    hornPath.cubicTo(
      baseX - baseHalfW * 0.8, baseY - 6,
      tipX - 0.5, tipY + 4,
      tipX, tipY,
    );
    hornPath.cubicTo(
      tipX + 0.5, tipY + 4,
      baseX + baseHalfW * 0.8, baseY - 6,
      baseX + baseHalfW, baseY,
    );
    hornPath.close();

    // Horn gradient — gold
    canvas.drawPath(
      hornPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(tipX, tipY),
          const Offset(baseX, baseY),
          [
            const Color(0xFFFFF8DC), // Bright gold tip
            const Color(0xFFFFE066), // Light gold
            const Color(0xFFFFD700), // Gold
            const Color(0xFFDAA520), // Goldenrod base
          ],
          [0.0, 0.3, 0.6, 1.0],
        ),
    );

    // Spiral lines winding up the horn
    final spiralPaint = Paint()
      ..color = const Color(0xFFB8860B).withValues(alpha: 0.45)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 6; i++) {
      final t = i / 7.0; // position along horn
      final y = baseY + (tipY - baseY) * t;
      final hw = baseHalfW * (1 - t) * 0.9; // narrowing half-width
      final cx = baseX + (tipX - baseX) * t;

      // Slight sinusoidal offset for spiral look
      final offsetX = sin(t * pi * 3 + 0.5) * hw * 0.3;
      canvas.drawLine(
        Offset(cx - hw + offsetX, y),
        Offset(cx + hw + offsetX, y),
        spiralPaint,
      );
    }

    // Magical glow emanating from tip
    final glowAlpha = 0.2 + hornGlow * 0.35;
    canvas.drawCircle(
      const Offset(tipX, tipY),
      8,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(tipX, tipY),
          8,
          [
            Color.fromRGBO(255, 248, 220, glowAlpha),
            Color.fromRGBO(255, 215, 0, glowAlpha * 0.5),
            const Color.fromRGBO(255, 215, 0, 0),
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Brighter inner glow
    canvas.drawCircle(
      const Offset(tipX, tipY),
      4,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: glowAlpha * 1.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _drawHornSparkles(Canvas canvas) {
    // Tiny sparkle crosses around horn tip
    const tipX = 16.0;
    const tipY = -60.0;
    final sparkleAlpha = 0.4 + hornGlow * 0.6;

    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: sparkleAlpha)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    // 4 sparkle crosses at different positions around the tip
    final sparklePositions = [
      const Offset(tipX - 6, tipY - 3),
      const Offset(tipX + 5, tipY - 1),
      const Offset(tipX - 3, tipY + 4),
      const Offset(tipX + 3, tipY - 5),
    ];

    for (int i = 0; i < sparklePositions.length; i++) {
      final pos = sparklePositions[i];
      final size = 2.0 + sin(hornGlow * pi * 2 + i * 1.5) * 1.0;

      // Vertical line of cross
      canvas.drawLine(
        Offset(pos.dx, pos.dy - size),
        Offset(pos.dx, pos.dy + size),
        sparklePaint,
      );
      // Horizontal line of cross
      canvas.drawLine(
        Offset(pos.dx - size, pos.dy),
        Offset(pos.dx + size, pos.dy),
        sparklePaint,
      );
    }

    // Central sparkle dot at horn tip
    canvas.drawCircle(
      const Offset(tipX, tipY),
      2.0 + hornGlow * 1.0,
      Paint()..color = Colors.white.withValues(alpha: sparkleAlpha * 0.8),
    );
  }

  // ── WINGS ─────────────────────────────────────────────────────────────────

  void _drawWing(Canvas canvas, {required bool isBack}) {
    canvas.save();

    // Wing pivot at shoulder area
    const pivotX = 2.0;
    const pivotY = -16.0;
    canvas.translate(pivotX, pivotY);

    // Flap rotation
    final flapAngle = isBack ? wingAngle * 0.6 : wingAngle;
    canvas.rotate(flapAngle * (isBack ? 0.5 : 0.9));

    final baseAlpha = isBack ? 0.45 : 0.75;

    // ── Wing outline shape (arc from body up and out) ──
    final wingOuterPath = Path();
    wingOuterPath.moveTo(0, 0); // shoulder
    wingOuterPath.cubicTo(-4, -10, -12, -25, -8, -40); // leading edge up
    wingOuterPath.cubicTo(-4, -48, 4, -48, 8, -42); // wing tip arc
    wingOuterPath.cubicTo(14, -36, 16, -28, 12, -20); // trailing edge back
    wingOuterPath.cubicTo(8, -12, 4, -6, 0, 0); // back to shoulder
    wingOuterPath.close();

    // Wing base fill — semi-transparent lavender with iridescence
    canvas.drawPath(
      wingOuterPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(-4, -45),
          [
            Color.fromRGBO(248, 244, 255, baseAlpha),
            Color.fromRGBO(230, 215, 255, baseAlpha),
            Color.fromRGBO(215, 195, 250, baseAlpha * 0.9),
            Color.fromRGBO(200, 180, 255, baseAlpha * 0.8),
          ],
          const [0.0, 0.3, 0.6, 1.0],
        ),
    );

    // ── Covert feathers (small, near body) ──
    final covertPaint = Paint()
      ..color = Color.fromRGBO(225, 210, 250, baseAlpha * 0.5)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final t = i / 4.0;
      final covert = Path();
      final startY = -4 - t * 8;
      covert.moveTo(-1, startY);
      covert.cubicTo(-3, startY - 4, -4 - t * 2, startY - 6, -3 - t * 2, startY - 8);
      canvas.drawPath(covert, covertPaint);
    }

    // ── Secondary feathers (middle layer) ──
    final secondaryPaint = Paint()
      ..color = Color.fromRGBO(210, 195, 245, baseAlpha * 0.4)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 5; i++) {
      final t = i / 5.0;
      final secondary = Path();
      final startY = -12 - t * 8;
      final startX = -2 - t * 2;
      secondary.moveTo(startX, startY);
      secondary.cubicTo(
        startX - 4, startY - 5,
        startX - 6, startY - 8,
        startX - 4 - t * 2, startY - 12,
      );
      canvas.drawPath(secondary, secondaryPaint);
    }

    // ── Primary feathers (longest, at wing tip) ──
    final primaryPaint = Paint()
      ..color = Color.fromRGBO(200, 180, 240, baseAlpha * 0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 6; i++) {
      final t = i / 6.0;
      final primary = Path();
      // Feathers fan out from mid-wing
      final baseY = -28 - t * 6;
      final baseX = -4 + t * 4;
      primary.moveTo(baseX, baseY);
      primary.cubicTo(
        baseX - 3 + t * 6, baseY - 6,
        baseX - 2 + t * 8, baseY - 10,
        baseX + t * 10, baseY - 14,
      );
      canvas.drawPath(primary, primaryPaint);
    }

    // ── Feather overlap shapes (elongated ovals for realism) ──
    for (int i = 0; i < 5; i++) {
      final t = i / 5.0;
      final featherPath = Path();
      final fx = -2 + t * 3;
      final fy = -10 - t * 8;
      final fLen = 12 + t * 6;

      featherPath.moveTo(fx, fy);
      featherPath.cubicTo(
        fx - 3, fy - fLen * 0.3,
        fx - 4, fy - fLen * 0.7,
        fx - 2 - t * 2, fy - fLen,
      );
      featherPath.cubicTo(
        fx - 1, fy - fLen * 0.7,
        fx, fy - fLen * 0.3,
        fx, fy,
      );
      featherPath.close();

      canvas.drawPath(
        featherPath,
        Paint()
          ..color = Color.fromRGBO(235, 225, 255, baseAlpha * 0.2)
          ..style = PaintingStyle.fill,
      );
    }

    // ── Iridescent shimmer on leading edge ──
    final shimmerPath = Path();
    shimmerPath.moveTo(0, 0);
    shimmerPath.cubicTo(-4, -10, -12, -25, -8, -40);
    shimmerPath.cubicTo(-4, -48, 0, -48, 2, -44);

    canvas.drawPath(
      shimmerPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(-8, -44),
          [
            Color.fromRGBO(255, 255, 255, baseAlpha * 0.1),
            Color.fromRGBO(200, 220, 255, baseAlpha * 0.3),
            Color.fromRGBO(220, 200, 255, baseAlpha * 0.3),
            Color.fromRGBO(255, 255, 255, baseAlpha * 0.1),
          ],
          const [0.0, 0.3, 0.7, 1.0],
        )
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // ── Wing edge outline ──
    canvas.drawPath(
      wingOuterPath,
      Paint()
        ..color = Colors.white.withValues(alpha: baseAlpha * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnicornPainter oldDelegate) {
    return oldDelegate.wingAngle != wingAngle ||
        oldDelegate.hornGlow != hornGlow ||
        oldDelegate.stumble != stumble;
  }
}

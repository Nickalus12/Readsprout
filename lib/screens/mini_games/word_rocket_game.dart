import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/dolch_words.dart';
import '../../services/audio_service.dart';
import '../../services/high_score_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Word Rocket -- tap letters in order to spell words and boost the rocket
// ---------------------------------------------------------------------------

class WordRocketGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const WordRocketGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<WordRocketGame> createState() => _WordRocketGameState();
}

class _WordRocketGameState extends State<WordRocketGame>
    with TickerProviderStateMixin {
  static const _gameId = 'word_rocket';
  static const _totalWords = 10;
  static const _lives = 3;

  final _rng = Random();

  // Game state
  List<String> _wordPool = [];
  String _currentWord = '';
  int _letterIndex = 0;
  List<_LetterTile> _tiles = [];
  int _score = 0;
  int _wordsCompleted = 0;
  int _livesLeft = _lives;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Rocket state
  double _rocketY = 0.7; // 0 = top, 1 = bottom (fraction of screen)
  double _rocketBoost = 0.0;
  double _turbulence = 0.0;

  // Particles
  final List<_ExhaustParticle> _exhaustParticles = [];
  final List<_StarParticle> _bgStars = [];

  // Animation
  late AnimationController _gameLoop;
  late AnimationController _boostController;
  late AnimationController _turbulenceController;
  late AnimationController _completionController;

  // Speed bonus timer
  late Stopwatch _wordTimer;
  int _combo = 0;

  @override
  void initState() {
    super.initState();
    _wordTimer = Stopwatch();

    _gameLoop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _gameLoop.addListener(_updateGame);

    _boostController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _turbulenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Generate background stars
    for (int i = 0; i < 60; i++) {
      _bgStars.add(_StarParticle.random(_rng));
    }

    _initWordPool();
    _nextWord();
  }

  void _initWordPool() {
    final unlocked = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        for (final w in DolchWords.wordsForLevel(level)) {
          if (w.text.length >= 2 && w.text.length <= 6) {
            unlocked.add(w.text);
          }
        }
      }
    }
    if (unlocked.length < 10) {
      for (final w in DolchWords.wordsForLevel(1)) {
        unlocked.add(w.text);
      }
    }
    unlocked.shuffle(_rng);
    _wordPool = unlocked;
  }

  void _nextWord() {
    if (_wordsCompleted >= _totalWords || _livesLeft <= 0) {
      _endGame();
      return;
    }

    final word = _wordPool[_wordsCompleted % _wordPool.length];
    _currentWord = word;
    _letterIndex = 0;
    _wordTimer.reset();
    _wordTimer.start();

    // Create letter tiles: correct letters + distractors, shuffled
    final letters = word.split('');
    final distractors = <String>[];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    while (distractors.length < 4) {
      final c = alphabet[_rng.nextInt(26)];
      if (!letters.contains(c) && !distractors.contains(c)) {
        distractors.add(c);
      }
    }

    final all = [...letters, ...distractors];
    all.shuffle(_rng);

    _tiles = all.asMap().entries.map((e) {
      return _LetterTile(
        letter: e.value,
        x: _rng.nextDouble() * 0.8 + 0.1,
        y: _rng.nextDouble() * 0.3 + 0.15,
        phase: _rng.nextDouble() * 2 * pi,
        speed: 0.3 + _rng.nextDouble() * 0.4,
      );
    }).toList();

    widget.audioService.playWord(word);
    if (mounted) setState(() {});
  }

  void _updateGame() {
    if (_gameOver || !mounted) return;

    setState(() {
      // Rocket gravity -- slowly drifts down
      _rocketY += 0.0003;
      _rocketY = _rocketY.clamp(0.1, 0.9);

      // Apply boost
      if (_rocketBoost > 0) {
        _rocketY -= _rocketBoost * 0.002;
        _rocketBoost *= 0.95;
        if (_rocketBoost < 0.01) _rocketBoost = 0;
      }

      // Apply turbulence
      if (_turbulence > 0) {
        _rocketY += sin(_gameLoop.value * pi * 20) * _turbulence * 0.003;
        _turbulence *= 0.92;
        if (_turbulence < 0.01) _turbulence = 0;
      }

      _rocketY = _rocketY.clamp(0.1, 0.9);

      // Update exhaust particles
      if (_rocketBoost > 0.1) {
        _exhaustParticles.add(_ExhaustParticle(
          x: 0.5 + (_rng.nextDouble() - 0.5) * 0.04,
          y: _rocketY + 0.05,
          vx: (_rng.nextDouble() - 0.5) * 0.002,
          vy: 0.002 + _rng.nextDouble() * 0.003,
          life: 1.0,
          size: 2 + _rng.nextDouble() * 4,
          color: _rng.nextBool()
              ? const Color(0xFFFF8C42)
              : const Color(0xFFFFD700),
        ));
      }

      for (final p in _exhaustParticles) {
        p.x += p.vx;
        p.y += p.vy;
        p.life -= 0.02;
      }
      _exhaustParticles.removeWhere((p) => p.life <= 0);

      // Float stars downward to simulate upward motion
      for (final s in _bgStars) {
        s.y += s.speed * 0.0005 * (1 + _rocketBoost * 2);
        if (s.y > 1.1) {
          s.y = -0.1;
          s.x = _rng.nextDouble();
        }
      }
    });
  }

  void _onTileTap(int index) {
    if (_gameOver) return;
    final tile = _tiles[index];
    if (tile.used) return;

    final expected = _currentWord[_letterIndex];
    if (tile.letter == expected) {
      // Correct
      Haptics.correct();
      widget.audioService.playLetter(tile.letter);
      setState(() {
        tile.used = true;
        tile.correct = true;
        _letterIndex++;
        _rocketBoost = 1.0;
      });
      _boostController.forward(from: 0.0);

      if (_letterIndex >= _currentWord.length) {
        _onWordComplete();
      }
    } else {
      // Wrong
      Haptics.wrong();
      widget.audioService.playError();
      setState(() {
        _turbulence = 1.0;
        _livesLeft--;
        _combo = 0;
      });
      _turbulenceController.forward(from: 0.0);

      if (_livesLeft <= 0) {
        _endGame();
      }
    }
  }

  void _onWordComplete() {
    _wordTimer.stop();
    _combo++;
    final speedBonus = max(0, (5000 - _wordTimer.elapsedMilliseconds) ~/ 100);
    final comboBonus = (_combo - 1) * 5;
    final wordScore = 10 + speedBonus + comboBonus;

    widget.audioService.playSuccess();
    Haptics.success();

    setState(() {
      _score += wordScore;
      _wordsCompleted++;
      _rocketBoost = 3.0;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_gameOver) _nextWord();
    });
  }

  Future<void> _endGame() async {
    _gameOver = true;
    _gameLoop.stop();
    _wordTimer.stop();

    final isNewBest = await widget.highScoreService.saveScore(
      _gameId,
      _score,
      widget.playerName,
    );

    if (mounted) {
      setState(() {
        _isNewBest = isNewBest;
      });
      if (_wordsCompleted >= _totalWords) {
        widget.audioService.playLevelCompleteEffect();
      }
      _completionController.forward(from: 0.0);
    }
  }

  void _restart() {
    _gameLoop.repeat();
    _completionController.reset();
    setState(() {
      _score = 0;
      _wordsCompleted = 0;
      _livesLeft = _lives;
      _gameOver = false;
      _isNewBest = false;
      _rocketY = 0.7;
      _rocketBoost = 0;
      _turbulence = 0;
      _combo = 0;
      _exhaustParticles.clear();
    });
    _initWordPool();
    _nextWord();
  }

  @override
  void dispose() {
    _gameLoop.removeListener(_updateGame);
    _gameLoop.dispose();
    _boostController.dispose();
    _turbulenceController.dispose();
    _completionController.dispose();
    super.dispose();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF050520), Color(0xFF0A0A2E)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Background stars
              AnimatedBuilder(
                animation: _gameLoop,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _StarFieldPainter(stars: _bgStars),
                    size: Size.infinite,
                  );
                },
              ),

              // Exhaust particles
              AnimatedBuilder(
                animation: _gameLoop,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ExhaustPainter(particles: _exhaustParticles),
                    size: Size.infinite,
                  );
                },
              ),

              // Rocket
              AnimatedBuilder(
                animation: _gameLoop,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _RocketPainter(
                      rocketY: _rocketY,
                      boost: _rocketBoost,
                      turbulence: _turbulence,
                      time: _gameLoop.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),

              // UI overlay
              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildWordDisplay(),
                  if (!_gameOver) Expanded(child: _buildLetterTiles()),
                  if (_gameOver) Expanded(child: _buildGameOver()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.primaryText),
          ),
          Expanded(
            child: Text(
              'Word Rocket',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
          // Lives
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_lives, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  i < _livesLeft
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: i < _livesLeft
                      ? AppColors.error
                      : AppColors.secondaryText.withValues(alpha: 0.3),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.starGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.starGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              '$_score',
              style: AppFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.starGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            'Word ${_wordsCompleted + 1} of $_totalWords',
            style: AppFonts.nunito(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_currentWord.length, (i) {
              final revealed = i < _letterIndex;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 32,
                height: 40,
                decoration: BoxDecoration(
                  color: revealed
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: i == _letterIndex
                        ? AppColors.electricBlue
                        : revealed
                            ? AppColors.success.withValues(alpha: 0.5)
                            : AppColors.border,
                    width: i == _letterIndex ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    revealed ? _currentWord[i] : '',
                    style: AppFonts.fredoka(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (_combo > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Combo x$_combo',
                style: AppFonts.fredoka(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLetterTiles() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) {
            // Check if a tile was hit
            final dx = details.localPosition.dx / constraints.maxWidth;
            final dy = details.localPosition.dy / constraints.maxHeight;
            for (int i = 0; i < _tiles.length; i++) {
              final t = _tiles[i];
              if (t.used) continue;
              final time = _gameLoop.value;
              final floatX =
                  t.x + sin(time * 2 * pi * t.speed + t.phase) * 0.03;
              final floatY =
                  t.y + cos(time * 2 * pi * t.speed * 0.7 + t.phase) * 0.02;
              if ((dx - floatX).abs() < 0.06 && (dy - floatY).abs() < 0.06) {
                _onTileTap(i);
                return;
              }
            }
          },
          child: AnimatedBuilder(
            animation: _gameLoop,
            builder: (context, _) {
              return CustomPaint(
                painter: _TilesPainter(
                  tiles: _tiles,
                  time: _gameLoop.value,
                  currentWord: _currentWord,
                  letterIndex: _letterIndex,
                ),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGameOver() {
    final best = widget.highScoreService.getPersonalBest(_gameId);
    return AnimatedBuilder(
      animation: _completionController,
      builder: (context, _) {
        final p = _completionController.value;
        return Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.8 + 0.2 * Curves.elasticOut.transform(p),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.electricBlue.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _wordsCompleted >= _totalWords
                          ? 'Mission Complete!'
                          : 'Mission Over',
                      style: AppFonts.fredoka(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$_score points',
                      style: AppFonts.fredoka(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.starGold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_wordsCompleted words spelled',
                      style: AppFonts.nunito(
                        fontSize: 14,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    if (_isNewBest) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.starGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'NEW BEST!',
                          style: AppFonts.fredoka(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.starGold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Best: $best',
                      style: AppFonts.nunito(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _restart,
                      icon: const Icon(Icons.replay_rounded, size: 20),
                      label: Text(
                        'Play Again',
                        style: AppFonts.fredoka(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---- Data classes ----

class _LetterTile {
  final String letter;
  final double x; // 0..1
  final double y; // 0..1
  final double phase;
  final double speed;
  bool used = false;
  bool correct = false;

  _LetterTile({
    required this.letter,
    required this.x,
    required this.y,
    required this.phase,
    required this.speed,
  });
}

class _ExhaustParticle {
  double x, y, vx, vy, life, size;
  Color color;

  _ExhaustParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.color,
  });
}

class _StarParticle {
  double x, y;
  final double size;
  final double opacity;
  final double speed;

  _StarParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
  });

  factory _StarParticle.random(Random rng) {
    return _StarParticle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 0.5 + rng.nextDouble() * 2.5,
      opacity: 0.2 + rng.nextDouble() * 0.6,
      speed: 0.5 + rng.nextDouble() * 1.5,
    );
  }
}

// ---- Painters ----

class _StarFieldPainter extends CustomPainter {
  final List<_StarParticle> stars;
  _StarFieldPainter({required this.stars});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: s.opacity)
        ..maskFilter =
            s.size > 1.5 ? MaskFilter.blur(BlurStyle.normal, s.size) : null;
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter old) => true;
}

class _ExhaustPainter extends CustomPainter {
  final List<_ExhaustParticle> particles;
  _ExhaustPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: (p.life * 0.8).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size * p.life,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExhaustPainter old) => true;
}

class _RocketPainter extends CustomPainter {
  final double rocketY;
  final double boost;
  final double turbulence;
  final double time;

  _RocketPainter({
    required this.rocketY,
    required this.boost,
    required this.turbulence,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = rocketY * size.height;
    final wobble = sin(time * 2 * pi * 8) * turbulence * 3;

    canvas.save();
    canvas.translate(cx + wobble, cy);

    // Rocket body
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE0E0FF), Color(0xFF8888CC)],
      ).createShader(const Rect.fromLTWH(-12, -30, 24, 60));
    final body = Path()
      ..moveTo(0, -30) // nose
      ..quadraticBezierTo(14, -10, 12, 20) // right side
      ..lineTo(-12, 20) // bottom
      ..quadraticBezierTo(-14, -10, 0, -30); // left side
    canvas.drawPath(body, bodyPaint);

    // Window
    canvas.drawCircle(
      const Offset(0, -5),
      6,
      Paint()..color = const Color(0xFF00D4FF).withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      const Offset(-2, -7),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // Fins
    final finPaint = Paint()..color = const Color(0xFFFF4757);
    final leftFin = Path()
      ..moveTo(-12, 14)
      ..lineTo(-22, 26)
      ..lineTo(-8, 20)
      ..close();
    final rightFin = Path()
      ..moveTo(12, 14)
      ..lineTo(22, 26)
      ..lineTo(8, 20)
      ..close();
    canvas.drawPath(leftFin, finPaint);
    canvas.drawPath(rightFin, finPaint);

    // Nose cone accent
    canvas.drawCircle(
      const Offset(0, -28),
      3,
      Paint()..color = const Color(0xFFFFD700),
    );

    // Flame if boosting
    if (boost > 0.05) {
      final flameLen = 15.0 + boost * 20;
      final flameWidth = 8.0 + sin(time * 2 * pi * 12) * 3;
      final flamePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFD700),
            const Color(0xFFFF8C42),
            const Color(0xFFFF4757).withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromLTWH(-flameWidth, 20, flameWidth * 2, flameLen));
      final flame = Path()
        ..moveTo(-flameWidth * 0.6, 20)
        ..quadraticBezierTo(0, 20 + flameLen, flameWidth * 0.6, 20);
      canvas.drawPath(flame, flamePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RocketPainter old) => true;
}

class _TilesPainter extends CustomPainter {
  final List<_LetterTile> tiles;
  final double time;
  final String currentWord;
  final int letterIndex;

  _TilesPainter({
    required this.tiles,
    required this.time,
    required this.currentWord,
    required this.letterIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in tiles) {
      if (t.used) continue;

      final floatX =
          (t.x + sin(time * 2 * pi * t.speed + t.phase) * 0.03) * size.width;
      final floatY =
          (t.y + cos(time * 2 * pi * t.speed * 0.7 + t.phase) * 0.02) *
              size.height;

      // Determine if this is a next-expected letter
      final isNext = letterIndex < currentWord.length &&
          t.letter == currentWord[letterIndex];

      // Glow
      if (isNext) {
        canvas.drawCircle(
          Offset(floatX, floatY),
          28,
          Paint()
            ..color = AppColors.electricBlue.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }

      // Tile background
      final tileRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(floatX, floatY), width: 44, height: 44),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        tileRect,
        Paint()
          ..color = isNext
              ? AppColors.surface
              : AppColors.surface.withValues(alpha: 0.8),
      );
      canvas.drawRRect(
        tileRect,
        Paint()
          ..color = isNext
              ? AppColors.electricBlue.withValues(alpha: 0.6)
              : AppColors.border.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNext ? 2 : 1,
      );

      // Letter text
      final tp = TextPainter(
        text: TextSpan(
          text: t.letter,
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isNext ? AppColors.electricBlue : AppColors.primaryText,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(floatX - tp.width / 2, floatY - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TilesPainter old) => true;
}

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

class _RocketSim extends ChangeNotifier {
  double rocketY = 0.7;
  double rocketBoost = 0.0;
  double turbulence = 0.0;
  double time = 0.0;

  final List<_ExhaustParticle> exhaustParticles = [];
  final List<_StarParticle> bgStars = [];
  List<_LetterTile> tiles = [];

  final _rng = Random();

  void tick(double animValue) {
    time = animValue;

    rocketY += 0.0003;
    rocketY = rocketY.clamp(0.1, 0.9);

    if (rocketBoost > 0) {
      rocketY -= rocketBoost * 0.002;
      rocketBoost *= 0.95;
      if (rocketBoost < 0.01) rocketBoost = 0;
    }

    if (turbulence > 0) {
      rocketY += sin(animValue * pi * 20) * turbulence * 0.003;
      turbulence *= 0.92;
      if (turbulence < 0.01) turbulence = 0;
    }

    rocketY = rocketY.clamp(0.1, 0.9);

    if (rocketBoost > 0.1) {
      exhaustParticles.add(_ExhaustParticle(
        x: 0.5 + (_rng.nextDouble() - 0.5) * 0.04,
        y: rocketY + 0.05,
        vx: (_rng.nextDouble() - 0.5) * 0.002,
        vy: 0.002 + _rng.nextDouble() * 0.003,
        life: 1.0,
        size: 2 + _rng.nextDouble() * 4,
        color: _rng.nextBool()
            ? const Color(0xFFFF8C42)
            : const Color(0xFFFFD700),
      ));
    }

    for (final p in exhaustParticles) {
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.02;
    }
    exhaustParticles.removeWhere((p) => p.life <= 0);

    for (final s in bgStars) {
      s.y += s.speed * 0.0005 * (1 + rocketBoost * 2);
      if (s.y > 1.1) {
        s.y = -0.1;
        s.x = _rng.nextDouble();
      }
    }

    notifyListeners();
  }

  void reset() {
    rocketY = 0.7;
    rocketBoost = 0;
    turbulence = 0;
    exhaustParticles.clear();
    tiles = [];
  }
}

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
  final _sim = _RocketSim();

  // Game state
  List<String> _wordPool = [];
  String _currentWord = '';
  int _letterIndex = 0;
  int _score = 0;
  int _wordsCompleted = 0;
  int _livesLeft = _lives;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Animation
  late AnimationController _gameLoop;
  late AnimationController _boostController;
  late AnimationController _turbulenceController;
  late AnimationController _completionController;

  // Speed bonus timer
  late Stopwatch _wordTimer;
  int _combo = 0;
  bool _showingStartOverlay = true;

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

    for (int i = 0; i < 60; i++) {
      _sim.bgStars.add(_StarParticle.random(_rng));
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

    _sim.tiles = all.asMap().entries.map((e) {
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
    _sim.tick(_gameLoop.value);
  }

  void _onTileTap(int index) {
    if (_gameOver || _showingStartOverlay) return;
    final tile = _sim.tiles[index];
    if (tile.used) return;

    final expected = _currentWord[_letterIndex];
    if (tile.letter == expected) {
      Haptics.correct();
      widget.audioService.playLetter(tile.letter);
      tile.used = true;
      tile.correct = true;
      _letterIndex++;
      _sim.rocketBoost = 1.0;
      _boostController.forward(from: 0.0);
      setState(() {});

      if (_letterIndex >= _currentWord.length) {
        _onWordComplete();
      }
    } else {
      Haptics.wrong();
      _sim.turbulence = 1.0;
      _turbulenceController.forward(from: 0.0);
      setState(() {
        _livesLeft--;
        _combo = 0;
      });

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

    _sim.rocketBoost = 3.0;
    setState(() {
      _score += wordScore;
      _wordsCompleted++;
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
    _sim.reset();
    setState(() {
      _showingStartOverlay = false;
      _score = 0;
      _wordsCompleted = 0;
      _livesLeft = _lives;
      _gameOver = false;
      _isNewBest = false;
      _combo = 0;
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
    _sim.dispose();
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
              RepaintBoundary(
                child: CustomPaint(
                  painter: _StarFieldPainter(sim: _sim),
                  size: Size.infinite,
                ),
              ),

              RepaintBoundary(
                child: CustomPaint(
                  painter: _ExhaustPainter(sim: _sim),
                  size: Size.infinite,
                ),
              ),

              RepaintBoundary(
                child: CustomPaint(
                  painter: _RocketPainter(sim: _sim),
                  size: Size.infinite,
                ),
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

              if (_showingStartOverlay) _buildStartOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showingStartOverlay = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.electricBlue.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u{1F680}',
                  style: AppFonts.fredoka(fontSize: 40),
                ),
                const SizedBox(height: 8),
                Text(
                  'Word Rocket',
                  style: AppFonts.fredoka(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        color: AppColors.electricBlue, size: 28),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: AppColors.secondaryText, size: 18),
                    const SizedBox(width: 8),
                    _buildHintTile('c'),
                    _buildHintTile('a'),
                    _buildHintTile('t'),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_upward_rounded,
                        color: AppColors.success, size: 22),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Listen to the word, then tap\nletters in order to fly up!',
                  style: AppFonts.nunito(
                    fontSize: 15,
                    color: AppColors.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.electricBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Tap to Start!',
                    style: AppFonts.fredoka(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
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

  Widget _buildHintTile(String letter) {
    return Container(
      width: 32,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.electricBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.electricBlue.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Text(
          letter,
          style: AppFonts.fredoka(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.electricBlue,
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
            final dx = details.localPosition.dx / constraints.maxWidth;
            final dy = details.localPosition.dy / constraints.maxHeight;
            for (int i = 0; i < _sim.tiles.length; i++) {
              final t = _sim.tiles[i];
              if (t.used) continue;
              final time = _sim.time;
              final floatX =
                  t.x + sin(time * 2 * pi * t.speed + t.phase) * 0.03;
              final floatY =
                  t.y + cos(time * 2 * pi * t.speed * 0.7 + t.phase) * 0.02;
              if ((dx - floatX).abs() < 0.08 && (dy - floatY).abs() < 0.08) {
                _onTileTap(i);
                return;
              }
            }
          },
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TilesPainter(
                sim: _sim,
                currentWord: _currentWord,
                letterIndex: _letterIndex,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
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
                          : 'Great Flying!',
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
  final double x;
  final double y;
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
  final _RocketSim sim;
  _StarFieldPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sim.bgStars) {
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
  bool shouldRepaint(covariant _StarFieldPainter old) => false;
}

class _ExhaustPainter extends CustomPainter {
  final _RocketSim sim;
  _ExhaustPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in sim.exhaustParticles) {
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
  bool shouldRepaint(covariant _ExhaustPainter old) => false;
}

class _RocketPainter extends CustomPainter {
  final _RocketSim sim;

  _RocketPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = sim.rocketY * size.height;
    final wobble = sin(sim.time * 2 * pi * 8) * sim.turbulence * 3;

    canvas.save();
    canvas.translate(cx + wobble, cy);

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE0E0FF), Color(0xFF8888CC)],
      ).createShader(const Rect.fromLTWH(-12, -30, 24, 60));
    final body = Path()
      ..moveTo(0, -30)
      ..quadraticBezierTo(14, -10, 12, 20)
      ..lineTo(-12, 20)
      ..quadraticBezierTo(-14, -10, 0, -30);
    canvas.drawPath(body, bodyPaint);

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

    canvas.drawCircle(
      const Offset(0, -28),
      3,
      Paint()..color = const Color(0xFFFFD700),
    );

    if (sim.rocketBoost > 0.05) {
      final flameLen = 15.0 + sim.rocketBoost * 20;
      final flameWidth = 8.0 + sin(sim.time * 2 * pi * 12) * 3;
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
  bool shouldRepaint(covariant _RocketPainter old) => false;
}

class _TilesPainter extends CustomPainter {
  final _RocketSim sim;
  final String currentWord;
  final int letterIndex;

  _TilesPainter({
    required this.sim,
    required this.currentWord,
    required this.letterIndex,
  }) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in sim.tiles) {
      if (t.used) continue;

      final floatX =
          (t.x + sin(sim.time * 2 * pi * t.speed + t.phase) * 0.03) * size.width;
      final floatY =
          (t.y + cos(sim.time * 2 * pi * t.speed * 0.7 + t.phase) * 0.02) *
              size.height;

      final isNext = letterIndex < currentWord.length &&
          t.letter == currentWord[letterIndex];

      if (isNext) {
        canvas.drawCircle(
          Offset(floatX, floatY),
          28,
          Paint()
            ..color = AppColors.electricBlue.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }

      final tileRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(floatX, floatY), width: 52, height: 52),
        const Radius.circular(14),
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
  bool shouldRepaint(covariant _TilesPainter old) =>
      old.currentWord != currentWord || old.letterIndex != letterIndex;
}

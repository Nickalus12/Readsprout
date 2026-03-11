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
// Word Ninja -- fruit-ninja style, tap/swipe correct words flying upward
// ---------------------------------------------------------------------------

class WordNinjaGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const WordNinjaGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<WordNinjaGame> createState() => _WordNinjaGameState();
}

class _WordNinjaGameState extends State<WordNinjaGame>
    with TickerProviderStateMixin {
  static const _gameId = 'word_ninja';
  static const _gameDuration = 45; // seconds
  static const _lives = 3;

  final _rng = Random();

  // Word data
  List<String> _wordPool = [];
  String _targetWord = '';

  // Flying words
  final List<_FlyingWord> _flyingWords = [];
  final List<_InkSplash> _splashes = [];

  // State
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _livesLeft = _lives;
  int _timeLeft = _gameDuration;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Timers
  Timer? _clockTimer;
  Timer? _spawnTimer;

  // Animations
  late AnimationController _gameLoop;
  late AnimationController _completionController;

  @override
  void initState() {
    super.initState();

    _gameLoop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _gameLoop.addListener(_update);

    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _initGame();
  }

  void _initGame() {
    final unlocked = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        for (final w in DolchWords.wordsForLevel(level)) {
          unlocked.add(w.text);
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

    _pickNewTarget();
    _startTimers();
  }

  void _pickNewTarget() {
    _targetWord = _wordPool[_rng.nextInt(_wordPool.length)];
    widget.audioService.playWord(_targetWord);
  }

  void _startTimers() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) _endGame();
      });
    });

    _spawnTimer?.cancel();
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted || _gameOver) return;
      _spawnWords();
    });

    // Initial spawn
    _spawnWords();
  }

  void _spawnWords() {
    // Spawn 2-4 words at a time, one is the target
    final count = 2 + _rng.nextInt(3);
    final includeTarget = _rng.nextDouble() < 0.7;

    final words = <String>[];
    if (includeTarget) words.add(_targetWord);

    while (words.length < count) {
      final w = _wordPool[_rng.nextInt(_wordPool.length)];
      if (w != _targetWord && !words.contains(w)) words.add(w);
    }
    words.shuffle(_rng);

    for (int i = 0; i < words.length; i++) {
      final startX = 0.15 + _rng.nextDouble() * 0.7;
      _flyingWords.add(_FlyingWord(
        word: words[i],
        isTarget: words[i] == _targetWord,
        x: startX,
        y: 1.15,
        vx: (_rng.nextDouble() - 0.5) * 0.002,
        vy: -(0.005 + _rng.nextDouble() * 0.003),
        rotation: (_rng.nextDouble() - 0.5) * 0.04,
        size: 0.9 + _rng.nextDouble() * 0.3,
      ));
    }
  }

  void _update() {
    if (_gameOver || !mounted) return;

    setState(() {
      for (final w in _flyingWords) {
        w.x += w.vx;
        w.y += w.vy;
        w.vy += 0.00008; // gravity
        w.angle += w.rotation;
        w.life -= 0.005;
      }

      // Remove words that fell below screen or expired
      _flyingWords.removeWhere((w) => w.y > 1.3 || w.life <= 0);

      // Update splashes
      for (final s in _splashes) {
        s.life -= 0.03;
        s.radius += 2;
      }
      _splashes.removeWhere((s) => s.life <= 0);
    });
  }

  void _onTapWord(int index) {
    if (_gameOver) return;
    final word = _flyingWords[index];
    if (word.hit) return;

    word.hit = true;

    // Add ink splash
    _splashes.add(_InkSplash(
      x: word.x,
      y: word.y,
      color: word.isTarget
          ? AppColors.success
          : AppColors.error,
      radius: 20,
      life: 1.0,
    ));

    if (word.isTarget) {
      // Correct!
      Haptics.success();
      widget.audioService.playSuccess();
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      final points = 10 + (_combo - 1) * 5;
      _score += points;

      // Remove this word and pick new target
      _flyingWords.removeAt(index);
      _pickNewTarget();
    } else {
      // Wrong word
      Haptics.wrong();
      widget.audioService.playError();
      _combo = 0;
      _livesLeft--;
      _flyingWords.removeAt(index);

      if (_livesLeft <= 0) {
        _endGame();
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _endGame() async {
    _gameOver = true;
    _clockTimer?.cancel();
    _spawnTimer?.cancel();
    _gameLoop.stop();

    final isNewBest = await widget.highScoreService.saveScore(
      _gameId,
      _score,
      widget.playerName,
    );

    if (mounted) {
      setState(() => _isNewBest = isNewBest);
      widget.audioService.playLevelCompleteEffect();
      _completionController.forward(from: 0.0);
    }
  }

  void _restart() {
    _completionController.reset();
    _flyingWords.clear();
    _splashes.clear();
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _livesLeft = _lives;
    _timeLeft = _gameDuration;
    _gameOver = false;
    _isNewBest = false;

    _gameLoop.repeat();
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _spawnTimer?.cancel();
    _gameLoop.removeListener(_update);
    _gameLoop.dispose();
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
            colors: [Color(0xFF1A0A2E), Color(0xFF0A0A1A)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Game area
              AnimatedBuilder(
                animation: _gameLoop,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final dx =
                              details.localPosition.dx / constraints.maxWidth;
                          final dy =
                              details.localPosition.dy / constraints.maxHeight;
                          // Find closest word
                          for (int i = _flyingWords.length - 1; i >= 0; i--) {
                            final w = _flyingWords[i];
                            if (w.hit) continue;
                            if ((dx - w.x).abs() < 0.08 &&
                                (dy - w.y).abs() < 0.06) {
                              _onTapWord(i);
                              return;
                            }
                          }
                        },
                        child: CustomPaint(
                          painter: _NinjaPainter(
                            words: _flyingWords,
                            splashes: _splashes,
                            targetWord: _targetWord,
                          ),
                          size: Size(
                              constraints.maxWidth, constraints.maxHeight),
                        ),
                      );
                    },
                  );
                },
              ),

              // UI overlay
              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildTargetDisplay(),
                  const Spacer(),
                  if (_gameOver) _buildGameOver(),
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
              'Word Ninja',
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
                  size: 18,
                  color: i < _livesLeft
                      ? AppColors.error
                      : AppColors.secondaryText.withValues(alpha: 0.3),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_timeLeft <= 10
                      ? AppColors.error
                      : AppColors.violet)
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_timeLeft}s',
              style: AppFonts.fredoka(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color:
                    _timeLeft <= 10 ? AppColors.error : AppColors.violet,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.starGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
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

  Widget _buildTargetDisplay() {
    return GestureDetector(
      onTap: () => widget.audioService.playWord(_targetWord),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.magenta.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volume_up_rounded,
                color: AppColors.magenta, size: 20),
            const SizedBox(width: 8),
            Text(
              'Slash: "$_targetWord"',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            if (_combo > 1) ...[
              const SizedBox(width: 12),
              Text(
                'x$_combo',
                style: AppFonts.fredoka(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.starGold,
                ),
              ),
            ],
          ],
        ),
      ),
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
            child: Container(
              margin: const EdgeInsets.all(32),
              padding:
                  const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.magenta.withValues(alpha: 0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.magenta.withValues(alpha: 0.15),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Time Up!',
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
                    'Max combo: x$_maxCombo',
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
                      backgroundColor: AppColors.magenta,
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
        );
      },
    );
  }
}

// ---- Data ----

class _FlyingWord {
  final String word;
  final bool isTarget;
  double x, y, vx, vy;
  double rotation;
  double angle = 0;
  double size;
  double life = 1.0;
  bool hit = false;

  _FlyingWord({
    required this.word,
    required this.isTarget,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.size,
  });
}

class _InkSplash {
  final double x, y;
  final Color color;
  double radius;
  double life;

  _InkSplash({
    required this.x,
    required this.y,
    required this.color,
    required this.radius,
    required this.life,
  });
}

// ---- Painter ----

class _NinjaPainter extends CustomPainter {
  final List<_FlyingWord> words;
  final List<_InkSplash> splashes;
  final String targetWord;

  _NinjaPainter({
    required this.words,
    required this.splashes,
    required this.targetWord,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw ink splashes
    for (final s in splashes) {
      final center = Offset(s.x * size.width, s.y * size.height);
      canvas.drawCircle(
        center,
        s.radius,
        Paint()
          ..color = s.color.withValues(alpha: (s.life * 0.5).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.radius * 0.5),
      );
    }

    // Draw flying words
    for (final w in words) {
      if (w.hit) continue;

      final cx = w.x * size.width;
      final cy = w.y * size.height;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(w.angle);

      // Word pill background
      final bgColor = w.isTarget
          ? AppColors.magenta.withValues(alpha: 0.8)
          : AppColors.surface.withValues(alpha: 0.9);
      final borderColor = w.isTarget
          ? AppColors.magenta
          : AppColors.border;

      final textPainter = TextPainter(
        text: TextSpan(
          text: w.word,
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 18 * w.size,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillWidth = textPainter.width + 28;
      final pillHeight = textPainter.height + 14;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset.zero, width: pillWidth, height: pillHeight),
        const Radius.circular(14),
      );
      canvas.drawRRect(rect, Paint()..color = bgColor);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = borderColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Glow for target words
      if (w.isTarget) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = AppColors.magenta.withValues(alpha: 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }

      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _NinjaPainter old) => true;
}

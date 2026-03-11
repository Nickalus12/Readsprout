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
// Word Train -- drag letters to train cars to spell words
// ---------------------------------------------------------------------------

class WordTrainGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const WordTrainGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<WordTrainGame> createState() => _WordTrainGameState();
}

class _WordTrainGameState extends State<WordTrainGame>
    with TickerProviderStateMixin {
  static const _gameId = 'word_train';
  static const _totalWords = 8;

  final _rng = Random();

  // Words
  List<String> _wordPool = [];
  String _currentWord = '';
  int _wordsCompleted = 0;

  // Train state
  double _trainX = -0.3; // train position (fraction of screen)
  List<String?> _trainCars = []; // filled letters in each car
  int _nextCarIndex = 0;

  // Station letters
  List<_StationLetter> _stationLetters = [];
  int? _draggingIndex;
  Offset _dragOffset = Offset.zero;

  // Score
  int _score = 0;
  int _streak = 0;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Timer
  late Stopwatch _wordTimer;

  // Animations
  late AnimationController _trainMoveController;
  late AnimationController _chugController;
  late AnimationController _completionController;
  late AnimationController _smokeController;

  // Smoke particles
  final List<_SmokeParticle> _smokeParticles = [];

  // Track segments (decorative)
  late List<_TrackSegment> _tracks;

  @override
  void initState() {
    super.initState();
    _wordTimer = Stopwatch();

    _trainMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _chugController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _smokeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _smokeController.addListener(_updateSmoke);

    _tracks = List.generate(20, (i) => _TrackSegment(i));

    _initGame();
  }

  void _initGame() {
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
    if (unlocked.length < 8) {
      for (final w in DolchWords.wordsForLevel(1)) {
        unlocked.add(w.text);
      }
    }
    unlocked.shuffle(_rng);
    _wordPool = unlocked;
    _wordsCompleted = 0;
    _score = 0;
    _streak = 0;
    _gameOver = false;
    _isNewBest = false;

    _nextWord();
  }

  void _nextWord() {
    if (_wordsCompleted >= _totalWords) {
      _endGame();
      return;
    }

    _currentWord = _wordPool[_wordsCompleted % _wordPool.length];
    _trainCars = List.filled(_currentWord.length, null);
    _nextCarIndex = 0;
    _trainX = -0.1;
    _wordTimer.reset();
    _wordTimer.start();

    // Create station letters
    final needed = _currentWord.split('');
    final distractors = <String>[];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    while (distractors.length < 3) {
      final c = alphabet[_rng.nextInt(26)];
      if (!needed.contains(c) && !distractors.contains(c)) {
        distractors.add(c);
      }
    }

    final all = [...needed, ...distractors];
    all.shuffle(_rng);

    _stationLetters = all.asMap().entries.map((e) {
      return _StationLetter(
        letter: e.value,
        originalIndex: e.key,
      );
    }).toList();

    widget.audioService.playWord(_currentWord);
    if (mounted) setState(() {});
  }

  void _updateSmoke() {
    if (!mounted || _gameOver) return;

    setState(() {
      // Add smoke from chimney
      if (_smokeParticles.length < 8) {
        _smokeParticles.add(_SmokeParticle(
          x: _trainX + 0.02,
          y: 0.35,
          vx: 0.0005 + _rng.nextDouble() * 0.001,
          vy: -(0.001 + _rng.nextDouble() * 0.002),
          life: 1.0,
          size: 4 + _rng.nextDouble() * 6,
        ));
      }

      for (final p in _smokeParticles) {
        p.x += p.vx;
        p.y += p.vy;
        p.life -= 0.015;
        p.size += 0.3;
      }
      _smokeParticles.removeWhere((p) => p.life <= 0);
    });
  }

  void _onLetterDragStart(int index) {
    if (_gameOver) return;
    final letter = _stationLetters[index];
    if (letter.used) return;
    setState(() {
      _draggingIndex = index;
    });
  }

  void _onLetterDragUpdate(DragUpdateDetails details) {
    if (_draggingIndex == null) return;
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onLetterDragEnd(DragEndDetails details) {
    if (_draggingIndex == null) return;

    // Check if dropped near the train car area
    // The train cars are in the upper half of the screen
    // We accept the drop if the drag went upward enough
    final letter = _stationLetters[_draggingIndex!];
    final expected =
        _nextCarIndex < _currentWord.length ? _currentWord[_nextCarIndex] : '';

    if (_dragOffset.dy < -40 && letter.letter == expected) {
      // Correct drop!
      Haptics.correct();
      widget.audioService.playLetter(letter.letter);
      _chugController.forward(from: 0.0);

      setState(() {
        _trainCars[_nextCarIndex] = letter.letter;
        letter.used = true;
        _nextCarIndex++;
        // Move train forward a bit
        _trainX += 0.08;
      });

      if (_nextCarIndex >= _currentWord.length) {
        _onWordComplete();
      }
    } else if (_dragOffset.dy < -40) {
      // Wrong letter dropped
      Haptics.wrong();
      widget.audioService.playError();
      setState(() => _streak = 0);
    }

    setState(() {
      _draggingIndex = null;
      _dragOffset = Offset.zero;
    });
  }

  void _onWordComplete() {
    _wordTimer.stop();
    _streak++;
    final speedBonus = max(0, (6000 - _wordTimer.elapsedMilliseconds) ~/ 100);
    final streakBonus = (_streak - 1) * 5;
    final wordScore = 10 + speedBonus + streakBonus;

    widget.audioService.playSuccess();
    Haptics.success();

    setState(() {
      _score += wordScore;
      _wordsCompleted++;
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && !_gameOver) _nextWord();
    });
  }

  Future<void> _endGame() async {
    _gameOver = true;
    _smokeController.stop();

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
    _smokeParticles.clear();
    _smokeController.repeat();
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _trainMoveController.dispose();
    _chugController.dispose();
    _completionController.dispose();
    _smokeController.removeListener(_updateSmoke);
    _smokeController.dispose();
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
            colors: [Color(0xFF1A2A3A), Color(0xFF0A1520)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (!_gameOver) _buildWordProgress(),
              if (!_gameOver) Expanded(flex: 3, child: _buildTrainArea()),
              if (!_gameOver)
                Expanded(flex: 2, child: _buildStationLetters()),
              if (_gameOver) Expanded(child: _buildGameOver()),
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
              'Word Train',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
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

  Widget _buildWordProgress() {
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
          GestureDetector(
            onTap: () => widget.audioService.playWord(_currentWord),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_up_rounded,
                    color: AppColors.electricBlue, size: 20),
                const SizedBox(width: 6),
                Text(
                  '"$_currentWord"',
                  style: AppFonts.fredoka(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
          if (_streak > 1)
            Text(
              'Streak x$_streak',
              style: AppFonts.fredoka(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.starGold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrainArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _smokeController,
          builder: (context, _) {
            return CustomPaint(
              painter: _TrainPainter(
                trainX: _trainX,
                cars: _trainCars,
                currentWord: _currentWord,
                nextCarIndex: _nextCarIndex,
                smokeParticles: _smokeParticles,
                tracks: _tracks,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        );
      },
    );
  }

  Widget _buildStationLetters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: AppColors.electricBlue.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Drag letters to the train',
            style: AppFonts.nunito(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_stationLetters.length, (i) {
                final letter = _stationLetters[i];
                if (letter.used) {
                  return SizedBox(
                    width: 52,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: AppColors.success.withValues(alpha: 0.5),
                          size: 20,
                        ),
                      ),
                    ),
                  );
                }

                final isDragging = _draggingIndex == i;
                return GestureDetector(
                  onPanStart: (_) => _onLetterDragStart(i),
                  onPanUpdate: _onLetterDragUpdate,
                  onPanEnd: _onLetterDragEnd,
                  child: Transform.translate(
                    offset: isDragging ? _dragOffset : Offset.zero,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDragging
                            ? AppColors.electricBlue.withValues(alpha: 0.2)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDragging
                              ? AppColors.electricBlue
                              : AppColors.border,
                          width: isDragging ? 2 : 1,
                        ),
                        boxShadow: isDragging
                            ? [
                                BoxShadow(
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          letter.letter,
                          style: AppFonts.fredoka(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isDragging
                                ? AppColors.electricBlue
                                : AppColors.primaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
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
                      'All Aboard!',
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
                      '$_wordsCompleted words completed',
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

// ---- Data ----

class _StationLetter {
  final String letter;
  final int originalIndex;
  bool used = false;

  _StationLetter({required this.letter, required this.originalIndex});
}

class _SmokeParticle {
  double x, y, vx, vy, life, size;

  _SmokeParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
  });
}

class _TrackSegment {
  final int index;
  _TrackSegment(this.index);
}

// ---- Painters ----

class _TrainPainter extends CustomPainter {
  final double trainX;
  final List<String?> cars;
  final String currentWord;
  final int nextCarIndex;
  final List<_SmokeParticle> smokeParticles;
  final List<_TrackSegment> tracks;

  _TrainPainter({
    required this.trainX,
    required this.cars,
    required this.currentWord,
    required this.nextCarIndex,
    required this.smokeParticles,
    required this.tracks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height * 0.75;

    // Draw tracks
    final trackPaint = Paint()
      ..color = const Color(0xFF4A3520).withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      trackPaint,
    );
    // Rail ties
    final tiePaint = Paint()
      ..color = const Color(0xFF4A3520).withValues(alpha: 0.3)
      ..strokeWidth = 2;
    for (int i = 0; i < 30; i++) {
      final x = i * size.width / 30;
      canvas.drawLine(
        Offset(x, trackY - 4),
        Offset(x, trackY + 4),
        tiePaint,
      );
    }

    // Draw smoke
    for (final p in smokeParticles) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        Paint()
          ..color = Colors.white
              .withValues(alpha: (p.life * 0.3).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size),
      );
    }

    // Draw engine
    final engineX = trainX * size.width;
    final engineY = trackY - 35;

    // Engine body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(engineX, engineY, 50, 30),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFCC3333),
    );
    // Cabin
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(engineX + 30, engineY - 15, 20, 15),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFDD4444),
    );
    // Window
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(engineX + 34, engineY - 12, 12, 8),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF88CCFF).withValues(alpha: 0.7),
    );
    // Chimney
    canvas.drawRect(
      Rect.fromLTWH(engineX + 8, engineY - 12, 8, 12),
      Paint()..color = const Color(0xFF2A2A2A),
    );
    // Wheels
    canvas.drawCircle(
      Offset(engineX + 12, trackY - 2),
      8,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    canvas.drawCircle(
      Offset(engineX + 38, trackY - 2),
      8,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    // Wheel centers
    canvas.drawCircle(
      Offset(engineX + 12, trackY - 2),
      3,
      Paint()..color = const Color(0xFF666666),
    );
    canvas.drawCircle(
      Offset(engineX + 38, trackY - 2),
      3,
      Paint()..color = const Color(0xFF666666),
    );

    // Draw train cars
    const carWidth = 44.0;
    const carSpacing = 8.0;
    for (int i = 0; i < cars.length; i++) {
      final carX = engineX + 55 + i * (carWidth + carSpacing);
      final carY = trackY - 30;
      final filled = cars[i] != null;
      final isNext = i == nextCarIndex;

      // Coupling
      canvas.drawLine(
        Offset(carX - carSpacing, trackY - 15),
        Offset(carX, trackY - 15),
        Paint()
          ..color = const Color(0xFF666666)
          ..strokeWidth = 2,
      );

      // Car body
      final carColor = filled
          ? AppColors.success.withValues(alpha: 0.3)
          : isNext
              ? AppColors.electricBlue.withValues(alpha: 0.15)
              : AppColors.surface;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(carX, carY, carWidth, 26),
          const Radius.circular(5),
        ),
        Paint()..color = carColor,
      );
      // Car border
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(carX, carY, carWidth, 26),
          const Radius.circular(5),
        ),
        Paint()
          ..color = isNext
              ? AppColors.electricBlue.withValues(alpha: 0.6)
              : filled
                  ? AppColors.success.withValues(alpha: 0.5)
                  : AppColors.border.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNext ? 2 : 1,
      );

      // Glow for next car
      if (isNext) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(carX - 2, carY - 2, carWidth + 4, 30),
            const Radius.circular(7),
          ),
          Paint()
            ..color = AppColors.electricBlue.withValues(alpha: 0.1)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Letter in car
      if (filled) {
        final tp = TextPainter(
          text: TextSpan(
            text: cars[i],
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
              carX + carWidth / 2 - tp.width / 2, carY + 13 - tp.height / 2),
        );
      } else if (isNext) {
        final tp = TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.electricBlue.withValues(alpha: 0.5),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
              carX + carWidth / 2 - tp.width / 2, carY + 13 - tp.height / 2),
        );
      }

      // Car wheels
      canvas.drawCircle(
        Offset(carX + 10, trackY - 2),
        5,
        Paint()..color = const Color(0xFF2A2A2A),
      );
      canvas.drawCircle(
        Offset(carX + carWidth - 10, trackY - 2),
        5,
        Paint()..color = const Color(0xFF2A2A2A),
      );
    }

    // Ground / scenery
    canvas.drawRect(
      Rect.fromLTWH(0, trackY + 5, size.width, size.height - trackY - 5),
      Paint()..color = const Color(0xFF1A3020).withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _TrainPainter old) => true;
}

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
// Spelling Bee Hive -- tap honeycomb hex letters to spell the word
// ---------------------------------------------------------------------------

class SpellingBeeGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const SpellingBeeGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<SpellingBeeGame> createState() => _SpellingBeeGameState();
}

class _SpellingBeeGameState extends State<SpellingBeeGame>
    with TickerProviderStateMixin {
  static const _gameId = 'spelling_bee';
  static const _totalWords = 10;

  final _rng = Random();

  // Words
  List<String> _wordPool = [];
  String _currentWord = '';
  int _letterIndex = 0;
  int _wordsCompleted = 0;

  // Hex grid
  List<_HexCell> _hexCells = [];

  // Score
  int _score = 0;
  int _streak = 0;
  int _mistakes = 0;
  bool _gameOver = false;
  bool _isNewBest = false;
  bool _showingStartOverlay = true;

  // Timer
  late Stopwatch _wordTimer;

  // Animations
  late AnimationController _honeyDripController;
  late Animation<double> _honeyDrip;
  late AnimationController _shakeController;
  late AnimationController _beeController;
  late AnimationController _completionController;

  // Bee positions (decorative)
  late List<_Bee> _bees;

  @override
  void initState() {
    super.initState();
    _wordTimer = Stopwatch();

    _honeyDripController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _honeyDrip = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _honeyDripController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _beeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _bees = List.generate(3, (_) => _Bee(_rng));

    _initGame();
  }

  void _initGame() {
    final unlocked = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        for (final w in DolchWords.wordsForLevel(level)) {
          if (w.text.length >= 2 && w.text.length <= 7) {
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
    _wordsCompleted = 0;
    _score = 0;
    _streak = 0;
    _mistakes = 0;
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
    _letterIndex = 0;
    _wordTimer.reset();
    _wordTimer.start();

    // Build hex grid with needed letters + distractors
    final needed = _currentWord.split('');
    final distractors = <String>[];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';

    // Add enough distractors to fill a nice hex grid
    final targetCount = max(7, needed.length + 4);
    while (distractors.length + needed.length < targetCount) {
      final c = alphabet[_rng.nextInt(26)];
      if (!distractors.contains(c)) {
        distractors.add(c);
      }
    }

    final allLetters = [...needed, ...distractors];
    allLetters.shuffle(_rng);

    // Generate hex positions in a honeycomb pattern
    _hexCells = [];
    final rows = _hexLayout(allLetters.length);
    int idx = 0;
    for (int row = 0; row < rows.length && idx < allLetters.length; row++) {
      final count = rows[row];
      for (int col = 0; col < count && idx < allLetters.length; col++) {
        _hexCells.add(_HexCell(
          letter: allLetters[idx],
          row: row,
          col: col,
          colsInRow: count,
        ));
        idx++;
      }
    }

    widget.audioService.playWord(_currentWord);
    if (mounted) setState(() {});
  }

  List<int> _hexLayout(int total) {
    // Honeycomb pattern: rows of alternating sizes
    if (total <= 3) return [total];
    if (total <= 5) return [2, 3];
    if (total <= 7) return [2, 3, 2];
    if (total <= 10) return [3, 4, 3];
    if (total <= 12) return [3, 4, 3, 2];
    return [3, 4, 3, 4]; // up to 14
  }

  void _dismissStartOverlay() {
    setState(() => _showingStartOverlay = false);
  }

  void _onHexTap(int index) {
    if (_gameOver || _showingStartOverlay) return;
    final cell = _hexCells[index];
    if (cell.state != _CellState.idle) return;

    final expected = _currentWord[_letterIndex];
    if (cell.letter == expected) {
      // Correct
      Haptics.correct();
      widget.audioService.playLetter(cell.letter);
      _honeyDripController.forward(from: 0.0);

      setState(() {
        cell.state = _CellState.correct;
        _letterIndex++;
      });

      if (_letterIndex >= _currentWord.length) {
        _onWordComplete();
      }
    } else {
      // Wrong - gentle feedback only
      Haptics.wrong();
      _shakeController.forward(from: 0.0);
      setState(() {
        _mistakes++;
        _streak = 0;
      });
    }
  }

  void _onWordComplete() {
    _wordTimer.stop();
    _streak++;

    final speedBonus = max(0, (5000 - _wordTimer.elapsedMilliseconds) ~/ 100);
    final streakBonus = (_streak - 1) * 5;
    final accuracyBonus = _mistakes == 0 ? 10 : 0;
    final wordScore = 10 + speedBonus + streakBonus + accuracyBonus;

    widget.audioService.playSuccess();
    Haptics.success();

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
    _showingStartOverlay = false;
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _honeyDripController.dispose();
    _shakeController.dispose();
    _beeController.dispose();
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
            colors: [Color(0xFF2A1A00), Color(0xFF1A1000)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative bees
              AnimatedBuilder(
                animation: _beeController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _BeePainter(
                      bees: _bees,
                      time: _beeController.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),

              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildWordDisplay(),
                  if (!_gameOver) Expanded(child: _buildHexGrid()),
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
      onTap: _dismissStartOverlay,
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
                color: AppColors.starGold.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u{1F41D}',
                  style: AppFonts.fredoka(fontSize: 40),
                ),
                const SizedBox(height: 8),
                Text(
                  'Spelling Bee',
                  style: AppFonts.fredoka(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                // Visual hint: listen icon + hex letters
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        color: AppColors.starGold, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      '"cat"',
                      style: AppFonts.fredoka(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.starGold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: AppColors.secondaryText, size: 18),
                    const SizedBox(width: 8),
                    _buildHintHex('c'),
                    const SizedBox(width: 4),
                    _buildHintHex('a'),
                    const SizedBox(width: 4),
                    _buildHintHex('t'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Listen, then tap the letters\nin order to spell it!',
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
                    color: AppColors.starGold,
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

  Widget _buildHintHex(String letter) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.starGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.starGold.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Text(
          letter,
          style: AppFonts.fredoka(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.starGold,
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
              'Spelling Bee',
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

  Widget _buildWordDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            'Word ${_wordsCompleted + 1} of $_totalWords',
            style: AppFonts.nunito(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => widget.audioService.playWord(_currentWord),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.starGold.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_up_rounded,
                      color: AppColors.starGold, size: 22),
                  const SizedBox(width: 8),
                  // Show spelled letters
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_currentWord.length, (i) {
                      final revealed = i < _letterIndex;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 28,
                        height: 36,
                        decoration: BoxDecoration(
                          color: revealed
                              ? AppColors.starGold.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: i == _letterIndex
                                ? AppColors.starGold
                                : revealed
                                    ? AppColors.starGold
                                        .withValues(alpha: 0.5)
                                    : AppColors.border,
                            width: i == _letterIndex ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            revealed ? _currentWord[i] : '',
                            style: AppFonts.fredoka(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.starGold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          if (_streak > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Streak x$_streak',
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

  Widget _buildHexGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hexSize = min(constraints.maxWidth / 5.5, 72.0).clamp(48.0, 72.0);
        final hexH = hexSize * 0.866; // sqrt(3)/2

        // Calculate grid dimensions
        final rows = _hexLayout(_hexCells.length);
        final gridHeight = rows.length * hexH * 1.1;
        final startY = (constraints.maxHeight - gridHeight) / 2;

        return Stack(
          children: List.generate(_hexCells.length, (i) {
            final cell = _hexCells[i];
            final rowOffset =
                cell.colsInRow.isEven ? hexSize * 0.5 : 0.0;
            final totalRowWidth =
                cell.colsInRow * hexSize * 1.1;
            final rowStartX =
                (constraints.maxWidth - totalRowWidth) / 2 + rowOffset;

            final x = rowStartX + cell.col * hexSize * 1.1;
            final y = startY + cell.row * hexH * 1.1;

            return Positioned(
              left: x,
              top: y,
              child: GestureDetector(
                onTap: () => _onHexTap(i),
                child: AnimatedBuilder(
                  animation: _honeyDrip,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _HexPainter(
                        letter: cell.letter,
                        state: cell.state,
                        isNext: _letterIndex < _currentWord.length &&
                            cell.letter == _currentWord[_letterIndex] &&
                            cell.state == _CellState.idle,
                        honeyProgress: cell.state == _CellState.correct
                            ? _honeyDrip.value
                            : 0.0,
                      ),
                      size: Size(hexSize, hexSize),
                    );
                  },
                ),
              ),
            );
          }),
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
                    color: AppColors.starGold.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Hive Complete!',
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
                      '$_wordsCompleted words, $_mistakes mistakes',
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
                        backgroundColor: AppColors.starGold,
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

enum _CellState { idle, correct }

class _HexCell {
  final String letter;
  final int row;
  final int col;
  final int colsInRow;
  _CellState state = _CellState.idle;

  _HexCell({
    required this.letter,
    required this.row,
    required this.col,
    required this.colsInRow,
  });
}

class _Bee {
  final double x, y, speed, phase;

  _Bee(Random rng)
      : x = rng.nextDouble(),
        y = 0.05 + rng.nextDouble() * 0.3,
        speed = 0.5 + rng.nextDouble() * 0.5,
        phase = rng.nextDouble() * 2 * pi;
}

// ---- Painters ----

class _HexPainter extends CustomPainter {
  final String letter;
  final _CellState state;
  final bool isNext;
  final double honeyProgress;

  _HexPainter({
    required this.letter,
    required this.state,
    required this.isNext,
    required this.honeyProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.45;

    // Draw hexagon
    final hexPath = _hexPath(cx, cy, r);

    // Fill
    final isGolden = state == _CellState.correct;
    final fillColor = isGolden
        ? const Color(0xFFFFD700).withValues(alpha: 0.3)
        : isNext
            ? AppColors.starGold.withValues(alpha: 0.1)
            : const Color(0xFF3A2800).withValues(alpha: 0.6);
    canvas.drawPath(hexPath, Paint()..color = fillColor);

    // Border
    final borderColor = isGolden
        ? AppColors.starGold
        : isNext
            ? AppColors.starGold.withValues(alpha: 0.7)
            : const Color(0xFF8B6914).withValues(alpha: 0.5);
    canvas.drawPath(
      hexPath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isGolden || isNext ? 2.5 : 1.5,
    );

    // Glow for golden
    if (isGolden) {
      canvas.drawPath(
        hexPath,
        Paint()
          ..color = AppColors.starGold.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Honey drip effect
    if (isGolden && honeyProgress > 0) {
      final dripY = cy + r + honeyProgress * 8;
      canvas.drawCircle(
        Offset(cx, dripY),
        3 * honeyProgress,
        Paint()..color = AppColors.starGold.withValues(alpha: 0.5),
      );
    }

    // Letter
    final textColor = isGolden
        ? AppColors.starGold
        : isNext
            ? AppColors.starGold.withValues(alpha: 0.9)
            : AppColors.primaryText;

    final tp = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: r * 0.8,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  Path _hexPath(double cx, double cy, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * pi / 180;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.state != state ||
      old.isNext != isNext ||
      old.honeyProgress != honeyProgress;
}

class _BeePainter extends CustomPainter {
  final List<_Bee> bees;
  final double time;

  _BeePainter({required this.bees, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final bee in bees) {
      final t = time * bee.speed + bee.phase;
      final bx = (bee.x + sin(t * 2 * pi) * 0.08) * size.width;
      final by = (bee.y + cos(t * 2 * pi * 0.6) * 0.04) * size.height;

      // Body
      canvas.drawOval(
        Rect.fromCenter(center: Offset(bx, by), width: 14, height: 10),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.7),
      );
      // Stripes
      canvas.drawLine(
        Offset(bx - 2, by - 4),
        Offset(bx - 2, by + 4),
        Paint()
          ..color = const Color(0xFF2A1A00).withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(bx + 2, by - 3),
        Offset(bx + 2, by + 3),
        Paint()
          ..color = const Color(0xFF2A1A00).withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
      // Wings
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(bx - 3, by - 6), width: 8, height: 5),
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(bx + 3, by - 6), width: 8, height: 5),
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BeePainter old) => true;
}

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
// Train starts on the RIGHT and chugs LEFT as words fuel it forward.
// ---------------------------------------------------------------------------

class _TrainSim extends ChangeNotifier {
  final List<_SmokeParticle> smokeParticles = [];
  double trainX = 0.95;
  bool chugBurst = false;

  final _rng = Random();

  double _trainWidthFraction = 0.05;

  void updateTrainWidth(int carCount) {
    _trainWidthFraction = 0.05 + carCount * 0.04;
  }

  void tick() {
    final maxParticles = chugBurst ? 16 : 8;
    if (smokeParticles.length < maxParticles) {
      smokeParticles.add(_SmokeParticle(
        x: trainX - _trainWidthFraction + 0.02,
        y: 0.30,
        vx: 0.0005 + _rng.nextDouble() * 0.002,
        vy: -(0.001 + _rng.nextDouble() * 0.003),
        life: 1.0,
        size: (chugBurst ? 6 : 4) + _rng.nextDouble() * 6,
      ));
    }

    for (final p in smokeParticles) {
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.015;
      p.size += 0.3;
    }
    smokeParticles.removeWhere((p) => p.life <= 0);

    notifyListeners();
  }

  /// Notify painters that train state changed (safe to call externally).
  void markDirty() => notifyListeners();

  void reset() {
    smokeParticles.clear();
    trainX = 0.95;
    chugBurst = false;
  }
}

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
  final _sim = _TrainSim();

  // Words
  List<String> _wordPool = [];
  String _currentWord = '';
  int _wordsCompleted = 0;

  // Train state
  double _trainXTarget = 0.95;
  List<String?> _trainCars = [];
  int _nextCarIndex = 0;

  // Fuel gauge
  double _fuelLevel = 0.0;

  // Station letters
  List<_StationLetter> _stationLetters = [];
  int? _draggingIndex;
  Offset _dragOffset = Offset.zero;

  // Score
  int _score = 0;
  int _streak = 0;
  bool _gameOver = false;
  bool _isNewBest = false;
  bool _showingStartOverlay = true;

  // Timer
  late Stopwatch _wordTimer;

  // Animations
  late AnimationController _trainMoveController;
  late Animation<double> _trainMoveAnim;
  late AnimationController _chugController;
  late AnimationController _completionController;
  late AnimationController _smokeController;
  late AnimationController _fuelFlashController;

  @override
  void initState() {
    super.initState();
    _wordTimer = Stopwatch();

    _trainMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _trainMoveAnim = Tween<double>(begin: 0.95, end: 0.95).animate(
      CurvedAnimation(parent: _trainMoveController, curve: Curves.easeInOut),
    );
    _trainMoveController.addListener(() {
      if (mounted) {
        _sim.trainX = _trainMoveAnim.value;
        _sim.markDirty();
      }
    });

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

    _fuelFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

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
    _sim.trainX = 0.95;
    _trainXTarget = 0.95;
    _fuelLevel = 0.0;

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
    _fuelLevel = 0.0;
    _wordTimer.reset();
    _wordTimer.start();
    _sim.updateTrainWidth(_trainCars.length);

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
    _sim.tick();
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

    final letter = _stationLetters[_draggingIndex!];
    final expected =
        _nextCarIndex < _currentWord.length ? _currentWord[_nextCarIndex] : '';

    if (_dragOffset.dy < -40 && letter.letter == expected) {
      Haptics.correct();
      widget.audioService.playLetter(letter.letter);
      _chugController.forward(from: 0.0);

      setState(() {
        _trainCars[_nextCarIndex] = letter.letter;
        letter.used = true;
        _nextCarIndex++;
        _fuelLevel = _nextCarIndex / _currentWord.length;
      });

      _fuelFlashController.forward(from: 0.0);

      if (_nextCarIndex >= _currentWord.length) {
        _onWordComplete();
      }
    } else if (_dragOffset.dy < -40) {
      Haptics.wrong();
      // Gentle feedback - no harsh error sound for young children
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
    _sim.chugBurst = true;

    const chugDistance = (0.95 - 0.10) / _totalWords;
    final oldTarget = _trainXTarget;
    _trainXTarget = (oldTarget - chugDistance).clamp(0.05, 0.95);

    _trainMoveAnim = Tween<double>(begin: _sim.trainX, end: _trainXTarget).animate(
      CurvedAnimation(parent: _trainMoveController, curve: Curves.easeInOut),
    );
    _trainMoveController.forward(from: 0.0);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _sim.chugBurst = false;
      }
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
    _trainMoveController.reset();
    _sim.reset();
    _smokeController.repeat();
    _showingStartOverlay = false;
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _trainMoveController.dispose();
    _chugController.dispose();
    _completionController.dispose();
    _fuelFlashController.dispose();
    _smokeController.removeListener(_updateSmoke);
    _smokeController.dispose();
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
            colors: [Color(0xFF1A2A3A), Color(0xFF0A1520)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildWordProgress(),
                  if (!_gameOver) _buildFuelGauge(),
                  if (!_gameOver) Expanded(flex: 3, child: _buildTrainArea()),
                  if (!_gameOver)
                    Expanded(flex: 2, child: _buildStationLetters()),
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
                color: const Color(0xFF4A90D9).withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u{1F682}',
                  style: AppFonts.fredoka(fontSize: 40),
                ),
                const SizedBox(height: 8),
                Text(
                  'Word Train',
                  style: AppFonts.fredoka(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                // Visual hint: drag letter to train car
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90D9).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              const Color(0xFF4A90D9).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'c',
                          style: AppFonts.fredoka(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4A90D9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        color: AppColors.secondaryText, size: 18),
                    const SizedBox(width: 6),
                    Container(
                      width: 40,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.starGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.starGold.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'c',
                          style: AppFonts.fredoka(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.starGold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Drag letters to the train\ncars to spell words!',
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
                    color: const Color(0xFF4A90D9),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _buildFuelGauge() {
    return AnimatedBuilder(
      animation: _fuelFlashController,
      builder: (context, _) {
        final flash = _fuelFlashController.value;
        final glowAlpha = (0.3 * (1.0 - flash)).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.local_gas_station_rounded,
                size: 18,
                color: _fuelLevel >= 1.0
                    ? AppColors.starGold
                    : AppColors.secondaryText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                    boxShadow: flash > 0.0
                        ? [
                            BoxShadow(
                              color: AppColors.starGold
                                  .withValues(alpha: glowAlpha),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _fuelLevel.clamp(0.0, 1.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _fuelLevel >= 1.0
                                ? [
                                    const Color(0xFFFF8C00),
                                    AppColors.starGold,
                                  ]
                                : [
                                    AppColors.electricBlue,
                                    AppColors.cyan,
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  '${(_fuelLevel * 100).round()}%',
                  style: AppFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _fuelLevel >= 1.0
                        ? AppColors.starGold
                        : AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrainArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: _TrainPainter(
              sim: _sim,
              cars: _trainCars,
              currentWord: _currentWord,
              nextCarIndex: _nextCarIndex,
              wordsCompleted: _wordsCompleted,
              totalWords: _totalWords,
              chugController: _chugController,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
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
            'Drag letters up to fuel the train',
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

// ---- Painters ----

class _TrainPainter extends CustomPainter {
  final _TrainSim sim;
  final List<String?> cars;
  final String currentWord;
  final int nextCarIndex;
  final int wordsCompleted;
  final int totalWords;
  final AnimationController chugController;

  _TrainPainter({
    required this.sim,
    required this.cars,
    required this.currentWord,
    required this.nextCarIndex,
    required this.wordsCompleted,
    required this.totalWords,
    required this.chugController,
  }) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final trainX = sim.trainX;
    final chugBounce = chugController.isAnimating
        ? sin(chugController.value * pi * 4) * 2
        : 0.0;
    final trackY = size.height * 0.75;

    final trackPaint = Paint()
      ..color = const Color(0xFF4A3520).withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      trackPaint,
    );
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

    _drawStation(canvas, size, trackY);

    for (final p in sim.smokeParticles) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        Paint()
          ..color = Colors.white
              .withValues(alpha: (p.life * 0.3).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size),
      );
    }

    const engineWidth = 50.0;
    const cabinWidth = 20.0;
    const carWidth = 44.0;
    const carSpacing = 8.0;

    final totalTrainPx =
        engineWidth + cars.length * (carWidth + carSpacing);

    final engineFrontX = trainX * size.width - totalTrainPx / 2;
    final engineY = trackY - 35 + chugBounce;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(engineFrontX, engineY, engineWidth, 30),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFCC3333),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            engineFrontX + engineWidth - cabinWidth, engineY - 15, cabinWidth, 15),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFDD4444),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            engineFrontX + engineWidth - cabinWidth + 4, engineY - 12, 12, 8),
        const Radius.circular(2),
      ),
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.7),
    );

    canvas.drawRect(
      Rect.fromLTWH(engineFrontX + 6, engineY - 12, 8, 12),
      Paint()..color = const Color(0xFF2A2A2A),
    );

    final cowPath = Path()
      ..moveTo(engineFrontX, engineY + 30)
      ..lineTo(engineFrontX - 8, engineY + 30)
      ..lineTo(engineFrontX, engineY + 20)
      ..close();
    canvas.drawPath(cowPath, Paint()..color = const Color(0xFF999999));

    canvas.drawCircle(
      Offset(engineFrontX + 12, trackY - 2 + chugBounce),
      8,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    canvas.drawCircle(
      Offset(engineFrontX + 38, trackY - 2 + chugBounce),
      8,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    canvas.drawCircle(
      Offset(engineFrontX + 12, trackY - 2 + chugBounce),
      3,
      Paint()..color = const Color(0xFF666666),
    );
    canvas.drawCircle(
      Offset(engineFrontX + 38, trackY - 2 + chugBounce),
      3,
      Paint()..color = const Color(0xFF666666),
    );

    for (int i = 0; i < cars.length; i++) {
      final carX =
          engineFrontX + engineWidth + carSpacing + i * (carWidth + carSpacing);
      final carY = trackY - 30 + chugBounce;
      final filled = cars[i] != null;
      final isNext = i == nextCarIndex;

      canvas.drawLine(
        Offset(carX - carSpacing, trackY - 15 + chugBounce),
        Offset(carX, trackY - 15 + chugBounce),
        Paint()
          ..color = const Color(0xFF666666)
          ..strokeWidth = 2,
      );

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

      canvas.drawCircle(
        Offset(carX + 10, trackY - 2 + chugBounce),
        5,
        Paint()..color = const Color(0xFF2A2A2A),
      );
      canvas.drawCircle(
        Offset(carX + carWidth - 10, trackY - 2 + chugBounce),
        5,
        Paint()..color = const Color(0xFF2A2A2A),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(0, trackY + 5, size.width, size.height - trackY - 5),
      Paint()..color = const Color(0xFF1A3020).withValues(alpha: 0.5),
    );
  }

  void _drawStation(Canvas canvas, Size size, double trackY) {
    const stationX = 10.0;
    final stationY = trackY - 55;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stationX - 5, trackY - 5, 60, 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF5A4030).withValues(alpha: 0.6),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stationX, stationY, 50, 50),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF2A4060).withValues(alpha: 0.6),
    );
    final roofPath = Path()
      ..moveTo(stationX - 5, stationY)
      ..lineTo(stationX + 25, stationY - 18)
      ..lineTo(stationX + 55, stationY)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()..color = const Color(0xFF8B4513).withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stationX + 18, stationY + 25, 14, 25),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0xFF1A2A3A).withValues(alpha: 0.8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stationX + 8, stationY + 10, 10, 10),
        const Radius.circular(2),
      ),
      Paint()
        ..color = const Color(0xFFFFDD88).withValues(alpha: 0.5),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'STATION',
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: AppColors.starGold.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(stationX + 25 - tp.width / 2, stationY - 28));

    final dotY = trackY + 14;
    for (int i = 0; i < totalWords; i++) {
      final dotX = stationX + 4 + i * 6.0;
      canvas.drawCircle(
        Offset(dotX, dotY),
        2.5,
        Paint()
          ..color = i < wordsCompleted
              ? AppColors.success.withValues(alpha: 0.8)
              : AppColors.border.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrainPainter old) =>
      old.nextCarIndex != nextCarIndex ||
      old.wordsCompleted != wordsCompleted ||
      old.currentWord != currentWord;
}

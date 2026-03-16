import 'dart:math';
import 'dart:ui' as ui;

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
// Cat Letter Toss — A pink glowing cat tosses letters; catch them in a basket
// ─────────────────────────────────────────────────────────────────────────────

class CatLetterTossGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;
  final bool hintsEnabled;
  final GameDifficultyParams? difficultyParams;

  const CatLetterTossGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
    this.difficultyParams,
  });

  @override
  State<CatLetterTossGame> createState() => _CatLetterTossGameState();
}

// ── Data models ──────────────────────────────────────────────────────────────

class _TossedLetter {
  String letter;
  bool isCorrect;
  double x; // absolute px
  double y; // absolute px
  double vx; // px/sec horizontal velocity
  double vy; // px/sec vertical velocity (positive = down)
  double rotation;
  double rotationSpeed;
  bool caught = false;
  bool missed = false;
  double catchAnimT = 0; // 0..1 fly-to-slot anim
  Offset? catchTarget;

  _TossedLetter({
    required this.letter,
    required this.isCorrect,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.rotation = 0,
    this.rotationSpeed = 0,
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

// ── Simulation ──────────────────────────────────────────────────────────────

class _CatLetterTossSim extends ChangeNotifier {
  final Random rng = Random();

  static const double gravity = 420.0;
  static const double tossInterval = 1.2;
  static const double basketWidth = 90.0;
  static const double basketHeight = 50.0;
  static const double letterSize = 38.0;
  static const double catMoveSpeed = 120.0;

  double catX = 0.5;
  double catTargetX = 0.5;
  double catPawAngle = 0;
  double catTailPhase = 0;
  double catEarTwitch = 0;
  double catGlowPhase = 0;
  bool catTossing = false;
  double catTossAnimT = 0;

  double basketX = 0.5;

  final List<_TossedLetter> letters = [];
  double tossTimer = 0;

  final List<_Sparkle> sparkles = [];
  final List<_Star> stars = [];

  double flashTimer = 0;
  Color flashColor = Colors.transparent;

  String feedbackText = '';
  double feedbackTimer = 0;
  Color feedbackColor = AppColors.success;

  double totalTime = 0;
  bool wordCelebrating = false;
  double wordCelebrateT = 0;

  void tick(double dt) {
    notifyListeners();
  }
}

// ── State ────────────────────────────────────────────────────────────────────

class _CatLetterTossGameState extends State<CatLetterTossGame>
    with TickerProviderStateMixin {
  late final _CatLetterTossSim _sim;

  // Game config
  late final int _maxLives;
  late final int _wordsPerRound;

  // Game state (overlay-only, trigger setState on change)
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  late int _lives;
  int _wordsCompleted = 0;
  int _combo = 0;
  int _bestCombo = 0;

  // Word state
  List<String> _wordPool = [];
  int _wordPoolIndex = 0;
  String _currentWord = '';
  int _nextLetterIndex = 0;
  List<bool> _slotsFilled = [];

  // Ticker
  late Ticker _ticker;
  Duration _lastTickTime = Duration.zero;

  // Word slot key for positioning
  final _slotRowKey = GlobalKey();
  List<Rect> _slotRects = [];

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sim = _CatLetterTossSim();
    _maxLives = widget.difficultyParams?.lives ?? 3;
    _wordsPerRound = widget.difficultyParams?.wordCount ?? 10;
    _lives = _maxLives;
    _sessionTimer = Stopwatch()..start();
    _buildWordPool();
    _nextWord();
    _initStars();
    _ticker = createTicker(_onTick)..start();
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
    pool.shuffle(_sim.rng);
    _wordPool = pool;
    _wordPoolIndex = 0;
  }

  void _nextWord() {
    if (_gameOver) return;
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle(_sim.rng);
      _wordPoolIndex = 0;
    }
    _currentWord = _wordPool[_wordPoolIndex++];
    _nextLetterIndex = 0;
    _slotsFilled = List.filled(_currentWord.length, false);
    _sim.wordCelebrating = false;
    _sim.wordCelebrateT = 0;
    widget.audioService.playWord(_currentWord);
  }

  // ── Stars ──────────────────────────────────────────────────────────────

  void _initStars() {
    final rng = _sim.rng;
    for (int i = 0; i < 60; i++) {
      _sim.stars.add(_Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: rng.nextDouble() * 2.0 + 0.5,
        twinklePhase: rng.nextDouble() * pi * 2,
        twinkleSpeed: rng.nextDouble() * 2 + 1,
        brightness: rng.nextDouble() * 0.5 + 0.3,
      ));
    }
  }

  // ── Game loop ─────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }
    final dt = (elapsed - _lastTickTime).inMicroseconds / 1e6;
    _lastTickTime = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    final sim = _sim;

    if (!_gameStarted || _gameOver) {
      sim.catGlowPhase += dt * 2.5;
      sim.catTailPhase += dt * 3.0;
      for (final s in sim.stars) {
        s.twinklePhase += dt * s.twinkleSpeed;
      }
      sim.tick(dt);
      return;
    }

    sim.totalTime += dt;

    sim.catGlowPhase += dt * 2.5;
    sim.catTailPhase += dt * 3.0;
    sim.catEarTwitch = sin(sim.totalTime * 4.0) * 0.1;

    final catDiff = sim.catTargetX - sim.catX;
    if (catDiff.abs() > 0.005) {
      sim.catX += catDiff.sign * _CatLetterTossSim.catMoveSpeed * dt / 400;
      sim.catX = sim.catX.clamp(0.1, 0.9);
    }

    if (sim.catTossing) {
      sim.catTossAnimT += dt * 6;
      sim.catPawAngle = sin(sim.catTossAnimT * pi) * 0.5;
      if (sim.catTossAnimT >= 1.0) {
        sim.catTossing = false;
        sim.catTossAnimT = 0;
        sim.catPawAngle = 0;
      }
    }

    if (!sim.wordCelebrating) {
      sim.tossTimer += dt;
      if (sim.tossTimer >= _CatLetterTossSim.tossInterval) {
        sim.tossTimer = 0;
        _tossLetter();
      }
    }

    final screenSize = MediaQuery.of(context).size;
    for (final l in sim.letters) {
      if (l.caught) {
        l.catchAnimT += dt * 4;
        if (l.catchAnimT > 1.0) l.catchAnimT = 1.0;
        continue;
      }
      if (l.missed) continue;

      l.vy += _CatLetterTossSim.gravity * dt;
      l.x += l.vx * dt;
      l.y += l.vy * dt;
      l.rotation += l.rotationSpeed * dt;

      final basketPx = sim.basketX * screenSize.width;
      final basketTop = screenSize.height - _CatLetterTossSim.basketHeight - 40;
      if (l.y + _CatLetterTossSim.letterSize / 2 >= basketTop &&
          l.y + _CatLetterTossSim.letterSize / 2 <= basketTop + _CatLetterTossSim.basketHeight &&
          (l.x - basketPx).abs() < _CatLetterTossSim.basketWidth / 2 + _CatLetterTossSim.letterSize / 4) {
        _onLetterCaught(l);
      }

      if (l.y > screenSize.height + 50) {
        l.missed = true;
      }
    }

    sim.letters.removeWhere((l) => l.missed || (l.caught && l.catchAnimT >= 1.0));

    for (final s in sim.sparkles) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
    }
    sim.sparkles.removeWhere((s) => s.life <= 0);

    for (final s in sim.stars) {
      s.twinklePhase += dt * s.twinkleSpeed;
    }

    bool overlayChanged = false;

    if (sim.wordCelebrating) {
      sim.wordCelebrateT += dt * 1.5;
      if (sim.wordCelebrateT >= 1.0) {
        _wordsCompleted++;
        overlayChanged = true;
        if (_wordsCompleted >= _wordsPerRound) {
          _gameOver = true;
          _awardMiniGameStickers();
        } else {
          _nextWord();
        }
      }
    }

    if (sim.flashTimer > 0) sim.flashTimer -= dt;
    if (sim.feedbackTimer > 0) sim.feedbackTimer -= dt;

    sim.tick(dt);
    if (overlayChanged && mounted) setState(() {});
  }

  // ── Toss logic ─────────────────────────────────────────────────────────

  void _tossLetter() {
    final screenSize = MediaQuery.of(context).size;
    final rng = _sim.rng;

    final neededLetter = _currentWord[_nextLetterIndex];
    final isCorrect = rng.nextDouble() < 0.45;
    final letter =
        isCorrect ? neededLetter : _randomDistractor(neededLetter);

    _sim.catTargetX = 0.15 + rng.nextDouble() * 0.7;
    _sim.catTossing = true;
    _sim.catTossAnimT = 0;

    final catPx = _sim.catX * screenSize.width;
    const catY = 100.0;
    final targetX = 0.2 + rng.nextDouble() * 0.6;
    final dx = targetX * screenSize.width - catPx;
    final vx = dx * (0.5 + rng.nextDouble() * 0.3);
    final vy = 40 + rng.nextDouble() * 60;

    _sim.letters.add(_TossedLetter(
      letter: letter,
      isCorrect: isCorrect,
      x: catPx,
      y: catY + 40,
      vx: vx,
      vy: vy,
      rotation: rng.nextDouble() * 0.5 - 0.25,
      rotationSpeed: (rng.nextDouble() - 0.5) * 4,
    ));
  }

  String _randomDistractor(String avoid) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    String c;
    do {
      c = alphabet[_sim.rng.nextInt(26)];
    } while (c == avoid);
    return c;
  }

  // ── Catch logic ────────────────────────────────────────────────────────

  void _onLetterCaught(_TossedLetter letter) {
    if (letter.caught || letter.missed) return;

    if (letter.isCorrect) {
      letter.caught = true;
      letter.catchAnimT = 0;

      if (_slotRects.isNotEmpty && _nextLetterIndex < _slotRects.length) {
        final rect = _slotRects[_nextLetterIndex];
        letter.catchTarget = rect.center;
      }

      _slotsFilled[_nextLetterIndex] = true;
      _nextLetterIndex++;
      _combo++;
      if (_combo > _bestCombo) _bestCombo = _combo;

      final comboMultiplier = _combo.clamp(1, 10);
      _score += 10 * comboMultiplier;

      _sim.feedbackText = _combo > 1 ? '${_combo}x Combo!' : 'Nice!';
      _sim.feedbackColor = AppColors.success;
      _sim.feedbackTimer = 1.0;

      _spawnSparkles(letter.x, letter.y, AppColors.magenta);

      widget.audioService.playSuccess();
      Haptics.correct();

      if (_nextLetterIndex >= _currentWord.length) {
        _sim.wordCelebrating = true;
        _sim.wordCelebrateT = 0;
        _score += 50;
        widget.audioService.playSuccess();
        Haptics.success();
        _spawnSparkles(
            MediaQuery.of(context).size.width / 2, 200, AppColors.starGold);
      }

      if (mounted) setState(() {});
    } else {
      letter.missed = true;
      _combo = 0;
      _lives--;
      _sim.flashTimer = 0.3;
      _sim.flashColor = AppColors.error;
      _sim.feedbackText = 'Oops!';
      _sim.feedbackColor = AppColors.error;
      _sim.feedbackTimer = 1.0;

      widget.audioService.playError();
      Haptics.wrong();

      if (_lives <= 0) {
        _gameOver = true;
        _awardMiniGameStickers();
      }

      if (mounted) setState(() {});
    }
  }

  void _spawnSparkles(double x, double y, Color baseColor) {
    final rng = _sim.rng;
    for (int i = 0; i < 12; i++) {
      final angle = rng.nextDouble() * pi * 2;
      final speed = 60 + rng.nextDouble() * 120;
      _sim.sparkles.add(_Sparkle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: 0.5 + rng.nextDouble() * 0.5,
        color: Color.lerp(
            baseColor, AppColors.starGold, rng.nextDouble() * 0.5)!,
        size: 3 + rng.nextDouble() * 4,
      ));
    }
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('cat_letter_toss', _score);
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

  // ── Restart ────────────────────────────────────────────────────────────

  void _restartGame() {
    _gameStarted = false;
    _gameOver = false;
    _score = 0;
    _lives = _maxLives;
    _wordsCompleted = 0;
    _combo = 0;
    _bestCombo = 0;
    _sim.totalTime = 0;
    _sim.letters.clear();
    _sim.sparkles.clear();
    _sim.tossTimer = 0;
    _sim.flashTimer = 0;
    _sim.feedbackTimer = 0;
    _sim.wordCelebrating = false;
    _sim.wordCelebrateT = 0;
    _buildWordPool();
    _nextWord();
  }

  // ── Slot rect calculation ─────────────────────────────────────────────

  void _calculateSlotRects() {
    final box = _slotRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final rowPos = box.localToGlobal(Offset.zero);
    const slotWidth = 38.0;
    const slotHeight = 44.0;
    const spacing = 6.0;
    final totalWidth =
        _currentWord.length * slotWidth + (_currentWord.length - 1) * spacing;
    final startX = rowPos.dx + (box.size.width - totalWidth) / 2;
    final topPadding = MediaQuery.of(context).padding.top;

    _slotRects = List.generate(_currentWord.length, (i) {
      final x = startX + i * (slotWidth + spacing);
      return Rect.fromLTWH(
          x, rowPos.dy + 8 - topPadding, slotWidth, slotHeight);
    });
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
            colors: [Color(0xFF050510), Color(0xFF0A0A2E), Color(0xFF0A0A1A)],
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !_gameStarted
              ? () => setState(() => _gameStarted = true)
              : null,
          onPanUpdate: _gameStarted
              ? (details) {
                  _sim.basketX =
                      (details.localPosition.dx / size.width).clamp(0.1, 0.9);
                }
              : null,
          onPanStart: _gameStarted
              ? (details) {
                  _sim.basketX =
                      (details.localPosition.dx / size.width).clamp(0.1, 0.9);
                }
              : null,
          onTapDown: _gameStarted
              ? (details) {
                  _sim.basketX =
                      (details.localPosition.dx / size.width).clamp(0.1, 0.9);
                }
              : null,
          child: Stack(
            children: [
              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _StarFieldPainter(
                      sim: _sim,
                    ),
                  ),
                ),
              ),

              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _CatPainter(
                      sim: _sim,
                    ),
                  ),
                ),
              ),

              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _LettersPainter(
                      sim: _sim,
                      hintsEnabled: widget.hintsEnabled,
                    ),
                  ),
                ),
              ),

              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _BasketPainter(
                      sim: _sim,
                    ),
                  ),
                ),
              ),

              // Flash overlay
              if (_sim.flashTimer > 0)
                IgnorePointer(
                  child: Container(
                    color: _sim.flashColor
                        .withValues(alpha: (_sim.flashTimer / 0.3) * 0.15),
                  ),
                ),

              // HUD
              _buildHUD(size),

              // Feedback text
              if (_sim.feedbackTimer > 0)
                Positioned(
                  top: size.height * 0.4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      _sim.feedbackText,
                      style: AppFonts.fredoka(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _sim.feedbackColor
                            .withValues(alpha: _sim.feedbackTimer.clamp(0.0, 1.0)),
                        shadows: [
                          Shadow(
                            color: _sim.feedbackColor.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (!_gameStarted) _buildStartOverlay(size),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStartOverlay(Size size) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cat Letter Toss',
              style: AppFonts.fredoka(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: AppColors.magenta,
                shadows: [
                  Shadow(
                    color: AppColors.magenta.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Drag the basket to catch\nthe right letters!',
              textAlign: TextAlign.center,
              style: AppFonts.nunito(
                fontSize: 18,
                color: AppColors.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.magenta, AppColors.violet],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.magenta.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'Tap to Start',
                style: AppFonts.fredoka(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHUD(Size screenSize) {
    return Column(
      children: [
        const SizedBox(height: 8),
        // Top bar
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
                      color: AppColors.electricBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${_wordsCompleted + 1}/$_wordsPerRound',
                  style: AppFonts.fredoka(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.electricBlue,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Combo
              if (_combo > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.magenta.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${_combo}x',
                    style: AppFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.magenta,
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

        const SizedBox(height: 12),

        // Word slots
        _buildWordSlots(screenSize),

        const Spacer(),
      ],
    );
  }

  Widget _buildWordSlots(Size screenSize) {
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
            glowRadius = 8 + goldenPulse * 8;
          } else if (filled) {
            borderColor = AppColors.success.withValues(alpha: 0.6);
            bgColor = AppColors.success.withValues(alpha: 0.1);
            textColor = AppColors.success;
          } else if (isNext) {
            borderColor = AppColors.magenta.withValues(alpha: 0.8);
            bgColor = AppColors.magenta.withValues(alpha: 0.1);
            textColor = AppColors.magenta;
            glowRadius = 6;
          } else {
            borderColor = AppColors.border.withValues(alpha: 0.5);
            bgColor = AppColors.surface.withValues(alpha: 0.4);
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
                border: Border.all(color: borderColor, width: 2),
                boxShadow: glowRadius > 0
                    ? [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.4),
                          blurRadius: glowRadius,
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: filled
                  ? Text(
                      _currentWord[i].toUpperCase(),
                      style: AppFonts.fredoka(
                        fontSize: 22,
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

  Widget _buildGameOver() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _wordsCompleted >= _wordsPerRound ? 'AMAZING!' : 'GAME OVER',
            style: AppFonts.fredoka(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: _wordsCompleted >= _wordsPerRound
                  ? AppColors.starGold
                  : AppColors.magenta,
              shadows: [
                Shadow(
                  color: (_wordsCompleted >= _wordsPerRound
                          ? AppColors.starGold
                          : AppColors.magenta)
                      .withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Score card
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
                if (_bestCombo > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Best combo: ${_bestCombo}x',
                    style: AppFonts.nunito(
                      fontSize: 14,
                      color: AppColors.magenta,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Play again
          GestureDetector(
            onTap: () => setState(() => _restartGame()),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.magenta, AppColors.violet],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.magenta.withValues(alpha: 0.3),
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

          // Back
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

// ─── Star field painter ──────────────────────────────────────────────────────

class _StarFieldPainter extends CustomPainter {
  final _CatLetterTossSim sim;

  _StarFieldPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Nebula glow
    final nebulaPaint1 = Paint()
      ..color = const Color(0xFF200030).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(
        Offset(size.width * 0.8, size.height * 0.2), 120, nebulaPaint1);
    final nebulaPaint2 = Paint()
      ..color = const Color(0xFF100030).withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    canvas.drawCircle(
        Offset(size.width * 0.2, size.height * 0.6), 100, nebulaPaint2);

    for (final s in sim.stars) {
      final twinkle = (sin(s.twinklePhase) * 0.3 + 0.7).clamp(0.0, 1.0);
      paint.color =
          Colors.white.withValues(alpha: s.brightness * twinkle);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        paint,
      );
      if (s.size > 1.5) {
        final glowPaint = Paint()
          ..color = const Color(0xFFFF88CC)
              .withValues(alpha: s.brightness * twinkle * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(
          Offset(s.x * size.width, s.y * size.height),
          s.size * 2.5,
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter old) => false;
}

// ─── Cat painter ─────────────────────────────────────────────────────────────

class _CatPainter extends CustomPainter {
  final _CatLetterTossSim sim;

  static const Color _catPink = Color(0xFFFF69B4);
  static const Color _catMagenta = Color(0xFFEC4899);
  static const Color _catLight = Color(0xFFFFB6D9);

  _CatPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = sim.catX * size.width;
    const cy = 80.0;
    final glowPulse = (sin(sim.catGlowPhase) * 0.3 + 0.7).clamp(0.0, 1.0);

    // ── Glow aura ──
    final auraPaint = Paint()
      ..color = _catMagenta.withValues(alpha: 0.15 + glowPulse * 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(Offset(cx, cy), 55 + glowPulse * 8, auraPaint);

    final auraInner = Paint()
      ..color = _catPink.withValues(alpha: 0.08 + glowPulse * 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(Offset(cx, cy), 42 + glowPulse * 5, auraInner);

    // ── Tail (behind body) ──
    _drawTail(canvas, cx, cy);

    // ── Body ──
    final bodyPaint = Paint()..color = _catPink;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: 48, height: 40),
      const Radius.circular(18),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // Body highlight
    final highlightPaint = Paint()
      ..color = _catLight.withValues(alpha: 0.3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 4, cy + 2), width: 20, height: 14),
      highlightPaint,
    );

    // ── Head ──
    final headPaint = Paint()..color = _catPink;
    canvas.drawCircle(Offset(cx, cy - 14), 20, headPaint);

    // Head highlight
    final headHighlight = Paint()
      ..color = _catLight.withValues(alpha: 0.25);
    canvas.drawCircle(Offset(cx - 4, cy - 18), 8, headHighlight);

    // ── Ears ──
    _drawEar(canvas, cx - 14, cy - 30, -0.3 + sim.catEarTwitch);
    _drawEar(canvas, cx + 14, cy - 30, 0.3 - sim.catEarTwitch);

    // ── Eyes ──
    final eyePaint = Paint()..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 7, cy - 16), width: 10, height: 11),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 7, cy - 16), width: 10, height: 11),
      eyePaint,
    );

    // Pupils
    final pupilPaint = Paint()..color = const Color(0xFF2D1B4E);
    canvas.drawCircle(Offset(cx - 6, cy - 15), 3.5, pupilPaint);
    canvas.drawCircle(Offset(cx + 8, cy - 15), 3.5, pupilPaint);

    // Eye shine
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - 5, cy - 17), 1.5, shinePaint);
    canvas.drawCircle(Offset(cx + 9, cy - 17), 1.5, shinePaint);

    // ── Nose ──
    final nosePaint = Paint()..color = _catMagenta;
    final nosePath = Path()
      ..moveTo(cx, cy - 9)
      ..lineTo(cx - 3, cy - 6)
      ..lineTo(cx + 3, cy - 6)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    // ── Mouth ──
    final mouthPaint = Paint()
      ..color = _catMagenta.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final mouthPath = Path()
      ..moveTo(cx - 4, cy - 5)
      ..quadraticBezierTo(cx, cy - 2, cx, cy - 5)
      ..quadraticBezierTo(cx, cy - 2, cx + 4, cy - 5);
    canvas.drawPath(mouthPath, mouthPaint);

    // ── Whiskers ──
    final whiskerPaint = Paint()
      ..color = _catLight.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    // Left
    canvas.drawLine(
        Offset(cx - 10, cy - 8), Offset(cx - 25, cy - 12), whiskerPaint);
    canvas.drawLine(
        Offset(cx - 10, cy - 6), Offset(cx - 24, cy - 5), whiskerPaint);
    canvas.drawLine(
        Offset(cx - 10, cy - 4), Offset(cx - 23, cy + 1), whiskerPaint);
    // Right
    canvas.drawLine(
        Offset(cx + 10, cy - 8), Offset(cx + 25, cy - 12), whiskerPaint);
    canvas.drawLine(
        Offset(cx + 10, cy - 6), Offset(cx + 24, cy - 5), whiskerPaint);
    canvas.drawLine(
        Offset(cx + 10, cy - 4), Offset(cx + 23, cy + 1), whiskerPaint);

    // ── Paws ──
    _drawPaws(canvas, cx, cy);
  }

  void _drawEar(Canvas canvas, double x, double y, double angle) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);

    final earOuter = Paint()..color = _catPink;
    final earPath = Path()
      ..moveTo(0, -14)
      ..lineTo(-8, 6)
      ..lineTo(8, 6)
      ..close();
    canvas.drawPath(earPath, earOuter);

    final earInner = Paint()..color = _catMagenta.withValues(alpha: 0.5);
    final innerPath = Path()
      ..moveTo(0, -9)
      ..lineTo(-4, 3)
      ..lineTo(4, 3)
      ..close();
    canvas.drawPath(innerPath, earInner);

    canvas.restore();
  }

  void _drawTail(Canvas canvas, double cx, double cy) {
    final tailPaint = Paint()
      ..color = _catPink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final tailSwing = sin(sim.catTailPhase) * 15;
    final tailPath = Path()
      ..moveTo(cx + 22, cy + 16)
      ..cubicTo(
        cx + 35 + tailSwing, cy + 5,
        cx + 40 + tailSwing * 0.5, cy - 15,
        cx + 30 + tailSwing * 0.8, cy - 25,
      );
    canvas.drawPath(tailPath, tailPaint);

    // Tail tip
    final tipPaint = Paint()
      ..color = _catMagenta
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
        Offset(cx + 30 + sin(sim.catTailPhase) * 15 * 0.8, cy - 25), 3, tipPaint);
  }

  void _drawPaws(Canvas canvas, double cx, double cy) {
    final pawPaint = Paint()..color = _catLight;

    // Left paw (static)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - 14, cy + 26), width: 14, height: 10),
      pawPaint,
    );

    // Right paw (tossing arm)
    canvas.save();
    canvas.translate(cx + 14, cy + 18);
    canvas.rotate(sim.catPawAngle);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 8), width: 14, height: 10),
      pawPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CatPainter old) => false;
}

// ─── Letters painter ─────────────────────────────────────────────────────────

class _LettersPainter extends CustomPainter {
  final _CatLetterTossSim sim;
  final bool hintsEnabled;

  _LettersPainter({required this.sim, required this.hintsEnabled}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final letterPaint = Paint();
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final l in sim.letters) {
      if (l.missed) continue;

      double x = l.x;
      double y = l.y;
      double opacity = 1.0;

      if (l.caught && l.catchTarget != null) {
        // Animate toward slot
        final t = Curves.easeInOut.transform(l.catchAnimT.clamp(0.0, 1.0));
        x = l.x + (l.catchTarget!.dx - l.x) * t;
        y = l.y + (l.catchTarget!.dy - l.y) * t;
        opacity = 1.0 - t * 0.5;
      }

      canvas.save();
      canvas.translate(x, y);
      if (!l.caught) canvas.rotate(l.rotation);

      // Block background
      final showHint = hintsEnabled && l.isCorrect;
      final blockColor =
          showHint ? const Color(0xFF2D1650) : const Color(0xFF1A1A2E);
      final borderCol = showHint
          ? const Color(0xFFEC4899).withValues(alpha: 0.7)
          : const Color(0xFF4A4A6A).withValues(alpha: 0.5);

      letterPaint
        ..color = blockColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      final blockRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset.zero,
            width: _CatLetterTossSim.letterSize,
            height: _CatLetterTossSim.letterSize),
        const Radius.circular(8),
      );
      canvas.drawRRect(blockRect, letterPaint);

      // Border
      letterPaint
        ..color = borderCol.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(blockRect, letterPaint);

      // Glow for correct letters
      if (showHint) {
        final glowPaint = Paint()
          ..color = const Color(0xFFEC4899).withValues(alpha: 0.15 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRRect(blockRect, glowPaint);
      }

      // Letter text
      textPainter.text = TextSpan(
        text: l.letter.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: showHint
              ? const Color(0xFFFF69B4).withValues(alpha: opacity)
              : const Color(0xFF8892B0).withValues(alpha: opacity),
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }

    for (final s in sim.sparkles) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      final sparkPaint = Paint()
        ..color = s.color.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(s.x, s.y), s.size * alpha, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LettersPainter old) => false;
}

// ─── Basket painter ──────────────────────────────────────────────────────────

class _BasketPainter extends CustomPainter {
  final _CatLetterTossSim sim;

  _BasketPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final basketX = sim.basketX;
    const basketWidth = _CatLetterTossSim.basketWidth;
    const basketHeight = _CatLetterTossSim.basketHeight;
    final cx = basketX * size.width;
    final top = size.height - basketHeight - 40;

    // Basket glow
    final glowPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, top + basketHeight / 2),
            width: basketWidth + 16,
            height: basketHeight + 8),
        const Radius.circular(16),
      ),
      glowPaint,
    );

    // Basket body
    final basketPath = Path();
    const halfW = basketWidth / 2;
    // Trapezoid shape: wider at top, narrower at bottom
    basketPath.moveTo(cx - halfW, top);
    basketPath.lineTo(cx + halfW, top);
    basketPath.lineTo(cx + halfW * 0.75, top + basketHeight);
    basketPath.lineTo(cx - halfW * 0.75, top + basketHeight);
    basketPath.close();

    // Fill
    final basketPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, top),
        Offset(cx, top + basketHeight),
        [
          const Color(0xFF2D1650).withValues(alpha: 0.9),
          const Color(0xFF1A1A2E).withValues(alpha: 0.9),
        ],
      );
    canvas.drawPath(basketPath, basketPaint);

    // Border
    final borderPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(basketPath, borderPaint);

    // Rim highlight
    final rimPaint = Paint()
      ..color = const Color(0xFFFFB6D9).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
        Offset(cx - halfW + 2, top + 2), Offset(cx + halfW - 2, top + 2), rimPaint);

    // Weave lines
    final weavePaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final t = i / 4;
      final y = top + basketHeight * t;
      final widthAtY = halfW * (1 - t * 0.25);
      canvas.drawLine(Offset(cx - widthAtY, y), Offset(cx + widthAtY, y), weavePaint);
    }
    // Vertical weave
    for (int i = -2; i <= 2; i++) {
      final xOff = i * (basketWidth / 5);
      canvas.drawLine(
        Offset(cx + xOff, top + 2),
        Offset(cx + xOff * 0.75, top + basketHeight - 2),
        weavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BasketPainter old) => false;
}

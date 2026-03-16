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

/// Powerup types that can spawn during gameplay.
enum _PowerUpType {
  freezeTime, // Slows all words for 3 seconds
  doublePoints, // Doubles points for 5 seconds
  extraLife, // Restores one lost life
  wordBomb, // Clears all wrong words from screen
}

class _NinjaSim extends ChangeNotifier {
  final List<_FlyingWord> flyingWords = [];
  final List<_FlyingPowerUp> flyingPowerUps = [];
  final List<_InkSplash> splashes = [];
  final List<_SlashTrail> slashTrails = [];

  double shakeX = 0;
  double shakeY = 0;
  int shakeFrames = 0;

  Color? flashColor;
  double flashAlpha = 0;

  String targetWord = '';
  int combo = 0;
  bool freezeActive = false;

  final _rng = Random();

  void tick() {
    final freezeFactor = freezeActive ? 0.5 : 1.0;

    for (final w in flyingWords) {
      w.x += w.vx * freezeFactor;
      w.y += w.vy * freezeFactor;
      w.vy += 0.00015 * freezeFactor;
      w.angle += w.rotation * freezeFactor;
      w.life -= 0.003;
    }
    flyingWords.removeWhere((w) => w.y > 1.3 || w.life <= 0);

    for (final p in flyingPowerUps) {
      p.x += p.vx * freezeFactor;
      p.y += p.vy * freezeFactor;
      p.vy += 0.00015 * freezeFactor;
      p.angle += p.rotation * freezeFactor;
      p.life -= 0.003;
      p.pulsePhase += 0.08;
    }
    flyingPowerUps.removeWhere((p) => p.y > 1.3 || p.life <= 0);

    for (final s in splashes) {
      s.life -= 0.03;
      s.radius += 2;
    }
    splashes.removeWhere((s) => s.life <= 0);

    for (final t in slashTrails) {
      t.life -= 0.06;
    }
    slashTrails.removeWhere((t) => t.life <= 0);

    if (shakeFrames > 0) {
      shakeX = (_rng.nextDouble() - 0.5) * 8;
      shakeY = (_rng.nextDouble() - 0.5) * 8;
      shakeFrames--;
    } else {
      shakeX = 0;
      shakeY = 0;
    }

    if (flashAlpha > 0) {
      flashAlpha -= 0.04;
      if (flashAlpha < 0) flashAlpha = 0;
    }

    notifyListeners();
  }

  void reset() {
    flyingWords.clear();
    flyingPowerUps.clear();
    splashes.clear();
    slashTrails.clear();
    shakeFrames = 0;
    shakeX = 0;
    shakeY = 0;
    flashAlpha = 0;
    combo = 0;
    freezeActive = false;
    targetWord = '';
  }
}

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
  static const _maxLives = 3;

  final _rng = Random();
  final _sim = _NinjaSim();

  // Word data
  List<String> _wordPool = [];

  // State
  int _score = 0;
  int _maxCombo = 0;
  int _livesLeft = _maxLives;
  int _timeLeft = _gameDuration;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Powerup active state
  bool _doublePointsActive = false;
  Timer? _freezeTimer;
  Timer? _doublePointsTimer;

  // Swipe tracking for slash trails
  final List<Offset> _swipePoints = [];
  bool _isSwiping = false;
  bool _showingStartOverlay = true;

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
    if (!_showingStartOverlay) _startTimers();
  }

  void _dismissStartOverlay() {
    setState(() => _showingStartOverlay = false);
    _startTimers();
  }

  void _pickNewTarget() {
    _sim.targetWord = _wordPool[_rng.nextInt(_wordPool.length)];
    widget.audioService.playWord(_sim.targetWord);
  }

  double get _speedMultiplier {
    if (_score < 50) return 1.0;
    if (_score < 100) return 1.15;
    if (_score < 200) return 1.3;
    if (_score < 350) return 1.5;
    return 1.7;
  }

  int get _spawnIntervalMs {
    if (_score < 50) return 1200;
    if (_score < 100) return 1050;
    if (_score < 200) return 900;
    if (_score < 350) return 750;
    return 650;
  }

  void _startTimers() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newTime = _timeLeft - 1;
      if (newTime <= 0) {
        _timeLeft = 0;
        _endGame();
        setState(() {});
      } else {
        setState(() => _timeLeft = newTime);
      }
    });

    _scheduleNextSpawn();
    _spawnWords();
  }

  void _scheduleNextSpawn() {
    _spawnTimer?.cancel();
    _spawnTimer = Timer(Duration(milliseconds: _spawnIntervalMs), () {
      if (!mounted || _gameOver) return;
      _spawnWords();
      if (_rng.nextDouble() < 0.15) {
        _spawnPowerUp();
      }
      _scheduleNextSpawn();
    });
  }

  void _spawnWords() {
    final count = 2 + _rng.nextInt(3);
    final includeTarget = _rng.nextDouble() < 0.7;

    final words = <String>[];
    if (includeTarget) words.add(_sim.targetWord);

    while (words.length < count) {
      final w = _wordPool[_rng.nextInt(_wordPool.length)];
      if (w != _sim.targetWord && !words.contains(w)) words.add(w);
    }
    words.shuffle(_rng);

    for (int i = 0; i < words.length; i++) {
      final trajectory = _rng.nextInt(10);
      double startX, startY, vx, vy;

      final speed = _speedMultiplier;
      final freezeFactor = _sim.freezeActive ? 0.5 : 1.0;
      final effectiveSpeed = speed * freezeFactor;

      if (trajectory <= 6) {
        startX = 0.1 + _rng.nextDouble() * 0.8;
        startY = 1.15;
        vx = (_rng.nextDouble() - 0.5) * 0.003 * effectiveSpeed;
        vy = -(0.010 + _rng.nextDouble() * 0.006) * effectiveSpeed;
      } else if (trajectory <= 8) {
        startX = -0.08;
        startY = 0.5 + _rng.nextDouble() * 0.3;
        vx = (0.004 + _rng.nextDouble() * 0.003) * effectiveSpeed;
        vy = -(0.006 + _rng.nextDouble() * 0.004) * effectiveSpeed;
      } else {
        startX = 1.08;
        startY = 0.5 + _rng.nextDouble() * 0.3;
        vx = -(0.004 + _rng.nextDouble() * 0.003) * effectiveSpeed;
        vy = -(0.006 + _rng.nextDouble() * 0.004) * effectiveSpeed;
      }

      _sim.flyingWords.add(_FlyingWord(
        word: words[i],
        isTarget: words[i] == _sim.targetWord,
        x: startX,
        y: startY,
        vx: vx,
        vy: vy,
        rotation: (_rng.nextDouble() - 0.5) * 0.04,
        size: 0.9 + _rng.nextDouble() * 0.3,
      ));
    }
  }

  void _spawnPowerUp() {
    final type =
        _PowerUpType.values[_rng.nextInt(_PowerUpType.values.length)];
    if (type == _PowerUpType.extraLife && _livesLeft >= _maxLives) return;

    final startX = 0.15 + _rng.nextDouble() * 0.7;
    final speed = _speedMultiplier;
    final freezeFactor = _sim.freezeActive ? 0.5 : 1.0;
    final effectiveSpeed = speed * freezeFactor;

    _sim.flyingPowerUps.add(_FlyingPowerUp(
      type: type,
      x: startX,
      y: 1.15,
      vx: (_rng.nextDouble() - 0.5) * 0.002 * effectiveSpeed,
      vy: -(0.011 + _rng.nextDouble() * 0.005) * effectiveSpeed,
      rotation: (_rng.nextDouble() - 0.5) * 0.06,
    ));
  }

  void _update() {
    if (_gameOver || !mounted) return;
    _sim.tick();
  }

  void _onTapWord(int index) {
    if (_gameOver) return;
    final word = _sim.flyingWords[index];
    if (word.hit) return;

    word.hit = true;

    _sim.splashes.add(_InkSplash(
      x: word.x,
      y: word.y,
      color: word.isTarget ? AppColors.success : AppColors.error,
      radius: 20,
      life: 1.0,
    ));

    if (word.isTarget) {
      Haptics.success();
      widget.audioService.playSuccess();
      _sim.combo++;
      if (_sim.combo > _maxCombo) _maxCombo = _sim.combo;
      final basePoints = 10 + (_sim.combo - 1) * 5;
      final points = _doublePointsActive ? basePoints * 2 : basePoints;

      _sim.flyingWords.removeAt(index);
      _pickNewTarget();
      setState(() => _score += points);
    } else {
      Haptics.wrong();
      widget.audioService.playError();
      _sim.combo = 0;
      _sim.shakeFrames = 8;
      _sim.flyingWords.removeAt(index);

      setState(() {
        _livesLeft--;
        if (_livesLeft <= 0) {
          _endGame();
        }
      });
    }
  }

  void _onTapPowerUp(int index) {
    if (_gameOver) return;
    final powerUp = _sim.flyingPowerUps[index];
    if (powerUp.collected) return;

    powerUp.collected = true;
    Haptics.success();

    _sim.splashes.add(_InkSplash(
      x: powerUp.x,
      y: powerUp.y,
      color: _powerUpColor(powerUp.type),
      radius: 30,
      life: 1.0,
    ));

    _sim.flashColor = _powerUpColor(powerUp.type);
    _sim.flashAlpha = 0.3;

    _sim.flyingPowerUps.removeAt(index);

    switch (powerUp.type) {
      case _PowerUpType.freezeTime:
        _activateFreeze();
      case _PowerUpType.doublePoints:
        _activateDoublePoints();
      case _PowerUpType.extraLife:
        setState(() {
          if (_livesLeft < _maxLives) _livesLeft++;
        });
      case _PowerUpType.wordBomb:
        _activateWordBomb();
    }
  }

  void _activateFreeze() {
    _sim.freezeActive = true;
    _freezeTimer?.cancel();
    _freezeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _sim.freezeActive = false;
        setState(() {});
      }
    });
    setState(() {});
  }

  void _activateDoublePoints() {
    _doublePointsActive = true;
    _doublePointsTimer?.cancel();
    _doublePointsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _doublePointsActive = false);
    });
    setState(() {});
  }

  void _activateWordBomb() {
    final toRemove = <int>[];
    for (int i = _sim.flyingWords.length - 1; i >= 0; i--) {
      final w = _sim.flyingWords[i];
      if (!w.isTarget && !w.hit) {
        _sim.splashes.add(_InkSplash(
          x: w.x,
          y: w.y,
          color: AppColors.flameOrange,
          radius: 25,
          life: 1.0,
        ));
        toRemove.add(i);
      }
    }
    for (final i in toRemove) {
      _sim.flyingWords.removeAt(i);
    }
    _sim.shakeFrames = 6;
  }

  Color _powerUpColor(_PowerUpType type) {
    switch (type) {
      case _PowerUpType.freezeTime:
        return AppColors.electricBlue;
      case _PowerUpType.doublePoints:
        return AppColors.starGold;
      case _PowerUpType.extraLife:
        return AppColors.error;
      case _PowerUpType.wordBomb:
        return AppColors.flameOrange;
    }
  }

  void _handlePanStart(Offset localPosition, Size size) {
    _isSwiping = true;
    _swipePoints.clear();
    _swipePoints.add(localPosition);
  }

  void _handlePanUpdate(Offset localPosition, Size size) {
    if (!_isSwiping) return;
    _swipePoints.add(localPosition);

    if (_swipePoints.length >= 2) {
      final p1 = _swipePoints[_swipePoints.length - 2];
      final p2 = _swipePoints[_swipePoints.length - 1];
      Color trailColor;
      if (_sim.combo >= 10) {
        trailColor = AppColors.electricBlue;
      } else if (_sim.combo >= 5) {
        trailColor = AppColors.flameOrange;
      } else {
        trailColor = AppColors.magenta;
      }
      _sim.slashTrails.add(_SlashTrail(
        x1: p1.dx / size.width,
        y1: p1.dy / size.height,
        x2: p2.dx / size.width,
        y2: p2.dy / size.height,
        color: trailColor,
        life: 1.0,
      ));
    }

    final dx = localPosition.dx / size.width;
    final dy = localPosition.dy / size.height;
    for (int i = _sim.flyingWords.length - 1; i >= 0; i--) {
      final w = _sim.flyingWords[i];
      if (w.hit) continue;
      if ((dx - w.x).abs() < 0.08 && (dy - w.y).abs() < 0.06) {
        _onTapWord(i);
        return;
      }
    }

    for (int i = _sim.flyingPowerUps.length - 1; i >= 0; i--) {
      final p = _sim.flyingPowerUps[i];
      if (p.collected) continue;
      if ((dx - p.x).abs() < 0.06 && (dy - p.y).abs() < 0.06) {
        _onTapPowerUp(i);
        return;
      }
    }
  }

  void _handlePanEnd() {
    _isSwiping = false;
    _swipePoints.clear();
  }

  Future<void> _endGame() async {
    _gameOver = true;
    _clockTimer?.cancel();
    _spawnTimer?.cancel();
    _freezeTimer?.cancel();
    _doublePointsTimer?.cancel();
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
    _sim.reset();
    _score = 0;
    _maxCombo = 0;
    _livesLeft = _maxLives;
    _timeLeft = _gameDuration;
    _gameOver = false;
    _isNewBest = false;
    _doublePointsActive = false;
    _showingStartOverlay = false;

    _gameLoop.repeat();
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _spawnTimer?.cancel();
    _freezeTimer?.cancel();
    _doublePointsTimer?.cancel();
    _gameLoop.removeListener(_update);
    _gameLoop.dispose();
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
            colors: [Color(0xFF1A0A2E), Color(0xFF0A0A1A)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Game area with screen shake transform
              ListenableBuilder(
                listenable: _sim,
                builder: (context, _) {
                  return Transform.translate(
                    offset: Offset(_sim.shakeX, _sim.shakeY),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final areaSize = Size(
                            constraints.maxWidth, constraints.maxHeight);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final dx = details.localPosition.dx /
                                constraints.maxWidth;
                            final dy = details.localPosition.dy /
                                constraints.maxHeight;
                            for (int i = _sim.flyingPowerUps.length - 1;
                                i >= 0;
                                i--) {
                              final p = _sim.flyingPowerUps[i];
                              if (p.collected) continue;
                              if ((dx - p.x).abs() < 0.06 &&
                                  (dy - p.y).abs() < 0.06) {
                                _onTapPowerUp(i);
                                return;
                              }
                            }
                            for (int i = _sim.flyingWords.length - 1;
                                i >= 0;
                                i--) {
                              final w = _sim.flyingWords[i];
                              if (w.hit) continue;
                              if ((dx - w.x).abs() < 0.08 &&
                                  (dy - w.y).abs() < 0.06) {
                                _onTapWord(i);
                                return;
                              }
                            }
                          },
                          onPanStart: (details) => _handlePanStart(
                              details.localPosition, areaSize),
                          onPanUpdate: (details) => _handlePanUpdate(
                              details.localPosition, areaSize),
                          onPanEnd: (_) => _handlePanEnd(),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _NinjaPainter(
                                sim: _sim,
                              ),
                              size: areaSize,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),

              // Flash overlay
              ListenableBuilder(
                listenable: _sim,
                builder: (context, _) {
                  if (_sim.flashAlpha > 0 && _sim.flashColor != null) {
                    return IgnorePointer(
                      child: Container(
                        color: _sim.flashColor!
                            .withValues(alpha: _sim.flashAlpha.clamp(0.0, 1.0)),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Freeze overlay tint
              if (_sim.freezeActive)
                IgnorePointer(
                  child: Container(
                    color: AppColors.electricBlue.withValues(alpha: 0.06),
                  ),
                ),

              // UI overlay
              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildTargetDisplay(),
                  if (!_gameOver) _buildActiveEffects(),
                  const Spacer(),
                  if (_gameOver) _buildGameOver(),
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
                color: AppColors.error.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u{1F977}',
                  style: AppFonts.fredoka(fontSize: 40),
                ),
                const SizedBox(height: 8),
                Text(
                  'Word Ninja',
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
                        color: AppColors.starGold, size: 28),
                    const SizedBox(width: 6),
                    Text(
                      '"cat"',
                      style: AppFonts.fredoka(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.starGold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: AppColors.secondaryText, size: 18),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'cat',
                        style: AppFonts.fredoka(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.touch_app_rounded,
                        color: AppColors.success, size: 22),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Listen to the word, then\ntap the matching word!',
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
                    color: AppColors.error,
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
            children: List.generate(_maxLives, (i) {
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
    Color comboColor;
    if (_sim.combo >= 10) {
      comboColor = AppColors.electricBlue;
    } else if (_sim.combo >= 5) {
      comboColor = AppColors.flameOrange;
    } else {
      comboColor = AppColors.starGold;
    }

    return GestureDetector(
      onTap: () => widget.audioService.playWord(_sim.targetWord),
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
              'Slash: "${_sim.targetWord}"',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            if (_sim.combo > 1) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: comboColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: comboColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_sim.combo >= 10)
                      Icon(Icons.bolt_rounded,
                          color: comboColor, size: 14)
                    else if (_sim.combo >= 5)
                      Icon(Icons.local_fire_department_rounded,
                          color: comboColor, size: 14),
                    Text(
                      'x${_sim.combo}',
                      style: AppFonts.fredoka(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: comboColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveEffects() {
    final effects = <Widget>[];

    if (_sim.freezeActive) {
      effects.add(_buildEffectChip(
        Icons.ac_unit_rounded,
        'FREEZE',
        AppColors.electricBlue,
      ));
    }
    if (_doublePointsActive) {
      effects.add(_buildEffectChip(
        Icons.looks_two_rounded,
        '2X PTS',
        AppColors.starGold,
      ));
    }

    if (effects.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: effects,
      ),
    );
  }

  Widget _buildEffectChip(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppFonts.fredoka(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
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
                    _livesLeft <= 0 ? 'Game Over!' : 'Time Up!',
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

// ---- Data Models ----

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

class _FlyingPowerUp {
  final _PowerUpType type;
  double x, y, vx, vy;
  double rotation;
  double angle = 0;
  double life = 1.0;
  double pulsePhase = 0;
  bool collected = false;

  _FlyingPowerUp({
    required this.type,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
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

class _SlashTrail {
  final double x1, y1, x2, y2;
  final Color color;
  double life;

  _SlashTrail({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.color,
    required this.life,
  });
}

// ---- Painter ----

class _NinjaPainter extends CustomPainter {
  final _NinjaSim sim;

  _NinjaPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw slash trails
    for (final t in sim.slashTrails) {
      final p1 = Offset(t.x1 * size.width, t.y1 * size.height);
      final p2 = Offset(t.x2 * size.width, t.y2 * size.height);
      final alpha = (t.life * 0.8).clamp(0.0, 1.0);
      final strokeWidth = 4.0 + t.life * 4.0;

      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = t.color.withValues(alpha: alpha * 0.3)
          ..strokeWidth = strokeWidth + 6
          ..strokeCap = StrokeCap.round
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.8),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = t.color.withValues(alpha: alpha)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.6)
          ..strokeWidth = strokeWidth * 0.3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Draw ink splashes
    for (final s in sim.splashes) {
      final center = Offset(s.x * size.width, s.y * size.height);
      canvas.drawCircle(
        center,
        s.radius,
        Paint()
          ..color =
              s.color.withValues(alpha: (s.life * 0.5).clamp(0.0, 1.0))
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, s.radius * 0.5),
      );
    }

    // Draw powerups
    for (final p in sim.flyingPowerUps) {
      if (p.collected) continue;
      _drawPowerUp(canvas, size, p);
    }

    // Draw flying words
    for (final w in sim.flyingWords) {
      if (w.hit) continue;
      _drawWord(canvas, size, w);
    }
  }

  void _drawPowerUp(Canvas canvas, Size size, _FlyingPowerUp p) {
    final cx = p.x * size.width;
    final cy = p.y * size.height;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(p.angle);

    final pulse = 1.0 + sin(p.pulsePhase) * 0.12;
    final radius = 22.0 * pulse;

    Color color;
    IconData icon;
    switch (p.type) {
      case _PowerUpType.freezeTime:
        color = AppColors.electricBlue;
        icon = Icons.ac_unit_rounded;
      case _PowerUpType.doublePoints:
        color = AppColors.starGold;
        icon = Icons.looks_two_rounded;
      case _PowerUpType.extraLife:
        color = AppColors.error;
        icon = Icons.favorite_rounded;
      case _PowerUpType.wordBomb:
        color = AppColors.flameOrange;
        icon = Icons.brightness_7_rounded;
    }

    canvas.drawCircle(
      Offset.zero,
      radius + 8,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withValues(alpha: 0.85),
    );

    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 22,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    iconPainter.paint(
      canvas,
      Offset(-iconPainter.width / 2, -iconPainter.height / 2),
    );

    canvas.restore();
  }

  void _drawWord(Canvas canvas, Size size, _FlyingWord w) {
    final cx = w.x * size.width;
    final cy = w.y * size.height;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(w.angle);

    final bgColor = w.isTarget
        ? AppColors.magenta.withValues(alpha: 0.8)
        : AppColors.surface.withValues(alpha: 0.9);
    final borderColor = w.isTarget ? AppColors.magenta : AppColors.border;

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

    if (w.isTarget) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = AppColors.magenta.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    if (sim.freezeActive) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = AppColors.electricBlue.withValues(alpha: 0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NinjaPainter old) => false;
}

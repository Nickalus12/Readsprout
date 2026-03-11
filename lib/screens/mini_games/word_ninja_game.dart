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

  // Word data
  List<String> _wordPool = [];
  String _targetWord = '';

  // Flying words & powerups
  final List<_FlyingWord> _flyingWords = [];
  final List<_FlyingPowerUp> _flyingPowerUps = [];
  final List<_InkSplash> _splashes = [];
  final List<_SlashTrail> _slashTrails = [];

  // State
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _livesLeft = _maxLives;
  int _timeLeft = _gameDuration;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Powerup active state
  bool _freezeActive = false;
  bool _doublePointsActive = false;
  Timer? _freezeTimer;
  Timer? _doublePointsTimer;

  // Screen shake
  double _shakeX = 0;
  double _shakeY = 0;
  int _shakeFrames = 0;

  // Flash overlay for powerup collect
  Color? _flashColor;
  double _flashAlpha = 0;

  // Swipe tracking for slash trails
  final List<Offset> _swipePoints = [];
  bool _isSwiping = false;

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

  /// Speed multiplier based on current score — words get faster as score climbs.
  double get _speedMultiplier {
    if (_score < 50) return 1.0;
    if (_score < 100) return 1.15;
    if (_score < 200) return 1.3;
    if (_score < 350) return 1.5;
    return 1.7;
  }

  /// Spawn interval decreases as score increases.
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
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) _endGame();
      });
    });

    _scheduleNextSpawn();

    // Initial spawn
    _spawnWords();
  }

  void _scheduleNextSpawn() {
    _spawnTimer?.cancel();
    _spawnTimer = Timer(Duration(milliseconds: _spawnIntervalMs), () {
      if (!mounted || _gameOver) return;
      _spawnWords();
      // Maybe spawn a powerup (15% chance per wave)
      if (_rng.nextDouble() < 0.15) {
        _spawnPowerUp();
      }
      _scheduleNextSpawn();
    });
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
      // Varied trajectories: some from bottom, some from sides
      final trajectory = _rng.nextInt(10); // 0-6 bottom, 7-8 left, 9 right
      double startX, startY, vx, vy;

      final speed = _speedMultiplier;
      final freezeFactor = _freezeActive ? 0.5 : 1.0;
      final effectiveSpeed = speed * freezeFactor;

      if (trajectory <= 6) {
        // From bottom — varied X positions, strong upward velocity
        startX = 0.1 + _rng.nextDouble() * 0.8;
        startY = 1.15;
        vx = (_rng.nextDouble() - 0.5) * 0.003 * effectiveSpeed;
        // Higher arc: vy between -0.010 and -0.016 so words reach 30-40% screen
        vy = -(0.010 + _rng.nextDouble() * 0.006) * effectiveSpeed;
      } else if (trajectory <= 8) {
        // From left side
        startX = -0.08;
        startY = 0.5 + _rng.nextDouble() * 0.3;
        vx = (0.004 + _rng.nextDouble() * 0.003) * effectiveSpeed;
        vy = -(0.006 + _rng.nextDouble() * 0.004) * effectiveSpeed;
      } else {
        // From right side
        startX = 1.08;
        startY = 0.5 + _rng.nextDouble() * 0.3;
        vx = -(0.004 + _rng.nextDouble() * 0.003) * effectiveSpeed;
        vy = -(0.006 + _rng.nextDouble() * 0.004) * effectiveSpeed;
      }

      _flyingWords.add(_FlyingWord(
        word: words[i],
        isTarget: words[i] == _targetWord,
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
    // Don't spawn extra life if at max
    if (type == _PowerUpType.extraLife && _livesLeft >= _maxLives) return;

    final startX = 0.15 + _rng.nextDouble() * 0.7;
    final speed = _speedMultiplier;
    final freezeFactor = _freezeActive ? 0.5 : 1.0;
    final effectiveSpeed = speed * freezeFactor;

    _flyingPowerUps.add(_FlyingPowerUp(
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

    setState(() {
      final freezeFactor = _freezeActive ? 0.5 : 1.0;

      // Update flying words
      for (final w in _flyingWords) {
        w.x += w.vx * freezeFactor;
        w.y += w.vy * freezeFactor;
        w.vy += 0.00015 * freezeFactor; // gravity (tuned for higher arcs)
        w.angle += w.rotation * freezeFactor;
        w.life -= 0.003;
      }
      _flyingWords.removeWhere((w) => w.y > 1.3 || w.life <= 0);

      // Update powerups
      for (final p in _flyingPowerUps) {
        p.x += p.vx * freezeFactor;
        p.y += p.vy * freezeFactor;
        p.vy += 0.00015 * freezeFactor;
        p.angle += p.rotation * freezeFactor;
        p.life -= 0.003;
        p.pulsePhase += 0.08;
      }
      _flyingPowerUps.removeWhere((p) => p.y > 1.3 || p.life <= 0);

      // Update splashes
      for (final s in _splashes) {
        s.life -= 0.03;
        s.radius += 2;
      }
      _splashes.removeWhere((s) => s.life <= 0);

      // Update slash trails
      for (final t in _slashTrails) {
        t.life -= 0.06;
      }
      _slashTrails.removeWhere((t) => t.life <= 0);

      // Update screen shake
      if (_shakeFrames > 0) {
        _shakeX = (_rng.nextDouble() - 0.5) * 8;
        _shakeY = (_rng.nextDouble() - 0.5) * 8;
        _shakeFrames--;
      } else {
        _shakeX = 0;
        _shakeY = 0;
      }

      // Update flash
      if (_flashAlpha > 0) {
        _flashAlpha -= 0.04;
        if (_flashAlpha < 0) _flashAlpha = 0;
      }
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
      color: word.isTarget ? AppColors.success : AppColors.error,
      radius: 20,
      life: 1.0,
    ));

    if (word.isTarget) {
      // Correct!
      Haptics.success();
      widget.audioService.playSuccess();
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      final basePoints = 10 + (_combo - 1) * 5;
      final points = _doublePointsActive ? basePoints * 2 : basePoints;
      _score += points;

      // Remove this word and pick new target
      _flyingWords.removeAt(index);
      _pickNewTarget();
    } else {
      // Wrong word — screen shake!
      Haptics.wrong();
      widget.audioService.playError();
      _combo = 0;
      _livesLeft--;
      _shakeFrames = 8;
      _flyingWords.removeAt(index);

      if (_livesLeft <= 0) {
        _endGame();
      }
    }

    if (mounted) setState(() {});
  }

  void _onTapPowerUp(int index) {
    if (_gameOver) return;
    final powerUp = _flyingPowerUps[index];
    if (powerUp.collected) return;

    powerUp.collected = true;
    Haptics.success();

    // Splash at powerup location
    _splashes.add(_InkSplash(
      x: powerUp.x,
      y: powerUp.y,
      color: _powerUpColor(powerUp.type),
      radius: 30,
      life: 1.0,
    ));

    // Flash effect
    _flashColor = _powerUpColor(powerUp.type);
    _flashAlpha = 0.3;

    _flyingPowerUps.removeAt(index);

    switch (powerUp.type) {
      case _PowerUpType.freezeTime:
        _activateFreeze();
      case _PowerUpType.doublePoints:
        _activateDoublePoints();
      case _PowerUpType.extraLife:
        if (_livesLeft < _maxLives) _livesLeft++;
      case _PowerUpType.wordBomb:
        _activateWordBomb();
    }

    if (mounted) setState(() {});
  }

  void _activateFreeze() {
    _freezeActive = true;
    _freezeTimer?.cancel();
    _freezeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _freezeActive = false);
    });
  }

  void _activateDoublePoints() {
    _doublePointsActive = true;
    _doublePointsTimer?.cancel();
    _doublePointsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _doublePointsActive = false);
    });
  }

  void _activateWordBomb() {
    // Remove all non-target words with splashes
    final toRemove = <int>[];
    for (int i = _flyingWords.length - 1; i >= 0; i--) {
      final w = _flyingWords[i];
      if (!w.isTarget && !w.hit) {
        _splashes.add(_InkSplash(
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
      _flyingWords.removeAt(i);
    }
    _shakeFrames = 6; // small shake for bomb effect
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

    // Add slash trail segment
    if (_swipePoints.length >= 2) {
      final p1 = _swipePoints[_swipePoints.length - 2];
      final p2 = _swipePoints[_swipePoints.length - 1];
      // Determine trail color based on combo
      Color trailColor;
      if (_combo >= 10) {
        trailColor = AppColors.electricBlue;
      } else if (_combo >= 5) {
        trailColor = AppColors.flameOrange;
      } else {
        trailColor = AppColors.magenta;
      }
      _slashTrails.add(_SlashTrail(
        x1: p1.dx / size.width,
        y1: p1.dy / size.height,
        x2: p2.dx / size.width,
        y2: p2.dy / size.height,
        color: trailColor,
        life: 1.0,
      ));
    }

    // Check if swipe hits any word
    final dx = localPosition.dx / size.width;
    final dy = localPosition.dy / size.height;
    for (int i = _flyingWords.length - 1; i >= 0; i--) {
      final w = _flyingWords[i];
      if (w.hit) continue;
      if ((dx - w.x).abs() < 0.08 && (dy - w.y).abs() < 0.06) {
        _onTapWord(i);
        return;
      }
    }

    // Check powerups
    for (int i = _flyingPowerUps.length - 1; i >= 0; i--) {
      final p = _flyingPowerUps[i];
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
    _flyingWords.clear();
    _flyingPowerUps.clear();
    _splashes.clear();
    _slashTrails.clear();
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _livesLeft = _maxLives;
    _timeLeft = _gameDuration;
    _gameOver = false;
    _isNewBest = false;
    _freezeActive = false;
    _doublePointsActive = false;
    _shakeFrames = 0;
    _shakeX = 0;
    _shakeY = 0;
    _flashAlpha = 0;

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
              Transform.translate(
                offset: Offset(_shakeX, _shakeY),
                child: AnimatedBuilder(
                  animation: _gameLoop,
                  builder: (context, _) {
                    return LayoutBuilder(
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
                            // Check powerups first (they're smaller targets)
                            for (int i = _flyingPowerUps.length - 1;
                                i >= 0;
                                i--) {
                              final p = _flyingPowerUps[i];
                              if (p.collected) continue;
                              if ((dx - p.x).abs() < 0.06 &&
                                  (dy - p.y).abs() < 0.06) {
                                _onTapPowerUp(i);
                                return;
                              }
                            }
                            // Find closest word
                            for (int i = _flyingWords.length - 1;
                                i >= 0;
                                i--) {
                              final w = _flyingWords[i];
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
                          child: CustomPaint(
                            painter: _NinjaPainter(
                              words: _flyingWords,
                              powerUps: _flyingPowerUps,
                              splashes: _splashes,
                              slashTrails: _slashTrails,
                              targetWord: _targetWord,
                              combo: _combo,
                              freezeActive: _freezeActive,
                            ),
                            size: areaSize,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Flash overlay
              if (_flashAlpha > 0 && _flashColor != null)
                IgnorePointer(
                  child: Container(
                    color: _flashColor!
                        .withValues(alpha: _flashAlpha.clamp(0.0, 1.0)),
                  ),
                ),

              // Freeze overlay tint
              if (_freezeActive)
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
    // Combo color escalation
    Color comboColor;
    if (_combo >= 10) {
      comboColor = AppColors.electricBlue;
    } else if (_combo >= 5) {
      comboColor = AppColors.flameOrange;
    } else {
      comboColor = AppColors.starGold;
    }

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
                    if (_combo >= 10)
                      Icon(Icons.bolt_rounded,
                          color: comboColor, size: 14)
                    else if (_combo >= 5)
                      Icon(Icons.local_fire_department_rounded,
                          color: comboColor, size: 14),
                    Text(
                      'x$_combo',
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

    if (_freezeActive) {
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
  final List<_FlyingWord> words;
  final List<_FlyingPowerUp> powerUps;
  final List<_InkSplash> splashes;
  final List<_SlashTrail> slashTrails;
  final String targetWord;
  final int combo;
  final bool freezeActive;

  _NinjaPainter({
    required this.words,
    required this.powerUps,
    required this.splashes,
    required this.slashTrails,
    required this.targetWord,
    required this.combo,
    required this.freezeActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw slash trails
    for (final t in slashTrails) {
      final p1 = Offset(t.x1 * size.width, t.y1 * size.height);
      final p2 = Offset(t.x2 * size.width, t.y2 * size.height);
      final alpha = (t.life * 0.8).clamp(0.0, 1.0);
      final strokeWidth = 4.0 + t.life * 4.0;

      // Glow layer
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
      // Core line
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = t.color.withValues(alpha: alpha)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      // Bright center
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
    for (final s in splashes) {
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
    for (final p in powerUps) {
      if (p.collected) continue;
      _drawPowerUp(canvas, size, p);
    }

    // Draw flying words
    for (final w in words) {
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
        icon = Icons.brightness_7_rounded; // bomb-like burst
    }

    // Outer glow
    canvas.drawCircle(
      Offset.zero,
      radius + 8,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Circle background
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withValues(alpha: 0.85),
    );

    // Border
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw icon using TextPainter with material icon font
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

    // Word pill background
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

    // Glow for target words
    if (w.isTarget) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = AppColors.magenta.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Freeze tint on words
    if (freezeActive) {
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
  bool shouldRepaint(covariant _NinjaPainter old) => true;
}

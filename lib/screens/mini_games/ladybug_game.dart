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
// Ladybug Letters — feed correct sight words to a growing ladybug
// ---------------------------------------------------------------------------

class _LadybugSim extends ChangeNotifier {
  double ladybugX = 0.5;
  double ladybugY = 0.7;
  double ladybugScale = 0.6;
  double ladybugAngle = 0.0;
  double legPhase = 0.0;
  int spotsCount = 3;
  bool shieldActive = false;
  bool doubleGrowthActive = false;
  double speedMultiplier = 1.0;

  double pulsePhase = 0.0;
  bool isPulsing = false;
  double pulseTimer = 0.0;

  final List<_FloatingLeaf> leaves = [];
  final List<_PollenParticle> pollen = [];
  final List<_SparkleEffect> sparkles = [];

  late List<_GardenFlower> flowers;
  late List<_GrassBlade> grassBlades;

  final _rng = Random();

  void tick(double dt) {
    legPhase += dt * 6.0 * speedMultiplier;
    ladybugAngle = sin(legPhase * 0.3) * 0.1;

    if (isPulsing) {
      pulseTimer += dt;
      pulsePhase = sin(pulseTimer * 10) * 0.05;
      if (pulseTimer > 0.5) {
        isPulsing = false;
        pulsePhase = 0.0;
      }
    }

    for (final leaf in leaves) {
      leaf.x += leaf.driftX * speedMultiplier;
      leaf.y += leaf.driftY * speedMultiplier;
      leaf.wobblePhase += dt * 1.5;

      if (leaf.x < -0.05) leaf.x = 1.05;
      if (leaf.x > 1.05) leaf.x = -0.05;
      if (leaf.y < -0.05) leaf.y = 0.55;
      if (leaf.y > 0.55) leaf.y = -0.05;
    }

    for (final p in pollen) {
      p.x += p.speedX + sin(p.phase) * 0.001;
      p.y += p.speedY;
      p.phase += dt * 2;
      if (p.y < -0.05) {
        p.y = 1.05;
        p.x = _rng.nextDouble();
      }
      if (p.x < -0.05 || p.x > 1.05) {
        p.x = _rng.nextDouble();
      }
    }

    for (final s in sparkles) {
      s.x += s.vx;
      s.y += s.vy;
      s.life -= dt * 2.0;
    }
    sparkles.removeWhere((s) => s.life <= 0);

    notifyListeners();
  }

  void reset() {
    ladybugX = 0.5;
    ladybugY = 0.7;
    ladybugScale = 0.6;
    ladybugAngle = 0.0;
    legPhase = 0.0;
    spotsCount = 3;
    shieldActive = false;
    doubleGrowthActive = false;
    speedMultiplier = 1.0;
    isPulsing = false;
    pulsePhase = 0.0;
    pulseTimer = 0.0;
    leaves.clear();
    sparkles.clear();
  }
}

class LadybugGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const LadybugGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<LadybugGame> createState() => _LadybugGameState();
}

class _LadybugGameState extends State<LadybugGame>
    with TickerProviderStateMixin {
  static const _gameId = 'ladybug_letters';
  static const _gameDuration = 60;
  static const _maxLives = 3;
  static const _maxLeaves = 6;
  static const _baseGrowth = 0.12;
  static const _shrinkAmount = 0.15;
  static const _minScale = 0.3;
  static const _maxScale = 2.5;
  static const _powerupChance = 0.15;

  final _rng = Random();
  final _sim = _LadybugSim();

  // -- Word pool
  List<String> _wordPool = [];
  String _targetWord = '';

  // -- Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _lives = _maxLives;
  int _score = 0;
  int _wordsCompleted = 0;
  int _secondsLeft = _gameDuration;
  Timer? _countdownTimer;
  Timer? _speedBoostTimer;

  // -- Animation
  late AnimationController _loopController;
  DateTime _lastFrameTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initWordPool();
    _initGarden();
    _initPollen();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_gameLoop);
  }

  void _initWordPool() {
    final all = DolchWords.allWords.map((w) => w.text).toList();
    all.shuffle(_rng);
    _wordPool = all.take(60).toList();
  }

  void _initGarden() {
    _sim.flowers = List.generate(8, (_) {
      return _GardenFlower(
        x: _rng.nextDouble(),
        y: 0.8 + _rng.nextDouble() * 0.18,
        size: 8 + _rng.nextDouble() * 12,
        petalCount: 4 + _rng.nextInt(4),
        color: [
          const Color(0xFFFF6B9D),
          const Color(0xFFFFD93D),
          const Color(0xFFFF8FA3),
          const Color(0xFFC77DFF),
          const Color(0xFFFF9E00),
        ][_rng.nextInt(5)],
        swayPhase: _rng.nextDouble() * pi * 2,
      );
    });

    _sim.grassBlades = List.generate(30, (_) {
      return _GrassBlade(
        x: _rng.nextDouble(),
        height: 20 + _rng.nextDouble() * 30,
        swayPhase: _rng.nextDouble() * pi * 2,
        shade: _rng.nextDouble(),
      );
    });
  }

  void _initPollen() {
    _sim.pollen.clear();
    for (int i = 0; i < 15; i++) {
      _sim.pollen.add(_PollenParticle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 1.5 + _rng.nextDouble() * 2.5,
        speedX: (_rng.nextDouble() - 0.5) * 0.01,
        speedY: -0.002 - _rng.nextDouble() * 0.005,
        opacity: 0.2 + _rng.nextDouble() * 0.4,
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _speedBoostTimer?.cancel();
    _loopController.stop();
    _loopController.dispose();
    _sim.dispose();
    super.dispose();
  }

  void _startGame() {
    _sim.reset();
    setState(() {
      _gameStarted = true;
      _gameOver = false;
      _lives = _maxLives;
      _score = 0;
      _wordsCompleted = 0;
      _secondsLeft = _gameDuration;
    });
    _pickNewTarget();
    _spawnLeaves();
    _loopController.repeat();
    _lastFrameTime = DateTime.now();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _gameOver) return;
      final newTime = _secondsLeft - 1;
      if (newTime <= 0) {
        _secondsLeft = 0;
        _endGame();
        setState(() {});
      } else {
        setState(() => _secondsLeft = newTime);
      }
    });
  }

  void _restartGame() {
    _countdownTimer?.cancel();
    _speedBoostTimer?.cancel();
    _loopController.stop();
    _initWordPool();
    _startGame();
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _speedBoostTimer?.cancel();
    _loopController.stop();

    final finalScore = (_wordsCompleted * _sim.ladybugScale * 10).round();
    widget.highScoreService.saveScore(_gameId, finalScore, widget.playerName);

    setState(() {
      _gameOver = true;
      _score = finalScore;
    });

    if (_wordsCompleted > 0) {
      widget.audioService.playSuccess();
      Haptics.success();
    }
  }

  void _pickNewTarget() {
    if (_wordPool.isEmpty) {
      _initWordPool();
    }
    _targetWord = _wordPool.removeAt(0);
    widget.audioService.playWord(_targetWord);
  }

  void _spawnLeaves() {
    _sim.leaves.clear();

    _sim.leaves.add(_FloatingLeaf(
      word: _targetWord,
      isCorrect: true,
      x: 0.1 + _rng.nextDouble() * 0.8,
      y: 0.1 + _rng.nextDouble() * 0.4,
      driftX: (_rng.nextDouble() - 0.5) * 0.005,
      driftY: (_rng.nextDouble() - 0.5) * 0.003,
      wobblePhase: _rng.nextDouble() * pi * 2,
      leafType: _rng.nextInt(3),
    ));

    final distractors = _wordPool.toList()..shuffle(_rng);
    final count = min(_maxLeaves - 1, distractors.length);
    for (int i = 0; i < count; i++) {
      if (distractors[i] == _targetWord) continue;
      _sim.leaves.add(_FloatingLeaf(
        word: distractors[i],
        isCorrect: false,
        x: 0.05 + _rng.nextDouble() * 0.9,
        y: 0.05 + _rng.nextDouble() * 0.5,
        driftX: (_rng.nextDouble() - 0.5) * 0.005,
        driftY: (_rng.nextDouble() - 0.5) * 0.003,
        wobblePhase: _rng.nextDouble() * pi * 2,
        leafType: _rng.nextInt(3),
      ));
    }

    if (_rng.nextDouble() < _powerupChance) {
      _spawnPowerup();
    }
  }

  void _spawnPowerup() {
    final type = _PowerupType.values[_rng.nextInt(_PowerupType.values.length)];
    _sim.leaves.add(_FloatingLeaf(
      word: '',
      isCorrect: false,
      x: 0.1 + _rng.nextDouble() * 0.8,
      y: 0.05 + _rng.nextDouble() * 0.35,
      driftX: (_rng.nextDouble() - 0.5) * 0.004,
      driftY: (_rng.nextDouble() - 0.5) * 0.002,
      wobblePhase: _rng.nextDouble() * pi * 2,
      leafType: 0,
      powerupType: type,
    ));
  }

  void _onLeafTapped(_FloatingLeaf leaf) {
    if (_gameOver || !_gameStarted) return;

    if (leaf.powerupType != null) {
      _activatePowerup(leaf.powerupType!);
      _sim.leaves.remove(leaf);
      setState(() {});
      return;
    }

    if (leaf.isCorrect) {
      _wordsCompleted++;
      final growth = _sim.doubleGrowthActive ? _baseGrowth * 2 : _baseGrowth;
      _sim.ladybugScale = min(_maxScale, _sim.ladybugScale + growth);
      _sim.spotsCount = (3 + (_sim.ladybugScale - 0.6) * 5).round().clamp(3, 12);
      _sim.doubleGrowthActive = false;

      _addSparkles(leaf.x, leaf.y);
      _sim.isPulsing = true;
      _sim.pulseTimer = 0.0;

      widget.audioService.playSuccess();
      Haptics.correct();

      _sim.ladybugX += (leaf.x - _sim.ladybugX) * 0.5;
      _sim.ladybugY += (leaf.y - _sim.ladybugY) * 0.3;

      _sim.leaves.remove(leaf);
      setState(() {});

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _gameOver) return;
        _pickNewTarget();
        _spawnLeaves();
        setState(() {});
      });
    } else {
      if (_sim.shieldActive) {
        _sim.shieldActive = false;
        Haptics.tap();
        _sim.leaves.remove(leaf);
        setState(() {});
        return;
      }

      _sim.ladybugScale = max(_minScale, _sim.ladybugScale - _shrinkAmount);
      _sim.spotsCount = (3 + (_sim.ladybugScale - 0.6) * 5).round().clamp(3, 12);

      // Gentle feedback - no harsh error sound for young children
      Haptics.wrong();

      leaf.isWrong = true;
      setState(() {
        _lives--;
      });

      if (_lives <= 0) {
        _endGame();
      }
    }
  }

  void _onReplayWord() {
    widget.audioService.playWord(_targetWord);
  }

  void _activatePowerup(_PowerupType type) {
    Haptics.correct();
    switch (type) {
      case _PowerupType.shield:
        _sim.shieldActive = true;
        break;
      case _PowerupType.speedBoost:
        _sim.speedMultiplier = 1.5;
        _secondsLeft = min(_secondsLeft + 5, _gameDuration);
        _speedBoostTimer?.cancel();
        _speedBoostTimer = Timer(const Duration(seconds: 8), () {
          if (mounted) _sim.speedMultiplier = 1.0;
        });
        setState(() {});
        break;
      case _PowerupType.doubleGrowth:
        _sim.doubleGrowthActive = true;
        break;
      case _PowerupType.gardenRain:
        _sim.leaves.removeWhere((l) => !l.isCorrect && l.powerupType == null);
        break;
    }
  }

  void _addSparkles(double x, double y) {
    for (int i = 0; i < 8; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 0.02 + _rng.nextDouble() * 0.04;
      _sim.sparkles.add(_SparkleEffect(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: 1.0,
        size: 2 + _rng.nextDouble() * 4,
        color: [
          AppColors.starGold,
          AppColors.success,
          AppColors.emerald,
          const Color(0xFFFFD93D),
        ][_rng.nextInt(4)],
      ));
    }
  }

  void _gameLoop() {
    if (_gameOver || !_gameStarted) return;

    final now = DateTime.now();
    final dt = now.difference(_lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = now;
    if (dt <= 0 || dt > 0.1) return;

    _sim.tick(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GardenBackgroundPainter(sim: _sim),
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PollenPainter(sim: _sim),
                ),
              ),
            ),
          ),

          if (_gameStarted && !_gameOver)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _LadybugPainter(sim: _sim),
                  ),
                ),
              ),
            ),

          ..._sim.leaves.map((leaf) => _buildLeafWidget(leaf)),

          if (_sim.sparkles.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SparklePainter(sim: _sim),
                  ),
                ),
              ),
            ),

          if (_gameStarted) SafeArea(child: _buildHUD(context)),

          if (_gameOver) _buildGameOver(context),

          if (!_gameStarted) _buildGetReady(context),
        ],
      ),
    );
  }

  Widget _buildLeafWidget(_FloatingLeaf leaf) {
    final size = MediaQuery.of(context).size;
    final leafX = leaf.x * size.width;
    final leafY = leaf.y * size.height;
    final wobble = sin(leaf.wobblePhase) * 3;

    if (leaf.powerupType != null) {
      return Positioned(
        left: leafX - 28,
        top: leafY - 28 + wobble,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onLeafTapped(leaf),
          child: SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _PowerupPainter(
                type: leaf.powerupType!,
                phase: leaf.wobblePhase,
              ),
            ),
          ),
        ),
      );
    }

    final leafColor = leaf.isCorrect
        ? AppColors.success
        : leaf.isWrong
            ? AppColors.error
            : const Color(0xFF4A8C3F);

    return Positioned(
      left: leafX - 45,
      top: leafY - 24 + wobble,
      child: GestureDetector(
        onTap: () => _onLeafTapped(leaf),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: leafColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: leafColor.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            leaf.word,
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHUD(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.primaryText,
                iconSize: 28,
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_maxLives, (i) {
                  final alive = i < _lives;
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      alive
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: alive ? AppColors.error : AppColors.secondaryText,
                      size: 22,
                    ),
                  );
                }),
              ),

              const Spacer(),

              if (_sim.shieldActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: AppColors.emerald, size: 18),
                ),

              if (_sim.doubleGrowthActive)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('2x',
                      style: AppFonts.fredoka(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error)),
                ),

              const Spacer(),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _secondsLeft <= 10
                        ? AppColors.error.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  '$_secondsLeft',
                  style: AppFonts.fredoka(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _secondsLeft <= 10
                        ? AppColors.error
                        : AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          GestureDetector(
            onTap: _onReplayWord,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.starGold.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.starGold.withValues(alpha: 0.1),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_up_rounded,
                      color: AppColors.starGold, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Find: $_targetWord',
                    style: AppFonts.fredoka(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.starGold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Size: ',
                style: AppFonts.nunito(
                  fontSize: 12,
                  color: AppColors.secondaryText,
                ),
              ),
              SizedBox(
                width: 80,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ((_sim.ladybugScale - _minScale) /
                            (_maxScale - _minScale))
                        .clamp(0.0, 1.0),
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation(
                      Color.lerp(AppColors.error, AppColors.success,
                          ((_sim.ladybugScale - _minScale) /
                                  (_maxScale - _minScale))
                              .clamp(0.0, 1.0))!,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$_wordsCompleted',
                style: AppFonts.fredoka(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
              const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.success, size: 14),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameOver(BuildContext context) {
    final highScore = widget.highScoreService.getPersonalBest(_gameId);
    final isNewBest = _score >= highScore && _score > 0;

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.emerald.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.emerald.withValues(alpha: 0.15),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _lives <= 0 ? 'Oh No!' : "Time's Up!",
                style: AppFonts.fredoka(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _LadybugStaticPainter(
                    scale: _sim.ladybugScale.clamp(0.5, 1.2),
                    spotsCount: _sim.spotsCount,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.starGold, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    '$_score',
                    style: AppFonts.fredoka(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: AppColors.starGold,
                    ),
                  ),
                ],
              ),
              if (isNewBest) ...[
                const SizedBox(height: 4),
                Text(
                  'NEW BEST!',
                  style: AppFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.starGold,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '$_wordsCompleted words fed to ladybug!',
                style: AppFonts.nunito(
                  fontSize: 14,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Great job, ${widget.playerName}!',
                style: AppFonts.nunito(
                  fontSize: 16,
                  color: AppColors.secondaryText,
                ),
              ),
              if (highScore > 0 && !isNewBest) ...[
                const SizedBox(height: 4),
                Text(
                  'Best: $highScore',
                  style: AppFonts.nunito(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _restartGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Play Again',
                      style: AppFonts.fredoka(
                          fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: BorderSide(
                          color:
                              AppColors.secondaryText.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: AppFonts.fredoka(
                          fontSize: 18, fontWeight: FontWeight.w500),
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

  Widget _buildGetReady(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.primaryText,
                iconSize: 28,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: _LadybugStaticPainter(
                        scale: 0.8,
                        spotsCount: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ladybug Letters',
                    style: AppFonts.fredoka(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the correct word to\nfeed the ladybug!',
                    textAlign: TextAlign.center,
                    style: AppFonts.nunito(
                      fontSize: 16,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _startGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Start!',
                      style: AppFonts.fredoka(
                          fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════════════════════════════════════

enum _PowerupType { shield, speedBoost, doubleGrowth, gardenRain }

class _FloatingLeaf {
  String word;
  bool isCorrect;
  double x;
  double y;
  double driftX;
  double driftY;
  double wobblePhase;
  int leafType;
  _PowerupType? powerupType;
  bool isWrong = false;

  _FloatingLeaf({
    required this.word,
    required this.isCorrect,
    required this.x,
    required this.y,
    required this.driftX,
    required this.driftY,
    required this.wobblePhase,
    required this.leafType,
    this.powerupType,
  });
}

class _PollenParticle {
  double x;
  double y;
  final double size;
  final double speedX;
  final double speedY;
  final double opacity;
  double phase;

  _PollenParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
    required this.phase,
  });
}

class _SparkleEffect {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double size;
  final Color color;

  _SparkleEffect({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.color,
  });
}

class _GardenFlower {
  final double x;
  final double y;
  final double size;
  final int petalCount;
  final Color color;
  final double swayPhase;

  _GardenFlower({
    required this.x,
    required this.y,
    required this.size,
    required this.petalCount,
    required this.color,
    required this.swayPhase,
  });
}

class _GrassBlade {
  final double x;
  final double height;
  final double swayPhase;
  final double shade;

  _GrassBlade({
    required this.x,
    required this.height,
    required this.swayPhase,
    required this.shade,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Custom Painters
// ═══════════════════════════════════════════════════════════════════════════

class _LadybugPainter extends CustomPainter {
  final _LadybugSim sim;

  _LadybugPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    _paintLadybug(
      canvas, size,
      x: sim.ladybugX,
      y: sim.ladybugY,
      scale: sim.ladybugScale + sim.pulsePhase,
      angle: sim.ladybugAngle,
      legPhase: sim.legPhase,
      spotsCount: sim.spotsCount,
      shieldActive: sim.shieldActive,
      doubleGrowthActive: sim.doubleGrowthActive,
    );
  }

  @override
  bool shouldRepaint(covariant _LadybugPainter old) => false;
}

class _LadybugStaticPainter extends CustomPainter {
  final double scale;
  final int spotsCount;

  _LadybugStaticPainter({required this.scale, required this.spotsCount});

  @override
  void paint(Canvas canvas, Size size) {
    _paintLadybug(
      canvas, size,
      x: 0.5, y: 0.5,
      scale: scale,
      angle: 0, legPhase: 0,
      spotsCount: spotsCount,
      shieldActive: false, doubleGrowthActive: false,
    );
  }

  @override
  bool shouldRepaint(covariant _LadybugStaticPainter old) =>
      old.scale != scale || old.spotsCount != spotsCount;
}

void _paintLadybug(
  Canvas canvas, Size size, {
  required double x,
  required double y,
  required double scale,
  required double angle,
  required double legPhase,
  required int spotsCount,
  required bool shieldActive,
  required bool doubleGrowthActive,
}) {
  final cx = x * size.width;
  final cy = y * size.height;
  final s = scale * 28;

  canvas.save();
  canvas.translate(cx, cy);
  canvas.rotate(angle);

  if (shieldActive) {
    canvas.drawCircle(
      Offset.zero,
      s + 12,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      Offset.zero,
      s + 10,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  if (doubleGrowthActive) {
    canvas.drawCircle(
      Offset.zero,
      s + 8,
      Paint()
        ..color = const Color(0xFFFF4757).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  final legPaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round;

  for (int i = 0; i < 3; i++) {
    final yOff = -s * 0.5 + i * s * 0.5;
    final legAnim = sin(legPhase + i * 1.2) * 3;
    canvas.drawLine(
      Offset(-s * 0.7, yOff),
      Offset(-s * 1.2 - legAnim, yOff + 4 + legAnim.abs()),
      legPaint,
    );
    canvas.drawLine(
      Offset(s * 0.7, yOff),
      Offset(s * 1.2 + legAnim, yOff + 4 + legAnim.abs()),
      legPaint,
    );
  }

  canvas.drawOval(
    Rect.fromCenter(center: const Offset(2, 3), width: s * 2, height: s * 2.2),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );

  final shellRect =
      Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 2.2);
  final shellPaint = Paint()
    ..shader = const RadialGradient(
      center: Alignment(-0.3, -0.3),
      colors: [Color(0xFFFF3333), Color(0xFFCC1111)],
    ).createShader(shellRect);
  canvas.drawOval(shellRect, shellPaint);

  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(-s * 0.25, -s * 0.35),
        width: s * 0.6,
        height: s * 0.4),
    Paint()..color = Colors.white.withValues(alpha: 0.2),
  );

  canvas.drawLine(
    Offset(0, -s * 0.9),
    Offset(0, s * 0.9),
    Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 1.5,
  );

  final spotPaint = Paint()..color = const Color(0xFF1A1A1A);
  final spotPositions = _getSpotPositions(spotsCount, s);
  for (final pos in spotPositions) {
    canvas.drawCircle(pos, s * 0.15, spotPaint);
  }

  final headY = -s * 1.0;
  canvas.drawCircle(
    Offset(0, headY),
    s * 0.5,
    Paint()..color = const Color(0xFF1A1A1A),
  );

  final eyeR = s * 0.14;
  canvas.drawCircle(
    Offset(-s * 0.2, headY - s * 0.05),
    eyeR,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    Offset(s * 0.2, headY - s * 0.05),
    eyeR,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    Offset(-s * 0.18, headY - s * 0.03),
    eyeR * 0.55,
    Paint()..color = const Color(0xFF1A1A1A),
  );
  canvas.drawCircle(
    Offset(s * 0.22, headY - s * 0.03),
    eyeR * 0.55,
    Paint()..color = const Color(0xFF1A1A1A),
  );

  final antennaePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final leftAntenna = Path()
    ..moveTo(-s * 0.15, headY - s * 0.4)
    ..quadraticBezierTo(
        -s * 0.5, headY - s * 1.0, -s * 0.4, headY - s * 1.2);
  canvas.drawPath(leftAntenna, antennaePaint);
  canvas.drawCircle(
    Offset(-s * 0.4, headY - s * 1.2),
    2.5,
    Paint()..color = const Color(0xFF1A1A1A),
  );

  final rightAntenna = Path()
    ..moveTo(s * 0.15, headY - s * 0.4)
    ..quadraticBezierTo(
        s * 0.5, headY - s * 1.0, s * 0.4, headY - s * 1.2);
  canvas.drawPath(rightAntenna, antennaePaint);
  canvas.drawCircle(
    Offset(s * 0.4, headY - s * 1.2),
    2.5,
    Paint()..color = const Color(0xFF1A1A1A),
  );

  final smilePath = Path()
    ..moveTo(-s * 0.15, headY + s * 0.15)
    ..quadraticBezierTo(0, headY + s * 0.3, s * 0.15, headY + s * 0.15);
  canvas.drawPath(
    smilePath,
    Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round,
  );

  canvas.restore();
}

List<Offset> _getSpotPositions(int count, double s) {
  final positions = <Offset>[];
  final allPositions = [
    Offset(-s * 0.35, -s * 0.35),
    Offset(s * 0.35, -s * 0.35),
    Offset(-s * 0.4, s * 0.15),
    Offset(s * 0.4, s * 0.15),
    Offset(-s * 0.2, s * 0.5),
    Offset(s * 0.2, s * 0.5),
    Offset(-s * 0.55, -s * 0.05),
    Offset(s * 0.55, -s * 0.05),
    Offset(-s * 0.15, -s * 0.6),
    Offset(s * 0.15, -s * 0.6),
    Offset(-s * 0.5, s * 0.4),
    Offset(s * 0.5, s * 0.4),
  ];
  for (int i = 0; i < min(count, allPositions.length); i++) {
    positions.add(allPositions[i]);
  }
  return positions;
}

class _GardenBackgroundPainter extends CustomPainter {
  final _LadybugSim sim;

  _GardenBackgroundPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    final time = sim.legPhase;

    final skyRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1628),
            Color(0xFF0D2818),
            Color(0xFF1A3A2A),
          ],
        ).createShader(skyRect),
    );

    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.08),
      18,
      Paint()
        ..color = const Color(0xFFFFF8DC)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.08),
      14,
      Paint()..color = const Color(0xFFFFF8DC),
    );

    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    final rng = Random(42);
    for (int i = 0; i < 20; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = rng.nextDouble() * size.height * 0.3;
      final twinkle = (sin(time * 0.5 + i * 1.3) * 0.3 + 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(sx, sy),
        0.8 + rng.nextDouble(),
        starPaint..color = Colors.white.withValues(alpha: 0.3 * twinkle),
      );
    }

    final groundPath = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
          size.width * 0.3, size.height * 0.72, size.width * 0.5, size.height * 0.74)
      ..quadraticBezierTo(
          size.width * 0.7, size.height * 0.76, size.width, size.height * 0.73)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      groundPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1B4332),
            Color(0xFF0D2818),
          ],
        ).createShader(Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3)),
    );

    for (final blade in sim.grassBlades) {
      final bx = blade.x * size.width;
      final baseY = size.height * 0.78;
      final sway = sin(time * 0.8 + blade.swayPhase) * 4;
      final green = Color.lerp(
        const Color(0xFF2D6A4F),
        const Color(0xFF40916C),
        blade.shade,
      )!;
      final grassPath = Path()
        ..moveTo(bx - 1, baseY)
        ..quadraticBezierTo(
            bx + sway, baseY - blade.height * 0.6, bx + sway * 1.5, baseY - blade.height)
        ..quadraticBezierTo(
            bx + sway, baseY - blade.height * 0.6, bx + 2, baseY)
        ..close();
      canvas.drawPath(grassPath, Paint()..color = green);
    }

    for (final flower in sim.flowers) {
      final fx = flower.x * size.width;
      final fy = flower.y * size.height;
      final sway = sin(time * 0.5 + flower.swayPhase) * 2;

      canvas.drawLine(
        Offset(fx, fy),
        Offset(fx + sway, fy - flower.size * 1.5),
        Paint()
          ..color = const Color(0xFF2D6A4F)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );

      final petalCenter = Offset(fx + sway, fy - flower.size * 1.5);
      for (int i = 0; i < flower.petalCount; i++) {
        final pAngle = (i / flower.petalCount) * pi * 2;
        final px = petalCenter.dx + cos(pAngle) * flower.size * 0.5;
        final py = petalCenter.dy + sin(pAngle) * flower.size * 0.5;
        canvas.drawCircle(
          Offset(px, py),
          flower.size * 0.25,
          Paint()..color = flower.color.withValues(alpha: 0.7),
        );
      }
      canvas.drawCircle(
        petalCenter,
        flower.size * 0.15,
        Paint()..color = const Color(0xFFFFD93D),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GardenBackgroundPainter old) => false;
}

class _PollenPainter extends CustomPainter {
  final _LadybugSim sim;

  _PollenPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in sim.pollen) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        Paint()
          ..color = const Color(0xFFFFF8DC).withValues(alpha: p.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PollenPainter old) => false;
}

class _SparklePainter extends CustomPainter {
  final _LadybugSim sim;

  _SparklePainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sim.sparkles) {
      final alpha = s.life.clamp(0.0, 1.0);
      final paint = Paint()
        ..color = s.color.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size * alpha,
        paint,
      );
      final linePaint = Paint()
        ..color = s.color.withValues(alpha: alpha * 0.6)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      final r = s.size * alpha * 1.5;
      final sx = s.x * size.width;
      final sy = s.y * size.height;
      canvas.drawLine(Offset(sx - r, sy), Offset(sx + r, sy), linePaint);
      canvas.drawLine(Offset(sx, sy - r), Offset(sx, sy + r), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => false;
}

class _PowerupPainter extends CustomPainter {
  final _PowerupType type;
  final double phase;

  _PowerupPainter({required this.type, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final glow = (sin(phase * 3) * 0.3 + 0.7).clamp(0.0, 1.0);

    switch (type) {
      case _PowerupType.shield:
        canvas.drawCircle(
          Offset(cx, cy),
          18,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.3 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        final leafPath = Path()
          ..moveTo(cx, cy - 14)
          ..quadraticBezierTo(cx + 16, cy - 4, cx, cy + 14)
          ..quadraticBezierTo(cx - 16, cy - 4, cx, cy - 14);
        canvas.drawPath(
          leafPath,
          Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.8),
        );
        canvas.drawLine(
          Offset(cx, cy - 10),
          Offset(cx, cy + 10),
          Paint()
            ..color = const Color(0xFF0D9668)
            ..strokeWidth = 1,
        );
        break;

      case _PowerupType.speedBoost:
        canvas.drawCircle(
          Offset(cx, cy),
          16,
          Paint()
            ..color = const Color(0xFFFFD93D).withValues(alpha: 0.3 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        final lWing = Path()
          ..moveTo(cx, cy)
          ..quadraticBezierTo(cx - 18, cy - 14, cx - 6, cy - 4);
        canvas.drawPath(
          lWing,
          Paint()
            ..color = const Color(0xFFFFD93D).withValues(alpha: 0.8)
            ..style = PaintingStyle.fill,
        );
        final rWing = Path()
          ..moveTo(cx, cy)
          ..quadraticBezierTo(cx + 18, cy - 14, cx + 6, cy - 4);
        canvas.drawPath(
          rWing,
          Paint()
            ..color = const Color(0xFFFFD93D).withValues(alpha: 0.8)
            ..style = PaintingStyle.fill,
        );
        break;

      case _PowerupType.doubleGrowth:
        canvas.drawCircle(
          Offset(cx, cy),
          16,
          Paint()
            ..color = const Color(0xFFFF4757).withValues(alpha: 0.3 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          Offset(cx, cy),
          12,
          Paint()..color = const Color(0xFFFF3333).withValues(alpha: 0.8),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '2x',
            style: AppFonts.fredoka(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
        break;

      case _PowerupType.gardenRain:
        canvas.drawCircle(
          Offset(cx, cy),
          16,
          Paint()
            ..color = const Color(0xFF00D4FF).withValues(alpha: 0.3 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        final dropPath = Path()
          ..moveTo(cx, cy - 14)
          ..quadraticBezierTo(cx + 12, cy + 2, cx, cy + 12)
          ..quadraticBezierTo(cx - 12, cy + 2, cx, cy - 14);
        canvas.drawPath(
          dropPath,
          Paint()..color = const Color(0xFF00D4FF).withValues(alpha: 0.8),
        );
        canvas.drawCircle(
          Offset(cx - 3, cy - 2),
          3,
          Paint()..color = Colors.white.withValues(alpha: 0.4),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PowerupPainter oldDelegate) => true;
}

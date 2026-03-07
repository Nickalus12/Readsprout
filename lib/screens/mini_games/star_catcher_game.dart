import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Star Catcher -- Space-themed letter constellation game
// Tap stars with letters in order to spell words and form constellations.
// ---------------------------------------------------------------------------

class StarCatcherGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const StarCatcherGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<StarCatcherGame> createState() => _StarCatcherGameState();
}

// ── Data models ────────────────────────────────────────────────────────────

class _Star {
  final int id;
  final String letter;
  final bool isCorrect;
  final int correctIndex; // which position in word (-1 if distractor)
  double x, y; // normalised 0..1
  double vx, vy;
  double twinklePhase;
  double radius;
  bool caught;
  double wobbleAmount;
  double wobbleTimer;
  double glowPulse;

  _Star({
    required this.id,
    required this.letter,
    required this.isCorrect,
    required this.correctIndex,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.twinklePhase,
    required this.radius,
  })  : caught = false,
        wobbleAmount = 0,
        wobbleTimer = 0,
        glowPulse = 0;
}

class _ConstellationLine {
  final Offset from;
  final Offset to;
  double opacity;
  _ConstellationLine({
    required this.from,
    required this.to,
    this.opacity = 0,
  });
}

class _SparkleParticle {
  double x, y, vx, vy, size, life;
  Color color;
  _SparkleParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
  });
}

class _ShootingStar {
  double x, y, vx, vy, life, length;
  _ShootingStar({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.length,
  });
}

// ── State ──────────────────────────────────────────────────────────────────

class _StarCatcherGameState extends State<StarCatcherGame>
    with SingleTickerProviderStateMixin {
  final _rng = Random();

  // Game config
  static const int _gameDurationSecs = 60;
  static const double _starZoneTop = 0.18;
  static const double _starZoneBottom = 0.88;

  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _wordsCompleted = 0;
  int _timeRemaining = _gameDurationSecs;
  Timer? _gameTimer;

  // Current word
  List<String> _wordPool = [];
  String _currentWord = '';
  int _nextLetterIndex = 0;

  // Stars
  List<_Star> _stars = [];
  int _nextStarId = 0;

  // Constellation lines (connect caught stars)
  final List<_ConstellationLine> _constellationLines = [];
  final List<Offset> _caughtPositions = [];

  // Visual effects
  final List<_SparkleParticle> _particles = [];
  final List<_ShootingStar> _shootingStars = [];
  double _flashOpacity = 0;
  Color _flashColor = Colors.white;

  // Background stars (static twinkling)
  late List<_BackgroundStar> _bgStars;

  // Animation
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;

  // Astronaut bob
  double _astronautBob = 0;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _wordPool = _buildWordPool();

    // Background stars
    _bgStars = List.generate(50, (_) => _BackgroundStar(
      x: _rng.nextDouble(),
      y: _rng.nextDouble(),
      size: 0.5 + _rng.nextDouble() * 2,
      phase: _rng.nextDouble() * pi * 2,
      speed: 0.5 + _rng.nextDouble() * 2,
    ));

    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gameTimer?.cancel();
    _sessionTimer.stop();
    super.dispose();
  }

  List<String> _buildWordPool() {
    final pool = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        pool.addAll(DolchWords.wordsForLevel(level).map((w) => w.text));
      }
    }
    if (pool.isEmpty) {
      pool.addAll(DolchWords.wordsForLevel(1).map((w) => w.text));
    }
    pool.shuffle(_rng);
    return pool;
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _gameOver = false;
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _wordsCompleted = 0;
      _timeRemaining = _gameDurationSecs;
      _stars = [];
      _constellationLines.clear();
      _caughtPositions.clear();
      _particles.clear();
      _shootingStars.clear();
      _nextLetterIndex = 0;
      _wordPool.shuffle(_rng);
    });
    _nextWord();
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _timeRemaining--;
        if (_timeRemaining <= 0) {
          _endGame();
        }
      });
    });
  }

  void _endGame() {
    _gameTimer?.cancel();
    widget.audioService.playError();
    setState(() => _gameOver = true);
    _awardMiniGameStickers();
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned =
        StickerDefinitions.miniGameStickersForScore('star_catcher', _score);
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

  void _nextWord() {
    if (_gameOver) return;
    if (_wordPool.isEmpty) _wordPool = _buildWordPool();
    _currentWord = _wordPool.removeAt(0);
    _nextLetterIndex = 0;
    _constellationLines.clear();
    _caughtPositions.clear();
    _spawnStars();

    // Speak the word
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_gameOver) {
        widget.audioService.playWord(_currentWord);
      }
    });
  }

  void _spawnStars() {
    _stars.clear();
    final letters = _currentWord.split('');
    final usedPositions = <Offset>[];

    // Place correct letter stars
    for (int i = 0; i < letters.length; i++) {
      final pos = _findOpenPosition(usedPositions);
      usedPositions.add(pos);
      _stars.add(_Star(
        id: _nextStarId++,
        letter: letters[i].toUpperCase(),
        isCorrect: true,
        correctIndex: i,
        x: pos.dx,
        y: pos.dy,
        vx: (_rng.nextDouble() - 0.5) * 0.06,
        vy: (_rng.nextDouble() - 0.5) * 0.04,
        twinklePhase: _rng.nextDouble() * pi * 2,
        radius: 28,
      ));
    }

    // Add distractor stars (3-5 random letters)
    final distractorCount = 3 + _rng.nextInt(3);
    const allLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (int i = 0; i < distractorCount; i++) {
      final pos = _findOpenPosition(usedPositions);
      usedPositions.add(pos);
      String letter;
      do {
        letter = allLetters[_rng.nextInt(allLetters.length)];
      } while (_currentWord.toUpperCase().contains(letter) &&
          _rng.nextDouble() > 0.3);

      _stars.add(_Star(
        id: _nextStarId++,
        letter: letter,
        isCorrect: false,
        correctIndex: -1,
        x: pos.dx,
        y: pos.dy,
        vx: (_rng.nextDouble() - 0.5) * 0.06,
        vy: (_rng.nextDouble() - 0.5) * 0.04,
        twinklePhase: _rng.nextDouble() * pi * 2,
        radius: 28,
      ));
    }
    _stars.shuffle(_rng);
  }

  Offset _findOpenPosition(List<Offset> existing) {
    const margin = 0.08;
    for (int attempt = 0; attempt < 50; attempt++) {
      final x = margin + _rng.nextDouble() * (1.0 - 2 * margin);
      final y = _starZoneTop + 0.05 +
          _rng.nextDouble() * (_starZoneBottom - _starZoneTop - 0.1);
      bool tooClose = false;
      for (final e in existing) {
        if ((e.dx - x).abs() < 0.12 && (e.dy - y).abs() < 0.1) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) return Offset(x, y);
    }
    return Offset(
      margin + _rng.nextDouble() * (1.0 - 2 * margin),
      _starZoneTop + _rng.nextDouble() * (_starZoneBottom - _starZoneTop),
    );
  }

  // ── Star tap handling ────────────────────────────────────────────────────

  void _onStarTap(_Star star) {
    if (star.caught || _gameOver) return;

    final expectedLetter =
        _currentWord[_nextLetterIndex].toUpperCase();
    final tappedLetter = star.letter.toUpperCase();

    if (star.isCorrect && star.correctIndex == _nextLetterIndex) {
      // Correct tap!
      _onCorrectTap(star);
    } else if (tappedLetter == expectedLetter && !star.caught) {
      // Could be a duplicate letter matching -- check if this is a valid correct star
      // for the current index
      final validStar = _stars.firstWhere(
        (s) => s.isCorrect && s.correctIndex == _nextLetterIndex && !s.caught,
        orElse: () => star,
      );
      if (validStar.id != star.id && tappedLetter == expectedLetter) {
        // This star has the right letter but wrong index. Wobble it.
        _onWrongTap(star);
      } else {
        _onCorrectTap(star);
      }
    } else {
      _onWrongTap(star);
    }
  }

  void _onCorrectTap(_Star star) {
    setState(() {
      star.caught = true;
      star.glowPulse = 1.0;
      _combo++;
      if (_combo > _bestCombo) _bestCombo = _combo;

      // Score: base 10 + combo bonus + speed bonus
      final comboBonus = (_combo > 1) ? (_combo - 1) * 5 : 0;
      final timeBonus = (_timeRemaining > 30) ? 5 : 0;
      _score += 10 + comboBonus + timeBonus;

      // Track caught position for constellation lines
      final pos = Offset(star.x, star.y);
      if (_caughtPositions.isNotEmpty) {
        _constellationLines.add(_ConstellationLine(
          from: _caughtPositions.last,
          to: pos,
          opacity: 1.0,
        ));
      }
      _caughtPositions.add(pos);

      _nextLetterIndex++;
    });

    widget.audioService.playLetter(star.letter.toLowerCase());

    // Spawn sparkles
    if (_screenSize != Size.zero) {
      _spawnSparkles(
        star.x * _screenSize.width,
        star.y * _screenSize.height,
        AppColors.starGold,
        8,
      );
    }

    // Shooting star on combo >= 3
    if (_combo >= 3 && _screenSize != Size.zero) {
      _spawnShootingStar();
    }

    // Check word complete
    if (_nextLetterIndex >= _currentWord.length) {
      widget.audioService.playSuccess();
      Haptics.success();
      _wordsCompleted++;
      _flashOpacity = 0.3;
      _flashColor = AppColors.starGold;

      // Big sparkle burst for word completion
      if (_screenSize != Size.zero) {
        for (final caught in _caughtPositions) {
          _spawnSparkles(
            caught.dx * _screenSize.width,
            caught.dy * _screenSize.height,
            AppColors.confettiColors[_rng.nextInt(AppColors.confettiColors.length)],
            6,
          );
        }
      }

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && !_gameOver) _nextWord();
      });
    } else {
      widget.audioService.playSuccess();
      Haptics.correct();
    }
  }

  void _onWrongTap(_Star star) {
    setState(() {
      star.wobbleAmount = 12;
      star.wobbleTimer = 0.4;
      _combo = 0;
    });
    widget.audioService.playError();
    Haptics.wrong();
  }

  // ── Effects ──────────────────────────────────────────────────────────────

  void _spawnSparkles(double cx, double cy, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 60 + _rng.nextDouble() * 120;
      _particles.add(_SparkleParticle(
        x: cx,
        y: cy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 30,
        size: 2 + _rng.nextDouble() * 4,
        life: 1.0,
        color: Color.lerp(color, Colors.white, _rng.nextDouble() * 0.5)!,
      ));
    }
  }

  void _spawnShootingStar() {
    final startX = _rng.nextDouble() * _screenSize.width;
    _shootingStars.add(_ShootingStar(
      x: startX,
      y: 0,
      vx: (_rng.nextDouble() - 0.5) * 200,
      vy: 300 + _rng.nextDouble() * 200,
      life: 1.0,
      length: 30 + _rng.nextDouble() * 40,
    ));
  }

  // ── Tick ──────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final dt = dtRaw.clamp(0.0, 0.05);
    if (_screenSize == Size.zero || !_gameStarted || _gameOver) {
      // Still update astronaut bob for start screen
      _astronautBob += dt * 1.5;
      if (mounted) setState(() {});
      return;
    }

    _astronautBob += dt * 1.5;

    // Update stars
    for (final s in _stars) {
      if (s.caught) {
        s.glowPulse = (s.glowPulse - dt * 0.5).clamp(0.0, 1.0);
        continue;
      }

      s.twinklePhase += dt * s.radius * 0.05;
      s.x += s.vx * dt;
      s.y += s.vy * dt;

      // Wobble decay
      if (s.wobbleTimer > 0) {
        s.wobbleTimer -= dt;
        if (s.wobbleTimer <= 0) s.wobbleAmount = 0;
      }

      // Bounce off edges
      final rNorm = s.radius / _screenSize.width;
      final rNormY = s.radius / _screenSize.height;
      if (s.x < rNorm) { s.x = rNorm; s.vx = s.vx.abs(); }
      if (s.x > 1 - rNorm) { s.x = 1 - rNorm; s.vx = -s.vx.abs(); }
      if (s.y < _starZoneTop + rNormY) {
        s.y = _starZoneTop + rNormY;
        s.vy = s.vy.abs();
      }
      if (s.y > _starZoneBottom - rNormY) {
        s.y = _starZoneBottom - rNormY;
        s.vy = -s.vy.abs();
      }

      // Random nudges
      if (_rng.nextDouble() < 0.02) {
        s.vx += (_rng.nextDouble() - 0.5) * 0.02;
        s.vy += (_rng.nextDouble() - 0.5) * 0.015;
      }

      // Dampen
      s.vx *= 0.998;
      s.vy *= 0.998;
      final speed = sqrt(s.vx * s.vx + s.vy * s.vy);
      if (speed > 0.15) {
        s.vx = s.vx / speed * 0.15;
        s.vy = s.vy / speed * 0.15;
      }
      if (speed < 0.01) {
        s.vx += (_rng.nextDouble() - 0.5) * 0.03;
        s.vy += (_rng.nextDouble() - 0.5) * 0.02;
      }
    }

    // Update particles
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 60 * dt; // gravity
      p.life -= dt * 1.5;
    }
    _particles.removeWhere((p) => p.life <= 0);

    // Update shooting stars
    for (final s in _shootingStars) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt * 1.2;
    }
    _shootingStars.removeWhere((s) => s.life <= 0);

    // Flash decay
    if (_flashOpacity > 0) {
      _flashOpacity = (_flashOpacity - dt * 2).clamp(0.0, 1.0);
    }

    // Constellation line fade-in
    for (final line in _constellationLines) {
      if (line.opacity < 1.0) {
        line.opacity = (line.opacity + dt * 4).clamp(0.0, 1.0);
      }
    }

    if (mounted) setState(() {});
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05051A),
      body: LayoutBuilder(builder: (context, constraints) {
        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        return _gameOver
            ? _buildGameOver()
            : _gameStarted
                ? _buildGameplay()
                : _buildStartScreen();
      }),
    );
  }

  // ── Start screen ─────────────────────────────────────────────────────────

  void _playIntro() {
    widget.audioService.playWord('star_catcher');
  }

  Widget _buildStartScreen() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_gameStarted) _playIntro();
    });

    return Stack(
      children: [
        _buildSpaceBackground(),
        SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.primaryText),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              // Astronaut icon
              Transform.translate(
                offset: Offset(0, sin(_astronautBob) * 6),
                child: const Icon(Icons.rocket_launch_rounded,
                    size: 64, color: AppColors.electricBlue),
              ),
              const SizedBox(height: 16),
              Text(
                'Star Catcher',
                style: GoogleFonts.fredoka(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.6),
                      blurRadius: 24,
                    ),
                    Shadow(
                      color: AppColors.violet.withValues(alpha: 0.4),
                      blurRadius: 48,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Speaker icon
              GestureDetector(
                onTap: _playIntro,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.electricBlue.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.electricBlue.withValues(alpha: 0.4),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: AppColors.electricBlue, size: 40),
                ),
              ),
              const Spacer(flex: 2),
              // Play button
              GestureDetector(
                onTap: _startGame,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.electricBlue.withValues(alpha: 0.3),
                        AppColors.violet.withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: AppColors.electricBlue.withValues(alpha: 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 32),
                      const SizedBox(width: 8),
                      Text(
                        'Play!',
                        style: GoogleFonts.fredoka(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ],
    );
  }

  // ── Gameplay ─────────────────────────────────────────────────────────────

  Widget _buildGameplay() {
    return Stack(
      children: [
        _buildSpaceBackground(),

        // Constellation lines
        CustomPaint(
          size: _screenSize,
          painter: _ConstellationPainter(
            lines: _constellationLines,
            screenSize: _screenSize,
          ),
        ),

        // Stars
        ..._stars.map((s) => _buildStarWidget(s)),

        // HUD
        SafeArea(
          child: Column(
            children: [
              _buildHUD(),
              _buildWordDisplay(),
            ],
          ),
        ),

        // Particles overlay
        IgnorePointer(
          child: CustomPaint(
            size: _screenSize,
            painter: _SparklesPainter(
              particles: _particles,
              shootingStars: _shootingStars,
            ),
          ),
        ),

        // Flash overlay
        if (_flashOpacity > 0)
          IgnorePointer(
            child: Container(
              color: _flashColor
                  .withValues(alpha: _flashOpacity.clamp(0.0, 0.4)),
            ),
          ),
      ],
    );
  }

  Widget _buildHUD() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
          ),
          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: AppColors.starGold),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: GoogleFonts.fredoka(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.starGold,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Combo
          if (_combo >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.electricBlue.withValues(alpha: 0.3),
                    AppColors.violet.withValues(alpha: 0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.electricBlue.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '${_combo}x',
                style: GoogleFonts.fredoka(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.electricBlue,
                ),
              ),
            ),
          const Spacer(),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _timeRemaining <= 10
                  ? AppColors.error.withValues(alpha: 0.2)
                  : AppColors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: _timeRemaining <= 10
                  ? Border.all(color: AppColors.error.withValues(alpha: 0.5))
                  : null,
            ),
            child: Text(
              '${_timeRemaining}s',
              style: GoogleFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _timeRemaining <= 10
                    ? AppColors.error
                    : AppColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordDisplay() {
    return GestureDetector(
      onTap: () {
        if (!_gameOver) widget.audioService.playWord(_currentWord);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.violet.withValues(alpha: 0.12),
              AppColors.electricBlue.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.violet.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volume_up_rounded,
                color: AppColors.violet, size: 24),
            const SizedBox(width: 10),
            // Show letters with progress
            ...List.generate(_currentWord.length, (i) {
              final letter = _currentWord[i].toUpperCase();
              final isCaught = i < _nextLetterIndex;
              final isNext = i == _nextLetterIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  letter,
                  style: GoogleFonts.fredoka(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: isCaught
                        ? AppColors.starGold
                        : isNext
                            ? Colors.white
                            : AppColors.secondaryText.withValues(alpha: 0.5),
                    shadows: isCaught
                        ? [
                            Shadow(
                              color:
                                  AppColors.starGold.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStarWidget(_Star star) {
    final px = star.x * _screenSize.width;
    final py = star.y * _screenSize.height;
    final twinkle = (sin(star.twinklePhase) * 0.3 + 0.7).clamp(0.4, 1.0);
    final wobbleX = star.wobbleTimer > 0
        ? sin(star.wobbleTimer * 30) * star.wobbleAmount
        : 0.0;

    final isNextTarget = star.isCorrect &&
        star.correctIndex == _nextLetterIndex &&
        !star.caught;
    final starColor = star.caught
        ? AppColors.starGold
        : isNextTarget
            ? Colors.white
            : AppColors.secondaryText.withValues(alpha: 0.7);

    return Positioned(
      left: px - star.radius + wobbleX,
      top: py - star.radius,
      child: GestureDetector(
        onTap: () => _onStarTap(star),
        child: SizedBox(
          width: star.radius * 2,
          height: star.radius * 2,
          child: CustomPaint(
            painter: _StarShapePainter(
              color: starColor,
              twinkle: star.caught ? 1.0 : twinkle,
              caught: star.caught,
              glowPulse: star.glowPulse,
              isHint: isNextTarget,
            ),
            child: Center(
              child: Text(
                star.letter,
                style: GoogleFonts.fredoka(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: star.caught
                      ? const Color(0xFF1A0A00)
                      : Colors.white,
                  shadows: star.caught
                      ? null
                      : [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Game Over ────────────────────────────────────────────────────────────

  Widget _buildGameOver() {
    String title;
    IconData icon;
    Color accentColor;

    if (_wordsCompleted >= 8) {
      title = 'Super Astronaut!';
      icon = Icons.rocket_launch_rounded;
      accentColor = AppColors.starGold;
    } else if (_wordsCompleted >= 4) {
      title = 'Star Catcher!';
      icon = Icons.star_rounded;
      accentColor = AppColors.electricBlue;
    } else if (_wordsCompleted >= 2) {
      title = 'Great Job!';
      icon = Icons.thumb_up_rounded;
      accentColor = AppColors.violet;
    } else {
      title = 'Nice Try!';
      icon = Icons.favorite_rounded;
      accentColor = AppColors.magenta;
    }

    return Stack(
      children: [
        _buildSpaceBackground(),
        SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 72, color: accentColor),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.fredoka(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatRow(Icons.star_rounded, AppColors.starGold,
                    'Score', '$_score'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.auto_awesome_rounded, AppColors.electricBlue,
                    'Words', '$_wordsCompleted'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.local_fire_department_rounded,
                    AppColors.magenta, 'Best Combo', '${_bestCombo}x'),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                        'Play Again', Icons.replay_rounded, _startGame),
                    const SizedBox(width: 16),
                    _buildActionButton('Exit', Icons.home_rounded, () {
                      Navigator.of(context).pop();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(
      IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.fredoka(
              fontSize: 14,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: GoogleFonts.fredoka(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.primaryText),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Background ───────────────────────────────────────────────────────────

  Widget _buildSpaceBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF05051A),
            Color(0xFF0D0D2B),
            Color(0xFF15103A),
          ],
        ),
      ),
      child: CustomPaint(
        size: _screenSize == Size.zero
            ? const Size(400, 800)
            : _screenSize,
        painter: _BackgroundStarsPainter(
          stars: _bgStars,
          time: _astronautBob,
        ),
      ),
    );
  }
}

// ── Star shape painter ─────────────────────────────────────────────────────

class _StarShapePainter extends CustomPainter {
  final Color color;
  final double twinkle;
  final bool caught;
  final double glowPulse;
  final bool isHint;

  const _StarShapePainter({
    required this.color,
    required this.twinkle,
    required this.caught,
    required this.glowPulse,
    required this.isHint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    // Glow behind star
    if (caught || isHint) {
      final glowColor = caught
          ? AppColors.starGold.withValues(alpha: 0.3 + glowPulse * 0.3)
          : AppColors.electricBlue.withValues(alpha: 0.15);
      canvas.drawCircle(
        Offset(cx, cy),
        r + 6,
        Paint()
          ..color = glowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Star shape (5-pointed)
    final path = _starPath(cx, cy, r * 0.55, r * twinkle);
    canvas.drawPath(
      path,
      Paint()
        ..color = caught
            ? AppColors.starGold
            : color.withValues(alpha: twinkle),
    );

    // Star border
    canvas.drawPath(
      path,
      Paint()
        ..color = caught
            ? AppColors.starGold.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: twinkle * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Inner highlight
    if (!caught) {
      final innerPath = _starPath(cx - 2, cy - 2, r * 0.3, r * 0.5);
      canvas.drawPath(
        innerPath,
        Paint()..color = Colors.white.withValues(alpha: twinkle * 0.2),
      );
    }
  }

  Path _starPath(double cx, double cy, double innerR, double outerR) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * pi / 5) - pi / 2;
      final r = i.isEven ? outerR : innerR;
      final x = cx + cos(angle) * r;
      final y = cy + sin(angle) * r;
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
  bool shouldRepaint(covariant _StarShapePainter oldDelegate) => true;
}

// ── Constellation line painter ─────────────────────────────────────────────

class _ConstellationPainter extends CustomPainter {
  final List<_ConstellationLine> lines;
  final Size screenSize;

  const _ConstellationPainter({
    required this.lines,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final from = Offset(
        line.from.dx * screenSize.width,
        line.from.dy * screenSize.height,
      );
      final to = Offset(
        line.to.dx * screenSize.width,
        line.to.dy * screenSize.height,
      );

      // Glow line
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = AppColors.electricBlue
              .withValues(alpha: line.opacity * 0.2)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Core line
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = AppColors.electricBlue
              .withValues(alpha: line.opacity * 0.6)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) => true;
}

// ── Sparkles / shooting star painter ───────────────────────────────────────

class _SparklesPainter extends CustomPainter {
  final List<_SparkleParticle> particles;
  final List<_ShootingStar> shootingStars;

  const _SparklesPainter({
    required this.particles,
    required this.shootingStars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Particles
    for (final p in particles) {
      final alpha = p.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * 1.5,
        Paint()
          ..color = p.color.withValues(alpha: alpha * 0.3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * alpha,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }

    // Shooting stars
    for (final s in shootingStars) {
      final alpha = s.life.clamp(0.0, 1.0);
      final nx = s.vx / sqrt(s.vx * s.vx + s.vy * s.vy);
      final ny = s.vy / sqrt(s.vx * s.vx + s.vy * s.vy);
      final tail = Offset(s.x - nx * s.length, s.y - ny * s.length);

      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromPoints(Offset(s.x, s.y), tail))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(s.x, s.y), tail, paint);

      // Bright head
      canvas.drawCircle(
        Offset(s.x, s.y),
        3,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklesPainter oldDelegate) => true;
}

// ── Background stars ───────────────────────────────────────────────────────

class _BackgroundStar {
  final double x, y, size, phase, speed;
  const _BackgroundStar({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
  });
}

class _BackgroundStarsPainter extends CustomPainter {
  final List<_BackgroundStar> stars;
  final double time;

  const _BackgroundStarsPainter({required this.stars, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final alpha =
          (0.3 + sin(time * s.speed + s.phase) * 0.4).clamp(0.1, 0.8);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..maskFilter = s.size > 1.5
              ? const MaskFilter.blur(BlurStyle.normal, 1)
              : null,
      );
    }

    // Draw a couple of faint planets
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.12),
      14,
      Paint()
        ..color = const Color(0xFF4A3080).withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.12),
      14,
      Paint()
        ..color = const Color(0xFF6A50A0).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.75),
      10,
      Paint()
        ..color = const Color(0xFF205060).withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(covariant _BackgroundStarsPainter oldDelegate) => true;
}

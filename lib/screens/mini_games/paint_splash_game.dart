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
// Paint Splash -- Art-themed color mixing letter game
// Tap paint blobs in order to spell words and create colorful art.
// ---------------------------------------------------------------------------

class PaintSplashGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;
  final bool hintsEnabled;

  const PaintSplashGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
  });

  @override
  State<PaintSplashGame> createState() => _PaintSplashGameState();
}

// ── Data models ────────────────────────────────────────────────────────────

class _PaintBlob {
  final int id;
  final String letter;
  final bool isCorrect;
  final int correctIndex;
  double x, y; // normalised 0..1
  double vx, vy;
  double radius;
  double wobblePhase;
  Color color;
  bool tapped;
  double splashTimer; // >0 means splashing away
  double squishAmount;
  double squishTimer;

  _PaintBlob({
    required this.id,
    required this.letter,
    required this.isCorrect,
    required this.correctIndex,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.wobblePhase,
    required this.color,
  })  : tapped = false,
        splashTimer = 0,
        squishAmount = 0,
        squishTimer = 0;
}

class _SplashDrop {
  double x, y, vx, vy, size, life;
  Color color;
  _SplashDrop({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
  });
}

class _CanvasSplat {
  final double x, y, radius;
  final Color color;
  double opacity;
  _CanvasSplat({
    required this.x,
    required this.y,
    required this.radius,
    required this.color,
  }) : opacity = 1.0;
}

class _CompletionShape {
  final double x, y;
  final int shapeType; // 0=star, 1=heart, 2=flower, 3=smiley
  final Color color;
  double scale;
  double opacity;
  _CompletionShape({
    required this.x,
    required this.y,
    required this.shapeType,
    required this.color,
  })  : scale = 0,
        opacity = 0;
}

// ── State ──────────────────────────────────────────────────────────────────

class _PaintSplashGameState extends State<PaintSplashGame>
    with SingleTickerProviderStateMixin {
  final _rng = Random();

  // Game config
  static const int _gameDurationSecs = 60;
  static const double _blobZoneTop = 0.22;
  static const double _blobZoneBottom = 0.88;

  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _wordsCompleted = 0;
  int _perfectWords = 0;
  int _timeRemaining = _gameDurationSecs;
  Timer? _gameTimer;
  bool _madeErrorThisWord = false;

  // Current word
  List<String> _wordPool = [];
  String _currentWord = '';
  int _nextLetterIndex = 0;

  // Blobs
  List<_PaintBlob> _blobs = [];
  int _nextBlobId = 0;

  // Visual effects
  final List<_SplashDrop> _splashDrops = [];
  final List<_CanvasSplat> _canvasSplats = [];
  _CompletionShape? _completionShape;
  double _completionTimer = 0;

  // Paint drip decorations
  late List<_PaintDrip> _paintDrips;

  // Animation
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;

  // Easel wobble
  double _easelTime = 0;

  // Palette of bright colors
  static const List<Color> _paintColors = [
    Color(0xFFFF4D6A), // red-pink
    Color(0xFF4D9FFF), // blue
    Color(0xFF4DFF88), // green
    Color(0xFFFFD74D), // yellow
    Color(0xFFFF8C4D), // orange
    Color(0xFFB84DFF), // purple
    Color(0xFF4DFFE0), // teal
    Color(0xFFFF4DA6), // hot pink
  ];

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _wordPool = _buildWordPool();

    // Paint drips
    _paintDrips = List.generate(8, (i) => _PaintDrip(
      x: 0.05 + _rng.nextDouble() * 0.9,
      startY: 0,
      length: 0.05 + _rng.nextDouble() * 0.15,
      width: 3 + _rng.nextDouble() * 5,
      color: _paintColors[i % _paintColors.length].withValues(alpha: 0.15),
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
      _perfectWords = 0;
      _timeRemaining = _gameDurationSecs;
      _blobs = [];
      _splashDrops.clear();
      _canvasSplats.clear();
      _completionShape = null;
      _nextLetterIndex = 0;
      _madeErrorThisWord = false;
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
        StickerDefinitions.miniGameStickersForScore('paint_splash', _score);
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
    _madeErrorThisWord = false;
    _completionShape = null;
    _spawnBlobs();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_gameOver) {
        widget.audioService.playWord(_currentWord);
      }
    });
  }

  void _spawnBlobs() {
    _blobs.clear();
    final letters = _currentWord.split('');
    final usedPositions = <Offset>[];
    int colorIdx = _rng.nextInt(_paintColors.length);

    for (int i = 0; i < letters.length; i++) {
      final pos = _findOpenPosition(usedPositions);
      usedPositions.add(pos);
      _blobs.add(_PaintBlob(
        id: _nextBlobId++,
        letter: letters[i].toUpperCase(),
        isCorrect: true,
        correctIndex: i,
        x: pos.dx,
        y: pos.dy,
        vx: (_rng.nextDouble() - 0.5) * 0.08,
        vy: (_rng.nextDouble() - 0.5) * 0.06,
        radius: 32,
        wobblePhase: _rng.nextDouble() * pi * 2,
        color: _paintColors[(colorIdx + i) % _paintColors.length],
      ));
    }

    // Distractors
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

      _blobs.add(_PaintBlob(
        id: _nextBlobId++,
        letter: letter,
        isCorrect: false,
        correctIndex: -1,
        x: pos.dx,
        y: pos.dy,
        vx: (_rng.nextDouble() - 0.5) * 0.08,
        vy: (_rng.nextDouble() - 0.5) * 0.06,
        radius: 32,
        wobblePhase: _rng.nextDouble() * pi * 2,
        color: widget.hintsEnabled
            ? Colors.grey.withValues(alpha: 0.5)
            : _paintColors[_rng.nextInt(_paintColors.length)],
      ));
    }
    _blobs.shuffle(_rng);
  }

  Offset _findOpenPosition(List<Offset> existing) {
    const margin = 0.1;
    for (int attempt = 0; attempt < 50; attempt++) {
      final x = margin + _rng.nextDouble() * (1.0 - 2 * margin);
      final y = _blobZoneTop + 0.05 +
          _rng.nextDouble() * (_blobZoneBottom - _blobZoneTop - 0.1);
      bool tooClose = false;
      for (final e in existing) {
        if ((e.dx - x).abs() < 0.14 && (e.dy - y).abs() < 0.1) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) return Offset(x, y);
    }
    return Offset(
      margin + _rng.nextDouble() * (1.0 - 2 * margin),
      _blobZoneTop + _rng.nextDouble() * (_blobZoneBottom - _blobZoneTop),
    );
  }

  // ── Blob tap ─────────────────────────────────────────────────────────────

  void _onBlobTap(_PaintBlob blob) {
    if (blob.tapped || _gameOver || _completionShape != null) return;

    if (blob.isCorrect && blob.correctIndex == _nextLetterIndex) {
      _onCorrectTap(blob);
    } else {
      _onWrongTap(blob);
    }
  }

  void _onCorrectTap(_PaintBlob blob) {
    setState(() {
      blob.tapped = true;
      blob.splashTimer = 0.4;
      _combo++;
      if (_combo > _bestCombo) _bestCombo = _combo;

      final comboBonus = (_combo > 1) ? (_combo - 1) * 5 : 0;
      _score += 10 + comboBonus;
      _nextLetterIndex++;
    });

    widget.audioService.playLetter(blob.letter.toLowerCase());

    // Splash effect
    if (_screenSize != Size.zero) {
      final px = blob.x * _screenSize.width;
      final py = blob.y * _screenSize.height;
      _spawnSplash(px, py, blob.color, 12);
      _canvasSplats.add(_CanvasSplat(
        x: px,
        y: py,
        radius: 20 + _rng.nextDouble() * 20,
        color: blob.color.withValues(alpha: 0.4),
      ));
    }

    // Check word complete
    if (_nextLetterIndex >= _currentWord.length) {
      widget.audioService.playSuccess();
      Haptics.success();
      _wordsCompleted++;

      if (!_madeErrorThisWord) {
        _perfectWords++;
        _score += 20; // no-mistake bonus
      }

      // Show completion shape
      if (_screenSize != Size.zero) {
        _completionShape = _CompletionShape(
          x: _screenSize.width / 2,
          y: _screenSize.height * 0.5,
          shapeType: _rng.nextInt(4),
          color: _paintColors[_rng.nextInt(_paintColors.length)],
        );
        _completionTimer = 0;
      }

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_gameOver) _nextWord();
      });
    } else {
      widget.audioService.playSuccess();
      Haptics.correct();
    }
  }

  void _onWrongTap(_PaintBlob blob) {
    setState(() {
      blob.squishAmount = 8;
      blob.squishTimer = 0.3;
      _combo = 0;
      _madeErrorThisWord = true;
    });
    widget.audioService.playError();
    Haptics.wrong();
  }

  void _spawnSplash(double cx, double cy, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 80 + _rng.nextDouble() * 150;
      _splashDrops.add(_SplashDrop(
        x: cx,
        y: cy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40,
        size: 3 + _rng.nextDouble() * 6,
        life: 1.0,
        color: Color.lerp(color, Colors.white, _rng.nextDouble() * 0.3)!,
      ));
    }
  }

  // ── Tick ──────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final dt = dtRaw.clamp(0.0, 0.05);
    _easelTime += dt * 1.2;
    if (_screenSize == Size.zero || !_gameStarted || _gameOver) {
      if (mounted) setState(() {});
      return;
    }

    // Update blobs
    for (final b in _blobs) {
      if (b.tapped) {
        if (b.splashTimer > 0) b.splashTimer -= dt;
        continue;
      }

      b.wobblePhase += dt * 3;
      b.x += b.vx * dt;
      b.y += b.vy * dt;

      // Squish decay
      if (b.squishTimer > 0) {
        b.squishTimer -= dt;
        if (b.squishTimer <= 0) b.squishAmount = 0;
      }

      // Bounce off edges
      final rNorm = b.radius / _screenSize.width;
      final rNormY = b.radius / _screenSize.height;
      if (b.x < rNorm) { b.x = rNorm; b.vx = b.vx.abs(); }
      if (b.x > 1 - rNorm) { b.x = 1 - rNorm; b.vx = -b.vx.abs(); }
      if (b.y < _blobZoneTop + rNormY) {
        b.y = _blobZoneTop + rNormY;
        b.vy = b.vy.abs();
      }
      if (b.y > _blobZoneBottom - rNormY) {
        b.y = _blobZoneBottom - rNormY;
        b.vy = -b.vy.abs();
      }

      // Random nudges
      if (_rng.nextDouble() < 0.03) {
        b.vx += (_rng.nextDouble() - 0.5) * 0.03;
        b.vy += (_rng.nextDouble() - 0.5) * 0.02;
      }

      // Dampen
      b.vx *= 0.997;
      b.vy *= 0.997;
      final speed = sqrt(b.vx * b.vx + b.vy * b.vy);
      if (speed > 0.2) {
        b.vx = b.vx / speed * 0.2;
        b.vy = b.vy / speed * 0.2;
      }
      if (speed < 0.02) {
        b.vx += (_rng.nextDouble() - 0.5) * 0.04;
        b.vy += (_rng.nextDouble() - 0.5) * 0.03;
      }
    }

    // Blob-to-blob collision
    for (int i = 0; i < _blobs.length; i++) {
      for (int j = i + 1; j < _blobs.length; j++) {
        final a = _blobs[i];
        final b = _blobs[j];
        if (a.tapped || b.tapped) continue;
        final dx = (a.x - b.x) * _screenSize.width;
        final dy = (a.y - b.y) * _screenSize.height;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = a.radius + b.radius + 6;
        if (dist < minDist && dist > 0) {
          final nx = dx / dist;
          final ny = dy / dist;
          final push = (minDist - dist) / _screenSize.width * 0.5;
          a.vx += nx * push;
          a.vy += ny * push / (_screenSize.height / _screenSize.width);
          b.vx -= nx * push;
          b.vy -= ny * push / (_screenSize.height / _screenSize.width);
        }
      }
    }

    // Update splash drops
    for (final d in _splashDrops) {
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vy += 100 * dt; // gravity
      d.life -= dt * 1.5;
    }
    _splashDrops.removeWhere((d) => d.life <= 0);

    // Canvas splat fade
    for (final s in _canvasSplats) {
      s.opacity = (s.opacity - dt * 0.1).clamp(0.0, 1.0);
    }
    _canvasSplats.removeWhere((s) => s.opacity <= 0);

    // Completion shape animation
    if (_completionShape != null) {
      _completionTimer += dt;
      _completionShape!.scale =
          (_completionTimer * 3).clamp(0.0, 1.0);
      _completionShape!.opacity =
          _completionTimer < 0.8 ? 1.0 : (1.2 - _completionTimer).clamp(0.0, 1.0);
      if (_completionTimer > 1.2) _completionShape = null;
    }

    if (mounted) setState(() {});
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
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
    widget.audioService.playWord('paint_splash');
  }

  Widget _buildStartScreen() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_gameStarted) _playIntro();
    });

    return Stack(
      children: [
        _buildCanvasBackground(),
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
                        color: Color(0xFF333333)),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              // Palette icon
              Transform.translate(
                offset: Offset(0, sin(_easelTime) * 4),
                child: const Icon(Icons.palette_rounded,
                    size: 64, color: Color(0xFFFF4D6A)),
              ),
              const SizedBox(height: 16),
              Text(
                'Paint Splash',
                style: AppFonts.fredoka(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF333333),
                  shadows: [
                    Shadow(
                      color: const Color(0xFFFF4D6A).withValues(alpha: 0.3),
                      blurRadius: 16,
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
                    color: const Color(0xFFFF4D6A).withValues(alpha: 0.15),
                    border: Border.all(
                      color: const Color(0xFFFF4D6A).withValues(alpha: 0.4),
                      width: 3,
                    ),
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: Color(0xFFFF4D6A), size: 40),
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
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF4D6A),
                        Color(0xFFFF8C4D),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF4D6A).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.brush_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'Play!',
                        style: AppFonts.fredoka(
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
        _buildCanvasBackground(),

        // Canvas splats (paint marks)
        CustomPaint(
          size: _screenSize,
          painter: _CanvasSplatsPainter(splats: _canvasSplats),
        ),

        // Paint blobs
        ..._blobs
            .where((b) => !b.tapped || b.splashTimer > 0)
            .map((b) => _buildBlobWidget(b)),

        // HUD
        SafeArea(
          child: Column(
            children: [
              _buildHUD(),
              _buildWordDisplay(),
            ],
          ),
        ),

        // Splash drops overlay
        IgnorePointer(
          child: CustomPaint(
            size: _screenSize,
            painter: _SplashDropsPainter(drops: _splashDrops),
          ),
        ),

        // Completion shape
        if (_completionShape != null)
          IgnorePointer(
            child: CustomPaint(
              size: _screenSize,
              painter: _CompletionShapePainter(shape: _completionShape!),
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
            color: const Color(0xFF555555),
          ),
          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFD74D).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: Color(0xFFFFAA00)),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: AppFonts.fredoka(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFAA00),
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
                    const Color(0xFFFF4D6A).withValues(alpha: 0.2),
                    const Color(0xFFB84DFF).withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF4D6A).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '${_combo}x',
                style: AppFonts.fredoka(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFF4D6A),
                ),
              ),
            ),
          const Spacer(),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _timeRemaining <= 10
                  ? const Color(0xFFFF4D6A).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: _timeRemaining <= 10
                  ? Border.all(
                      color:
                          const Color(0xFFFF4D6A).withValues(alpha: 0.5))
                  : Border.all(
                      color: const Color(0xFFDDDDDD)),
            ),
            child: Text(
              '${_timeRemaining}s',
              style: AppFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _timeRemaining <= 10
                    ? const Color(0xFFFF4D6A)
                    : const Color(0xFF555555),
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
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFF4D6A).withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4D6A).withValues(alpha: 0.1),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volume_up_rounded,
                color: Color(0xFFFF4D6A), size: 24),
            const SizedBox(width: 10),
            ...List.generate(_currentWord.length, (i) {
              final letter = _currentWord[i].toUpperCase();
              final isDone = i < _nextLetterIndex;
              final isNext = i == _nextLetterIndex;
              final blobColor = isDone
                  ? _blobs
                      .firstWhere(
                        (b) => b.isCorrect && b.correctIndex == i,
                        orElse: () => _blobs.first,
                      )
                      .color
                  : null;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  letter,
                  style: AppFonts.fredoka(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: isDone
                        ? blobColor ?? const Color(0xFFFF4D6A)
                        : isNext
                            ? const Color(0xFF333333)
                            : const Color(0xFFCCCCCC),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBlobWidget(_PaintBlob blob) {
    final px = blob.x * _screenSize.width;
    final py = blob.y * _screenSize.height;
    final wobble = sin(blob.wobblePhase) * 3;
    final squishX = blob.squishTimer > 0
        ? sin(blob.squishTimer * 40) * blob.squishAmount
        : 0.0;

    final splashScale = blob.splashTimer > 0
        ? 1.0 + (0.4 - blob.splashTimer) * 2
        : 1.0;
    final splashAlpha = blob.splashTimer > 0
        ? (blob.splashTimer / 0.4).clamp(0.0, 1.0)
        : 1.0;

    final isNextTarget = blob.isCorrect &&
        blob.correctIndex == _nextLetterIndex &&
        !blob.tapped;

    return Positioned(
      left: px - blob.radius + squishX,
      top: py - blob.radius + wobble,
      child: GestureDetector(
        onTap: () => _onBlobTap(blob),
        child: Opacity(
          opacity: splashAlpha,
          child: Transform.scale(
            scale: splashScale,
            child: SizedBox(
              width: blob.radius * 2,
              height: blob.radius * 2,
              child: CustomPaint(
                painter: _PaintBlobPainter(
                  color: blob.tapped
                      ? blob.color.withValues(alpha: 0.5)
                      : blob.color,
                  isHint: isNextTarget,
                  wobblePhase: blob.wobblePhase,
                ),
                child: Center(
                  child: Text(
                    blob.letter,
                    style: AppFonts.fredoka(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
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
      title = 'Masterpiece!';
      icon = Icons.auto_fix_high_rounded;
      accentColor = const Color(0xFFB84DFF);
    } else if (_wordsCompleted >= 4) {
      title = 'Little Artist!';
      icon = Icons.palette_rounded;
      accentColor = const Color(0xFFFF4D6A);
    } else if (_wordsCompleted >= 2) {
      title = 'Great Job!';
      icon = Icons.thumb_up_rounded;
      accentColor = const Color(0xFF4D9FFF);
    } else {
      title = 'Nice Try!';
      icon = Icons.brush_rounded;
      accentColor = const Color(0xFFFF8C4D);
    }

    return Stack(
      children: [
        _buildCanvasBackground(),
        // Celebration splats
        CustomPaint(
          size: _screenSize,
          painter: _CanvasSplatsPainter(splats: _canvasSplats),
        ),
        SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 72, color: accentColor),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: AppFonts.fredoka(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF333333),
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatRow(Icons.star_rounded,
                    const Color(0xFFFFAA00), 'Score', '$_score'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.brush_rounded,
                    const Color(0xFFFF4D6A), 'Words', '$_wordsCompleted'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.local_fire_department_rounded,
                    const Color(0xFFB84DFF), 'Best Combo', '${_bestCombo}x'),
                if (_perfectWords > 0) ...[
                  const SizedBox(height: 8),
                  _buildStatRow(Icons.check_circle_rounded,
                      const Color(0xFF4DFF88), 'Perfect', '$_perfectWords'),
                ],
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
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppFonts.fredoka(
              fontSize: 14,
              color: const Color(0xFF888888),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppFonts.fredoka(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF333333),
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
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDDDDDD)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF555555)),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF555555),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Background ───────────────────────────────────────────────────────────

  Widget _buildCanvasBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF8F0),
            Color(0xFFFFF0E8),
            Color(0xFFFFECE0),
          ],
        ),
      ),
      child: CustomPaint(
        size: _screenSize == Size.zero
            ? const Size(400, 800)
            : _screenSize,
        painter: _CanvasTexturePainter(drips: _paintDrips),
      ),
    );
  }
}

// ── Paint blob painter ─────────────────────────────────────────────────────

class _PaintBlobPainter extends CustomPainter {
  final Color color;
  final bool isHint;
  final double wobblePhase;

  const _PaintBlobPainter({
    required this.color,
    required this.isHint,
    required this.wobblePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    // Subtle glow for hint
    if (isHint) {
      canvas.drawCircle(
        Offset(cx, cy),
        r + 8,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Paint blob shape (slightly irregular circle)
    final path = Path();
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * pi * 2;
      final wobble = sin(wobblePhase + i * 0.8) * 2;
      final blobR = r + wobble;
      final x = cx + cos(angle) * blobR;
      final y = cy + sin(angle) * blobR;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Fill
    canvas.drawPath(
      path,
      Paint()..color = color,
    );

    // Highlight
    canvas.drawCircle(
      Offset(cx - r * 0.25, cy - r * 0.25),
      r * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // Border
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PaintBlobPainter oldDelegate) => true;
}

// ── Canvas splats painter ──────────────────────────────────────────────────

class _CanvasSplatsPainter extends CustomPainter {
  final List<_CanvasSplat> splats;

  const _CanvasSplatsPainter({required this.splats});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in splats) {
      // Main splat
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.radius,
        Paint()
          ..color = s.color.withValues(alpha: s.opacity * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.radius * 0.3),
      );
      // Core
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.radius * 0.6,
        Paint()..color = s.color.withValues(alpha: s.opacity * 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasSplatsPainter oldDelegate) => true;
}

// ── Splash drops painter ───────────────────────────────────────────────────

class _SplashDropsPainter extends CustomPainter {
  final List<_SplashDrop> drops;

  const _SplashDropsPainter({required this.drops});

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drops) {
      final alpha = d.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(d.x, d.y),
        d.size * alpha,
        Paint()..color = d.color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashDropsPainter oldDelegate) => true;
}

// ── Completion shape painter ───────────────────────────────────────────────

class _CompletionShapePainter extends CustomPainter {
  final _CompletionShape shape;

  const _CompletionShapePainter({required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    if (shape.scale <= 0 || shape.opacity <= 0) return;

    canvas.save();
    canvas.translate(shape.x, shape.y);
    canvas.scale(shape.scale);

    final paint = Paint()
      ..color = shape.color.withValues(alpha: shape.opacity);
    final glowPaint = Paint()
      ..color = shape.color.withValues(alpha: shape.opacity * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    switch (shape.shapeType) {
      case 0: // Star
        final path = _starPath(0, 0, 20, 45);
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);
        break;
      case 1: // Heart
        final path = _heartPath(0, 0, 40);
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);
        break;
      case 2: // Flower
        _drawFlower(canvas, paint, glowPaint);
        break;
      case 3: // Smiley
        _drawSmiley(canvas, paint, glowPaint);
        break;
    }

    canvas.restore();
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

  Path _heartPath(double cx, double cy, double s) {
    final path = Path();
    path.moveTo(cx, cy + s * 0.3);
    path.cubicTo(cx - s, cy - s * 0.3, cx - s * 0.5, cy - s,
        cx, cy - s * 0.4);
    path.cubicTo(cx + s * 0.5, cy - s, cx + s, cy - s * 0.3,
        cx, cy + s * 0.3);
    path.close();
    return path;
  }

  void _drawFlower(Canvas canvas, Paint paint, Paint glowPaint) {
    // Petals
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * pi * 2;
      final px = cos(angle) * 25;
      final py = sin(angle) * 25;
      canvas.drawCircle(Offset(px, py), 15, glowPaint);
      canvas.drawCircle(Offset(px, py), 15, paint);
    }
    // Center
    canvas.drawCircle(Offset.zero, 12,
        Paint()..color = const Color(0xFFFFD74D).withValues(alpha: paint.color.a));
  }

  void _drawSmiley(Canvas canvas, Paint paint, Paint glowPaint) {
    // Face
    canvas.drawCircle(Offset.zero, 35, glowPaint);
    canvas.drawCircle(Offset.zero, 35, paint);
    // Eyes
    final eyePaint = Paint()..color = Colors.white.withValues(alpha: paint.color.a);
    canvas.drawCircle(const Offset(-12, -8), 6, eyePaint);
    canvas.drawCircle(const Offset(12, -8), 6, eyePaint);
    // Pupils
    final pupilPaint = Paint()
      ..color = const Color(0xFF333333).withValues(alpha: paint.color.a);
    canvas.drawCircle(const Offset(-12, -8), 3, pupilPaint);
    canvas.drawCircle(const Offset(12, -8), 3, pupilPaint);
    // Smile
    final smilePath = Path()
      ..addArc(
        const Rect.fromLTWH(-16, -4, 32, 28),
        0.2,
        pi - 0.4,
      );
    canvas.drawPath(
      smilePath,
      Paint()
        ..color = Colors.white.withValues(alpha: paint.color.a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CompletionShapePainter oldDelegate) => true;
}

// ── Canvas texture / drip painter ──────────────────────────────────────────

class _PaintDrip {
  final double x, startY, length, width;
  final Color color;
  const _PaintDrip({
    required this.x,
    required this.startY,
    required this.length,
    required this.width,
    required this.color,
  });
}

class _CanvasTexturePainter extends CustomPainter {
  final List<_PaintDrip> drips;

  const _CanvasTexturePainter({required this.drips});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle canvas grid
    final gridPaint = Paint()
      ..color = const Color(0x08000000)
      ..strokeWidth = 0.5;
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Paint drips along edges
    for (final d in drips) {
      final path = Path();
      final dx = d.x * size.width;
      final dy = d.startY * size.height;
      final dLen = d.length * size.height;
      path.moveTo(dx - d.width / 2, dy);
      path.lineTo(dx + d.width / 2, dy);
      path.lineTo(dx + d.width / 3, dy + dLen * 0.7);
      path.quadraticBezierTo(dx, dy + dLen, dx, dy + dLen + d.width);
      path.quadraticBezierTo(
          dx, dy + dLen, dx - d.width / 3, dy + dLen * 0.7);
      path.close();
      canvas.drawPath(path, Paint()..color = d.color);
    }

    // Easel frame border
    final framePaint = Paint()
      ..color = const Color(0x15000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      framePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasTexturePainter oldDelegate) => false;
}

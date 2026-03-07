import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/rhyme_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Rhyme Time — Match the rhyming word! Hear a word, tap its rhyme partner
// from bouncing bubbles. Combos, streaks, and satisfying pop effects.
// ---------------------------------------------------------------------------

class RhymeTimeGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const RhymeTimeGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<RhymeTimeGame> createState() => _RhymeTimeGameState();
}

// ── Data models ─────────────────────────────────────────────────────────────

class _WordBubble {
  final int id;
  final String word;
  final bool isCorrect;
  double x, y; // normalized 0..1
  double vx, vy; // velocity (normalized/s)
  double radius; // in pixels
  double wobblePhase;
  double popTimer; // >0 means popping
  bool popped;
  Color color;

  _WordBubble({
    required this.id,
    required this.word,
    required this.isCorrect,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.wobblePhase,
    required this.color,
  })  : popTimer = 0,
        popped = false;
}

class _PopParticle {
  double x, y, vx, vy, size, life;
  Color color;
  _PopParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
  });
}

class _FloatingNote {
  double x, y;
  double opacity = 1.0;
  String text;
  double vy = -60;
  _FloatingNote({
    required this.x,
    required this.y,
    required this.text,
  });
}

// ── State ───────────────────────────────────────────────────────────────────

class _RhymeTimeGameState extends State<RhymeTimeGame>
    with SingleTickerProviderStateMixin {
  final _rng = Random();

  // Game config
  static const int _gameDurationSecs = 60;
  static const int _maxLives = 3;
  static const int _startChoices = 3;
  static const int _maxChoices = 6;

  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _lives = _maxLives;
  int _combo = 0;
  int _bestCombo = 0;
  int _wordsMatched = 0;
  int _timeRemaining = _gameDurationSecs;
  Timer? _gameTimer;

  // Current round
  String _targetWord = '';
  List<_WordBubble> _bubbles = [];
  int _nextBubbleId = 0;
  bool _roundTransitioning = false;

  // Difficulty
  int _currentChoices = _startChoices;

  // Effects
  final List<_PopParticle> _particles = [];
  final List<_FloatingNote> _floatingNotes = [];
  double _screenShake = 0;
  double _flashOpacity = 0;
  Color? _flashColor;

  // Animation
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;

  // Rhyme data
  late List<RhymeFamily> _shuffledFamilies;
  int _familyIndex = 0;

  // Visual theme colors per round
  static const _roundColors = [
    Color(0xFF00D4FF), // cyan
    Color(0xFFFF69B4), // pink
    Color(0xFF10B981), // emerald
    Color(0xFFFFD700), // gold
    Color(0xFF8B5CF6), // violet
    Color(0xFFFF6B6B), // coral
    Color(0xFF06B6D4), // teal
    Color(0xFFF59E0B), // amber
  ];

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _shuffledFamilies = List.of(rhymeFamilies)..shuffle(_rng);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gameTimer?.cancel();
    _sessionTimer.stop();
    super.dispose();
  }

  // ── Game lifecycle ────────────────────────────────────────────────────────

  void _playIntro() {
    // Play the intro explanation voice
    widget.audioService.playWord('rhyme_time_intro');
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _gameOver = false;
      _score = 0;
      _lives = _maxLives;
      _combo = 0;
      _bestCombo = 0;
      _wordsMatched = 0;
      _timeRemaining = _gameDurationSecs;
      _currentChoices = _startChoices;
      _familyIndex = 0;
      _shuffledFamilies = List.of(rhymeFamilies)..shuffle(_rng);
      _particles.clear();
      _floatingNotes.clear();
    });

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _gameOver) return;
      setState(() {
        _timeRemaining--;
        if (_timeRemaining <= 0) _endGame();
      });
    });

    _loadRound();
  }

  void _endGame() {
    _gameTimer?.cancel();
    setState(() => _gameOver = true);
    _awardMiniGameStickers();
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('rhyme_time', _score);
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

  void _loadRound() {
    if (_gameOver) return;

    // Pick a family
    if (_familyIndex >= _shuffledFamilies.length) {
      _familyIndex = 0;
      _shuffledFamilies.shuffle(_rng);
    }
    final family = _shuffledFamilies[_familyIndex++];

    // Pick target word from this family
    final familyWords = List.of(family.words)..shuffle(_rng);
    _targetWord = familyWords.first;

    // Pick one correct answer (different from target)
    final correctWord = familyWords.length > 1
        ? familyWords.firstWhere((w) => w != _targetWord)
        : familyWords.first;

    // Pick distractors from OTHER families
    final otherWords = <String>[];
    for (final f in _shuffledFamilies) {
      if (f.familyName != family.familyName) {
        otherWords.addAll(f.words);
      }
    }
    otherWords.shuffle(_rng);

    final numDistractors = _currentChoices - 1;
    final distractors = otherWords.take(numDistractors).toList();

    // Build bubbles
    final allChoices = <_WordBubble>[];
    final roundColor = _roundColors[_wordsMatched % _roundColors.length];

    allChoices.add(_makeBubble(correctWord, true, roundColor));
    for (final d in distractors) {
      allChoices.add(_makeBubble(d, false, roundColor));
    }
    allChoices.shuffle(_rng);

    setState(() {
      _bubbles = allChoices;
      _roundTransitioning = false;
    });

    // Speak the target word after bubbles appear
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && !_gameOver) {
        widget.audioService.playWord(_targetWord);
      }
    });
  }

  // Top of bubble zone (fraction of screen) — below the HUD + target area
  static const double _bubbleZoneTop = 0.22;
  static const double _bubbleZoneBottom = 0.88;

  _WordBubble _makeBubble(String word, bool correct, Color roundColor) {
    const xMargin = 0.08;
    return _WordBubble(
      id: _nextBubbleId++,
      word: word,
      isCorrect: correct,
      x: xMargin + _rng.nextDouble() * (1.0 - 2 * xMargin),
      y: _bubbleZoneTop + 0.05 +
          _rng.nextDouble() * (_bubbleZoneBottom - _bubbleZoneTop - 0.1),
      vx: (_rng.nextDouble() - 0.5) * 0.18,
      vy: (_rng.nextDouble() - 0.5) * 0.14,
      radius: 42,
      wobblePhase: _rng.nextDouble() * pi * 2,
      color: correct
          ? roundColor
          : [
              const Color(0xFF4B5563),
              const Color(0xFF6B7280),
              const Color(0xFF374151),
              const Color(0xFF525E6E),
            ][_rng.nextInt(4)],
    );
  }

  // ── Tick ───────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final dt = dtRaw.clamp(0.0, 0.05);
    if (_screenSize == Size.zero || !_gameStarted || _gameOver) return;

    // Update bubbles — bounce off walls, stay in play zone
    for (final b in _bubbles) {
      if (b.popped) continue;
      b.wobblePhase += dt * 2;
      b.x += b.vx * dt;
      b.y += b.vy * dt;

      // Add small random velocity nudges for more dynamic movement
      if (_rng.nextDouble() < 0.02) {
        b.vx += (_rng.nextDouble() - 0.5) * 0.04;
        b.vy += (_rng.nextDouble() - 0.5) * 0.03;
      }

      final rNorm = b.radius / _screenSize.width;
      if (b.x < rNorm) {
        b.x = rNorm;
        b.vx = b.vx.abs();
      }
      if (b.x > 1 - rNorm) {
        b.x = 1 - rNorm;
        b.vx = -b.vx.abs();
      }

      // Use proper bubble zone bounds (not behind header)
      final rNormY = b.radius / _screenSize.height;
      final topBound = _bubbleZoneTop + rNormY;
      final bottomBound = _bubbleZoneBottom - rNormY;
      if (b.y < topBound) {
        b.y = topBound;
        b.vy = b.vy.abs();
      }
      if (b.y > bottomBound) {
        b.y = bottomBound;
        b.vy = -b.vy.abs();
      }

      // Pop animation
      if (b.popTimer > 0) {
        b.popTimer -= dt;
        if (b.popTimer <= 0) b.popped = true;
      }
    }

    // Bubble-to-bubble collision (simple repulsion)
    for (int i = 0; i < _bubbles.length; i++) {
      for (int j = i + 1; j < _bubbles.length; j++) {
        final a = _bubbles[i];
        final b = _bubbles[j];
        if (a.popped || b.popped) continue;
        final dx = (a.x - b.x) * _screenSize.width;
        final dy = (a.y - b.y) * _screenSize.height;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = a.radius + b.radius + 8;
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

    // Dampen velocities but keep minimum movement
    for (final b in _bubbles) {
      if (b.popped) continue;
      b.vx *= 0.997;
      b.vy *= 0.997;
      // Clamp max speed
      final speed = sqrt(b.vx * b.vx + b.vy * b.vy);
      if (speed > 0.35) {
        b.vx = b.vx / speed * 0.35;
        b.vy = b.vy / speed * 0.35;
      }
      // Ensure minimum speed so bubbles don't stagnate
      if (speed < 0.03) {
        b.vx += (_rng.nextDouble() - 0.5) * 0.06;
        b.vy += (_rng.nextDouble() - 0.5) * 0.05;
      }
    }

    // Update particles
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 120 * dt; // gravity
      p.life -= dt * 2;
      if (p.life <= 0) _particles.removeAt(i);
    }

    // Update floating notes
    for (int i = _floatingNotes.length - 1; i >= 0; i--) {
      final n = _floatingNotes[i];
      n.y += n.vy * dt;
      n.opacity -= dt * 1.5;
      if (n.opacity <= 0) _floatingNotes.removeAt(i);
    }

    // Screen shake decay
    if (_screenShake > 0) _screenShake *= 0.9;
    if (_screenShake < 0.5) _screenShake = 0;

    // Flash decay
    if (_flashOpacity > 0) {
      _flashOpacity -= dt * 4;
      if (_flashOpacity < 0) _flashOpacity = 0;
    }

    // Trigger rebuild for animations
    if (mounted) setState(() {});
  }

  // ── Bubble tap ────────────────────────────────────────────────────────────

  void _onBubbleTap(_WordBubble bubble) {
    if (bubble.popped || bubble.popTimer > 0 || _roundTransitioning) return;
    if (_gameOver) return;

    // Play the word
    widget.audioService.playWord(bubble.word);

    if (bubble.isCorrect) {
      _onCorrectTap(bubble);
    } else {
      _onWrongTap(bubble);
    }
  }

  void _onCorrectTap(_WordBubble bubble) {
    Haptics.success();
    _combo++;
    if (_combo > _bestCombo) _bestCombo = _combo;
    final comboMultiplier = _combo >= 5 ? 3 : (_combo >= 3 ? 2 : 1);
    final points = 100 * comboMultiplier;
    _score += points;
    _wordsMatched++;

    // Pop the correct bubble
    bubble.popTimer = 0.3;

    // Spawn particles
    final bx = bubble.x * _screenSize.width;
    final by = bubble.y * _screenSize.height;
    _spawnPopBurst(bx, by, bubble.color, 16);

    // Floating score note
    _floatingNotes.add(_FloatingNote(
      x: bx,
      y: by - 30,
      text: '+$points${_combo >= 3 ? ' x$comboMultiplier' : ''}',
    ));

    if (_combo >= 3) {
      _floatingNotes.add(_FloatingNote(
        x: bx,
        y: by - 60,
        text: '$_combo combo!',
      ));
    }

    // Flash green
    _flashColor = AppColors.success;
    _flashOpacity = 0.15;

    // Increase difficulty every 3 words
    if (_wordsMatched % 3 == 0 && _currentChoices < _maxChoices) {
      _currentChoices++;
    }

    _roundTransitioning = true;

    // Pop remaining wrong bubbles with quick stagger, then load next round
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _gameOver) return;
      int delay = 0;
      for (final b in _bubbles) {
        if (!b.popped && b.popTimer <= 0) {
          Future.delayed(Duration(milliseconds: delay), () {
            if (!mounted) return;
            b.popTimer = 0.2;
            final px = b.x * _screenSize.width;
            final py = b.y * _screenSize.height;
            _spawnPopBurst(px, py, b.color.withValues(alpha: 0.5), 6);
          });
          delay += 50;
        }
      }

      // Load new round quickly after pops
      Future.delayed(Duration(milliseconds: delay + 300), () {
        if (mounted && !_gameOver) _loadRound();
      });
    });
  }

  void _onWrongTap(_WordBubble bubble) {
    Haptics.wrong();
    _combo = 0;
    _lives--;
    _screenShake = 8;

    // Flash red
    _flashColor = AppColors.error;
    _flashOpacity = 0.2;

    // Pop wrong bubble
    bubble.popTimer = 0.25;
    final bx = bubble.x * _screenSize.width;
    final by = bubble.y * _screenSize.height;
    _spawnPopBurst(bx, by, AppColors.error, 8);

    final wrongMessages = ['Not quite!', 'Hmm, nope!', 'Keep trying!', 'Almost!'];
    _floatingNotes.add(_FloatingNote(
      x: bx,
      y: by - 30,
      text: wrongMessages[_rng.nextInt(wrongMessages.length)],
    ));

    if (_lives <= 0) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _endGame();
      });
    }
  }

  void _spawnPopBurst(double cx, double cy, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 80 + _rng.nextDouble() * 160;
      _particles.add(_PopParticle(
        x: cx,
        y: cy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40,
        size: 3 + _rng.nextDouble() * 5,
        life: 1.0,
        color: Color.lerp(color, Colors.white, _rng.nextDouble() * 0.4)!,
      ));
    }
  }

  void _replayTarget() {
    widget.audioService.playWord(_targetWord);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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

  // ── Start screen ──────────────────────────────────────────────────────────

  Widget _buildStartScreen() {
    // Auto-play intro voice after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_gameStarted) _playIntro();
    });

    return Stack(
      children: [
        _buildBackground(),
        SafeArea(
          child: Column(
            children: [
              // Back button at top
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

              // Title
              Text(
                'Rhyme Time',
                style: GoogleFonts.fredoka(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: AppColors.magenta.withValues(alpha: 0.6),
                      blurRadius: 24,
                    ),
                    Shadow(
                      color: AppColors.violet.withValues(alpha: 0.4),
                      blurRadius: 48,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms).scale(
                    begin: const Offset(0.8, 0.8),
                    curve: Curves.easeOutBack,
                    duration: 600.ms,
                  ),

              const SizedBox(height: 20),

              // Large tappable speaker — plays voice explanation
              GestureDetector(
                onTap: _playIntro,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.magenta.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.magenta.withValues(alpha: 0.4),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.magenta.withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: AppColors.magenta, size: 48),
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(
                      begin: 1.0,
                      end: 1.1,
                      duration: 1200.ms,
                      curve: Curves.easeInOut)
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 500.ms),

              const SizedBox(height: 20),

              // Tappable example — cat → hat
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // "cat" bubble
                  GestureDetector(
                    onTap: () => widget.audioService.playWord('cat'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.electricBlue.withValues(alpha: 0.2),
                        border: Border.all(
                          color: AppColors.electricBlue.withValues(alpha: 0.6),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.electricBlue.withValues(alpha: 0.2),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.volume_up_rounded,
                              color: AppColors.electricBlue, size: 22),
                          const SizedBox(height: 2),
                          Text(
                            'cat',
                            style: GoogleFonts.fredoka(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.electricBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                          begin: 1.0,
                          end: 1.08,
                          duration: 1500.ms,
                          curve: Curves.easeInOut),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppColors.secondaryText, size: 28),
                  ),

                  // "hat" bubble — the rhyme answer
                  GestureDetector(
                    onTap: () => widget.audioService.playWord('hat'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.magenta.withValues(alpha: 0.2),
                        border: Border.all(
                          color: AppColors.magenta.withValues(alpha: 0.6),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.magenta.withValues(alpha: 0.2),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              color: AppColors.magenta, size: 22),
                          const SizedBox(height: 2),
                          Text(
                            'hat',
                            style: GoogleFonts.fredoka(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.magenta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                          begin: 1.0,
                          end: 1.08,
                          duration: 1500.ms,
                          delay: 200.ms,
                          curve: Curves.easeInOut),
                ],
              ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

              const Spacer(flex: 2),

              // Play button
              GestureDetector(
                onTap: _startGame,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.magenta, AppColors.violet],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.magenta.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
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
              )
                  .animate(
                    onPlay: (c) => c.repeat(reverse: true),
                  )
                  .scaleXY(
                    begin: 1.0,
                    end: 1.05,
                    duration: 1200.ms,
                    curve: Curves.easeInOut,
                  )
                  .animate()
                  .fadeIn(delay: 700.ms, duration: 500.ms),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ],
    );
  }

  // ── Gameplay ──────────────────────────────────────────────────────────────

  Widget _buildGameplay() {
    final shakeOffset = _screenShake > 0
        ? Offset(
            (_rng.nextDouble() - 0.5) * _screenShake * 2,
            (_rng.nextDouble() - 0.5) * _screenShake * 2,
          )
        : Offset.zero;

    return Transform.translate(
      offset: shakeOffset,
      child: Stack(
        children: [
          _buildBackground(),

          // Target word display at top
          SafeArea(
            child: Column(
              children: [
                _buildHUD(),
                _buildTargetArea(),
              ],
            ),
          ),

          // Bouncing word bubbles
          ..._bubbles
              .where((b) => !b.popped)
              .map((b) => _buildBubbleWidget(b)),

          // Particles overlay
          IgnorePointer(
            child: CustomPaint(
              size: _screenSize,
              painter: _ParticlePainter(
                particles: _particles,
                floatingNotes: _floatingNotes,
              ),
            ),
          ),

          // Flash overlay
          if (_flashOpacity > 0)
            IgnorePointer(
              child: Container(
                color: (_flashColor ?? Colors.white)
                    .withValues(alpha: _flashOpacity.clamp(0.0, 1.0)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHUD() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Back button
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
            child: Text(
              '$_score',
              style: GoogleFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.starGold,
              ),
            ),
          ),

          const Spacer(),

          // Combo indicator
          if (_combo >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.magenta.withValues(alpha: 0.3),
                    AppColors.violet.withValues(alpha: 0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.magenta.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '${_combo}x',
                style: GoogleFonts.fredoka(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.magenta,
                ),
              ),
            ),

          const Spacer(),

          // Lives
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_maxLives, (i) {
              return Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  i < _lives
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: i < _lives
                      ? AppColors.magenta
                      : AppColors.secondaryText.withValues(alpha: 0.3),
                ),
              );
            }),
          ),

          const SizedBox(width: 8),

          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _timeRemaining <= 10
                  ? AppColors.error.withValues(alpha: 0.2)
                  : AppColors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: _timeRemaining <= 10
                  ? Border.all(
                      color: AppColors.error.withValues(alpha: 0.5))
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

  Widget _buildTargetArea() {
    return GestureDetector(
      onTap: _replayTarget,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.electricBlue.withValues(alpha: 0.12),
              AppColors.violet.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.electricBlue.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricBlue.withValues(alpha: 0.1),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.volume_up_rounded,
              color: AppColors.electricBlue,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'What rhymes with ',
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '"$_targetWord"',
              style: GoogleFonts.fredoka(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.electricBlue,
              ),
            ),
            Text(
              ' ?',
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleWidget(_WordBubble bubble) {
    final px = bubble.x * _screenSize.width;
    final py = bubble.y * _screenSize.height;
    final wobble = sin(bubble.wobblePhase) * 3;
    final scale = bubble.popTimer > 0
        ? 1.0 + (0.3 - bubble.popTimer) * 2 // expand then fade
        : 1.0;
    final opacity = bubble.popTimer > 0
        ? (bubble.popTimer / 0.3).clamp(0.0, 1.0)
        : 1.0;

    return Positioned(
      left: px - bubble.radius,
      top: py - bubble.radius + wobble,
      child: GestureDetector(
        onTap: () => _onBubbleTap(bubble),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: bubble.radius * 2,
              height: bubble.radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  colors: [
                    bubble.color.withValues(alpha: 0.5),
                    bubble.color.withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(
                  color: bubble.color.withValues(alpha: 0.7),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: bubble.color.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  bubble.word,
                  style: GoogleFonts.fredoka(
                    fontSize: 18,
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
    );
  }

  // ── Game Over ─────────────────────────────────────────────────────────────

  Widget _buildGameOver() {
    final isGood = _wordsMatched >= 5;
    final isStar = _wordsMatched >= 10;

    String title;
    String subtitle;
    IconData icon;
    Color accentColor;

    if (isStar) {
      title = 'Rhyme Star!';
      subtitle = 'You are a rhyming superstar!';
      icon = Icons.star_rounded;
      accentColor = AppColors.starGold;
    } else if (isGood) {
      title = 'Awesome!';
      subtitle = 'You matched so many rhymes!';
      icon = Icons.emoji_events_rounded;
      accentColor = AppColors.magenta;
    } else if (_wordsMatched >= 2) {
      title = 'Good Job!';
      subtitle = 'Keep practicing your rhymes!';
      icon = Icons.thumb_up_rounded;
      accentColor = AppColors.electricBlue;
    } else {
      title = 'Nice Try!';
      subtitle = 'Rhyming gets easier with practice!';
      icon = Icons.favorite_rounded;
      accentColor = AppColors.violet;
    }

    return Stack(
      children: [
        _buildBackground(),
        SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 72, color: accentColor)
                    .animate()
                    .scale(
                      begin: const Offset(0.5, 0.5),
                      curve: Curves.easeOutBack,
                      duration: 600.ms,
                    ),

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
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

                const SizedBox(height: 6),

                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ).animate().fadeIn(delay: 350.ms, duration: 400.ms),

                const SizedBox(height: 24),

                // Stats (tappable — speaks the stat)
                _buildStatRow(Icons.star_rounded, AppColors.starGold,
                    'Score', '$_score', 'score'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.check_circle_rounded, AppColors.success,
                    'Rhymes Found', '$_wordsMatched', 'rhymes_found'),
                const SizedBox(height: 8),
                _buildStatRow(Icons.local_fire_department_rounded,
                    AppColors.magenta, 'Best Combo', '${_bestCombo}x', 'best_combo'),

                const SizedBox(height: 32),

                // Play again
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton('Play Again', Icons.replay_rounded, () {
                      _startGame();
                    }),
                    const SizedBox(width: 16),
                    _buildActionButton('Exit', Icons.home_rounded, () {
                      Navigator.of(context).pop();
                    }),
                  ],
                )
                    .animate()
                    .fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _speakStat(String statKey) {
    // Speak the stat label as a word
    final wordMap = {
      'score': 'score',
      'rhymes_found': 'rhymes',
      'best_combo': 'combo',
    };
    final word = wordMap[statKey];
    if (word != null) {
      widget.audioService.playWord(word);
    }
  }

  Widget _buildStatRow(
      IconData icon, Color color, String label, String value,
      [String? speakKey]) {
    return GestureDetector(
      onTap: speakKey != null ? () => _speakStat(speakKey) : null,
      child: Container(
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
              style: GoogleFonts.nunito(
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
            if (speakKey != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.volume_up_rounded, size: 16,
                  color: AppColors.secondaryText.withValues(alpha: 0.5)),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideX(
          begin: -0.1,
          curve: Curves.easeOut,
          duration: 400.ms,
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

  // ── Background ────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F0A1E),
            Color(0xFF1A1035),
            Color(0xFF12082A),
          ],
        ),
      ),
    );
  }
}

// ── Particle Painter ────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final List<_PopParticle> particles;
  final List<_FloatingNote> floatingNotes;

  _ParticlePainter({required this.particles, required this.floatingNotes});

  @override
  void paint(Canvas canvas, Size size) {
    // Pop particles
    for (final p in particles) {
      final alpha = p.life.clamp(0.0, 1.0);
      // Glow
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * 2,
        Paint()
          ..color = p.color.withValues(alpha: alpha * 0.3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size),
      );
      // Core
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * alpha,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }

    // Floating score notes
    for (final n in floatingNotes) {
      final tp = TextPainter(
        text: TextSpan(
          text: n.text,
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: n.opacity.clamp(0.0, 1.0)),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: n.opacity * 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(n.x - tp.width / 2, n.y));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

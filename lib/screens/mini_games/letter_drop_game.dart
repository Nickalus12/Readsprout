import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:forge2d/forge2d.dart' hide Transform;

import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Letter Drop — Physics-based word builder with gravity
// ---------------------------------------------------------------------------

class LetterDropGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const LetterDropGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<LetterDropGame> createState() => _LetterDropGameState();
}

// -- Data models ------------------------------------------------------------

class _LetterBody {
  final String letter;
  final Body body;
  final int id;
  bool isDropping = false; // gravity enabled
  bool isLocked = false; // correct & placed in slot
  bool isBouncing = false; // wrong answer bounce animation
  double bounceTimer = 0;
  double glowTimer = 0; // glow animation for locked letters
  Vector2 homePosition; // for floating spring-back
  double wobblePhase;

  _LetterBody({
    required this.letter,
    required this.body,
    required this.id,
    required this.homePosition,
    required this.wobblePhase,
  });
}

class _Slot {
  final int index;
  final String expectedLetter;
  bool filled = false;
  double glowTimer = 0;

  _Slot({
    required this.index,
    required this.expectedLetter,
  });
}

class _Particle {
  double x, y;
  double vx, vy;
  double opacity = 1.0;
  double size;
  Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
  });
}

class _TrailDot {
  double x, y;
  double opacity = 1.0;
  double size;
  Color color;

  _TrailDot({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
  });
}

// -- State ------------------------------------------------------------------

class _LetterDropGameState extends State<LetterDropGame>
    with SingleTickerProviderStateMixin {
  final _rng = Random();

  // Physics
  late final World _world;
  late final AnimationController _controller;
  static const double _scale = 50.0;
  static const int _minStepMicros = 33333; // ~30fps cap
  int _lastStepMicros = 0;

  // Game config
  static const int _maxLives = 3;
  static const int _wordsPerRound = 8;
  static const int _gameDurationSecs = 90;
  static const int _maxDynamicBodies = 12;

  // Game state
  bool _gameOver = false;
  bool _roundComplete = false;
  int _score = 0;
  int _lives = _maxLives;
  int _wordsCompleted = 0;
  int _timeRemaining = _gameDurationSecs;
  Timer? _gameTimer;

  // Word state
  List<String> _wordPool = [];
  int _wordPoolIndex = 0;
  String _currentWord = '';
  int _nextSlotIndex = 0; // which slot we're filling next
  List<_Slot> _slots = [];

  // Physics bodies
  final List<_LetterBody> _letterBodies = [];
  int _nextBodyId = 0;
  // Wall bodies for cleanup
  final List<Body> _wallBodies = [];
  // Slot divider bodies
  final List<Body> _slotDividerBodies = [];

  // Drag-to-aim state
  _LetterBody? _dragging;
  double _dragTimer = 0; // seconds held while dragging
  static const double _maxDragSecs = 2.0; // auto-release after 2s

  // Visual effects
  final List<_Particle> _particles = [];
  final List<_TrailDot> _trails = [];
  double _wordCelebrateT = 0;
  bool _wordCelebrating = false;

  // Layout measurements
  bool _initialized = false;
  bool _initScheduled = false;
  double _areaWidth = 0;
  double _areaHeight = 0;
  double _slotShelfY = 0; // world Y of slot shelf top
  double _floatZoneBottom = 0; // world Y below which is "drop zone"

  // Colors for this round
  List<Color> _themeColors = [AppColors.electricBlue, AppColors.cyan];

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _world = World(Vector2(0, 9.8));
    _world.createBody(BodyDef());

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 300), // long enough
    )..addListener(_simulationStep);

    _buildWordPool();
    _pickThemeColors();
  }

  @override
  void dispose() {
    _controller.dispose();
    _gameTimer?.cancel();
    _sessionTimer.stop();
    super.dispose();
  }

  // -- Theme colors ---------------------------------------------------------

  void _pickThemeColors() {
    final idx = _rng.nextInt(AppColors.levelGradients.length);
    _themeColors = AppColors.levelGradients[idx];
  }

  // -- Word pool ------------------------------------------------------------

  void _buildWordPool() {
    final highest = widget.progressService.highestUnlockedLevel;
    final pool = <String>[];
    for (int lvl = 1; lvl <= highest; lvl++) {
      final words = DolchWords.wordsForLevel(lvl);
      for (final w in words) {
        // Prefer words with 3-6 letters for good gameplay
        final text = w.text.toLowerCase();
        if (text.length >= 2 && text.length <= 6) {
          pool.add(text);
        }
      }
    }
    if (pool.isEmpty) {
      pool.addAll(
        DolchWords.wordsForLevel(1).map((w) => w.text.toLowerCase()),
      );
    }
    pool.shuffle(_rng);
    _wordPool = pool;
    _wordPoolIndex = 0;
  }

  String _nextWordFromPool() {
    if (_wordPoolIndex >= _wordPool.length) {
      _wordPool.shuffle(_rng);
      _wordPoolIndex = 0;
    }
    return _wordPool[_wordPoolIndex++];
  }

  // -- Game lifecycle -------------------------------------------------------

  void _startGame() {
    setState(() {
      _gameOver = false;
      _roundComplete = false;
      _score = 0;
      _lives = _maxLives;
      _wordsCompleted = 0;
      _timeRemaining = _gameDurationSecs;
    });

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _gameOver || _roundComplete) return;
      setState(() {
        _timeRemaining--;
        if (_timeRemaining <= 0) {
          _endGame();
        }
      });
    });

    _loadNextWord();
    _controller.repeat();
  }

  void _endGame() {
    setState(() {
      _gameOver = true;
    });
    _gameTimer?.cancel();
    _controller.stop();
    _awardMiniGameStickers();
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('letter_drop', _wordsCompleted);
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

  void _loadNextWord() {
    if (_wordsCompleted >= _wordsPerRound) {
      setState(() => _roundComplete = true);
      _gameTimer?.cancel();
      _controller.stop();
      _awardMiniGameStickers();
      return;
    }

    _currentWord = _nextWordFromPool();
    _nextSlotIndex = 0;
    _slots = List.generate(
      _currentWord.length,
      (i) => _Slot(index: i, expectedLetter: _currentWord[i]),
    );

    // Clear old letter bodies
    _clearLetterBodies();
    // Clear slot dividers
    _clearSlotDividers();

    // Create slot shelf and dividers
    _createSlotShelf();

    // Populate floating letters
    _populateLetters();

    // Play word pronunciation
    widget.audioService.playWord(_currentWord);
  }

  void _clearLetterBodies() {
    for (final lb in _letterBodies) {
      _world.destroyBody(lb.body);
    }
    _letterBodies.clear();
  }

  void _clearSlotDividers() {
    for (final b in _slotDividerBodies) {
      _world.destroyBody(b);
    }
    _slotDividerBodies.clear();
  }

  // -- Physics setup --------------------------------------------------------

  void _createWalls() {
    final worldW = _areaWidth / _scale;
    final worldH = _areaHeight / _scale;

    // Left wall
    _createStaticEdge(
      Vector2(-0.1, 0),
      Vector2(-0.1, worldH),
    );
    // Right wall
    _createStaticEdge(
      Vector2(worldW + 0.1, 0),
      Vector2(worldW + 0.1, worldH),
    );
    // Floor (below slot shelf)
    _createStaticEdge(
      Vector2(0, worldH + 0.5),
      Vector2(worldW, worldH + 0.5),
    );
  }

  void _createStaticEdge(Vector2 a, Vector2 b) {
    final bodyDef = BodyDef(type: BodyType.static, position: Vector2.zero());
    final body = _world.createBody(bodyDef);
    final shape = EdgeShape()..set(a, b);
    body.createFixture(FixtureDef(shape, friction: 0.3, restitution: 0.4));
    _wallBodies.add(body);
  }

  void _createSlotShelf() {
    final worldW = _areaWidth / _scale;
    final slotCount = _currentWord.length;
    final slotWidth = (worldW * 0.8) / slotCount;
    final shelfLeft = worldW * 0.1;
    final shelfTop = _slotShelfY;
    const shelfHeight = 1.2;

    // Shelf bottom
    _createSlotDivider(
      Vector2(shelfLeft, shelfTop + shelfHeight),
      Vector2(shelfLeft + slotWidth * slotCount, shelfTop + shelfHeight),
    );

    // Dividers between slots
    for (int i = 0; i <= slotCount; i++) {
      final x = shelfLeft + i * slotWidth;
      _createSlotDivider(
        Vector2(x, shelfTop),
        Vector2(x, shelfTop + shelfHeight),
      );
    }
  }

  void _createSlotDivider(Vector2 a, Vector2 b) {
    final bodyDef = BodyDef(type: BodyType.static, position: Vector2.zero());
    final body = _world.createBody(bodyDef);
    final shape = EdgeShape()..set(a, b);
    body.createFixture(FixtureDef(shape, friction: 0.5, restitution: 0.3));
    _slotDividerBodies.add(body);
  }

  // -- Letter population ----------------------------------------------------

  void _populateLetters() {
    final wordLetters = _currentWord.split('');
    // Create distractor letters
    final distractorCount = max(2, 8 - wordLetters.length);
    final distractors = _generateDistractors(wordLetters, distractorCount);

    final allLetters = [...wordLetters, ...distractors];
    allLetters.shuffle(_rng);

    final worldW = _areaWidth / _scale;
    // Start below HUD + target word area (~120px from top)
    final floatTop = 120.0 / _scale;
    final floatHeight = _floatZoneBottom - floatTop;

    for (int i = 0; i < allLetters.length && _letterBodies.length < _maxDynamicBodies; i++) {
      final letter = allLetters[i];
      // Distribute across the float zone in a grid
      final cols = min(allLetters.length, 4);
      final rows = (allLetters.length / cols).ceil();
      final row = i ~/ cols;
      final col = i % cols;
      final spacing = worldW / (cols + 1);
      final rowSpacing = floatHeight / (rows + 1);
      final x = spacing * (col + 1) + (_rng.nextDouble() - 0.5) * 0.4;
      final y = floatTop + rowSpacing * (row + 1) + (_rng.nextDouble() - 0.5) * 0.3;

      final home = Vector2(x, y);
      _createLetterBody(letter, home);
    }
  }

  List<String> _generateDistractors(List<String> wordLetters, int count) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    final distractors = <String>[];
    final avoid = wordLetters.toSet();

    while (distractors.length < count) {
      final c = alphabet[_rng.nextInt(alphabet.length)];
      if (!avoid.contains(c) || _rng.nextDouble() < 0.3) {
        distractors.add(c);
      }
    }
    return distractors;
  }

  void _createLetterBody(String letter, Vector2 home) {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: home.clone(),
      fixedRotation: true,
      linearDamping: 2.0,
      angularDamping: 3.0,
      gravityScale: Vector2.zero(), // float initially
    );

    final body = _world.createBody(bodyDef);
    final shape = CircleShape()..radius = 0.4;
    body.createFixture(FixtureDef(
      shape,
      density: 1.0,
      friction: 0.3,
      restitution: 0.5,
    ));

    _letterBodies.add(_LetterBody(
      letter: letter,
      body: body,
      id: _nextBodyId++,
      homePosition: home,
      wobblePhase: _rng.nextDouble() * pi * 2,
    ));
  }

  // -- Simulation step ------------------------------------------------------

  void _simulationStep() {
    if (!mounted || _gameOver || _roundComplete) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastStepMicros < _minStepMicros) return;
    _lastStepMicros = now;

    // Step physics
    _world.stepDt(1 / 60);

    // Tick drag timer — auto-release after max hold time
    if (_dragging != null) {
      _dragTimer += 1 / 30;
      if (_dragTimer >= _maxDragSecs) {
        final lb = _dragging!;
        _dragging = null;
        _dragTimer = 0;
        if (!lb.isLocked && !lb.isBouncing) {
          lb.isDropping = true;
          lb.body.gravityScale = null;
          lb.body.linearDamping = 0.3;
          lb.body.linearVelocity = Vector2(0, 2);
        }
      }
    }

    // Apply floating forces to non-dropping letters
    for (final lb in _letterBodies) {
      if (lb.isLocked || lb.isDropping || lb == _dragging) continue;

      // Spring force back toward home
      final delta = lb.homePosition - lb.body.position;
      final dist = delta.length;
      if (dist > 0.1) {
        final springForce = delta.normalized()..scale(dist * 2.0);
        lb.body.applyLinearImpulse(springForce..scale(lb.body.mass * 0.05));
      }

      // Gentle wobble
      lb.wobblePhase += 0.03;
      final wobbleX = sin(lb.wobblePhase) * 0.15;
      final wobbleY = cos(lb.wobblePhase * 0.7) * 0.1;
      lb.body.applyLinearImpulse(
        Vector2(wobbleX, wobbleY)..scale(lb.body.mass * 0.02),
      );
    }

    // Check dropping letters against slots
    _checkSlotCollisions();

    // Update bounce timers
    for (final lb in _letterBodies) {
      if (lb.isBouncing) {
        lb.bounceTimer += 1 / 30;
        if (lb.bounceTimer > 1.5) {
          // Reset to floating
          lb.isBouncing = false;
          lb.isDropping = false;
          lb.body.gravityScale = Vector2.zero();
          lb.body.linearDamping = 2.0;
          // Teleport back to home if way off screen
          final worldH = _areaHeight / _scale;
          if (lb.body.position.y > worldH - 1.0 || lb.body.position.y < 0) {
            lb.body.setTransform(lb.homePosition, 0);
            lb.body.linearVelocity = Vector2.zero();
          }
        }
      }
    }

    // Update glow timers on locked slots
    for (final slot in _slots) {
      if (slot.filled && slot.glowTimer < 1.0) {
        slot.glowTimer = (slot.glowTimer + 0.03).clamp(0.0, 1.0);
      }
    }

    // Update particles
    _updateParticles();

    // Update trails
    _updateTrails();

    // Add trails for dropping letters
    for (final lb in _letterBodies) {
      if (lb.isDropping && !lb.isLocked) {
        final sx = lb.body.position.x * _scale;
        final sy = lb.body.position.y * _scale;
        if (_rng.nextDouble() < 0.5) {
          _trails.add(_TrailDot(
            x: sx + (_rng.nextDouble() - 0.5) * 8,
            y: sy + 15,
            size: 2 + _rng.nextDouble() * 3,
            color: _themeColors[0],
          ));
        }
      }
    }

    // Word celebration timer
    if (_wordCelebrating) {
      _wordCelebrateT += 1 / 30;
      if (_wordCelebrateT > 1.8) {
        _wordCelebrating = false;
        _wordCelebrateT = 0;
        _loadNextWord();
      }
    }

    setState(() {});
  }

  void _checkSlotCollisions() {
    if (_wordCelebrating) return;

    final worldW = _areaWidth / _scale;
    final slotCount = _currentWord.length;
    final slotWidth = (worldW * 0.8) / slotCount;
    final shelfLeft = worldW * 0.1;

    for (final lb in _letterBodies) {
      if (!lb.isDropping || lb.isLocked || lb.isBouncing) continue;

      final pos = lb.body.position;
      // Check if letter is in slot region
      if (pos.y >= _slotShelfY - 0.2 && pos.y <= _slotShelfY + 1.5) {
        // Which slot column?
        final relX = pos.x - shelfLeft;
        if (relX < 0 || relX > slotWidth * slotCount) continue;
        final slotIdx = (relX / slotWidth).floor().clamp(0, slotCount - 1);
        final slot = _slots[slotIdx];

        if (slot.filled) continue;

        // Check if this is the next expected slot and correct letter
        if (slotIdx == _nextSlotIndex &&
            lb.letter == slot.expectedLetter) {
          // Correct!
          _lockLetterInSlot(lb, slot, shelfLeft, slotWidth);
        } else {
          // Wrong — bounce out
          _bounceLetter(lb);
        }
      }
    }
  }

  void _lockLetterInSlot(_LetterBody lb, _Slot slot, double shelfLeft, double slotWidth) {
    slot.filled = true;
    slot.glowTimer = 0;
    lb.isLocked = true;
    lb.isDropping = false;

    // Position exactly in slot center
    final slotCenterX = shelfLeft + (slot.index + 0.5) * slotWidth;
    final slotCenterY = _slotShelfY + 0.5;
    lb.body.setTransform(Vector2(slotCenterX, slotCenterY), 0);
    lb.body.linearVelocity = Vector2.zero();
    lb.body.angularVelocity = 0;
    lb.body.gravityScale = Vector2.zero();
    lb.body.setType(BodyType.static);

    // Score
    _score += 10;

    // Particle burst
    _spawnBurst(slotCenterX * _scale, slotCenterY * _scale, _themeColors[0], 8);

    // Play success sound
    widget.audioService.playSuccess();
    Haptics.correct();

    // Advance to next slot
    _nextSlotIndex++;

    // Check word complete
    if (_nextSlotIndex >= _currentWord.length) {
      _onWordComplete();
    }
  }

  void _onWordComplete() {
    _wordsCompleted++;
    _score += 50; // word bonus
    // Time bonus
    final timeBonus = (_timeRemaining / _gameDurationSecs * 20).round();
    _score += timeBonus;

    _wordCelebrating = true;
    _wordCelebrateT = 0;

    // Big celebration burst
    final cx = _areaWidth / 2;
    final cy = _slotShelfY * _scale;
    _spawnBurst(cx, cy, _themeColors[0], 20);
    _spawnBurst(cx, cy, _themeColors[1], 15);

    widget.audioService.playLevelCompleteEffect();
    widget.audioService.playSuccess();
    Haptics.success();
  }

  void _bounceLetter(_LetterBody lb) {
    lb.isBouncing = true;
    lb.bounceTimer = 0;

    // Strong upward impulse
    lb.body.applyLinearImpulse(
      Vector2(
        (_rng.nextDouble() - 0.5) * 8,
        -12,
      )..scale(lb.body.mass),
    );

    // Lose a life
    _lives--;
    widget.audioService.playError();
    Haptics.wrong();

    // Spawn error particles
    _spawnBurst(
      lb.body.position.x * _scale,
      lb.body.position.y * _scale,
      AppColors.error,
      6,
    );

    if (_lives <= 0) {
      _endGame();
    }
  }

  // -- Tap handling ---------------------------------------------------------

  void _onTapLetter(_LetterBody lb) {
    if (lb.isDropping || lb.isLocked || lb.isBouncing) return;
    if (_gameOver || _roundComplete || _wordCelebrating) return;

    // Enable gravity — drop it!
    lb.isDropping = true;
    lb.body.gravityScale = null; // restore world gravity
    lb.body.linearDamping = 0.3;

    // Small downward impulse to feel snappy
    lb.body.applyLinearImpulse(
      Vector2(0, 2)..scale(lb.body.mass),
    );
  }

  // -- Drag-to-aim handling -------------------------------------------------

  void _onPanStartLetter(_LetterBody lb, DragStartDetails details) {
    if (lb.isDropping || lb.isLocked || lb.isBouncing) return;
    if (_gameOver || _roundComplete || _wordCelebrating) return;
    _dragging = lb;
    _dragTimer = 0;
  }

  void _onPanUpdateLetter(DragUpdateDetails details) {
    if (_dragging == null) return;
    // Move letter body by the drag delta
    final dx = details.delta.dx / _scale;
    final dy = details.delta.dy / _scale;
    var newPos = _dragging!.body.position + Vector2(dx, dy);

    // Clamp to float zone — can't drag below float zone or near baskets
    final worldW = _areaWidth / _scale;
    newPos.x = newPos.x.clamp(0.3, worldW - 0.3);
    newPos.y = newPos.y.clamp(0.5, _floatZoneBottom);

    _dragging!.body.setTransform(newPos, _dragging!.body.angle);
    // Keep velocity zero while dragging
    _dragging!.body.linearVelocity = Vector2.zero();
  }

  void _onPanEndLetter(DragEndDetails details) {
    if (_dragging == null) return;
    final lb = _dragging!;
    _dragging = null;
    _dragTimer = 0;

    if (lb.isLocked || lb.isBouncing) return;

    // Enable gravity — letter drops from where it was released
    lb.isDropping = true;
    lb.body.gravityScale = null;
    lb.body.linearDamping = 0.3;

    // Apply fling velocity from the drag (only downward component)
    final vx = details.velocity.pixelsPerSecond.dx / _scale;
    final vy = details.velocity.pixelsPerSecond.dy / _scale;
    final vel = Vector2(vx, vy);
    // Cap velocity magnitude
    if (vel.length > 15) {
      vel.normalize();
      vel.scale(15);
    }
    // Ensure some minimum downward velocity
    if (vel.y < 2) vel.y = 2;
    lb.body.linearVelocity = vel;
  }

  // -- Particles ------------------------------------------------------------

  void _spawnBurst(double x, double y, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 40 + _rng.nextDouble() * 80;
      _particles.add(_Particle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        size: 2 + _rng.nextDouble() * 3,
        color: color,
      ));
    }
  }

  void _updateParticles() {
    for (final p in _particles) {
      p.x += p.vx * (1 / 30);
      p.y += p.vy * (1 / 30);
      p.vy += 60 * (1 / 30); // gravity
      p.opacity -= 0.03;
    }
    _particles.removeWhere((p) => p.opacity <= 0);
  }

  void _updateTrails() {
    for (final t in _trails) {
      t.opacity -= 0.05;
      t.size *= 0.95;
    }
    _trails.removeWhere((t) => t.opacity <= 0);
  }

  // -- Replay ---------------------------------------------------------------

  void _replay() {
    // Destroy all physics bodies except walls
    _clearLetterBodies();
    _clearSlotDividers();

    _buildWordPool();
    _pickThemeColors();
    _startGame();
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A2E), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: _gameOver
              ? _buildGameOver()
              : _roundComplete
                  ? _buildRoundComplete()
                  : _buildGameArea(),
        ),
      ),
    );
  }

  void _initializeLayout(double width, double height) {
    if (_initialized) return;
    _initialized = true;
    _areaWidth = width;
    _areaHeight = height;
    _slotShelfY = (_areaHeight - 80) / _scale;
    _floatZoneBottom = _areaHeight * 0.50 / _scale;
    _createWalls();
    _startGame();
  }

  Widget _buildGameArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Initialize physics on first layout (once only)
        if (!_initialized && !_initScheduled && w > 0 && h > 0) {
          _initScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _initializeLayout(w, h);
            }
          });
        }

        if (!_initialized) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.electricBlue),
          );
        }

        return Stack(
          children: [
            // Background stars (IgnorePointer so taps pass through)
            IgnorePointer(
              child: CustomPaint(
                size: Size(_areaWidth, _areaHeight),
                painter: _StarFieldPainter(seed: 77),
              ),
            ),

            // Slot shelf + particles + trails
            IgnorePointer(
              child: CustomPaint(
                size: Size(_areaWidth, _areaHeight),
                painter: _ShelfPainter(
                  slots: _slots,
                  currentWord: _currentWord,
                  slotShelfY: _slotShelfY,
                  scale: _scale,
                  areaWidth: _areaWidth,
                  themeColor: _themeColors[0],
                  particles: _particles,
                  trails: _trails,
                ),
              ),
            ),

            // Floating / dropping letter widgets
            ..._letterBodies
                .where((lb) => !lb.isLocked)
                .map(_buildLetterWidget),

            // Locked letters (in slots)
            ..._letterBodies
                .where((lb) => lb.isLocked)
                .map(_buildLockedLetterWidget),

            // HUD (uses Column with MainAxisSize.min to not block taps)
            _buildHUD(),

            // Target word display
            _buildTargetWord(),

            // Instruction hint
            if (_wordsCompleted == 0 &&
                _nextSlotIndex == 0 &&
                !_wordCelebrating)
              _buildInstruction(),

            // Word celebration overlay
            if (_wordCelebrating) _buildCelebration(),
          ],
        );
      },
    );
  }

  Widget _buildLetterWidget(_LetterBody lb) {
    final sx = lb.body.position.x * _scale;
    final sy = lb.body.position.y * _scale;
    const radius = 22.0;

    final isDragging = lb == _dragging;
    final color = lb.isBouncing
        ? AppColors.error
        : lb.isDropping
            ? _themeColors[0]
            : _themeColors[1];

    return Positioned(
      left: sx - radius,
      top: sy - radius,
      child: GestureDetector(
        onTap: () => _onTapLetter(lb),
        onPanStart: (d) => _onPanStartLetter(lb, d),
        onPanUpdate: _onPanUpdateLetter,
        onPanEnd: _onPanEndLetter,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: isDragging ? 0.55 : 0.35),
                color.withValues(alpha: isDragging ? 0.25 : 0.12),
              ],
            ),
            border: Border.all(
              color: color.withValues(alpha: isDragging ? 1.0 : 0.7),
              width: isDragging ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isDragging ? 0.7 : (lb.isDropping ? 0.5 : 0.2)),
                blurRadius: isDragging ? 24 : (lb.isDropping ? 16 : 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              lb.letter.toUpperCase(),
              style: GoogleFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.8),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedLetterWidget(_LetterBody lb) {
    final sx = lb.body.position.x * _scale;
    final sy = lb.body.position.y * _scale;
    const radius = 22.0;
    const color = AppColors.success;

    return Positioned(
      left: sx - radius,
      top: sy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.5),
              color.withValues(alpha: 0.2),
            ],
          ),
          border: Border.all(
            color: color.withValues(alpha: 0.9),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Center(
          child: Text(
            lb.letter.toUpperCase(),
            style: GoogleFonts.fredoka(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: color.withValues(alpha: 0.9),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHUD() {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.primaryText,
                size: 22,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _themeColors[0].withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: AppColors.starGold, size: 18),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: GoogleFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _timeRemaining <= 15
                    ? AppColors.error.withValues(alpha: 0.5)
                    : AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_rounded,
                  color: _timeRemaining <= 15
                      ? AppColors.error
                      : AppColors.secondaryText,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_timeRemaining}s',
                  style: GoogleFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _timeRemaining <= 15
                        ? AppColors.error
                        : AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Lives
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_maxLives, (i) {
              final active = i < _lives;
              return Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: active
                      ? AppColors.error
                      : AppColors.secondaryText.withValues(alpha: 0.3),
                  size: 20,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetWord() {
    return Positioned(
      top: 56,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Word counter
          Text(
            '${_wordsCompleted + 1} / $_wordsPerRound',
            style: GoogleFonts.fredoka(
              fontSize: 12,
              color: AppColors.secondaryText.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          // Target word
          GestureDetector(
            onTap: () => widget.audioService.playWord(_currentWord),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _themeColors[0].withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _themeColors[0].withValues(alpha: 0.15),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    color: _themeColors[0].withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentWord,
                    style: GoogleFonts.fredoka(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(
                          color: _themeColors[0].withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: _slotShelfY * _scale + 80,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _themeColors[0].withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'Drag & fling letters into the slots!',
              style: GoogleFonts.fredoka(
                fontSize: 14,
                color: AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCelebration() {
    final opacity = (1.0 - _wordCelebrateT / 1.8).clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Text(
              'Great job!',
              style: GoogleFonts.fredoka(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: AppColors.starGold,
                shadows: [
                  Shadow(
                    color: AppColors.starGold.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _lives <= 0 ? 'Game Over' : 'Time\'s Up!',
            style: GoogleFonts.fredoka(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$_wordsCompleted words completed',
            style: GoogleFonts.fredoka(
              fontSize: 18,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: AppColors.starGold, size: 24),
              const SizedBox(width: 6),
              Text(
                '$_score',
                style: GoogleFonts.fredoka(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildActionButton('Play Again', Icons.refresh_rounded, _replay),
          const SizedBox(height: 12),
          _buildActionButton('Back', Icons.arrow_back_rounded, () {
            Navigator.of(context).pop();
          }),
        ],
      ),
    );
  }

  Widget _buildRoundComplete() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Round Complete!',
            style: GoogleFonts.fredoka(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.starGold,
              shadows: [
                Shadow(
                  color: AppColors.starGold.withValues(alpha: 0.5),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$_wordsCompleted words completed',
            style: GoogleFonts.fredoka(
              fontSize: 18,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: AppColors.starGold, size: 24),
              const SizedBox(width: 6),
              Text(
                '$_score',
                style: GoogleFonts.fredoka(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildActionButton('Play Again', Icons.refresh_rounded, _replay),
          const SizedBox(height: 12),
          _buildActionButton('Back', Icons.arrow_back_rounded, () {
            Navigator.of(context).pop();
          }),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _themeColors[0].withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: _themeColors[0].withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _themeColors[0], size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Custom painters --------------------------------------------------------

class _StarFieldPainter extends CustomPainter {
  final int seed;
  _StarFieldPainter({this.seed = 42});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint();

    for (int i = 0; i < 50; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 1.2 + 0.3;
      paint.color = Colors.white.withValues(
        alpha: rng.nextDouble() * 0.3 + 0.1,
      );
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShelfPainter extends CustomPainter {
  final List<_Slot> slots;
  final String currentWord;
  final double slotShelfY;
  final double scale;
  final double areaWidth;
  final Color themeColor;
  final List<_Particle> particles;
  final List<_TrailDot> trails;

  _ShelfPainter({
    required this.slots,
    required this.currentWord,
    required this.slotShelfY,
    required this.scale,
    required this.areaWidth,
    required this.themeColor,
    required this.particles,
    required this.trails,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (currentWord.isEmpty || slots.isEmpty) return;

    final slotCount = currentWord.length;
    final worldW = areaWidth / scale;
    final slotWidth = (worldW * 0.8) / slotCount;
    final shelfLeft = worldW * 0.1;
    final shelfScreenLeft = shelfLeft * scale;
    final shelfScreenTop = slotShelfY * scale;
    final slotScreenWidth = slotWidth * scale;
    final shelfScreenHeight = 1.2 * scale;

    // Draw shelf background
    final shelfRect = Rect.fromLTWH(
      shelfScreenLeft,
      shelfScreenTop,
      slotScreenWidth * slotCount,
      shelfScreenHeight,
    );
    final shelfPaint = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shelfRect, const Radius.circular(8)),
      shelfPaint,
    );

    // Draw shelf border
    final borderPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(shelfRect, const Radius.circular(8)),
      borderPaint,
    );

    // Draw dividers
    final dividerPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (int i = 1; i < slotCount; i++) {
      final x = shelfScreenLeft + i * slotScreenWidth;
      canvas.drawLine(
        Offset(x, shelfScreenTop + 4),
        Offset(x, shelfScreenTop + shelfScreenHeight - 4),
        dividerPaint,
      );
    }

    // Draw slot hint letters (faded)
    for (int i = 0; i < slotCount; i++) {
      final slot = slots[i];
      if (!slot.filled) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: slot.expectedLetter.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 20,
              color: themeColor.withValues(alpha: 0.15),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final cx = shelfScreenLeft + (i + 0.5) * slotScreenWidth;
        final cy = shelfScreenTop + shelfScreenHeight / 2;
        textPainter.paint(
          canvas,
          Offset(cx - textPainter.width / 2, cy - textPainter.height / 2),
        );
      }

      // Glow effect for filled slots
      if (slot.filled && slot.glowTimer < 1.0) {
        final glowPaint = Paint()
          ..color = AppColors.success.withValues(alpha: (1.0 - slot.glowTimer) * 0.3);
        final cx = shelfScreenLeft + (i + 0.5) * slotScreenWidth;
        final cy = shelfScreenTop + shelfScreenHeight / 2;
        canvas.drawCircle(
          Offset(cx, cy),
          30 + slot.glowTimer * 20,
          glowPaint,
        );
      }
    }

    // Draw trails
    for (final t in trails) {
      final trailPaint = Paint()
        ..color = t.color.withValues(alpha: t.opacity * 0.5);
      canvas.drawCircle(Offset(t.x, t.y), t.size, trailPaint);
    }

    // Draw particles
    for (final p in particles) {
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: p.opacity.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x, p.y), p.size, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShelfPainter oldDelegate) => true;
}

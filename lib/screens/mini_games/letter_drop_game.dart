import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:forge2d/forge2d.dart' hide Transform;

import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../models/game_difficulty_params.dart';
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
  final bool hintsEnabled;
  final GameDifficultyParams? difficultyParams;

  const LetterDropGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
    this.hintsEnabled = true,
    this.difficultyParams,
  });

  @override
  State<LetterDropGame> createState() => _LetterDropGameState();
}

// -- Data models ------------------------------------------------------------

class _LetterBody {
  final String letter;
  final Body body;
  final int id;
  bool isDropping = false;
  bool isLocked = false;
  bool isBouncing = false;
  double bounceTimer = 0;
  double glowTimer = 0;
  Vector2 homePosition;
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

// -- Simulation ChangeNotifier -----------------------------------------------

class _LetterDropSim extends ChangeNotifier {
  final List<_LetterBody> letterBodies;
  List<_Slot> slots;
  final List<_Particle> particles;
  final List<_TrailDot> trails;
  String currentWord = '';
  double slotShelfY = 0;
  double scale = 50.0;
  double areaWidth = 0;
  double areaHeight = 0;
  List<Color> themeColors;
  bool hintsEnabled;
  double wordCelebrateT = 0;
  bool wordCelebrating = false;

  _LetterDropSim({
    required this.letterBodies,
    required this.slots,
    required this.particles,
    required this.trails,
    this.themeColors = const [Color(0xFF00D4FF), Color(0xFF06D6A0)],
    this.hintsEnabled = true,
  });

  void tick() {
    notifyListeners();
  }

  _LetterBody? hitTest(Offset localPos) {
    for (final lb in letterBodies) {
      if (lb.isLocked || lb.isDropping || lb.isBouncing) continue;
      final sx = lb.body.position.x * scale;
      final sy = lb.body.position.y * scale;
      final dx = localPos.dx - sx;
      final dy = localPos.dy - sy;
      if (dx * dx + dy * dy <= 22 * 22) return lb;
    }
    return null;
  }
}

// -- State ------------------------------------------------------------------

class _LetterDropGameState extends State<LetterDropGame>
    with SingleTickerProviderStateMixin {
  final _rng = Random();

  // Physics
  late final World _world;
  late final AnimationController _controller;
  static const double _scale = 50.0;
  static const int _minStepMicros = 33333;
  int _lastStepMicros = 0;

  // Game config
  late final int _maxLives;
  late final int _wordsPerRound;
  late final int _gameDurationSecs;
  static const int _maxDynamicBodies = 12;

  // Game state
  bool _gameOver = false;
  bool _roundComplete = false;
  int _score = 0;
  late int _lives;
  int _wordsCompleted = 0;
  late int _timeRemaining;
  Timer? _gameTimer;

  // Word state
  List<String> _wordPool = [];
  int _wordPoolIndex = 0;
  String _currentWord = '';
  int _nextSlotIndex = 0;
  List<_Slot> _slots = [];

  // Physics bodies
  final List<_LetterBody> _letterBodies = [];
  int _nextBodyId = 0;
  final List<Body> _wallBodies = [];
  final List<Body> _slotDividerBodies = [];

  // Drag-to-aim state
  _LetterBody? _dragging;
  double _dragTimer = 0;
  static const double _maxDragSecs = 2.0;

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
  double _slotShelfY = 0;
  double _floatZoneBottom = 0;

  // Colors for this round
  List<Color> _themeColors = [AppColors.electricBlue, AppColors.cyan];

  late final Stopwatch _sessionTimer;
  late final _LetterDropSim _sim;

  @override
  void initState() {
    super.initState();
    _maxLives = widget.difficultyParams?.lives ?? 3;
    _wordsPerRound = widget.difficultyParams?.wordCount ?? 8;
    _gameDurationSecs = widget.difficultyParams?.gameDurationSeconds.toInt() ?? 90;
    _lives = _maxLives;
    _timeRemaining = _gameDurationSecs;
    _sessionTimer = Stopwatch()..start();
    _world = World(Vector2(0, 9.8));
    _world.createBody(BodyDef());

    _sim = _LetterDropSim(
      letterBodies: _letterBodies,
      slots: _slots,
      particles: _particles,
      trails: _trails,
      themeColors: _themeColors,
      hintsEnabled: widget.hintsEnabled,
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 300),
    )..addListener(_simulationStep);

    _buildWordPool();
    _pickThemeColors();
  }

  @override
  void dispose() {
    _controller.dispose();
    _gameTimer?.cancel();
    _sessionTimer.stop();
    _sim.dispose();
    super.dispose();
  }

  // -- Theme colors ---------------------------------------------------------

  void _pickThemeColors() {
    final idx = _rng.nextInt(AppColors.levelGradients.length);
    _themeColors = AppColors.levelGradients[idx];
    _sim.themeColors = _themeColors;
  }

  // -- Word pool ------------------------------------------------------------

  void _buildWordPool() {
    final highest = widget.progressService.highestUnlockedLevel;
    final pool = <String>[];
    for (int lvl = 1; lvl <= highest; lvl++) {
      final words = DolchWords.wordsForLevel(lvl);
      for (final w in words) {
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

    _sim.currentWord = _currentWord;
    _sim.slots = _slots;

    _clearLetterBodies();
    _clearSlotDividers();
    _createSlotShelf();
    _populateLetters();
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

    _createStaticEdge(
      Vector2(-0.1, 0),
      Vector2(-0.1, worldH),
    );
    _createStaticEdge(
      Vector2(worldW + 0.1, 0),
      Vector2(worldW + 0.1, worldH),
    );
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

    _createSlotDivider(
      Vector2(shelfLeft, shelfTop + shelfHeight),
      Vector2(shelfLeft + slotWidth * slotCount, shelfTop + shelfHeight),
    );

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
    final distractorCount = max(2, 8 - wordLetters.length);
    final distractors = _generateDistractors(wordLetters, distractorCount);

    final allLetters = [...wordLetters, ...distractors];
    allLetters.shuffle(_rng);

    final worldW = _areaWidth / _scale;
    const floatTop = 120.0 / _scale;
    final floatHeight = _floatZoneBottom - floatTop;

    for (int i = 0; i < allLetters.length && _letterBodies.length < _maxDynamicBodies; i++) {
      final letter = allLetters[i];
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
      gravityScale: Vector2.zero(),
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

    _world.stepDt(1 / 60);

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

    for (final lb in _letterBodies) {
      if (lb.isLocked || lb.isDropping || lb == _dragging) continue;

      final delta = lb.homePosition - lb.body.position;
      final dist = delta.length;
      if (dist > 0.1) {
        final springForce = delta.normalized()..scale(dist * 2.0);
        lb.body.applyLinearImpulse(springForce..scale(lb.body.mass * 0.05));
      }

      lb.wobblePhase += 0.03;
      final wobbleX = sin(lb.wobblePhase) * 0.15;
      final wobbleY = cos(lb.wobblePhase * 0.7) * 0.1;
      lb.body.applyLinearImpulse(
        Vector2(wobbleX, wobbleY)..scale(lb.body.mass * 0.02),
      );
    }

    _checkSlotCollisions();

    for (final lb in _letterBodies) {
      if (lb.isBouncing) {
        lb.bounceTimer += 1 / 30;
        if (lb.bounceTimer > 1.5) {
          lb.isBouncing = false;
          lb.isDropping = false;
          lb.body.gravityScale = Vector2.zero();
          lb.body.linearDamping = 2.0;
          final worldH = _areaHeight / _scale;
          if (lb.body.position.y > worldH - 1.0 || lb.body.position.y < 0) {
            lb.body.setTransform(lb.homePosition, 0);
            lb.body.linearVelocity = Vector2.zero();
          }
        }
      }
    }

    for (final slot in _slots) {
      if (slot.filled && slot.glowTimer < 1.0) {
        slot.glowTimer = (slot.glowTimer + 0.03).clamp(0.0, 1.0);
      }
    }

    _updateParticles();
    _updateTrails();

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

    if (_wordCelebrating) {
      _wordCelebrateT += 1 / 30;
      _sim.wordCelebrateT = _wordCelebrateT;
      _sim.wordCelebrating = _wordCelebrating;
      if (_wordCelebrateT > 1.8) {
        _wordCelebrating = false;
        _wordCelebrateT = 0;
        _sim.wordCelebrating = false;
        _sim.wordCelebrateT = 0;
        _loadNextWord();
      }
    }

    _sim.tick();
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
      if (pos.y >= _slotShelfY - 0.2 && pos.y <= _slotShelfY + 1.5) {
        final relX = pos.x - shelfLeft;
        if (relX < 0 || relX > slotWidth * slotCount) continue;
        final slotIdx = (relX / slotWidth).floor().clamp(0, slotCount - 1);
        final slot = _slots[slotIdx];

        if (slot.filled) continue;

        if (slotIdx == _nextSlotIndex &&
            lb.letter == slot.expectedLetter) {
          _lockLetterInSlot(lb, slot, shelfLeft, slotWidth);
        } else {
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

    final slotCenterX = shelfLeft + (slot.index + 0.5) * slotWidth;
    final slotCenterY = _slotShelfY + 0.5;
    lb.body.setTransform(Vector2(slotCenterX, slotCenterY), 0);
    lb.body.linearVelocity = Vector2.zero();
    lb.body.angularVelocity = 0;
    lb.body.gravityScale = Vector2.zero();
    lb.body.setType(BodyType.static);

    _spawnBurst(slotCenterX * _scale, slotCenterY * _scale, _themeColors[0], 8);

    widget.audioService.playSuccess();
    Haptics.correct();

    _nextSlotIndex++;

    setState(() {
      _score += 10;
    });

    if (_nextSlotIndex >= _currentWord.length) {
      _onWordComplete();
    }
  }

  void _onWordComplete() {
    _wordsCompleted++;
    final timeBonus = (_timeRemaining / _gameDurationSecs * 20).round();

    _wordCelebrating = true;
    _wordCelebrateT = 0;
    _sim.wordCelebrating = true;
    _sim.wordCelebrateT = 0;

    final cx = _areaWidth / 2;
    final cy = _slotShelfY * _scale;
    _spawnBurst(cx, cy, _themeColors[0], 20);
    _spawnBurst(cx, cy, _themeColors[1], 15);

    widget.audioService.playLevelCompleteEffect();
    widget.audioService.playSuccess();
    Haptics.success();

    setState(() {
      _score += 50 + timeBonus;
    });
  }

  void _bounceLetter(_LetterBody lb) {
    lb.isBouncing = true;
    lb.bounceTimer = 0;

    lb.body.applyLinearImpulse(
      Vector2(
        (_rng.nextDouble() - 0.5) * 8,
        -12,
      )..scale(lb.body.mass),
    );

    widget.audioService.playError();
    Haptics.wrong();

    _spawnBurst(
      lb.body.position.x * _scale,
      lb.body.position.y * _scale,
      AppColors.error,
      6,
    );

    setState(() {
      _lives--;
    });

    if (_lives <= 0) {
      _endGame();
    }
  }

  // -- Tap handling ---------------------------------------------------------

  void _onTapLetter(_LetterBody lb) {
    if (lb.isDropping || lb.isLocked || lb.isBouncing) return;
    if (_gameOver || _roundComplete || _wordCelebrating) return;

    lb.isDropping = true;
    lb.body.gravityScale = null;
    lb.body.linearDamping = 0.3;

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
    final dx = details.delta.dx / _scale;
    final dy = details.delta.dy / _scale;
    var newPos = _dragging!.body.position + Vector2(dx, dy);

    final worldW = _areaWidth / _scale;
    newPos.x = newPos.x.clamp(0.3, worldW - 0.3);
    newPos.y = newPos.y.clamp(0.5, _floatZoneBottom);

    _dragging!.body.setTransform(newPos, _dragging!.body.angle);
    _dragging!.body.linearVelocity = Vector2.zero();
  }

  void _onPanEndLetter(DragEndDetails details) {
    if (_dragging == null) return;
    final lb = _dragging!;
    _dragging = null;
    _dragTimer = 0;

    if (lb.isLocked || lb.isBouncing) return;

    lb.isDropping = true;
    lb.body.gravityScale = null;
    lb.body.linearDamping = 0.3;

    final vx = details.velocity.pixelsPerSecond.dx / _scale;
    final vy = details.velocity.pixelsPerSecond.dy / _scale;
    final vel = Vector2(vx, vy);
    if (vel.length > 15) {
      vel.normalize();
      vel.scale(15);
    }
    if (vel.y < 2) vel.y = 2;
    lb.body.linearVelocity = vel;
  }

  // -- Canvas hit-test handlers ---------------------------------------------

  void _onCanvasTapUp(TapUpDetails details) {
    final lb = _sim.hitTest(details.localPosition);
    if (lb != null) _onTapLetter(lb);
  }

  void _onCanvasPanStart(DragStartDetails details) {
    final lb = _sim.hitTest(details.localPosition);
    if (lb != null) _onPanStartLetter(lb, details);
  }

  void _onCanvasPanUpdate(DragUpdateDetails details) {
    _onPanUpdateLetter(details);
  }

  void _onCanvasPanEnd(DragEndDetails details) {
    _onPanEndLetter(details);
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
      p.vy += 60 * (1 / 30);
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

    _sim.areaWidth = _areaWidth;
    _sim.areaHeight = _areaHeight;
    _sim.slotShelfY = _slotShelfY;
    _sim.scale = _scale;

    _createWalls();
    _startGame();
  }

  Widget _buildGameArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

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
            RepaintBoundary(
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(_areaWidth, _areaHeight),
                  painter: _StarFieldPainter(seed: 77),
                ),
              ),
            ),

            Positioned.fill(
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: _onCanvasTapUp,
                  onPanStart: _onCanvasPanStart,
                  onPanUpdate: _onCanvasPanUpdate,
                  onPanEnd: _onCanvasPanEnd,
                  child: CustomPaint(
                    size: Size(_areaWidth, _areaHeight),
                    painter: _LetterDropPainter(_sim),
                  ),
                ),
              ),
            ),

            _buildHUD(),
            _buildTargetWord(),

            if (_wordsCompleted == 0 &&
                _nextSlotIndex == 0 &&
                !_wordCelebrating)
              _buildInstruction(),
          ],
        );
      },
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
                  style: AppFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

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
                  style: AppFonts.fredoka(
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
          Text(
            '${_wordsCompleted + 1} / $_wordsPerRound',
            style: AppFonts.fredoka(
              fontSize: 12,
              color: AppColors.secondaryText.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
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
                    style: AppFonts.fredoka(
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
              style: AppFonts.fredoka(
                fontSize: 14,
                color: AppColors.secondaryText,
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
            style: AppFonts.fredoka(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$_wordsCompleted words completed',
            style: AppFonts.fredoka(
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
                style: AppFonts.fredoka(
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
            style: AppFonts.fredoka(
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
            style: AppFonts.fredoka(
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
                style: AppFonts.fredoka(
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
              style: AppFonts.fredoka(
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

class _LetterDropPainter extends CustomPainter {
  final _LetterDropSim sim;

  _LetterDropPainter(this.sim) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    if (sim.currentWord.isEmpty || sim.areaWidth == 0) return;

    _paintShelf(canvas, size);
    _paintTrails(canvas);
    _paintParticles(canvas);
    _paintLetters(canvas);

    if (sim.wordCelebrating) {
      _paintCelebration(canvas, size);
    }
  }

  void _paintShelf(Canvas canvas, Size size) {
    final slots = sim.slots;
    final currentWord = sim.currentWord;
    if (slots.isEmpty) return;

    final slotCount = currentWord.length;
    final worldW = sim.areaWidth / sim.scale;
    final slotWidth = (worldW * 0.8) / slotCount;
    final shelfLeft = worldW * 0.1;
    final shelfScreenLeft = shelfLeft * sim.scale;
    final shelfScreenTop = sim.slotShelfY * sim.scale;
    final slotScreenWidth = slotWidth * sim.scale;
    final shelfScreenHeight = 1.2 * sim.scale;
    final themeColor = sim.themeColors.isNotEmpty ? sim.themeColors[0] : AppColors.electricBlue;

    final shelfRect = Rect.fromLTWH(
      shelfScreenLeft,
      shelfScreenTop,
      slotScreenWidth * slotCount,
      shelfScreenHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shelfRect, const Radius.circular(8)),
      Paint()..color = AppColors.surface.withValues(alpha: 0.6),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(shelfRect, const Radius.circular(8)),
      Paint()
        ..color = themeColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

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

    for (int i = 0; i < slotCount; i++) {
      final slot = slots[i];
      if (!slot.filled && sim.hintsEnabled) {
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
  }

  void _paintTrails(Canvas canvas) {
    for (final t in sim.trails) {
      canvas.drawCircle(
        Offset(t.x, t.y),
        t.size,
        Paint()..color = t.color.withValues(alpha: t.opacity * 0.5),
      );
    }
  }

  void _paintParticles(Canvas canvas) {
    for (final p in sim.particles) {
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size,
        Paint()..color = p.color.withValues(alpha: p.opacity.clamp(0.0, 1.0)),
      );
    }
  }

  void _paintLetters(Canvas canvas) {
    final scale = sim.scale;
    final themeColors = sim.themeColors;

    for (final lb in sim.letterBodies) {
      final sx = lb.body.position.x * scale;
      final sy = lb.body.position.y * scale;
      const radius = 22.0;
      final center = Offset(sx, sy);

      Color color;
      double borderWidth;
      double glowRadius;
      double fillAlpha;
      double borderAlpha;
      double shadowAlpha;

      if (lb.isLocked) {
        color = AppColors.success;
        borderWidth = 2.5;
        glowRadius = 20;
        fillAlpha = 0.5;
        borderAlpha = 0.9;
        shadowAlpha = 0.6;
      } else {
        color = lb.isBouncing && sim.hintsEnabled
            ? AppColors.error
            : lb.isDropping
                ? themeColors[0]
                : themeColors[1];
        borderWidth = 2;
        glowRadius = lb.isDropping ? 16 : 8;
        fillAlpha = 0.35;
        borderAlpha = 0.7;
        shadowAlpha = lb.isDropping ? 0.5 : 0.2;
      }

      // Glow
      canvas.drawCircle(
        center,
        radius + 4,
        Paint()
          ..color = color.withValues(alpha: shadowAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius.toDouble()),
      );

      // Fill gradient
      final gradient = RadialGradient(
        colors: [
          color.withValues(alpha: fillAlpha),
          color.withValues(alpha: fillAlpha * 0.4),
        ],
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius)),
      );

      // Border
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = color.withValues(alpha: borderAlpha),
      );

      // Letter text
      final tp = TextPainter(
        text: TextSpan(
          text: lb.letter.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 22,
            fontWeight: lb.isLocked ? FontWeight.w700 : FontWeight.w600,
            color: Colors.white,
            shadows: [
              Shadow(
                color: color.withValues(alpha: lb.isLocked ? 0.9 : 0.8),
                blurRadius: lb.isLocked ? 12 : 8,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
    }
  }

  void _paintCelebration(Canvas canvas, Size size) {
    final opacity = (1.0 - sim.wordCelebrateT / 1.8).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: 'Great job!',
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppColors.starGold.withValues(alpha: opacity),
          shadows: [
            Shadow(
              color: AppColors.starGold.withValues(alpha: opacity * 0.6),
              blurRadius: 20,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(
      (size.width - tp.width) / 2,
      (size.height - tp.height) / 2,
    ));
  }

  @override
  bool shouldRepaint(covariant _LetterDropPainter old) => false;
}

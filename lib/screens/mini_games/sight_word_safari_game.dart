import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/high_score_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Sight Word Safari -- hear an animal name, tap the matching animal card.
// Each animal IS the word: the child hears "tiger" and taps the tiger.
// ---------------------------------------------------------------------------

/// An animal with its display name used as the target word.
class _SafariAnimal {
  final String name; // also the target word
  final String emoji;
  final Color color;

  const _SafariAnimal(this.name, this.emoji, this.color);
}

/// All available safari animals. Each animal's name is the sight word.
const _allAnimals = <_SafariAnimal>[
  _SafariAnimal('tiger', '\u{1F42F}', Color(0xFFFF8C42)),
  _SafariAnimal('elephant', '\u{1F418}', Color(0xFF8E8E8E)),
  _SafariAnimal('monkey', '\u{1F435}', Color(0xFFCD853F)),
  _SafariAnimal('parrot', '\u{1F99C}', Color(0xFF00E68A)),
  _SafariAnimal('frog', '\u{1F438}', Color(0xFF4CAF50)),
  _SafariAnimal('toucan', '\u{1F426}', Color(0xFFFFD700)),
  _SafariAnimal('lion', '\u{1F981}', Color(0xFFE8A317)),
  _SafariAnimal('bear', '\u{1F43B}', Color(0xFF8B5E3C)),
  _SafariAnimal('snake', '\u{1F40D}', Color(0xFF66BB6A)),
  _SafariAnimal('owl', '\u{1F989}', Color(0xFFAB8D6B)),
  _SafariAnimal('rabbit', '\u{1F430}', Color(0xFFE8A0BF)),
  _SafariAnimal('fish', '\u{1F41F}', Color(0xFF42A5F5)),
  _SafariAnimal('fox', '\u{1F98A}', Color(0xFFFF7043)),
  _SafariAnimal('bat', '\u{1F987}', Color(0xFF7E57C2)),
  _SafariAnimal('whale', '\u{1F433}', Color(0xFF5C8FCC)),
  _SafariAnimal('turtle', '\u{1F422}', Color(0xFF388E3C)),
];

enum _CardState { idle, correct, wrong }

class _AnimalCard {
  final _SafariAnimal animal;
  final double bouncePhase;
  _CardState state = _CardState.idle;

  _AnimalCard({required this.animal, required this.bouncePhase});

  String get word => animal.name;
}

// ---------------------------------------------------------------------------

class SightWordSafariGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;

  const SightWordSafariGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
  });

  @override
  State<SightWordSafariGame> createState() => _SightWordSafariGameState();
}

class _SightWordSafariGameState extends State<SightWordSafariGame>
    with TickerProviderStateMixin {
  static const _gameId = 'sight_word_safari';
  static const _roundCount = 12;
  static const _roundDurationSecs = 10;

  final _rng = Random();

  // Round state
  int _round = 0;
  String _targetWord = '';
  List<_AnimalCard> _animals = [];
  int? _selectedIndex;
  bool _answered = false;
  bool _gameOver = false;
  bool _isNewBest = false;

  // Pool of animals shuffled for this session
  late List<_SafariAnimal> _animalPool;

  // Score
  int _score = 0;
  int _streak = 0;

  // Timer
  Timer? _roundTimer;
  int _timeLeft = _roundDurationSecs;

  // Animations
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  late AnimationController _entranceController;
  late AnimationController _completionController;

  // Jungle particles
  late List<_JungleParticle> _particles;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _particles = List.generate(15, (_) => _JungleParticle(_rng));

    _initGame();
  }

  void _initGame() {
    _animalPool = List<_SafariAnimal>.from(_allAnimals)..shuffle(_rng);
    _round = 0;
    _score = 0;
    _streak = 0;
    _gameOver = false;
    _isNewBest = false;

    _nextRound();
  }

  /// Speak an animal word. Tries bundled word audio first; falls back to
  /// spelling it out letter-by-letter for animals without audio files.
  Future<void> _speakAnimalWord(String word) async {
    final success = await widget.audioService.playWord(word);
    if (!success) {
      // Spell it out letter by letter
      for (int i = 0; i < word.length; i++) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        await widget.audioService.playLetter(word[i]);
      }
    }
  }

  void _nextRound() {
    if (_round >= _roundCount) {
      _endGame();
      return;
    }

    // Difficulty ramp: start with 3 animals, add one every 3 rounds, max 6
    final animalCount = min(3 + (_round ~/ 3), 6);

    // Pick distinct animals for this round
    final pool = List<_SafariAnimal>.from(_animalPool)..shuffle(_rng);
    final roundAnimals = pool.take(animalCount).toList();

    // Target is one of the animals shown
    final target = roundAnimals[_rng.nextInt(roundAnimals.length)];
    _targetWord = target.name;

    _animals = roundAnimals.map((a) {
      return _AnimalCard(
        animal: a,
        bouncePhase: _rng.nextDouble() * 2 * pi,
      );
    }).toList()
      ..shuffle(_rng);

    _selectedIndex = null;
    _answered = false;
    _timeLeft = _roundDurationSecs;

    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          _onTimeout();
        }
      });
    });

    _entranceController.forward(from: 0.0);
    _speakAnimalWord(_targetWord);

    if (mounted) setState(() {});
  }

  void _onAnimalTap(int index) {
    if (_answered || _gameOver) return;
    _answered = true;
    _roundTimer?.cancel();

    setState(() {
      _selectedIndex = index;
    });

    if (_animals[index].word == _targetWord) {
      // Correct
      Haptics.success();
      widget.audioService.playSuccess();
      _bounceController.forward(from: 0.0);

      _streak++;
      final timeBonus = _timeLeft * 2;
      final streakBonus = (_streak - 1) * 3;
      _score += 10 + timeBonus + streakBonus;

      setState(() {
        _animals[index].state = _CardState.correct;
      });

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || _gameOver) return;
        _round++;
        _nextRound();
      });
    } else {
      // Wrong
      Haptics.wrong();
      widget.audioService.playError();
      _shakeController.forward(from: 0.0);
      _streak = 0;

      setState(() {
        _animals[index].state = _CardState.wrong;
        // Highlight correct answer
        for (final a in _animals) {
          if (a.word == _targetWord) a.state = _CardState.correct;
        }
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted || _gameOver) return;
        _round++;
        _nextRound();
      });
    }
  }

  void _onTimeout() {
    if (_answered || _gameOver) return;
    _answered = true;
    _streak = 0;

    widget.audioService.playError();

    setState(() {
      for (final a in _animals) {
        if (a.word == _targetWord) a.state = _CardState.correct;
      }
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted || _gameOver) return;
      _round++;
      _nextRound();
    });
  }

  Future<void> _endGame() async {
    _roundTimer?.cancel();
    _gameOver = true;

    final isNewBest = await widget.highScoreService.saveScore(
      _gameId,
      _score,
      widget.playerName,
    );

    if (mounted) {
      setState(() {
        _isNewBest = isNewBest;
      });
      widget.audioService.playLevelCompleteEffect();
      _completionController.forward(from: 0.0);
    }
  }

  void _restart() {
    _completionController.reset();
    _initGame();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    _bounceController.dispose();
    _shakeController.dispose();
    _entranceController.dispose();
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
            colors: [Color(0xFF0A2A10), Color(0xFF0A1A0A)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Jungle particles
              CustomPaint(
                painter: _JungleParticlePainter(particles: _particles),
                size: Size.infinite,
              ),

              Column(
                children: [
                  _buildHeader(),
                  if (!_gameOver) _buildTargetPrompt(),
                  if (!_gameOver) Expanded(child: _buildAnimalGrid()),
                  if (_gameOver) Expanded(child: _buildGameOver()),
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
              'Word Safari',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
          // Timer
          if (!_gameOver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (_timeLeft <= 3
                        ? AppColors.error
                        : AppColors.emerald)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_timeLeft <= 3
                          ? AppColors.error
                          : AppColors.emerald)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_rounded,
                    size: 14,
                    color:
                        _timeLeft <= 3 ? AppColors.error : AppColors.emerald,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_timeLeft',
                    style: AppFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _timeLeft <= 3
                          ? AppColors.error
                          : AppColors.emerald,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
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

  Widget _buildTargetPrompt() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            'Round ${_round + 1} of $_roundCount',
            style: AppFonts.nunito(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _speakAnimalWord(_targetWord),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.emerald.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.15),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.volume_up_rounded,
                    color: AppColors.emerald,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Find the $_targetWord!',
                    style: AppFonts.fredoka(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_streak > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Streak x$_streak',
                style: AppFonts.fredoka(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimalGrid() {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: List.generate(_animals.length, (i) {
              final delay = i * 0.15;
              final progress =
                  ((_entranceController.value - delay) / 0.5).clamp(0.0, 1.0);
              return Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * Curves.elasticOut.transform(progress),
                  child: _buildAnimalCard(i),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildAnimalCard(int index) {
    final animal = _animals[index];
    final isSelected = _selectedIndex == index;

    Color borderColor;
    Color bgColor;
    switch (animal.state) {
      case _CardState.correct:
        borderColor = AppColors.success;
        bgColor = AppColors.success.withValues(alpha: 0.1);
      case _CardState.wrong:
        borderColor = AppColors.error;
        bgColor = AppColors.error.withValues(alpha: 0.1);
      case _CardState.idle:
        borderColor = animal.animal.color.withValues(alpha: 0.5);
        bgColor = AppColors.surface;
    }

    Widget card = GestureDetector(
      onTap: () => _onAnimalTap(index),
      child: Container(
        width: 140,
        height: 170,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            if (isSelected && animal.state == _CardState.correct)
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            BoxShadow(
              color: animal.animal.color.withValues(alpha: 0.1),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animal emoji
            Text(
              animal.animal.emoji,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 8),
            // Animal name = the word
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: animal.animal.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: animal.animal.color.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                animal.word,
                style: AppFonts.fredoka(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Apply bounce animation to correct answer
    if (isSelected && animal.state == _CardState.correct) {
      card = AnimatedBuilder(
        animation: _bounceAnim,
        builder: (_, child) {
          return Transform.scale(scale: _bounceAnim.value, child: child);
        },
        child: card,
      );
    }

    // Apply shake to wrong answer
    if (isSelected && animal.state == _CardState.wrong) {
      card = AnimatedBuilder(
        animation: _shakeAnim,
        builder: (_, child) {
          final offset = sin(_shakeAnim.value * pi * 4) * 8;
          return Transform.translate(
            offset: Offset(offset, 0),
            child: child,
          );
        },
        child: card,
      );
    }

    return card;
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
                    color: AppColors.emerald.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emerald.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Safari Complete!',
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
                        backgroundColor: AppColors.emerald,
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

// ---- Jungle particle background ----

class _JungleParticle {
  final double x, y, size, speed, phase;
  final Color color;

  _JungleParticle(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        size = 2 + rng.nextDouble() * 4,
        speed = 0.3 + rng.nextDouble() * 0.5,
        phase = rng.nextDouble() * 2 * pi,
        color = const [
          Color(0xFF10B981),
          Color(0xFF059669),
          Color(0xFF34D399),
          Color(0xFFFFD700),
        ][rng.nextInt(4)];
}

class _JungleParticlePainter extends CustomPainter {
  final List<_JungleParticle> particles;
  _JungleParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        Paint()
          ..color = p.color.withValues(alpha: 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JungleParticlePainter old) => false;
}

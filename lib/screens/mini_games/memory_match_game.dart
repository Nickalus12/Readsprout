import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/dolch_words.dart';
import '../../data/sticker_definitions.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Memory Match — A card-flipping sight word matching game
// ─────────────────────────────────────────────────────────────────────────────

class MemoryMatchGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const MemoryMatchGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

class _MemoryMatchGameState extends State<MemoryMatchGame>
    with TickerProviderStateMixin {
  static const int _pairCount = 6;
  static const int _totalCards = _pairCount * 2;
  static const int _columns = 3;
  static const int _rows = 4;

  final _rng = Random();

  // Card data
  List<_CardData> _cards = [];

  // Precomputed star positions for card backs (indexed by card index)
  List<List<_MiniStar>> _cardStarPositions = [];

  // Flip state
  int? _firstFlippedIndex;
  bool _checkingMatch = false;

  // Score / stats
  int _moves = 0;
  int _matchesFound = 0;
  bool _gameComplete = false;

  // Timer
  late Stopwatch _stopwatch;
  Timer? _displayTimer;
  String _elapsedDisplay = '0:00';

  // Animation controllers — one per card for independent flip animations
  List<AnimationController> _flipControllers = [];
  List<Animation<double>> _flipAnimations = [];

  // Match glow controller
  late AnimationController _matchGlowController;
  late Animation<double> _matchGlow;

  // Stars entrance animation
  late AnimationController _starsController;

  // Background star positions
  late List<_StarParticle> _bgStars;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _stopwatch = Stopwatch();

    _matchGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _matchGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _matchGlowController, curve: Curves.easeOut),
    );

    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Generate background stars
    _bgStars = List.generate(40, (_) => _StarParticle.random(_rng));

    _initGame();
  }

  void _initGame() {
    // Gather words from unlocked levels
    final unlockedWords = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        final words = DolchWords.wordsForLevel(level);
        for (final w in words) {
          unlockedWords.add(w.text);
        }
      }
    }

    // Need at least 6 unique words
    if (unlockedWords.length < _pairCount) {
      final fallback = DolchWords.wordsForLevel(1);
      unlockedWords.clear();
      for (final w in fallback) {
        unlockedWords.add(w.text);
      }
    }

    // Pick 6 random words
    unlockedWords.shuffle(_rng);
    final chosen = unlockedWords.take(_pairCount).toList();

    // Create pairs and assign level-based gradient colors
    final cards = <_CardData>[];
    for (int i = 0; i < chosen.length; i++) {
      final word = chosen[i];
      // Find the word's level for color
      int wordLevel = 1;
      for (int l = 1; l <= DolchWords.totalLevels; l++) {
        final levelWords = DolchWords.wordsForLevel(l);
        if (levelWords.any((w) => w.text == word)) {
          wordLevel = l;
          break;
        }
      }
      final gradientIndex =
          (wordLevel - 1) % AppColors.levelGradients.length;

      cards.add(_CardData(word: word, pairId: i, gradientIndex: gradientIndex));
      cards.add(_CardData(word: word, pairId: i, gradientIndex: gradientIndex));
    }

    cards.shuffle(_rng);

    // Dispose old controllers if re-initializing
    for (final c in _flipControllers) {
      c.dispose();
    }

    // Create flip animation controllers
    _flipControllers = List.generate(_totalCards, (_) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
    });

    _flipAnimations = _flipControllers.map((c) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    // Precompute star positions for card backs so they don't shift on rebuild
    _cardStarPositions = List.generate(_totalCards, (_) {
      return List.generate(5, (_) => _MiniStar.random(_rng));
    });

    setState(() {
      _cards = cards;
      _firstFlippedIndex = null;

      _checkingMatch = false;
      _moves = 0;
      _matchesFound = 0;
      _gameComplete = false;
      _elapsedDisplay = '0:00';
    });

    _stopwatch.reset();
    _stopwatch.start();
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_gameComplete) {
        setState(() {
          _elapsedDisplay = _formatDuration(_stopwatch.elapsed);
        });
      }
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    _stopwatch.stop();
    for (final c in _flipControllers) {
      c.dispose();
    }
    _matchGlowController.dispose();
    _starsController.dispose();
    _sessionTimer.stop();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  int _computeStars() {
    if (_moves <= 8) return 3;
    if (_moves <= 12) return 2;
    return 1;
  }

  void _onCardTap(int index) {
    if (_checkingMatch) return;
    if (_cards[index].matched) return;
    if (index == _firstFlippedIndex) return;
    if (_flipControllers[index].value > 0) return;

    // Flip the card face-up
    _flipControllers[index].forward();

    if (_firstFlippedIndex == null) {
      setState(() {
        _firstFlippedIndex = index;
      });
    } else {
      setState(() {
        _moves++;
        _checkingMatch = true;
      });

      final firstIdx = _firstFlippedIndex!;
      final secondIdx = index;

      if (_cards[firstIdx].pairId == _cards[secondIdx].pairId) {
        _handleMatch(firstIdx, secondIdx);
      } else {
        _handleMismatch(firstIdx, secondIdx);
      }
    }
  }

  Future<void> _handleMatch(int firstIdx, int secondIdx) async {
    widget.audioService.playSuccess();
    Haptics.success();
    await Future.delayed(const Duration(milliseconds: 200));
    widget.audioService.playWord(_cards[firstIdx].word);

    _matchGlowController.forward(from: 0.0);

    setState(() {
      _cards[firstIdx].matched = true;
      _cards[secondIdx].matched = true;
      _matchesFound++;
      _firstFlippedIndex = null;

      _checkingMatch = false;
    });

    if (_matchesFound >= _pairCount) {
      _stopwatch.stop();
      _displayTimer?.cancel();
      _awardMiniGameStickers();
      setState(() {
        _gameComplete = true;
      });
      await Future.delayed(const Duration(milliseconds: 400));
      widget.audioService.playLevelCompleteEffect();
      _starsController.forward(from: 0.0);
    }
  }

  Future<void> _handleMismatch(int firstIdx, int secondIdx) async {
    widget.audioService.playError();
    Haptics.wrong();

    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    _flipControllers[firstIdx].reverse();
    _flipControllers[secondIdx].reverse();

    setState(() {
      _firstFlippedIndex = null;

      _checkingMatch = false;
    });
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    // Award completion sticker
    final earned = StickerDefinitions.miniGameStickersForScore('memory_match', _matchesFound);
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
    // Award misses-based stickers (sharp memory, perfect recall)
    final misses = _moves - _matchesFound;
    final missId = StickerDefinitions.memoryMatchPerfectId(misses);
    if (missId != null && !ps.hasSticker(missId)) {
      final def = StickerDefinitions.byId(missId);
      if (def != null) {
        ps.awardSticker(StickerRecord(
          stickerId: missId,
          dateEarned: DateTime.now(),
          category: def.category.name,
        ));
      }
    }
  }

  void _restartGame() {
    _starsController.reset();
    _matchGlowController.reset();
    _initGame();
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Background stars
              ..._bgStars.map((s) => Positioned(
                    left: s.x * MediaQuery.of(context).size.width,
                    top: s.y * MediaQuery.of(context).size.height,
                    child: Container(
                      width: s.size,
                      height: s.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: s.opacity),
                      ),
                    ),
                  )),

              // Ambient center glow
              Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.violet.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Main content
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _gameComplete
                        ? _buildGameComplete()
                        : _buildCardGrid(),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.primaryText),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Memory Match',
                  style: GoogleFonts.fredoka(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stats row - wraps on small screens
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _StatChip(
                icon: Icons.touch_app_rounded,
                label: '$_moves',
                color: AppColors.electricBlue,
              ),
              _StatChip(
                icon: Icons.timer_rounded,
                label: _elapsedDisplay,
                color: AppColors.violet,
              ),
              _StatChip(
                icon: Icons.stars_rounded,
                label: '$_matchesFound/$_pairCount',
                color: AppColors.starGold,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardGrid() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;

          final cardWidth = (availableWidth - (_columns - 1) * 12) / _columns;
          final cardHeight = (availableHeight - (_rows - 1) * 12) / _rows;
          final cardSize = min(cardWidth, cardHeight);

          final gridWidth = cardSize * _columns + (_columns - 1) * 12;
          final gridHeight = cardSize * _rows + (_rows - 1) * 12;

          return Center(
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(_totalCards, (index) {
                  return SizedBox(
                    width: cardSize,
                    height: cardSize,
                    child: _buildCard(index, cardSize),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(int index, double size) {
    final card = _cards[index];

    return AnimatedBuilder(
      animation: _flipAnimations[index],
      builder: (context, child) {
        final value = _flipAnimations[index].value;
        final isFront = value >= 0.5;
        final angle = value * pi;

        return AnimatedBuilder(
          animation: _matchGlow,
          builder: (context, _) {
            return GestureDetector(
              onTap: () => _onCardTap(index),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // perspective
                  ..rotateY(angle),
                child: isFront
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(pi),
                        child: _buildCardFront(card, size),
                      )
                    : _buildCardBack(index, size),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCardBack(int cardIndex, double size) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2D1B69),
            Color(0xFF1A1040),
          ],
        ),
        border: Border.all(
          color: AppColors.violet.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle star pattern (precomputed positions)
          ..._cardStarPositions[cardIndex].map((star) {
            return Positioned(
              left: star.xFrac * (size - 24) + 8,
              top: star.yFrac * (size - 24) + 8,
              child: Icon(
                Icons.star_rounded,
                size: star.size,
                color: AppColors.starGold.withValues(alpha: 0.15),
              ),
            );
          }),

          // Shimmer gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: const Alignment(-1.5, -1.5),
                  end: const Alignment(1.5, 1.5),
                  colors: [
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Question mark
          Center(
            child: Text(
              '?',
              style: GoogleFonts.fredoka(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w600,
                color: AppColors.violet.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFront(_CardData card, double size) {
    final gradient = AppColors.levelGradients[card.gradientIndex];
    final isMatched = card.matched;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFF8F8FF),
        border: Border.all(
          color: isMatched
              ? AppColors.starGold.withValues(alpha: 0.8)
              : gradient[0].withValues(alpha: 0.7),
          width: isMatched ? 3 : 2,
        ),
        boxShadow: [
          if (isMatched)
            BoxShadow(
              color: AppColors.starGold
                  .withValues(alpha: 0.3 + _matchGlow.value * 0.3),
              blurRadius: 16,
              spreadRadius: 2,
            )
          else
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Opacity(
        opacity: isMatched ? 0.8 : 1.0,
        child: Center(
          child: Text(
            card.word,
            style: GoogleFonts.fredoka(
              fontSize: size * 0.22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2A2A4A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameComplete() {
    final stars = _computeStars();
    final elapsed = _formatDuration(_stopwatch.elapsed);

    return Center(
      child: AnimatedBuilder(
        animation: _starsController,
        builder: (context, _) {
          final progress = _starsController.value;
          return Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + 0.2 * Curves.elasticOut.transform(progress),
              child: Container(
                margin: const EdgeInsets.all(32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.starGold.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'You found all the words!',
                      style: GoogleFonts.fredoka(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Stars
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final filled = i < stars;
                        final delay = i * 0.2;
                        final starProgress =
                            ((progress - delay) / 0.4).clamp(0.0, 1.0);
                        return Transform.scale(
                          scale: filled
                              ? Curves.elasticOut.transform(starProgress)
                              : 0.7,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 52,
                              color: filled
                                  ? AppColors.starGold
                                  : AppColors.secondaryText
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Stats
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CompleteStat(
                          icon: Icons.touch_app_rounded,
                          label: '$_moves moves',
                          color: AppColors.electricBlue,
                        ),
                        const SizedBox(width: 24),
                        _CompleteStat(
                          icon: Icons.timer_rounded,
                          label: elapsed,
                          color: AppColors.violet,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Replay button
                    ElevatedButton.icon(
                      onPressed: _restartGame,
                      icon: const Icon(Icons.replay_rounded, size: 22),
                      label: Text(
                        'Play Again',
                        style: GoogleFonts.fredoka(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.violet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Helper Widgets ─────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CompleteStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.fredoka(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.primaryText,
          ),
        ),
      ],
    );
  }
}

// ─── Data Models ────────────────────────────────────────────────────────────

class _CardData {
  final String word;
  final int pairId;
  final int gradientIndex;
  bool matched = false;

  _CardData({
    required this.word,
    required this.pairId,
    required this.gradientIndex,
  });
}

class _StarParticle {
  final double x;
  final double y;
  final double size;
  final double opacity;

  const _StarParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
  });

  factory _StarParticle.random(Random rng) {
    return _StarParticle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 1 + rng.nextDouble() * 2.5,
      opacity: 0.1 + rng.nextDouble() * 0.4,
    );
  }
}

class _MiniStar {
  final double xFrac; // 0..1 fraction within card area
  final double yFrac;
  final double size;

  const _MiniStar({
    required this.xFrac,
    required this.yFrac,
    required this.size,
  });

  factory _MiniStar.random(Random rng) {
    return _MiniStar(
      xFrac: rng.nextDouble(),
      yFrac: rng.nextDouble(),
      size: 3.0 + rng.nextDouble() * 3,
    );
  }
}

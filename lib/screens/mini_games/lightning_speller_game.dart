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
// Lightning Speller — A storm-themed spelling mini game
// ─────────────────────────────────────────────────────────────────────────────

class LightningSpellerGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final ProfileService? profileService;

  const LightningSpellerGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.profileService,
  });

  @override
  State<LightningSpellerGame> createState() => _LightningSpellerGameState();
}

class _LightningSpellerGameState extends State<LightningSpellerGame>
    with TickerProviderStateMixin {
  final _rng = Random();

  // Word state
  List<String> _wordPool = [];
  String _currentWord = '';
  List<String> _scrambledLetters = [];
  int _nextCorrectIndex = 0;
  bool _wordVisible = true;

  // Letter tile state: which tiles have been correctly tapped
  List<bool> _tileCorrect = [];
  // Maps from correct-order index to scrambled-tile index
  List<int> _correctOrderToTile = [];

  // Score
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  bool _madeErrorThisWord = false;

  // Lightning bolt animation
  int? _activeBoltTileIndex;
  late AnimationController _boltController;
  late Animation<double> _boltOpacity;

  // Error shake
  int? _errorTileIndex;
  late AnimationController _errorController;

  // Cloud breathing
  late AnimationController _cloudBreathController;

  // Cloud internal lightning flash
  late AnimationController _cloudFlashController;

  // Background lightning
  late AnimationController _bgLightningController;
  double _bgLightningX = 0.5;

  // Rain particles
  late AnimationController _rainController;
  final List<_RainDrop> _rainDrops = [];

  // Chain lightning (word complete)
  bool _chainActive = false;
  late AnimationController _chainController;

  // Error cloud flash (red)
  late AnimationController _errorFlashController;

  // Lives
  int _lives = 3;
  bool _gameOver = false;

  // Word reveal timer
  Timer? _revealTimer;

  // Tile positions (set after layout)
  final List<GlobalKey> _tileKeys = [];

  // Cloud key for position
  final GlobalKey _cloudKey = GlobalKey();

  // Game state
  bool _gameStarted = false;

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();
    _initControllers();
    _buildWordPool();
    _initRain();
    _startBackgroundEffects();

    // Small delay then start game
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _gameStarted = true);
        _nextWord();
      }
    });
  }

  void _initControllers() {
    _boltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _boltOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _boltController, curve: Curves.easeOut),
    );
    _boltController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _activeBoltTileIndex = null);
      }
    });

    _errorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _errorController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _errorTileIndex = null);
      }
    });

    _cloudBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _cloudFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _bgLightningController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _rainController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _rainController.addListener(() {
      if (mounted) setState(() => _updateRain());
    });

    _chainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _chainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _chainActive = false);
        // Move to next word after chain
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _nextWord();
        });
      }
    });

    _errorFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  void _initRain() {
    for (int i = 0; i < 60; i++) {
      _rainDrops.add(_RainDrop(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        speed: 0.005 + _rng.nextDouble() * 0.008,
        length: 8 + _rng.nextDouble() * 16,
        opacity: 0.15 + _rng.nextDouble() * 0.25,
      ));
    }
  }

  void _updateRain() {
    for (final drop in _rainDrops) {
      drop.y += drop.speed;
      if (drop.y > 1.0) {
        drop.y = -0.05;
        drop.x = _rng.nextDouble();
      }
    }
  }

  void _startBackgroundEffects() {
    // Periodic cloud internal flash
    _scheduleCloudFlash();
    // Periodic background lightning
    _scheduleBgLightning();
  }

  void _scheduleCloudFlash() {
    Future.delayed(Duration(milliseconds: 2000 + _rng.nextInt(4000)), () {
      if (!mounted) return;
      _cloudFlashController.forward(from: 0).then((_) {
        if (mounted) {
          _cloudFlashController.reverse().then((_) {
            // Sometimes double flash
            if (_rng.nextBool()) {
              Future.delayed(const Duration(milliseconds: 80), () {
                if (!mounted) return;
                _cloudFlashController.forward(from: 0).then((_) {
                  if (mounted) _cloudFlashController.reverse();
                });
              });
            }
          });
        }
      });
      _scheduleCloudFlash();
    });
  }

  void _scheduleBgLightning() {
    Future.delayed(Duration(milliseconds: 4000 + _rng.nextInt(6000)), () {
      if (!mounted) return;
      setState(() => _bgLightningX = 0.1 + _rng.nextDouble() * 0.8);
      _bgLightningController.forward(from: 0).then((_) {
        if (mounted) _bgLightningController.reverse();
      });
      _scheduleBgLightning();
    });
  }

  void _buildWordPool() {
    final unlocked = <String>[];
    for (int level = 1; level <= DolchWords.totalLevels; level++) {
      if (widget.progressService.isLevelUnlocked(level)) {
        final words = DolchWords.wordsForLevel(level);
        unlocked.addAll(words.map((w) => w.text.toLowerCase()));
      }
    }
    if (unlocked.isEmpty) {
      unlocked.addAll(
          DolchWords.wordsForLevel(1).map((w) => w.text.toLowerCase()));
    }
    unlocked.shuffle(_rng);
    _wordPool = unlocked;
  }

  void _nextWord() {
    if (!mounted) return;

    // Pick a word, progressively favoring longer ones as score increases
    String word;
    if (_wordPool.isEmpty) _buildWordPool();

    if (_score < 5) {
      // Easy: prefer short words
      final short = _wordPool.where((w) => w.length <= 4).toList();
      word = (short.isNotEmpty ? short : _wordPool)[
          _rng.nextInt((short.isNotEmpty ? short : _wordPool).length)];
    } else if (_score < 15) {
      word = _wordPool[_rng.nextInt(_wordPool.length)];
    } else {
      // Hard: prefer longer words
      final long = _wordPool.where((w) => w.length >= 4).toList();
      word = (long.isNotEmpty ? long : _wordPool)[
          _rng.nextInt((long.isNotEmpty ? long : _wordPool).length)];
    }

    // Scramble letters
    final letters = word.split('');
    final scrambled = List<String>.from(letters);
    // Ensure scrambled is different from original (if word > 1 char)
    if (word.length > 1) {
      int tries = 0;
      do {
        scrambled.shuffle(_rng);
        tries++;
      } while (scrambled.join() == word && tries < 20);
    }

    // Build mapping: for each correct index, which tile holds it
    // We need to track: when user taps the i-th correct letter, which
    // scrambled tile should light up.
    // Map each position in the original word to where it ended up in scrambled.
    final mapping = <int>[];
    final used = List<bool>.filled(scrambled.length, false);
    for (int ci = 0; ci < letters.length; ci++) {
      for (int si = 0; si < scrambled.length; si++) {
        if (!used[si] && scrambled[si] == letters[ci]) {
          mapping.add(si);
          used[si] = true;
          break;
        }
      }
    }

    setState(() {
      _currentWord = word;
      _scrambledLetters = scrambled;
      _nextCorrectIndex = 0;
      _tileCorrect = List<bool>.filled(scrambled.length, false);
      _correctOrderToTile = mapping;
      _madeErrorThisWord = false;
      _wordVisible = true;
      _chainActive = false;
      _activeBoltTileIndex = null;
      _errorTileIndex = null;

      // Create tile keys
      _tileKeys.clear();
      for (int i = 0; i < scrambled.length; i++) {
        _tileKeys.add(GlobalKey());
      }
    });

    // Play the word
    widget.audioService.playWord(word);

    // Hide word after 2 seconds
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _wordVisible = false);
    });
  }

  void _onTileTap(int tileIndex) {
    if (_gameOver) return;
    if (_chainActive) return;
    if (_tileCorrect[tileIndex]) return; // Already used

    // Check if the tapped letter matches the expected letter.
    // For duplicate letters (e.g. "well" has two L's), accept ANY
    // untapped tile with the correct letter — don't require the
    // specific tile from the pre-built mapping.
    final expectedLetter = _currentWord[_nextCorrectIndex];
    if (_scrambledLetters[tileIndex] == expectedLetter) {
      // Update the mapping so subsequent lookups stay consistent
      final originalTile = _correctOrderToTile[_nextCorrectIndex];
      if (originalTile != tileIndex) {
        // Swap: find a later mapping entry that points to tileIndex
        // and give it the originally-mapped tile instead.
        for (int j = _nextCorrectIndex + 1;
            j < _correctOrderToTile.length;
            j++) {
          if (_correctOrderToTile[j] == tileIndex) {
            _correctOrderToTile[j] = originalTile;
            break;
          }
        }
        _correctOrderToTile[_nextCorrectIndex] = tileIndex;
      }
      _handleCorrectTap(tileIndex);
    } else {
      _handleWrongTap(tileIndex);
    }
  }

  void _handleCorrectTap(int tileIndex) {
    Haptics.correct();
    // Play letter sound
    widget.audioService.playLetter(_scrambledLetters[tileIndex]);

    setState(() {
      _tileCorrect[tileIndex] = true;
      _activeBoltTileIndex = tileIndex;
      _nextCorrectIndex++;
    });

    // Flash the cloud
    _cloudFlashController.forward(from: 0).then((_) {
      if (mounted) _cloudFlashController.reverse();
    });

    // Animate lightning bolt
    _boltController.forward(from: 0);

    // Check if word is complete
    if (_nextCorrectIndex >= _currentWord.length) {
      _handleWordComplete();
    }
  }

  void _handleWrongTap(int tileIndex) {
    widget.audioService.playError();
    Haptics.wrong();
    _madeErrorThisWord = true;

    setState(() {
      _errorTileIndex = tileIndex;
      _combo = 0;
      _lives--;
    });

    _errorController.forward(from: 0);

    // Red cloud flash
    _errorFlashController.forward(from: 0).then((_) {
      if (mounted) _errorFlashController.reverse();
    });

    // Check game over
    if (_lives <= 0) {
      _revealTimer?.cancel();
      _awardMiniGameStickers();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _gameOver = true);
      });
    }
  }

  void _handleWordComplete() {
    widget.audioService.playSuccess();
    Haptics.success();

    setState(() {
      _score++;
      if (!_madeErrorThisWord) {
        _combo++;
        if (_combo > _bestCombo) _bestCombo = _combo;
      } else {
        _combo = 0;
      }
      _chainActive = true;
    });

    _chainController.forward(from: 0);
  }

  void _replayWord() {
    widget.audioService.playWord(_currentWord);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _boltController.dispose();
    _errorController.dispose();
    _cloudBreathController.dispose();
    _cloudFlashController.dispose();
    _errorFlashController.dispose();
    _bgLightningController.dispose();
    _rainController.dispose();
    _chainController.dispose();
    _sessionTimer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background
          _buildBackground(),
          // Rain
          _buildRain(),
          // Background lightning
          _buildBgLightning(),
          // Main content
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 8),
                // Cloud area
                _buildCloudArea(),
                // Word display
                _buildWordDisplay(),
                const Spacer(),
                // Lightning bolt overlay is painted via CustomPaint in stack
                // Letter tiles
                _buildLetterTiles(),
                const SizedBox(height: 32),
              ],
            ),
          ),
          // Lightning bolt overlay
          if (_activeBoltTileIndex != null)
            AnimatedBuilder(
              animation: _boltOpacity,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _LightningBoltPainter(
                    from: _getCloudBottomCenter(),
                    to: _getTileCenter(_activeBoltTileIndex!),
                    opacity: _boltOpacity.value,
                    rng: _rng,
                  ),
                );
              },
            ),
          // Game over overlay
          if (_gameOver) _buildGameOver(),
          // Chain lightning overlay
          if (_chainActive)
            AnimatedBuilder(
              animation: _chainController,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _ChainLightningPainter(
                    tilePositions: _getAllTilePositions(),
                    progress: _chainController.value,
                    rng: _rng,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _awardMiniGameStickers() {
    final ps = widget.profileService;
    if (ps == null) return;
    final earned = StickerDefinitions.miniGameStickersForScore('lightning_speller', _score);
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

  void _restartGame() {
    setState(() {
      _lives = 3;
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _gameOver = false;
      _chainActive = false;
    });
    _buildWordPool();
    _nextWord();
  }

  Widget _buildGameOver() {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFF4466).withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4466).withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flash_off_rounded,
                  color: Color(0xFFFF4466), size: 48),
              const SizedBox(height: 12),
              Text(
                'Storm Over!',
                style: GoogleFonts.fredoka(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 20),
              _gameOverStat(Icons.bolt, 'Words Spelled', '$_score',
                  AppColors.electricBlue),
              const SizedBox(height: 10),
              _gameOverStat(Icons.local_fire_department, 'Best Combo',
                  '${_bestCombo}x', AppColors.starGold),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _gameOverButton(
                    'Exit',
                    const Color(0xFF3A3A5C),
                    () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 16),
                  _gameOverButton(
                    'Play Again',
                    AppColors.electricBlue,
                    _restartGame,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameOverStat(
      IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.fredoka(
            fontSize: 16,
            color: AppColors.secondaryText,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.fredoka(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _gameOverButton(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: GoogleFonts.fredoka(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color == const Color(0xFF3A3A5C)
                ? AppColors.secondaryText
                : color,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.primaryText),
          ),
          const Spacer(),
          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.electricBlue
                      .withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: AppColors.electricBlue, size: 20),
                const SizedBox(width: 6),
                Text(
                  '$_score',
                  style: GoogleFonts.fredoka(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Combo
          if (_combo > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.starGold.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department,
                      color: AppColors.starGold, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${_combo}x',
                    style: GoogleFonts.fredoka(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.starGold,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          // Lives
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final alive = i < _lives;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  alive ? Icons.favorite : Icons.favorite_border,
                  color: alive
                      ? const Color(0xFFFF4466)
                      : const Color(0xFF3A3A5C),
                  size: 22,
                ),
              );
            }),
          ),
          const Spacer(),
          // Replay button
          IconButton(
            onPressed: _gameOver ? null : _replayWord,
            icon: const Icon(Icons.volume_up_rounded,
                color: AppColors.secondaryText),
            tooltip: 'Hear word again',
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D0520), // Deep storm purple
            Color(0xFF0A0A1A), // Near black
            Color(0xFF080818),
          ],
        ),
      ),
    );
  }

  Widget _buildRain() {
    return AnimatedBuilder(
      animation: _rainController,
      builder: (context, _) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _RainPainter(drops: _rainDrops),
        );
      },
    );
  }

  Widget _buildBgLightning() {
    return AnimatedBuilder(
      animation: _bgLightningController,
      builder: (context, _) {
        if (_bgLightningController.value < 0.01) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _BgLightningPainter(
            x: _bgLightningX,
            opacity: _bgLightningController.value * 0.15,
            rng: _rng,
          ),
        );
      },
    );
  }

  Widget _buildCloudArea() {
    return SizedBox(
      key: _cloudKey,
      height: 140,
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [_cloudBreathController, _cloudFlashController, _errorFlashController]),
        builder: (context, _) {
          final breathOffset =
              sin(_cloudBreathController.value * pi) * 4;
          return Transform.translate(
            offset: Offset(0, breathOffset),
            child: Center(
              child: CustomPaint(
                size: const Size(220, 130),
                painter: _StormCloudPainter(
                  flashIntensity: _cloudFlashController.value,
                  errorFlashIntensity: _errorFlashController.value,
                  breathPhase: _cloudBreathController.value,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWordDisplay() {
    if (!_gameStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Get Ready!',
          style: GoogleFonts.fredoka(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: AppColors.electricBlue,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: AnimatedOpacity(
        opacity: _wordVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: Text(
          _currentWord.toUpperCase(),
          style: GoogleFonts.fredoka(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: AppColors.electricBlue,
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: AppColors.electricBlue.withValues(alpha: 0.6),
                blurRadius: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLetterTiles() {
    if (_scrambledLetters.isEmpty) return const SizedBox(height: 100);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: List.generate(_scrambledLetters.length, (i) {
          return _buildTile(i);
        }),
      ),
    );
  }

  Widget _buildTile(int index) {
    final letter = _scrambledLetters[index];
    final isCorrect = _tileCorrect[index];
    final isError = _errorTileIndex == index;
    final isChainTarget = _chainActive && isCorrect;

    Color bgColor;
    Color borderColor;
    Color textColor;
    List<BoxShadow> shadows = [];

    if (isCorrect) {
      bgColor = const Color(0xFF0A2A4A);
      borderColor = AppColors.electricBlue;
      textColor = AppColors.electricBlue;
      shadows = [
        BoxShadow(
          color: AppColors.electricBlue.withValues(alpha: 0.5),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ];
    } else if (isError) {
      bgColor = AppColors.error.withValues(alpha: 0.2);
      borderColor = AppColors.error;
      textColor = AppColors.error;
    } else {
      bgColor = const Color(0xFF1C1C2E);
      borderColor = const Color(0xFF3A3A5C);
      textColor = AppColors.secondaryText;
    }

    Widget tile = AnimatedContainer(
      key: _tileKeys[index],
      duration: const Duration(milliseconds: 250),
      width: 56,
      height: 64,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: shadows,
      ),
      child: Center(
        child: Text(
          letter.toUpperCase(),
          style: GoogleFonts.fredoka(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );

    // Error shake animation
    if (isError) {
      tile = AnimatedBuilder(
        animation: _errorController,
        builder: (context, child) {
          final shake =
              sin(_errorController.value * pi * 4) * 6 *
              (1 - _errorController.value);
          return Transform.translate(
            offset: Offset(shake, 0),
            child: child,
          );
        },
        child: tile,
      );
    }

    // Chain glow pulse
    if (isChainTarget) {
      tile = AnimatedBuilder(
        animation: _chainController,
        builder: (context, child) {
          final pulse = sin(_chainController.value * pi * 3) * 0.3 + 0.7;
          return Opacity(opacity: pulse, child: child);
        },
        child: tile,
      );
    }

    return GestureDetector(
      onTap: isCorrect ? null : () => _onTileTap(index),
      child: tile,
    );
  }

  // ── Position helpers ────────────────────────────────────────────────

  Offset _getCloudBottomCenter() {
    final cloudBox =
        _cloudKey.currentContext?.findRenderObject() as RenderBox?;
    if (cloudBox == null) return const Offset(200, 180);
    final pos = cloudBox.localToGlobal(Offset.zero);
    return Offset(pos.dx + cloudBox.size.width / 2,
        pos.dy + cloudBox.size.height - 10);
  }

  Offset _getTileCenter(int tileIndex) {
    if (tileIndex >= _tileKeys.length) return const Offset(200, 500);
    final box =
        _tileKeys[tileIndex].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(200, 500);
    final pos = box.localToGlobal(Offset.zero);
    return Offset(pos.dx + box.size.width / 2, pos.dy + box.size.height / 2);
  }

  List<Offset> _getAllTilePositions() {
    final positions = <Offset>[];
    // Return correct tiles in order
    for (int ci = 0; ci < _correctOrderToTile.length; ci++) {
      final ti = _correctOrderToTile[ci];
      positions.add(_getTileCenter(ti));
    }
    return positions;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain data
// ─────────────────────────────────────────────────────────────────────────────

class _RainDrop {
  double x;
  double y;
  final double speed;
  final double length;
  final double opacity;

  _RainDrop({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.opacity,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Storm Cloud Painter
// ─────────────────────────────────────────────────────────────────────────────

class _StormCloudPainter extends CustomPainter {
  final double flashIntensity;
  final double errorFlashIntensity;
  final double breathPhase;

  _StormCloudPainter({
    required this.flashIntensity,
    this.errorFlashIntensity = 0.0,
    required this.breathPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 5;

    // ── Back cloud layers (darker, depth) ───────────────────────────
    _drawCloudBlob(canvas, cx - 50, cy + 10, 55, 38,
        _lerpFlash(const Color(0xFF1A1030), flashIntensity));
    _drawCloudBlob(canvas, cx + 55, cy + 8, 50, 35,
        _lerpFlash(const Color(0xFF1C1235), flashIntensity));
    _drawCloudBlob(canvas, cx, cy + 15, 65, 40,
        _lerpFlash(const Color(0xFF1E1438), flashIntensity));

    // ── Mid layer (purple-gray) ─────────────────────────────────────
    _drawCloudBlob(canvas, cx - 40, cy, 60, 40,
        _lerpFlash(const Color(0xFF2A1E50), flashIntensity));
    _drawCloudBlob(canvas, cx + 40, cy - 2, 55, 38,
        _lerpFlash(const Color(0xFF281C4D), flashIntensity));

    // ── Main body (front, lighter) ──────────────────────────────────
    _drawCloudBlob(canvas, cx, cy - 5, 70, 45,
        _lerpFlash(const Color(0xFF3A2870), flashIntensity));
    _drawCloudBlob(canvas, cx - 30, cy - 10, 50, 35,
        _lerpFlash(const Color(0xFF352565), flashIntensity));
    _drawCloudBlob(canvas, cx + 30, cy - 8, 48, 33,
        _lerpFlash(const Color(0xFF382768), flashIntensity));

    // ── Top highlight puffs ─────────────────────────────────────────
    _drawCloudBlob(canvas, cx - 15, cy - 25, 35, 22,
        _lerpFlash(const Color(0xFF4A3888), flashIntensity));
    _drawCloudBlob(canvas, cx + 20, cy - 22, 30, 20,
        _lerpFlash(const Color(0xFF483685), flashIntensity));
    _drawCloudBlob(canvas, cx, cy - 30, 28, 18,
        _lerpFlash(const Color(0xFF5040A0), flashIntensity));

    // ── Internal glow when flashing ─────────────────────────────────
    if (flashIntensity > 0.01) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFFEE88)
            .withValues(alpha: flashIntensity * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 80, height: 50),
        glowPaint,
      );
    }

    // ── Red error glow when wrong tap ────────────────────────────────
    if (errorFlashIntensity > 0.01) {
      final errGlow = Paint()
        ..color = const Color(0xFFFF2244)
            .withValues(alpha: errorFlashIntensity * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 100, height: 60),
        errGlow,
      );
      // Inner hot core
      final errCore = Paint()
        ..color = const Color(0xFFFF6644)
            .withValues(alpha: errorFlashIntensity * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 50, height: 30),
        errCore,
      );
    }

    // ── Face ────────────────────────────────────────────────────────
    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = const Color(0xFF1A1030);

    // Left eye
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx - 18, cy - 6), width: 16, height: 18),
        eyePaint);
    canvas.drawCircle(Offset(cx - 17, cy - 4), 5, pupilPaint);

    // Right eye
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + 18, cy - 6), width: 16, height: 18),
        eyePaint);
    canvas.drawCircle(Offset(cx + 19, cy - 4), 5, pupilPaint);

    // Eye shines
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - 15, cy - 8), 2.5, shinePaint);
    canvas.drawCircle(Offset(cx + 21, cy - 8), 2.5, shinePaint);

    // Mouth — determined grin
    final mouthPaint = Paint()
      ..color = const Color(0xFF1A1030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path()
      ..moveTo(cx - 10, cy + 10)
      ..quadraticBezierTo(cx, cy + 18, cx + 10, cy + 10);
    canvas.drawPath(mouthPath, mouthPaint);

    // ── Mini rain drops below cloud ─────────────────────────────────
    final dropPaint = Paint()
      ..color = const Color(0xFF6B7BFF).withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final dropPositions = [
      Offset(cx - 35, cy + 42),
      Offset(cx - 15, cy + 48),
      Offset(cx + 10, cy + 45),
      Offset(cx + 30, cy + 40),
      Offset(cx - 25, cy + 55),
      Offset(cx + 5, cy + 58),
      Offset(cx + 25, cy + 53),
    ];

    for (final dp in dropPositions) {
      final yOff = (breathPhase * 8) % 12;
      final p = Offset(dp.dx, dp.dy + yOff);
      canvas.drawLine(p, Offset(p.dx - 1, p.dy + 6), dropPaint);
    }
  }

  void _drawCloudBlob(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    final paint = Paint()
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: w, height: h),
      paint,
    );
  }

  Color _lerpFlash(Color base, double flash) {
    Color result = Color.lerp(base, const Color(0xFFA090FF), flash * 0.6)!;
    if (errorFlashIntensity > 0.01) {
      result = Color.lerp(
          result, const Color(0xFFFF3344), errorFlashIntensity * 0.7)!;
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _StormCloudPainter old) =>
      old.flashIntensity != flashIntensity ||
      old.errorFlashIntensity != errorFlashIntensity ||
      old.breathPhase != breathPhase;
}

// ─────────────────────────────────────────────────────────────────────────────
// Lightning Bolt Painter (cloud to tile)
// ─────────────────────────────────────────────────────────────────────────────

class _LightningBoltPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double opacity;
  final Random rng;

  // Cache the bolt segments so they don't jitter
  late final List<Offset> _mainBolt;
  late final List<List<Offset>> _branches;

  _LightningBoltPainter({
    required this.from,
    required this.to,
    required this.opacity,
    required this.rng,
  }) {
    _mainBolt = _generateBoltPath(from, to, 8);
    _branches = _generateBranches(_mainBolt, 3);
  }

  List<Offset> _generateBoltPath(Offset start, Offset end, int segments) {
    final points = <Offset>[start];
    final dx = (end.dx - start.dx) / segments;
    final dy = (end.dy - start.dy) / segments;

    for (int i = 1; i < segments; i++) {
      final jitterX = (rng.nextDouble() - 0.5) * 30;
      final jitterY = (rng.nextDouble() - 0.5) * 10;
      points.add(Offset(
        start.dx + dx * i + jitterX,
        start.dy + dy * i + jitterY,
      ));
    }
    points.add(end);
    return points;
  }

  List<List<Offset>> _generateBranches(
      List<Offset> mainPath, int branchCount) {
    final branches = <List<Offset>>[];
    for (int b = 0; b < branchCount; b++) {
      final startIdx = 1 + rng.nextInt(mainPath.length - 2);
      final branchStart = mainPath[startIdx];
      final angle = (rng.nextDouble() - 0.5) * 1.2;
      final length = 20 + rng.nextDouble() * 30;
      final branchEnd = Offset(
        branchStart.dx + cos(angle) * length,
        branchStart.dy + sin(angle) * length + 15,
      );
      branches.add(_generateBoltPath(branchStart, branchEnd, 3));
    }
    return branches;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity < 0.01) return;

    // Outer glow
    final glowPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: opacity * 0.3)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Core bolt
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Blue mid
    final midPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: opacity * 0.8)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _drawBoltPath(canvas, _mainBolt, glowPaint);
    _drawBoltPath(canvas, _mainBolt, midPaint);
    _drawBoltPath(canvas, _mainBolt, corePaint);

    // Branches (thinner)
    final branchGlow = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: opacity * 0.2)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final branchCore = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.7)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final branch in _branches) {
      _drawBoltPath(canvas, branch, branchGlow);
      _drawBoltPath(canvas, branch, branchCore);
    }

    // Impact flash at target
    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(to, 15, flashPaint);
  }

  void _drawBoltPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LightningBoltPainter old) =>
      old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// Chain Lightning Painter (connects all correct tiles)
// ─────────────────────────────────────────────────────────────────────────────

class _ChainLightningPainter extends CustomPainter {
  final List<Offset> tilePositions;
  final double progress;
  final Random rng;

  _ChainLightningPainter({
    required this.tilePositions,
    required this.progress,
    required this.rng,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tilePositions.length < 2) return;

    final visibleCount =
        (tilePositions.length * progress).ceil().clamp(0, tilePositions.length);

    final glowPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.3)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < visibleCount - 1; i++) {
      final from = tilePositions[i];
      final to = tilePositions[i + 1];

      // Small jitter for chain segments
      final midX = (from.dx + to.dx) / 2 + (rng.nextDouble() - 0.5) * 12;
      final midY = (from.dy + to.dy) / 2 + (rng.nextDouble() - 0.5) * 8;
      final mid = Offset(midX, midY);

      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(to.dx, to.dy);

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
    }

    // Node flashes at each tile
    final nodePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    for (int i = 0; i < visibleCount; i++) {
      canvas.drawCircle(tilePositions[i], 8, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChainLightningPainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain Painter
// ─────────────────────────────────────────────────────────────────────────────

class _RainPainter extends CustomPainter {
  final List<_RainDrop> drops;

  _RainPainter({required this.drops});

  @override
  void paint(Canvas canvas, Size size) {
    for (final drop in drops) {
      final paint = Paint()
        ..color = const Color(0xFF5566BB).withValues(alpha: drop.opacity)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;

      final x = drop.x * size.width;
      final y = drop.y * size.height;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - 1, y + drop.length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Lightning Painter
// ─────────────────────────────────────────────────────────────────────────────

class _BgLightningPainter extends CustomPainter {
  final double x;
  final double opacity;
  final Random rng;

  _BgLightningPainter({
    required this.x,
    required this.opacity,
    required this.rng,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity < 0.01) return;

    final startX = x * size.width;
    const startY = 0.0;
    final endY = size.height * 0.4;

    final paint = Paint()
      ..color = const Color(0xFF8888FF).withValues(alpha: opacity)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path()..moveTo(startX, startY);
    const segments = 6;
    final segH = endY / segments;

    for (int i = 1; i <= segments; i++) {
      final jx = (rng.nextDouble() - 0.5) * 20;
      path.lineTo(startX + jx, startY + segH * i);
    }

    canvas.drawPath(path, paint);

    // Dim glow
    final glowPaint = Paint()
      ..color = const Color(0xFF9999FF).withValues(alpha: opacity * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(Offset(startX, endY * 0.3), 40, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BgLightningPainter old) =>
      old.opacity != opacity;
}

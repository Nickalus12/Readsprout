import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';
import '../models/progress.dart';
import '../models/word.dart';
import '../data/phrase_templates.dart';
import '../services/audio_service.dart';
import '../services/progress_service.dart';
import '../widgets/animated_glow_border.dart';
import '../widgets/letter_tile.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/floating_hearts_bg.dart';

class GameScreen extends StatefulWidget {
  final int level;
  final int tier;
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;

  const GameScreen({
    super.key,
    required this.level,
    required this.progressService,
    required this.audioService,
    this.tier = 1,
    this.playerName = '',
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late List<Word> _words;
  int _currentWordIndex = 0;
  int _currentLetterIndex = 0;
  int _mistakesThisWord = 0;
  int _perfectWords = 0; // Track words with zero mistakes
  bool _showingCelebration = false;
  bool _levelComplete = false;
  bool _shaking = false;
  bool _isPlayingAudio = false;
  bool _savingProgress = false;
  String _levelCompletePhrase = '';

  // Track which letters have been correctly typed
  final List<bool> _revealedLetters = [];

  // ── Tier-specific state ──────────────────────────────────────────

  /// Tier 2 (Adventurer): consecutive wrong guesses at the current position.
  int _wrongCountAtPosition = 0;

  /// Tier 2 (Adventurer): the letter key currently being nudged (pulsed).
  String? _nudgeKey;

  /// Tier 3 (Champion): consecutive words with 0 mistakes.
  int _perfectStreak = 0;

  /// Whether the current champion word was "not passed" (2+ mistakes).
  bool _championWordFailed = false;

  // ── Animation controllers ────────────────────────────────────────

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late ConfettiController _confettiController;
  late ConfettiController _levelConfettiController;

  /// Tier 2: nudge pulse animation for the correct key after 2 wrong guesses.
  late AnimationController _nudgeController;

  /// Tier 3: perfect streak badge scale-pop.
  late AnimationController _streakPopController;

  /// Extra golden confetti controller for champion perfect words.
  late ConfettiController _goldenConfettiController;

  // Focus node for keyboard input
  final FocusNode _focusNode = FocusNode();

  // ── Convenience getters ──────────────────────────────────────────

  Word get _currentWord => _words[_currentWordIndex];
  String get _targetText => _currentWord.text.toLowerCase();
  bool get _isLastWord => _currentWordIndex >= _words.length - 1;
  WordTier get _wordTier => WordTier.fromValue(widget.tier) ?? WordTier.explorer;
  bool get _isExplorer => widget.tier == 1;
  bool get _isAdventurer => widget.tier == 2;
  bool get _isChampion => widget.tier == 3;

  GlowState get _screenGlowState {
    if (_levelComplete) return GlowState.celebrate;
    if (_showingCelebration) return GlowState.correct;
    if (_shaking) return GlowState.error;
    if (_isPlayingAudio) return GlowState.listening;
    return GlowState.idle;
  }

  @override
  void initState() {
    super.initState();

    // Load words for this level, shuffle for variety
    _words = List.from(DolchWords.wordsForLevel(widget.level))..shuffle();
    _initRevealedLetters();

    // Shake animation for wrong input
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reset();
        setState(() => _shaking = false);
      }
    });

    // Nudge controller (Tier 2) — pulse correct key for ~1 second
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _nudgeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _nudgeKey = null);
        _nudgeController.reset();
      }
    });

    // Streak pop controller (Tier 3) — quick scale pop
    _streakPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Confetti
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 1));
    _levelConfettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _goldenConfettiController =
        ConfettiController(duration: const Duration(milliseconds: 800));

    // Announce the first word after a brief delay
    Future.delayed(const Duration(milliseconds: 600), _announceCurrentWord);
  }

  void _initRevealedLetters() {
    _revealedLetters.clear();
    _revealedLetters.addAll(List.filled(_targetText.length, false));
    _wrongCountAtPosition = 0;
    _nudgeKey = null;
    _championWordFailed = false;
    _mistakesThisWord = 0;

    if (_isAdventurer && _targetText.isNotEmpty) {
      // Tier 2: pre-reveal first letter, start typing at index 1
      _revealedLetters[0] = true;
      _currentLetterIndex = 1;
    } else {
      _currentLetterIndex = 0;
    }
  }

  Future<void> _announceCurrentWord() async {
    setState(() => _isPlayingAudio = true);
    final ok = await widget.audioService.playWord(_currentWord.text);
    if (mounted) {
      setState(() => _isPlayingAudio = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio not available \u2014 tap "Hear Word" to try again'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _onKeyPressed(String key) {
    if (_showingCelebration || _levelComplete) return;

    final expectedLetter = _targetText[_currentLetterIndex];

    if (key.toLowerCase() == expectedLetter.toLowerCase()) {
      // Correct letter!
      setState(() {
        _revealedLetters[_currentLetterIndex] = true;
        _currentLetterIndex++;
        _wrongCountAtPosition = 0; // reset for next position
        _nudgeKey = null;
      });

      // Play the phonetic sound for this letter
      widget.audioService.playLetter(expectedLetter);

      // Check if word is complete — delay so last letter sound plays
      if (_currentLetterIndex >= _targetText.length) {
        Future.delayed(const Duration(milliseconds: 500), _onWordComplete);
      }
    } else {
      // Wrong letter — shake and retry
      _onWrongLetter();
    }
  }

  void _onWrongLetter() {
    setState(() {
      _shaking = true;
      _mistakesThisWord++;
      _wrongCountAtPosition++;
    });
    _shakeController.forward();
    widget.audioService.playError();
    if (Platform.isAndroid || Platform.isIOS) HapticFeedback.mediumImpact();

    // Tier 2 nudge: after 2 consecutive wrong guesses at same position,
    // briefly pulse the correct key.
    if (_isAdventurer && _wrongCountAtPosition >= 2) {
      final expected = _targetText[_currentLetterIndex];
      setState(() => _nudgeKey = expected);
      _nudgeController.forward(from: 0);
    }
  }

  Future<void> _onWordComplete() async {
    // Track perfect words
    if (_mistakesThisWord == 0) _perfectWords++;

    // Champion quality gate
    final wordPassedChampion = !_isChampion || _mistakesThisWord <= 1;

    // Champion perfect streak
    if (_isChampion) {
      if (_mistakesThisWord == 0) {
        _perfectStreak++;
        _streakPopController.forward(from: 0);
      } else {
        _perfectStreak = 0;
      }
      _championWordFailed = !wordPassedChampion;
    }

    // Save progress BEFORE showing celebration UI to prevent data loss on back-nav
    setState(() => _savingProgress = true);
    final wasTierComplete = await widget.progressService.recordTierWordComplete(
      level: widget.level,
      tier: widget.tier,
      wordText: _currentWord.text,
      mistakes: _mistakesThisWord,
    );
    if (mounted) setState(() => _savingProgress = false);

    // Play success chime
    widget.audioService.playSuccess();

    // Tier-aware confetti
    if (_isChampion && _mistakesThisWord == 0) {
      // Extra golden burst for perfect champion words
      _goldenConfettiController.play();
    }
    _confettiController.play();

    if (Platform.isAndroid || Platform.isIOS) HapticFeedback.lightImpact();

    setState(() => _showingCelebration = true);

    // Celebrate — give the child time to enjoy it
    await Future.delayed(const Duration(milliseconds: 2500));

    if (_isLastWord || wasTierComplete) {
      // Level/tier complete!
      _levelConfettiController.play();
      widget.audioService.playLevelCompleteEffect();
      Future.delayed(const Duration(milliseconds: 500), () {
        widget.audioService.playLevelComplete(widget.playerName);
      });
      setState(() {
        _showingCelebration = false;
        _levelComplete = true;
        _levelCompletePhrase =
            PhraseTemplates.randomLevelComplete(widget.playerName);
      });
    } else {
      // Next word
      setState(() {
        _showingCelebration = false;
        _currentWordIndex++;
        _initRevealedLetters();
      });

      Future.delayed(
          const Duration(milliseconds: 400), _announceCurrentWord);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _nudgeController.dispose();
    _streakPopController.dispose();
    _confettiController.stop();
    _confettiController.dispose();
    _levelConfettiController.stop();
    _levelConfettiController.dispose();
    _goldenConfettiController.stop();
    _goldenConfettiController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientIndex =
        (widget.level - 1) % AppColors.levelGradients.length;
    final levelColors = AppColors.levelGradients[gradientIndex];

    return Scaffold(
      body: AnimatedGlowBorder(
        state: _screenGlowState,
        borderRadius: 0,
        strokeWidth: 2,
        glowRadius: 18,
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent && event.character != null) {
              final char = event.character!;
              if (RegExp(r'^[a-zA-Z]$').hasMatch(char)) {
                _onKeyPressed(char);
              }
            }
          },
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Stack(
              children: [
                // ── Background gradient ──────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.2,
                      colors: [
                        levelColors.first.withValues(alpha: 0.12),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),

                // ── Floating hearts (subtle in game) ─────
                const Positioned.fill(
                  child: Opacity(
                    opacity: 0.4,
                    child: FloatingHeartsBackground(
                      cloudZoneHeight: 0.10,
                    ),
                  ),
                ),

                // ── Main content ─────────────────────────
                SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(levelColors),
                      if (_levelComplete)
                        Expanded(child: _buildLevelComplete())
                      else ...[
                        const SizedBox(height: 8),
                        // Progress dots
                        _buildProgressDots(levelColors),
                        const Spacer(flex: 2),

                        // Champion: "Keep practicing!" message for failed words
                        if (_isChampion && _championWordFailed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Keep practicing!',
                              style: GoogleFonts.fredoka(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),

                        // Hear word button
                        _buildHearButton(),
                        const SizedBox(height: 28),

                        // Letter tiles
                        _buildLetterTiles(),
                        const SizedBox(height: 32),

                        // On-screen keyboard
                        _buildKeyboard(levelColors),
                        const Spacer(flex: 1),
                      ],
                    ],
                  ),
                ),

                // ── Champion perfect streak badge ─────────
                if (_isChampion && _perfectStreak > 0 && !_levelComplete)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    right: 8,
                    child: _buildStreakBadge(),
                  ),

                // ── Celebration overlay ───────────────────
                if (_showingCelebration)
                  CelebrationOverlay(
                    word: _currentWord.text,
                    playerName: widget.playerName,
                  ),

                // ── Standard confetti ─────────────────────
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirection: pi / 2,
                    maxBlastForce: _isAdventurer ? 7 : 5,
                    minBlastForce: 2,
                    emissionFrequency: _isAdventurer ? 0.2 : 0.3,
                    numberOfParticles: _isChampion ? 15 : (_isAdventurer ? 12 : 8),
                    gravity: 0.3,
                    colors: AppColors.confettiColors,
                  ),
                ),

                // ── Level complete confetti ───────────────
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _levelConfettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    maxBlastForce: _isChampion ? 20 : 15,
                    minBlastForce: 5,
                    emissionFrequency: _isChampion ? 0.05 : 0.1,
                    numberOfParticles: _isChampion ? 35 : 20,
                    gravity: 0.2,
                    colors: AppColors.confettiColors,
                  ),
                ),

                // ── Champion golden confetti (perfect word) ───
                if (_isChampion)
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      confettiController: _goldenConfettiController,
                      blastDirectionality: BlastDirectionality.explosive,
                      maxBlastForce: 12,
                      minBlastForce: 4,
                      emissionFrequency: 0.15,
                      numberOfParticles: 12,
                      gravity: 0.25,
                      colors: const [
                        AppColors.starGold,
                        Color(0xFFFFF176), // light gold
                        Color(0xFFFFE082), // amber
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────

  Widget _buildHeader(List<Color> levelColors) {
    final zone = DolchWords.zoneForLevel(widget.level);
    final tierColor = _wordTier.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _savingProgress ? null : () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: _savingProgress
                  ? AppColors.secondaryText
                  : AppColors.primaryText,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level name
                Text(
                  DolchWords.levelName(widget.level),
                  style: GoogleFonts.fredoka(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Zone name + tier badge
                Row(
                  children: [
                    Text(
                      '${zone.icon} ${zone.name}',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_wordTier.icon} ${_wordTier.displayName}',
                      style: GoogleFonts.fredoka(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tierColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Word counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              '${_currentWordIndex + 1}/${_words.length}',
              style: GoogleFonts.fredoka(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress Dots ───────────────────────────────────────────────

  Widget _buildProgressDots(List<Color> levelColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_words.length, (i) {
          final isDone = i < _currentWordIndex;
          final isCurrent = i == _currentWordIndex;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isCurrent ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isDone
                  ? AppColors.success
                  : isCurrent
                      ? levelColors.first
                      : AppColors.surface,
              border: Border.all(
                color: isDone
                    ? AppColors.success.withValues(alpha: 0.5)
                    : isCurrent
                        ? levelColors.first.withValues(alpha: 0.5)
                        : AppColors.border.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: (isDone || isCurrent)
                  ? [
                      BoxShadow(
                        color: (isDone
                                ? AppColors.success
                                : levelColors.first)
                            .withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  // ── Hear Word Button ────────────────────────────────────────────

  Widget _buildHearButton() {
    return GestureDetector(
      onTap: _announceCurrentWord,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: _isPlayingAudio
              ? AppColors.electricBlue.withValues(alpha: 0.15)
              : AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isPlayingAudio
                ? AppColors.electricBlue.withValues(alpha: 0.4)
                : AppColors.border.withValues(alpha: 0.5),
          ),
          boxShadow: _isPlayingAudio
              ? [
                  BoxShadow(
                    color:
                        AppColors.electricBlue.withValues(alpha: 0.15),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlayingAudio
                  ? Icons.hearing_rounded
                  : Icons.volume_up_rounded,
              color: AppColors.electricBlue,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              _isPlayingAudio ? 'Listen...' : 'Hear Word',
              style: GoogleFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.electricBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Letter Tiles ────────────────────────────────────────────────

  Widget _buildLetterTiles() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        double offsetX = 0;
        if (_shaking) {
          offsetX = sin(_shakeAnimation.value * pi * 4) * 12;
        }
        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: child,
        );
      },
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: List.generate(_targetText.length, (i) {
          // Tier 2: first letter is pre-revealed with silver tint
          final isPreRevealed = _isAdventurer && i == 0;
          return LetterTile(
            letter: _targetText[i],
            isRevealed: _revealedLetters[i],
            isActive: i == _currentLetterIndex && !_showingCelebration,
            isError: _shaking && i == _currentLetterIndex,
            revealedColor: isPreRevealed && !(_currentLetterIndex > i && i > 0)
                ? AppColors.silver
                : null,
          );
        }),
      ),
    );
  }

  // ── On-Screen Keyboard ──────────────────────────────────────────

  Widget _buildKeyboard(List<Color> levelColors) {
    const rows = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((letter) {
                // Tier 1: highlight expected letter
                final isExpected = _isExplorer &&
                    !_showingCelebration &&
                    !_levelComplete &&
                    _currentLetterIndex < _targetText.length &&
                    letter == _targetText[_currentLetterIndex];

                // Tier 2: nudge pulse on the correct key after 2 wrong
                final isNudging = _isAdventurer && _nudgeKey == letter;

                return _KeyboardKey(
                  letter: letter,
                  isExpected: isExpected,
                  isNudging: isNudging,
                  nudgeController: _nudgeController,
                  accentColor: levelColors.first,
                  onTap: () => _onKeyPressed(letter),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Champion Perfect Streak Badge ──────────────────────────────

  Widget _buildStreakBadge() {
    final isGold = _perfectStreak >= 5;
    final flameColor = isGold ? AppColors.starGold : AppColors.error;

    return AnimatedBuilder(
      animation: _streakPopController,
      builder: (context, child) {
        // Scale pop: 1.0 -> 1.3 -> 1.0
        final t = _streakPopController.value;
        final scale = 1.0 + 0.3 * sin(t * pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: flameColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: flameColor.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: flameColor.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: flameColor,
            ),
            const SizedBox(width: 4),
            Text(
              '$_perfectStreak',
              style: GoogleFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: flameColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Level Complete ──────────────────────────────────────────────

  Widget _buildLevelComplete() {
    final tierColor = _wordTier.color;
    final tierLabel = _isChampion
        ? 'CHAMPION!'
        : _isAdventurer
            ? 'Tier Complete!'
            : 'Level Complete!';
    final praiseColor = _isChampion
        ? AppColors.starGold
        : _isAdventurer
            ? AppColors.silver
            : AppColors.success;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star with glow (tier-colored)
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: tierColor.withValues(alpha: 0.5),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Icon(
                Icons.star_rounded,
                color: tierColor,
                size: 80,
              ),
            ).animate().scale(
                  begin: const Offset(0.3, 0.3),
                  end: const Offset(1.0, 1.0),
                  curve: Curves.elasticOut,
                  duration: 800.ms,
                ),
            const SizedBox(height: 20),

            Text(
              tierLabel,
              style: GoogleFonts.fredoka(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                shadows: [
                  Shadow(
                    color: tierColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3, end: 0),

            const SizedBox(height: 8),

            // Personalized phrase
            Text(
              _levelCompletePhrase.isNotEmpty
                  ? _levelCompletePhrase
                  : 'Amazing job!',
              style: GoogleFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: praiseColor,
                shadows: [
                  Shadow(
                    color: praiseColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 16),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatChip(
                  icon: Icons.check_circle_rounded,
                  value: '${_words.length}',
                  label: 'Words',
                  color: AppColors.success,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.star_rounded,
                  value: '$_perfectWords',
                  label: 'Perfect',
                  color: AppColors.starGold,
                ),
                if (_isChampion && _perfectStreak > 0) ...[
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.local_fire_department_rounded,
                    value: '$_perfectStreak',
                    label: 'Streak',
                    color: _perfectStreak >= 5
                        ? AppColors.starGold
                        : AppColors.error,
                  ),
                ],
              ],
            ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 32),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundButton(
                  label: 'Replay',
                  icon: Icons.replay_rounded,
                  color: AppColors.secondaryText,
                  onTap: () {
                    setState(() {
                      _words.shuffle();
                      _currentWordIndex = 0;
                      _perfectWords = 0;
                      _perfectStreak = 0;
                      _initRevealedLetters();
                      _levelComplete = false;
                    });
                    Future.delayed(const Duration(milliseconds: 400),
                        _announceCurrentWord);
                  },
                ),
                const SizedBox(width: 24),
                if (widget.level < DolchWords.totalLevels)
                  _RoundButton(
                    label: 'Next',
                    icon: Icons.arrow_forward_rounded,
                    color: AppColors.success,
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => GameScreen(
                            level: widget.level + 1,
                            tier: widget.tier,
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                          ),
                          transitionsBuilder: (_, animation, __, child) {
                            return FadeTransition(
                              opacity: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeInOut,
                              ),
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                  ),
              ],
            ).animate().fadeIn(delay: 700.ms),
          ],
        ),
      ),
    );
  }
}

// ── Keyboard Key ────────────────────────────────────────────────────

class _KeyboardKey extends StatefulWidget {
  final String letter;
  final bool isExpected;
  final bool isNudging;
  final AnimationController? nudgeController;
  final Color accentColor;
  final VoidCallback onTap;

  const _KeyboardKey({
    required this.letter,
    required this.isExpected,
    this.isNudging = false,
    this.nudgeController,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_KeyboardKey> createState() => _KeyboardKeyState();
}

class _KeyboardKeyState extends State<_KeyboardKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // If this key is being nudged (Tier 2), wrap in animated builder
    if (widget.isNudging && widget.nudgeController != null) {
      return AnimatedBuilder(
        animation: widget.nudgeController!,
        builder: (context, child) {
          // Pulse: scale 1.0 -> 1.1 -> 1.0 with blue glow
          final t = widget.nudgeController!.value;
          final pulse = 1.0 + 0.1 * sin(t * pi * 2);
          final glowAlpha = 0.4 * sin(t * pi);
          return Transform.scale(
            scale: pulse,
            child: _buildKey(
              nudgeGlowAlpha: glowAlpha.clamp(0.0, 1.0),
            ),
          );
        },
      );
    }
    return _buildKey();
  }

  Widget _buildKey({double nudgeGlowAlpha = 0.0}) {
    final showHighlight = widget.isExpected;
    final showNudge = nudgeGlowAlpha > 0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 34,
        height: 46,
        transform: Matrix4.identity()
          ..setEntry(0, 0, _pressed ? 0.92 : 1.0)
          ..setEntry(1, 1, _pressed ? 0.92 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: showHighlight
              ? AppColors.electricBlue.withValues(alpha: 0.2)
              : showNudge
                  ? AppColors.electricBlue.withValues(alpha: 0.15)
                  : _pressed
                      ? AppColors.surface.withValues(alpha: 0.5)
                      : AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: showHighlight
                ? AppColors.electricBlue
                : showNudge
                    ? AppColors.electricBlue.withValues(alpha: 0.6)
                    : AppColors.border.withValues(alpha: 0.5),
            width: showHighlight ? 1.5 : 1,
          ),
          boxShadow: [
            if (showHighlight)
              BoxShadow(
                color: AppColors.electricBlue.withValues(alpha: 0.25),
                blurRadius: 8,
              ),
            if (showNudge)
              BoxShadow(
                color: AppColors.electricBlue.withValues(alpha: nudgeGlowAlpha * 0.4),
                blurRadius: 10,
              ),
          ],
        ),
        child: Center(
          child: Text(
            widget.letter,
            style: GoogleFonts.fredoka(
              fontSize: 18,
              fontWeight:
                  (showHighlight || showNudge) ? FontWeight.w600 : FontWeight.w400,
              color: (showHighlight || showNudge)
                  ? AppColors.electricBlue
                  : AppColors.primaryText,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Round Button ────────────────────────────────────────────────────

class _RoundButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.1),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
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

// ── Stat Chip ───────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

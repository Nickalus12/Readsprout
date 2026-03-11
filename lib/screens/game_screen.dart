import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';
import '../models/progress.dart';
import '../models/word.dart';
import '../data/music_layers.dart';
import '../data/phrase_templates.dart';
import '../services/audio_service.dart';
import '../models/player_profile.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/stats_service.dart';
import '../services/streak_service.dart';
import '../services/adaptive_music_service.dart';
import '../services/avatar_personality_service.dart';
import '../services/review_service.dart';
import '../services/adaptive_difficulty_service.dart';
import '../data/sticker_definitions.dart';
import '../widgets/animated_glow_border.dart';
import '../widgets/letter_tile.dart';
import '../widgets/letter_tracing_canvas.dart';
import '../data/letter_paths.dart';
import '../utils/haptics.dart';
import '../avatar/avatar_widget.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/zone_background.dart';

class GameScreen extends StatefulWidget {
  final int level;
  final int tier;
  final ProgressService progressService;
  final AudioService audioService;
  final ProfileService? profileService;
  final StatsService? statsService;
  final StreakService? streakService;
  final AvatarPersonalityService? personalityService;
  final ReviewService? reviewService;
  final AdaptiveDifficultyService? adaptiveDifficultyService;
  final AdaptiveMusicService? musicService;
  final String playerName;
  final String profileId;

  const GameScreen({
    super.key,
    required this.level,
    required this.progressService,
    required this.audioService,
    this.profileService,
    this.statsService,
    this.streakService,
    this.personalityService,
    this.reviewService,
    this.adaptiveDifficultyService,
    this.musicService,
    this.tier = 1,
    this.playerName = '',
    this.profileId = '',
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

  // ── In-level streak (all tiers) ────────────────────────────────
  /// Consecutive correct words within this level session.
  int _inLevelStreak = 0;

  // ── Progressive hints state ────────────────────────────────────
  /// Total wrong taps on the current word (resets per word).
  int _totalWrongTapsThisWord = 0;

  /// Whether the correct letter is being revealed (3rd wrong tap hint).
  bool _hintRevealing = false;

  // ── Zone encouragement state ─────────────────────────────────
  /// Whether a zone streak message is being displayed.
  bool _showStreakMessage = false;
  String _streakMessageText = '';
  String _zoneEncouragement = '';

  // ── Finger Spell (letter tracing) state ──────────────────────
  /// Whether letter tracing is active for the current word.
  bool _tracingActive = false;

  /// Index of the letter currently being traced (within the word).
  int _tracingLetterIndex = 0;

  /// Maximum number of letters to trace per word (caps long words).
  static const int _maxTracingLetters = 3;

  /// Random instance for tracing probability.
  final Random _tracingRandom = Random();

  // ── Zone info cache ────────────────────────────────────────────
  late final int _zoneIndex;
  late final String _zoneKey;

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

  // Avatar expression controller for gameplay reactions
  final AvatarController _avatarController = AvatarController();

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

  late final Stopwatch _sessionTimer;

  @override
  void initState() {
    super.initState();
    _sessionTimer = Stopwatch()..start();

    // Cache zone info
    _zoneIndex = zoneIndexForLevel(widget.level);
    final zone = DolchWords.zoneForLevel(widget.level);
    _zoneKey = PhraseTemplates.zoneKey(zone.name);

    // Start adaptive background music for this zone
    final musicZoneKey = MusicLayers.zoneKeyFromIndex(_zoneIndex);
    widget.musicService?.startZoneMusic(musicZoneKey);

    // Load words for this level, ordered by spaced repetition priority
    final levelWords = List<Word>.from(DolchWords.wordsForLevel(widget.level));
    if (widget.reviewService != null) {
      final wordTexts = levelWords.map((w) => w.text.toLowerCase()).toList();
      final ordered = widget.reviewService!.orderWordsForPractice(wordTexts);
      levelWords.sort((a, b) {
        final ai = ordered.indexOf(a.text.toLowerCase());
        final bi = ordered.indexOf(b.text.toLowerCase());
        return ai.compareTo(bi);
      });
    } else {
      levelWords.shuffle();
    }
    _words = levelWords;
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

    // Wire amplitude-based lip sync to avatar
    _avatarController.bindAmplitude(widget.audioService.mouthAmplitude);

    // Notify personality service of session start
    if (widget.profileId.isNotEmpty) {
      widget.personalityService?.onSessionStart(widget.profileId);
    }

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
    _totalWrongTapsThisWord = 0;
    _hintRevealing = false;

    if ((_isExplorer || _isAdventurer) && _targetText.isNotEmpty) {
      // Explorer & Adventurer: pre-reveal first letter, start typing at index 1
      _revealedLetters[0] = true;
      _currentLetterIndex = 1;

      // 1-letter words are already complete after pre-reveal
      if (_currentLetterIndex >= _targetText.length) {
        Future.delayed(const Duration(milliseconds: 800), _onWordComplete);
      }
    } else {
      _currentLetterIndex = 0;
    }

    // Decide whether to show tracing for this word
    _tracingActive = _shouldShowTracing();
    _tracingLetterIndex = _currentLetterIndex; // start tracing from first unrevealed letter
  }

  /// Returns true ~25% of the time to trigger letter tracing mode.
  /// Only triggers when the word has letters with defined stroke paths.
  bool _shouldShowTracing() {
    if (_targetText.isEmpty) return false;
    // Check at least one letter in the word has a tracing path
    final startIdx = (_isExplorer || _isAdventurer) ? 1 : 0;
    if (startIdx >= _targetText.length) return false;
    final hasPath = LetterPaths.strokeCount(_targetText[startIdx]) > 0;
    if (!hasPath) return false;
    return _tracingRandom.nextDouble() < 0.25;
  }

  /// Called when a letter tracing is completed successfully.
  void _onTracingLetterComplete() {
    if (!mounted) return;
    final letterIdx = _tracingLetterIndex;
    if (letterIdx >= _targetText.length) return;

    // Reveal the traced letter
    Haptics.correct();
    widget.audioService.playLetter(_targetText[letterIdx]);
    setState(() {
      _revealedLetters[letterIdx] = true;
      _tracingLetterIndex++;
      _currentLetterIndex = _tracingLetterIndex;
    });

    // Check how many letters have been traced — cap at _maxTracingLetters
    final tracedCount = letterIdx - ((_isExplorer || _isAdventurer) ? 1 : 0) + 1;

    if (_tracingLetterIndex >= _targetText.length) {
      // All letters traced — word complete
      Future.delayed(const Duration(milliseconds: 500), _onWordComplete);
    } else if (tracedCount >= _maxTracingLetters) {
      // Traced enough letters, switch to keyboard for the rest
      setState(() => _tracingActive = false);
    }
    // Otherwise continue tracing the next letter
  }

  Future<void> _announceCurrentWord() async {
    if (!mounted) return;
    widget.statsService?.recordWordHeard(_currentWord.text);
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
      Haptics.correct();
      widget.statsService?.recordLetterTap(key);
      widget.adaptiveDifficultyService?.recordEvent(correct: true);
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
      _onWrongLetter(key);
    }
  }

  void _onWrongLetter(String tappedKey) {
    // Track the wrong tap with what was expected
    final expected = _targetText[_currentLetterIndex];
    widget.statsService?.recordWrongTap(tappedKey, expected);
    widget.adaptiveDifficultyService?.recordEvent(correct: false);
    // Notify personality service of incorrect attempt
    if (widget.profileId.isNotEmpty) {
      widget.personalityService?.onWordIncorrect(widget.profileId);
    }
    // Dip music intensity on wrong answer
    widget.musicService?.onWrongAnswer();
    setState(() {
      _shaking = true;
      _mistakesThisWord++;
      _wrongCountAtPosition++;
      _totalWrongTapsThisWord++;
    });
    _shakeController.forward();
    widget.audioService.playError();
    Haptics.wrong();

    // ── Progressive hints (all tiers) ────────────────────────────
    // 1st wrong tap → avatar shows "thinking"
    // 2nd wrong tap → highlight correct next letter with subtle glow
    // 3rd wrong tap → briefly reveal the answer letter with bounce, then hide

    if (_totalWrongTapsThisWord == 1) {
      // 1st wrong: avatar thinks
      _avatarController.setExpression(AvatarExpression.thinking, duration: const Duration(seconds: 1));
    } else if (_totalWrongTapsThisWord == 2) {
      // 2nd wrong: avatar still thinking + highlight correct key on keyboard
      _avatarController.setExpression(AvatarExpression.thinking, duration: const Duration(seconds: 2));
      setState(() => _nudgeKey = expected);
      _nudgeController.forward(from: 0);
    } else if (_totalWrongTapsThisWord >= 3) {
      // 3rd+ wrong: briefly reveal the correct letter tile, then hide
      _avatarController.setExpression(AvatarExpression.surprised, duration: const Duration(milliseconds: 1500));
      setState(() {
        _hintRevealing = true;
        _nudgeKey = expected;
      });
      _nudgeController.forward(from: 0);
      // Auto-hide the hint after a brief moment
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _hintRevealing = false);
        }
      });
    }

    // Tier 2 nudge: after 2 consecutive wrong guesses at same position,
    // briefly pulse the correct key (redundant with progressive hints
    // but kept for tier-specific behavior compatibility).
    if (_isAdventurer && _wrongCountAtPosition >= 2 && _totalWrongTapsThisWord < 2) {
      setState(() => _nudgeKey = expected);
      _nudgeController.forward(from: 0);
    }
  }

  /// Play a zone-themed level-complete phrase.
  void _playZoneLevelComplete() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      widget.audioService.playLevelComplete(widget.playerName);
    });
  }

  /// Update ProfileService with word completion data, stickers, etc.
  void _updateProfile() {
    final ps = widget.profileService;
    if (ps == null) return;

    // Increment total words ever completed
    final newTotal = ps.totalWordsEverCompleted + 1;
    ps.setTotalWordsEverCompleted(newTotal);

    // Track words played today for chest unlock
    final todayCount = ps.wordsPlayedToday;
    ps.setWordsPlayedToday(todayCount + 1);

    // Check milestone stickers
    final milestoneId = StickerDefinitions.milestoneIdForWordCount(newTotal);
    if (milestoneId != null && !ps.hasSticker(milestoneId)) {
      final def = StickerDefinitions.byId(milestoneId);
      if (def != null) {
        ps.awardSticker(StickerRecord(
          stickerId: milestoneId,
          dateEarned: DateTime.now(),
          category: def.category.name,
          isNew: true,
        ));
      }
    }

    // Check perfect level sticker
    if (_mistakesThisWord == 0 && _isLastWord && _perfectWords == _words.length) {
      const perfectId = 'perfect_level';
      if (!ps.hasSticker(perfectId)) {
        final def = StickerDefinitions.byId(perfectId);
        if (def != null) {
          ps.awardSticker(StickerRecord(
            stickerId: perfectId,
            dateEarned: DateTime.now(),
            category: def.category.name,
            isNew: true,
          ));
        }
      }
    }

    // Check level completion sticker
    if (_isLastWord) {
      final levelStickerId = 'level_${widget.level}';
      if (!ps.hasSticker(levelStickerId)) {
        final def = StickerDefinitions.byId(levelStickerId);
        if (def != null) {
          ps.awardSticker(StickerRecord(
            stickerId: levelStickerId,
            dateEarned: DateTime.now(),
            category: def.category.name,
            isNew: true,
          ));
        }
      }
    }

    // Check evolution stickers
    final evoId = StickerDefinitions.evolutionIdForWordCount(newTotal);
    if (evoId != null && !ps.hasSticker(evoId)) {
      final def = StickerDefinitions.byId(evoId);
      if (def != null) {
        ps.awardSticker(StickerRecord(
          stickerId: evoId,
          dateEarned: DateTime.now(),
          category: def.category.name,
          isNew: true,
        ));
      }
    }
  }

  Future<void> _onWordComplete() async {
    // Record word stats
    widget.statsService?.recordWordCompleted(
      _words[_currentWordIndex].text,
      _mistakesThisWord,
    );

    // Record spaced repetition review
    widget.reviewService?.recordWordReview(
      _words[_currentWordIndex].text.toLowerCase(),
      _mistakesThisWord,
    );

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

    // Update profile: word count, play session, stickers
    _updateProfile();

    // Play success chime + avatar reaction
    widget.audioService.playSuccess();
    _avatarController.setExpression(AvatarExpression.excited, duration: const Duration(seconds: 2));

    // Bump adaptive music intensity on correct answer
    widget.musicService?.onCorrectAnswer();

    // Notify personality service of correct word
    if (widget.profileId.isNotEmpty) {
      widget.personalityService?.onWordCorrect(widget.profileId);
    }

    // ── In-level streak tracking ───────────────────────────────
    if (_mistakesThisWord == 0) {
      _inLevelStreak++;
    } else {
      widget.musicService?.onStreakBroken();
      _inLevelStreak = 0;
    }

    // Show zone-themed streak message at milestones (3, 5, 7, 10+)
    if (_inLevelStreak >= 3 &&
        (_inLevelStreak == 3 || _inLevelStreak == 5 ||
         _inLevelStreak == 7 || _inLevelStreak >= 10)) {
      widget.musicService?.onStreakReached(_inLevelStreak);
      _streakMessageText = PhraseTemplates.randomZoneStreakMessage(_zoneKey);
      _showStreakMessage = true;
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _showStreakMessage = false);
      });
    }

    // Zone-themed encouragement text for celebration overlay
    _zoneEncouragement = PhraseTemplates.randomZoneEncouragement(
      _zoneKey, widget.playerName,
    );

    // Tier-aware confetti
    if (_isChampion && _mistakesThisWord == 0) {
      // Extra golden burst for perfect champion words
      _goldenConfettiController.play();
    }
    _confettiController.play();

    // Zone-aware avatar expression on word complete
    widget.audioService.playSuccess();
    if (_zoneIndex >= 3) {
      _avatarController.setExpression(AvatarExpression.excited, duration: const Duration(seconds: 2));
    } else if (_zoneIndex == 2) {
      _avatarController.setExpression(AvatarExpression.surprised, duration: const Duration(milliseconds: 600));
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _avatarController.setExpression(AvatarExpression.excited, duration: const Duration(milliseconds: 1400));
      });
    } else {
      _avatarController.setExpression(
        _inLevelStreak >= 3 ? AvatarExpression.excited : AvatarExpression.happy,
        duration: const Duration(seconds: 2),
      );
    }

    // Streak milestone pop
    if (_inLevelStreak == 3 || _inLevelStreak == 5) {
      _streakPopController.forward(from: 0);
    }

    Haptics.success();

    setState(() => _showingCelebration = true);

    // Celebrate — give the child time to enjoy it
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    if (_isLastWord || wasTierComplete) {
      // Level/tier complete — stop background music for celebration
      widget.musicService?.stopMusic();
      _levelConfettiController.play();
      widget.audioService.playLevelCompleteEffect();
      _avatarController.setExpression(AvatarExpression.excited, duration: const Duration(seconds: 4));
      _playZoneLevelComplete();

      // Record daily streak
      widget.streakService?.recordPractice();

      setState(() {
        _showingCelebration = false;
        _levelComplete = true;
        _levelCompletePhrase =
            PhraseTemplates.randomZoneLevelComplete(_zoneKey, widget.playerName);
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
    // Stop adaptive music when leaving game
    widget.musicService?.stopMusic();
    _sessionTimer.stop();
    widget.statsService?.recordPlayTime(_sessionTimer.elapsed.inSeconds);
    // Notify personality service of session end
    if (widget.profileId.isNotEmpty) {
      widget.personalityService?.onSessionEnd(
        widget.profileId,
        _sessionTimer.elapsed,
      );
    }
    _avatarController.dispose();
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
                // ── Zone-themed animated background ──────
                Positioned.fill(
                  child: ZoneBackground(
                    zone: zoneIndexForLevel(widget.level),
                  ),
                ),

                // ── Main content ─────────────────────────
                SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(levelColors),
                      if (_levelComplete)
                        Expanded(child: _buildLevelComplete())
                      else
                        Expanded(
                          child: Column(
                            children: [
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
                                    style: AppFonts.fredoka(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ),

                              // Hear word button
                              _buildHearButton(),
                              const SizedBox(height: 20),

                              // Letter tiles
                              _buildLetterTiles(),
                              const SizedBox(height: 20),

                              // On-screen keyboard or letter tracing canvas
                              if (_tracingActive &&
                                  _tracingLetterIndex < _targetText.length &&
                                  !_showingCelebration)
                                _buildTracingArea()
                              else
                                _buildKeyboard(levelColors),
                              const Spacer(flex: 1),
                            ],
                          ),
                        ),
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

                // ── Zone streak message (e.g. "Forest Fire!") ────
                if (_showStreakMessage && _streakMessageText.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.starGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.starGold.withValues(alpha: 0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.starGold.withValues(alpha: 0.2),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department_rounded,
                                size: 22, color: AppColors.starGold),
                            const SizedBox(width: 8),
                            Text(
                              '$_streakMessageText $_inLevelStreak',
                              style: AppFonts.fredoka(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.starGold,
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .scaleXY(
                            begin: 0.5, end: 1.0,
                            duration: 400.ms,
                            curve: Curves.elasticOut,
                          )
                          .fadeIn(duration: 200.ms)
                          .then(delay: 1200.ms)
                          .fadeOut(duration: 300.ms),
                    ),
                  ),

                // ── Celebration overlay ───────────────────
                if (_showingCelebration)
                  CelebrationOverlay(
                    word: _currentWord.text,
                    playerName: widget.playerName,
                    zoneIndex: _zoneIndex,
                    inLevelStreak: _inLevelStreak,
                    zoneEncouragement: _zoneEncouragement,
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
                  style: AppFonts.fredoka(
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
                      style: AppFonts.nunito(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_wordTier.icon} ${_wordTier.displayName}',
                      style: AppFonts.fredoka(
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
          // Small avatar with reactions
          if (widget.profileService != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AvatarWidget(
                config: widget.profileService!.avatar,
                size: 36,
                showBackground: false,
                controller: _avatarController,
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
              style: AppFonts.fredoka(
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
          // Just-completed dot gets a brief glow pulse
          final justCompleted = isDone && i == _currentWordIndex - 1;

          Widget dot = AnimatedContainer(
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

          // Brief scale pulse on the most recently completed dot
          if (justCompleted) {
            dot = dot
                .animate(key: ValueKey('dot_done_$i'))
                .scale(
                  begin: const Offset(1.5, 1.5),
                  end: const Offset(1.0, 1.0),
                  duration: 400.ms,
                  curve: Curves.easeOut,
                );
          }

          return dot;
        }),
      ),
    );
  }

  // ── Hear Word Button ────────────────────────────────────────────

  Widget _buildHearButton() {
    final button = GestureDetector(
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
                : AppColors.electricBlue.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricBlue.withValues(
                  alpha: _isPlayingAudio ? 0.2 : 0.08),
              blurRadius: _isPlayingAudio ? 16 : 8,
            ),
          ],
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
              style: AppFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.electricBlue,
              ),
            ),
          ],
        ),
      ),
    );

    if (_isPlayingAudio) {
      return button
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.04, duration: 600.ms, curve: Curves.easeInOut);
    }
    return button;
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
        key: ValueKey('word_$_currentWordIndex'),
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: List.generate(_targetText.length, (i) {
          // Explorer/Adventurer: first letter is pre-revealed
          final isPreRevealed = (_isExplorer || _isAdventurer) && i == 0;
          // During hint reveal (3rd wrong tap), briefly show the correct letter
          final hintReveal = _hintRevealing && i == _currentLetterIndex;
          Widget tile = LetterTile(
            letter: _targetText[i],
            isRevealed: _revealedLetters[i] || hintReveal,
            isActive: i == _currentLetterIndex && !_showingCelebration,
            isError: _shaking && i == _currentLetterIndex,
            revealedColor: hintReveal
                ? AppColors.electricBlue
                : isPreRevealed && !(_currentLetterIndex > i && i > 0)
                    ? AppColors.silver
                    : null,
          );
          // Bounce animation on hint reveal
          if (hintReveal) {
            tile = tile
                .animate(key: const ValueKey('hint_bounce'))
                .scaleXY(begin: 1.3, end: 1.0, duration: 400.ms, curve: Curves.elasticOut);
          }
          return tile;
        }),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0, duration: 300.ms),
    );
  }

  // ── Letter Tracing Area ────────────────────────────────────────

  Widget _buildTracingArea() {
    final letter = _targetText[_tracingLetterIndex];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LetterTracingCanvas(
        key: ValueKey('trace_${_currentWordIndex}_$_tracingLetterIndex'),
        letter: letter,
        traceColor: AppColors.electricBlue,
        guideColor: Colors.white.withValues(alpha: 0.3),
        onComplete: _onTracingLetterComplete,
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(
          begin: 0.1,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
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
              style: AppFonts.fredoka(
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

  /// Get champion words that still need to pass (bestMistakes > 1).
  List<String> _getChampionRemainingWords() {
    if (!_isChampion) return [];
    final lp = widget.progressService.getLevel(widget.level);
    final tierProg = lp.tierProgress[3];
    if (tierProg == null) return [];

    final allWords = DolchWords.wordsForLevel(widget.level);
    final remaining = <String>[];
    for (final word in allWords) {
      final stats = tierProg.wordStats[word.text];
      if (stats == null || stats.bestMistakes > 1) {
        remaining.add(word.text);
      }
    }
    return remaining;
  }

  Widget _buildLevelComplete() {
    final tierColor = _wordTier.color;
    final praiseColor = _isChampion
        ? AppColors.starGold
        : _isAdventurer
            ? AppColors.silver
            : AppColors.success;

    // Check if champion tier is actually complete
    final championRemaining = _getChampionRemainingWords();
    final championNotDone = _isChampion && championRemaining.isNotEmpty;

    final tierLabel = championNotDone
        ? 'Almost There!'
        : _isChampion
            ? 'CHAMPION!'
            : _isAdventurer
                ? 'Tier Complete!'
                : 'Level Complete!';

    final tierIcon = championNotDone
        ? Icons.emoji_events_rounded
        : Icons.star_rounded;

    final tierIconColor = championNotDone
        ? AppColors.starGold.withValues(alpha: 0.6)
        : tierColor;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star/trophy with glow (tier-colored)
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: tierIconColor.withValues(alpha: 0.5),
                    blurRadius: 50,
                    spreadRadius: 12,
                  ),
                  BoxShadow(
                    color: tierIconColor.withValues(alpha: 0.2),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                tierIcon,
                color: tierIconColor,
                size: 88,
              ),
            )
                .animate()
                .scaleXY(
                  begin: 0.0,
                  end: 1.0,
                  curve: Curves.elasticOut,
                  duration: 900.ms,
                )
                .rotate(
                  begin: -0.05,
                  end: 0,
                  duration: 900.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 20),

            Text(
              tierLabel,
              style: AppFonts.fredoka(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                shadows: [
                  Shadow(
                    color: tierIconColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                  Shadow(
                    color: tierIconColor.withValues(alpha: 0.15),
                    blurRadius: 40,
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 250.ms, duration: 400.ms)
                .slideY(begin: 0.3, end: 0, delay: 250.ms, duration: 400.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 8),

            // Personalized phrase or "try again" message
            Text(
              championNotDone
                  ? '${championRemaining.length} word${championRemaining.length == 1 ? '' : 's'} left to master!'
                  : _levelCompletePhrase.isNotEmpty
                      ? _levelCompletePhrase
                      : 'Amazing job!',
              style: AppFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: championNotDone ? AppColors.electricBlue : praiseColor,
                shadows: [
                  Shadow(
                    color: (championNotDone ? AppColors.electricBlue : praiseColor)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 400.ms, duration: 300.ms),

            // Show remaining champion words that need to pass
            if (championNotDone) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: championRemaining.map((word) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      word,
                      style: AppFonts.fredoka(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error.withValues(alpha: 0.9),
                      ),
                    ),
                  );
                }).toList(),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 8),
              Text(
                'Spell with 1 mistake or less!',
                style: AppFonts.nunito(
                  fontSize: 13,
                  color: AppColors.secondaryText.withValues(alpha: 0.7),
                ),
              ).animate().fadeIn(delay: 650.ms),
            ],

            const SizedBox(height: 16),

            // Stats row
            if (!championNotDone)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatChip(
                    icon: Icons.check_circle_rounded,
                    value: '${_words.length}',
                    label: 'Words',
                    color: AppColors.success,
                  )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 500.ms, duration: 300.ms),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.star_rounded,
                    value: '$_perfectWords',
                    label: 'Perfect',
                    color: AppColors.starGold,
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 300.ms),
                  if (_isChampion && _perfectStreak > 0) ...[
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.local_fire_department_rounded,
                      value: '$_perfectStreak',
                      label: 'Streak',
                      color: _perfectStreak >= 5
                          ? AppColors.starGold
                          : AppColors.error,
                    )
                        .animate()
                        .fadeIn(delay: 700.ms, duration: 300.ms)
                        .slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 300.ms),
                  ],
                ],
              ),

            if (championNotDone)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatChip(
                    icon: Icons.check_circle_rounded,
                    value: '${_words.length - championRemaining.length}/10',
                    label: 'Passed',
                    color: AppColors.success,
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 300.ms),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.star_rounded,
                    value: '$_perfectWords',
                    label: 'Perfect',
                    color: AppColors.starGold,
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 300.ms),
                ],
              ),

            const SizedBox(height: 32),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundButton(
                  label: championNotDone ? 'Try Again' : 'Replay',
                  icon: championNotDone
                      ? Icons.refresh_rounded
                      : Icons.replay_rounded,
                  color: championNotDone
                      ? AppColors.electricBlue
                      : AppColors.secondaryText,
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
                )
                    .animate()
                    .fadeIn(delay: 750.ms, duration: 300.ms)
                    .slideY(begin: 0.3, end: 0, delay: 750.ms, duration: 300.ms),
                if (!championNotDone) ...[
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
                            transitionDuration: const Duration(milliseconds: 600),
                            pageBuilder: (_, __, ___) => GameScreen(
                              level: widget.level + 1,
                              tier: widget.tier,
                              progressService: widget.progressService,
                              audioService: widget.audioService,
                              profileService: widget.profileService,
                              statsService: widget.statsService,
                              streakService: widget.streakService,
                              personalityService: widget.personalityService,
                              adaptiveDifficultyService: widget.adaptiveDifficultyService,
                              playerName: widget.playerName,
                              profileId: widget.profileId,
                            ),
                            transitionsBuilder: (_, animation, __, child) {
                              // Smooth slide + fade for level transition
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: FadeTransition(
                                  opacity: CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeIn,
                                  ),
                                  child: child,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                        .animate()
                        .fadeIn(delay: 850.ms, duration: 300.ms)
                        .slideY(begin: 0.3, end: 0, delay: 850.ms, duration: 300.ms),
                ],
              ],
            ),
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

    // Dynamic key sizing based on screen width
    // 10 keys per row + margins = need to fit within screen width - padding
    final screenW = MediaQuery.of(context).size.width;
    final keyMargin = (screenW / 200).clamp(1.5, 3.0);
    final keyWidth = ((screenW - 16) / 10 - keyMargin * 2).clamp(24.0, 38.0);
    final keyHeight = (keyWidth * 1.3).clamp(32.0, 50.0);
    final fontSize = (keyWidth * 0.5).clamp(13.0, 20.0);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.symmetric(horizontal: keyMargin),
          width: keyWidth,
          height: keyHeight,
          decoration: BoxDecoration(
            color: showHighlight
                ? AppColors.electricBlue.withValues(alpha: 0.2)
                : showNudge
                    ? AppColors.electricBlue.withValues(alpha: 0.15)
                    : _pressed
                        ? AppColors.electricBlue.withValues(alpha: 0.12)
                        : AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: showHighlight
                  ? AppColors.electricBlue
                  : showNudge
                      ? AppColors.electricBlue.withValues(alpha: 0.6)
                      : _pressed
                          ? AppColors.electricBlue.withValues(alpha: 0.4)
                          : AppColors.border.withValues(alpha: 0.5),
              width: showHighlight ? 1.5 : 1,
            ),
            boxShadow: [
              if (showHighlight)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              if (showNudge)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: nudgeGlowAlpha * 0.5),
                  blurRadius: 12,
                ),
              if (_pressed)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
            ],
          ),
          child: Center(
            child: Text(
              widget.letter,
              style: AppFonts.fredoka(
                fontSize: fontSize,
                fontWeight:
                    (showHighlight || showNudge) ? FontWeight.w600 : FontWeight.w400,
                color: (showHighlight || showNudge || _pressed)
                    ? AppColors.electricBlue
                    : AppColors.primaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Round Button ────────────────────────────────────────────────────

class _RoundButton extends StatefulWidget {
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
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: _pressed ? 0.2 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.color.withValues(alpha: 0.4), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: widget.color, size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: AppFonts.fredoka(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: widget.color,
              ),
            ),
          ],
        ),
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
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppFonts.nunito(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

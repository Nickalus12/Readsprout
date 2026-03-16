import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../data/dolch_words.dart';
import '../../models/word.dart';
import '../../data/music_layers.dart';
import '../../data/phrase_templates.dart';
import '../../services/audio_service.dart';
import '../../models/player_profile.dart';
import '../../services/profile_service.dart';
import '../../services/progress_service.dart';
import '../../services/stats_service.dart';
import '../../services/streak_service.dart';
import '../../services/adaptive_music_service.dart';
import '../../services/avatar_personality_service.dart';
import '../../services/review_service.dart';
import '../../services/adaptive_difficulty_service.dart';
import '../../data/sticker_definitions.dart';
import '../../widgets/animated_glow_border.dart';
import '../../data/letter_paths.dart';
import '../../utils/haptics.dart';
import '../../avatar/avatar_widget.dart';
import '../../widgets/celebration_overlay.dart';
import '../../widgets/zone_background.dart';
import '../../data/word_context.dart';
import 'game_hud.dart';
import 'game_board.dart';
import 'game_keyboard.dart';
import 'game_completion.dart';
import 'champion_retry_overlay.dart';

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

  /// Optional custom word list for review mode. When provided, these words
  /// are used instead of loading from DolchWords.wordsForLevel.
  final List<Word>? reviewWords;

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
    this.reviewWords,
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

  /// Today's date key for daily accuracy tracking (YYYY-MM-DD).
  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

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

  /// Whether the champion retry prompt is showing (word failed, offer retry).
  bool _championRetryPrompt = false;

  /// Total mistakes across all words in this champion tier session.
  int _championTierMistakes = 0;

  // ── In-level streak (all tiers) ────────────────────────────────
  /// Consecutive correct words within this level session.
  int _inLevelStreak = 0;

  // ── Progressive hints state ────────────────────────────────────
  /// Total wrong taps on the current word (resets per word).
  int _totalWrongTapsThisWord = 0;

  /// Whether the correct letter is being revealed (3rd wrong tap hint).
  bool _hintRevealing = false;

  /// Whether the player has used a purchased hint on the current word.
  bool _purchasedHintUsed = false;

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

  // ── Inactivity detection (encouraging nudge after 5s idle) ───
  Timer? _idleTimer;

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_showingCelebration || _levelComplete || _championRetryPrompt) return;
    _idleTimer = Timer(const Duration(seconds: 5), _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (!mounted || _showingCelebration || _levelComplete) return;
    // Gentle encouraging expression + think animation (head tilt)
    _avatarController.setExpression(
      AvatarExpression.happy,
      duration: const Duration(seconds: 3),
    );
    _avatarController.playAnimation('think');
    // Highlight the correct key as a gentle hint
    if (_currentLetterIndex < _targetText.length) {
      setState(() => _nudgeKey = _targetText[_currentLetterIndex].toUpperCase());
      _nudgeController.forward(from: 0);
    }
  }

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

  void _onShakeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _shakeController.reset();
      setState(() => _shaking = false);
    }
  }

  void _onNudgeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() => _nudgeKey = null);
      _nudgeController.reset();
    }
  }

  // Focus node for keyboard input
  final FocusNode _focusNode = FocusNode();

  // Avatar expression controller for gameplay reactions
  final AvatarController _avatarController = AvatarController();

  // ── Convenience getters ──────────────────────────────────────────

  Word get _currentWord => _words[_currentWordIndex];
  String get _targetText => _currentWord.text.toLowerCase();
  bool get _isLastWord => _currentWordIndex >= _words.length - 1;
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

    // Load words: use review words if provided, otherwise load from level data
    final List<Word> levelWords;
    if (widget.reviewWords != null && widget.reviewWords!.isNotEmpty) {
      levelWords = List<Word>.from(widget.reviewWords!);
    } else {
      levelWords = List<Word>.from(DolchWords.wordsForLevel(widget.level));
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
    }
    _words = levelWords;
    _initRevealedLetters();

    // Shake animation for wrong input
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _shakeController.addStatusListener(_onShakeStatus);

    // Nudge controller (Tier 2) — pulse correct key for ~1 second
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _nudgeController.addStatusListener(_onNudgeStatus);

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

    // Start idle detection
    _resetIdleTimer();
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
    _purchasedHintUsed = false;

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
    if (_showingCelebration || _levelComplete || _championRetryPrompt) return;
    _resetIdleTimer();

    final expectedLetter = _targetText[_currentLetterIndex];

    if (key.toLowerCase() == expectedLetter.toLowerCase()) {
      // Correct letter!
      Haptics.correct();
      widget.statsService?.recordLetterTap(key);
      widget.statsService?.recordDailyAccuracy(_todayKey, correct: 1, wrong: 0);
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
      } else {
        // Quick happy flash + nod for each correct letter
        _avatarController.setExpression(
          AvatarExpression.happy,
          duration: const Duration(milliseconds: 800),
        );
        _avatarController.playAnimation('nod');
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
    widget.statsService?.recordDailyAccuracy(_todayKey, correct: 0, wrong: 1);
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
    // 1st wrong tap → avatar shows "thinking" + highlight correct key
    // 2nd+ wrong tap → briefly reveal the answer letter with bounce

    if (_totalWrongTapsThisWord == 1) {
      // 1st wrong: avatar gentle head shake + think + highlight correct key
      _avatarController.setExpression(AvatarExpression.thinking, duration: const Duration(seconds: 2));
      _avatarController.playAnimation('headShake');
      setState(() => _nudgeKey = expected);
      _nudgeController.forward(from: 0);
    } else if (_totalWrongTapsThisWord >= 2) {
      // 2nd+ wrong: briefly reveal the correct letter tile, then hide
      _avatarController.setExpression(AvatarExpression.surprised, duration: const Duration(milliseconds: 1500));
      setState(() {
        _hintRevealing = true;
        _nudgeKey = expected;
      });
      _nudgeController.forward(from: 0);
      // Auto-hide the hint after a brief moment
      Future.delayed(const Duration(milliseconds: 1500), () {
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

  /// Buy a hint for 2 star coins — reveals the correct next letter.
  /// Only available for Adventurer/Champion tiers, once per word.
  static const _hintCost = 2;

  void _buyHint() {
    if (_purchasedHintUsed) return;
    if (_currentLetterIndex >= _targetText.length) return;
    if (!widget.progressService.spendStarCoins(_hintCost)) {
      // Not enough coins — show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough coins! Need $_hintCost coins.',
            style: AppFonts.nunito(fontSize: 14, color: Colors.white),
          ),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _purchasedHintUsed = true;
      _hintRevealing = true;
      final expected = _targetText[_currentLetterIndex].toUpperCase();
      _nudgeKey = expected;
    });
    _nudgeController.forward(from: 0);

    // Auto-hide after brief moment
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _hintRevealing = false);
    });
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

    // Champion perfect streak + tier mistake tracking
    if (_isChampion) {
      _championTierMistakes += _mistakesThisWord;
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

    // Record daily streak on every word completion (not just level/tier finish)
    widget.streakService?.recordPractice();

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
      // Avatar escalating excitement on streak milestones
      if (_inLevelStreak >= 7) {
        _avatarController.playAnimation('celebrate');
      } else if (_inLevelStreak >= 5) {
        _avatarController.playAnimation('clap');
      } else {
        _avatarController.playAnimation('thumbsUp');
      }
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

    _idleTimer?.cancel(); // Stop idle detection during celebration
    setState(() => _showingCelebration = true);

    // Celebrate — give the child plenty of time to enjoy it
    await Future.delayed(const Duration(milliseconds: 3200));
    if (!mounted) return;

    if (_isLastWord || wasTierComplete) {
      // Level/tier complete — stop background music for celebration
      widget.musicService?.stopMusic();
      _levelConfettiController.play();
      widget.audioService.playLevelCompleteEffect();
      _avatarController.setExpression(AvatarExpression.excited, duration: const Duration(seconds: 4));
      _avatarController.playAnimation('celebrate');
      _playZoneLevelComplete();

      setState(() {
        _showingCelebration = false;
        _levelComplete = true;
        _levelCompletePhrase =
            PhraseTemplates.randomZoneLevelComplete(_zoneKey, widget.playerName);
      });
    } else if (_isChampion && _championWordFailed) {
      // Champion word failed — show retry prompt instead of auto-advancing
      setState(() {
        _showingCelebration = false;
        _championRetryPrompt = true;
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
      _resetIdleTimer();
    }
  }

  /// Retry the current champion word (reset just this word's state).
  void _retryChampionWord() {
    setState(() {
      _championRetryPrompt = false;
      _initRevealedLetters();
    });
    Future.delayed(const Duration(milliseconds: 300), _announceCurrentWord);
  }

  /// Skip the failed champion word and move to the next one.
  void _skipChampionWord() {
    setState(() {
      _championRetryPrompt = false;
      if (_currentWordIndex < _words.length - 1) {
        _currentWordIndex++;
        _initRevealedLetters();
      } else {
        // Was last word — go to level complete
        _levelComplete = true;
        _levelCompletePhrase =
            PhraseTemplates.randomZoneLevelComplete(_zoneKey, widget.playerName);
      }
    });
    if (!_levelComplete && _currentWordIndex < _words.length) {
      Future.delayed(const Duration(milliseconds: 300), _announceCurrentWord);
    }
  }

  @override
  void dispose() {
    // Stop adaptive music when leaving game
    widget.musicService?.stopMusic();
    _sessionTimer.stop();
    widget.statsService?.recordPlayTime(_sessionTimer.elapsed.inSeconds);
    // Record daily session for activity chart
    widget.statsService?.recordDailySession(
      _todayKey,
      _currentWordIndex, // words completed this session
      (_sessionTimer.elapsed.inSeconds / 60).ceil(),
    );
    // Notify personality service of session end
    if (widget.profileId.isNotEmpty) {
      widget.personalityService?.onSessionEnd(
        widget.profileId,
        _sessionTimer.elapsed,
      );
    }
    _idleTimer?.cancel();
    _avatarController.dispose();
    _shakeController.removeStatusListener(_onShakeStatus);
    _shakeController.dispose();
    _nudgeController.removeStatusListener(_onNudgeStatus);
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
                      GameHeader(
                        level: widget.level,
                        tier: widget.tier,
                        savingProgress: _savingProgress,
                        currentWordIndex: _currentWordIndex,
                        totalWords: _words.length,
                        profileService: widget.profileService,
                        avatarController: _avatarController,
                      ),
                      if (_levelComplete)
                        Expanded(
                          child: GameLevelComplete(
                            level: widget.level,
                            tier: widget.tier,
                            perfectWords: _perfectWords,
                            perfectStreak: _perfectStreak,
                            totalWords: _words.length,
                            totalTierMistakes: _championTierMistakes,
                            levelCompletePhrase: _levelCompletePhrase,
                            progressService: widget.progressService,
                            onReplay: () {
                              setState(() {
                                _words.shuffle();
                                _currentWordIndex = 0;
                                _perfectWords = 0;
                                _perfectStreak = 0;
                                _championTierMistakes = 0;
                                _initRevealedLetters();
                                _levelComplete = false;
                              });
                              Future.delayed(const Duration(milliseconds: 400),
                                  _announceCurrentWord);
                            },
                            onNext: widget.level < DolchWords.totalLevels
                                ? () {
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
                                          reviewService: widget.reviewService,
                                          adaptiveDifficultyService: widget.adaptiveDifficultyService,
                                          musicService: widget.musicService,
                                          playerName: widget.playerName,
                                          profileId: widget.profileId,
                                        ),
                                        transitionsBuilder: (_, animation, __, child) {
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
                                  }
                                : null,
                          ),
                        )
                      else
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Adapt spacing based on available height
                              final availH = constraints.maxHeight;
                              final tight = availH < 420;
                              final veryTight = availH < 340;
                              final gap1 = veryTight ? 6.0 : tight ? 10.0 : 20.0;
                              final gap2 = veryTight ? 6.0 : tight ? 10.0 : 20.0;
                              final topGap = veryTight ? 2.0 : tight ? 4.0 : 8.0;

                              return Column(
                                children: [
                                  SizedBox(height: topGap),
                                  // Progress dots
                                  GameProgressDots(
                                    totalWords: _words.length,
                                    currentWordIndex: _currentWordIndex,
                                    levelColors: levelColors,
                                  ),
                                  const Spacer(flex: 2),

                                  // Champion: "Keep practicing!" message for failed words
                                  if (_isChampion && _championWordFailed)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'Keep practicing!',
                                        style: AppFonts.fredoka(
                                          fontSize: tight ? 14 : 16,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ),

                                  // Hear word button + emoji hint
                                  HearWordButton(
                                    isPlayingAudio: _isPlayingAudio,
                                    onTap: _announceCurrentWord,
                                  ),
                                  if (getWordEmoji(_currentWord.text).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: GestureDetector(
                                        onTap: _announceCurrentWord,
                                        child: Text(
                                          getWordEmoji(_currentWord.text),
                                          style: TextStyle(fontSize: tight ? 28 : 36),
                                        ),
                                      ),
                                    ),
                                  SizedBox(height: tight ? 4 : gap1),

                                  // Letter tiles
                                  GameLetterTiles(
                                    targetText: _targetText,
                                    currentWordIndex: _currentWordIndex,
                                    currentLetterIndex: _currentLetterIndex,
                                    revealedLetters: _revealedLetters,
                                    isExplorer: _isExplorer,
                                    isAdventurer: _isAdventurer,
                                    showingCelebration: _showingCelebration,
                                    shaking: _shaking,
                                    hintRevealing: _hintRevealing,
                                    shakeAnimation: _shakeAnimation,
                                  ),

                                  // Buy Hint button (Adventurer/Champion only)
                                  if (!_isExplorer &&
                                      !_showingCelebration &&
                                      !_levelComplete &&
                                      _currentLetterIndex < _targetText.length)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                                      child: GestureDetector(
                                        onTap: _purchasedHintUsed ? null : _buyHint,
                                        child: AnimatedOpacity(
                                          opacity: _purchasedHintUsed ? 0.4 : 1.0,
                                          duration: const Duration(milliseconds: 200),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _purchasedHintUsed
                                                  ? AppColors.surface.withValues(alpha: 0.4)
                                                  : AppColors.starGold.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _purchasedHintUsed
                                                    ? AppColors.border.withValues(alpha: 0.3)
                                                    : AppColors.starGold.withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _purchasedHintUsed ? Icons.check_rounded : Icons.lightbulb_rounded,
                                                  size: 14,
                                                  color: _purchasedHintUsed ? AppColors.secondaryText : AppColors.starGold,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _purchasedHintUsed ? 'Hint used' : 'Hint  $_hintCost',
                                                  style: AppFonts.nunito(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _purchasedHintUsed ? AppColors.secondaryText : AppColors.starGold,
                                                  ),
                                                ),
                                                if (!_purchasedHintUsed) ...[
                                                  const SizedBox(width: 2),
                                                  Icon(
                                                    Icons.monetization_on_rounded,
                                                    size: 12,
                                                    color: AppColors.starGold.withValues(alpha: 0.8),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  SizedBox(height: gap2),

                                  // On-screen keyboard or letter tracing canvas
                                  if (_tracingActive &&
                                      _tracingLetterIndex < _targetText.length &&
                                      !_showingCelebration)
                                    GameTracingArea(
                                      targetText: _targetText,
                                      currentWordIndex: _currentWordIndex,
                                      tracingLetterIndex: _tracingLetterIndex,
                                      onComplete: _onTracingLetterComplete,
                                    )
                                  else
                                    GameKeyboard(
                                      isExplorer: _isExplorer,
                                      isAdventurer: _isAdventurer,
                                      showingCelebration: _showingCelebration,
                                      levelComplete: _levelComplete,
                                      currentLetterIndex: _currentLetterIndex,
                                      targetText: _targetText,
                                      nudgeKey: _nudgeKey,
                                      nudgeController: _nudgeController,
                                      levelColors: levelColors,
                                      onKeyPressed: _onKeyPressed,
                                    ),
                                  SizedBox(height: veryTight ? 2 : tight ? 4 : 0),
                                  if (!veryTight) const Spacer(flex: 1),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Champion perfect streak badge (centered below header) ──
                if (_isChampion && _perfectStreak > 0 && !_levelComplete)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 52,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GameStreakBadge(
                        perfectStreak: _perfectStreak,
                        streakPopController: _streakPopController,
                      ),
                    ),
                  ),

                // ── Zone streak message (e.g. "Forest Fire!") ────
                if (_showStreakMessage && _streakMessageText.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 50,
                    left: 0,
                    right: 0,
                    child: ZoneStreakMessage(
                      messageText: _streakMessageText,
                      inLevelStreak: _inLevelStreak,
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
                    tier: widget.tier,
                    mistakes: _mistakesThisWord,
                    isPerfectChampionRun: _isChampion && _perfectStreak > 0 && _mistakesThisWord == 0,
                  ),

                // ── Champion retry prompt ───────────────────
                if (_championRetryPrompt)
                  ChampionRetryOverlay(
                    word: _currentWord.text,
                    onRetry: _retryChampionWord,
                    onSkip: _skipChampionWord,
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
}

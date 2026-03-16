import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/game_animations.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../services/high_score_service.dart';
import '../services/profile_service.dart';
import '../services/stats_service.dart';
import '../services/avatar_personality_service.dart';
import 'mini_games/unicorn_flight_game.dart';
import 'mini_games/lightning_speller_game.dart';
import 'mini_games/word_bubbles_game.dart';
import 'mini_games/memory_match_game.dart';
import 'mini_games/falling_letters_game.dart';
import 'mini_games/cat_letter_toss_game.dart';
import 'mini_games/letter_drop_game.dart';
import 'mini_games/rhyme_time_game.dart';
import 'mini_games/star_catcher_game.dart';
import 'mini_games/paint_splash_game.dart';
import 'mini_games/word_rocket_game.dart';
import 'mini_games/sight_word_safari_game.dart';
import 'mini_games/word_ninja_game.dart';
import 'mini_games/spelling_bee_game.dart';
import 'mini_games/word_train_game.dart';
import 'mini_games/ladybug_game.dart';
import 'mini_games/element_lab/element_lab_game.dart';
import 'mini_games/element_lab/element_lab_painters.dart';
import 'mini_games/color_mix_lab_game.dart';
import 'mini_games/sound_garden_game.dart';
import 'mini_games/bubble_pop_zoo_game.dart';
import '../services/adaptive_difficulty_service.dart';

class MiniGamesScreen extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;
  final ProfileService? profileService;
  final StatsService? statsService;
  final AvatarPersonalityService? personalityService;
  final AdaptiveDifficultyService? adaptiveDifficultyService;
  final String profileId;

  const MiniGamesScreen({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
    this.profileService,
    this.statsService,
    this.personalityService,
    this.adaptiveDifficultyService,
    this.profileId = '',
  });

  @override
  State<MiniGamesScreen> createState() => _MiniGamesScreenState();
}

class _MiniGamesScreenState extends State<MiniGamesScreen> {
  static const _hintsPrefKey = 'mini_game_hints_enabled';
  bool _hintsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadHintsPref();
  }

  Future<void> _loadHintsPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintsEnabled = prefs.getBool(_hintsPrefKey) ?? true;
    });
  }

  Future<void> _toggleHints() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintsEnabled = !_hintsEnabled;
    });
    await prefs.setBool(_hintsPrefKey, _hintsEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.backgroundEnd],
              ),
            ),
          ),

          // Floating particles
          const Positioned.fill(
            child: ExcludeSemantics(child: _MiniGameParticles()),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Free Games Section ──
                        _buildSectionHeader(
                          icon: Icons.play_circle_rounded,
                          label: 'Free Games',
                          gradientColors: [AppColors.electricBlue, AppColors.cyan],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            _buildGameBtn(
                              context, 'Unicorn Flight',
                              const _UnicornIconPainter(), AppColors.magenta, 0,
                              UnicornFlightGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('unicorn_flight'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Lightning Speller',
                              const _StormCloudPainter(), AppColors.electricBlue, 1,
                              LightningSpellerGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('lightning_speller'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Word Bubbles',
                              const _BubblesIconPainter(), AppColors.cyan, 2,
                              WordBubblesGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('word_bubbles'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Memory Match',
                              const _CardsIconPainter(), AppColors.violet, 3,
                              MemoryMatchGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('memory_match'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Falling Letters',
                              const _FallingIconPainter(), AppColors.starGold, 4,
                              FallingLettersGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('falling_letters'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Cat Toss',
                              const _CatIconPainter(), AppColors.magenta, 5,
                              CatLetterTossGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('cat_letter_toss'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Letter Drop',
                              const _DropIconPainter(), AppColors.emerald, 6,
                              LetterDropGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('letter_drop'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Rhyme Time',
                              const _RhymeIconPainter(), AppColors.magenta, 7,
                              RhymeTimeGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('rhyme_time'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Star Catcher',
                              const _StarCatcherIconPainter(), AppColors.violet, 8,
                              StarCatcherGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('star_catcher'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Paint Splash',
                              const _PaintSplashIconPainter(), AppColors.magenta, 9,
                              PaintSplashGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                profileService: widget.profileService,
                                hintsEnabled: _hintsEnabled,
                                difficultyParams: widget.adaptiveDifficultyService?.getParamsForGame('paint_splash'),
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Word Rocket',
                              const _RocketIconPainter(), AppColors.electricBlue, 10,
                              WordRocketGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Word Safari',
                              const _SafariIconPainter(), AppColors.emerald, 11,
                              SightWordSafariGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Word Ninja',
                              const _NinjaIconPainter(), AppColors.magenta, 12,
                              WordNinjaGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Spelling Bee',
                              const _BeeIconPainter(), AppColors.starGold, 13,
                              SpellingBeeGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Word Train',
                              const _TrainIconPainter(), AppColors.electricBlue, 14,
                              WordTrainGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Ladybug Letters',
                              const _LadybugIconPainter(), AppColors.error, 15,
                              LadybugGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                highScoreService: widget.highScoreService,
                                playerName: widget.playerName,
                              ),
                            ),
                            _buildGameBtn(
                              context, 'Bubble Pop Zoo',
                              const BubblePopZooIconPainter(), AppColors.cyan, 16,
                              BubblePopZooGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ── Premium Games Section ──
                        _buildSectionHeader(
                          icon: Icons.star_rounded,
                          label: 'Premium Games',
                          gradientColors: [const Color(0xFFFFD700), const Color(0xFFFF8C42)],
                          trailing: _buildCoinBalanceChip(),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            _buildPremiumGameCard(
                              context, 'Element Lab',
                              const BeakerIconPainter(), AppColors.emerald, 17,
                              kElementLabCost,
                              (freePlay) => ElementLabGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                freePlay: freePlay,
                              ),
                            ),
                            _buildPremiumGameCard(
                              context, 'Color Mix Lab',
                              const ColorMixLabIconPainter(), AppColors.magenta, 18,
                              kColorMixLabCost,
                              (freePlay) => ColorMixLabGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                freePlay: freePlay,
                              ),
                            ),
                            _buildPremiumGameCard(
                              context, 'Sound Garden',
                              const SoundGardenIconPainter(), AppColors.emerald, 19,
                              kSoundGardenCost,
                              (freePlay) => SoundGardenGame(
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                playerName: widget.playerName,
                                freePlay: freePlay,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Semantics(
            label: 'Go back',
            hint: 'Return to home screen',
            button: true,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primaryText,
              iconSize: 28,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.audioService.playWord('mini_games'),
              child: Text(
                'Mini Games',
                textAlign: TextAlign.center,
                style: AppFonts.fredoka(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ),
          Tooltip(
            message: _hintsEnabled ? 'Hints ON' : 'Hints OFF',
            child: IconButton(
              onPressed: _toggleHints,
              icon: Icon(
                _hintsEnabled
                    ? Icons.lightbulb_rounded
                    : Icons.lightbulb_outline_rounded,
                color: _hintsEnabled
                    ? AppColors.starGold
                    : AppColors.secondaryText,
              ),
              iconSize: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required List<Color> gradientColors,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.first.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildCoinBalanceChip() {
    final coins = widget.progressService.starCoins;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.starGold.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.starGold.withValues(alpha: 0.15),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.starGold, size: 16),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: AppFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.starGold,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a premium game card — larger than free game buttons with gold border.
  Widget _buildPremiumGameCard(BuildContext context, String label,
      CustomPainter painter, Color glow, int index, int cost,
      Widget Function(bool freePlay) gameBuilder) {
    final balance = widget.progressService.starCoins;
    final freePlay = widget.progressService.freePlayMode;
    final canAfford = freePlay || balance >= cost;

    return GestureDetector(
      onTap: () async {
        if (!canAfford) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.starGold, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Need More Stars!',
                    style: AppFonts.fredoka(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
              content: Text(
                'This game costs $cost star coins.\n'
                'You have $balance — earn ${cost - balance} more by completing words!',
                style: AppFonts.fredoka(
                  fontSize: 14,
                  color: AppColors.secondaryText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'OK',
                    style: AppFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.electricBlue,
                    ),
                  ),
                ),
              ],
            ),
          );
          return;
        }
        if (!freePlay) {
          widget.progressService.spendStarCoins(cost);
        }
        if (!mounted) return;
        final game = gameBuilder(freePlay);
        await Navigator.push(context, GameAnimations.smoothRoute(game));
        if (!mounted) return;
        setState(() {}); // refresh coin display
        if (widget.profileId.isNotEmpty) {
          widget.personalityService?.onMiniGamePlayed(widget.profileId, index);
        }
        if (index < _gameIds.length) {
          widget.statsService?.recordMiniGamePlayed(_gameIds[index], 0);
        }
      },
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: canAfford
                ? AppColors.starGold.withValues(alpha: 0.6)
                : AppColors.secondaryText.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: canAfford
                  ? AppColors.starGold.withValues(alpha: 0.2)
                  : Colors.transparent,
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  colors: [
                    glow.withValues(alpha: 0.1),
                    AppColors.surface,
                  ],
                ),
                border: Border.all(
                  color: glow.withValues(alpha: canAfford ? 0.5 : 0.2),
                  width: 1.5,
                ),
              ),
              child: Opacity(
                opacity: canAfford ? 1.0 : 0.5,
                child: CustomPaint(
                  painter: painter,
                  size: const Size(64, 64),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Label
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppFonts.fredoka(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: canAfford
                    ? AppColors.primaryText
                    : AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 6),
            // Cost badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: canAfford
                    ? AppColors.starGold.withValues(alpha: 0.15)
                    : AppColors.secondaryText.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: canAfford
                      ? AppColors.starGold.withValues(alpha: 0.4)
                      : AppColors.secondaryText.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    canAfford ? Icons.star_rounded : Icons.lock_rounded,
                    color: canAfford
                        ? AppColors.starGold
                        : AppColors.secondaryText,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$cost',
                    style: AppFonts.fredoka(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: canAfford
                          ? AppColors.starGold
                          : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (index * 80).ms, duration: 400.ms)
        .scale(
          begin: const Offset(0.8, 0.8),
          curve: Curves.easeOutBack,
          delay: (index * 80).ms,
          duration: 500.ms,
        );
  }

  static const _gameIds = [
    'unicorn_flight', 'lightning_speller', 'word_bubbles',
    'memory_match', 'falling_letters', 'cat_letter_toss',
    'letter_drop', 'rhyme_time', 'star_catcher', 'paint_splash',
    'word_rocket', 'sight_word_safari', 'word_ninja',
    'spelling_bee', 'word_train', 'ladybug_letters', 'bubble_pop_zoo',
    'element_lab', 'color_mix_lab', 'sound_garden',
  ];

  Widget _buildGameBtn(BuildContext context, String label,
      CustomPainter painter, Color glow, int index, Widget game) {
    return _GameButton(
      label: label,
      painter: painter,
      glowColor: glow,
      floatIndex: index,
      onTap: () async {
        await Navigator.push(context, GameAnimations.smoothRoute(game));
        if (!mounted) return;
        // Record mini game played with personality service
        if (widget.profileId.isNotEmpty) {
          widget.personalityService?.onMiniGamePlayed(widget.profileId, index);
        }
        // Record mini game play in stats
        if (index < _gameIds.length) {
          widget.statsService?.recordMiniGamePlayed(_gameIds[index], 0);
        }
      },
    )
        .animate()
        .fadeIn(delay: (index * 80).ms, duration: 400.ms)
        .scale(
          begin: const Offset(0.8, 0.8),
          curve: Curves.easeOutBack,
          delay: (index * 80).ms,
          duration: 500.ms,
        );
  }

}

// ── Compact floating game button ──────────────────────────────────────────

class _GameButton extends StatefulWidget {
  final String label;
  final CustomPainter painter;
  final Color glowColor;
  final VoidCallback onTap;
  final int floatIndex;

  const _GameButton({
    required this.label,
    required this.painter,
    required this.glowColor,
    required this.onTap,
    this.floatIndex = 0,
  });

  @override
  State<_GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<_GameButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovering = true),
      onTapUp: (_) => setState(() => _hovering = false),
      onTapCancel: () => setState(() => _hovering = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
            _hovering ? 1.08 : 1.0, _hovering ? 1.08 : 1.0, 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon circle (with optional coin badge + idle float)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [
                          widget.glowColor.withValues(alpha: 0.08),
                          AppColors.surface,
                        ],
                      ),
                      border: Border.all(
                        color: widget.glowColor.withValues(alpha: _hovering ? 0.8 : 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.glowColor
                              .withValues(alpha: _hovering ? 0.4 : 0.15),
                          blurRadius: _hovering ? 24 : 12,
                          spreadRadius: _hovering ? 4 : 1,
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: widget.painter,
                      size: const Size(72, 72),
                    ),
                  )
                      .animate(
                        onPlay: (c) => c.repeat(reverse: true),
                        delay: Duration(milliseconds: widget.floatIndex * 200),
                      )
                      .slideY(
                        begin: 0,
                        end: -0.06,
                        duration: Duration(milliseconds: 1800 + (widget.floatIndex % 3) * 200),
                        curve: Curves.easeInOut,
                      ),
                ],
              ),
              const SizedBox(height: 6),
              // Label
              Text(
                widget.label,
                style: AppFonts.fredoka(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Unicorn icon painter (compact, fits 88x88 circle) ─────────────────────

class _UnicornIconPainter extends CustomPainter {
  const _UnicornIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Body
    final bodyPaint = Paint()
      ..color = const Color(0xFFF0E6FF)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 2, cy + 6), width: 36, height: 20),
      bodyPaint,
    );

    // Head
    final headPaint = Paint()
      ..color = const Color(0xFFF5F0FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 14, cy - 4), 10, headPaint);

    // Horn (golden)
    final hornPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx + 18, cy - 12),
      Offset(cx + 22, cy - 26),
      hornPaint,
    );

    // Horn glow dot
    canvas.drawCircle(
      Offset(cx + 22, cy - 26),
      2,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Rainbow mane
    final maneColors = [
      const Color(0xFFFF4757),
      const Color(0xFFFF8C42),
      const Color(0xFFFFD700),
      const Color(0xFF00E68A),
      const Color(0xFF00D4FF),
      const Color(0xFF8B5CF6),
    ];
    for (int i = 0; i < maneColors.length; i++) {
      final mp = Paint()
        ..color = maneColors[i].withValues(alpha: 0.8)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final yOff = cy - 10.0 + i * 3.5;
      final path = Path()
        ..moveTo(cx + 8, yOff)
        ..quadraticBezierTo(cx - 4, yOff - 4 + i * 1.5, cx - 10, yOff + 2);
      canvas.drawPath(path, mp);
    }

    // Legs
    final legPaint = Paint()
      ..color = const Color(0xFFE0D4F5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 10, cy + 14), Offset(cx - 12, cy + 26), legPaint);
    canvas.drawLine(Offset(cx - 2, cy + 15), Offset(cx - 2, cy + 27), legPaint);
    canvas.drawLine(Offset(cx + 6, cy + 15), Offset(cx + 6, cy + 27), legPaint);
    canvas.drawLine(Offset(cx + 12, cy + 14), Offset(cx + 14, cy + 26), legPaint);

    // Wing
    final wingPaint = Paint()
      ..color = const Color(0xFFD0BFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    final wingPath = Path()
      ..moveTo(cx - 2, cy)
      ..quadraticBezierTo(cx - 14, cy - 20, cx + 4, cy - 16)
      ..quadraticBezierTo(cx + 6, cy - 6, cx - 2, cy);
    canvas.drawPath(wingPath, wingPaint);

    // Eye
    canvas.drawCircle(
      Offset(cx + 18, cy - 5),
      1.5,
      Paint()..color = const Color(0xFF4A2080),
    );

    // Sparkles
    _drawSparkle(canvas, Offset(cx + 26, cy - 22), 3, const Color(0xFFFFD700));
    _drawSparkle(canvas, Offset(cx - 18, cy - 14), 2, AppColors.electricBlue);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Storm cloud icon painter (compact, fits 88x88 circle) ─────────────────

class _StormCloudPainter extends CustomPainter {
  const _StormCloudPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 6;

    // Cloud body
    final cloudPaint = Paint()
      ..color = const Color(0xFF3A3555)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 10, cy), 12, cloudPaint);
    canvas.drawCircle(Offset(cx + 6, cy - 3), 15, cloudPaint);
    canvas.drawCircle(Offset(cx + 18, cy + 1), 10, cloudPaint);
    canvas.drawCircle(Offset(cx - 2, cy + 4), 11, cloudPaint);

    // Cloud highlight
    final hlPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 4, cy - 6), 9, hlPaint);

    // Main lightning bolt
    final boltPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final bolt = Path()
      ..moveTo(cx + 2, cy + 10)
      ..lineTo(cx - 4, cy + 24)
      ..lineTo(cx + 2, cy + 22)
      ..lineTo(cx - 2, cy + 34);
    canvas.drawPath(bolt, boltPaint);

    // Bolt glow
    canvas.drawPath(
      bolt,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.3)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Small secondary bolt
    final bolt2 = Path()
      ..moveTo(cx + 14, cy + 12)
      ..lineTo(cx + 11, cy + 22)
      ..lineTo(cx + 14, cy + 20)
      ..lineTo(cx + 12, cy + 28);
    canvas.drawPath(
      bolt2,
      Paint()
        ..color = AppColors.electricBlue.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Rain dots
    final rainPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final rx = cx - 14.0 + i * 10;
      final ry = cy + 14.0 + (i % 3) * 5;
      canvas.drawLine(Offset(rx, ry), Offset(rx - 0.5, ry + 4), rainPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Bubbles icon painter (compact, fits 88x88 circle) ────────────────────

class _BubblesIconPainter extends CustomPainter {
  const _BubblesIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Main bubble
    final mainPaint = Paint()
      ..color = const Color(0xFF00D4FF).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy - 2), 18, mainPaint);
    // Highlight
    canvas.drawCircle(
      Offset(cx - 5, cy - 10),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    // Border
    canvas.drawCircle(
      Offset(cx, cy - 2),
      18,
      Paint()
        ..color = const Color(0xFF00D4FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Small bubble 1
    canvas.drawCircle(Offset(cx - 18, cy + 12), 8, mainPaint);
    canvas.drawCircle(
      Offset(cx - 20, cy + 9),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      Offset(cx - 18, cy + 12),
      8,
      Paint()
        ..color = const Color(0xFFFF69B4).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Small bubble 2
    canvas.drawCircle(
      Offset(cx + 16, cy + 10),
      10,
      Paint()..color = const Color(0xFF90EE90).withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(cx + 13, cy + 6),
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    // Word text in main bubble
    final tp = TextPainter(
      text: TextSpan(
        text: 'abc',
        style: AppFonts.fredoka(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Cards icon painter (compact, fits 88x88 circle) ──────────────────────

class _CardsIconPainter extends CustomPainter {
  const _CardsIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Back card (rotated slightly)
    canvas.save();
    canvas.translate(cx + 4, cy);
    canvas.rotate(0.15);
    final backCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-14, -18, 28, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      backCard,
      Paint()..color = const Color(0xFF2D1B69),
    );
    canvas.drawRRect(
      backCard,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Question mark
    final tp1 = TextPainter(
      text: TextSpan(
        text: '?',
        style: AppFonts.fredoka(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.violet.withValues(alpha: 0.3),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(-tp1.width / 2, -tp1.height / 2));
    canvas.restore();

    // Front card (face up)
    canvas.save();
    canvas.translate(cx - 6, cy + 2);
    canvas.rotate(-0.1);
    final frontCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-14, -18, 28, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      frontCard,
      Paint()..color = const Color(0xFFF8F8FF),
    );
    canvas.drawRRect(
      frontCard,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Star on front
    canvas.drawCircle(
      Offset.zero,
      3,
      Paint()..color = AppColors.starGold,
    );
    // Word
    final tp2 = TextPainter(
      text: TextSpan(
        text: 'the',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2A2A4A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(-tp2.width / 2, 6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Falling letters icon painter (compact, fits 88x88 circle) ────────────

class _FallingIconPainter extends CustomPainter {
  const _FallingIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Falling letter tiles
    final letters = ['A', 'B', 'C'];
    final offsets = [
      Offset(cx - 16, cy - 14),
      Offset(cx + 2, cy - 4),
      Offset(cx + 14, cy + 8),
    ];
    final rotations = [-0.15, 0.08, -0.1];
    final alphas = [0.9, 1.0, 0.7];

    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(offsets[i].dx, offsets[i].dy);
      canvas.rotate(rotations[i]);

      // Tile background
      final tileRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -12, 20, 24),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        tileRect,
        Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: alphas[i]),
      );
      canvas.drawRRect(
        tileRect,
        Paint()
          ..color = AppColors.electricBlue.withValues(alpha: 0.5 * alphas[i])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Letter text
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: AppFonts.fredoka(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.electricBlue.withValues(alpha: alphas[i]),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Sparkle trail from top letter
    _drawSparkle(canvas, Offset(cx - 16, cy - 26), 2, AppColors.starGold);
    _drawSparkle(canvas, Offset(cx + 6, cy - 16), 1.5, AppColors.electricBlue);

    // Slots at bottom
    final slotPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final sx = cx - 16.0 + i * 16;
      canvas.drawLine(Offset(sx, cy + 22), Offset(sx + 10, cy + 22), slotPaint);
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Cat icon painter (compact, fits 88x88 circle) ────────────────────────

class _CatIconPainter extends CustomPainter {
  const _CatIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow aura
    canvas.drawCircle(
      Offset(cx, cy),
      28,
      Paint()
        ..color = AppColors.magenta.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Body
    final bodyPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 6), width: 32, height: 24),
      bodyPaint,
    );

    // Head
    canvas.drawCircle(Offset(cx, cy - 8), 14, bodyPaint);

    // Ears
    final earPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..style = PaintingStyle.fill;
    final leftEar = Path()
      ..moveTo(cx - 12, cy - 14)
      ..lineTo(cx - 8, cy - 26)
      ..lineTo(cx - 2, cy - 14)
      ..close();
    final rightEar = Path()
      ..moveTo(cx + 2, cy - 14)
      ..lineTo(cx + 8, cy - 26)
      ..lineTo(cx + 12, cy - 14)
      ..close();
    canvas.drawPath(leftEar, earPaint);
    canvas.drawPath(rightEar, earPaint);

    // Inner ears
    final innerEarPaint = Paint()
      ..color = const Color(0xFFFFB8D9)
      ..style = PaintingStyle.fill;
    final leftInner = Path()
      ..moveTo(cx - 10, cy - 15)
      ..lineTo(cx - 8, cy - 22)
      ..lineTo(cx - 4, cy - 15)
      ..close();
    final rightInner = Path()
      ..moveTo(cx + 4, cy - 15)
      ..lineTo(cx + 8, cy - 22)
      ..lineTo(cx + 10, cy - 15)
      ..close();
    canvas.drawPath(leftInner, innerEarPaint);
    canvas.drawPath(rightInner, innerEarPaint);

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFF2A1040);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy - 8), width: 5, height: 6),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy - 8), width: 5, height: 6),
      eyePaint,
    );
    // Eye shine
    canvas.drawCircle(
      Offset(cx - 4, cy - 9),
      1.2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx + 6, cy - 9),
      1.2,
      Paint()..color = Colors.white,
    );

    // Nose
    canvas.drawCircle(
      Offset(cx, cy - 4),
      1.5,
      Paint()..color = const Color(0xFFFF6BA8),
    );

    // Whiskers
    final whiskerPaint = Paint()
      ..color = const Color(0xFFFFCDE0)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 4, cy - 3), Offset(cx - 18, cy - 6), whiskerPaint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 17, cy), whiskerPaint);
    canvas.drawLine(Offset(cx + 4, cy - 3), Offset(cx + 18, cy - 6), whiskerPaint);
    canvas.drawLine(Offset(cx + 4, cy - 2), Offset(cx + 17, cy), whiskerPaint);

    // Tail
    final tailPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tail = Path()
      ..moveTo(cx + 14, cy + 10)
      ..quadraticBezierTo(cx + 24, cy + 4, cx + 20, cy - 4);
    canvas.drawPath(tail, tailPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Drop icon painter (compact, fits 88x88 circle) ───────────────────────

class _DropIconPainter extends CustomPainter {
  const _DropIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Letter bubble at top
    final bubblePaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy - 12), 12, bubblePaint);
    canvas.drawCircle(
      Offset(cx, cy - 12),
      12,
      Paint()
        ..color = AppColors.emerald.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Letter "A" in bubble
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: AppFonts.fredoka(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.emerald,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - 12 - tp.height / 2));

    // Downward arrow / motion lines
    final arrowPaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // Motion trails
    canvas.drawLine(Offset(cx - 6, cy + 2), Offset(cx - 6, cy + 8), arrowPaint);
    canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + 12), arrowPaint);
    canvas.drawLine(Offset(cx + 6, cy + 2), Offset(cx + 6, cy + 8), arrowPaint);

    // Slot shelf at bottom
    final shelfPaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 18, cy + 18), Offset(cx + 18, cy + 18), shelfPaint);
    // Slot dividers
    canvas.drawLine(Offset(cx - 6, cy + 14), Offset(cx - 6, cy + 18), shelfPaint);
    canvas.drawLine(Offset(cx + 6, cy + 14), Offset(cx + 6, cy + 18), shelfPaint);

    // Small bouncing letter
    final smallBubble = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 16, cy - 2), 7, smallBubble);
    final tp2 = TextPainter(
      text: TextSpan(
        text: 'B',
        style: AppFonts.fredoka(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: AppColors.starGold.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx + 16 - tp2.width / 2, cy - 2 - tp2.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Rhyme icon painter (compact, fits 88x88 circle) ──────────────────────

class _RhymeIconPainter extends CustomPainter {
  const _RhymeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Two overlapping speech bubbles
    final bubble1 = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx - 8, cy - 6), width: 32, height: 24),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bubble1,
      Paint()..color = AppColors.magenta.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      bubble1,
      Paint()
        ..color = AppColors.magenta.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tail for bubble 1
    final tail1 = Path()
      ..moveTo(cx - 14, cy + 4)
      ..lineTo(cx - 20, cy + 14)
      ..lineTo(cx - 6, cy + 4);
    canvas.drawPath(
      tail1,
      Paint()..color = AppColors.magenta.withValues(alpha: 0.3),
    );

    final bubble2 = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + 8, cy + 2), width: 32, height: 24),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bubble2,
      Paint()..color = AppColors.violet.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      bubble2,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tail for bubble 2
    final tail2 = Path()
      ..moveTo(cx + 14, cy + 12)
      ..lineTo(cx + 20, cy + 22)
      ..lineTo(cx + 6, cy + 12);
    canvas.drawPath(
      tail2,
      Paint()..color = AppColors.violet.withValues(alpha: 0.3),
    );

    // Text in bubbles
    final tp1 = TextPainter(
      text: TextSpan(
        text: 'cat',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.magenta,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(cx - 8 - tp1.width / 2, cy - 6 - tp1.height / 2));

    final tp2 = TextPainter(
      text: TextSpan(
        text: 'hat',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.violet,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx + 8 - tp2.width / 2, cy + 2 - tp2.height / 2));

    // Musical note sparkles
    _drawNote(canvas, Offset(cx - 16, cy - 18), AppColors.magenta);
    _drawNote(canvas, Offset(cx + 18, cy - 12), AppColors.violet);
  }

  void _drawNote(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Note stem
    canvas.drawLine(Offset(c.dx + 3, c.dy), Offset(c.dx + 3, c.dy - 8), p);
    // Note head
    canvas.drawCircle(Offset(c.dx + 1, c.dy + 1), 2.5,
        Paint()..color = color.withValues(alpha: 0.7));
    // Flag
    final flag = Path()
      ..moveTo(c.dx + 3, c.dy - 8)
      ..quadraticBezierTo(c.dx + 8, c.dy - 6, c.dx + 5, c.dy - 3);
    canvas.drawPath(flag, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Star Catcher icon painter (compact, fits 88x88 circle) ───────────────

class _StarCatcherIconPainter extends CustomPainter {
  const _StarCatcherIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dark sky background circle
    canvas.drawCircle(
      Offset(cx, cy),
      30,
      Paint()..color = const Color(0xFF0D0D2B).withValues(alpha: 0.4),
    );

    // Stars (5-pointed)
    _drawMiniStar(canvas, Offset(cx - 12, cy - 10), 8, AppColors.starGold);
    _drawMiniStar(canvas, Offset(cx + 10, cy - 6), 6, AppColors.electricBlue);
    _drawMiniStar(canvas, Offset(cx + 2, cy + 8), 7, AppColors.violet);
    _drawMiniStar(canvas, Offset(cx - 8, cy + 12), 5, const Color(0xFF00E68A));

    // Constellation lines
    final linePaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 12, cy - 10), Offset(cx + 10, cy - 6), linePaint);
    canvas.drawLine(Offset(cx + 10, cy - 6), Offset(cx + 2, cy + 8), linePaint);

    // Small letter on one star
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: AppFonts.fredoka(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A0A00),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 12 - tp.width / 2, cy - 10 - tp.height / 2));

    // Tiny sparkles
    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 18, cy - 16), Offset(cx + 22, cy - 16), sparklePaint);
    canvas.drawLine(Offset(cx + 20, cy - 18), Offset(cx + 20, cy - 14), sparklePaint);
  }

  void _drawMiniStar(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * pi / 5) - pi / 2;
      final sr = i.isEven ? r : r * 0.45;
      final x = center.dx + cos(angle) * sr;
      final y = center.dy + sin(angle) * sr;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Paint Splash icon painter (compact, fits 88x88 circle) ───────────────

class _PaintSplashIconPainter extends CustomPainter {
  const _PaintSplashIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Canvas / easel frame
    final framePaint = Paint()
      ..color = const Color(0xFFDDCCBB).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 36),
        const Radius.circular(4),
      ),
      framePaint,
    );
    // Canvas fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 36),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFFFF8F0).withValues(alpha: 0.6),
    );

    // Paint splats
    canvas.drawCircle(Offset(cx - 8, cy - 4), 7,
        Paint()..color = const Color(0xFFFF4D6A).withValues(alpha: 0.7));
    canvas.drawCircle(Offset(cx + 6, cy + 2), 6,
        Paint()..color = const Color(0xFF4D9FFF).withValues(alpha: 0.7));
    canvas.drawCircle(Offset(cx - 2, cy + 6), 5,
        Paint()..color = const Color(0xFF4DFF88).withValues(alpha: 0.6));
    canvas.drawCircle(Offset(cx + 10, cy - 6), 4,
        Paint()..color = const Color(0xFFFFD74D).withValues(alpha: 0.7));

    // Paint brush
    final brushPaint = Paint()
      ..color = const Color(0xFF8B6914)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 14, cy - 14), Offset(cx + 4, cy - 2), brushPaint);
    // Brush tip
    canvas.drawCircle(Offset(cx + 4, cy - 2), 2.5,
        Paint()..color = const Color(0xFFFF4D6A));

    // Letter in a splat
    final tp = TextPainter(
      text: TextSpan(
        text: 'B',
        style: AppFonts.fredoka(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 8 - tp.width / 2, cy - 4 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Rocket icon painter (compact, fits 88x88 circle) ──────────────────────

class _RocketIconPainter extends CustomPainter {
  const _RocketIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Rocket body
    final bodyPaint = Paint()
      ..color = const Color(0xFFE0E0FF)
      ..style = PaintingStyle.fill;
    final body = Path()
      ..moveTo(cx, cy - 22)
      ..quadraticBezierTo(cx + 10, cy - 8, cx + 8, cy + 12)
      ..lineTo(cx - 8, cy + 12)
      ..quadraticBezierTo(cx - 10, cy - 8, cx, cy - 22);
    canvas.drawPath(body, bodyPaint);

    // Window
    canvas.drawCircle(
      Offset(cx, cy - 6),
      4,
      Paint()..color = AppColors.electricBlue.withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      Offset(cx - 1.5, cy - 7.5),
      1.5,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // Fins
    final finPaint = Paint()..color = const Color(0xFFFF4757);
    final leftFin = Path()
      ..moveTo(cx - 8, cy + 6)
      ..lineTo(cx - 16, cy + 16)
      ..lineTo(cx - 5, cy + 12)
      ..close();
    final rightFin = Path()
      ..moveTo(cx + 8, cy + 6)
      ..lineTo(cx + 16, cy + 16)
      ..lineTo(cx + 5, cy + 12)
      ..close();
    canvas.drawPath(leftFin, finPaint);
    canvas.drawPath(rightFin, finPaint);

    // Nose cone
    canvas.drawCircle(
      Offset(cx, cy - 20),
      2.5,
      Paint()..color = AppColors.starGold,
    );

    // Flame
    final flamePaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final flame = Path()
      ..moveTo(cx - 5, cy + 12)
      ..quadraticBezierTo(cx, cy + 26, cx + 5, cy + 12);
    canvas.drawPath(flame, flamePaint);

    // Stars around
    _drawSparkle(canvas, Offset(cx - 18, cy - 14), 2, AppColors.electricBlue);
    _drawSparkle(canvas, Offset(cx + 16, cy - 16), 2.5, AppColors.starGold);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Safari icon painter (compact, fits 88x88 circle) ──────────────────────

class _SafariIconPainter extends CustomPainter {
  const _SafariIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Tree trunk
    canvas.drawLine(
      Offset(cx - 14, cy + 8),
      Offset(cx - 14, cy - 4),
      Paint()
        ..color = const Color(0xFF8B6914)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // Foliage
    canvas.drawCircle(
      Offset(cx - 14, cy - 10),
      10,
      Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(cx - 8, cy - 14),
      7,
      Paint()..color = const Color(0xFF059669).withValues(alpha: 0.5),
    );

    // Elephant body
    final elephantPaint = Paint()
      ..color = const Color(0xFF8E8E8E)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 6, cy + 4), width: 24, height: 18),
      elephantPaint,
    );
    // Head
    canvas.drawCircle(Offset(cx + 16, cy - 2), 8, elephantPaint);
    // Trunk
    final trunk = Path()
      ..moveTo(cx + 22, cy)
      ..quadraticBezierTo(cx + 28, cy + 6, cx + 24, cy + 14);
    canvas.drawPath(
      trunk,
      Paint()
        ..color = const Color(0xFF8E8E8E)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    // Eye
    canvas.drawCircle(
      Offset(cx + 18, cy - 3),
      1.5,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    // Legs
    final legPaint = Paint()
      ..color = const Color(0xFF7A7A7A)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy + 12), Offset(cx, cy + 20), legPaint);
    canvas.drawLine(Offset(cx + 6, cy + 12), Offset(cx + 6, cy + 20), legPaint);
    canvas.drawLine(Offset(cx + 10, cy + 12), Offset(cx + 10, cy + 20), legPaint);

    // Word card
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + 6, cy - 18), width: 26, height: 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(cardRect, Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = AppColors.emerald.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: 'the',
        style: AppFonts.fredoka(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2A2A4A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx + 6 - tp.width / 2, cy - 18 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Ninja icon painter (compact, fits 88x88 circle) ──────────────────────

class _NinjaIconPainter extends CustomPainter {
  const _NinjaIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Slash lines
    final slashPaint = Paint()
      ..color = AppColors.magenta.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 20, cy + 10), Offset(cx + 20, cy - 14), slashPaint);
    canvas.drawLine(Offset(cx - 16, cy - 8), Offset(cx + 18, cy + 12), slashPaint);

    // Word pills
    _drawWordPill(canvas, Offset(cx - 8, cy - 10), 'go', AppColors.magenta, true);
    _drawWordPill(canvas, Offset(cx + 8, cy + 8), 'it', AppColors.surface, false);

    // Ink splat
    canvas.drawCircle(
      Offset(cx + 14, cy - 4),
      6,
      Paint()
        ..color = AppColors.magenta.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Sparkle
    _drawSparkle(canvas, Offset(cx - 16, cy - 18), 2, AppColors.starGold);
  }

  void _drawWordPill(Canvas canvas, Offset center, String text, Color bg, bool glow) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final w = tp.width + 14;
    final h = tp.height + 8;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = bg.withValues(alpha: 0.8));
    if (glow) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = bg.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Bee icon painter (compact, fits 88x88 circle) ─────────────────────────

class _BeeIconPainter extends CustomPainter {
  const _BeeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Honeycomb hexagons background
    _drawHex(canvas, Offset(cx - 10, cy - 10), 10, const Color(0xFFFFD700).withValues(alpha: 0.15));
    _drawHex(canvas, Offset(cx + 8, cy - 6), 10, const Color(0xFFFFD700).withValues(alpha: 0.1));
    _drawHex(canvas, Offset(cx - 2, cy + 8), 10, const Color(0xFFFFD700).withValues(alpha: 0.12));

    // Hex borders
    _drawHexBorder(canvas, Offset(cx - 10, cy - 10), 10, AppColors.starGold.withValues(alpha: 0.4));
    _drawHexBorder(canvas, Offset(cx + 8, cy - 6), 10, AppColors.starGold.withValues(alpha: 0.3));
    _drawHexBorder(canvas, Offset(cx - 2, cy + 8), 10, AppColors.starGold.withValues(alpha: 0.35));

    // Letters in hexes
    _drawHexLetter(canvas, Offset(cx - 10, cy - 10), 'c', AppColors.starGold);
    _drawHexLetter(canvas, Offset(cx + 8, cy - 6), 'a', AppColors.starGold);
    _drawHexLetter(canvas, Offset(cx - 2, cy + 8), 't', AppColors.starGold);

    // Bee
    final bx = cx + 16.0;
    final by = cy - 16.0;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bx, by), width: 10, height: 7),
      Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.8),
    );
    canvas.drawLine(
      Offset(bx - 1, by - 3),
      Offset(bx - 1, by + 3),
      Paint()
        ..color = const Color(0xFF2A1A00).withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(bx + 2, by - 2),
      Offset(bx + 2, by + 2),
      Paint()
        ..color = const Color(0xFF2A1A00).withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    // Wings
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bx - 2, by - 5), width: 6, height: 4),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bx + 2, by - 5), width: 6, height: 4),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _drawHex(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * pi / 180;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawHexBorder(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * pi / 180;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawHexLetter(Canvas canvas, Offset center, String letter, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: letter,
        style: AppFonts.fredoka(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Train icon painter (compact, fits 88x88 circle) ──────────────────────

class _TrainIconPainter extends CustomPainter {
  const _TrainIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Track
    canvas.drawLine(
      Offset(cx - 28, cy + 14),
      Offset(cx + 28, cy + 14),
      Paint()
        ..color = const Color(0xFF4A3520).withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Engine body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 22, cy - 4, 22, 16),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFCC3333),
    );
    // Cabin
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 8, cy - 12, 10, 8),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFDD4444),
    );
    // Chimney
    canvas.drawRect(
      Rect.fromLTWH(cx - 18, cy - 10, 5, 6),
      Paint()..color = const Color(0xFF2A2A2A),
    );
    // Smoke puff
    canvas.drawCircle(
      Offset(cx - 16, cy - 16),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(cx - 12, cy - 20),
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.2),
    );

    // Wheels
    canvas.drawCircle(Offset(cx - 16, cy + 12), 4, Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawCircle(Offset(cx - 6, cy + 12), 4, Paint()..color = const Color(0xFF2A2A2A));

    // Car with letter
    final carX = cx + 4.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(carX, cy - 2, 20, 14),
        const Radius.circular(3),
      ),
      Paint()..color = AppColors.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(carX, cy - 2, 20, 14),
        const Radius.circular(3),
      ),
      Paint()
        ..color = AppColors.electricBlue.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Letter in car
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: AppFonts.fredoka(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.electricBlue,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(carX + 10 - tp.width / 2, cy + 5 - tp.height / 2));

    // Car wheels
    canvas.drawCircle(Offset(carX + 5, cy + 12), 3, Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawCircle(Offset(carX + 15, cy + 12), 3, Paint()..color = const Color(0xFF2A2A2A));

    // Coupling
    canvas.drawLine(
      Offset(cx, cy + 5),
      Offset(carX, cy + 5),
      Paint()
        ..color = const Color(0xFF666666)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Ladybug icon painter (compact, fits 88x88 circle) ─────────────────────

class _LadybugIconPainter extends CustomPainter {
  const _LadybugIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Legs
    final legPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final yOff = cy - 6.0 + i * 6.0;
      canvas.drawLine(Offset(cx - 10, yOff), Offset(cx - 16, yOff + 3), legPaint);
      canvas.drawLine(Offset(cx + 10, yOff), Offset(cx + 16, yOff + 3), legPaint);
    }

    // Shell
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 2), width: 24, height: 28),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFF3333), Color(0xFFCC1111)],
        ).createShader(
          Rect.fromCenter(center: Offset(cx, cy + 2), width: 24, height: 28),
        ),
    );

    // Center line
    canvas.drawLine(
      Offset(cx, cy - 10),
      Offset(cx, cy + 14),
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..strokeWidth = 1,
    );

    // Spots
    final spotPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(Offset(cx - 4, cy - 2), 2.5, spotPaint);
    canvas.drawCircle(Offset(cx + 4, cy - 2), 2.5, spotPaint);
    canvas.drawCircle(Offset(cx - 5, cy + 6), 2, spotPaint);
    canvas.drawCircle(Offset(cx + 5, cy + 6), 2, spotPaint);

    // Head
    canvas.drawCircle(
      Offset(cx, cy - 12),
      7,
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Eyes
    canvas.drawCircle(Offset(cx - 2.5, cy - 13), 1.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + 2.5, cy - 13), 1.5, Paint()..color = Colors.white);

    // Antennae
    final antennaePaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final leftA = Path()
      ..moveTo(cx - 2, cy - 18)
      ..quadraticBezierTo(cx - 8, cy - 26, cx - 6, cy - 28);
    canvas.drawPath(leftA, antennaePaint);
    canvas.drawCircle(Offset(cx - 6, cy - 28), 1.5, Paint()..color = const Color(0xFF1A1A1A));
    final rightA = Path()
      ..moveTo(cx + 2, cy - 18)
      ..quadraticBezierTo(cx + 8, cy - 26, cx + 6, cy - 28);
    canvas.drawPath(rightA, antennaePaint);
    canvas.drawCircle(Offset(cx + 6, cy - 28), 1.5, Paint()..color = const Color(0xFF1A1A1A));

    // Leaf
    final leafPath = Path()
      ..moveTo(cx + 18, cy + 8)
      ..quadraticBezierTo(cx + 26, cy + 2, cx + 22, cy - 4)
      ..quadraticBezierTo(cx + 14, cy + 2, cx + 18, cy + 8);
    canvas.drawPath(leafPath, Paint()..color = const Color(0xFF40916C).withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Floating particles ────────────────────────────────────────────────────

class _MiniGameParticles extends StatefulWidget {
  const _MiniGameParticles();

  @override
  State<_MiniGameParticles> createState() => _MiniGameParticlesState();
}

class _MiniGameParticlesState extends State<_MiniGameParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    final rng = Random(42);
    _particles = List.generate(10, (_) => _Particle(rng));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            time: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  final double x, y, speed, phase, size;
  final Color color;

  _Particle(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.2 + rng.nextDouble() * 0.5,
        phase = rng.nextDouble() * 2 * pi,
        size = 1.5 + rng.nextDouble() * 2.0,
        color = [
          AppColors.magenta,
          AppColors.violet,
          AppColors.electricBlue,
          AppColors.starGold,
        ][rng.nextInt(4)];
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;

  _ParticlePainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = time * p.speed + p.phase;
      final x = (p.x + sin(t * 2 * pi) * 0.03) * size.width;
      final y = (p.y + cos(t * 2 * pi * 0.7) * 0.02) * size.height;
      final alpha = (0.2 + sin(t * 2 * pi * 2) * 0.2).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

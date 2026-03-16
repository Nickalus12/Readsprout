import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../services/streak_service.dart';
import '../services/high_score_service.dart';
import '../services/stats_service.dart';
import '../services/avatar_personality_service.dart';
import '../services/adaptive_music_service.dart';
import '../services/review_service.dart';
import '../avatar/avatar_widget.dart';
import '../widgets/floating_hearts_bg.dart';
import '../widgets/streak_badge.dart';
import 'level_select_screen.dart';
import 'alphabet_screen.dart';
import 'mini_games_screen.dart';
import 'parent_dashboard_screen.dart';
import 'profile_screen.dart';
import '../services/adaptive_difficulty_service.dart';

class HomeScreen extends StatefulWidget {
  final ProfileService? profileService;
  final ProgressService progressService;
  final AudioService audioService;
  final StreakService streakService;
  final HighScoreService highScoreService;
  final StatsService? statsService;
  final AvatarPersonalityService? personalityService;
  final ReviewService? reviewService;
  final AdaptiveDifficultyService? adaptiveDifficultyService;
  final AdaptiveMusicService? musicService;
  final String playerName;
  final String profileId;
  final VoidCallback? onChangeName;
  final VoidCallback? onSignOut;

  const HomeScreen({
    super.key,
    this.profileService,
    required this.progressService,
    required this.audioService,
    required this.streakService,
    required this.highScoreService,
    this.statsService,
    this.personalityService,
    this.reviewService,
    this.adaptiveDifficultyService,
    this.musicService,
    this.playerName = '',
    this.profileId = '',
    this.onChangeName,
    this.onSignOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  bool _hasPlayedWelcome = false;
  late AnimationController _logoController;
  late Ticker _starTicker;
  late _StarSim _starSim;
  final _heartsKey = GlobalKey<FloatingHeartsBackgroundState>();
  final AvatarController _avatarController = AvatarController();

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _starSim = _StarSim();
    _starTicker = createTicker(_starSim.tick)..start();
    // Bind avatar lip sync to audio amplitude
    _avatarController.bindAmplitude(widget.audioService.mouthAmplitude);
    // Check streak status on app open
    widget.streakService.checkStreak();
    // Play welcome phrase on first load
    if (widget.playerName.isNotEmpty && !_hasPlayedWelcome) {
      _hasPlayedWelcome = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          widget.audioService.playWelcome(widget.playerName);
          _avatarController.setExpression(AvatarExpression.happy,
              duration: const Duration(seconds: 3));
        }
      });
    }
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _starTicker.dispose();
    _starSim.dispose();
    _logoController.dispose();
    super.dispose();
  }

  void _onLogoTap() {
    widget.audioService.playWord('reading_sprout');
    _logoController.forward(from: 0);
  }

  void _showMilestone(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              color: AppColors.starGold,
            ),
            const SizedBox(width: 8),
            Text(
              message,
              style: AppFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppColors.starGold.withValues(alpha: 0.5),
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Called externally (e.g. from app.dart) when a streak milestone is reached.
  void showStreakMilestone(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMilestone(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalStars = widget.progressService.totalStars;
    final totalWords = widget.progressService.totalWordsCompleted;
    final hasName = widget.playerName.isNotEmpty;
    final screenW = MediaQuery.of(context).size.width;
    // Scale factor: 1.0 on a ~400dp wide phone, smaller on narrower screens
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _starSim.tapAt(event.localPosition);
          _heartsKey.currentState?.tapAt(event.localPosition);
        },
        child: Stack(
        children: [
          // ── Background gradient ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  AppColors.backgroundEnd,
                ],
              ),
            ),
          ),

          // ── Floating hearts + cloud physics layer ───────────
          ExcludeSemantics(
            child: Positioned.fill(
              child: FloatingHeartsBackground(
                key: _heartsKey,
                cloudZoneHeight: 0.18,
              ),
            ),
          ),

          // ── Floating stars (IgnorePointer — taps pass through) ──
          ExcludeSemantics(
            child: Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: LayoutBuilder(builder: (context, constraints) {
                    _starSim.size = constraints.biggest;
                    return CustomPaint(
                      size: constraints.biggest,
                      painter: _StarPainter(sim: _starSim),
                    );
                  }),
                ),
              ),
            ),
          ),

          // ── Parent Dashboard button (top-right, subtle) ────
          if (widget.statsService != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Semantics(
                label: 'Parent dashboard',
                hint: 'Opens parent settings and stats',
                button: true,
                child: GestureDetector(
                  onTap: () => _showParentGate(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: AppColors.secondaryText.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

          // ── Foreground content ──────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.06),

                    // ── Logo (tappable with bounce + glow) ──
                    Semantics(
                      label: 'Reading Sprout logo',
                      hint: 'Tap to hear the app name',
                      button: true,
                      child: GestureDetector(
                      onTap: _onLogoTap,
                      child: AnimatedBuilder(
                        animation: _logoController,
                        builder: (context, child) {
                          final t = _logoController.value;
                          final bounce = 1.0 + sin(t * pi) * 0.08;
                          final glow = sin(t * pi);
                          return Transform.scale(
                            scale: bounce,
                            child: Container(
                              decoration: glow > 0.01
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.electricBlue
                                              .withValues(alpha: glow * 0.25),
                                          blurRadius: 16 * glow,
                                          spreadRadius: 2 * glow,
                                        ),
                                      ],
                                    )
                                  : null,
                              child: child,
                            ),
                          );
                        },
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: (widget.profileService != null ? 120 : 160) * sf,
                          height: (widget.profileService != null ? 120 : 160) * sf,
                        ),
                      ),
                    ))
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          curve: Curves.easeOutCubic,
                          duration: 600.ms,
                        ),

                    const SizedBox(height: 12),

                    // ── Hero: Player name (tappable letters) ──
                    if (hasName)
                      Semantics(
                        label: 'Player name: ${widget.playerName}',
                        hint: 'Tap each letter to hear it',
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            for (int i = 0; i < widget.playerName.length; i++)
                              _TappableNameLetter(
                                letter: widget.playerName[i],
                                index: i,
                                audioService: widget.audioService,
                              ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 800.ms)
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            curve: Curves.easeOutCubic,
                            duration: 800.ms,
                          ),

                    const SizedBox(height: 6),

                    // ── Tagline (tappable words) ────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TappableTagWord(
                          text: 'Hear.',
                          audioWord: 'hear',
                          audioService: widget.audioService,
                        ),
                        const SizedBox(width: 8),
                        _TappableTagWord(
                          text: 'Type.',
                          audioWord: 'type',
                          audioService: widget.audioService,
                        ),
                        const SizedBox(width: 8),
                        _TappableTagWord(
                          text: 'Learn.',
                          audioWord: 'learn',
                          audioService: widget.audioService,
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(
                          delay: hasName ? 500.ms : 400.ms,
                          duration: 600.ms,
                        ),

                    const SizedBox(height: 20),

                    // ── Stat badges ───────────────────────────
                    if (totalWords > 0 || widget.streakService.hasStreak)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (totalWords > 0) ...[
                            _StatBadge(
                              icon: Icons.star_rounded,
                              iconColor: AppColors.starGold,
                              value: '$totalStars',
                              label: 'Stars',
                              audioService: widget.audioService,
                              audioWord: 'stars',
                            ),
                            _StatBadge(
                              icon: Icons.check_circle_rounded,
                              iconColor: AppColors.success,
                              value: '$totalWords',
                              label: 'Words',
                              audioService: widget.audioService,
                              audioWord: 'words',
                            ),
                          ],
                          if (widget.streakService.hasStreak)
                            StreakBadge(
                              currentStreak:
                                  widget.streakService.currentStreak,
                            ),
                        ],
                      )
                          .animate()
                          .fadeIn(delay: 700.ms, duration: 600.ms),

                    const SizedBox(height: 24),

                    // ── Adventure Mode button ────────────────
                    Semantics(
                      label: 'Adventure Mode',
                      hint: 'Begin your word journey',
                      button: true,
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          _smoothRoute(LevelSelectScreen(
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
                          )),
                        ),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16 * sf, vertical: 10 * sf),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.emerald.withValues(alpha: 0.18),
                              AppColors.electricBlue.withValues(alpha: 0.12),
                              AppColors.violet.withValues(alpha: 0.10),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: AppColors.emerald.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.emerald.withValues(alpha: 0.15),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color:
                                  AppColors.electricBlue.withValues(alpha: 0.08),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Small trees flanking the text
                            CustomPaint(
                              size: Size(24 * sf, 24 * sf),
                              painter: const _TreeIconPainter(
                                  mirrored: false),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Adventure Mode',
                                  style: AppFonts.fredoka(
                                    fontSize: 18 * sf,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Begin your word journey',
                                  style: AppFonts.nunito(
                                    fontSize: 10 * sf,
                                    color: AppColors.emerald
                                        .withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            )),
                            const SizedBox(width: 8),
                            CustomPaint(
                              size: Size(24 * sf, 24 * sf),
                              painter: const _TreeIconPainter(
                                  mirrored: true),
                            ),
                          ],
                        ),
                      ),
                    ))
                        .animate(
                          onPlay: (controller) =>
                              controller.repeat(reverse: true),
                        )
                        .scaleXY(
                          begin: 1.0,
                          end: 1.03,
                          duration: 1500.ms,
                          curve: Curves.easeInOut,
                        )
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 500.ms)
                        .slideY(
                          begin: 0.5,
                          end: 0,
                          curve: Curves.easeOutCubic,
                        ),

                    const SizedBox(height: 16),

                    // ── Garden & Mini Games icons ────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.profileService != null)
                          _MenuIconButton(
                            icon: Icons.local_florist_rounded,
                            semanticLabel: 'My Profile',
                            onTap: () => Navigator.push(
                              context,
                              _smoothRoute(ProfileScreen(
                                profileService: widget.profileService!,
                                progressService: widget.progressService,
                                audioService: widget.audioService,
                                streakService: widget.streakService,
                                playerName: widget.playerName,
                                onSignOut: widget.onSignOut,
                              )),
                            ),
                          ),
                        if (widget.profileService != null)
                          const SizedBox(width: 20),
                        _MenuIconButton(
                          icon: Icons.abc_rounded,
                          semanticLabel: 'Alphabet Practice',
                          onTap: () => Navigator.push(
                            context,
                            _smoothRoute(AlphabetScreen(
                              audioService: widget.audioService,
                            )),
                          ),
                        ),
                        const SizedBox(width: 20),
                        _MenuIconButton(
                          icon: Icons.sports_esports_rounded,
                          semanticLabel: 'Mini Games',
                          onTap: () => Navigator.push(
                            context,
                            _smoothRoute(MiniGamesScreen(
                              progressService: widget.progressService,
                              audioService: widget.audioService,
                              highScoreService: widget.highScoreService,
                              playerName: widget.playerName,
                              profileService: widget.profileService,
                              statsService: widget.statsService,
                              personalityService: widget.personalityService,
                              adaptiveDifficultyService: widget.adaptiveDifficultyService,
                              profileId: widget.profileId,
                            )),
                          ),
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(delay: 700.ms, duration: 400.ms)
                        .slideY(
                          begin: 0.15,
                          end: 0,
                          delay: 700.ms,
                          duration: 400.ms,
                          curve: Curves.easeOut,
                        ),

                    SizedBox(height: MediaQuery.of(context).size.height * 0.06),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showParentGate(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ParentGate(
        onVerified: () {
          Navigator.pop(context); // close dialog
          Navigator.push(
            context,
            _smoothRoute(ParentDashboardScreen(
              progressService: widget.progressService,
              statsService: widget.statsService!,
              streakService: widget.streakService,
              highScoreService: widget.highScoreService,
              reviewService: widget.reviewService,
              playerName: widget.playerName,
            )),
          );
        },
      ),
    );
  }

  PageRouteBuilder _smoothRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity:
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}

class _StatBadge extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final AudioService? audioService;
  final String? audioWord;

  const _StatBadge({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.audioService,
    this.audioWord,
  });

  @override
  State<_StatBadge> createState() => _StatBadgeState();
}

class _StatBadgeState extends State<_StatBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _onTap() {
    if (widget.audioService != null && widget.audioWord != null) {
      widget.audioService!.playWord(widget.audioWord!);
      _bounceController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _bounceController,
        builder: (context, child) {
          final scale = 1.0 +
              0.15 * sin(_bounceController.value * pi);
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20, color: widget.iconColor),
              const SizedBox(width: 6),
              Text(
                widget.value,
                style: AppFonts.fredoka(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: AppFonts.nunito(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tappable name letter (electric glow on tap) ──────────────────────

class _TappableNameLetter extends StatefulWidget {
  final String letter;
  final int index;
  final AudioService audioService;

  const _TappableNameLetter({
    required this.letter,
    required this.index,
    required this.audioService,
  });

  @override
  State<_TappableNameLetter> createState() => _TappableNameLetterState();
}

class _TappableNameLetterState extends State<_TappableNameLetter>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _onTap() {
    widget.audioService.playLetter(widget.letter.toLowerCase());
    _glowController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final t = _glowController.value;
          final glow = sin(t * pi);
          final bounce = 1.0 + glow * 0.12;

          // Electric blue glow that fades
          final glowColor = AppColors.electricBlue.withValues(alpha: glow * 0.8);
          final coreColor = Color.lerp(
            Colors.white,
            AppColors.electricBlue,
            glow * 0.4,
          )!;

          final nameSf = (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.2);
          return Transform.scale(
            scale: bounce,
            child: Text(
              widget.letter.toUpperCase(),
              style: AppFonts.fredoka(
                fontSize: 36 * nameSf,
                fontWeight: FontWeight.w700,
                color: glow > 0.01 ? coreColor : Colors.white,
                letterSpacing: 2,
                shadows: [
                  if (glow > 0.01) ...[
                    Shadow(
                      color: glowColor,
                      blurRadius: 24 * glow,
                    ),
                    Shadow(
                      color: AppColors.electricBlue.withValues(alpha: glow * 0.6),
                      blurRadius: 12,
                    ),
                    Shadow(
                      color: AppColors.violet.withValues(alpha: glow * 0.4),
                      blurRadius: 40 * glow,
                    ),
                  ] else ...[
                    Shadow(
                      color: AppColors.magenta.withValues(alpha: 0.7),
                      blurRadius: 28,
                    ),
                    Shadow(
                      color: AppColors.violet.withValues(alpha: 0.5),
                      blurRadius: 56,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Tappable tagline word ──────────────────────────────────────────────

class _TappableTagWord extends StatefulWidget {
  final String text;
  final String audioWord;
  final AudioService audioService;

  const _TappableTagWord({
    required this.text,
    required this.audioWord,
    required this.audioService,
  });

  @override
  State<_TappableTagWord> createState() => _TappableTagWordState();
}

class _TappableTagWordState extends State<_TappableTagWord>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _onTap() {
    widget.audioService.playWord(widget.audioWord);
    _bounceController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _bounceController,
        builder: (context, child) {
          final scale = 1.0 +
              0.2 * sin(_bounceController.value * pi);
          final color = Color.lerp(
            AppColors.secondaryText.withValues(alpha: 0.7),
            AppColors.electricBlue,
            sin(_bounceController.value * pi),
          )!;
          return Transform.scale(
            scale: scale,
            child: Text(
              widget.text,
              style: AppFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Icon-only menu button ──────────────────────────────────────────────

class _MenuIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  const _MenuIconButton({
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  @override
  State<_MenuIconButton> createState() => _MenuIconButtonState();
}

class _MenuIconButtonState extends State<_MenuIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _pressController.forward(),
        onTapUp: (_) => _pressController.reverse(),
        onTapCancel: () => _pressController.reverse(),
        child: AnimatedBuilder(
          animation: _pressController,
          builder: (context, child) {
            final scale = 1.0 - _pressController.value * 0.08;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              size: 26,
              color: AppColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tree icon for Adventure Mode button ─────────────────────────────────

class _TreeIconPainter extends CustomPainter {
  final bool mirrored;
  const _TreeIconPainter({required this.mirrored});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;

    if (mirrored) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    // Trunk
    final trunkPaint = Paint()
      ..color = const Color(0xFF6B4226)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, bottom), Offset(cx, bottom - 10), trunkPaint);

    // Tree layers (3 triangular layers, bottom-up, progressively smaller)
    final treePaint = Paint()..style = PaintingStyle.fill;

    // Bottom layer
    treePaint.color = AppColors.emerald.withValues(alpha: 0.8);
    final layer1 = Path()
      ..moveTo(cx - 12, bottom - 8)
      ..lineTo(cx, bottom - 18)
      ..lineTo(cx + 12, bottom - 8)
      ..close();
    canvas.drawPath(layer1, treePaint);

    // Middle layer
    treePaint.color = const Color(0xFF10B981).withValues(alpha: 0.85);
    final layer2 = Path()
      ..moveTo(cx - 9, bottom - 14)
      ..lineTo(cx, bottom - 22)
      ..lineTo(cx + 9, bottom - 14)
      ..close();
    canvas.drawPath(layer2, treePaint);

    // Top layer
    treePaint.color = const Color(0xFF34D399).withValues(alpha: 0.9);
    final layer3 = Path()
      ..moveTo(cx - 6, bottom - 19)
      ..lineTo(cx, bottom - 27)
      ..lineTo(cx + 6, bottom - 19)
      ..close();
    canvas.drawPath(layer3, treePaint);

    // Star on top
    canvas.drawCircle(
      Offset(cx, bottom - 27),
      1.5,
      Paint()
        ..color = AppColors.starGold
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    if (mirrored) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Star simulation (ChangeNotifier for efficient repaint) ────────────

class _StarSim extends ChangeNotifier {
  final List<_StarParticle> stars = [];
  final List<_StarFlash> flashes = [];
  double time = 0;
  Duration _lastElapsed = Duration.zero;
  Size size = Size.zero;
  bool _disposed = false;

  static const _flashDuration = 0.55;
  static const _flashMaxRadius = 60.0;

  _StarSim() {
    final rng = Random(99);
    for (int i = 0; i < 15; i++) {
      stars.add(_StarParticle(rng));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Offset starScreenPos(_StarParticle star) {
    final t = time * star.speed + star.phase;
    final x = (star.x + sin(t * 2 * pi) * 0.02) * size.width;
    final y = (star.y + cos(t * 2 * pi * 0.6) * 0.015) * size.height;
    return Offset(x, y);
  }

  void tapAt(Offset pos) {
    if (size == Size.zero) return;

    _StarParticle? closest;
    double closestDist = double.infinity;
    Offset closestPos = Offset.zero;

    for (final star in stars) {
      final sPos = starScreenPos(star);
      final dist = (sPos - pos).distance;
      if (dist < 45 && dist < closestDist) {
        closestDist = dist;
        closest = star;
        closestPos = sPos;
      }
    }

    if (closest != null) {
      stars.remove(closest);

      // Purple flash burst (same style as cloud absorbing hearts)
      flashes.add(_StarFlash(x: closestPos.dx, y: closestPos.dy));

      // Respawn after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (_disposed) return;
        stars.add(_StarParticle(Random()));
      });
    }
  }

  void tick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final dt = dtRaw.clamp(0.0, 0.05);
    if (size == Size.zero) return;

    time += dt;

    // Update flashes
    for (int i = flashes.length - 1; i >= 0; i--) {
      flashes[i].elapsed += dt;
      if (flashes[i].elapsed >= _flashDuration) {
        flashes.removeAt(i);
      }
    }

    notifyListeners();
  }
}

class _StarParticle {
  final double x;
  final double y;
  final double speed;
  final double phase;
  final double size;
  final double brightness;

  _StarParticle(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.2 + rng.nextDouble() * 0.6,
        phase = rng.nextDouble() * 2 * pi,
        size = 2.0 + rng.nextDouble() * 3.0,
        brightness = 0.3 + rng.nextDouble() * 0.7;
}

class _StarFlash {
  double x;
  double y;
  double elapsed = 0;
  _StarFlash({required this.x, required this.y});
}

class _StarPainter extends CustomPainter {
  final _StarSim sim;

  _StarPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw stars
    for (final star in sim.stars) {
      final pos = sim.starScreenPos(star);
      final t = sim.time * star.speed + star.phase;
      final alpha =
          (star.brightness * (0.4 + sin(t * 2 * pi * 2.5) * 0.4))
              .clamp(0.0, 1.0);
      _drawStar(canvas, pos, star.size, alpha);
    }

    // Draw purple burst flashes (same effect as cloud absorbing hearts)
    for (final f in sim.flashes) {
      final t =
          (f.elapsed / _StarSim._flashDuration).clamp(0.0, 1.0);
      final curve = Curves.easeOut.transform(t);
      final radius = _StarSim._flashMaxRadius * (0.3 + 0.7 * curve);
      final intensity = t < 0.15
          ? (t / 0.15)
          : 1.0 - ((t - 0.15) / 0.85);
      final alpha = (intensity * 0.55).clamp(0.0, 1.0);
      final center = Offset(f.x, f.y);
      final rect = Rect.fromCircle(center: center, radius: radius);

      // Radial purple glow
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF8B5CF6).withValues(alpha: alpha),
              const Color(0xFFD946EF).withValues(alpha: alpha * 0.5),
              const Color(0xFF8B5CF6).withValues(alpha: 0),
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + radius * 0.2),
      );

      // Bright core
      canvas.drawCircle(
        center,
        radius * 0.2,
        Paint()
          ..color = const Color(0xFFC084FC).withValues(alpha: alpha * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double s, double alpha) {
    // Glow
    canvas.drawCircle(
      center,
      s * 1.5,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.8),
    );
    // Core
    canvas.drawCircle(
      center,
      s * 0.4,
      Paint()..color = Colors.white.withValues(alpha: alpha * 0.9),
    );
    // Cross rays
    final rayPaint = Paint()
      ..color = AppColors.starGold.withValues(alpha: alpha * 0.6)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - s, center.dy),
      Offset(center.dx + s, center.dy),
      rayPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - s),
      Offset(center.dx, center.dy + s),
      rayPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => false;
}

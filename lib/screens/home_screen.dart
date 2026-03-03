import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../services/streak_service.dart';
import '../widgets/floating_hearts_bg.dart';
import '../widgets/streak_badge.dart';
import 'level_select_screen.dart';
import 'word_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final StreakService streakService;
  final String playerName;
  final VoidCallback? onChangeName;

  const HomeScreen({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.streakService,
    this.playerName = '',
    this.onChangeName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasPlayedWelcome = false;

  @override
  void initState() {
    super.initState();
    // Check streak status on app open
    widget.streakService.checkStreak();
    // Play welcome phrase on first load
    if (widget.playerName.isNotEmpty && !_hasPlayedWelcome) {
      _hasPlayedWelcome = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          widget.audioService.playWelcome(widget.playerName);
        }
      });
    }
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
              style: GoogleFonts.fredoka(
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

    return Scaffold(
      body: Stack(
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
          const Positioned.fill(
            child: FloatingHeartsBackground(
              cloudZoneHeight: 0.18,
            ),
          ),

          // ── Foreground content ──────────────────────────────
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // ── Logo ─────────────────────────────────
                    Image.asset(
                      'assets/images/logo.png',
                      width: 180,
                      height: 180,
                    )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          curve: Curves.easeOutCubic,
                          duration: 600.ms,
                        ),

                    const SizedBox(height: 12),

                    // ── Hero: Player name ─────────────────────
                    if (hasName)
                      Text(
                        widget.playerName,
                        style: GoogleFonts.fredoka(
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: AppColors.magenta.withValues(alpha: 0.7),
                              blurRadius: 28,
                            ),
                            Shadow(
                              color: AppColors.violet.withValues(alpha: 0.5),
                              blurRadius: 56,
                            ),
                            Shadow(
                              color: AppColors.electricBlue.withValues(alpha: 0.3),
                              blurRadius: 80,
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
                          )
                          .then()
                          .shimmer(
                            delay: 400.ms,
                            duration: 2000.ms,
                            color: AppColors.electricBlue.withValues(alpha: 0.3),
                          ),

                    const SizedBox(height: 6),

                    // ── Tagline ───────────────────────────────
                    Text(
                      'Hear it. Type it. Learn it!',
                      style: GoogleFonts.nunito(
                        fontSize: hasName ? 15 : 18,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
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
                              label: 'Mastered',
                            ),
                            _StatBadge(
                              icon: Icons.check_circle_rounded,
                              iconColor: AppColors.success,
                              value: '$totalWords',
                              label: 'Words',
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

                    const Spacer(flex: 1),

                    // ── Play button ───────────────────────────
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        _smoothRoute(LevelSelectScreen(
                          progressService: widget.progressService,
                          audioService: widget.audioService,
                          playerName: widget.playerName,
                        )),
                      ),
                      child: Container(
                        width: 220,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.electricBlue.withValues(alpha: 0.15),
                              AppColors.violet.withValues(alpha: 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: AppColors.electricBlue.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.electricBlue.withValues(alpha: 0.15),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Play!',
                              style: GoogleFonts.fredoka(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
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

                    // ── Bottom row: Custom Words + Change Name ─
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            _smoothRoute(const WordEditorScreen()),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          label: Text(
                            'Custom Words',
                            style: GoogleFonts.fredoka(fontSize: 16),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.secondaryText,
                          ),
                        ),
                        if (widget.onChangeName != null) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: widget.onChangeName,
                            icon:
                                const Icon(Icons.person_rounded, size: 20),
                            label: Text(
                              'Name',
                              style: GoogleFonts.fredoka(fontSize: 16),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ).animate().fadeIn(delay: 700.ms),

                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
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

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

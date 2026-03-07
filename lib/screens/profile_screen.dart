import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/daily_treasure.dart';
import '../widgets/sticker_book.dart';
import '../widgets/word_constellation.dart';
import '../widgets/word_garden.dart';
import 'avatar_editor_screen.dart';

/// Main profile screen ("Garden") showing avatar, stats,
/// companion, treasure, garden, stickers, and word constellation.
class ProfileScreen extends StatefulWidget {
  final ProfileService profileService;
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final VoidCallback? onSignOut;

  const ProfileScreen({
    super.key,
    required this.profileService,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.onSignOut,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AvatarConfig _avatar;
  late AnimationController _avatarGlowController;

  @override
  void initState() {
    super.initState();
    _avatar = widget.profileService.avatar;
    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _avatarGlowController.dispose();
    super.dispose();
  }

  int get _wordCount => widget.profileService.totalWordsEverCompleted;
  int get _masteredCount => widget.progressService.totalStars;
  int get _streak => widget.profileService.currentStreak;

  void _openAvatarEditor() async {
    final result = await Navigator.push<AvatarConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarEditorScreen(
          profileService: widget.profileService,
          wordsMastered: _wordCount,
          streakDays: _streak,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _avatar = result);
    }
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

          // Firefly particles
          const Positioned.fill(child: _FireflyBackground()),

          // Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        _buildHeroSection(),
                        const SizedBox(height: 18),
                        DailyTreasure(
                          profileService: widget.profileService,
                          wordsPlayedToday: widget.profileService.wordsPlayedToday,
                          currentStreak: _streak,
                        ).animate().fadeIn(delay: 100.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        WordGarden(
                          progressService: widget.progressService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 200.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        StickerBook(
                          profileService: widget.profileService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 300.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        WordConstellation(
                          progressService: widget.progressService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 400.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 28),
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

  // ── Header ─────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: 28,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.audioService.playWord('garden'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_florist_rounded,
                    size: 20,
                    color: AppColors.emerald.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'My Garden',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fredoka(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onSignOut != null)
            GestureDetector(
              onTap: () {
                // Pop back to home, then trigger sign-out to go to picker
                Navigator.of(context).pop();
                widget.onSignOut!();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.violet.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: AppColors.violet.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Switch',
                      style: GoogleFonts.fredoka(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.violet.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────────

  Widget _buildHeroSection() {
    return Column(
      children: [
        // Avatar + name row — compact side-by-side layout
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar — tap opens editor, with animated glow
            GestureDetector(
              onTap: _openAvatarEditor,
              child: AnimatedBuilder(
                animation: _avatarGlowController,
                builder: (context, child) {
                  final glowAlpha = 0.2 + _avatarGlowController.value * 0.2;
                  final blurRadius = 16.0 + _avatarGlowController.value * 12;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.violet.withValues(alpha: 0.4 + _avatarGlowController.value * 0.2),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.violet.withValues(alpha: glowAlpha),
                              blurRadius: blurRadius,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(2),
                        child: AvatarWidget(config: _avatar, size: 90),
                      ),
                      // Edit badge — small pencil icon
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.violet,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.violet.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(width: 16),

            // Name + stats stacked
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.playerName.isNotEmpty)
                  GestureDetector(
                    onTap: () => widget.audioService.playWelcome(widget.playerName),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.playerName,
                          style: GoogleFonts.fredoka(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: AppColors.magenta.withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.volume_up_rounded,
                          color: AppColors.secondaryText.withValues(alpha: 0.4),
                          size: 16,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                // Inline stats chips with labels
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatChip(Icons.local_florist_rounded, AppColors.emerald, '$_wordCount',
                      label: 'Words',
                      onTap: () => widget.audioService.playWord('words'),
                    ),
                    const SizedBox(width: 8),
                    _StatChip(Icons.star_rounded, AppColors.starGold, '$_masteredCount',
                      label: 'Stars',
                      onTap: () => widget.audioService.playWord('stars'),
                    ),
                    const SizedBox(width: 8),
                    _StatChip(Icons.local_fire_department_rounded, AppColors.flameOrange, '$_streak',
                      label: 'Streak',
                      animate: _streak > 0,
                      onTap: () => widget.audioService.playWord('streak'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
      ],
    );
  }

}

// ── Compact stat chip ─────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String? label;
  final bool animate;
  final VoidCallback? onTap;

  const _StatChip(this.icon, this.color, this.value, {this.label, this.animate = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget chip = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: GoogleFonts.fredoka(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            if (label != null) ...[
              const SizedBox(height: 1),
              Text(
                label!,
                style: GoogleFonts.nunito(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (animate) {
      chip = chip
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.05, duration: 1200.ms);
    }

    return chip;
  }
}

// ── Firefly background (adapted from FloatingHeartsBackground) ─────────

class _FireflyBackground extends StatefulWidget {
  const _FireflyBackground();

  @override
  State<_FireflyBackground> createState() => _FireflyBackgroundState();
}

class _FireflyBackgroundState extends State<_FireflyBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Firefly> _fireflies;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    final rng = Random(42);
    _fireflies = List.generate(20, (_) => _Firefly(rng));
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
          painter: _FireflyPainter(
            fireflies: _fireflies,
            time: _controller.value,
          ),
        );
      },
    );
  }
}

class _Firefly {
  final double x;
  final double y;
  final double speed;
  final double phase;
  final double size;

  _Firefly(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.3 + rng.nextDouble() * 0.7,
        phase = rng.nextDouble() * 2 * pi,
        size = 1.5 + rng.nextDouble() * 2.0;
}

class _FireflyPainter extends CustomPainter {
  final List<_Firefly> fireflies;
  final double time;

  _FireflyPainter({required this.fireflies, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final fly in fireflies) {
      final t = time * fly.speed + fly.phase;
      final x = (fly.x + sin(t * 2 * pi) * 0.03) * size.width;
      final y = (fly.y + cos(t * 2 * pi * 0.7) * 0.02) * size.height;
      final alpha = (0.3 + sin(t * 2 * pi * 1.5) * 0.3).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = AppColors.starGold.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fly.size * 2);

      canvas.drawCircle(Offset(x, y), fly.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireflyPainter oldDelegate) => true;
}

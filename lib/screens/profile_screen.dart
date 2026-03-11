import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/streak_service.dart';
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
  final StreakService streakService;
  final String playerName;
  final VoidCallback? onSignOut;

  const ProfileScreen({
    super.key,
    required this.profileService,
    required this.progressService,
    required this.audioService,
    required this.streakService,
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
  final AvatarController _avatarController = AvatarController();

  @override
  void initState() {
    super.initState();
    _avatar = widget.profileService.avatar;
    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Wire amplitude-based lip sync to avatar
    _avatarController.bindAmplitude(widget.audioService.mouthAmplitude);

    // Greet the child when profile opens
    Future.delayed(const Duration(milliseconds: 600), _greetChild);
  }

  void _greetChild() {
    if (!mounted) return;
    widget.audioService.playWelcome(widget.playerName);
  }

  void _onAvatarTap() {
    _avatarController.setExpression(
      AvatarExpression.excited,
      duration: const Duration(milliseconds: 1200),
    );
    widget.audioService.playSuccess();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _avatarGlowController.dispose();
    super.dispose();
  }

  int get _wordCount => widget.profileService.totalWordsEverCompleted;
  int get _masteredCount => widget.progressService.totalStars;
  int get _streak => widget.streakService.currentStreak;

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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * sf, vertical: 4 * sf),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: 28 * sf,
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
                    size: 20 * sf,
                    color: AppColors.emerald.withValues(alpha: 0.7),
                  ),
                  SizedBox(width: 6 * sf),
                  Text(
                    'My Garden',
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: 22 * sf,
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
                padding: EdgeInsets.symmetric(horizontal: 10 * sf, vertical: 6 * sf),
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14 * sf),
                  border: Border.all(
                    color: AppColors.violet.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18 * sf,
                      color: AppColors.violet.withValues(alpha: 0.8),
                    ),
                    SizedBox(width: 4 * sf),
                    Text(
                      'Switch',
                      style: AppFonts.fredoka(
                        fontSize: 13 * sf,
                        fontWeight: FontWeight.w500,
                        color: AppColors.violet.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(width: 48 * sf),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────────

  Widget _buildHeroSection() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Column(
      children: [
        // Avatar + name row — compact side-by-side layout
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar — tap for reaction, long-press opens editor
            GestureDetector(
              onTap: _onAvatarTap,
              onLongPress: _openAvatarEditor,
              child: AnimatedBuilder(
                animation: _avatarGlowController,
                builder: (context, child) {
                  final glowAlpha = 0.2 + _avatarGlowController.value * 0.2;
                  final blurRadius = 16.0 + _avatarGlowController.value * 12;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 100 * sf,
                        height: 100 * sf,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.violet.withValues(alpha: 0.4 + _avatarGlowController.value * 0.2),
                            width: 2.5 * sf,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.violet.withValues(alpha: glowAlpha),
                              blurRadius: blurRadius,
                              spreadRadius: 3 * sf,
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(2 * sf),
                        child: AvatarWidget(config: _avatar, size: 90 * sf, controller: _avatarController),
                      ),
                      // Edit badge — small pencil icon
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 28 * sf,
                          height: 28 * sf,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.violet,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2 * sf,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.violet.withValues(alpha: 0.4),
                                blurRadius: 8 * sf,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 14 * sf,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            SizedBox(width: 16 * sf),

            // Name + stats stacked
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.playerName.isNotEmpty)
                    GestureDetector(
                      onTap: () => widget.audioService.playWelcome(widget.playerName),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.playerName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: AppFonts.fredoka(
                                fontSize: 28 * sf,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: AppColors.magenta.withValues(alpha: 0.5),
                                    blurRadius: 16 * sf,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 6 * sf),
                          Icon(
                            Icons.volume_up_rounded,
                            color: AppColors.secondaryText.withValues(alpha: 0.4),
                            size: 16 * sf,
                          ),
                        ],
                      ),
                    ),

                SizedBox(height: 10 * sf),

                // Inline stats chips with labels
                Wrap(
                  spacing: 8 * sf,
                  runSpacing: 6 * sf,
                  children: [
                    _StatChip(Icons.local_florist_rounded, AppColors.emerald, '$_wordCount',
                      label: 'Words', sf: sf,
                      onTap: () => widget.audioService.playWord('words'),
                    ),
                    _StatChip(Icons.star_rounded, AppColors.starGold, '$_masteredCount',
                      label: 'Stars', sf: sf,
                      onTap: () => widget.audioService.playWord('stars'),
                    ),
                    _StatChip(Icons.local_fire_department_rounded, AppColors.flameOrange, '$_streak',
                      label: 'Streak', sf: sf,
                      animate: _streak > 0,
                      onTap: () => widget.audioService.playWord('streak'),
                    ),
                  ],
                ),
              ],
            ),
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
  final double sf;
  final VoidCallback? onTap;

  const _StatChip(this.icon, this.color, this.value, {this.label, this.animate = false, this.sf = 1.0, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget chip = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * sf, vertical: 6 * sf),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14 * sf),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8 * sf,
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
                Icon(icon, size: 16 * sf, color: color),
                SizedBox(width: 4 * sf),
                Text(
                  value,
                  style: AppFonts.fredoka(
                    fontSize: 15 * sf,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            if (label != null) ...[
              SizedBox(height: 1 * sf),
              Text(
                label!,
                style: AppFonts.nunito(
                  fontSize: 9 * sf,
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _FireflyPainter(
              fireflies: _fireflies,
              time: _controller.value,
            ),
          );
        },
      ),
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

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class CelebrationOverlay extends StatefulWidget {
  final String word;
  final String playerName;

  const CelebrationOverlay({
    super.key,
    required this.word,
    this.playerName = '',
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final String _praise;

  static const _glowColors = <Color>[
    AppColors.electricBlue,
    AppColors.violet,
    AppColors.magenta,
    AppColors.starGold,
    AppColors.emerald,
    AppColors.cyan,
    AppColors.electricBlue,
  ];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Simple generic praise per word — personalized phrases are for level complete
    const genericPraise = [
      'Great job!',
      'Awesome!',
      'You got it!',
      'Well done!',
      'Perfect!',
      'Nice work!',
      'Way to go!',
      'Fantastic!',
    ];
    _praise = (List.of(genericPraise)..shuffle()).first;
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Color _lerpThroughColors(double t, List<Color> colors) {
    if (colors.length < 2) return colors.first;
    final segmentCount = colors.length - 1;
    final scaledT = t * segmentCount;
    final index = scaledT.floor().clamp(0, segmentCount - 1);
    final localT = scaledT - index;
    return Color.lerp(colors[index], colors[index + 1], localT)!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A1A).withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Word with animated rainbow glow ──────────
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final glowColor = _lerpThroughColors(
                  _glowController.value,
                  _glowColors,
                );
                return Text(
                  widget.word.toUpperCase(),
                  style: AppFonts.fredoka(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 8,
                    shadows: [
                      Shadow(color: glowColor, blurRadius: 28),
                      Shadow(
                        color: glowColor.withValues(alpha: 0.5),
                        blurRadius: 56,
                      ),
                      Shadow(
                        color: glowColor.withValues(alpha: 0.2),
                        blurRadius: 80,
                      ),
                    ],
                  ),
                );
              },
            )
                .animate()
                .scaleXY(
                  begin: 0.3,
                  end: 1.0,
                  curve: Curves.elasticOut,
                  duration: 700.ms,
                )
                .fadeIn(duration: 200.ms)
                .shimmer(
                  delay: 700.ms,
                  duration: 1200.ms,
                  color: Colors.white.withValues(alpha: 0.3),
                ),

            const SizedBox(height: 20),

            // ── Praise in a pill badge ───────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.1),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Text(
                _praise,
                style: AppFonts.fredoka(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: AppColors.success,
                  shadows: [
                    Shadow(
                      color: AppColors.success.withValues(alpha: 0.5),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .scaleXY(
                  begin: 0.4,
                  end: 1.0,
                  delay: 200.ms,
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(delay: 200.ms, duration: 250.ms),

            const SizedBox(height: 20),

            // ── Star burst (3 stars) ─────────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Middle star is slightly larger
                final size = i == 1 ? 28.0 : 22.0;
                final iconSize = i == 1 ? 18.0 : 14.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.starGold,
                          AppColors.starGold.withValues(alpha: 0.6),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.starGold.withValues(alpha: 0.6),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.star_rounded,
                      size: iconSize,
                      color: Colors.white,
                    ),
                  )
                      .animate()
                      .scaleXY(
                        begin: 0,
                        end: 1.0,
                        delay: Duration(milliseconds: 300 + (i * 140)),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      )
                      .rotate(
                        begin: -0.1,
                        end: 0,
                        delay: Duration(milliseconds: 300 + (i * 140)),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      ),
                );
              }),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms);
  }
}

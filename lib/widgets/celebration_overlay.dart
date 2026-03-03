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
                  style: GoogleFonts.fredoka(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 6,
                    shadows: [
                      Shadow(color: glowColor, blurRadius: 24),
                      Shadow(
                        color: glowColor.withValues(alpha: 0.5),
                        blurRadius: 48,
                      ),
                    ],
                  ),
                );
              },
            )
                .animate()
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1.0, 1.0),
                  curve: Curves.elasticOut,
                  duration: 600.ms,
                ),

            const SizedBox(height: 16),

            // ── Praise in a pill badge ───────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _praise,
                style: GoogleFonts.fredoka(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: AppColors.success,
                  shadows: [
                    Shadow(
                      color: AppColors.success.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 250.ms, duration: 400.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 16),

            // ── Star burst (3 stars) ─────────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 22,
                    height: 22,
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
                          color: AppColors.starGold.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0, 0),
                        end: const Offset(1.0, 1.0),
                        delay: Duration(milliseconds: 350 + (i * 120)),
                        duration: 500.ms,
                        curve: Curves.elasticOut,
                      ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

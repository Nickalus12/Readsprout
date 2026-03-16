import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';

/// Overlay shown when a Champion tier word is completed with too many mistakes.
///
/// Offers the child a choice to retry just this word or skip to the next one,
/// instead of forcing a full tier restart.
class ChampionRetryOverlay extends StatelessWidget {
  final String word;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const ChampionRetryOverlay({
    super.key,
    required this.word,
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A1A).withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encouraging icon
              Icon(
                Icons.emoji_events_rounded,
                size: 56,
                color: AppColors.starGold.withValues(alpha: 0.7),
              )
                  .animate()
                  .scaleXY(
                    begin: 0.0,
                    end: 1.0,
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  ),

              const SizedBox(height: 16),

              // "Almost!" title
              Text(
                'Almost!',
                style: AppFonts.fredoka(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.electricBlue,
                  shadows: [
                    Shadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.4),
                      blurRadius: 16,
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 300.ms)
                  .slideY(begin: 0.2, end: 0, delay: 200.ms, duration: 300.ms),

              const SizedBox(height: 8),

              // Word display
              Text(
                '"$word"',
                style: AppFonts.fredoka(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 300.ms),

              const SizedBox(height: 8),

              // Explanation
              Text(
                'Try spelling it with fewer mistakes!',
                textAlign: TextAlign.center,
                style: AppFonts.nunito(
                  fontSize: 15,
                  color: AppColors.secondaryText.withValues(alpha: 0.8),
                ),
              )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 300.ms),

              const SizedBox(height: 28),

              // Action buttons - large and clear for a 4-year-old
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Skip / Continue button (smaller, secondary)
                  GestureDetector(
                    onTap: onSkip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.secondaryText.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.skip_next_rounded,
                            size: 28,
                            color: AppColors.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Skip',
                            style: AppFonts.fredoka(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 300.ms)
                      .slideY(
                          begin: 0.2,
                          end: 0,
                          delay: 500.ms,
                          duration: 300.ms),

                  const SizedBox(width: 20),

                  // Try Again button (prominent, pulsing)
                  GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.electricBlue.withValues(alpha: 0.25),
                            AppColors.violet.withValues(alpha: 0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.electricBlue.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.electricBlue.withValues(alpha: 0.2),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.refresh_rounded,
                            size: 28,
                            color: AppColors.electricBlue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Try Again',
                            style: AppFonts.fredoka(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.electricBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 300.ms)
                      .slideY(
                          begin: 0.2,
                          end: 0,
                          delay: 600.ms,
                          duration: 300.ms)
                      .then(delay: 500.ms)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                        begin: 1.0,
                        end: 1.04,
                        duration: 1200.ms,
                        curve: Curves.easeInOut,
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

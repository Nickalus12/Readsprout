import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'bookworm_companion.dart';

/// Full-screen celebration overlay when a child's bookworm evolves.
///
/// Sequence:
/// 1. Screen dims
/// 2. Old bookworm scales up to center
/// 3. Sparkle particles swirl
/// 4. Flash of white light
/// 5. New bookworm bounces in
/// 6. Confetti explosion
/// 7. Title text: "You're now a [stage title]!"
///
/// Use [EvolutionCelebration.show] to trigger from anywhere.
class EvolutionCelebration extends StatefulWidget {
  /// The word count BEFORE the evolution (old stage).
  final int previousWordCount;

  /// The word count AFTER the evolution (new stage).
  final int newWordCount;

  /// Called when the celebration finishes.
  final VoidCallback? onComplete;

  const EvolutionCelebration({
    super.key,
    required this.previousWordCount,
    required this.newWordCount,
    this.onComplete,
  });

  /// Show the evolution celebration as an overlay.
  ///
  /// Returns when the celebration animation completes.
  static Future<void> show(
    BuildContext context, {
    required int previousWordCount,
    required int newWordCount,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, _, __) {
        return EvolutionCelebration(
          previousWordCount: previousWordCount,
          newWordCount: newWordCount,
          onComplete: () => Navigator.of(context).pop(),
        );
      },
      transitionDuration: Duration.zero,
    );
  }

  /// Check if the word count crosses an evolution boundary.
  ///
  /// Returns the new [BookwormStage] if evolution occurred, null otherwise.
  static BookwormStage? checkEvolution(int oldCount, int newCount) {
    final oldStage = BookwormStage.fromWordCount(oldCount);
    final newStage = BookwormStage.fromWordCount(newCount);
    if (newStage.index > oldStage.index) return newStage;
    return null;
  }

  @override
  State<EvolutionCelebration> createState() => _EvolutionCelebrationState();
}

class _EvolutionCelebrationState extends State<EvolutionCelebration>
    with TickerProviderStateMixin {
  late final ConfettiController _confettiController;
  late final AnimationController _sequenceController;
  late final AnimationController _sparkleController;

  // Animation phases
  bool _showDim = false;
  bool _showOldWorm = false;
  bool _showSparkles = false;
  bool _showFlash = false;
  bool _showNewWorm = false;
  bool _showConfetti = false;
  bool _showTitle = false;

  late final BookwormStage _newStage;

  @override
  void initState() {
    super.initState();

    _newStage = BookwormStage.fromWordCount(widget.newWordCount);

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _sequenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Phase 1: Dim screen (0ms)
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() => _showDim = true);

    // Phase 2: Show old worm scaling up (300ms)
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _showOldWorm = true);

    // Phase 3: Sparkles swirl (800ms)
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _showSparkles = true);

    // Phase 4: Flash of light (1200ms)
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _showFlash = true;
      _showOldWorm = false;
    });

    // Phase 5: New worm bounces in (1600ms)
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _showFlash = false;
      _showNewWorm = true;
      _showSparkles = false;
    });

    // Phase 6: Confetti (1800ms)
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _showConfetti = true);
    _confettiController.play();

    // Phase 7: Title (2200ms)
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _showTitle = true);

    // Auto-dismiss after 3 seconds of viewing
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _confettiController.stop();
    _confettiController.dispose();
    _sequenceController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onComplete,
        child: Stack(
          children: [
            // Dimmed background
            AnimatedOpacity(
              opacity: _showDim ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                color: AppColors.background.withValues(alpha: 0.92),
              ),
            ),

            // Old bookworm scaling up to center
            if (_showOldWorm)
              Center(
                child: BookwormCompanion(
                  wordCount: widget.previousWordCount,
                  size: 140,
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.3, 0.3),
                      end: const Offset(1.0, 1.0),
                      duration: 600.ms,
                      curve: Curves.easeOutBack,
                    )
                    .fadeIn(duration: 300.ms),
              ),

            // Sparkle particles
            if (_showSparkles)
              ...List.generate(12, (i) {
                return _SparkleParticle(
                  index: i,
                  screenSize: screenSize,
                  controller: _sparkleController,
                );
              }),

            // Flash of light
            if (_showFlash)
              Center(
                child: Container(
                  width: screenSize.width,
                  height: screenSize.height,
                  color: Colors.white,
                )
                    .animate()
                    .fadeIn(duration: 150.ms)
                    .then()
                    .fadeOut(duration: 300.ms),
              ),

            // New bookworm bouncing in
            if (_showNewWorm)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BookwormCompanion(
                      wordCount: widget.newWordCount,
                      size: 160,
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.0, 0.0),
                          end: const Offset(1.0, 1.0),
                          duration: 700.ms,
                          curve: Curves.elasticOut,
                        )
                        .fadeIn(duration: 200.ms),
                    if (_showTitle) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _newStage.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _newStage.primaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          "You're now a ${_newStage.title}!",
                          style: AppFonts.fredoka(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: _newStage.primaryColor,
                            shadows: [
                              Shadow(
                                color: _newStage.primaryColor.withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.3, end: 0, duration: 500.ms, curve: Curves.easeOutBack),
                    ],
                    const SizedBox(height: 16),
                    if (_showTitle)
                      Text(
                        'Tap to continue',
                        style: AppFonts.nunito(
                          fontSize: 14,
                          color: AppColors.secondaryText.withValues(alpha: 0.6),
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fadeIn(duration: 800.ms, delay: 500.ms)
                          .fadeOut(delay: 2000.ms, duration: 800.ms),
                  ],
                ),
              ),

            // Confetti
            if (_showConfetti)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  numberOfParticles: 40,
                  maxBlastForce: 30,
                  minBlastForce: 10,
                  emissionFrequency: 0.06,
                  gravity: 0.15,
                  colors: AppColors.confettiColors,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Sparkle particle that orbits the center during the transition
// ────────────────────────────────────────────────────────────────────────
class _SparkleParticle extends StatelessWidget {
  final int index;
  final Size screenSize;
  final AnimationController controller;

  const _SparkleParticle({
    required this.index,
    required this.screenSize,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final angle = (index / 12) * 2 * pi;
    final radius = screenSize.width * 0.2 + (index % 3) * 20;
    final particleSize = 6.0 + (index % 4) * 2.0;

    final colors = [
      AppColors.starGold,
      AppColors.electricBlue,
      AppColors.violet,
      AppColors.magenta,
      AppColors.emerald,
      AppColors.cyan,
    ];
    final color = colors[index % colors.length];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final currentAngle = angle + t * 2 * pi;
        final x = screenSize.width / 2 + cos(currentAngle) * radius * (1 - t * 0.3);
        final y = screenSize.height / 2 + sin(currentAngle) * radius * (1 - t * 0.3);

        return Positioned(
          left: x - particleSize / 2,
          top: y - particleSize / 2,
          child: Opacity(
            opacity: (1.0 - t * 0.5).clamp(0.0, 1.0),
            child: Container(
              width: particleSize,
              height: particleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

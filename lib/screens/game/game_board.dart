import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../widgets/letter_tile.dart';
import '../../widgets/letter_tracing_canvas.dart';

// ── Hear Word Button ────────────────────────────────────────────

class HearWordButton extends StatelessWidget {
  final bool isPlayingAudio;
  final VoidCallback onTap;

  const HearWordButton({
    super.key,
    required this.isPlayingAudio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final compact = screenH < 600;
    final hPad = compact ? 16.0 : 24.0;
    final vPad = compact ? 8.0 : 12.0;
    final iconSz = compact ? 20.0 : 24.0;
    final fontSz = compact ? 15.0 : 18.0;

    final button = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: isPlayingAudio
              ? AppColors.electricBlue.withValues(alpha: 0.15)
              : AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isPlayingAudio
                ? AppColors.electricBlue.withValues(alpha: 0.4)
                : AppColors.electricBlue.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricBlue.withValues(
                  alpha: isPlayingAudio ? 0.2 : 0.08),
              blurRadius: isPlayingAudio ? 16 : 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlayingAudio
                  ? Icons.hearing_rounded
                  : Icons.volume_up_rounded,
              color: AppColors.electricBlue,
              size: iconSz,
            ),
            SizedBox(width: compact ? 6 : 10),
            Text(
              isPlayingAudio ? 'Listen...' : 'Hear Word',
              style: AppFonts.fredoka(
                fontSize: fontSz,
                fontWeight: FontWeight.w500,
                color: AppColors.electricBlue,
              ),
            ),
          ],
        ),
      ),
    );

    if (isPlayingAudio) {
      return button
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.04, duration: 600.ms, curve: Curves.easeInOut);
    }
    // Gentle shimmer on idle to invite tapping
    return button
        .animate(
          onPlay: (c) => c.repeat(),
          delay: 2000.ms,
        )
        .shimmer(
          duration: 1800.ms,
          color: AppColors.electricBlue.withValues(alpha: 0.15),
          delay: 3000.ms,
        );
  }
}

// ── Letter Tiles ────────────────────────────────────────────────

class GameLetterTiles extends StatelessWidget {
  final String targetText;
  final int currentWordIndex;
  final int currentLetterIndex;
  final List<bool> revealedLetters;
  final bool isExplorer;
  final bool isAdventurer;
  final bool showingCelebration;
  final bool shaking;
  final bool hintRevealing;
  final Animation<double> shakeAnimation;

  const GameLetterTiles({
    super.key,
    required this.targetText,
    required this.currentWordIndex,
    required this.currentLetterIndex,
    required this.revealedLetters,
    required this.isExplorer,
    required this.isAdventurer,
    required this.showingCelebration,
    required this.shaking,
    required this.hintRevealing,
    required this.shakeAnimation,
  });

  @override
  Widget build(BuildContext context) {
    // Detect if word is fully revealed (word complete — trigger wave)
    final allRevealed = revealedLetters.every((r) => r);

    return AnimatedBuilder(
      animation: shakeAnimation,
      builder: (context, child) {
        double offsetX = 0;
        if (shaking) {
          // Soft wobble: 2 oscillations, small amplitude, quickly damped
          final t = shakeAnimation.value;
          offsetX = sin(t * pi * 2) * 5 * (1.0 - t * 0.7);
        }
        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: child,
        );
      },
      child: Wrap(
        key: ValueKey('word_$currentWordIndex'),
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: List.generate(targetText.length, (i) {
          // Explorer/Adventurer: first letter is pre-revealed
          final isPreRevealed = (isExplorer || isAdventurer) && i == 0;
          // During hint reveal (3rd wrong tap), briefly show the correct letter
          final hintReveal = hintRevealing && i == currentLetterIndex;
          // Just revealed = this tile's index matches the letter just typed
          final justRevealed = revealedLetters[i] &&
              i == currentLetterIndex - 1 &&
              !showingCelebration &&
              !isPreRevealed;
          Widget tile = LetterTile(
            letter: targetText[i],
            isRevealed: revealedLetters[i] || hintReveal,
            isActive: i == currentLetterIndex && !showingCelebration,
            isError: shaking && i == currentLetterIndex,
            revealedColor: hintReveal
                ? AppColors.electricBlue
                : isPreRevealed && !(currentLetterIndex > i && i > 0)
                    ? AppColors.silver
                    : null,
          );
          // Bounce animation on hint reveal
          if (hintReveal) {
            tile = tile
                .animate(key: const ValueKey('hint_bounce'))
                .scaleXY(begin: 1.3, end: 1.0, duration: 400.ms, curve: Curves.elasticOut);
          }
          // Pop animation for a just-typed correct letter
          if (justRevealed) {
            tile = tile
                .animate(key: ValueKey('pop_${currentWordIndex}_$i'))
                .scaleXY(begin: 1.2, end: 1.0, duration: 300.ms, curve: Curves.elasticOut);
          }
          // Wave animation when word is complete (stagger each tile)
          if (allRevealed && showingCelebration) {
            tile = tile
                .animate(key: ValueKey('wave_${currentWordIndex}_$i'))
                .slideY(
                  begin: 0,
                  end: -0.15,
                  delay: Duration(milliseconds: i * 60),
                  duration: 200.ms,
                  curve: Curves.easeOut,
                )
                .then()
                .slideY(
                  begin: -0.15,
                  end: 0,
                  duration: 200.ms,
                  curve: Curves.bounceOut,
                );
          }
          return tile;
        }),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0, duration: 300.ms),
    );
  }
}

// ── Letter Tracing Area ────────────────────────────────────────

class GameTracingArea extends StatelessWidget {
  final String targetText;
  final int currentWordIndex;
  final int tracingLetterIndex;
  final VoidCallback onComplete;

  const GameTracingArea({
    super.key,
    required this.targetText,
    required this.currentWordIndex,
    required this.tracingLetterIndex,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final letter = targetText[tracingLetterIndex];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LetterTracingCanvas(
        key: ValueKey('trace_${currentWordIndex}_$tracingLetterIndex'),
        letter: letter,
        traceColor: AppColors.electricBlue,
        guideColor: Colors.white.withValues(alpha: 0.3),
        onComplete: onComplete,
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(
          begin: 0.1,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

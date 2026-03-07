import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/player_profile.dart';
import '../theme/app_theme.dart';
import 'bookworm_companion.dart';

/// Vertical path showing all 5 bookworm evolution stages.
///
/// Completed stages show a green checkmark and full-color companion.
/// The current stage has a golden border, animated glow, and progress bar.
/// Future stages are locked and dimmed.
///
/// Show as a bottom sheet via [EvolutionPath.showAsBottomSheet].
class EvolutionPath extends StatelessWidget {
  final int wordCount;

  const EvolutionPath({
    super.key,
    required this.wordCount,
  });

  /// Display the evolution path as a modal bottom sheet.
  static void showAsBottomSheet(BuildContext context, {required int wordCount}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    'Evolution Path',
                    style: AppFonts.fredoka(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
                // Path content
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    child: EvolutionPath(wordCount: wordCount),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStage = BookwormStage.fromWordCount(wordCount);
    const stages = BookwormStage.values;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = stages.length - 1; i >= 0; i--) ...[
          _StageCard(
            stage: stages[i],
            wordCount: wordCount,
            state: _getStageState(stages[i], currentStage),
          ),
          if (i > 0)
            _ConnectorLine(
              isUnlocked: stages[i - 1].index <= currentStage.index,
            ),
        ],
      ],
    );
  }

  _StageState _getStageState(BookwormStage stage, BookwormStage current) {
    if (stage.index < current.index) return _StageState.completed;
    if (stage.index == current.index) return _StageState.current;
    return _StageState.locked;
  }
}

enum _StageState { completed, current, locked }

// ────────────────────────────────────────────────────────────────────────
// Individual stage card
// ────────────────────────────────────────────────────────────────────────
class _StageCard extends StatelessWidget {
  final BookwormStage stage;
  final int wordCount;
  final _StageState state;

  const _StageCard({
    required this.stage,
    required this.wordCount,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _StageState.current;
    final isLocked = state == _StageState.locked;
    final isCompleted = state == _StageState.completed;

    final borderColor = isCurrent
        ? AppColors.starGold
        : isCompleted
            ? AppColors.success.withValues(alpha: 0.4)
            : AppColors.border;

    final bgColor = isCurrent
        ? AppColors.starGold.withValues(alpha: 0.08)
        : isCompleted
            ? AppColors.success.withValues(alpha: 0.05)
            : AppColors.surface;

    Widget card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Status icon or companion preview
          SizedBox(
            width: 56,
            height: 56,
            child: _buildLeadingWidget(isLocked, isCompleted),
          ),
          const SizedBox(width: 16),
          // Title and info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.title,
                  style: AppFonts.fredoka(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isLocked
                        ? AppColors.secondaryText.withValues(alpha: 0.5)
                        : AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stage.minWords}-${stage.maxWords} words',
                  style: AppFonts.nunito(
                    fontSize: 13,
                    color: AppColors.secondaryText.withValues(
                      alpha: isLocked ? 0.4 : 0.8,
                    ),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(height: 10),
                  _buildProgressBar(),
                ],
              ],
            ),
          ),
          // Status badge
          _buildStatusBadge(isLocked, isCompleted, isCurrent),
        ],
      ),
    );

    if (isCurrent) {
      card = card
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(
            duration: 3000.ms,
            color: AppColors.starGold.withValues(alpha: 0.08),
          );
    }

    return Opacity(
      opacity: isLocked ? 0.55 : 1.0,
      child: card,
    );
  }

  Widget _buildLeadingWidget(bool isLocked, bool isCompleted) {
    if (isLocked) {
      // Dimmed silhouette
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xFF3A3A5A),
          BlendMode.srcATop,
        ),
        child: BookwormCompanion(
          wordCount: stage.minWords,
          size: 56,
        ),
      );
    }
    return BookwormCompanion(
      wordCount: stage.minWords,
      size: 56,
    );
  }

  Widget _buildStatusBadge(bool isLocked, bool isCompleted, bool isCurrent) {
    if (isCompleted) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success.withValues(alpha: 0.15),
          border: Border.all(color: AppColors.success, width: 1.5),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 18,
          color: AppColors.success,
        ),
      );
    }
    if (isCurrent) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.starGold.withValues(alpha: 0.15),
          border: Border.all(color: AppColors.starGold, width: 1.5),
        ),
        child: const Icon(
          Icons.star_rounded,
          size: 16,
          color: AppColors.starGold,
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.15, 1.15),
            duration: 1200.ms,
          );
    }
    // Locked
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.border.withValues(alpha: 0.3),
      ),
      child: Icon(
        Icons.lock_outline_rounded,
        size: 16,
        color: AppColors.secondaryText.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildProgressBar() {
    final readingLevel = ReadingLevel.values[stage.index];
    final progress = readingLevel.progressToNext(wordCount);
    final wordsInRange = wordCount - stage.minWords;
    final totalRange = stage.maxWords - stage.minWords + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                // Track
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Fill
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          stage.primaryColor,
                          stage.primaryColor.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: stage.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Progress text
        Text(
          '$wordsInRange / $totalRange words to next!',
          style: AppFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: stage.primaryColor,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Connector line between stages
// ────────────────────────────────────────────────────────────────────────
class _ConnectorLine extends StatelessWidget {
  final bool isUnlocked;

  const _ConnectorLine({required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      width: double.infinity,
      child: Center(
        child: isUnlocked
            ? Container(
                width: 2,
                height: 32,
                color: AppColors.success.withValues(alpha: 0.4),
              )
            : CustomPaint(
                size: const Size(2, 32),
                painter: _DottedLinePainter(
                  color: AppColors.border.withValues(alpha: 0.4),
                ),
              ),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashH = 4.0;
    const gapH = 4.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dashH).clamp(0, size.height)),
        paint,
      );
      y += dashH + gapH;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

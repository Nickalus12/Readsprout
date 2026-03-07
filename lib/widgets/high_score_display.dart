import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/high_score_service.dart';
import '../theme/app_theme.dart';

class HighScoreDisplay extends StatelessWidget {
  final HighScoreService highScoreService;
  final String gameId;
  final int currentScore;
  final bool isNewHighScore;

  const HighScoreDisplay({
    super.key,
    required this.highScoreService,
    required this.gameId,
    required this.currentScore,
    required this.isNewHighScore,
  });

  @override
  Widget build(BuildContext context) {
    final scores = highScoreService.getHighScores(gameId, limit: 5);

    if (scores.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNewHighScore
              ? AppColors.starGold.withValues(alpha: 0.5)
              : AppColors.border.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          if (isNewHighScore)
            BoxShadow(
              color: AppColors.starGold.withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColors.starGold,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'High Scores',
                style: AppFonts.fredoka(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              if (isNewHighScore) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.starGold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'NEW BEST!',
                    style: AppFonts.fredoka(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.starGold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: AppColors.border.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 6),
          // Score list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scores.length,
              itemBuilder: (context, index) {
                final entry = scores[index];
                final isCurrentScore = entry.score == currentScore &&
                    entry.date.difference(DateTime.now()).inSeconds.abs() < 5;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                  decoration: BoxDecoration(
                    color: isCurrentScore
                        ? AppColors.starGold.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      // Rank
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${index + 1}.',
                          style: AppFonts.fredoka(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: index == 0
                                ? AppColors.starGold
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                      // Name
                      Expanded(
                        child: Text(
                          entry.playerName,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.nunito(
                            fontSize: 13,
                            fontWeight: isCurrentScore
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isCurrentScore
                                ? AppColors.primaryText
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                      // Score
                      Text(
                        '${entry.score}',
                        style: AppFonts.fredoka(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isCurrentScore
                              ? AppColors.starGold
                              : AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Date
                      Text(
                        _formatDate(entry.date),
                        style: AppFonts.nunito(
                          fontSize: 10,
                          color: AppColors.secondaryText.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}

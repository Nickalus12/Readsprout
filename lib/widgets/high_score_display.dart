import 'package:flutter/material.dart';

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
      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isNewHighScore
              ? AppColors.starGold.withValues(alpha: 0.5)
              : AppColors.border.withValues(alpha: 0.4),
          width: isNewHighScore ? 1.5 : 1,
        ),
        boxShadow: [
          if (isNewHighScore) ...[
            BoxShadow(
              color: AppColors.starGold.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppColors.starGold.withValues(alpha: 0.05),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ] else
            BoxShadow(
              color: AppColors.violet.withValues(alpha: 0.05),
              blurRadius: 8,
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
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.starGold,
                size: 20,
                shadows: [
                  Shadow(
                    color: AppColors.starGold.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                'High Scores',
                style: AppFonts.fredoka(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              if (isNewHighScore) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.starGold.withValues(alpha: 0.25),
                        AppColors.starGold.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.starGold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'NEW BEST!',
                    style: AppFonts.fredoka(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.starGold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: AppColors.border.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 8),
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
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: isCurrentScore
                        ? AppColors.starGold.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      // Rank with medal for top 3
                      SizedBox(
                        width: 24,
                        child: index < 3
                            ? Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: [
                                  AppColors.starGold,
                                  AppColors.silver,
                                  AppColors.bronze,
                                ][index],
                              )
                            : Text(
                                '${index + 1}.',
                                style: AppFonts.fredoka(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      // Name
                      Expanded(
                        child: Text(
                          entry.playerName,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.nunito(
                            fontSize: 14,
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
                          fontSize: 15,
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
                          fontSize: 11,
                          color: AppColors.secondaryText.withValues(alpha: 0.5),
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

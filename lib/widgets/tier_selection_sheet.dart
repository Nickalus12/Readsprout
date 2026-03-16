import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/progress.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';

/// A full-screen level detail overlay that shows:
/// - The level's words displayed large and clear
/// - A simple visual difficulty picker (3 big tappable cards)
/// - A big PLAY button
///
/// Designed for a 4-year-old who cannot read — everything is visual.
class TierSelectionSheet extends StatefulWidget {
  final int level;
  final String levelName;
  final String zoneName;
  final ProgressService progressService;
  final void Function(WordTier tier) onTierSelected;
  final int suggestedTier;

  const TierSelectionSheet({
    super.key,
    required this.level,
    required this.levelName,
    required this.zoneName,
    required this.progressService,
    required this.onTierSelected,
    this.suggestedTier = 1,
  });

  /// Show this as a modal bottom sheet and return the selected tier.
  static Future<WordTier?> show({
    required BuildContext context,
    required int level,
    required String levelName,
    required String zoneName,
    required ProgressService progressService,
    int suggestedTier = 1,
  }) {
    return showModalBottomSheet<WordTier>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TierSelectionSheet(
        level: level,
        levelName: levelName,
        zoneName: zoneName,
        progressService: progressService,
        suggestedTier: suggestedTier,
        onTierSelected: (tier) => Navigator.pop(context, tier),
      ),
    );
  }

  @override
  State<TierSelectionSheet> createState() => _TierSelectionSheetState();
}

class _TierSelectionSheetState extends State<TierSelectionSheet> {
  late int _selectedTierValue;

  @override
  void initState() {
    super.initState();
    _selectedTierValue = widget.suggestedTier;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);
    final lp = widget.progressService.getLevel(widget.level);
    final words = DolchWords.wordsForLevel(widget.level);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.secondaryText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Level name
            Padding(
              padding: EdgeInsets.fromLTRB(24 * sf, 4 * sf, 24 * sf, 2 * sf),
              child: Text(
                widget.levelName,
                style: AppFonts.fredoka(
                  fontSize: 22 * sf,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),

            // Star display — big and clear
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final earned = lp.highestCompletedTier > i;
                final Color starColor;
                if (i == 0) {
                  starColor = AppColors.bronze;
                } else if (i == 1) {
                  starColor = AppColors.silver;
                } else {
                  starColor = AppColors.starGold;
                }
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * sf),
                  child: Icon(
                    earned ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 28 * sf,
                    color: earned
                        ? starColor
                        : AppColors.secondaryText.withValues(alpha: 0.25),
                  ),
                );
              }),
            ),

            SizedBox(height: 12 * sf),

            // Words grid — show ALL words big and clear
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20 * sf),
              child: Wrap(
                spacing: 8 * sf,
                runSpacing: 8 * sf,
                alignment: WrapAlignment.center,
                children: words.map((word) {
                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14 * sf,
                      vertical: 8 * sf,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12 * sf),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      word.text,
                      style: AppFonts.fredoka(
                        fontSize: 18 * sf,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryText,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            SizedBox(height: 16 * sf),

            // Difficulty picker — 3 big visual cards in a row
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * sf),
              child: Row(
                children: WordTier.values.map((tier) {
                  final unlocked = widget.progressService
                      .isTierUnlocked(widget.level, tier.value);
                  final isSelected = _selectedTierValue == tier.value;
                  final tierProg = lp.tierProgress[tier.value];
                  final isComplete = tierProg?.isComplete ?? false;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4 * sf),
                      child: _DifficultyCard(
                        tier: tier,
                        unlocked: unlocked,
                        isSelected: isSelected,
                        isComplete: isComplete,
                        sf: sf,
                        onTap: unlocked
                            ? () => setState(
                                () => _selectedTierValue = tier.value)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            SizedBox(height: 16 * sf),

            // Big PLAY button - hero CTA
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20 * sf),
              child: SizedBox(
                width: double.infinity,
                height: 62 * sf,
                child: _PlayButton(
                  tier: WordTier.fromValue(_selectedTierValue)!,
                  sf: sf,
                  onTap: () {
                    final tier = WordTier.fromValue(_selectedTierValue);
                    if (tier != null) widget.onTierSelected(tier);
                  },
                ),
              ),
            ),

            SizedBox(height: 8 * sf),
          ],
        ),
      ),
    );
  }
}

// ── Difficulty card (one of 3 in the horizontal row) ────────────────────

class _DifficultyCard extends StatelessWidget {
  final WordTier tier;
  final bool unlocked;
  final bool isSelected;
  final bool isComplete;
  final double sf;
  final VoidCallback? onTap;

  const _DifficultyCard({
    required this.tier,
    required this.unlocked,
    required this.isSelected,
    required this.isComplete,
    required this.sf,
    this.onTap,
  });

  IconData get _icon {
    switch (tier) {
      case WordTier.explorer:
        return Icons.child_care_rounded;
      case WordTier.adventurer:
        return Icons.local_fire_department_rounded;
      case WordTier.champion:
        return Icons.emoji_events_rounded;
    }
  }

  Color get _cardColor {
    switch (tier) {
      case WordTier.explorer:
        return const Color(0xFF4CAF50); // green
      case WordTier.adventurer:
        return const Color(0xFF42A5F5); // blue
      case WordTier.champion:
        return AppColors.starGold;
    }
  }

  String get _label {
    switch (tier) {
      case WordTier.explorer:
        return 'Easy';
      case WordTier.adventurer:
        return 'Medium';
      case WordTier.champion:
        return 'Hard';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _cardColor;
    final starCount = tier.value;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: unlocked ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            vertical: 12 * sf,
            horizontal: 8 * sf,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : AppColors.background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16 * sf),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.6)
                  : AppColors.border.withValues(alpha: 0.3),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon or lock
              if (unlocked)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _icon,
                      size: 32 * sf,
                      color: isSelected ? color : color.withValues(alpha: 0.6),
                    ),
                    if (isComplete)
                      Positioned(
                        top: -4 * sf,
                        right: -8 * sf,
                        child: Container(
                          width: 16 * sf,
                          height: 16 * sf,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 10 * sf,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                )
              else
                Icon(
                  Icons.lock_rounded,
                  size: 28 * sf,
                  color: AppColors.secondaryText.withValues(alpha: 0.3),
                ),

              SizedBox(height: 6 * sf),

              // Star indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final filled = i < starCount;
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14 * sf,
                    color: filled
                        ? (unlocked
                            ? color
                            : AppColors.secondaryText.withValues(alpha: 0.3))
                        : AppColors.secondaryText.withValues(alpha: 0.2),
                  );
                }),
              ),

              SizedBox(height: 4 * sf),

              // Label
              Text(
                _label,
                style: AppFonts.fredoka(
                  fontSize: 13 * sf,
                  fontWeight: FontWeight.w600,
                  color: unlocked
                      ? (isSelected ? color : AppColors.secondaryText)
                      : AppColors.secondaryText.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Big PLAY button ────────────────────────────────────────────────────

class _PlayButton extends StatefulWidget {
  final WordTier tier;
  final double sf;
  final VoidCallback onTap;

  const _PlayButton({
    required this.tier,
    required this.sf,
    required this.onTap,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  double _scale = 1.0;

  Color get _color {
    switch (widget.tier) {
      case WordTier.explorer:
        return const Color(0xFF4CAF50);
      case WordTier.adventurer:
        return const Color(0xFF42A5F5);
      case WordTier.champion:
        return AppColors.starGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.3),
                color.withValues(alpha: 0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20 * widget.sf),
            border: Border.all(
              color: color.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 32 * widget.sf,
                color: color,
              ),
              SizedBox(width: 8 * widget.sf),
              Text(
                'PLAY',
                style: AppFonts.fredoka(
                  fontSize: 22 * widget.sf,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .scaleXY(begin: 0.9, end: 1.0, duration: 300.ms, curve: Curves.easeOutCubic)
        .then(delay: 500.ms)
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 1.0,
          end: 1.03,
          duration: 1400.ms,
          curve: Curves.easeInOut,
        );
  }
}

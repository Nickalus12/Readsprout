import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';
import '../models/progress.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../widgets/floating_hearts_bg.dart';
import '../widgets/tier_stars_display.dart';
import '../widgets/tier_selection_sheet.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;

  const LevelSelectScreen({
    super.key,
    required this.progressService,
    required this.audioService,
    this.playerName = '',
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  // Track which zones are expanded. Default: expand the zone containing the
  // highest unlocked level, collapse others.
  late final Map<int, bool> _expanded;

  @override
  void initState() {
    super.initState();
    final highestUnlocked = widget.progressService.highestUnlockedLevel;
    _expanded = {};
    for (int i = 0; i < DolchWords.zones.length; i++) {
      final zone = DolchWords.zones[i];
      _expanded[i] = zone.containsLevel(highestUnlocked);
    }
    // If nothing matched (shouldn't happen), open the first zone.
    if (!_expanded.values.any((v) => v)) {
      _expanded[0] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

          // Floating hearts
          const Positioned.fill(
            child: FloatingHeartsBackground(cloudZoneHeight: 0.12),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Choose a Level',
                        style: GoogleFonts.fredoka(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                          shadows: [
                            Shadow(
                              color: AppColors.electricBlue
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _TotalStarsBadge(
                        stars: widget.progressService.totalStars,
                        maxStars: DolchWords.totalLevels * 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Scrollable zone list
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: DolchWords.zones.length,
                    itemBuilder: (context, zoneIndex) {
                      return _buildZoneSection(context, zoneIndex);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Zone section (header + collapsible level list) ───────────────────

  Widget _buildZoneSection(BuildContext context, int zoneIndex) {
    final zone = DolchWords.zones[zoneIndex];
    final isExpanded = _expanded[zoneIndex] ?? false;

    // Compute zone stats
    int zoneStars = 0;
    int zonePossibleStars = zone.levelCount * 3;
    bool zoneUnlocked = false;

    for (int l = zone.startLevel; l <= zone.endLevel; l++) {
      final lp = widget.progressService.getLevel(l);
      zoneStars += lp.starsEarned;
      if (widget.progressService.isLevelUnlocked(l)) zoneUnlocked = true;
    }

    final zoneComplete = zoneStars == zonePossibleStars;
    final zoneProgress = zonePossibleStars > 0
        ? zoneStars / zonePossibleStars
        : 0.0;

    // Determine previous zone name for locked-zone hint
    String? previousZoneName;
    if (!zoneUnlocked && zoneIndex > 0) {
      previousZoneName = DolchWords.zones[zoneIndex - 1].name;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          // Zone header (tappable to expand/collapse)
          GestureDetector(
            onTap: () => setState(() {
              _expanded[zoneIndex] = !isExpanded;
            }),
            child: AnimatedOpacity(
              opacity: zoneUnlocked ? 1.0 : 0.55,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: zoneComplete
                      ? AppColors.starGold.withValues(alpha: 0.06)
                      : zoneUnlocked
                          ? AppColors.surface.withValues(alpha: 0.8)
                          : AppColors.surface.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: zoneComplete
                        ? AppColors.starGold.withValues(alpha: 0.25)
                        : zoneUnlocked
                            ? AppColors.border
                            : AppColors.border.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    // Zone icon
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: zoneComplete
                            ? AppColors.starGold.withValues(alpha: 0.15)
                            : zoneUnlocked
                                ? AppColors.electricBlue.withValues(alpha: 0.1)
                                : AppColors.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: zoneUnlocked
                          ? Text(
                              zone.icon,
                              style: const TextStyle(fontSize: 20),
                            )
                          : Icon(
                              Icons.lock_rounded,
                              color:
                                  AppColors.secondaryText.withValues(alpha: 0.4),
                              size: 18,
                            ),
                    ),
                    const SizedBox(width: 12),

                    // Zone name + star count / locked message
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            zone.name,
                            style: GoogleFonts.fredoka(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: zoneUnlocked
                                  ? AppColors.primaryText
                                  : AppColors.secondaryText
                                      .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (zoneUnlocked)
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: AppColors.starGold),
                                const SizedBox(width: 3),
                                Text(
                                  '$zoneStars / $zonePossibleStars',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Progress bar
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: SizedBox(
                                      height: 4,
                                      child: LinearProgressIndicator(
                                        value: zoneProgress,
                                        backgroundColor: AppColors.background,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          zoneComplete
                                              ? AppColors.starGold
                                              : AppColors.electricBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              previousZoneName != null
                                  ? 'Master all tiers in $previousZoneName to unlock'
                                  : 'Locked',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondaryText
                                    .withValues(alpha: 0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Expand/collapse chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.secondaryText.withValues(alpha: 0.6),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(
                delay: Duration(milliseconds: zoneIndex * 80),
                duration: 400.ms,
              ),

          // Level cards (collapsible)
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildLevelCards(zone, zoneIndex),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildLevelCards(Zone zone, int zoneIndex) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: List.generate(zone.levelCount, (i) {
          final level = zone.startLevel + i;
          final lp = widget.progressService.getLevel(level);
          final unlocked = widget.progressService.isLevelUnlocked(level);
          final gradientIndex =
              (level - 1) % AppColors.levelGradients.length;
          final colors = AppColors.levelGradients[gradientIndex];
          final words = DolchWords.wordsForLevel(level);

          return _LevelCard(
            level: level,
            name: DolchWords.levelName(level),
            unlocked: unlocked,
            levelProgress: lp,
            accentColor: colors.first,
            wordPreview:
                words.take(5).map((w) => w.text).join(', '),
            isTier2Unlocked:
                widget.progressService.isTierUnlocked(level, 2),
            isTier3Unlocked:
                widget.progressService.isTierUnlocked(level, 3),
            onTap: unlocked
                ? () => _onLevelTapped(context, level)
                : null,
          )
              .animate()
              .fadeIn(
                delay: Duration(
                    milliseconds: zoneIndex * 80 + (i + 1) * 40),
                duration: 350.ms,
              )
              .slideX(
                begin: 0.05,
                end: 0,
                delay: Duration(
                    milliseconds: zoneIndex * 80 + (i + 1) * 40),
                curve: Curves.easeOutCubic,
              );
        }),
      ),
    );
  }

  // ── Level tap → show TierSelectionSheet → navigate to game ──────────

  Future<void> _onLevelTapped(BuildContext context, int level) async {
    final zoneName =
        DolchWords.zoneForLevel(level).name;
    final suggestedTier =
        widget.progressService.suggestedTierForLevel(level);

    final selectedTier = await TierSelectionSheet.show(
      context: context,
      level: level,
      levelName: DolchWords.levelName(level),
      zoneName: zoneName,
      progressService: widget.progressService,
      suggestedTier: suggestedTier,
    );

    if (selectedTier == null || !context.mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GameScreen(
          level: level,
          progressService: widget.progressService,
          audioService: widget.audioService,
          playerName: widget.playerName,
          tier: selectedTier.value,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }
}

// ── Level Card ──────────────────────────────────────────────────────────

class _LevelCard extends StatelessWidget {
  final int level;
  final String name;
  final bool unlocked;
  final LevelProgress levelProgress;
  final Color accentColor;
  final String wordPreview;
  final bool isTier2Unlocked;
  final bool isTier3Unlocked;
  final VoidCallback? onTap;

  const _LevelCard({
    required this.level,
    required this.name,
    required this.unlocked,
    required this.levelProgress,
    required this.accentColor,
    required this.wordPreview,
    required this.isTier2Unlocked,
    required this.isTier3Unlocked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isComplete = levelProgress.isComplete;
    final starsEarned = levelProgress.starsEarned;
    final hasAnyStars = starsEarned > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: unlocked ? 1.0 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hasAnyStars
                  ? accentColor.withValues(alpha: 0.06)
                  : AppColors.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasAnyStars
                    ? accentColor.withValues(alpha: 0.25)
                    : unlocked
                        ? accentColor.withValues(alpha: 0.15)
                        : AppColors.border.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: isComplete
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.06),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Left: Level number badge
                _LevelBadge(
                  level: level,
                  unlocked: unlocked,
                  accentColor: accentColor,
                  overallProgress: levelProgress.overallProgress,
                  starsEarned: starsEarned,
                ),
                const SizedBox(width: 14),

                // Center: Level name + word preview
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.fredoka(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: unlocked
                              ? AppColors.primaryText
                              : AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        wordPreview,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: AppColors.secondaryText
                              .withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right: 3-star tier display or lock icon
                if (unlocked)
                  TierStarsDisplay(
                    levelProgress: levelProgress,
                    isTier2Unlocked: isTier2Unlocked,
                    isTier3Unlocked: isTier3Unlocked,
                    starSize: 18,
                  )
                else
                  Icon(
                    Icons.lock_rounded,
                    color: AppColors.secondaryText.withValues(alpha: 0.4),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Level Badge (circular + number) ─────────────────────────────────────

class _LevelBadge extends StatelessWidget {
  final int level;
  final bool unlocked;
  final Color accentColor;
  final double overallProgress;
  final int starsEarned;

  const _LevelBadge({
    required this.level,
    required this.unlocked,
    required this.accentColor,
    required this.overallProgress,
    required this.starsEarned,
  });

  @override
  Widget build(BuildContext context) {
    // Ring color reflects highest tier completed
    final Color ringColor;
    if (starsEarned >= 3) {
      ringColor = AppColors.starGold;
    } else if (starsEarned >= 2) {
      ringColor = AppColors.silver;
    } else if (starsEarned >= 1) {
      ringColor = AppColors.bronze;
    } else {
      ringColor = accentColor;
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              value: unlocked ? overallProgress : 0.0,
              backgroundColor: unlocked
                  ? ringColor.withValues(alpha: 0.12)
                  : AppColors.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          Text(
            '$level',
            style: GoogleFonts.fredoka(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: unlocked
                  ? AppColors.primaryText
                  : AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Total Stars Badge ───────────────────────────────────────────────────

class _TotalStarsBadge extends StatelessWidget {
  final int stars;
  final int maxStars;
  const _TotalStarsBadge({required this.stars, required this.maxStars});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.starGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.starGold.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded,
              color: AppColors.starGold, size: 16),
          const SizedBox(width: 4),
          Text(
            '$stars/$maxStars',
            style: GoogleFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.starGold,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';
import '../models/progress.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../services/stats_service.dart';
import '../services/streak_service.dart';
import '../services/adaptive_music_service.dart';
import '../services/avatar_personality_service.dart';
import '../services/review_service.dart';
import '../services/adaptive_difficulty_service.dart';
import '../widgets/zone_background.dart';
import '../widgets/tier_stars_display.dart';
import '../widgets/tier_selection_sheet.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final ProfileService? profileService;
  final StatsService? statsService;
  final StreakService? streakService;
  final AvatarPersonalityService? personalityService;
  final ReviewService? reviewService;
  final AdaptiveDifficultyService? adaptiveDifficultyService;
  final AdaptiveMusicService? musicService;
  final String playerName;
  final String profileId;

  const LevelSelectScreen({
    super.key,
    required this.progressService,
    required this.audioService,
    this.profileService,
    this.statsService,
    this.streakService,
    this.personalityService,
    this.reviewService,
    this.adaptiveDifficultyService,
    this.musicService,
    this.playerName = '',
    this.profileId = '',
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  // Track which zones are expanded. Default: expand the zone containing the
  // highest unlocked level, collapse others.
  late final Map<int, bool> _expanded;

  /// Zone index for the animated background (based on highest unlocked level).
  late final int _activeZoneIndex;

  @override
  void initState() {
    super.initState();
    final highestUnlocked = widget.progressService.highestUnlockedLevel;
    _activeZoneIndex = zoneIndexForLevel(highestUnlocked);
    _expanded = {};
    for (int i = 0; i < DolchWords.zones.length; i++) {
      final zone = DolchWords.zones[i];
      // Only expand if the zone contains the highest unlocked level
      // AND the zone is actually unlocked
      final zoneHasUnlocked = List.generate(
        zone.levelCount,
        (j) => widget.progressService.isLevelUnlocked(zone.startLevel + j),
      ).any((u) => u);
      _expanded[i] = zoneHasUnlocked && zone.containsLevel(highestUnlocked);
    }
    // If nothing matched (shouldn't happen), open the first zone.
    if (!_expanded.values.any((v) => v)) {
      _expanded[0] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Scaffold(
      body: Stack(
        children: [
          // Zone-themed animated background
          ExcludeSemantics(
            child: Positioned.fill(
              child: ZoneBackground(zone: _activeZoneIndex),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(8 * sf, 8 * sf, 16 * sf, 0),
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Go back',
                        hint: 'Return to home screen',
                        button: true,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          iconSize: 28 * sf,
                          padding: EdgeInsets.all(8 * sf),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.primaryText,
                            size: 28 * sf,
                          ),
                        ),
                      ),
                      SizedBox(width: 4 * sf),
                      GestureDetector(
                        onTap: () => widget.audioService.playWord('adventure_path'),
                        child: Text(
                          'Adventure Path',
                          style: AppFonts.fredoka(
                            fontSize: 22 * sf,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryText,
                            shadows: [
                              Shadow(
                                color: AppColors.electricBlue
                                    .withValues(alpha: 0.3),
                                blurRadius: 12 * sf,
                              ),
                            ],
                          ),
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
                SizedBox(height: 8 * sf),

                // Scrollable zone list
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16 * sf, 4 * sf, 16 * sf, 24 * sf),
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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

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
      padding: EdgeInsets.only(bottom: 6 * sf),
      child: Column(
        children: [
          // Zone header (tappable to expand/collapse)
          GestureDetector(
            onTap: zoneUnlocked
                ? () => setState(() {
                      _expanded[zoneIndex] = !isExpanded;
                    })
                : null,
            child: AnimatedOpacity(
              opacity: zoneUnlocked ? 1.0 : 0.55,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * sf, vertical: 12 * sf),
                decoration: BoxDecoration(
                  color: zoneComplete
                      ? AppColors.starGold.withValues(alpha: 0.06)
                      : zoneUnlocked
                          ? AppColors.surface.withValues(alpha: 0.8)
                          : AppColors.surface.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14 * sf),
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
                      width: 38 * sf,
                      height: 38 * sf,
                      decoration: BoxDecoration(
                        color: zoneComplete
                            ? AppColors.starGold.withValues(alpha: 0.15)
                            : zoneUnlocked
                                ? AppColors.electricBlue.withValues(alpha: 0.1)
                                : AppColors.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10 * sf),
                      ),
                      alignment: Alignment.center,
                      child: zoneUnlocked
                          ? Text(
                              zone.icon,
                              style: TextStyle(fontSize: 20 * sf),
                            )
                          : Icon(
                              Icons.auto_awesome_rounded,
                              color:
                                  AppColors.secondaryText.withValues(alpha: 0.35),
                              size: 18 * sf,
                            ),
                    ),
                    SizedBox(width: 12 * sf),

                    // Zone name + star count / locked message
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => widget.audioService.playWord(
                              zone.name.toLowerCase().replaceAll(' ', '_'),
                            ),
                            child: Text(
                              zone.name,
                              style: AppFonts.fredoka(
                                fontSize: 17 * sf,
                                fontWeight: FontWeight.w600,
                                color: zoneUnlocked
                                    ? AppColors.primaryText
                                    : AppColors.secondaryText
                                        .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          SizedBox(height: 4 * sf),
                          if (zoneUnlocked)
                            Row(
                              children: [
                                Icon(Icons.star_rounded,
                                    size: 13 * sf, color: AppColors.starGold),
                                SizedBox(width: 3 * sf),
                                Text(
                                  '$zoneStars / $zonePossibleStars',
                                  style: AppFonts.nunito(
                                    fontSize: 12 * sf,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                SizedBox(width: 12 * sf),
                                // Progress bar
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2 * sf),
                                    child: SizedBox(
                                      height: 4 * sf,
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
                                  ? 'Coming soon! Finish $previousZoneName first'
                                  : 'Coming soon!',
                              style: AppFonts.nunito(
                                fontSize: 12 * sf,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondaryText
                                    .withValues(alpha: 0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8 * sf),

                    // Expand/collapse chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.secondaryText.withValues(alpha: 0.6),
                        size: 24 * sf,
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

          // Level cards (collapsible) — only show for unlocked zones
          if (zoneUnlocked)
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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Padding(
      padding: EdgeInsets.only(top: 6 * sf),
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
                    milliseconds: zoneIndex * 80 + (i + 1) * 50),
                duration: 350.ms,
              )
              .scaleXY(
                begin: 0.95,
                end: 1.0,
                delay: Duration(
                    milliseconds: zoneIndex * 80 + (i + 1) * 50),
                duration: 350.ms,
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
          profileService: widget.profileService,
          statsService: widget.statsService,
          streakService: widget.streakService,
          personalityService: widget.personalityService,
          reviewService: widget.reviewService,
          adaptiveDifficultyService: widget.adaptiveDifficultyService,
          musicService: widget.musicService,
          playerName: widget.playerName,
          profileId: widget.profileId,
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

class _LevelCard extends StatefulWidget {
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
  State<_LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<_LevelCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _scale = 0.95);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    final isComplete = widget.levelProgress.isComplete;
    final starsEarned = widget.levelProgress.starsEarned;
    final hasAnyStars = starsEarned > 0;
    // "Next to play" = unlocked, not complete, and has no stars yet
    final isNextToPlay = widget.unlocked && !hasAnyStars && !isComplete;

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * sf),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: widget.unlocked ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: EdgeInsets.all(14 * sf),
              decoration: BoxDecoration(
                color: hasAnyStars
                    ? widget.accentColor.withValues(alpha: 0.06)
                    : isNextToPlay
                        ? widget.accentColor.withValues(alpha: 0.04)
                        : AppColors.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(16 * sf),
                border: Border.all(
                  color: hasAnyStars
                      ? widget.accentColor.withValues(alpha: 0.25)
                      : isNextToPlay
                          ? widget.accentColor.withValues(alpha: 0.3)
                          : widget.unlocked
                              ? widget.accentColor.withValues(alpha: 0.15)
                              : AppColors.border.withValues(alpha: 0.5),
                  width: isNextToPlay ? 1.8 : 1.5,
                ),
                boxShadow: [
                  if (isComplete)
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.08),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  if (isNextToPlay)
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.1),
                      blurRadius: 12,
                    ),
                ],
              ),
              child: Row(
                children: [
                  // Left: Level number badge
                  _LevelBadge(
                    level: widget.level,
                    unlocked: widget.unlocked,
                    accentColor: widget.accentColor,
                    overallProgress: widget.levelProgress.overallProgress,
                    starsEarned: starsEarned,
                  ),
                  SizedBox(width: 14 * sf),

                  // Center: Level name + word preview
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: AppFonts.fredoka(
                            fontSize: 15 * sf,
                            fontWeight: FontWeight.w600,
                            color: widget.unlocked
                                ? AppColors.primaryText
                                : AppColors.secondaryText,
                          ),
                        ),
                        SizedBox(height: 4 * sf),
                        Text(
                          widget.wordPreview,
                          style: AppFonts.nunito(
                            fontSize: 12 * sf,
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
                  SizedBox(width: 10 * sf),

                  // Right: 3-star tier display or lock icon
                  if (widget.unlocked)
                    TierStarsDisplay(
                      levelProgress: widget.levelProgress,
                      isTier2Unlocked: widget.isTier2Unlocked,
                      isTier3Unlocked: widget.isTier3Unlocked,
                      starSize: 18 * sf,
                    )
                  else
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.secondaryText.withValues(alpha: 0.3),
                      size: 18 * sf,
                    ),
                ],
              ),
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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

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
      width: 44 * sf,
      height: 44 * sf,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44 * sf,
            height: 44 * sf,
            child: CircularProgressIndicator(
              strokeWidth: 3 * sf,
              value: unlocked ? overallProgress : 0.0,
              backgroundColor: unlocked
                  ? ringColor.withValues(alpha: 0.12)
                  : AppColors.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          Text(
            '$level',
            style: AppFonts.fredoka(
              fontSize: 17 * sf,
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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * sf, vertical: 5 * sf),
      decoration: BoxDecoration(
        color: AppColors.starGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12 * sf),
        border: Border.all(
          color: AppColors.starGold.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded,
              color: AppColors.starGold, size: 16 * sf),
          SizedBox(width: 4 * sf),
          Text(
            '$stars/$maxStars',
            style: AppFonts.fredoka(
              fontSize: 14 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.starGold,
            ),
          ),
        ],
      ),
    );
  }
}

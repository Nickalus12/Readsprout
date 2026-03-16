import 'dart:math';
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
import '../services/player_settings_service.dart';
import '../widgets/zone_background.dart';
import '../widgets/tier_stars_display.dart';
import '../widgets/tier_selection_sheet.dart';
import '../widgets/zone_unlock_overlay.dart';
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
  final PlayerSettingsService? settingsService;
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
    this.settingsService,
    this.playerName = '',
    this.profileId = '',
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen>
    with TickerProviderStateMixin {
  // Track which zones are expanded.
  late final Map<int, bool> _expanded;

  /// Tracks which locked zone is currently shaking.
  int? _shakingZoneIndex;
  AnimationController? _lockedShakeController;

  /// Tracks which locked level card is currently shaking.
  int? _shakingLevelNumber;
  AnimationController? _lockedLevelShakeController;

  /// Zone index for the animated background.
  late final int _activeZoneIndex;

  /// Overlay entry for the "locked" tooltip bubble.
  OverlayEntry? _lockedTooltipEntry;

  @override
  void initState() {
    super.initState();
    final highestUnlocked = widget.progressService.highestUnlockedLevel;
    _activeZoneIndex = zoneIndexForLevel(highestUnlocked);
    _expanded = {};
    for (int i = 0; i < DolchWords.zones.length; i++) {
      final zone = DolchWords.zones[i];
      final zoneHasUnlocked = List.generate(
        zone.levelCount,
        (j) => widget.progressService.isLevelUnlocked(zone.startLevel + j),
      ).any((u) => u);
      _expanded[i] = zoneHasUnlocked && zone.containsLevel(highestUnlocked);
    }
    if (!_expanded.values.any((v) => v)) {
      _expanded[0] = true;
    }

    _lockedShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _lockedShakeController?.reset();
          if (mounted) setState(() => _shakingZoneIndex = null);
        }
      });

    _lockedLevelShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _lockedLevelShakeController?.reset();
          if (mounted) setState(() => _shakingLevelNumber = null);
        }
      });
  }

  @override
  void dispose() {
    _lockedShakeController?.dispose();
    _lockedLevelShakeController?.dispose();
    _dismissLockedTooltip();
    super.dispose();
  }

  void _shakeLockedZone(int zoneIndex) {
    setState(() => _shakingZoneIndex = zoneIndex);
    _lockedShakeController?.forward(from: 0);
  }

  void _shakeLockedLevel(int levelNumber, BuildContext cardContext) {
    setState(() => _shakingLevelNumber = levelNumber);
    _lockedLevelShakeController?.forward(from: 0);
    widget.audioService.playError();
    _showLockedTooltip(cardContext, levelNumber);
  }

  void _showLockedTooltip(BuildContext cardContext, int levelNumber) {
    _dismissLockedTooltip();

    final renderBox = cardContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Find what level they need to complete first
    final previousLevel = levelNumber - 1;
    final previousName =
        previousLevel >= 1 ? DolchWords.levelName(previousLevel) : '';

    _lockedTooltipEntry = OverlayEntry(
      builder: (context) => _LockedTooltip(
        left: offset.dx + size.width / 2,
        top: offset.dy - 8,
        message: previousName.isNotEmpty
            ? 'Finish $previousName first!'
            : 'Not yet!',
        onDismiss: _dismissLockedTooltip,
      ),
    );

    Overlay.of(context).insert(_lockedTooltipEntry!);

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), _dismissLockedTooltip);
  }

  void _dismissLockedTooltip() {
    _lockedTooltipEntry?.remove();
    _lockedTooltipEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Scaffold(
      body: Stack(
        children: [
          // Zone-themed animated background
          Positioned.fill(
            child: ExcludeSemantics(
              child: ZoneBackground(zone: _activeZoneIndex),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Header — wrapped to prevent overflow
                Padding(
                  padding: EdgeInsets.fromLTRB(8 * sf, 8 * sf, 8 * sf, 0),
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
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              widget.audioService.playWord('adventure_path'),
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
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(width: 6 * sf),
                      _CoinBadge(coins: widget.progressService.starCoins),
                      SizedBox(width: 6 * sf),
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
                    padding: EdgeInsets.fromLTRB(
                        12 * sf, 4 * sf, 12 * sf, 24 * sf),
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
    final zoneProgress =
        zonePossibleStars > 0 ? zoneStars / zonePossibleStars : 0.0;

    // Determine previous zone name for locked-zone hint
    String? previousZoneName;
    if (!zoneUnlocked && zoneIndex > 0) {
      previousZoneName = DolchWords.zones[zoneIndex - 1].name;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 6 * sf),
      child: Column(
        children: [
          // Zone header
          GestureDetector(
            onTap: zoneUnlocked
                ? () => setState(() {
                      _expanded[zoneIndex] = !isExpanded;
                    })
                : () {
                    _shakeLockedZone(zoneIndex);
                  },
            child: AnimatedBuilder(
              animation: _lockedShakeController!,
              builder: (context, child) {
                double offsetX = 0;
                if (_shakingZoneIndex == zoneIndex && !zoneUnlocked) {
                  final t = _lockedShakeController!.value;
                  offsetX = sin(t * pi * 4) * 8 * (1.0 - t);
                }
                return Transform.translate(
                  offset: Offset(offsetX, 0),
                  child: child,
                );
              },
              child: AnimatedOpacity(
                opacity: zoneUnlocked ? 1.0 : 0.55,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 14 * sf, vertical: 12 * sf),
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
                                  ? AppColors.electricBlue
                                      .withValues(alpha: 0.1)
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
                                color: AppColors.secondaryText
                                    .withValues(alpha: 0.35),
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
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(height: 4 * sf),
                            if (zoneUnlocked)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.star_rounded,
                                          size: 14 * sf,
                                          color: AppColors.starGold),
                                      SizedBox(width: 3 * sf),
                                      Text(
                                        '$zoneStars / $zonePossibleStars',
                                        style: AppFonts.nunito(
                                          fontSize: 12 * sf,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4 * sf),
                                  // Prominent progress bar
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4 * sf),
                                    child: SizedBox(
                                      height: 8 * sf,
                                      child: LinearProgressIndicator(
                                        value: zoneProgress,
                                        backgroundColor:
                                            AppColors.background,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          zoneComplete
                                              ? AppColors.starGold
                                              : AppColors.electricBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                previousZoneName != null
                                    ? 'Finish $previousZoneName first'
                                    : 'Coming soon!',
                                style: AppFonts.nunito(
                                  fontSize: 12 * sf,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.secondaryText
                                      .withValues(alpha: 0.5),
                                  fontStyle: FontStyle.italic,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 4 * sf),

                      // Expand/collapse chevron
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color:
                              AppColors.secondaryText.withValues(alpha: 0.6),
                          size: 24 * sf,
                        ),
                      ),
                    ],
                  ),
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
          if (zoneUnlocked)
            AnimatedSize(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? _buildLevelCards(zone, zoneIndex)
                  : const SizedBox(width: double.infinity, height: 0),
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
            wordPreview: words.take(5).map((w) => w.text).join(', '),
            isTier2Unlocked:
                widget.progressService.isTierUnlocked(level, 2),
            isTier3Unlocked:
                widget.progressService.isTierUnlocked(level, 3),
            isShaking: _shakingLevelNumber == level,
            shakeController: _lockedLevelShakeController!,
            onTap: unlocked
                ? () => _onLevelTapped(context, level)
                : null,
            onLockedTap: !unlocked
                ? (cardContext) => _shakeLockedLevel(level, cardContext)
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
    final zoneName = DolchWords.zoneForLevel(level).name;
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

    // Record last-played for Continue button on home screen
    widget.settingsService?.setLastPlayed(level, selectedTier.value);

    // Snapshot which zones are fully mastered BEFORE entering the game
    final masteredBefore = <int>{};
    for (int i = 0; i < DolchWords.zones.length; i++) {
      final z = DolchWords.zones[i];
      if (widget.progressService
          .isZoneFullyMastered(z.startLevel, z.endLevel)) {
        masteredBefore.add(i);
      }
    }

    await Navigator.push(
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
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );

    // After returning from GameScreen, check for newly mastered zones
    if (!context.mounted) return;
    await _checkForZoneUnlock(context, masteredBefore);

    // Refresh the level list to reflect updated progress
    if (mounted) setState(() {});
  }

  /// Compare zone mastery state before/after gameplay and show celebration.
  Future<void> _checkForZoneUnlock(
    BuildContext context,
    Set<int> masteredBefore,
  ) async {
    for (int i = 0; i < DolchWords.zones.length; i++) {
      if (masteredBefore.contains(i)) continue;
      final z = DolchWords.zones[i];
      if (!widget.progressService
          .isZoneFullyMastered(z.startLevel, z.endLevel)) {
        continue;
      }
      final isLastZone = i + 1 >= DolchWords.zones.length;
      final nextZoneIndex = isLastZone ? i : i + 1;

      widget.audioService.playLevelCompleteEffect();

      if (!context.mounted) return;
      await ZoneUnlockOverlay.show(
        context,
        masteredZoneIndex: i,
        newZoneIndex: nextZoneIndex,
        playerName: widget.playerName,
        isAllComplete: isLastZone,
      );

      break;
    }
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
  final bool isShaking;
  final AnimationController shakeController;
  final VoidCallback? onTap;
  final void Function(BuildContext)? onLockedTap;

  const _LevelCard({
    required this.level,
    required this.name,
    required this.unlocked,
    required this.levelProgress,
    required this.accentColor,
    required this.wordPreview,
    required this.isTier2Unlocked,
    required this.isTier3Unlocked,
    required this.isShaking,
    required this.shakeController,
    this.onTap,
    this.onLockedTap,
  });

  @override
  State<_LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<_LevelCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLockedTap == null) return;
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
    final isNextToPlay = widget.unlocked && !hasAnyStars && !isComplete;
    final isFullyMastered = starsEarned >= 3;

    Widget card = Padding(
      padding: EdgeInsets.only(bottom: 8 * sf),
      child: AnimatedBuilder(
        animation: widget.shakeController,
        builder: (context, child) {
          double offsetX = 0;
          if (widget.isShaking && !widget.unlocked) {
            final t = widget.shakeController.value;
            offsetX = sin(t * pi * 4) * 6 * (1.0 - t);
          }
          return Transform.translate(
            offset: Offset(offsetX, 0),
            child: child,
          );
        },
        child: GestureDetector(
          onTap: widget.onTap ??
              (widget.onLockedTap != null
                  ? () => widget.onLockedTap!(context)
                  : null),
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
                  color: isFullyMastered
                      ? AppColors.starGold.withValues(alpha: 0.06)
                      : hasAnyStars
                          ? widget.accentColor.withValues(alpha: 0.06)
                          : isNextToPlay
                              ? widget.accentColor.withValues(alpha: 0.04)
                              : AppColors.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16 * sf),
                  border: Border.all(
                    color: isFullyMastered
                        ? AppColors.starGold.withValues(alpha: 0.5)
                        : hasAnyStars
                            ? widget.accentColor.withValues(alpha: 0.25)
                            : isNextToPlay
                                ? widget.accentColor.withValues(alpha: 0.35)
                                : widget.unlocked
                                    ? widget.accentColor
                                        .withValues(alpha: 0.15)
                                    : AppColors.border.withValues(alpha: 0.5),
                    width: isFullyMastered ? 2.0 : isNextToPlay ? 2.0 : 1.5,
                  ),
                  boxShadow: [
                    if (isFullyMastered)
                      BoxShadow(
                        color:
                            AppColors.starGold.withValues(alpha: 0.12),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    if (isComplete && !isFullyMastered)
                      BoxShadow(
                        color:
                            widget.accentColor.withValues(alpha: 0.08),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    if (isNextToPlay)
                      BoxShadow(
                        color:
                            widget.accentColor.withValues(alpha: 0.15),
                        blurRadius: 16,
                        spreadRadius: 2,
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
                      overallProgress:
                          widget.levelProgress.overallProgress,
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
                            overflow: TextOverflow.ellipsis,
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
                    SizedBox(width: 8 * sf),

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
                        color: AppColors.secondaryText
                            .withValues(alpha: 0.3),
                        size: 18 * sf,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Next-to-play card gets a gentle breathing pulse to guide the child
    if (isNextToPlay) {
      card = card
          .animate(
            onPlay: (c) => c.repeat(reverse: true),
          )
          .scaleXY(
            begin: 1.0,
            end: 1.015,
            duration: 1600.ms,
            curve: Curves.easeInOut,
          );
    }

    return card;
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

// ── Locked Tooltip ──────────────────────────────────────────────────────

class _LockedTooltip extends StatefulWidget {
  final double left;
  final double top;
  final String message;
  final VoidCallback onDismiss;

  const _LockedTooltip({
    required this.left,
    required this.top,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_LockedTooltip> createState() => _LockedTooltipState();
}

class _LockedTooltipState extends State<_LockedTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: widget.top - 40,
      child: GestureDetector(
        onTap: widget.onDismiss,
        behavior: HitTestBehavior.translucent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value,
              child: Transform.translate(
                offset: _slide.value,
                child: child,
              ),
            );
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.electricBlue.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.electricBlue.withValues(alpha: 0.1),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: AppColors.electricBlue.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.message,
                    style: AppFonts.fredoka(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryText,
                    ),
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

// ── Coin Badge ───────────────────────────────────────────────────────

class _CoinBadge extends StatelessWidget {
  final int coins;
  const _CoinBadge({required this.coins});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * sf, vertical: 4 * sf),
      decoration: BoxDecoration(
        color: AppColors.starGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12 * sf),
        border: Border.all(
          color: AppColors.starGold.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monetization_on_rounded,
              color: AppColors.starGold.withValues(alpha: 0.8),
              size: 14 * sf),
          SizedBox(width: 3 * sf),
          Text(
            '$coins',
            style: AppFonts.fredoka(
              fontSize: 12 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.starGold.withValues(alpha: 0.8),
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
      padding: EdgeInsets.symmetric(horizontal: 8 * sf, vertical: 4 * sf),
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
              color: AppColors.starGold, size: 14 * sf),
          SizedBox(width: 3 * sf),
          Text(
            '$stars/$maxStars',
            style: AppFonts.fredoka(
              fontSize: 12 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.starGold,
            ),
          ),
        ],
      ),
    );
  }
}

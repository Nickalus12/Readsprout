import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/dolch_words.dart';
import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import '../avatar/avatar_widget.dart';
import '../widgets/daily_treasure.dart';
import '../widgets/sticker_book.dart';
import '../widgets/word_constellation.dart';
import '../widgets/word_garden.dart';
import 'avatar_editor_screen.dart';

/// Main profile screen ("Garden") showing avatar, stats,
/// companion, treasure, garden, stickers, and word constellation.
class ProfileScreen extends StatefulWidget {
  final ProfileService profileService;
  final ProgressService progressService;
  final AudioService audioService;
  final StreakService streakService;
  final String playerName;
  final VoidCallback? onSignOut;

  const ProfileScreen({
    super.key,
    required this.profileService,
    required this.progressService,
    required this.audioService,
    required this.streakService,
    required this.playerName,
    this.onSignOut,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AvatarConfig _avatar;
  late AnimationController _avatarGlowController;
  late AnimationController _statsAnimController;
  late AnimationController _homeFrameController;
  final AvatarController _avatarController = AvatarController();

  // Animated counter values
  double _animatedWordCount = 0;
  double _animatedStarCount = 0;
  double _animatedStreakCount = 0;

  @override
  void initState() {
    super.initState();
    _avatar = widget.profileService.avatar;
    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _homeFrameController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _statsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Wire amplitude-based lip sync to avatar
    _avatarController.bindAmplitude(widget.audioService.mouthAmplitude);

    // Greet the child when profile opens — avatar waves and looks happy
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _avatarController.setExpression(
          AvatarExpression.happy,
          duration: const Duration(milliseconds: 2500),
        );
      }
    });
    Future.delayed(const Duration(milliseconds: 600), _greetChild);

    // Animate counters after a brief delay
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _statsAnimController.forward();
        _statsAnimController.addListener(_updateAnimatedCounters);
      }
    });
  }

  void _updateAnimatedCounters() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_statsAnimController.value);
    setState(() {
      _animatedWordCount = _wordCount * t;
      _animatedStarCount = _masteredCount * t;
      _animatedStreakCount = _streak * t;
    });
  }

  void _greetChild() {
    if (!mounted) return;
    widget.audioService.playWelcome(widget.playerName);
  }

  int _tapCount = 0;

  void _onAvatarTap() {
    _tapCount++;
    // Cycle through fun expressions so repeated taps feel different
    final expressions = [
      AvatarExpression.excited,
      AvatarExpression.happy,
      AvatarExpression.surprised,
      AvatarExpression.excited,
      AvatarExpression.happy,
    ];
    final expr = expressions[_tapCount % expressions.length];
    _avatarController.setExpression(
      expr,
      duration: const Duration(milliseconds: 1500),
    );
    widget.audioService.playSuccess();
  }

  @override
  void dispose() {
    _statsAnimController.removeListener(_updateAnimatedCounters);
    _statsAnimController.dispose();
    _avatarController.dispose();
    _avatarGlowController.dispose();
    _homeFrameController.dispose();
    super.dispose();
  }

  int get _wordCount => widget.profileService.totalWordsEverCompleted;
  int get _masteredCount => widget.progressService.totalStars;
  int get _streak => widget.streakService.currentStreak;
  ReadingLevel get _readingLevel => widget.profileService.readingLevel;

  void _openAvatarEditor() async {
    final result = await Navigator.push<AvatarConfig>(
      context,
      PageRouteBuilder<AvatarConfig>(
        pageBuilder: (_, __, ___) => AvatarEditorScreen(
          profileService: widget.profileService,
          wordsMastered: _wordCount,
          streakDays: _streak,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (result != null && mounted) {
      setState(() => _avatar = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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

          // Firefly particles
          const Positioned.fill(child: _FireflyBackground()),

          // Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        _buildHeroSection(),
                        const SizedBox(height: 18),
                        _buildCompletionRing(),
                        const SizedBox(height: 18),
                        _buildLevelProgressMap(),
                        const SizedBox(height: 18),
                        _buildAchievements(),
                        const SizedBox(height: 18),
                        DailyTreasure(
                          profileService: widget.profileService,
                          wordsPlayedToday: widget.profileService.wordsPlayedToday,
                          currentStreak: _streak,
                        ).animate().fadeIn(delay: 200.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        WordGarden(
                          progressService: widget.progressService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 300.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        StickerBook(
                          profileService: widget.profileService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 400.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 18),
                        WordConstellation(
                          progressService: widget.progressService,
                          audioService: widget.audioService,
                        ).animate().fadeIn(delay: 500.ms, duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 300.ms),
                        const SizedBox(height: 24),
                        if (widget.onSignOut != null)
                          _buildSignOutButton(),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * sf, vertical: 4 * sf),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: 28 * sf,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.audioService.playWord('garden'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_florist_rounded,
                    size: 20 * sf,
                    color: AppColors.emerald.withValues(alpha: 0.7),
                  ),
                  SizedBox(width: 6 * sf),
                  Text(
                    widget.playerName.isNotEmpty
                        ? "${widget.playerName}'s Garden"
                        : 'My Garden',
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: 22 * sf,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 48 * sf),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────────

  Widget _buildHeroSection() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);
    final level = _readingLevel;
    final nextLevel = level.next;
    final progressToNext = level.progressToNext(_wordCount);

    // Avatar home frame: ~40% screen width on phone, capped at 300px
    final frameW = (screenW * 0.40).clamp(120.0, 300.0);
    final frameH = frameW / 0.75; // 3:4 aspect ratio

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 16 * sf),

            // ── Avatar Home Frame ──
            GestureDetector(
              onTap: _onAvatarTap,
              onLongPress: _openAvatarEditor,
              child: _AvatarHomeFrame(
                width: frameW,
                height: frameH,
                sf: sf,
                frameController: _homeFrameController,
                glowController: _avatarGlowController,
                avatar: _avatar,
                avatarController: _avatarController,
                level: widget.progressService.highestUnlockedLevel,
                onEditTap: _openAvatarEditor,
              ),
            ),

            SizedBox(width: 14 * sf),

            // ── Name + reading level + stats ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8 * sf),

                  // Player name
                  if (widget.playerName.isNotEmpty)
                    GestureDetector(
                      onTap: () => widget.audioService.playWelcome(widget.playerName),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.playerName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: AppFonts.fredoka(
                                fontSize: 26 * sf,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: AppColors.magenta.withValues(alpha: 0.5),
                                    blurRadius: 16 * sf,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 6 * sf),
                          Icon(
                            Icons.volume_up_rounded,
                            color: AppColors.secondaryText.withValues(alpha: 0.4),
                            size: 16 * sf,
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 6 * sf),

                  // Reading level title with icon
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * sf, vertical: 4 * sf),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _levelColor(level).withValues(alpha: 0.15),
                          _levelColor(level).withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10 * sf),
                      border: Border.all(
                        color: _levelColor(level).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _levelIcon(level),
                          size: 14 * sf,
                          color: _levelColor(level),
                        ),
                        SizedBox(width: 4 * sf),
                        Text(
                          level.title,
                          style: AppFonts.fredoka(
                            fontSize: 12 * sf,
                            fontWeight: FontWeight.w600,
                            color: _levelColor(level),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Progress to next level
                  if (nextLevel != null) ...[
                    SizedBox(height: 6 * sf),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4 * sf),
                            child: LinearProgressIndicator(
                              value: progressToNext,
                              backgroundColor: AppColors.surface,
                              valueColor: AlwaysStoppedAnimation(
                                _levelColor(level).withValues(alpha: 0.7),
                              ),
                              minHeight: 4 * sf,
                            ),
                          ),
                        ),
                        SizedBox(width: 6 * sf),
                        Text(
                          '${(progressToNext * 100).round()}%',
                          style: AppFonts.nunito(
                            fontSize: 10 * sf,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2 * sf),
                    Text(
                      'Next: ${nextLevel.title}',
                      style: AppFonts.nunito(
                        fontSize: 10 * sf,
                        color: AppColors.secondaryText.withValues(alpha: 0.6),
                      ),
                    ),
                  ],

                  SizedBox(height: 10 * sf),

                  // Animated stat chips
                  Wrap(
                    spacing: 8 * sf,
                    runSpacing: 6 * sf,
                    children: [
                      _StatChip(Icons.local_florist_rounded, AppColors.emerald,
                        '${_animatedWordCount.round()}',
                        label: 'Words', sf: sf,
                        onTap: () => widget.audioService.playWord('words'),
                      ),
                      _StatChip(Icons.star_rounded, AppColors.starGold,
                        '${_animatedStarCount.round()}',
                        label: 'Stars', sf: sf,
                        onTap: () => widget.audioService.playWord('stars'),
                      ),
                      _StatChip(Icons.local_fire_department_rounded, AppColors.flameOrange,
                        '${_animatedStreakCount.round()}',
                        label: 'Streak', sf: sf,
                        animate: _streak > 0,
                        onTap: () => widget.audioService.playWord('streak'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(width: 12 * sf),
          ],
        ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
      ],
    );
  }

  Color _levelColor(ReadingLevel level) {
    return switch (level) {
      ReadingLevel.wordSprout => AppColors.emerald,
      ReadingLevel.wordExplorer => AppColors.electricBlue,
      ReadingLevel.wordWizard => AppColors.violet,
      ReadingLevel.wordChampion => AppColors.magenta,
      ReadingLevel.readingSuperstar => AppColors.starGold,
    };
  }

  IconData _levelIcon(ReadingLevel level) {
    return switch (level) {
      ReadingLevel.wordSprout => Icons.eco_rounded,
      ReadingLevel.wordExplorer => Icons.explore_rounded,
      ReadingLevel.wordWizard => Icons.auto_awesome_rounded,
      ReadingLevel.wordChampion => Icons.emoji_events_rounded,
      ReadingLevel.readingSuperstar => Icons.star_rounded,
    };
  }

  // ── Completion Ring ─────────────────────────────────────────────────

  Widget _buildCompletionRing() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);
    const totalWords = 220; // Total Dolch words
    final completedWords = widget.progressService.totalWordsCompleted;
    final percentage = (completedWords / totalWords).clamp(0.0, 1.0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * sf),
      child: Container(
        padding: EdgeInsets.all(16 * sf),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20 * sf),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Circular progress ring
            SizedBox(
              width: 80 * sf,
              height: 80 * sf,
              child: AnimatedBuilder(
                animation: _statsAnimController,
                builder: (context, child) {
                  final animatedPercentage = percentage *
                      Curves.easeOutCubic.transform(_statsAnimController.value);
                  return CustomPaint(
                    painter: _CompletionRingPainter(
                      progress: animatedPercentage,
                      sf: sf,
                    ),
                    child: Center(
                      child: Text(
                        '${(animatedPercentage * 100).round()}%',
                        style: AppFonts.fredoka(
                          fontSize: 18 * sf,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(width: 16 * sf),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_graph_rounded, size: 18 * sf, color: AppColors.electricBlue),
                      SizedBox(width: 6 * sf),
                      Text(
                        'Overall Progress',
                        style: AppFonts.fredoka(
                          fontSize: 16 * sf,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * sf),
                  Text(
                    '$completedWords of $totalWords words learned',
                    style: AppFonts.nunito(
                      fontSize: 13 * sf,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  SizedBox(height: 4 * sf),
                  Text(
                    '$_masteredCount of 66 stars earned',
                    style: AppFonts.nunito(
                      fontSize: 12 * sf,
                      color: AppColors.secondaryText.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 100.ms, duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ── Level Progress Map ──────────────────────────────────────────────

  Widget _buildLevelProgressMap() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    // Zone colors mapping
    const zoneColors = [
      AppColors.emerald,     // Whispering Woods - green
      AppColors.electricBlue, // Shimmer Shore - blue
      Color(0xFF9CA3AF),     // Crystal Peaks - gray
      AppColors.violet,       // Skyward Kingdom - purple
      AppColors.starGold,     // Celestial Crown - gold
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * sf),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.map_rounded, size: 18 * sf, color: AppColors.violet),
              SizedBox(width: 6 * sf),
              Text(
                'Adventure Map',
                style: AppFonts.fredoka(
                  fontSize: 16 * sf,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * sf),

          // Horizontal scrollable zone strip
          SizedBox(
            height: 120 * sf,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: DolchWords.zones.length,
              separatorBuilder: (_, __) => SizedBox(width: 8 * sf),
              itemBuilder: (context, zoneIdx) {
                final zone = DolchWords.zones[zoneIdx];
                final zoneColor = zoneColors[zoneIdx];
                final highestLevel = widget.progressService.highestUnlockedLevel;

                return Container(
                  width: 160 * sf,
                  padding: EdgeInsets.all(10 * sf),
                  decoration: BoxDecoration(
                    color: zoneColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16 * sf),
                    border: Border.all(
                      color: zoneColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Zone name
                      Text(
                        zone.name,
                        style: AppFonts.fredoka(
                          fontSize: 12 * sf,
                          fontWeight: FontWeight.w600,
                          color: zoneColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8 * sf),

                      // Level stars grid
                      Expanded(
                        child: Wrap(
                          spacing: 4 * sf,
                          runSpacing: 4 * sf,
                          children: [
                            for (int level = zone.startLevel; level <= zone.endLevel; level++)
                              _LevelDot(
                                level: level,
                                progressService: widget.progressService,
                                zoneColor: zoneColor,
                                isCurrentLevel: level == highestLevel,
                                sf: sf,
                              ),
                          ],
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
    )
        .animate()
        .fadeIn(delay: 150.ms, duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ── Achievements Section ────────────────────────────────────────────

  Widget _buildAchievements() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    // Define milestones
    final wordMilestones = [
      (1, 'First Word', Icons.emoji_nature_rounded),
      (10, '10 Words', Icons.local_florist_rounded),
      (25, '25 Words', Icons.park_rounded),
      (50, '50 Words', Icons.forest_rounded),
      (100, '100 Words', Icons.auto_awesome_rounded),
      (150, '150 Words', Icons.bolt_rounded),
      (200, '200 Words', Icons.diamond_rounded),
      (220, 'All Words!', Icons.workspace_premium_rounded),
    ];

    final streakMilestones = [
      (3, '3 Day Streak', Icons.local_fire_department_rounded),
      (7, '7 Day Streak', Icons.whatshot_rounded),
      (14, '14 Days', Icons.celebration_rounded),
      (30, '30 Days', Icons.emoji_events_rounded),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * sf),
      child: Container(
        padding: EdgeInsets.all(16 * sf),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20 * sf),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 18 * sf, color: AppColors.starGold),
                SizedBox(width: 6 * sf),
                Text(
                  'Achievements',
                  style: AppFonts.fredoka(
                    fontSize: 16 * sf,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * sf),

            // Word milestones
            Text(
              'Word Milestones',
              style: AppFonts.nunito(
                fontSize: 12 * sf,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            SizedBox(height: 8 * sf),
            Wrap(
              spacing: 8 * sf,
              runSpacing: 8 * sf,
              children: wordMilestones.map((m) {
                final earned = _wordCount >= m.$1;
                return _AchievementBadge(
                  icon: m.$3,
                  label: m.$2,
                  earned: earned,
                  color: AppColors.emerald,
                  sf: sf,
                );
              }).toList(),
            ),

            SizedBox(height: 14 * sf),

            // Streak milestones
            Text(
              'Streak Milestones',
              style: AppFonts.nunito(
                fontSize: 12 * sf,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            SizedBox(height: 8 * sf),
            Wrap(
              spacing: 8 * sf,
              runSpacing: 8 * sf,
              children: streakMilestones.map((m) {
                final earned = widget.streakService.longestStreak >= m.$1;
                return _AchievementBadge(
                  icon: m.$3,
                  label: m.$2,
                  earned: earned,
                  color: AppColors.flameOrange,
                  sf: sf,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ── Switch Profile Button (bottom of page) ───────────────────────────

  Widget _buildSignOutButton() {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40 * sf),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
          widget.onSignOut!();
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10 * sf),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14 * sf),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                size: 18 * sf,
                color: AppColors.secondaryText.withValues(alpha: 0.5),
              ),
              SizedBox(width: 6 * sf),
              Text(
                'Switch Profile',
                style: AppFonts.fredoka(
                  fontSize: 13 * sf,
                  fontWeight: FontWeight.w500,
                  color: AppColors.secondaryText.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 600.ms, duration: 400.ms);
  }
}

// ── Level Dot (for Adventure Map) ─────────────────────────────────────

class _LevelDot extends StatelessWidget {
  final int level;
  final ProgressService progressService;
  final Color zoneColor;
  final bool isCurrentLevel;
  final double sf;

  const _LevelDot({
    required this.level,
    required this.progressService,
    required this.zoneColor,
    required this.isCurrentLevel,
    required this.sf,
  });

  @override
  Widget build(BuildContext context) {
    final lp = progressService.getLevel(level);
    final isUnlocked = progressService.isLevelUnlocked(level);
    final stars = lp.highestCompletedTier;
    final size = 28 * sf;

    // Star colors for 1, 2, 3
    final starColors = [AppColors.bronze, AppColors.silver, AppColors.starGold];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUnlocked
            ? (stars > 0 ? zoneColor.withValues(alpha: 0.25) : AppColors.surface)
            : AppColors.surface.withValues(alpha: 0.3),
        border: Border.all(
          color: isCurrentLevel
              ? AppColors.electricBlue
              : isUnlocked
                  ? zoneColor.withValues(alpha: 0.5)
                  : AppColors.border.withValues(alpha: 0.3),
          width: isCurrentLevel ? 2 : 1,
        ),
        boxShadow: isCurrentLevel
            ? [
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: Center(
        child: isUnlocked
            ? (stars > 0
                ? Icon(
                    Icons.star_rounded,
                    size: 16 * sf,
                    color: starColors[(stars - 1).clamp(0, 2)],
                  )
                : Text(
                    '$level',
                    style: AppFonts.nunito(
                      fontSize: 10 * sf,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondaryText,
                    ),
                  ))
            : Icon(
                Icons.lock_rounded,
                size: 12 * sf,
                color: AppColors.border.withValues(alpha: 0.5),
              ),
      ),
    );
  }
}

// ── Achievement Badge ─────────────────────────────────────────────────

class _AchievementBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool earned;
  final Color color;
  final double sf;

  const _AchievementBadge({
    required this.icon,
    required this.label,
    required this.earned,
    required this.color,
    required this.sf,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40 * sf,
          height: 40 * sf,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: earned
                ? color.withValues(alpha: 0.15)
                : AppColors.surface.withValues(alpha: 0.3),
            border: Border.all(
              color: earned
                  ? color.withValues(alpha: 0.5)
                  : AppColors.border.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: earned
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 20 * sf,
            color: earned
                ? color
                : AppColors.border.withValues(alpha: 0.4),
          ),
        ),
        SizedBox(height: 4 * sf),
        SizedBox(
          width: 56 * sf,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.nunito(
              fontSize: 9 * sf,
              fontWeight: FontWeight.w600,
              color: earned
                  ? AppColors.primaryText.withValues(alpha: 0.8)
                  : AppColors.secondaryText.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Compact stat chip ─────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String? label;
  final bool animate;
  final double sf;
  final VoidCallback? onTap;

  const _StatChip(this.icon, this.color, this.value, {this.label, this.animate = false, this.sf = 1.0, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget chip = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * sf, vertical: 6 * sf),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14 * sf),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8 * sf,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16 * sf, color: color),
                SizedBox(width: 4 * sf),
                Text(
                  value,
                  style: AppFonts.fredoka(
                    fontSize: 15 * sf,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            if (label != null) ...[
              SizedBox(height: 1 * sf),
              Text(
                label!,
                style: AppFonts.nunito(
                  fontSize: 9 * sf,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (animate) {
      chip = chip
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.05, duration: 1200.ms);
    }

    return chip;
  }
}

// ── Completion Ring Painter ───────────────────────────────────────────

class _CompletionRingPainter extends CustomPainter {
  final double progress;
  final double sf;

  _CompletionRingPainter({required this.progress, required this.sf});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6 * sf;
    final strokeWidth = 6.0 * sf;

    // Background ring
    final bgPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: [
            AppColors.electricBlue,
            AppColors.violet,
            AppColors.magenta,
            AppColors.electricBlue,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        progressPaint,
      );

      // End dot glow
      final endAngle = -pi / 2 + 2 * pi * progress;
      final dotCenter = Offset(
        center.dx + radius * cos(endAngle),
        center.dy + radius * sin(endAngle),
      );
      final dotPaint = Paint()
        ..color = AppColors.electricBlue.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * sf);
      canvas.drawCircle(dotCenter, 3 * sf, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompletionRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Firefly background (adapted from FloatingHeartsBackground) ─────────

class _FireflyBackground extends StatefulWidget {
  const _FireflyBackground();

  @override
  State<_FireflyBackground> createState() => _FireflyBackgroundState();
}

class _FireflyBackgroundState extends State<_FireflyBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Firefly> _fireflies;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    final rng = Random(42);
    _fireflies = List.generate(20, (_) => _Firefly(rng));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _FireflyPainter(
              fireflies: _fireflies,
              time: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _Firefly {
  final double x;
  final double y;
  final double speed;
  final double phase;
  final double size;

  _Firefly(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.3 + rng.nextDouble() * 0.7,
        phase = rng.nextDouble() * 2 * pi,
        size = 1.5 + rng.nextDouble() * 2.0;
}

class _FireflyPainter extends CustomPainter {
  final List<_Firefly> fireflies;
  final double time;

  _FireflyPainter({required this.fireflies, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final fly in fireflies) {
      final t = time * fly.speed + fly.phase;
      final x = (fly.x + sin(t * 2 * pi) * 0.03) * size.width;
      final y = (fly.y + cos(t * 2 * pi * 0.7) * 0.02) * size.height;
      final alpha = (0.3 + sin(t * 2 * pi * 1.5) * 0.3).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = AppColors.starGold.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fly.size * 2);

      canvas.drawCircle(Offset(x, y), fly.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireflyPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════
//  AVATAR HOME FRAME
//  Alive rectangular container with animated gradient, ambient glow,
//  and floating particles. Replaces the old circular avatar container.
// ═══════════════════════════════════════════════════════════════════════

class _AvatarHomeFrame extends StatelessWidget {
  final double width;
  final double height;
  final double sf;
  final AnimationController frameController;
  final AnimationController glowController;
  final AvatarConfig avatar;
  final AvatarController avatarController;
  final int level;
  final VoidCallback? onEditTap;

  const _AvatarHomeFrame({
    required this.width,
    required this.height,
    required this.sf,
    required this.frameController,
    required this.glowController,
    required this.avatar,
    required this.avatarController,
    required this.level,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16 * sf);

    return AnimatedBuilder(
      animation: Listenable.merge([frameController, glowController]),
      builder: (context, child) {
        final t = frameController.value;
        final glowT = glowController.value;
        final glowAlpha = 0.20 + glowT * 0.20;
        final borderAlpha = 0.35 + glowT * 0.25;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Ambient glow behind frame
            Positioned(
              left: -8 * sf,
              top: -8 * sf,
              right: -8 * sf,
              bottom: -8 * sf,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20 * sf),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violet.withValues(alpha: glowAlpha),
                      blurRadius: 24 + glowT * 12,
                      spreadRadius: 2 * sf,
                    ),
                    BoxShadow(
                      color: AppColors.magenta.withValues(alpha: glowAlpha * 0.35),
                      blurRadius: 36 + glowT * 16,
                      spreadRadius: 1 * sf,
                    ),
                  ],
                ),
              ),
            ),

            // Main frame container
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: AppColors.violet.withValues(alpha: borderAlpha),
                  width: 2.5 * sf,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14 * sf),
                child: Stack(
                  children: [
                    // Animated gradient background
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HomeFrameBgPainter(phase: t),
                      ),
                    ),

                    // Floating particles
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FloatingParticlePainter(phase: t),
                      ),
                    ),

                    // Avatar — centered, full bust, no background
                    Center(
                      child: AvatarWidget(
                        config: avatar,
                        size: width * 0.88,
                        controller: avatarController,
                        showBackground: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Edit badge — bottom-right
            Positioned(
              right: -6 * sf,
              bottom: -6 * sf,
              child: GestureDetector(
                onTap: onEditTap,
                child: Container(
                  width: 30 * sf,
                  height: 30 * sf,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.violet,
                    border: Border.all(
                      color: AppColors.background,
                      width: 2.5 * sf,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.4),
                        blurRadius: 8 * sf,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 14 * sf,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Level badge — top-left
            Positioned(
              left: -6 * sf,
              top: -6 * sf,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * sf, vertical: 3 * sf),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.starGold, Color(0xFFFFAA00)],
                  ),
                  borderRadius: BorderRadius.circular(10 * sf),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  'Lv $level',
                  style: AppFonts.fredoka(
                    fontSize: 11 * sf,
                    fontWeight: FontWeight.w700,
                    color: AppColors.background,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Paints a slowly shifting gradient background for the avatar home frame.
class _HomeFrameBgPainter extends CustomPainter {
  final double phase; // 0.0 to 1.0, loops

  const _HomeFrameBgPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    // Shift gradient angle over time for a living feel
    final angle = phase * 2 * pi;
    final dx = cos(angle) * 0.4;
    final dy = sin(angle) * 0.4;

    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(dx - 0.5, dy - 0.8),
        end: Alignment(-dx + 0.5, -dy + 0.8),
        colors: const [
          Color(0xFF1A1040), // deep indigo
          Color(0xFF0E1A3A), // dark navy
          Color(0xFF1A1040), // back to indigo
          Color(0xFF12102A), // very dark purple
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, paint);

    // Subtle radial highlight at center (avatar spotlight)
    final centerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(dx * 0.2, dy * 0.15 - 0.1),
        radius: 0.9,
        colors: [
          const Color(0xFF2A1F5E).withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, centerPaint);
  }

  @override
  bool shouldRepaint(_HomeFrameBgPainter old) =>
      (old.phase * 60).round() != (phase * 60).round();
}

/// Paints 3 slow-moving luminous dots inside the avatar home frame.
class _FloatingParticlePainter extends CustomPainter {
  final double phase;

  const _FloatingParticlePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 3 particles with different speeds and paths
    const particles = [
      (xSpeed: 0.7, ySpeed: 1.0, xOff: 0.25, yOff: 0.30, radius: 2.5),
      (xSpeed: 1.3, ySpeed: 0.8, xOff: 0.70, yOff: 0.55, radius: 2.0),
      (xSpeed: 0.9, ySpeed: 1.2, xOff: 0.50, yOff: 0.80, radius: 1.8),
    ];

    for (final p in particles) {
      final x = w * (p.xOff + sin(phase * pi * 2 * p.xSpeed) * 0.12);
      final y = h * (p.yOff + cos(phase * pi * 2 * p.ySpeed) * 0.08);
      final alpha = 0.15 + sin(phase * pi * 2 * p.xSpeed + 1.5) * 0.10;

      final paint = Paint()
        ..color = AppColors.violet.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 2);

      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_FloatingParticlePainter old) =>
      (old.phase * 60).round() != (phase * 60).round();
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../data/dolch_words.dart';
import '../services/high_score_service.dart';
import '../services/progress_service.dart';
import '../services/review_service.dart';
import '../services/stats_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_tutorial_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Parent Gate — simple math challenge to keep kids out
// ─────────────────────────────────────────────────────────────────────────────

class ParentGate extends StatefulWidget {
  final VoidCallback onVerified;

  const ParentGate({super.key, required this.onVerified});

  @override
  State<ParentGate> createState() => _ParentGateState();
}

class _ParentGateState extends State<ParentGate> {
  late int _a, _b, _answer;
  late String _question;
  late List<int> _options;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    final rng = Random();
    // Mix of multiplication and addition
    if (rng.nextBool()) {
      _a = 3 + rng.nextInt(8); // 3..10
      _b = 2 + rng.nextInt(9); // 2..10
      _answer = _a * _b;
      _question = 'What is $_a x $_b?';
    } else {
      _a = 10 + rng.nextInt(30); // 10..39
      _b = 5 + rng.nextInt(20); // 5..24
      _answer = _a + _b;
      _question = 'What is $_a + $_b?';
    }

    // Generate 3 wrong answers close to the real one
    final wrongSet = <int>{};
    while (wrongSet.length < 3) {
      final offset = rng.nextInt(11) - 5; // -5..+5
      final wrong = _answer + (offset == 0 ? (rng.nextBool() ? 1 : -1) : offset);
      if (wrong != _answer && wrong > 0) wrongSet.add(wrong);
    }
    _options = [...wrongSet, _answer]..shuffle(rng);
    _wrong = false;
  }

  void _onAnswer(int value) {
    if (value == _answer) {
      widget.onVerified();
    } else {
      setState(() {
        _wrong = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _generate();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 36,
              color: AppColors.violet.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'Parent Check',
              style: AppFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solve to continue',
              style: AppFonts.nunito(
                fontSize: 14,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _question,
              style: AppFonts.fredoka(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _options.map((opt) {
                return GestureDetector(
                  onTap: () => _onAnswer(opt),
                  child: Container(
                    width: 72,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$opt',
                      style: AppFonts.fredoka(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_wrong) ...[
              const SizedBox(height: 14),
              Text(
                'Not quite - try again!',
                style: AppFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parent Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class ParentDashboardScreen extends StatefulWidget {
  final ProgressService progressService;
  final StatsService statsService;
  final StreakService streakService;
  final HighScoreService highScoreService;
  final ReviewService? reviewService;
  final String playerName;

  const ParentDashboardScreen({
    super.key,
    required this.progressService,
    required this.statsService,
    required this.streakService,
    required this.highScoreService,
    this.reviewService,
    this.playerName = '',
  });

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  // Zone accent colors
  static const List<Color> _zoneColors = [
    Color(0xFF10B981), // Whispering Woods — forest green
    Color(0xFF3B82F6), // Shimmer Shore — ocean blue
    Color(0xFFA78BFA), // Crystal Peaks — icy lavender
    Color(0xFFF59E0B), // Skyward Kingdom — warm gold
    Color(0xFF8B5CF6), // Celestial Crown — nebula purple
  ];

  static const List<String> _miniGameNames = [
    'Unicorn Flight',
    'Lightning Speller',
    'Word Bubbles',
    'Memory Match',
    'Falling Letters',
    'Cat Letter Toss',
    'Letter Drop',
    'Rhyme Time',
    'Star Catcher',
    'Paint Splash',
  ];

  static const List<String> _miniGameIds = [
    'unicorn_flight',
    'lightning_speller',
    'word_bubbles',
    'memory_match',
    'falling_letters',
    'cat_letter_toss',
    'letter_drop',
    'rhyme_time',
    'star_catcher',
    'paint_splash',
  ];

  static const List<IconData> _miniGameIcons = [
    Icons.flight_rounded,
    Icons.bolt_rounded,
    Icons.bubble_chart_rounded,
    Icons.grid_view_rounded,
    Icons.arrow_downward_rounded,
    Icons.pets_rounded,
    Icons.text_fields_rounded,
    Icons.music_note_rounded,
    Icons.star_rounded,
    Icons.color_lens_rounded,
  ];

  int get _currentLevel => widget.progressService.highestUnlockedLevel;
  int get _totalWordsMastered => widget.progressService.totalWordsCompleted;
  int get _totalStars => widget.progressService.totalStars;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Sliver App Bar ──
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: Semantics(
              label: 'Go back',
              hint: 'Return to home screen',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primaryText),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
              title: Text(
                'Parent Dashboard',
                style: AppFonts.fredoka(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.surfaceVariant, AppColors.background],
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeaderCard(),
                const SizedBox(height: 16),
                _buildProgressOverviewCard(),
                const SizedBox(height: 16),
                _buildActivityChart(),
                const SizedBox(height: 16),
                _buildStrengthsCard(),
                const SizedBox(height: 16),
                _buildMiniGameCard(),
                const SizedBox(height: 16),
                _buildInsightsCard(),
                const SizedBox(height: 16),
                _buildSettingsSection(),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 1. Header Card
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildHeaderCard() {
    final zone = DolchWords.zoneForLevel(_currentLevel);
    final streak = widget.streakService.currentStreak;
    final longestStreak = widget.streakService.longestStreak;
    final stats = widget.statsService.stats;

    return _DashboardCard(
      child: Row(
        children: [
          // Avatar placeholder (circle with initial)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.4),
                  AppColors.electricBlue.withValues(alpha: 0.3),
                ],
              ),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.playerName.isNotEmpty
                  ? widget.playerName[0].toUpperCase()
                  : '?',
              style: AppFonts.fredoka(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playerName.isNotEmpty ? widget.playerName : 'Player',
                  style: AppFonts.fredoka(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Level $_currentLevel of ${DolchWords.totalLevels}  --  ${zone.name}',
                  style: AppFonts.nunito(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.local_fire_department_rounded,
                      color: AppColors.flameOrange,
                      value: '$streak day${streak == 1 ? '' : 's'}',
                    ),
                    const SizedBox(width: 14),
                    _MiniStat(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.starGold,
                      value: 'Best: $longestStreak',
                    ),
                    const SizedBox(width: 14),
                    _MiniStat(
                      icon: Icons.timer_rounded,
                      color: AppColors.cyan,
                      value: '${stats.totalSessions} sessions',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 2. Progress Overview
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildProgressOverviewCard() {
    const totalWords = 220; // Dolch words
    final wordsLearned = _totalWordsMastered;

    // Count tier completions across all levels
    int explorerComplete = 0, adventurerComplete = 0, championComplete = 0;
    for (int l = 1; l <= DolchWords.totalLevels; l++) {
      final lp = widget.progressService.getLevel(l);
      if (lp.highestCompletedTier >= 1) explorerComplete++;
      if (lp.highestCompletedTier >= 2) adventurerComplete++;
      if (lp.highestCompletedTier >= 3) championComplete++;
    }

    // Words per zone
    final zoneWordCounts = <int>[];
    for (final zone in DolchWords.zones) {
      int count = 0;
      for (int l = zone.startLevel; l <= zone.endLevel; l++) {
        final lp = widget.progressService.getLevel(l);
        count += lp.wordStats.values.where((s) => s.attempts > 0).length;
      }
      zoneWordCounts.add(count);
    }

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Progress Overview', icon: Icons.trending_up_rounded),
          const SizedBox(height: 16),

          // Circular progress + stats
          Row(
            children: [
              // Circular progress
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _CircularProgressPainter(
                    progress: (wordsLearned / totalWords).clamp(0.0, 1.0),
                    color: AppColors.emerald,
                    bgColor: AppColors.border.withValues(alpha: 0.3),
                    strokeWidth: 8,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$wordsLearned',
                          style: AppFonts.fredoka(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emerald,
                          ),
                        ),
                        Text(
                          'of $totalWords',
                          style: AppFonts.nunito(
                            fontSize: 11,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Tier completions
              Expanded(
                child: Column(
                  children: [
                    _TierRow(
                      label: 'Explorer',
                      count: explorerComplete,
                      total: DolchWords.totalLevels,
                      color: AppColors.bronze,
                    ),
                    const SizedBox(height: 8),
                    _TierRow(
                      label: 'Adventurer',
                      count: adventurerComplete,
                      total: DolchWords.totalLevels,
                      color: AppColors.silver,
                    ),
                    const SizedBox(height: 8),
                    _TierRow(
                      label: 'Champion',
                      count: championComplete,
                      total: DolchWords.totalLevels,
                      color: AppColors.starGold,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: AppColors.starGold),
                        const SizedBox(width: 6),
                        Text(
                          '$_totalStars / ${DolchWords.totalLevels * 3} Stars',
                          style: AppFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Zone breakdown bars
          Text(
            'Words by Zone',
            style: AppFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(DolchWords.zones.length, (i) {
            final zone = DolchWords.zones[i];
            final maxWords = zone.levelCount * 10;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ZoneBar(
                name: zone.name,
                count: zoneWordCounts[i],
                maxCount: maxWords,
                color: _zoneColors[i],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 3. Activity Chart (Last 7 Days)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildActivityChart() {
    final dailyStats = widget.statsService.getDailyStats(7);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Last 7 Days', icon: Icons.calendar_today_rounded),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: const Size(double.infinity, 140),
              painter: _BarChartPainter(
                data: dailyStats
                    .map((e) => e.value.wordsPlayed.toDouble())
                    .toList(),
                labels: dailyStats.map((e) {
                  final parts = e.key.split('-');
                  return '${parts[1]}/${parts[2]}';
                }).toList(),
                barColor: AppColors.electricBlue,
                labelColor: AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Words practiced per day',
              style: AppFonts.nunito(
                fontSize: 12,
                color: AppColors.secondaryText.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 4. Strengths & Struggles
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildStrengthsCard() {
    final stats = widget.statsService.stats;

    // Compute per-letter accuracy
    final letterAccuracy = <String, double>{};
    const allLetters = 'abcdefghijklmnopqrstuvwxyz';
    for (final l in allLetters.split('')) {
      final correct = stats.letterTaps[l] ?? 0;
      final wrong = stats.wrongLetterTaps[l] ?? 0;
      final total = correct + wrong;
      if (total > 0) {
        letterAccuracy[l] = correct / total;
      }
    }

    final sorted = letterAccuracy.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final strongest = sorted.take(5).toList();
    final weakest = sorted.reversed.take(5).toList();

    // Top confusions
    final confusions = widget.statsService.topConfusions.take(5).toList();

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Strengths & Struggles', icon: Icons.psychology_rounded),
          const SizedBox(height: 14),

          if (sorted.isEmpty)
            const _EmptyState(message: 'Play more to see letter accuracy data!')
          else ...[
            // Strongest
            Text(
              'Strongest Letters',
              style: AppFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.success.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: strongest.map((e) => _LetterChip(
                letter: e.key,
                accuracy: e.value,
                isStrong: true,
              )).toList(),
            ),

            const SizedBox(height: 14),

            // Struggling
            if (weakest.isNotEmpty && weakest.first.value < 0.9) ...[
              Text(
                'Needs Practice',
                style: AppFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.starGold.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: weakest
                    .where((e) => e.value < 0.9)
                    .map((e) => _LetterChip(
                      letter: e.key,
                      accuracy: e.value,
                      isStrong: false,
                    ))
                    .toList(),
              ),
            ],

            // Confused pairs
            if (confusions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Common Confusions',
                style: AppFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.magenta.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: confusions.map((e) {
                  final parts = e.key.split('_for_');
                  if (parts.length == 2) {
                    return _ConfusionChip(
                      tapped: parts[0],
                      expected: parts[1],
                      count: e.value,
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 5. Mini Game Performance
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildMiniGameCard() {
    final stats = widget.statsService.stats;

    // Only show games that have been played
    final playedGames = <int>[];
    for (int i = 0; i < _miniGameIds.length; i++) {
      final gameStats = stats.miniGameStats[_miniGameIds[i]];
      if (gameStats != null && gameStats.timesPlayed > 0) {
        playedGames.add(i);
      }
    }

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Mini Games', icon: Icons.sports_esports_rounded),
          const SizedBox(height: 14),

          if (playedGames.isEmpty)
            const _EmptyState(message: 'No mini games played yet!')
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: playedGames.map((i) {
                final gameStats = stats.miniGameStats[_miniGameIds[i]]!;
                final highScore = widget.highScoreService.getPersonalBest(_miniGameIds[i]);
                return _MiniGameTile(
                  name: _miniGameNames[i],
                  icon: _miniGameIcons[i],
                  highScore: highScore,
                  timesPlayed: gameStats.timesPlayed,
                  color: _zoneColors[i % _zoneColors.length],
                );
              }).toList(),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 6. Learning Insights
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildInsightsCard() {
    final stats = widget.statsService.stats;
    final accuracy = widget.statsService.accuracy;
    final reviewSummary = widget.reviewService?.getReviewSummary();

    // Average session duration
    final avgMinutes = stats.totalSessions > 0
        ? (stats.totalPlayTimeSeconds / 60 / stats.totalSessions).round()
        : 0;

    // Build recommendations
    final recommendations = <_Recommendation>[];

    // Recommend next level
    final nextLevel = widget.progressService.highestUnlockedLevel;
    if (nextLevel <= DolchWords.totalLevels) {
      final lp = widget.progressService.getLevel(nextLevel);
      if (!lp.isComplete) {
        recommendations.add(_Recommendation(
          icon: Icons.arrow_forward_rounded,
          color: AppColors.emerald,
          text: 'Continue Level $nextLevel: ${DolchWords.levelName(nextLevel)}',
        ));
      }
    }

    // Review due words
    if (reviewSummary != null && reviewSummary.dueToday > 0) {
      recommendations.add(_Recommendation(
        icon: Icons.refresh_rounded,
        color: AppColors.electricBlue,
        text: '${reviewSummary.dueToday} word${reviewSummary.dueToday == 1 ? '' : 's'} due for review',
      ));
    }

    // Practice confused letters
    final confusions = widget.statsService.topConfusions;
    if (confusions.isNotEmpty) {
      final top = confusions.first;
      final parts = top.key.split('_for_');
      if (parts.length == 2) {
        recommendations.add(_Recommendation(
          icon: Icons.edit_rounded,
          color: AppColors.magenta,
          text: 'Practice confused letters: ${parts[0].toUpperCase()} / ${parts[1].toUpperCase()}',
        ));
      }
    }

    // Streak encouragement
    final streak = widget.streakService.currentStreak;
    if (streak == 0) {
      recommendations.add(const _Recommendation(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.flameOrange,
        text: 'Start a streak -- play today!',
      ));
    } else if (streak < 7) {
      recommendations.add(_Recommendation(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.flameOrange,
        text: '${7 - streak} more day${7 - streak == 1 ? '' : 's'} to a weekly streak!',
      ));
    }

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Learning Insights', icon: Icons.lightbulb_rounded),
          const SizedBox(height: 14),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _InsightStat(
                  label: 'Accuracy',
                  value: '${(accuracy * 100).round()}%',
                  color: accuracy >= 0.8 ? AppColors.success : AppColors.starGold,
                ),
              ),
              Expanded(
                child: _InsightStat(
                  label: 'Avg Session',
                  value: avgMinutes > 0 ? '$avgMinutes min' : '--',
                  color: AppColors.electricBlue,
                ),
              ),
              Expanded(
                child: _InsightStat(
                  label: 'Perfect Words',
                  value: '${stats.totalPerfectWords}',
                  color: AppColors.emerald,
                ),
              ),
            ],
          ),

          if (reviewSummary != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _InsightStat(
                    label: 'Mastered (SRS)',
                    value: '${reviewSummary.mastered}',
                    color: AppColors.starGold,
                  ),
                ),
                Expanded(
                  child: _InsightStat(
                    label: 'Words Heard',
                    value: '${stats.totalWordsHeard}',
                    color: AppColors.cyan,
                  ),
                ),
                Expanded(
                  child: _InsightStat(
                    label: 'Total Played',
                    value: '${stats.totalWordsCompleted}',
                    color: AppColors.violet,
                  ),
                ),
              ],
            ),
          ],

          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Recommendations',
              style: AppFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            ...recommendations.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(r.icon, size: 18, color: r.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.text,
                      style: AppFonts.nunito(
                        fontSize: 13,
                        color: AppColors.primaryText.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 500.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 7. Settings Section
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildSettingsSection() {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Settings', icon: Icons.settings_rounded),
          const SizedBox(height: 14),

          // Free play mode toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.all_inclusive_rounded,
                    color: AppColors.emerald, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Free Play Mode',
                        style: AppFonts.fredoka(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                      Text(
                        'Skip star coin costs and time limits for mini games',
                        style: AppFonts.nunito(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: widget.progressService.freePlayMode,
                  onChanged: (v) {
                    setState(() {
                      widget.progressService.freePlayMode = v;
                    });
                  },
                  activeTrackColor: AppColors.emerald,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Replay tutorial
          _SettingsButton(
            icon: Icons.school_rounded,
            label: 'Replay Tutorial',
            color: AppColors.electricBlue,
            onTap: () => _replayTutorial(context),
            subtitle: 'Show the onboarding guide again',
          ),
          const SizedBox(height: 10),

          // Reset progress
          _SettingsButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset All Progress',
            color: AppColors.error,
            onTap: () => _confirmReset(context),
          ),
          const SizedBox(height: 10),

          // Export (placeholder)
          _SettingsButton(
            icon: Icons.download_rounded,
            label: 'Export Data',
            color: AppColors.secondaryText.withValues(alpha: 0.4),
            onTap: null,
            subtitle: 'Coming soon',
          ),
        ],
      ),
    ).animate().fadeIn(delay: 600.ms, duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  void _replayTutorial(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingTutorialScreen(
          onComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reset Progress?',
          style: AppFonts.fredoka(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
        ),
        content: Text(
          'This will erase all progress, stats, and high scores for ${widget.playerName.isNotEmpty ? widget.playerName : 'this player'}. This cannot be undone.',
          style: AppFonts.nunito(
            fontSize: 14,
            color: AppColors.secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmResetFinal(context);
            },
            child: Text(
              'Reset',
              style: AppFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Second confirmation dialog — requires explicit "Yes, reset everything" tap.
  void _confirmResetFinal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            Text(
              'Are you sure?',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        content: Text(
          'All stars, words learned, streaks, and high scores will be permanently deleted. This action cannot be undone.',
          style: AppFonts.nunito(
            fontSize: 14,
            color: AppColors.secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep Progress',
              style: AppFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.emerald,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.progressService.resetAll();
              await widget.statsService.resetAll();
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Progress reset complete',
                    style: AppFonts.nunito(fontSize: 14, color: Colors.white),
                  ),
                  backgroundColor: AppColors.surface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: Text(
              'Yes, reset everything',
              style: AppFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Helper Widgets & Painters
// ═════════════════════════════════════════════════════════════════════════════

class _DashboardCard extends StatelessWidget {
  final Widget child;
  const _DashboardCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.electricBlue.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  const _MiniStat({required this.icon, required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          message,
          style: AppFonts.nunito(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: AppColors.secondaryText.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ── Tier row (progress bar) ─────────────────────────────────────────────

class _TierRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;
  const _TierRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: AppFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? count / total : 0,
              backgroundColor: AppColors.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count/$total',
          style: AppFonts.nunito(
            fontSize: 11,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

// ── Zone bar ────────────────────────────────────────────────────────────

class _ZoneBar extends StatelessWidget {
  final String name;
  final int count;
  final int maxCount;
  final Color color;
  const _ZoneBar({
    required this.name,
    required this.count,
    required this.maxCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: AppFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.9),
              ),
            ),
            Text(
              '$count / $maxCount',
              style: AppFonts.nunito(
                fontSize: 11,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: maxCount > 0 ? count / maxCount : 0,
            backgroundColor: AppColors.border.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.7)),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// ── Letter accuracy chip ────────────────────────────────────────────────

class _LetterChip extends StatelessWidget {
  final String letter;
  final double accuracy;
  final bool isStrong;
  const _LetterChip({
    required this.letter,
    required this.accuracy,
    required this.isStrong,
  });

  @override
  Widget build(BuildContext context) {
    final color = isStrong ? AppColors.success : AppColors.starGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            letter.toUpperCase(),
            style: AppFonts.fredoka(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(accuracy * 100).round()}%',
            style: AppFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confusion chip ──────────────────────────────────────────────────────

class _ConfusionChip extends StatelessWidget {
  final String tapped;
  final String expected;
  final int count;
  const _ConfusionChip({
    required this.tapped,
    required this.expected,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.magenta.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.magenta.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${tapped.toUpperCase()} / ${expected.toUpperCase()}',
            style: AppFonts.fredoka(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.magenta.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${count}x',
            style: AppFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.magenta.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini game tile ──────────────────────────────────────────────────────

class _MiniGameTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final int highScore;
  final int timesPlayed;
  final Color color;
  const _MiniGameTile({
    required this.name,
    required this.icon,
    required this.highScore,
    required this.timesPlayed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.fredoka(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'Best: $highScore',
            style: AppFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.starGold,
            ),
          ),
          Text(
            'Played $timesPlayed${timesPlayed == 1 ? ' time' : ' times'}',
            style: AppFonts.nunito(
              fontSize: 10,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Insight stat ────────────────────────────────────────────────────────

class _InsightStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InsightStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppFonts.fredoka(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppFonts.nunito(
            fontSize: 11,
            color: AppColors.secondaryText,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Settings button ─────────────────────────────────────────────────────

class _SettingsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? subtitle;
  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppFonts.nunito(
                        fontSize: 11,
                        color: AppColors.secondaryText.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: color.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Recommendation {
  final IconData icon;
  final Color color;
  final String text;
  const _Recommendation({required this.icon, required this.color, required this.text});
}

// ═════════════════════════════════════════════════════════════════════════════
// Custom Painters
// ═════════════════════════════════════════════════════════════════════════════

// ── Circular progress painter ───────────────────────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) / 2) - strokeWidth;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    if (progress > 0) {
      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, // Start from top
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      // Subtle glow on progress end
      final endAngle = -pi / 2 + sweepAngle;
      final glowX = center.dx + radius * cos(endAngle);
      final glowY = center.dy + radius * sin(endAngle);
      canvas.drawCircle(
        Offset(glowX, glowY),
        strokeWidth * 0.8,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Bar chart painter ───────────────────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color barColor;
  final Color labelColor;

  _BarChartPainter({
    required this.data,
    required this.labels,
    required this.barColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.reduce(max);
    final effectiveMax = maxVal > 0 ? maxVal : 1.0;
    final barCount = data.length;
    final barWidth = (size.width - (barCount + 1) * 8) / barCount;
    final chartHeight = size.height - 24; // Reserve space for labels

    // Grid lines (subtle)
    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 3; i++) {
      final y = chartHeight * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (int i = 0; i < barCount; i++) {
      final x = 8.0 + i * (barWidth + 8);
      final barHeight = (data[i] / effectiveMax) * (chartHeight - 4);
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(4),
      );

      // Bar fill
      canvas.drawRRect(
        barRect,
        Paint()..color = barColor.withValues(alpha: data[i] > 0 ? 0.6 : 0.1),
      );

      // Glow on non-zero bars
      if (data[i] > 0) {
        canvas.drawRRect(
          barRect,
          Paint()
            ..color = barColor.withValues(alpha: 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      // Value label on top of bar
      if (data[i] > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${data[i].round()}',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: barColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(
            x + (barWidth - textPainter.width) / 2,
            chartHeight - barHeight - 14,
          ),
        );
      }

      // Date label below
      if (i < labels.length) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 9,
              color: labelColor.withValues(alpha: 0.6),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(
            x + (barWidth - labelPainter.width) / 2,
            chartHeight + 6,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.data != data;
}

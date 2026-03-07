import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/avatar_options.dart';
import '../models/player_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// Activity-based treasure chest widget.
///
/// Chests are earned at 10, 25, and 50 words per day (max 3 per day).
/// Chest tier (wooden/silver/golden) based on streak affects reward rarity.
/// Rewards are VISUAL (icons, colors, effects) — never text labels.
///
/// States:
/// - [_ChestState.earning]  — progress arc filling toward next chest
/// - [_ChestState.ready]    — chest glowing, tap to open
/// - [_ChestState.opening]  — dramatic open animation
/// - [_ChestState.revealed] — reward icon displayed with celebration
/// - [_ChestState.complete] — all 3 daily chests claimed, come back tomorrow
class DailyTreasure extends StatefulWidget {
  final ProfileService profileService;
  final int wordsPlayedToday;
  final int currentStreak;

  /// Called when the chest is opened with the reward item ID.
  final ValueChanged<String>? onRewardEarned;

  const DailyTreasure({
    super.key,
    required this.profileService,
    required this.wordsPlayedToday,
    required this.currentStreak,
    this.onRewardEarned,
  });

  @override
  State<DailyTreasure> createState() => _DailyTreasureState();
}

enum _ChestState { earning, ready, opening, revealed, complete }

enum _ChestTier { wooden, silver, golden }

class _DailyTreasureState extends State<DailyTreasure>
    with TickerProviderStateMixin {
  late _ChestState _state;
  TreasureReward? _reward;
  late AnimationController _wobbleController;
  late AnimationController _glowController;
  late AnimationController _revealController;

  @override
  void initState() {
    super.initState();

    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _updateState();
  }

  @override
  void didUpdateWidget(DailyTreasure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wordsPlayedToday != widget.wordsPlayedToday) {
      // Words changed — re-evaluate state
      if (_state != _ChestState.opening && _state != _ChestState.revealed) {
        _updateState();
      }
    }
  }

  void _updateState() {
    if (widget.profileService.allDailyChestsComplete) {
      _state = _ChestState.complete;
    } else if (widget.profileService.hasChestReady) {
      _state = _ChestState.ready;
    } else {
      _state = _ChestState.earning;
    }
  }

  _ChestTier get _tier {
    if (widget.currentStreak >= 7) return _ChestTier.golden;
    if (widget.currentStreak >= 3) return _ChestTier.silver;
    return _ChestTier.wooden;
  }

  Color get _tierColor => switch (_tier) {
        _ChestTier.wooden => AppColors.chestWood,
        _ChestTier.silver => AppColors.chestSilver,
        _ChestTier.golden => AppColors.chestGold,
      };

  IconData get _tierIcon => switch (_tier) {
        _ChestTier.wooden => Icons.inventory_2_rounded,
        _ChestTier.silver => Icons.inventory_2_rounded,
        _ChestTier.golden => Icons.inventory_2_rounded,
      };

  /// Allowed rarities based on chest tier.
  Set<RewardRarity> get _allowedRarities => switch (_tier) {
        _ChestTier.wooden => {RewardRarity.common},
        _ChestTier.silver => {RewardRarity.common, RewardRarity.uncommon},
        _ChestTier.golden => {
            RewardRarity.common,
            RewardRarity.uncommon,
            RewardRarity.rare,
          },
      };

  /// Pick a random reward the player doesn't already own,
  /// filtered by the allowed rarities for the current chest tier.
  TreasureReward _pickReward() {
    final rng = Random();
    final owned = widget.profileService.unlockedItems;
    final rarities = _allowedRarities;

    // Filter to un-owned rewards of allowed rarity
    final available = allTreasureRewards
        .where((r) => !owned.contains(r.id) && rarities.contains(r.rarity))
        .toList();

    if (available.isNotEmpty) {
      return available[rng.nextInt(available.length)];
    }

    // All allowed rewards owned — give a random sticker (always re-earnable)
    final stickers = allTreasureRewards
        .where((r) =>
            r.category == TreasureCategory.sticker &&
            rarities.contains(r.rarity))
        .toList();
    if (stickers.isNotEmpty) {
      return stickers[rng.nextInt(stickers.length)];
    }

    // Ultimate fallback — any sticker
    final allStickers = allTreasureRewards
        .where((r) => r.category == TreasureCategory.sticker)
        .toList();
    return allStickers[rng.nextInt(allStickers.length)];
  }

  /// Apply the reward to the player's profile.
  Future<void> _applyReward(TreasureReward reward) async {
    // Unlock the item
    await widget.profileService.unlockItem(reward.id);

    // Apply effect flags directly to avatar if it's an effect reward
    if (reward.category == TreasureCategory.effect &&
        reward.effectFlag != null) {
      final avatar = widget.profileService.avatar;
      AvatarConfig updated;
      switch (reward.effectFlag) {
        case 'hasSparkle':
          updated = avatar.copyWith(hasSparkle: true);
        case 'hasRainbowSparkle':
          updated = avatar.copyWith(hasRainbowSparkle: true);
        case 'hasGoldenGlow':
          updated = avatar.copyWith(hasGoldenGlow: true);
        default:
          return;
      }
      await widget.profileService.setAvatar(updated);
    }

    // Apply face paint to avatar
    if (reward.category == TreasureCategory.facePaint &&
        reward.facePaintIndex != null) {
      final avatar = widget.profileService.avatar;
      final updated = avatar.copyWith(facePaint: reward.facePaintIndex);
      await widget.profileService.setAvatar(updated);
    }

    // Apply glasses to avatar
    if (reward.category == TreasureCategory.glasses &&
        reward.glassesIndex != null) {
      final avatar = widget.profileService.avatar;
      final updated = avatar.copyWith(glassesStyle: reward.glassesIndex);
      await widget.profileService.setAvatar(updated);
    }

    // Award sticker records for sticker rewards
    if (reward.category == TreasureCategory.sticker) {
      await widget.profileService.awardSticker(
        StickerRecord(
          stickerId: reward.id,
          dateEarned: DateTime.now(),
          category: 'treasure',
        ),
      );
    }

    // Persist the reward ID
    await widget.profileService.setLastChestRewardId(reward.id);
    await widget.profileService.setLastChestReward(reward.id);
  }

  void _onTap() async {
    switch (_state) {
      case _ChestState.earning:
      case _ChestState.complete:
        // Shake to show not ready
        _wobbleController.forward(from: 0);

      case _ChestState.ready:
        // Begin opening sequence
        setState(() => _state = _ChestState.opening);

        // Pick reward
        final reward = _pickReward();

        // Dramatic pause
        await Future.delayed(const Duration(milliseconds: 1800));

        if (!mounted) return;
        setState(() {
          _state = _ChestState.revealed;
          _reward = reward;
        });

        _revealController.forward(from: 0);

        // Persist
        await widget.profileService.markChestOpened();
        await _applyReward(reward);
        widget.onRewardEarned?.call(reward.id);

      case _ChestState.opening:
        // Ignore taps during animation
        break;

      case _ChestState.revealed:
        // Tap again to dismiss and check for more chests
        setState(() {
          _reward = null;
          _updateState();
        });
    }
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    _glowController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  // ── Progress ──────────────────────────────────────────────────────

  double get _progress => widget.profileService.chestProgress;
  int get _chestsAvailable => widget.profileService.chestsAvailable;
  int get _chestsEarnedToday => widget.profileService.currentChestIndex;
  int get _chestsClaimedToday =>
      _chestsEarnedToday - _chestsAvailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header — treasure chest icon with daily chest tracker
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.inventory_2_rounded, size: 22, color: _tierColor),
              const SizedBox(width: 8),
              // Daily chest tracker: 3 small chest icons showing earned/claimed status
              _buildDailyChestTracker(),
            ],
          ),
        ),

        GestureDetector(
          onTap: _onTap,
          child: Container(
            width: double.infinity,
            height: 180,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _tierColor.withValues(alpha: 0.3),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildCurrentState(),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds 3 small chest icons showing daily progress (0/3 to 3/3).
  /// Claimed chests are filled, earned-but-unclaimed pulse, unearned are dim.
  Widget _buildDailyChestTracker() {
    final claimed = widget.profileService.allDailyChestsComplete
        ? ProfileService.maxDailyChests
        : _chestsClaimedToday.clamp(0, ProfileService.maxDailyChests);
    final earned = _chestsEarnedToday.clamp(0, ProfileService.maxDailyChests);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _tierColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(ProfileService.maxDailyChests, (i) {
          final isClaimed = i < claimed;
          final isEarned = i < earned;
          final icon = Icon(
            Icons.inventory_2_rounded,
            size: 14,
            color: isClaimed
                ? AppColors.success
                : isEarned
                    ? _tierColor
                    : _tierColor.withValues(alpha: 0.25),
          );

          if (isEarned && !isClaimed) {
            // Pulse unclaimed chests
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: icon
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 0.9, end: 1.15, duration: 800.ms),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: icon,
          );
        }),
      ),
    );
  }

  Widget _buildCurrentState() {
    return switch (_state) {
      _ChestState.earning => _buildEarning(),
      _ChestState.ready => _buildReady(),
      _ChestState.opening => _buildOpening(),
      _ChestState.revealed => _buildRevealed(),
      _ChestState.complete => _buildComplete(),
    };
  }

  // ── Earning State ─────────────────────────────────────────────────
  // Shows a circular progress arc toward the next chest threshold.

  Widget _buildEarning() {
    final chestNumber = _chestsEarnedToday + 1; // 1st, 2nd, or 3rd
    final thresholdIdx = _chestsEarnedToday;
    final currentTarget = thresholdIdx < ProfileService.chestThresholds.length
        ? ProfileService.chestThresholds[thresholdIdx]
        : ProfileService.chestThresholds.last;
    final previousTarget = thresholdIdx > 0
        ? ProfileService.chestThresholds[thresholdIdx - 1]
        : 0;
    final wordsInRange = (widget.wordsPlayedToday - previousTarget)
        .clamp(0, currentTarget - previousTarget);
    final totalInRange = currentTarget - previousTarget;

    return AnimatedBuilder(
      animation: _wobbleController,
      builder: (context, child) {
        final wobble = sin(_wobbleController.value * pi * 4) *
            (1 - _wobbleController.value) *
            0.05;
        return Transform.rotate(angle: wobble, child: child);
      },
      child: Column(
        key: const ValueKey('earning'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular progress arc around chest icon
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background arc
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 6,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                // Progress arc
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 6,
                    backgroundColor: Colors.transparent,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _tierColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                // Chest icon (dimmed) in center
                Icon(
                  _tierIcon,
                  size: 40,
                  color: _tierColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Small word count progress: filled dots for words in current range
          // Show as a compact row of small dots (max ~10 visible)
          _buildCompactProgressDots(wordsInRange, totalInRange),

          const SizedBox(height: 8),

          // Chest number indicator: which chest they're working toward
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(ProfileService.maxDailyChests, (i) {
              final isTarget = i == chestNumber - 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: isTarget ? 10 : 6,
                  height: isTarget ? 10 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < chestNumber - 1
                        ? AppColors.success
                        : isTarget
                            ? _tierColor
                            : _tierColor.withValues(alpha: 0.2),
                    boxShadow: isTarget
                        ? [
                            BoxShadow(
                              color: _tierColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .rotate(begin: -0.005, end: 0.005, duration: 2500.ms);
  }

  /// Compact progress indicator showing filled vs total segments.
  Widget _buildCompactProgressDots(int filled, int total) {
    // Normalize to max 10 visual segments
    const maxDots = 10;
    final segments = total <= maxDots ? total : maxDots;
    final filledSegments =
        total <= maxDots ? filled : (filled * maxDots / total).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(segments, (i) {
          final isFilled = i < filledSegments;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled
                    ? AppColors.starGold
                    : AppColors.border.withValues(alpha: 0.3),
                boxShadow: isFilled
                    ? [
                        BoxShadow(
                          color: AppColors.starGold.withValues(alpha: 0.4),
                          blurRadius: 3,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Complete State ─────────────────────────────────────────────────
  // All 3 daily chests claimed. Sleeping chest, come back tomorrow.

  Widget _buildComplete() {
    return AnimatedBuilder(
      animation: _wobbleController,
      builder: (context, child) {
        final wobble = sin(_wobbleController.value * pi * 4) *
            (1 - _wobbleController.value) *
            0.05;
        return Transform.rotate(angle: wobble, child: child);
      },
      child: Column(
        key: const ValueKey('complete'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Sleeping chest with moon/zzz
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                _tierIcon,
                size: 48,
                color: _tierColor.withValues(alpha: 0.3),
              ),
              // Moon overlay to indicate "sleeping"
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.nightlight_rounded,
                  size: 20,
                  color: AppColors.starGold.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Three green check circles — all done
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(ProfileService.maxDailyChests, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.success.withValues(alpha: 0.6),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Ready State ───────────────────────────────────────────────────
  // Chest is glowing, pulsing, begging to be tapped.

  Widget _buildReady() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _tierColor
                    .withValues(alpha: 0.15 + _glowController.value * 0.2),
                blurRadius: 24 + _glowController.value * 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        key: const ValueKey('ready'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glowing chest
          Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring behind chest
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _tierColor.withValues(alpha: 0.3),
                      _tierColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Icon(
                _tierIcon,
                size: 56,
                color: _tierColor,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 0.92, end: 1.08, duration: 900.ms),
            ],
          ),

          const SizedBox(height: 12),

          // Bouncing hand/tap indicator icon (no text!)
          Icon(
            Icons.touch_app_rounded,
            size: 28,
            color: AppColors.starGold.withValues(alpha: 0.8),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -4, duration: 600.ms)
              .fadeIn(duration: 400.ms)
              .then()
              .fadeOut(duration: 400.ms),
        ],
      ),
    );
  }

  // ── Opening State ─────────────────────────────────────────────────
  // Dramatic animation: shake, light beams, scale up, burst.

  Widget _buildOpening() {
    return SizedBox(
      key: const ValueKey('opening'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating light beams
          ...List.generate(8, (i) {
            final angle = i * (pi / 4);
            return Transform.rotate(
              angle: angle,
              child: Container(
                width: 3,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _tierColor.withValues(alpha: 0.8),
                      _tierColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            );
          })
              .animate()
              .rotate(begin: 0, end: 0.5, duration: 1800.ms)
              .fadeIn(duration: 400.ms),

          // Expanding glow circle
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _tierColor.withValues(alpha: 0.5),
                  _tierColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          )
              .animate()
              .scaleXY(begin: 0.5, end: 2.0, duration: 1500.ms)
              .fadeOut(delay: 1000.ms, duration: 500.ms),

          // Chest icon shaking then bursting
          Icon(
            _tierIcon,
            size: 64,
            color: _tierColor,
          )
              .animate()
              .scaleXY(begin: 1.0, end: 1.3, duration: 600.ms)
              .then()
              .shakeX(amount: 4, hz: 8, duration: 600.ms)
              .then()
              .scaleXY(end: 0.0, duration: 300.ms)
              .fadeOut(duration: 300.ms),

          // Sparkle particles flying outward
          ...List.generate(6, (i) {
            final angle = i * (pi / 3) + pi / 6;
            final dx = cos(angle) * 50;
            final dy = sin(angle) * 50;
            return Icon(
              Icons.auto_awesome,
              size: 14,
              color: AppColors.confettiColors[i % AppColors.confettiColors.length],
            )
                .animate(delay: 1200.ms)
                .fadeIn(duration: 200.ms)
                .moveX(begin: 0, end: dx, duration: 500.ms, curve: Curves.easeOut)
                .moveY(begin: 0, end: dy, duration: 500.ms, curve: Curves.easeOut)
                .fadeOut(delay: 300.ms, duration: 200.ms);
          }),
        ],
      ),
    );
  }

  // ── Revealed State ────────────────────────────────────────────────
  // Big reward icon with glow, sparkle, and celebration.

  Widget _buildRevealed() {
    final reward = _reward;
    if (reward == null) {
      return const SizedBox(key: ValueKey('revealed_empty'));
    }

    return Column(
      key: const ValueKey('revealed'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Reward icon with radial glow
        Stack(
          alignment: Alignment.center,
          children: [
            // Glow behind reward
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    reward.color.withValues(alpha: 0.4),
                    reward.color.withValues(alpha: 0.1),
                    reward.color.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 0.9, end: 1.1, duration: 1200.ms),

            // Reward icon (BIG and bold)
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reward.color.withValues(alpha: 0.15),
                border: Border.all(
                  color: reward.color.withValues(alpha: 0.6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: reward.color.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                reward.icon,
                size: 36,
                color: reward.color,
              ),
            )
                .animate()
                .scaleXY(begin: 0.0, end: 1.0, duration: 500.ms,
                    curve: Curves.elasticOut)
                .fadeIn(duration: 200.ms),

            // Orbiting sparkles
            ...List.generate(4, (i) {
              final angle = i * (pi / 2);
              return Positioned(
                left: 50 + cos(angle) * 44 - 6,
                top: 50 + sin(angle) * 44 - 6,
                child: Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: AppColors.confettiColors[i],
                )
                    .animate(delay: (200 + i * 100).ms)
                    .fadeIn(duration: 300.ms)
                    .scaleXY(begin: 0, end: 1, duration: 400.ms),
              );
            }),
          ],
        ),

        const SizedBox(height: 12),

        // Category indicator — icon-only row
        _buildRewardCategoryIndicator(reward),

        const SizedBox(height: 8),

        // Tap again hint (bouncing down-arrow icon)
        if (_chestsAvailable > 0)
          Icon(
            Icons.touch_app_rounded,
            size: 20,
            color: _tierColor.withValues(alpha: 0.5),
          )
              .animate(delay: 1500.ms, onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: 3, duration: 500.ms)
        else
          // Checkmark — all done for now
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: AppColors.success.withValues(alpha: 0.6),
          )
              .animate(delay: 1000.ms)
              .fadeIn(duration: 400.ms)
              .scaleXY(begin: 0, end: 1, duration: 300.ms),
      ],
    );
  }

  /// Small visual indicator of what category the reward is.
  /// Uses icons only — no text.
  Widget _buildRewardCategoryIndicator(TreasureReward reward) {
    final IconData categoryIcon;
    final Color categoryColor;

    switch (reward.category) {
      case TreasureCategory.accessory:
        categoryIcon = Icons.face_retouching_natural;
        categoryColor = const Color(0xFFFFB6C1);
      case TreasureCategory.bgColor:
        categoryIcon = Icons.palette_rounded;
        categoryColor = const Color(0xFF6BB8F0);
      case TreasureCategory.effect:
        categoryIcon = Icons.auto_awesome;
        categoryColor = AppColors.starGold;
      case TreasureCategory.sticker:
        categoryIcon = Icons.emoji_events_rounded;
        categoryColor = const Color(0xFFFF7EB3);
      case TreasureCategory.facePaint:
        categoryIcon = Icons.brush_rounded;
        categoryColor = const Color(0xFFFF6B8A);
      case TreasureCategory.glasses:
        categoryIcon = Icons.visibility_rounded;
        categoryColor = const Color(0xFF4A90D9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Icon(
        categoryIcon,
        size: 18,
        color: categoryColor,
      ),
    )
        .animate()
        .fadeIn(delay: 400.ms, duration: 300.ms)
        .slideY(begin: 0.3, end: 0, duration: 300.ms);
  }
}

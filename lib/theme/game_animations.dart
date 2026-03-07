import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'app_theme.dart';

/// Reusable animation presets for the ReadSprout app.
/// Usage: widget.animate(effects: GameAnimations.scaleIn)
class GameAnimations {
  GameAnimations._();

  /// Staggered fade-in from below. Pass index for delay offset.
  static List<Effect> fadeInUp({
    int index = 0,
    Duration interval = const Duration(milliseconds: 80),
  }) =>
      [
        FadeEffect(
          delay: interval * index,
          duration: 400.ms,
          curve: Curves.easeOut,
        ),
        SlideEffect(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
          delay: interval * index,
          duration: 400.ms,
          curve: Curves.easeOut,
        ),
      ];

  /// Quick scale-in entrance
  static final List<Effect> scaleIn = [
    ScaleEffect(
      begin: const Offset(0.85, 0.85),
      end: const Offset(1, 1),
      duration: 350.ms,
      curve: Curves.easeOutBack,
    ),
    FadeEffect(duration: 250.ms),
  ];

  /// Correct answer: green flash + bounce
  static final List<Effect> correctFlash = [
    ScaleEffect(
      begin: const Offset(1, 1),
      end: const Offset(1.15, 1.15),
      duration: 150.ms,
      curve: Curves.easeOut,
    ),
    ScaleEffect(
      begin: const Offset(1.15, 1.15),
      end: const Offset(1, 1),
      delay: 150.ms,
      duration: 200.ms,
      curve: Curves.easeInOut,
    ),
    TintEffect(
      color: AppColors.emerald,
      end: 0.3,
      duration: 200.ms,
    ),
  ];

  /// Wrong answer: shake + red flash
  static final List<Effect> errorShake = [
    ShakeEffect(
      duration: 400.ms,
      hz: 5,
      offset: const Offset(6, 0),
      rotation: 0,
    ),
    TintEffect(
      color: AppColors.error,
      end: 0.25,
      duration: 200.ms,
    ),
  ];

  /// Shimmer sweep for highlights
  static final List<Effect> shimmerHighlight = [
    ShimmerEffect(
      duration: 1500.ms,
      color: AppColors.electricBlue,
    ),
  ];

  /// Bubble pop: scale up and fade out
  static final List<Effect> bubblePop = [
    ScaleEffect(
      begin: const Offset(1, 1),
      end: const Offset(1.4, 1.4),
      duration: 250.ms,
      curve: Curves.easeOut,
    ),
    FadeEffect(
      begin: 1,
      end: 0,
      duration: 250.ms,
    ),
  ];

  /// Star bounce in (for ratings)
  static List<Effect> starBounce({int index = 0}) => [
        ScaleEffect(
          begin: const Offset(0, 0),
          end: const Offset(1, 1),
          delay: Duration(milliseconds: 200 + index * 200),
          duration: 600.ms,
          curve: Curves.elasticOut,
        ),
        FadeEffect(
          delay: Duration(milliseconds: 200 + index * 200),
          duration: 200.ms,
        ),
      ];

  /// Score/stat reveal
  static List<Effect> scoreReveal({int index = 0}) => [
        FadeEffect(
          delay: Duration(milliseconds: 100 * index),
          duration: 300.ms,
        ),
        SlideEffect(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
          delay: Duration(milliseconds: 100 * index),
          duration: 300.ms,
          curve: Curves.easeOut,
        ),
      ];

  /// Gentle attention pulse (for CTA buttons)
  static final List<Effect> attentionPulse = [
    ScaleEffect(
      begin: const Offset(1, 1),
      end: const Offset(1.05, 1.05),
      duration: 1200.ms,
      curve: Curves.easeInOut,
    ),
  ];

  /// Combo fire effect
  static final List<Effect> comboFire = [
    ScaleEffect(
      begin: const Offset(0.9, 0.9),
      end: const Offset(1.1, 1.1),
      duration: 300.ms,
      curve: Curves.easeOut,
    ),
    TintEffect(
      color: AppColors.flameOrange,
      end: 0.3,
      duration: 300.ms,
    ),
  ];
}

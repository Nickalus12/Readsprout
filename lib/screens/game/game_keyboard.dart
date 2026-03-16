import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// ── On-Screen Keyboard ──────────────────────────────────────────

class GameKeyboard extends StatelessWidget {
  final bool isExplorer;
  final bool isAdventurer;
  final bool showingCelebration;
  final bool levelComplete;
  final int currentLetterIndex;
  final String targetText;
  final String? nudgeKey;
  final AnimationController nudgeController;
  final List<Color> levelColors;
  final ValueChanged<String> onKeyPressed;

  const GameKeyboard({
    super.key,
    required this.isExplorer,
    required this.isAdventurer,
    required this.showingCelebration,
    required this.levelComplete,
    required this.currentLetterIndex,
    required this.targetText,
    required this.nudgeKey,
    required this.nudgeController,
    required this.levelColors,
    required this.onKeyPressed,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ];

    final screenH = MediaQuery.of(context).size.height;
    final shortScreen = screenH < 600;
    final rowGap = shortScreen ? 3.0 : 6.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          return Padding(
            padding: EdgeInsets.only(bottom: rowGap),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((letter) {
                // Tier 1: highlight expected letter
                final isExpected = isExplorer &&
                    !showingCelebration &&
                    !levelComplete &&
                    currentLetterIndex < targetText.length &&
                    letter == targetText[currentLetterIndex];

                // Tier 2: nudge pulse on the correct key after 2 wrong
                final isNudging = isAdventurer && nudgeKey == letter;

                return KeyboardKey(
                  letter: letter,
                  isExpected: isExpected,
                  isNudging: isNudging,
                  nudgeController: nudgeController,
                  accentColor: levelColors.first,
                  onTap: () => onKeyPressed(letter),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Keyboard Key ────────────────────────────────────────────────────

class KeyboardKey extends StatefulWidget {
  final String letter;
  final bool isExpected;
  final bool isNudging;
  final AnimationController? nudgeController;
  final Color accentColor;
  final VoidCallback onTap;

  const KeyboardKey({
    super.key,
    required this.letter,
    required this.isExpected,
    this.isNudging = false,
    this.nudgeController,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<KeyboardKey> createState() => _KeyboardKeyState();
}

class _KeyboardKeyState extends State<KeyboardKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // If this key is being nudged (Tier 2), wrap in animated builder
    if (widget.isNudging && widget.nudgeController != null) {
      return AnimatedBuilder(
        animation: widget.nudgeController!,
        builder: (context, child) {
          // Pulse: scale 1.0 -> 1.1 -> 1.0 with blue glow
          final t = widget.nudgeController!.value;
          final pulse = 1.0 + 0.1 * sin(t * pi * 2);
          final glowAlpha = 0.4 * sin(t * pi);
          return Transform.scale(
            scale: pulse,
            child: _buildKey(
              nudgeGlowAlpha: glowAlpha.clamp(0.0, 1.0),
            ),
          );
        },
      );
    }
    return _buildKey();
  }

  Widget _buildKey({double nudgeGlowAlpha = 0.0}) {
    final showHighlight = widget.isExpected;
    final showNudge = nudgeGlowAlpha > 0;

    // Dynamic key sizing based on screen width AND height
    // 10 keys per row + margins = need to fit within screen width - padding
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final shortScreen = screenH < 600;
    final keyMargin = (screenW / 200).clamp(1.5, 3.0);
    final keyWidth = ((screenW - 16) / 10 - keyMargin * 2).clamp(24.0, 38.0);
    final maxKeyH = shortScreen ? 38.0 : 50.0;
    final keyHeight = (keyWidth * 1.3).clamp(28.0, maxKeyH);
    final fontSize = (keyWidth * 0.5).clamp(12.0, 20.0);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.symmetric(horizontal: keyMargin),
          width: keyWidth,
          height: keyHeight,
          decoration: BoxDecoration(
            color: showHighlight
                ? AppColors.electricBlue.withValues(alpha: 0.2)
                : showNudge
                    ? AppColors.electricBlue.withValues(alpha: 0.15)
                    : _pressed
                        ? AppColors.electricBlue.withValues(alpha: 0.12)
                        : AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: showHighlight
                  ? AppColors.electricBlue
                  : showNudge
                      ? AppColors.electricBlue.withValues(alpha: 0.6)
                      : _pressed
                          ? AppColors.electricBlue.withValues(alpha: 0.4)
                          : AppColors.border.withValues(alpha: 0.5),
              width: showHighlight ? 1.5 : 1,
            ),
            boxShadow: [
              if (showHighlight)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              if (showNudge)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: nudgeGlowAlpha * 0.5),
                  blurRadius: 12,
                ),
              if (_pressed)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
            ],
          ),
          child: Center(
            child: Text(
              widget.letter,
              style: AppFonts.fredoka(
                fontSize: fontSize,
                fontWeight:
                    (showHighlight || showNudge) ? FontWeight.w600 : FontWeight.w400,
                color: (showHighlight || showNudge || _pressed)
                    ? AppColors.electricBlue
                    : AppColors.primaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

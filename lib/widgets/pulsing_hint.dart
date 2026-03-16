import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A pulsing glow overlay that draws attention to an interactive element.
/// Used for first-time hints — shows a soft pulsing ring and optional
/// bouncing hand icon to guide a child who cannot read.
class PulsingHint extends StatefulWidget {
  final Widget child;
  final bool active;
  final bool showHand;
  final Color glowColor;
  final double glowRadius;

  const PulsingHint({
    super.key,
    required this.child,
    this.active = true,
    this.showHand = false,
    this.glowColor = AppColors.starGold,
    this.glowRadius = 8.0,
  });

  @override
  State<PulsingHint> createState() => _PulsingHintState();
}

class _PulsingHintState extends State<PulsingHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulsingHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _controller.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.glowRadius + 4),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: 0.15 + pulse * 0.25),
                blurRadius: 12 + pulse * 16,
                spreadRadius: pulse * 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (widget.showHand)
            Positioned(
              bottom: -28,
              right: -8,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final bounce = sin(_controller.value * pi) * 6;
                  return Transform.translate(
                    offset: Offset(0, -bounce),
                    child: child,
                  );
                },
                child: const Icon(
                  Icons.touch_app_rounded,
                  size: 28,
                  color: AppColors.starGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

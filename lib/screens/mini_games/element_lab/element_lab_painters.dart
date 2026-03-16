import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Element Lab Painters — CustomPainters for grid rendering and icons
// ---------------------------------------------------------------------------

/// Renders the pixel-buffer image onto the canvas.
class GridPainter extends CustomPainter {
  final ui.Image? image;
  final double canvasLeft;
  final double canvasTop;
  final double canvasPixelW;
  final double canvasPixelH;
  final bool lightningFlash;

  const GridPainter({
    required this.image,
    required this.canvasLeft,
    required this.canvasTop,
    required this.canvasPixelW,
    required this.canvasPixelH,
    required this.lightningFlash,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;

    final src = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(canvasLeft, canvasTop, canvasPixelW, canvasPixelH);

    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    canvas.drawImageRect(image!, src, dst, paint);

    if (lightningFlash) {
      // Bright flash overlay for lightning strikes
      canvas.drawRect(
        dst,
        Paint()
          ..color = const Color(0x30FFFFCC)
          ..blendMode = BlendMode.screen,
      );
      // Subtle secondary bloom with blue-white tint
      canvas.drawRect(
        dst,
        Paint()
          ..color = const Color(0x10CCDDFF)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      image != old.image ||
      lightningFlash != old.lightningFlash ||
      canvasLeft != old.canvasLeft ||
      canvasTop != old.canvasTop ||
      canvasPixelW != old.canvasPixelW ||
      canvasPixelH != old.canvasPixelH;
}

/// Beaker icon painter for the mini-games hub.
class BeakerIconPainter extends CustomPainter {
  const BeakerIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Beaker body
    final beakerPath = Path()
      ..moveTo(cx - 10, cy - 16)
      ..lineTo(cx - 10, cy - 4)
      ..lineTo(cx - 16, cy + 14)
      ..lineTo(cx + 16, cy + 14)
      ..lineTo(cx + 10, cy - 4)
      ..lineTo(cx + 10, cy - 16)
      ..close();

    // Glass outline
    canvas.drawPath(
      beakerPath,
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      beakerPath,
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // Liquid inside (bottom half)
    final liquidPath = Path()
      ..moveTo(cx - 13, cy + 4)
      ..quadraticBezierTo(cx, cy + 1, cx + 13, cy + 4)
      ..lineTo(cx + 16, cy + 14)
      ..lineTo(cx - 16, cy + 14)
      ..close();
    canvas.drawPath(
      liquidPath,
      Paint()
        ..color = const Color(0xFF33CC33).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    // Bubbles inside liquid
    canvas.drawCircle(
      Offset(cx - 4, cy + 8),
      2.5,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(cx + 5, cy + 6),
      1.8,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(cx - 1, cy + 12),
      1.5,
      Paint()..color = const Color(0xFF66FF66).withValues(alpha: 0.4),
    );

    // Beaker rim
    canvas.drawLine(
      Offset(cx - 12, cy - 16),
      Offset(cx + 12, cy - 16),
      Paint()
        ..color = const Color(0xFF88CCFF).withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Sparkle at top
    _drawSparkle(canvas, Offset(cx + 2, cy - 22), 3, AppColors.starGold);
    _drawSparkle(canvas, Offset(cx - 8, cy - 6), 2, AppColors.electricBlue);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Seed type icon painter for the seed selection popup.
class SeedIconPainter extends CustomPainter {
  final int seedType;
  const SeedIconPainter(this.seedType);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    switch (seedType) {
      case 1: // Grass — small green blades
        final p = Paint()..color = const Color(0xFF33CC33)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx - 4, cy + 6), Offset(cx - 5, cy - 4), p);
        canvas.drawLine(Offset(cx, cy + 6), Offset(cx, cy - 6), p);
        canvas.drawLine(Offset(cx + 4, cy + 6), Offset(cx + 5, cy - 4), p);
      case 2: // Flower — stem + bloom
        final stem = Paint()..color = const Color(0xFF33AA33)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 7), Offset(cx, cy - 1), stem);
        final bloom = Paint()..color = const Color(0xFFFF88CC);
        for (int i = 0; i < 5; i++) {
          final a = i * 3.14159 * 2 / 5 - 1.57;
          canvas.drawCircle(Offset(cx + cos(a) * 3.5, cy - 4 + sin(a) * 3.5), 2, bloom);
        }
        canvas.drawCircle(Offset(cx, cy - 4), 1.5, Paint()..color = const Color(0xFFFFDD44));
      case 3: // Tree — trunk + canopy
        final trunk = Paint()..color = const Color(0xFF8B6914)..strokeWidth = 2.5..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 7), Offset(cx, cy - 1), trunk);
        final canopy = Paint()..color = const Color(0xFF228B22);
        canvas.drawCircle(Offset(cx, cy - 5), 5, canopy);
      case 4: // Mushroom — cap + stem
        final stem = Paint()..color = const Color(0xFFF0E0D0)..strokeWidth = 2..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx, cy + 6), Offset(cx, cy - 1), stem);
        final cap = Paint()..color = const Color(0xFFCC3333);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy - 2), width: 14, height: 10), 3.14159, 3.14159, true, cap);
        // White spots
        final spot = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(cx - 2, cy - 4), 1.2, spot);
        canvas.drawCircle(Offset(cx + 3, cy - 3), 1, spot);
      case 5: // Vine — curling tendril
        final p = Paint()..color = const Color(0xFF33AA33)..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(cx - 4, cy + 6)
          ..quadraticBezierTo(cx - 6, cy, cx - 2, cy - 2)
          ..quadraticBezierTo(cx + 4, cy - 5, cx + 2, cy - 8);
        canvas.drawPath(path, p);
        // Leaf
        final leaf = Paint()..color = const Color(0xFF33CC33);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx + 3, cy - 4), width: 5, height: 3), leaf);
    }
  }

  @override
  bool shouldRepaint(SeedIconPainter old) => old.seedType != seedType;
}

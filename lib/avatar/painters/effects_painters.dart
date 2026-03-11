import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Effects painters — face paint uses BlendMode for painted-on-skin feel,
/// glasses have environment reflections, sparkles have drift and rotation.

// ══════════════════════════════════════════════════════════════════════
//  COLOR HELPERS
// ══════════════════════════════════════════════════════════════════════

Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

Color _coolShadow(Color color, [double amount = 0.2]) {
  final r = (color.r * (1 - amount) + 0.15 * amount).clamp(0.0, 1.0);
  final g = (color.g * (1 - amount) + 0.12 * amount).clamp(0.0, 1.0);
  final b = (color.b * (1 - amount) + 0.35 * amount).clamp(0.0, 1.0);
  return Color.from(alpha: color.a, red: r, green: g, blue: b);
}

Color _warmHighlight(Color color, [double amount = 0.25]) {
  final r = (color.r * (1 - amount) + 1.0 * amount).clamp(0.0, 1.0);
  final g = (color.g * (1 - amount) + 0.97 * amount).clamp(0.0, 1.0);
  final b = (color.b * (1 - amount) + 0.85 * amount).clamp(0.0, 1.0);
  return Color.from(alpha: color.a, red: r, green: g, blue: b);
}

// ══════════════════════════════════════════════════════════════════════
//  FACE PAINT — painted ON the skin with BlendMode.multiply
// ══════════════════════════════════════════════════════════════════════

class FacePaintPainter extends CustomPainter {
  final int style;
  final Color skinColor;

  FacePaintPainter({required this.style, this.skinColor = const Color(0xFFF5D6B8)});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Use saveLayer with BlendMode to make paint look like it's on skin
    // The face paint composites onto whatever is beneath it.
    switch (style) {
      case 1:
        _drawStar(canvas, w, h);
      case 2:
        _drawButterfly(canvas, w, h);
      case 3:
        _drawHeart(canvas, w, h);
      case 4:
        _drawRainbow(canvas, w, h);
      case 5:
        _drawWhiskers(canvas, w, h);
      case 6:
        _drawTiger(canvas, w, h);
      case 7:
        _drawFlower(canvas, w, h);
      case 8:
        _drawLightning(canvas, w, h);
      case 9:
        _drawDots(canvas, w, h);
    }
  }

  // ── 1: Star on left cheek — glowing face paint star ──
  void _drawStar(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.18, h * 0.55);
    final r = w * 0.085;

    // Soft underglow (painted onto skin)
    canvas.drawCircle(
      center,
      r * 1.8,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Star paint — multi-layered for painted-on look
    // Base layer (larger, softer, more transparent)
    final starBase = _starPath(center, r * 1.1);
    canvas.drawPath(
      starBase,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Main star with gradient
    final starMain = _starPath(center, r);
    final starGrad = RadialGradient(
      center: const Alignment(-0.2, -0.2),
      colors: [
        _warmHighlight(AppColors.starGold, 0.3).withValues(alpha: 0.65),
        AppColors.starGold.withValues(alpha: 0.55),
        _darken(AppColors.starGold, 0.1).withValues(alpha: 0.45),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawPath(
      starMain,
      Paint()
        ..shader = starGrad.createShader(Rect.fromCircle(center: center, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );

    // Sparkle highlight on one point
    canvas.drawCircle(
      Offset(center.dx, center.dy - r * 0.7),
      r * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  // ── 2: Butterfly on right cheek — delicate wing details ──
  void _drawButterfly(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.80, h * 0.52);
    final r = w * 0.12;

    // Wings with organic bezier shape and gradient
    for (final isLeft in [true, false]) {
      final sign = isLeft ? -1.0 : 1.0;
      final wingPath = Path()
        ..moveTo(center.dx, center.dy)
        ..cubicTo(
          center.dx + sign * r * 0.3, center.dy - r * 0.6,
          center.dx + sign * r * 0.8, center.dy - r * 0.5,
          center.dx + sign * r * 0.7, center.dy - r * 0.15,
        )
        ..cubicTo(
          center.dx + sign * r * 0.9, center.dy + r * 0.1,
          center.dx + sign * r * 0.6, center.dy + r * 0.5,
          center.dx, center.dy + r * 0.15,
        )
        ..close();

      final wingGrad = RadialGradient(
        center: Alignment(sign * 0.3, -0.3),
        colors: [
          const Color(0xFFD4A8FF).withValues(alpha: 0.55),
          const Color(0xFFB794F6).withValues(alpha: 0.40),
          const Color(0xFF8B5CF6).withValues(alpha: 0.30),
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      final wingBounds = wingPath.getBounds();
      canvas.drawPath(
        wingPath,
        Paint()
          ..shader = wingGrad.createShader(wingBounds)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );

      // Wing pattern dots
      final dotCenter = Offset(
          center.dx + sign * r * 0.4, center.dy - r * 0.1);
      canvas.drawCircle(
        dotCenter,
        r * 0.08,
        Paint()..color = Colors.white.withValues(alpha: 0.3),
      );
    }

    // Body — slender with gradient
    final bodyPaint = Paint()
      ..color = const Color(0xFF6B4690).withValues(alpha: 0.4)
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3);
    canvas.drawLine(
      center.translate(0, -r * 0.2),
      center.translate(0, r * 0.15),
      bodyPaint,
    );

    // Antennae
    final antPaint = Paint()
      ..color = const Color(0xFF6B4690).withValues(alpha: 0.3)
      ..strokeWidth = r * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center.translate(0, -r * 0.2),
        center.translate(-r * 0.15, -r * 0.4), antPaint);
    canvas.drawLine(center.translate(0, -r * 0.2),
        center.translate(r * 0.15, -r * 0.4), antPaint);
    // Antenna tips
    canvas.drawCircle(center.translate(-r * 0.15, -r * 0.4), r * 0.025,
        Paint()..color = const Color(0xFF6B4690).withValues(alpha: 0.3));
    canvas.drawCircle(center.translate(r * 0.15, -r * 0.4), r * 0.025,
        Paint()..color = const Color(0xFF6B4690).withValues(alpha: 0.3));
  }

  // ── 3: Heart on left cheek ──
  void _drawHeart(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.18, h * 0.55);
    final r = w * 0.075;

    // Underglow
    canvas.drawCircle(
      center,
      r * 1.6,
      Paint()
        ..color = const Color(0xFFFF4D6A).withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Base bleed
    _drawHeartPath(canvas, center, r * 1.1,
      Paint()
        ..color = const Color(0xFFFF4D6A).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Main heart
    final heartGrad = RadialGradient(
      center: const Alignment(-0.2, -0.35),
      colors: [
        _warmHighlight(const Color(0xFFFF7090), 0.2).withValues(alpha: 0.7),
        const Color(0xFFFF4D6A).withValues(alpha: 0.55),
        _coolShadow(const Color(0xFFFF4D6A), 0.15).withValues(alpha: 0.45),
      ],
    );
    _drawHeartPath(canvas, center, r,
      Paint()
        ..shader = heartGrad.createShader(Rect.fromCircle(center: center, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );

    // Specular
    canvas.drawCircle(
      center.translate(-r * 0.15, -r * 0.3),
      r * 0.15,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  void _drawHeartPath(Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  // ── 4: Rainbow across forehead ──
  void _drawRainbow(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.50, h * 0.12);
    final width = w * 0.30;
    final height = h * 0.08;
    const colors = [
      Color(0xFFFF4444),
      Color(0xFFFF8C42),
      Color(0xFFFFD700),
      Color(0xFF00E68A),
      Color(0xFF4A90D9),
      Color(0xFF9B59B6),
    ];
    final bandH = height / colors.length;

    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i].withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandH * 1.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      final r = width - i * bandH;
      canvas.drawArc(
        Rect.fromCenter(center: center, width: r * 2, height: r),
        pi,
        pi,
        false,
        paint,
      );
    }

    // Top shimmer
    canvas.drawArc(
      Rect.fromCenter(center: center, width: width * 2.1, height: width * 1.05),
      pi,
      pi,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandH * 0.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
  }

  // ── 5: Cat whiskers — soft painted whiskers with nose ──
  void _drawWhiskers(Canvas canvas, double w, double h) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);

    // Left whiskers with slight droop (bezier curves)
    for (int i = 0; i < 3; i++) {
      final yBase = h * (0.50 + i * 0.06);
      final droop = h * 0.01 * i;
      final whisker = Path()
        ..moveTo(w * 0.05, yBase - droop)
        ..cubicTo(w * 0.12, yBase - droop * 0.5, w * 0.22, yBase, w * 0.30, yBase + droop * 0.5);
      canvas.drawPath(whisker, paint);
    }
    // Right whiskers
    for (int i = 0; i < 3; i++) {
      final yBase = h * (0.50 + i * 0.06);
      final droop = h * 0.01 * i;
      final whisker = Path()
        ..moveTo(w * 0.95, yBase - droop)
        ..cubicTo(w * 0.88, yBase - droop * 0.5, w * 0.78, yBase, w * 0.70, yBase + droop * 0.5);
      canvas.drawPath(whisker, paint);
    }

    // Cute cat nose (upside-down triangle)
    final nosePath = Path()
      ..moveTo(w * 0.48, h * 0.46)
      ..cubicTo(w * 0.49, h * 0.44, w * 0.51, h * 0.44, w * 0.52, h * 0.46)
      ..cubicTo(w * 0.51, h * 0.48, w * 0.49, h * 0.48, w * 0.48, h * 0.46)
      ..close();
    canvas.drawPath(
      nosePath,
      Paint()
        ..color = const Color(0xFFFF7090).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  // ── 6: Tiger stripes — bold painted stripes ──
  void _drawTiger(Canvas canvas, double w, double h) {
    final paint = Paint()
      ..color = const Color(0xFFFF8C42).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.030
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    // Forehead stripes — curved, not straight
    final stripes = [
      (Path()..moveTo(w * 0.15, h * 0.14)..cubicTo(w * 0.18, h * 0.16, w * 0.25, h * 0.20, w * 0.30, h * 0.22)),
      (Path()..moveTo(w * 0.10, h * 0.24)..cubicTo(w * 0.14, h * 0.25, w * 0.20, h * 0.28, w * 0.25, h * 0.30)),
      (Path()..moveTo(w * 0.70, h * 0.22)..cubicTo(w * 0.75, h * 0.20, w * 0.82, h * 0.16, w * 0.85, h * 0.14)),
      (Path()..moveTo(w * 0.75, h * 0.30)..cubicTo(w * 0.80, h * 0.28, w * 0.86, h * 0.25, w * 0.90, h * 0.24)),
    ];
    for (final stripe in stripes) {
      canvas.drawPath(stripe, paint);
    }

    // Nose bridge stripe
    canvas.drawLine(
      Offset(w * 0.44, h * 0.10),
      Offset(w * 0.56, h * 0.10),
      paint,
    );

    // Orange nose tip
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.47),
      w * 0.015,
      Paint()
        ..color = const Color(0xFFFF8C42).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  // ── 7: Flower on right cheek ──
  void _drawFlower(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.80, h * 0.52);
    final r = w * 0.08;

    // Soft glow
    canvas.drawCircle(
      center,
      r * 1.6,
      Paint()
        ..color = const Color(0xFFFF7EB3).withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Petals — organic bezier shapes
    for (int i = 0; i < 5; i++) {
      final angle = i * 2 * pi / 5 - pi / 2;
      final tip = Offset(
          center.dx + r * 0.85 * cos(angle), center.dy + r * 0.85 * sin(angle));

      final perpAngle = angle + pi / 2;
      final petalWidth = r * 0.25;
      final left = Offset(
          center.dx + r * 0.15 * cos(angle) + petalWidth * cos(perpAngle),
          center.dy + r * 0.15 * sin(angle) + petalWidth * sin(perpAngle));
      final right = Offset(
          center.dx + r * 0.15 * cos(angle) - petalWidth * cos(perpAngle),
          center.dy + r * 0.15 * sin(angle) - petalWidth * sin(perpAngle));

      final petalPath = Path()
        ..moveTo(left.dx, left.dy)
        ..cubicTo(
          left.dx + r * 0.3 * cos(angle + 0.3),
          left.dy + r * 0.3 * sin(angle + 0.3),
          tip.dx + petalWidth * 0.2 * cos(perpAngle),
          tip.dy + petalWidth * 0.2 * sin(perpAngle),
          tip.dx, tip.dy,
        )
        ..cubicTo(
          tip.dx - petalWidth * 0.2 * cos(perpAngle),
          tip.dy - petalWidth * 0.2 * sin(perpAngle),
          right.dx + r * 0.3 * cos(angle - 0.3),
          right.dy + r * 0.3 * sin(angle - 0.3),
          right.dx, right.dy,
        )
        ..close();

      final petalGrad = RadialGradient(
        center: Alignment(cos(angle) * -0.3, sin(angle) * -0.3),
        colors: [
          Colors.white.withValues(alpha: 0.50),
          const Color(0xFFFF7EB3).withValues(alpha: 0.40),
        ],
      );
      canvas.drawPath(
        petalPath,
        Paint()
          ..shader = petalGrad.createShader(petalPath.getBounds())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
    }

    // Center
    canvas.drawCircle(
      center,
      r * 0.22,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  // ── 8: Lightning bolt on left cheek ──
  void _drawLightning(Canvas canvas, double w, double h) {
    final start = Offset(w * 0.13, h * 0.43);
    final bw = w * 0.11;
    final bh = h * 0.20;

    // Electric glow
    canvas.drawCircle(
      Offset(start.dx + bw * 0.5, start.dy + bh * 0.5),
      bw * 1.8,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Base bleed
    final boltPath = _boltPath(start, bw, bh);
    canvas.drawPath(
      boltPath,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Main bolt with gradient
    final boltGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(AppColors.starGold, 0.35).withValues(alpha: 0.65),
        AppColors.starGold.withValues(alpha: 0.55),
      ],
    );
    canvas.drawPath(
      boltPath,
      Paint()
        ..shader = boltGrad.createShader(Rect.fromLTWH(start.dx, start.dy, bw, bh))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
  }

  Path _boltPath(Offset start, double w, double h) {
    return Path()
      ..moveTo(start.dx + w * 0.40, start.dy)
      ..lineTo(start.dx + w * 0.10, start.dy + h * 0.45)
      ..lineTo(start.dx + w * 0.45, start.dy + h * 0.45)
      ..lineTo(start.dx + w * 0.20, start.dy + h)
      ..lineTo(start.dx + w * 0.80, start.dy + h * 0.35)
      ..lineTo(start.dx + w * 0.50, start.dy + h * 0.35)
      ..lineTo(start.dx + w * 0.70, start.dy)
      ..close();
  }

  // ── 9: Dots across nose bridge ──
  void _drawDots(Canvas canvas, double w, double h) {
    const colors = [
      Color(0xFFFF4D6A),
      AppColors.starGold,
      Color(0xFF4A90D9),
      Color(0xFF00E68A),
      Color(0xFFB794F6),
    ];
    for (int i = 0; i < 5; i++) {
      final pos = Offset(w * (0.30 + i * 0.10), h * 0.42);
      final r = w * 0.020;

      // Underglow
      canvas.drawCircle(
        pos,
        r * 2.0,
        Paint()
          ..color = colors[i].withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Paint dot with gradient
      final dotGrad = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          _lighten(colors[i], 0.2).withValues(alpha: 0.55),
          colors[i].withValues(alpha: 0.45),
        ],
      );
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..shader = dotGrad.createShader(Rect.fromCircle(center: pos, radius: r))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
    }
  }

  Path _starPath(Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final outer = Offset(
          center.dx + r * cos(outerAngle), center.dy + r * sin(outerAngle));
      final inner = Offset(center.dx + r * 0.42 * cos(innerAngle),
          center.dy + r * 0.42 * sin(innerAngle));
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(FacePaintPainter old) =>
      old.style != style || old.skinColor != skinColor;
}

// ══════════════════════════════════════════════════════════════════════
//  GLASSES — metallic frames, tinted lenses, environment reflection
// ══════════════════════════════════════════════════════════════════════

class GlassesPainter extends CustomPainter {
  final int style;

  GlassesPainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Metallic frame gradient (cool shadow at bottom, warm highlight at top)
    const frameGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF4A4A5E), // warm side
        Color(0xFF2A2A3E),
        Color(0xFF1A1A2E),
        Color(0xFF252538), // bottom catch light
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    );
    final framePaint = Paint()
      ..shader = frameGrad.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.032;

    // Shadow beneath glasses
    canvas.drawLine(
      Offset(w * 0.12, h * 0.55),
      Offset(w * 0.88, h * 0.55),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.08)
        ..strokeWidth = h * 0.15
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    switch (style) {
      case 1:
        _drawRoundGlasses(canvas, w, h, framePaint);
      case 2:
        _drawSquareGlasses(canvas, w, h, framePaint);
      case 3:
        _drawCatEyeGlasses(canvas, w, h, framePaint);
      case 4:
        _drawStarGlasses(canvas, w, h, framePaint);
      case 5:
        _drawHeartGlasses(canvas, w, h, framePaint);
      case 6:
        _drawAviatorGlasses(canvas, w, h, framePaint);
    }
  }

  /// Draw lens tint, frame, and environment reflection for an oval lens.
  void _drawOvalLens(Canvas canvas, Rect lensRect, Paint frame) {
    // Lens tint gradient (darker at top like real sunglasses)
    final tintGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF6BB8F0).withValues(alpha: 0.10),
        const Color(0xFF6BB8F0).withValues(alpha: 0.04),
      ],
    );
    canvas.drawOval(lensRect, Paint()..shader = tintGrad.createShader(lensRect));

    // Frame
    canvas.drawOval(lensRect, frame);

    // Environment reflection — curved white highlight
    final center = lensRect.center;
    final rw = lensRect.width * 0.35;
    final rh = lensRect.height * 0.20;
    final reflectionPath = Path()
      ..moveTo(center.dx - rw * 0.8, center.dy - rh * 1.5)
      ..cubicTo(
        center.dx - rw * 0.4, center.dy - rh * 2.2,
        center.dx + rw * 0.2, center.dy - rh * 2.0,
        center.dx + rw * 0.6, center.dy - rh * 1.2,
      )
      ..cubicTo(
        center.dx + rw * 0.3, center.dy - rh * 1.0,
        center.dx - rw * 0.3, center.dy - rh * 1.0,
        center.dx - rw * 0.8, center.dy - rh * 1.5,
      )
      ..close();
    canvas.drawPath(
      reflectionPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  /// Draw lens tint, frame, and reflection for a path-based lens.
  void _drawPathLens(Canvas canvas, Path lensPath, Paint frame) {
    final bounds = lensPath.getBounds();
    final tintGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF6BB8F0).withValues(alpha: 0.10),
        const Color(0xFF6BB8F0).withValues(alpha: 0.04),
      ],
    );
    canvas.drawPath(lensPath, Paint()..shader = tintGrad.createShader(bounds));
    canvas.drawPath(lensPath, frame);

    // Curved reflection
    final center = bounds.center;
    final rw = bounds.width * 0.3;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - rw * 0.3, center.dy - bounds.height * 0.15),
        width: rw * 1.2,
        height: bounds.height * 0.15,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  // Bridge connector with gradient
  void _drawBridge(Canvas canvas, Offset from, Offset to, Paint frame) {
    canvas.drawLine(from, to, frame);
  }

  void _drawRoundGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      _drawOvalLens(
        canvas,
        Rect.fromCenter(center: Offset(cx, h * 0.50), width: w * 0.36, height: h * 0.80),
        frame,
      );
    }
    _drawBridge(canvas, Offset(w * 0.46, h * 0.45), Offset(w * 0.54, h * 0.45), frame);
  }

  void _drawSquareGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      final rect = Rect.fromCenter(
          center: Offset(cx, h * 0.50), width: w * 0.36, height: h * 0.72);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.03));

      // Tint
      final tintGrad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6BB8F0).withValues(alpha: 0.10),
          const Color(0xFF6BB8F0).withValues(alpha: 0.04),
        ],
      );
      canvas.drawRRect(rrect, Paint()..shader = tintGrad.createShader(rect));
      canvas.drawRRect(rrect, frame);

      // Reflection
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - w * 0.04, h * 0.36),
          width: w * 0.10,
          height: h * 0.10,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.2),
      );
    }
    _drawBridge(canvas, Offset(w * 0.46, h * 0.45), Offset(w * 0.54, h * 0.45), frame);
  }

  void _drawCatEyeGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      final path = Path()
        ..moveTo(cx - w * 0.16, h * 0.50)
        ..cubicTo(cx - w * 0.18, h * 0.18, cx - w * 0.04, h * 0.18, cx, h * 0.20)
        ..cubicTo(cx + w * 0.04, h * 0.18, cx + w * 0.18, h * 0.18, cx + w * 0.16, h * 0.50)
        ..cubicTo(cx + w * 0.14, h * 0.80, cx + w * 0.02, h * 0.85, cx, h * 0.85)
        ..cubicTo(cx - w * 0.02, h * 0.85, cx - w * 0.14, h * 0.80, cx - w * 0.16, h * 0.50)
        ..close();
      _drawPathLens(canvas, path, frame);
    }
    _drawBridge(canvas, Offset(w * 0.44, h * 0.45), Offset(w * 0.56, h * 0.45), frame);
  }

  void _drawStarGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      final center = Offset(cx, h * 0.50);
      final r = w * 0.17;
      final starP = _starShape(center, r);
      _drawPathLens(canvas, starP, frame);
    }
    _drawBridge(canvas, Offset(w * 0.45, h * 0.48), Offset(w * 0.55, h * 0.48), frame);
  }

  void _drawHeartGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      final center = Offset(cx, h * 0.50);
      final r = w * 0.15;
      final heartP = _heartShape(center, r);
      _drawPathLens(canvas, heartP, frame);
    }
    _drawBridge(canvas, Offset(w * 0.43, h * 0.45), Offset(w * 0.57, h * 0.45), frame);
  }

  void _drawAviatorGlasses(Canvas canvas, double w, double h, Paint frame) {
    for (final cx in [w * 0.28, w * 0.72]) {
      final path = Path()
        ..moveTo(cx - w * 0.16, h * 0.25)
        ..cubicTo(cx - w * 0.08, h * 0.22, cx + w * 0.08, h * 0.22, cx + w * 0.16, h * 0.25)
        ..cubicTo(cx + w * 0.20, h * 0.45, cx + w * 0.15, h * 0.78, cx + w * 0.12, h * 0.82)
        ..cubicTo(cx + w * 0.05, h * 0.88, cx - w * 0.05, h * 0.88, cx - w * 0.12, h * 0.82)
        ..cubicTo(cx - w * 0.15, h * 0.78, cx - w * 0.20, h * 0.45, cx - w * 0.16, h * 0.25)
        ..close();

      // Aviator-specific darker tint gradient
      final aviatorTint = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6BB8F0).withValues(alpha: 0.14),
          const Color(0xFF4A90D9).withValues(alpha: 0.08),
          const Color(0xFF6BB8F0).withValues(alpha: 0.04),
        ],
      );
      canvas.drawPath(path,
          Paint()..shader = aviatorTint.createShader(Rect.fromLTWH(0, 0, w, h)));
      canvas.drawPath(path, frame);

      // Curved reflection
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - w * 0.04, h * 0.30),
          width: w * 0.12,
          height: h * 0.08,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
      );
    }
    _drawBridge(canvas, Offset(w * 0.44, h * 0.28), Offset(w * 0.56, h * 0.28), frame);
  }

  Path _starShape(Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + r * cos(outerAngle), center.dy + r * sin(outerAngle));
      } else {
        path.lineTo(center.dx + r * cos(outerAngle), center.dy + r * sin(outerAngle));
      }
      path.lineTo(center.dx + r * 0.45 * cos(innerAngle),
          center.dy + r * 0.45 * sin(innerAngle));
    }
    path.close();
    return path;
  }

  Path _heartShape(Offset center, double r) {
    final x = center.dx;
    final y = center.dy;
    return Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.3, y - r * 0.3, x - r * 0.5, y - r * 1.1, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.1, x + r * 1.3, y - r * 0.3, x, y + r * 0.5)
      ..close();
  }

  @override
  bool shouldRepaint(GlassesPainter old) => old.style != style;
}

// ══════════════════════════════════════════════════════════════════════
//  SPARKLE — magical particles with drift, rotation, and stagger
// ══════════════════════════════════════════════════════════════════════

class SparklePainter extends CustomPainter {
  final bool rainbow;
  final double time;

  SparklePainter({required this.rainbow, this.time = 0.0});

  static const int _sparkleCount = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    const goldColors = [
      AppColors.starGold,
      Colors.white,
      Color(0xFFFFF0B0),
      AppColors.starGold,
      Colors.white,
      Color(0xFFFFE070),
      AppColors.starGold,
      Colors.white,
      Color(0xFFFFF5CC),
      AppColors.starGold,
      Colors.white,
      Color(0xFFFFD700),
    ];
    const rainbowColors = [
      Colors.red, Colors.orange, Colors.yellow, Colors.green,
      Colors.blue, Colors.purple, Colors.red, Colors.orange,
      Colors.yellow, Colors.green, Colors.blue, Colors.purple,
    ];
    final colors = rainbow ? rainbowColors : goldColors;

    // Reusable Paint objects to reduce per-frame allocations
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final sparklePaint = Paint();

    for (int i = 0; i < _sparkleCount; i++) {
      // Base position (deterministic from seed)
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final baseR = size.width * 0.018 + rng.nextDouble() * size.width * 0.022;
      final phaseOffset = rng.nextDouble();

      // Staggered phase per sparkle
      final phase = (time + phaseOffset) % 1.0;
      final alpha = (sin(phase * 2 * pi) * 0.5 + 0.5).clamp(0.0, 1.0);

      // Slight drift motion — sparkles float gently
      final driftX = sin(time * 2 * pi + i * 0.7) * size.width * 0.008;
      final driftY = cos(time * 2 * pi + i * 1.1) * size.height * 0.006;
      final x = baseX + driftX;
      final y = baseY + driftY;

      // Size oscillation
      final r = baseR * (0.5 + alpha * 0.5);

      // Rotation per sparkle
      final rotation = time * pi * 2 + i * pi / 6;

      if (alpha < 0.05) continue; // Skip invisible sparkles

      final color = colors[i % colors.length];

      // Glow halo
      glowPaint.color = color.withValues(alpha: alpha * 0.10);
      canvas.drawCircle(Offset(x, y), r * 2.5, glowPaint);

      // Rotated 4-pointed star sparkle
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      // Gradient from bright center to color edge
      final sparkleGrad = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: alpha * 0.9),
          color.withValues(alpha: alpha * 0.6),
          color.withValues(alpha: alpha * 0.1),
        ],
        stops: const [0.0, 0.4, 1.0],
      );

      final sparklePath = Path()
        // Vertical diamond (taller)
        ..moveTo(0, -r)
        ..cubicTo(r * 0.15, -r * 0.15, r * 0.15, -r * 0.15, r * 0.2, 0)
        ..cubicTo(r * 0.15, r * 0.15, r * 0.15, r * 0.15, 0, r)
        ..cubicTo(-r * 0.15, r * 0.15, -r * 0.15, r * 0.15, -r * 0.2, 0)
        ..cubicTo(-r * 0.15, -r * 0.15, -r * 0.15, -r * 0.15, 0, -r)
        ..close()
        // Horizontal diamond (wider)
        ..moveTo(-r * 0.85, 0)
        ..cubicTo(-r * 0.15, r * 0.12, -r * 0.15, r * 0.12, 0, r * 0.18)
        ..cubicTo(r * 0.15, r * 0.12, r * 0.15, r * 0.12, r * 0.85, 0)
        ..cubicTo(r * 0.15, -r * 0.12, r * 0.15, -r * 0.12, 0, -r * 0.18)
        ..cubicTo(-r * 0.15, -r * 0.12, -r * 0.15, -r * 0.12, -r * 0.85, 0)
        ..close();

      sparklePaint.shader = sparkleGrad.createShader(
          Rect.fromCircle(center: Offset.zero, radius: r));
      canvas.drawPath(sparklePath, sparklePaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SparklePainter old) =>
      old.rainbow != rainbow || (old.time * 60).round() != (time * 60).round();
}

// ══════════════════════════════════════════════════════════════════════
//  GOLDEN GLOW — warm radial aura behind avatar
// ══════════════════════════════════════════════════════════════════════

class GoldenGlowPainter extends CustomPainter {
  final double intensity;
  final double time;

  GoldenGlowPainter({this.intensity = 1.0, this.time = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.52;

    // Subtle pulse
    final pulse = 0.85 + sin(time * pi * 2) * 0.15;
    final i = intensity * pulse;

    final gradient = RadialGradient(
      colors: [
        AppColors.starGold.withValues(alpha: 0.0),
        AppColors.starGold.withValues(alpha: 0.05 * i),
        _warmHighlight(AppColors.starGold, 0.2).withValues(alpha: 0.12 * i),
        AppColors.starGold.withValues(alpha: 0.06 * i),
        AppColors.starGold.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.45, 0.65, 0.82, 1.0],
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader =
            gradient.createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(GoldenGlowPainter old) =>
      old.intensity != intensity ||
      (old.time * 30).round() != (time * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  CELEBRATION BURST — radial burst of stars/hearts on word complete
// ══════════════════════════════════════════════════════════════════════

class CelebrationBurstPainter extends CustomPainter {
  /// Animation progress from 0.0 (burst start) to 1.0 (fully faded).
  final double progress;

  CelebrationBurstPainter({required this.progress});

  static const int _particleCount = 10;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.55;
    final rng = Random(7);

    // Reusable Paint to reduce per-frame allocations
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Pre-compute shared values outside the loop
    final distT = Curves.easeOutCubic.transform(progress);
    final scaleT = progress < 0.3
        ? Curves.easeOut.transform(progress / 0.3)
        : 1.0;
    final alpha = progress < 0.3
        ? 1.0
        : (1.0 - ((progress - 0.3) / 0.7)).clamp(0.0, 1.0);

    if (alpha < 0.02) return;

    for (int i = 0; i < _particleCount; i++) {
      // Deterministic angle with slight jitter
      final angle = (i / _particleCount) * 2 * pi + rng.nextDouble() * 0.4;

      // Particles fly outward: ease-out distance
      final dist = maxRadius * (0.15 + distT * 0.85) * (0.8 + rng.nextDouble() * 0.4);
      final x = center.dx + dist * cos(angle);
      final y = center.dy + dist * sin(angle);

      final baseR = size.width * 0.035 * scaleT * (0.7 + rng.nextDouble() * 0.6);

      // Alternate between stars and hearts
      final isStar = i % 3 != 0;
      final color = isStar
          ? Color.lerp(AppColors.starGold, Colors.white, rng.nextDouble() * 0.3)!
          : Color.lerp(const Color(0xFFFF7090), const Color(0xFFFF4D6A), rng.nextDouble())!;

      // Glow
      glowPaint.color = color.withValues(alpha: alpha * 0.12);
      canvas.drawCircle(Offset(x, y), baseR * 2.0, glowPaint);

      if (isStar) {
        _drawMiniStar(canvas, Offset(x, y), baseR, color, alpha,
            rotation: progress * pi + i * 0.5);
      } else {
        _drawMiniHeart(canvas, Offset(x, y), baseR, color, alpha);
      }
    }
  }

  void _drawMiniStar(Canvas canvas, Offset center, double r, Color color,
      double alpha, {double rotation = 0.0}) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final outer = Offset(r * cos(outerAngle), r * sin(outerAngle));
      final inner = Offset(r * 0.42 * cos(innerAngle), r * 0.42 * sin(innerAngle));
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();

    final grad = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: alpha * 0.8),
        color.withValues(alpha: alpha * 0.6),
      ],
    );
    canvas.drawPath(
      path,
      Paint()..shader = grad.createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
  }

  void _drawMiniHeart(Canvas canvas, Offset center, double r, Color color,
      double alpha) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.45)
      ..cubicTo(x - r * 1.1, y - r * 0.25, x - r * 0.45, y - r * 0.9, x, y - r * 0.25)
      ..cubicTo(x + r * 0.45, y - r * 0.9, x + r * 1.1, y - r * 0.25, x, y + r * 0.45)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: alpha * 0.65),
    );
    // Specular
    canvas.drawCircle(
      Offset(x - r * 0.15, y - r * 0.25),
      r * 0.12,
      Paint()..color = Colors.white.withValues(alpha: alpha * 0.4),
    );
  }

  @override
  bool shouldRepaint(CelebrationBurstPainter old) =>
      (old.progress * 60).round() != (progress * 60).round();
}

// ══════════════════════════════════════════════════════════════════════
//  LEVEL UP AURA — rising golden pillar with sparkle particles
// ══════════════════════════════════════════════════════════════════════

class LevelUpAuraPainter extends CustomPainter {
  /// Animation progress from 0.0 (start) to 1.0 (fully risen/faded).
  final double progress;

  LevelUpAuraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    // Aura fades in then out
    final auraAlpha = progress < 0.2
        ? Curves.easeIn.transform(progress / 0.2)
        : progress > 0.7
            ? Curves.easeOut.transform((1.0 - progress) / 0.3)
            : 1.0;

    // Rising vertical gradient — animates upward over time
    final riseOffset = progress * h * 0.4;
    final pillarWidth = w * 0.35;

    // Outer glow
    final outerGlow = RadialGradient(
      center: Alignment(0, 0.3 - progress * 0.6),
      radius: 0.8,
      colors: [
        AppColors.starGold.withValues(alpha: auraAlpha * 0.15),
        AppColors.starGold.withValues(alpha: auraAlpha * 0.06),
        AppColors.starGold.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = outerGlow.createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Central pillar — vertical gradient shifting upward
    final pillarRect = Rect.fromCenter(
      center: Offset(centerX, h * 0.5 - riseOffset * 0.3),
      width: pillarWidth,
      height: h * 1.2,
    );
    final pillarGrad = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        AppColors.starGold.withValues(alpha: 0.0),
        AppColors.starGold.withValues(alpha: auraAlpha * 0.12),
        _warmHighlight(AppColors.starGold, 0.3).withValues(alpha: auraAlpha * 0.18),
        AppColors.starGold.withValues(alpha: auraAlpha * 0.08),
        AppColors.starGold.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.2, 0.45, 0.7, 1.0],
    );

    // Clip pillar to a soft-edged column
    canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint());
    canvas.drawRect(pillarRect, Paint()..shader = pillarGrad.createShader(pillarRect));
    // Horizontal fade mask (soft edges on left/right)
    final hMask = LinearGradient(
      colors: [
        Colors.transparent,
        Colors.white,
        Colors.white,
        Colors.transparent,
      ],
      stops: [
        (centerX - pillarWidth * 0.5) / w,
        (centerX - pillarWidth * 0.25) / w,
        (centerX + pillarWidth * 0.25) / w,
        (centerX + pillarWidth * 0.5) / w,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = hMask.createShader(Rect.fromLTWH(0, 0, w, h))
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();

    // Rising sparkle particles
    final rng = Random(13);
    const particleCount = 8;

    // Reusable Paint objects to reduce per-frame allocations
    final particleGlowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final particleDotPaint = Paint();

    for (int i = 0; i < particleCount; i++) {
      final baseX = centerX + (rng.nextDouble() - 0.5) * pillarWidth * 0.8;
      final baseY = h * (0.3 + rng.nextDouble() * 0.5);
      // Each particle rises at its own rate
      final riseT = (progress * 1.5 + rng.nextDouble() * 0.5) % 1.0;
      final y = baseY - riseT * h * 0.4;
      final x = baseX + sin(riseT * pi * 3 + i) * w * 0.02;

      // Fade in then out
      final pAlpha = sin(riseT * pi) * auraAlpha;
      if (pAlpha < 0.03) continue;

      final r = w * 0.012 * (0.5 + sin(riseT * pi) * 0.5);
      final isWhite = i % 3 == 0;
      final color = isWhite ? Colors.white : AppColors.starGold;

      // Glow
      particleGlowPaint.color = color.withValues(alpha: pAlpha * 0.15);
      canvas.drawCircle(Offset(x, y), r * 2.5, particleGlowPaint);

      // Sparkle dot
      particleDotPaint.color = color.withValues(alpha: pAlpha * 0.7);
      canvas.drawCircle(Offset(x, y), r, particleDotPaint);
    }
  }

  @override
  bool shouldRepaint(LevelUpAuraPainter old) =>
      (old.progress * 60).round() != (progress * 60).round();
}

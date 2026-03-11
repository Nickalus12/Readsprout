import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Accessory painters — Pixar-quality rendering with real material
/// properties, proper lighting, layered shadows, and smooth bezier curves.
///
/// Design principles:
/// - Every accessory has weight and material identity (metal, fabric, organic)
/// - Shadows are layered beneath every element that sits on top of another
/// - Organic shapes use cubic beziers exclusively (no straight segments)
/// - Shadow colors shift cool (blue-purple), highlights shift warm (yellow-white)
/// - All sizes proportional to passed [Size] — works at 42px and 150px

// ══════════════════════════════════════════════════════════════════════
//  COLOR + MATERIAL HELPERS
// ══════════════════════════════════════════════════════════════════════

Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// Shift color toward cool blue for shadows.
Color _coolShadow(Color color, [double amount = 0.2]) {
  final r = (color.r * (1 - amount) + 0.15 * amount).clamp(0.0, 1.0);
  final g = (color.g * (1 - amount) + 0.12 * amount).clamp(0.0, 1.0);
  final b = (color.b * (1 - amount) + 0.35 * amount).clamp(0.0, 1.0);
  return Color.from(alpha: color.a, red: r, green: g, blue: b);
}

/// Shift color toward warm yellow for highlights.
Color _warmHighlight(Color color, [double amount = 0.25]) {
  final r = (color.r * (1 - amount) + 1.0 * amount).clamp(0.0, 1.0);
  final g = (color.g * (1 - amount) + 0.97 * amount).clamp(0.0, 1.0);
  final b = (color.b * (1 - amount) + 0.85 * amount).clamp(0.0, 1.0);
  return Color.from(alpha: color.a, red: r, green: g, blue: b);
}

/// Draw a drop shadow for a path (offset, blurred, cool-tinted).
void _drawShadow(Canvas canvas, Path path,
    {double dx = 0, double dy = 2, double blur = 3, double alpha = 0.2}) {
  canvas.drawPath(
    path.shift(Offset(dx, dy)),
    Paint()
      ..color = const Color(0xFF1A1040).withValues(alpha: alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );
}

/// Metallic gradient with specular band for gold/silver surfaces.
Paint _metallicPaint(Rect bounds, Color base, {double specularPos = 0.3}) {
  final grad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      _warmHighlight(base, 0.35),
      _lighten(base, 0.15),
      base,
      _coolShadow(base, 0.15),
      _darken(base, 0.2),
      _lighten(base, 0.05), // bottom rim catch light
    ],
    stops: [0.0, specularPos - 0.05, specularPos + 0.15, 0.65, 0.85, 1.0],
  );
  return Paint()..shader = grad.createShader(bounds);
}

/// Draw a jewel with internal refraction simulation.
void _drawJewel(Canvas canvas, Offset center, double r, Color color) {
  // Outer setting shadow
  canvas.drawCircle(
    center.translate(0, r * 0.15),
    r * 1.05,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3),
  );

  // Jewel body — radial gradient simulating depth/refraction
  final refractGrad = RadialGradient(
    center: const Alignment(-0.25, -0.3),
    focal: const Alignment(-0.15, -0.15),
    focalRadius: 0.05,
    colors: [
      _warmHighlight(color, 0.6), // bright caustic center
      _lighten(color, 0.25),
      color,
      _coolShadow(color, 0.3),
      _darken(color, 0.35),
    ],
    stops: const [0.0, 0.2, 0.45, 0.75, 1.0],
  );
  canvas.drawCircle(
    center,
    r,
    Paint()
      ..shader =
          refractGrad.createShader(Rect.fromCircle(center: center, radius: r)),
  );

  // Inner refraction line — simulates facet edge
  final facetPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.15)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.08;
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: r * 0.6),
    -pi * 0.7,
    pi * 0.5,
    false,
    facetPaint,
  );

  // Colored light rays emanating from jewel (refraction effect)
  for (int i = 0; i < 6; i++) {
    final angle = i * pi / 3 + pi * 0.1;
    final rayLen = r * (1.4 + (i % 2) * 0.4);
    canvas.drawLine(
      center,
      Offset(center.dx + rayLen * cos(angle), center.dy + rayLen * sin(angle)),
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..strokeWidth = r * 0.15
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.2),
    );
  }

  // Primary specular highlight (large soft)
  canvas.drawOval(
    Rect.fromCenter(
      center: center.translate(-r * 0.2, -r * 0.25),
      width: r * 0.55,
      height: r * 0.35,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15),
  );

  // Secondary specular (small sharp)
  canvas.drawCircle(
    center.translate(-r * 0.15, -r * 0.2),
    r * 0.12,
    Paint()..color = Colors.white.withValues(alpha: 0.85),
  );
}

/// 5-pointed star path.
Path _starPath(Offset center, double r) {
  final path = Path();
  for (int i = 0; i < 5; i++) {
    final outerAngle = -pi / 2 + i * 2 * pi / 5;
    final innerAngle = outerAngle + pi / 5;
    final outer =
        Offset(center.dx + r * cos(outerAngle), center.dy + r * sin(outerAngle));
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

/// Draw a small crescent moon shape.
void _drawMoon(Canvas canvas, Offset center, double r, Paint paint) {
  final moonPath = Path()
    ..addOval(Rect.fromCircle(center: center, radius: r));
  final cutout = Path()
    ..addOval(Rect.fromCircle(
        center: Offset(center.dx + r * 0.4, center.dy - r * 0.2),
        radius: r * 0.75));
  final crescent = Path.combine(PathOperation.difference, moonPath, cutout);
  canvas.drawPath(crescent, paint);
}

/// Draw a filigree curl (decorative scrollwork).
void _drawFiligree(Canvas canvas, Offset start, Offset end, double size,
    Paint paint, {bool flip = false}) {
  final mx = (start.dx + end.dx) / 2;
  final my = (start.dy + end.dy) / 2;
  final dir = flip ? -1.0 : 1.0;
  final path = Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      mx + size * 0.3 * dir, my - size * 0.5,
      mx - size * 0.2 * dir, my - size * 0.6,
      mx, my - size * 0.2,
    )
    ..cubicTo(
      mx + size * 0.2 * dir, my + size * 0.1,
      mx + size * 0.4 * dir, my - size * 0.1,
      end.dx, end.dy,
    );
  canvas.drawPath(path, paint);
}

// ══════════════════════════════════════════════════════════════════════
//  CROWN (accessory index 2)
// ══════════════════════════════════════════════════════════════════════

class CrownPainter extends CustomPainter {
  final Color color;
  final bool jewels;
  final double swayValue;

  CrownPainter({
    required this.color,
    this.jewels = false,
    this.swayValue = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    final crownPath = _crownPath(w, h);

    // Layered shadow beneath crown
    _drawShadow(canvas, crownPath, dy: h * 0.04, blur: 4, alpha: 0.25);

    // Metallic gold body — specular band shifts with sway
    final specPos = 0.25 + (swayValue - 0.5) * 0.1;
    canvas.drawPath(crownPath, _metallicPaint(bounds, color, specularPos: specPos));

    // Velvet liner inside the crown (dark red/purple gradient visible at base)
    final linerPath = Path()
      ..moveTo(w * 0.04, h)
      ..cubicTo(w * 0.04, h * 0.92, w * 0.04, h * 0.75, w * 0.06, h * 0.68)
      ..lineTo(w * 0.94, h * 0.68)
      ..cubicTo(w * 0.96, h * 0.75, w * 0.96, h * 0.92, w * 0.96, h)
      ..close();
    const linerGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF4A0030),
        Color(0xFF300020),
        Color(0xFF200018),
      ],
    );
    canvas.drawPath(linerPath,
        Paint()..shader = linerGrad.createShader(Rect.fromLTWH(0, h * 0.68, w, h * 0.32)));

    // Filigree ornamental curves on crown body
    final filigreePaint = Paint()
      ..color = _warmHighlight(color, 0.5).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;
    _drawFiligree(canvas, Offset(w * 0.10, h * 0.70), Offset(w * 0.30, h * 0.55),
        w * 0.12, filigreePaint);
    _drawFiligree(canvas, Offset(w * 0.70, h * 0.55), Offset(w * 0.90, h * 0.70),
        w * 0.12, filigreePaint, flip: true);
    _drawFiligree(canvas, Offset(w * 0.35, h * 0.65), Offset(w * 0.65, h * 0.65),
        w * 0.10, filigreePaint);

    // Embossed rim along top edge
    final rimHighlight = Paint()
      ..color = _warmHighlight(color, 0.5).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(crownPath, rimHighlight);

    // Animated metallic specular band that shifts with sway
    final bandShift = (swayValue - 0.5) * w * 0.15;
    final specularBandPath = Path()
      ..moveTo(w * 0.15 + bandShift, h * 0.30)
      ..cubicTo(w * 0.25 + bandShift, h * 0.25, w * 0.35 + bandShift, h * 0.75,
          w * 0.45 + bandShift, h * 0.70);
    canvas.drawPath(
      specularBandPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.04
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
    );

    // Inner shadow at base of crown (ambient occlusion)
    canvas.drawLine(
      Offset(w * 0.02, h * 0.95),
      Offset(w * 0.98, h * 0.95),
      Paint()
        ..color = _coolShadow(color, 0.4).withValues(alpha: 0.3)
        ..strokeWidth = h * 0.08
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.04),
    );

    // Decorative band detail
    final bandY = h * 0.82;
    canvas.drawLine(
      Offset(w * 0.03, bandY),
      Offset(w * 0.97, bandY),
      Paint()
        ..color = _darken(color, 0.15).withValues(alpha: 0.4)
        ..strokeWidth = h * 0.04
        ..strokeCap = StrokeCap.round,
    );

    if (jewels) {
      _drawJewel(canvas, Offset(w * 0.30, h * 0.42), w * 0.055,
          const Color(0xFFFF4D6A));
      _drawJewel(
          canvas, Offset(w * 0.50, h * 0.60), w * 0.06, AppColors.electricBlue);
      _drawJewel(
          canvas, Offset(w * 0.70, h * 0.42), w * 0.055, AppColors.emerald);
    }
  }

  Path _crownPath(double w, double h) {
    // Smooth crown using cubic beziers — no straight segments on the points
    return Path()
      ..moveTo(0, h)
      ..cubicTo(0, h * 0.85, 0, h * 0.5, w * 0.02, h * 0.38)
      ..cubicTo(w * 0.06, h * 0.50, w * 0.10, h * 0.58, w * 0.15, h * 0.58)
      ..cubicTo(w * 0.20, h * 0.58, w * 0.24, h * 0.25, w * 0.30, h * 0.10)
      ..cubicTo(w * 0.36, h * 0.30, w * 0.42, h * 0.48, w * 0.50, h * 0.48)
      ..cubicTo(w * 0.58, h * 0.48, w * 0.64, h * 0.30, w * 0.70, h * 0.10)
      ..cubicTo(w * 0.76, h * 0.25, w * 0.80, h * 0.58, w * 0.85, h * 0.58)
      ..cubicTo(w * 0.90, h * 0.58, w * 0.94, h * 0.50, w * 0.98, h * 0.38)
      ..cubicTo(w, h * 0.5, w, h * 0.85, w, h)
      ..close();
  }

  @override
  bool shouldRepaint(CrownPainter old) =>
      old.color != color ||
      old.jewels != jewels ||
      (old.swayValue * 50).round() != (swayValue * 50).round();
}

// ══════════════════════════════════════════════════════════════════════
//  FLOWER (accessory index 3)
// ══════════════════════════════════════════════════════════════════════

class FlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    final petalR = w * 0.26;

    // Shadow beneath flower
    canvas.drawCircle(
      c.translate(0, w * 0.03),
      petalR * 1.2,
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Small green leaf behind the flower
    canvas.save();
    canvas.translate(c.dx + petalR * 0.6, c.dy + petalR * 0.4);
    canvas.rotate(0.6);
    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(petalR * 0.25, -petalR * 0.35, petalR * 0.55, -petalR * 0.25, petalR * 0.7, 0)
      ..cubicTo(petalR * 0.55, petalR * 0.25, petalR * 0.25, petalR * 0.35, 0, 0)
      ..close();
    final leafGrad = LinearGradient(
      colors: [
        _lighten(const Color(0xFF3DA07A), 0.1),
        const Color(0xFF3DA07A),
        _darken(const Color(0xFF3DA07A), 0.1),
      ],
    );
    canvas.drawPath(leafPath,
        Paint()..shader = leafGrad.createShader(Rect.fromLTWH(0, -petalR * 0.35, petalR * 0.7, petalR * 0.7)));
    // Leaf vein
    canvas.drawLine(
      Offset.zero,
      Offset(petalR * 0.55, 0),
      Paint()
        ..color = const Color(0xFF2D8060).withValues(alpha: 0.35)
        ..strokeWidth = w * 0.005
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Second leaf on the other side
    canvas.save();
    canvas.translate(c.dx - petalR * 0.7, c.dy + petalR * 0.35);
    canvas.rotate(-0.5);
    final leaf2Path = Path()
      ..moveTo(0, 0)
      ..cubicTo(-petalR * 0.2, -petalR * 0.3, -petalR * 0.45, -petalR * 0.2, -petalR * 0.55, 0)
      ..cubicTo(-petalR * 0.45, petalR * 0.2, -petalR * 0.2, petalR * 0.3, 0, 0)
      ..close();
    canvas.drawPath(leaf2Path,
        Paint()..shader = leafGrad.createShader(Rect.fromLTWH(-petalR * 0.55, -petalR * 0.3, petalR * 0.55, petalR * 0.6)));
    canvas.restore();

    // Hoisted Paint objects for petal loop
    final veinPaint = Paint()
      ..color = const Color(0xFFFF7EB3).withValues(alpha: 0.25)
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    final petalFillPaint = Paint();
    final coolPinkShadow = _coolShadow(const Color(0xFFFF7EB3), 0.2);

    // 6 petals with translucency, individual petal-shaped bezier curves and gradient
    for (int i = 0; i < 6; i++) {
      final angle = i * 2 * pi / 6 - pi / 2;
      final petalTip = Offset(
          c.dx + petalR * 1.1 * cos(angle), c.dy + petalR * 1.1 * sin(angle));

      // Petal shape using bezier curves for organic feel
      final perpAngle = angle + pi / 2;
      final petalWidth = petalR * 0.38;
      final leftBase = Offset(
          c.dx + petalR * 0.15 * cos(angle) + petalWidth * cos(perpAngle),
          c.dy + petalR * 0.15 * sin(angle) + petalWidth * sin(perpAngle));
      final rightBase = Offset(
          c.dx + petalR * 0.15 * cos(angle) - petalWidth * cos(perpAngle),
          c.dy + petalR * 0.15 * sin(angle) - petalWidth * sin(perpAngle));

      final petalPath = Path()
        ..moveTo(leftBase.dx, leftBase.dy)
        ..cubicTo(
          leftBase.dx + petalR * 0.5 * cos(angle + 0.3),
          leftBase.dy + petalR * 0.5 * sin(angle + 0.3),
          petalTip.dx + petalWidth * 0.3 * cos(perpAngle),
          petalTip.dy + petalWidth * 0.3 * sin(perpAngle),
          petalTip.dx,
          petalTip.dy,
        )
        ..cubicTo(
          petalTip.dx - petalWidth * 0.3 * cos(perpAngle),
          petalTip.dy - petalWidth * 0.3 * sin(perpAngle),
          rightBase.dx + petalR * 0.5 * cos(angle - 0.3),
          rightBase.dy + petalR * 0.5 * sin(angle - 0.3),
          rightBase.dx,
          rightBase.dy,
        )
        ..close();

      // Petal gradient: warm white center to pink edge with warm undertones
      final petalGrad = RadialGradient(
        center: Alignment(cos(angle) * -0.5, sin(angle) * -0.5),
        radius: 1.2,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          const Color(0xFFFFF0F5), // warm undertone
          const Color(0xFFFFD0E0),
          const Color(0xFFFF7EB3),
          coolPinkShadow,
        ],
        stops: const [0.0, 0.15, 0.35, 0.65, 1.0],
      );
      final petalBounds = petalPath.getBounds();

      // Draw petal with slight translucency
      canvas.saveLayer(petalBounds, Paint()..color = Colors.white.withValues(alpha: 0.88));
      canvas.drawPath(
          petalPath, petalFillPaint..shader = petalGrad.createShader(petalBounds));
      canvas.restore();

      // Petal vein lines (center vein + branching)
      final veinStart = Offset(c.dx + petalR * 0.1 * cos(angle),
          c.dy + petalR * 0.1 * sin(angle));
      final veinEnd = Offset(c.dx + petalR * 0.85 * cos(angle),
          c.dy + petalR * 0.85 * sin(angle));
      canvas.drawLine(veinStart, veinEnd, veinPaint);

      // Side veins branching off center
      final thinVeinPaint = Paint()
        ..color = const Color(0xFFFF7EB3).withValues(alpha: 0.12)
        ..strokeWidth = w * 0.003
        ..strokeCap = StrokeCap.round;
      for (int v = 1; v <= 3; v++) {
        final t = v * 0.22;
        final vx = c.dx + petalR * t * cos(angle);
        final vy = c.dy + petalR * t * sin(angle);
        canvas.drawLine(
          Offset(vx, vy),
          Offset(vx + petalR * 0.12 * cos(angle + 0.7),
              vy + petalR * 0.12 * sin(angle + 0.7)),
          thinVeinPaint,
        );
        canvas.drawLine(
          Offset(vx, vy),
          Offset(vx + petalR * 0.12 * cos(angle - 0.7),
              vy + petalR * 0.12 * sin(angle - 0.7)),
          thinVeinPaint,
        );
      }
    }

    // Center with 3D gold dome
    final centerGrad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        _warmHighlight(AppColors.starGold, 0.4),
        AppColors.starGold,
        _darken(AppColors.starGold, 0.25),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawCircle(
        c,
        petalR * 0.35,
        Paint()
          ..shader = centerGrad
              .createShader(Rect.fromCircle(center: c, radius: petalR * 0.35)));

    // Pollen dots with individual tiny highlights
    final dotPaint = Paint()..color = const Color(0xFFCC9900);
    final dotHighlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.4);
    for (int i = 0; i < 8; i++) {
      final a = i * 2 * pi / 8 + 0.2;
      final dotCenter = Offset(
          c.dx + petalR * 0.18 * cos(a), c.dy + petalR * 0.18 * sin(a));
      canvas.drawCircle(dotCenter, petalR * 0.05, dotPaint);
      canvas.drawCircle(
        dotCenter.translate(-petalR * 0.015, -petalR * 0.015),
        petalR * 0.02,
        dotHighlightPaint,
      );
    }

    // Floating pollen particles above the flower
    final pollenPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    for (int i = 0; i < 5; i++) {
      final angle = i * 1.25 + 0.3;
      final dist = petalR * (0.5 + (i % 3) * 0.15);
      final py = c.dy - petalR * 0.3 - (i % 2) * petalR * 0.15;
      canvas.drawCircle(
        Offset(c.dx + dist * cos(angle) * 0.3, py),
        w * 0.008 + (i % 2) * w * 0.004,
        pollenPaint,
      );
    }

    // Center specular
    canvas.drawCircle(
      c.translate(-petalR * 0.08, -petalR * 0.1),
      petalR * 0.1,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(FlowerPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  BOW (accessory index 4) — satin fabric with proper folds
// ══════════════════════════════════════════════════════════════════════

class BowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow beneath bow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.55), width: w * 0.9, height: h * 0.4),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Left lobe — organic bezier shape with satin gradient
    _drawSatinLobe(canvas, w, h, isRight: false);
    // Right lobe
    _drawSatinLobe(canvas, w, h, isRight: true);

    // Ribbon tails hanging down with flowing gravity curve
    final tailGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFE0559D),
        _coolShadow(const Color(0xFFE0559D), 0.2),
      ],
    );
    final tailPaint = Paint()
      ..shader = tailGrad.createShader(Rect.fromLTWH(0, h * 0.5, w, h * 0.5));

    // Left tail — more flowing S-curve
    final leftTail = Path()
      ..moveTo(w * 0.44, h * 0.52)
      ..cubicTo(w * 0.40, h * 0.60, w * 0.34, h * 0.70, w * 0.30, h * 0.80)
      ..cubicTo(w * 0.28, h * 0.87, w * 0.25, h * 0.93, w * 0.22, h * 0.98)
      ..lineTo(w * 0.28, h * 0.90)
      ..cubicTo(w * 0.32, h * 0.82, w * 0.36, h * 0.72, w * 0.39, h * 0.64)
      ..cubicTo(w * 0.42, h * 0.58, w * 0.45, h * 0.54, w * 0.47, h * 0.52)
      ..close();
    canvas.drawPath(leftTail, tailPaint);
    // Tail satin sheen
    canvas.drawPath(leftTail, Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));

    // Right tail — flowing S-curve
    final rightTail = Path()
      ..moveTo(w * 0.56, h * 0.52)
      ..cubicTo(w * 0.60, h * 0.60, w * 0.66, h * 0.70, w * 0.70, h * 0.80)
      ..cubicTo(w * 0.72, h * 0.87, w * 0.75, h * 0.93, w * 0.78, h * 0.98)
      ..lineTo(w * 0.72, h * 0.90)
      ..cubicTo(w * 0.68, h * 0.82, w * 0.64, h * 0.72, w * 0.61, h * 0.64)
      ..cubicTo(w * 0.58, h * 0.58, w * 0.55, h * 0.54, w * 0.53, h * 0.52)
      ..close();
    canvas.drawPath(rightTail, tailPaint);
    canvas.drawPath(rightTail, Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));

    // Center knot — 3D dome shape with tighter wrinkle detail
    final knotCenter = Offset(w * 0.5, h * 0.48);
    final knotR = w * 0.10;
    final knotGrad = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      colors: [
        _warmHighlight(const Color(0xFFFF7EB3), 0.3),
        const Color(0xFFFF7EB3),
        _coolShadow(const Color(0xFFE0559D), 0.25),
        _darken(const Color(0xFFBB3380), 0.15),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    canvas.drawCircle(
      knotCenter,
      knotR,
      Paint()
        ..shader = knotGrad
            .createShader(Rect.fromCircle(center: knotCenter, radius: knotR)),
    );
    // Knot wrinkle lines (multiple for tight gathered fabric)
    final knotWrinklePaint = Paint()
      ..color = _darken(const Color(0xFFE0559D), 0.15).withValues(alpha: 0.25)
      ..strokeWidth = knotR * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      knotCenter.translate(-knotR * 0.15, -knotR * 0.5),
      knotCenter.translate(-knotR * 0.1, knotR * 0.5),
      knotWrinklePaint,
    );
    canvas.drawLine(
      knotCenter.translate(0, -knotR * 0.45),
      knotCenter.translate(0.05, knotR * 0.45),
      knotWrinklePaint,
    );
    canvas.drawLine(
      knotCenter.translate(knotR * 0.15, -knotR * 0.5),
      knotCenter.translate(knotR * 0.1, knotR * 0.5),
      knotWrinklePaint,
    );
    // Knot specular
    canvas.drawOval(
      Rect.fromCenter(
        center: knotCenter.translate(-knotR * 0.2, -knotR * 0.2),
        width: knotR * 0.5,
        height: knotR * 0.3,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  void _drawSatinLobe(Canvas canvas, double w, double h,
      {required bool isRight}) {
    final cx = isRight ? w * 0.72 : w * 0.28;
    final lw = w * 0.40;

    // Organic lobe shape via bezier
    final lobe = Path()
      ..moveTo(w * 0.5, h * 0.35)
      ..cubicTo(
        isRight ? w * 0.55 : w * 0.45,
        h * 0.05,
        cx + (isRight ? lw * 0.3 : -lw * 0.3),
        h * 0.02,
        cx + (isRight ? lw * 0.45 : -lw * 0.45),
        h * 0.35,
      )
      ..cubicTo(
        cx + (isRight ? lw * 0.5 : -lw * 0.5),
        h * 0.55,
        cx + (isRight ? lw * 0.2 : -lw * 0.2),
        h * 0.75,
        w * 0.5,
        h * 0.60,
      )
      ..close();

    // Satin gradient: lighter at center, darker at edges
    final satinGrad = RadialGradient(
      center: Alignment(isRight ? 0.15 : -0.15, -0.15),
      radius: 0.9,
      colors: [
        _warmHighlight(const Color(0xFFFF9EC0), 0.2),
        const Color(0xFFFF7EB3),
        _coolShadow(const Color(0xFFE0559D), 0.15),
      ],
      stops: const [0.0, 0.45, 1.0],
    );
    final lobeBounds = lobe.getBounds();
    canvas.drawPath(lobe, Paint()..shader = satinGrad.createShader(lobeBounds));

    // Fabric fold shadow lines (satin creases)
    final foldShadowPaint = Paint()
      ..color = _darken(const Color(0xFFE0559D), 0.15).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final foldX = isRight ? 1.0 : -1.0;
    // Two crease lines through each lobe
    canvas.drawLine(
      Offset(w * 0.5 + foldX * w * 0.05, h * 0.25),
      Offset(cx + foldX * lw * 0.15, h * 0.55),
      foldShadowPaint,
    );
    canvas.drawLine(
      Offset(cx - foldX * lw * 0.05, h * 0.15),
      Offset(cx + foldX * lw * 0.25, h * 0.45),
      foldShadowPaint,
    );

    // Diagonal sheen highlight across each loop (satin reflectance)
    final sheenPath = Path()
      ..moveTo(w * 0.5 + foldX * w * 0.02, h * 0.18)
      ..cubicTo(
        cx - foldX * lw * 0.1, h * 0.20,
        cx + foldX * lw * 0.1, h * 0.35,
        cx + foldX * lw * 0.3, h * 0.40,
      );
    canvas.drawPath(
      sheenPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Fabric fold highlight (overall soft glow)
    canvas.drawPath(
      lobe,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(BowPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  CAP (accessory index 5) — fabric texture with seams
// ══════════════════════════════════════════════════════════════════════

class CapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    // Shadow beneath cap
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.97), width: w * 1.05, height: h * 0.12),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Dome with fabric gradient (warm highlight on top, cool shadow below)
    final dome = Path()
      ..moveTo(w * 0.05, h * 0.85)
      ..cubicTo(w * 0.05, h * 0.35, w * 0.20, h * 0.13, w * 0.50, h * 0.12)
      ..cubicTo(w * 0.80, h * 0.13, w * 0.95, h * 0.35, w * 0.95, h * 0.85)
      ..close();

    final domeGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFF4A90D9), 0.15),
        _lighten(const Color(0xFF4A90D9), 0.08),
        const Color(0xFF4A90D9),
        _coolShadow(const Color(0xFF4A90D9), 0.15),
      ],
      stops: const [0.0, 0.25, 0.6, 1.0],
    );
    canvas.drawPath(dome, Paint()..shader = domeGrad.createShader(bounds));

    // Fabric panel seam lines with stitching detail
    final seamPaint = Paint()
      ..color = _coolShadow(const Color(0xFF4A90D9), 0.25).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;
    for (final sx in [0.30, 0.50, 0.70]) {
      final seamPath = Path()
        ..moveTo(w * sx, h * 0.14)
        ..cubicTo(w * sx, h * 0.35, w * sx, h * 0.55, w * sx, h * 0.82);
      canvas.drawPath(seamPath, seamPaint);

      // Dashed stitching along seams
      final stitchPaint = Paint()
        ..color = _lighten(const Color(0xFF4A90D9), 0.15).withValues(alpha: 0.3)
        ..strokeWidth = w * 0.004
        ..strokeCap = StrokeCap.round;
      for (double y = h * 0.18; y < h * 0.78; y += h * 0.05) {
        canvas.drawLine(
          Offset(w * sx + w * 0.008, y),
          Offset(w * sx + w * 0.008, y + h * 0.02),
          stitchPaint,
        );
      }
    }

    // Cross-hatch fabric weave texture
    final weavePaintH = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = w * 0.003;
    final weavePaintV = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = w * 0.002;
    for (double y = h * 0.2; y < h * 0.8; y += h * 0.05) {
      canvas.drawLine(Offset(w * 0.08, y), Offset(w * 0.92, y), weavePaintH);
    }
    // Vertical cross-hatch lines for canvas weave effect
    for (double x = w * 0.10; x < w * 0.90; x += w * 0.05) {
      canvas.drawLine(Offset(x, h * 0.16), Offset(x, h * 0.82), weavePaintV);
    }

    // Brim with curved gradient
    final brim = Path()
      ..moveTo(0, h * 0.83)
      ..cubicTo(w * 0.25, h * 0.90, w * 0.75, h * 0.90, w, h * 0.83)
      ..cubicTo(w, h * 0.92, w * 0.75, h, 0, h)
      ..close();
    final brimGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF3B7AC7),
        _coolShadow(const Color(0xFF3B7AC7), 0.2),
      ],
    );
    canvas.drawPath(
        brim, Paint()..shader = brimGrad.createShader(Rect.fromLTWH(0, h * 0.83, w, h * 0.17)));

    // Brim shadow on the face below
    canvas.drawLine(
      Offset(w * 0.05, h * 0.98),
      Offset(w * 0.95, h * 0.98),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.12)
        ..strokeWidth = h * 0.04
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Button on top with 3D dome
    final btnCenter = Offset(w * 0.50, h * 0.14);
    final btnR = w * 0.045;
    final btnGrad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [Colors.white, Colors.white.withValues(alpha: 0.6)],
    );
    canvas.drawCircle(
      btnCenter,
      btnR,
      Paint()
        ..shader =
            btnGrad.createShader(Rect.fromCircle(center: btnCenter, radius: btnR)),
    );
    canvas.drawCircle(
      btnCenter.translate(-btnR * 0.2, -btnR * 0.2),
      btnR * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(CapPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  WIZARD HAT (accessory index 6) — fabric folds, animated stars
// ══════════════════════════════════════════════════════════════════════

class WizardHatPainter extends CustomPainter {
  final double twinklePhase;

  WizardHatPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    // Shadow
    final hatPath = _hatPath(w, h);
    _drawShadow(canvas, hatPath, dy: h * 0.04, blur: 4, alpha: 0.2);

    // Hat cone with purple fabric gradient + fold shadows
    final hatGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _warmHighlight(AppColors.violet, 0.1),
        _lighten(AppColors.violet, 0.05),
        AppColors.violet,
        _coolShadow(AppColors.violet, 0.2),
        _darken(AppColors.violet, 0.25),
      ],
      stops: const [0.0, 0.2, 0.45, 0.7, 1.0],
    );
    canvas.drawPath(hatPath, Paint()..shader = hatGrad.createShader(bounds));

    // Fabric wrinkle shadows along the cone (multiple creases)
    final foldPaint = Paint()
      ..color = _darken(AppColors.violet, 0.2).withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawLine(
        Offset(w * 0.42, h * 0.15), Offset(w * 0.25, h * 0.65), foldPaint);
    canvas.drawLine(
        Offset(w * 0.55, h * 0.20), Offset(w * 0.72, h * 0.60), foldPaint);
    // Additional subtle wrinkle
    canvas.drawLine(
        Offset(w * 0.48, h * 0.10), Offset(w * 0.48, h * 0.55),
        Paint()
          ..color = _darken(AppColors.violet, 0.15).withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.01
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));

    // Brim with organic curl and depth
    final brimPath = Path()
      ..moveTo(w * 0.0, h * 0.82)
      ..cubicTo(w * 0.15, h * 0.78, w * 0.35, h * 0.76, w * 0.50, h * 0.77)
      ..cubicTo(w * 0.65, h * 0.76, w * 0.85, h * 0.78, w * 1.0, h * 0.82)
      ..cubicTo(w * 0.95, h * 0.96, w * 0.55, h * 0.98, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.45, h * 0.98, w * 0.05, h * 0.96, w * 0.0, h * 0.82)
      ..close();
    final brimGrad = RadialGradient(
      colors: [
        _lighten(AppColors.violet, 0.05),
        AppColors.violet,
        _darken(AppColors.violet, 0.15),
      ],
    );
    final brimRect = brimPath.getBounds();
    canvas.drawPath(brimPath, Paint()..shader = brimGrad.createShader(brimRect));

    // Gold star with animated glow
    final starCenter = Offset(w * 0.46, h * 0.36);
    final glowIntensity = 0.2 + sin(twinklePhase * 2 * pi) * 0.1;
    canvas.drawCircle(
      starCenter,
      w * 0.16,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: glowIntensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    final starGrad = RadialGradient(
      center: const Alignment(-0.2, -0.2),
      colors: [
        _warmHighlight(AppColors.starGold, 0.5),
        AppColors.starGold,
        _darken(AppColors.starGold, 0.15),
      ],
    );
    canvas.drawPath(
      _starPath(starCenter, w * 0.095),
      Paint()
        ..shader = starGrad.createShader(
            Rect.fromCircle(center: starCenter, radius: w * 0.095)),
    );

    // Small decorative moon
    _drawMoon(
      canvas,
      Offset(w * 0.62, h * 0.28),
      w * 0.03,
      Paint()..color = AppColors.starGold.withValues(alpha: 0.6),
    );

    // Small stars on hat body
    for (final pos in [
      Offset(w * 0.30, h * 0.50),
      Offset(w * 0.65, h * 0.55),
    ]) {
      canvas.drawPath(
        _starPath(pos, w * 0.025),
        Paint()..color = AppColors.starGold.withValues(alpha: 0.35),
      );
    }

    // Constellation dots that twinkle
    final dotPositions = [
      Offset(w * 0.33, h * 0.22),
      Offset(w * 0.62, h * 0.28),
      Offset(w * 0.58, h * 0.50),
      Offset(w * 0.28, h * 0.55),
      Offset(w * 0.43, h * 0.60),
      Offset(w * 0.68, h * 0.45),
      Offset(w * 0.38, h * 0.42),
    ];
    final twinklePaint = Paint();
    for (int i = 0; i < dotPositions.length; i++) {
      final phase = (twinklePhase + i * 0.14) % 1.0;
      final alpha = (sin(phase * 2 * pi) * 0.35 + 0.45).clamp(0.1, 0.8);
      final dotR = w * 0.010 + w * 0.005 * sin(phase * 2 * pi);
      canvas.drawCircle(
        dotPositions[i],
        dotR,
        twinklePaint..color = Colors.white.withValues(alpha: alpha),
      );
    }

    // Faint constellation lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = w * 0.004
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(dotPositions[0], dotPositions[1], linePaint);
    canvas.drawLine(dotPositions[1], dotPositions[5], linePaint);
    canvas.drawLine(dotPositions[3], dotPositions[4], linePaint);

    // Sparkle particles at the tip
    final tipSparklePhase = (twinklePhase * 3) % 1.0;
    for (int i = 0; i < 4; i++) {
      final sa = i * pi / 2 + tipSparklePhase * pi * 2;
      final sd = w * 0.03 + w * 0.02 * sin(tipSparklePhase * pi * 2 + i);
      final sp = Offset(w * 0.48 + sd * cos(sa), h * 0.02 + sd * sin(sa).abs());
      final sparkleAlpha = (sin(tipSparklePhase * pi * 2 + i * 1.5) * 0.4 + 0.4).clamp(0.0, 0.8);
      canvas.drawCircle(
        sp,
        w * 0.006,
        Paint()..color = Colors.white.withValues(alpha: sparkleAlpha),
      );
    }
  }

  Path _hatPath(double w, double h) {
    return Path()
      ..moveTo(w * 0.48, 0)
      ..cubicTo(w * 0.42, h * 0.15, w * 0.20, h * 0.55, w * 0.05, h * 0.82)
      ..cubicTo(w * 0.20, h * 0.76, w * 0.80, h * 0.76, w * 0.95, h * 0.82)
      ..cubicTo(w * 0.80, h * 0.55, w * 0.56, h * 0.15, w * 0.52, 0)
      ..close();
  }

  @override
  bool shouldRepaint(WizardHatPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  WINGS (accessory index 7) — translucent with iridescent shift
// ══════════════════════════════════════════════════════════════════════

class WingsPainter extends CustomPainter {
  final double swayValue;

  WingsPainter({this.swayValue = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _drawWing(canvas, w, h, isLeft: true);
    _drawWing(canvas, w, h, isLeft: false);
  }

  void _drawWing(Canvas canvas, double w, double h, {required bool isLeft}) {
    final sign = isLeft ? -1.0 : 1.0;
    final baseX = w * 0.50 + sign * w * 0.12;
    final tipX = w * 0.50 + sign * w * 0.48;
    final midX = w * 0.50 + sign * w * 0.35;

    // Wing shape with organic bezier curves
    final wingPath = Path()
      ..moveTo(baseX, h * 0.45)
      // Upper edge sweeping out to tip
      ..cubicTo(
        baseX + sign * w * 0.10, h * 0.15,
        tipX - sign * w * 0.05, h * 0.08,
        tipX, h * 0.35,
      )
      // Outer edge curving down with feather serrations
      ..cubicTo(
        tipX + sign * w * 0.02, h * 0.55,
        tipX - sign * w * 0.05, h * 0.75,
        midX, h * 0.88,
      )
      // Lower edge sweeping back to base
      ..cubicTo(
        midX - sign * w * 0.08, h * 0.80,
        baseX + sign * w * 0.02, h * 0.68,
        baseX, h * 0.55,
      )
      ..close();

    // Iridescent gradient — hue shifts based on sway value for shimmer
    final hueShift = (swayValue - 0.5) * 0.3;
    final iridescentGrad = LinearGradient(
      begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      colors: [
        AppColors.electricBlue.withValues(alpha: 0.10),
        AppColors.electricBlue.withValues(alpha: 0.25 + hueShift * 0.1),
        AppColors.violet.withValues(alpha: 0.22 - hueShift * 0.05),
        AppColors.magenta.withValues(alpha: 0.18 + hueShift * 0.08),
        AppColors.electricBlue.withValues(alpha: 0.30),
        AppColors.cyan.withValues(alpha: 0.20 - hueShift * 0.05),
      ],
      stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    );

    // Use saveLayer for proper translucent compositing
    final wingBounds = wingPath.getBounds();
    canvas.saveLayer(wingBounds, Paint());
    canvas.drawPath(
        wingPath, Paint()..shader = iridescentGrad.createShader(wingBounds));

    // Individual feather shapes overlapping
    _drawFeathers(canvas, w, h, baseX, tipX, midX, sign);

    // Membrane vein structure — organic branching lines
    final veinPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.004
      ..strokeCap = StrokeCap.round;

    final thinVeinPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.002
      ..strokeCap = StrokeCap.round;

    // Main vein
    final mainVein = Path()
      ..moveTo(baseX, h * 0.50)
      ..cubicTo(
        baseX + sign * w * 0.12, h * 0.42,
        midX - sign * w * 0.05, h * 0.40,
        tipX - sign * w * 0.10, h * 0.38,
      );
    canvas.drawPath(mainVein, veinPaint);

    // Secondary veins branching from main
    for (int i = 0; i < 4; i++) {
      final t = 0.2 + i * 0.2;
      final vx = baseX + (tipX - baseX) * t;
      final vy = h * (0.48 - t * 0.08);

      // Upper branch
      final upperBranch = Path()
        ..moveTo(vx, vy)
        ..cubicTo(
          vx + sign * w * 0.04, vy - h * 0.08,
          vx + sign * w * 0.06, vy - h * 0.12,
          vx + sign * w * 0.08, vy - h * 0.15,
        );
      canvas.drawPath(upperBranch, thinVeinPaint);

      // Lower branch
      final lowerBranch = Path()
        ..moveTo(vx, vy)
        ..cubicTo(
          vx + sign * w * 0.03, vy + h * 0.06,
          vx + sign * w * 0.05, vy + h * 0.12,
          vx + sign * w * 0.06, vy + h * 0.18,
        );
      canvas.drawPath(lowerBranch, thinVeinPaint);
    }

    canvas.restore();

    // Wing outline with iridescent edge
    final outlineGrad = LinearGradient(
      begin: isLeft ? Alignment.topRight : Alignment.topLeft,
      end: isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
      colors: [
        AppColors.electricBlue.withValues(alpha: 0.5),
        AppColors.violet.withValues(alpha: 0.4),
        AppColors.electricBlue.withValues(alpha: 0.6),
      ],
    );
    canvas.drawPath(
      wingPath,
      Paint()
        ..shader = outlineGrad.createShader(wingBounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.005,
    );

    // Feather edge detail — serrated outer edge
    _drawFeatherEdge(canvas, w, h, tipX, midX, sign);
  }

  void _drawFeathers(Canvas canvas, double w, double h,
      double baseX, double tipX, double midX, double sign) {
    // Individual overlapping feather shapes along the wing
    final featherPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    final featherStrokePaint = Paint()
      ..color = AppColors.violet.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.002;

    for (int i = 0; i < 5; i++) {
      final t = 0.15 + i * 0.16;
      final fx = baseX + (tipX - baseX) * t;
      final fy = h * (0.38 + t * 0.08);
      final fLen = w * 0.08 * (1.0 - t * 0.3);

      final feather = Path()
        ..moveTo(fx, fy)
        ..cubicTo(
          fx + sign * fLen * 0.3, fy - fLen * 0.8,
          fx + sign * fLen * 0.7, fy - fLen * 1.0,
          fx + sign * fLen, fy - fLen * 0.6,
        )
        ..cubicTo(
          fx + sign * fLen * 0.8, fy - fLen * 0.2,
          fx + sign * fLen * 0.4, fy + fLen * 0.1,
          fx, fy,
        )
        ..close();
      canvas.drawPath(feather, featherPaint);
      canvas.drawPath(feather, featherStrokePaint);
    }
  }

  void _drawFeatherEdge(Canvas canvas, double w, double h,
      double tipX, double midX, double sign) {
    // Small serrated notches along the outer wing edge
    final edgePaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.003
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 6; i++) {
      final t = i / 6.0;
      final ex = tipX + (midX - tipX) * t;
      final ey = h * (0.35 + t * 0.53);
      final notchLen = w * 0.015;
      canvas.drawLine(
        Offset(ex, ey),
        Offset(ex + sign * notchLen, ey + notchLen * 0.5),
        edgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(WingsPainter old) =>
      (old.swayValue * 30).round() != (swayValue * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  ROYAL CROWN (accessory index 8) — elaborate with cross/orb
// ══════════════════════════════════════════════════════════════════════

class RoyalCrownPainter extends CustomPainter {
  final double swayValue;

  RoyalCrownPainter({this.swayValue = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    final crownPath = _crownPath(w, h);

    // Shadow
    _drawShadow(canvas, crownPath, dy: h * 0.05, blur: 5, alpha: 0.25);

    // Metallic gold body with shifting specular
    final specPos = 0.3 + (swayValue - 0.5) * 0.1;
    canvas.drawPath(crownPath, _metallicPaint(bounds, AppColors.starGold, specularPos: specPos));

    // Ermine fur trim at base — white with black spots
    final furBaseY = h * 0.82;
    final furHeight = h * 0.18;
    final furRect = Rect.fromLTWH(w * 0.01, furBaseY, w * 0.98, furHeight);
    const furGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF8F8F0),
        Color(0xFFF0F0E8),
        Color(0xFFE8E8E0),
      ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(furRect, Radius.circular(h * 0.02)),
      Paint()..shader = furGrad.createShader(furRect),
    );
    // Black ermine spots
    final spotPaint = Paint()..color = const Color(0xFF1A1A2E);
    for (int i = 0; i < 8; i++) {
      final sx = w * (0.06 + i * 0.12);
      final sy = furBaseY + furHeight * 0.5;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(sx, sy), width: w * 0.018, height: h * 0.035),
        spotPaint,
      );
    }

    // Arched band structure across the crown
    final archPaint = Paint()
      ..shader = _metallicPaint(bounds, AppColors.starGold).shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015;
    final archPath = Path()
      ..moveTo(w * 0.10, h * 0.65)
      ..cubicTo(w * 0.30, h * 0.25, w * 0.70, h * 0.25, w * 0.90, h * 0.65);
    canvas.drawPath(archPath, archPaint);
    // Second arch perpendicular (foreshortened)
    final arch2Path = Path()
      ..moveTo(w * 0.35, h * 0.60)
      ..cubicTo(w * 0.42, h * 0.30, w * 0.58, h * 0.30, w * 0.65, h * 0.60);
    canvas.drawPath(arch2Path, Paint()
      ..shader = _metallicPaint(bounds, AppColors.starGold).shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.010);

    // Embossed border along top
    canvas.drawPath(
      crownPath,
      Paint()
        ..color = _warmHighlight(AppColors.starGold, 0.45).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.010,
    );

    // Cross/orb finial on top
    final orbCenter = Offset(w * 0.50, h * 0.06);
    _drawJewel(canvas, orbCenter, w * 0.04, AppColors.starGold);

    final crossPaint = Paint()
      ..shader = _metallicPaint(bounds, AppColors.starGold).shader
      ..strokeWidth = w * 0.018
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.50, h * 0.01), Offset(w * 0.50, h * 0.12), crossPaint);
    canvas.drawLine(Offset(w * 0.44, h * 0.05), Offset(w * 0.56, h * 0.05), crossPaint);

    // Multiple jewels with refraction and caustic light patterns
    _drawJewel(canvas, Offset(w * 0.20, h * 0.48), w * 0.04, const Color(0xFFFF4D6A));
    _drawJewel(canvas, Offset(w * 0.35, h * 0.32), w * 0.035, AppColors.electricBlue);
    _drawJewel(canvas, Offset(w * 0.50, h * 0.52), w * 0.05, AppColors.emerald);
    _drawJewel(canvas, Offset(w * 0.65, h * 0.32), w * 0.035, AppColors.violet);
    _drawJewel(canvas, Offset(w * 0.80, h * 0.48), w * 0.04, const Color(0xFFFF4D6A));
  }

  Path _crownPath(double w, double h) {
    return Path()
      ..moveTo(0, h)
      ..cubicTo(0, h * 0.85, 0, h * 0.45, w * 0.02, h * 0.32)
      ..cubicTo(w * 0.05, h * 0.42, w * 0.08, h * 0.52, w * 0.10, h * 0.50)
      ..cubicTo(w * 0.14, h * 0.46, w * 0.17, h * 0.22, w * 0.20, h * 0.14)
      ..cubicTo(w * 0.24, h * 0.28, w * 0.30, h * 0.40, w * 0.35, h * 0.42)
      ..cubicTo(w * 0.40, h * 0.42, w * 0.45, h * 0.18, w * 0.50, h * 0.06)
      ..cubicTo(w * 0.55, h * 0.18, w * 0.60, h * 0.42, w * 0.65, h * 0.42)
      ..cubicTo(w * 0.70, h * 0.40, w * 0.76, h * 0.28, w * 0.80, h * 0.14)
      ..cubicTo(w * 0.83, h * 0.22, w * 0.86, h * 0.46, w * 0.90, h * 0.50)
      ..cubicTo(w * 0.92, h * 0.52, w * 0.95, h * 0.42, w * 0.98, h * 0.32)
      ..cubicTo(w, h * 0.45, w, h * 0.85, w, h)
      ..close();
  }

  @override
  bool shouldRepaint(RoyalCrownPainter old) =>
      (old.swayValue * 50).round() != (swayValue * 50).round();
}

// ══════════════════════════════════════════════════════════════════════
//  TIARA (accessory index 9)
// ══════════════════════════════════════════════════════════════════════

class TiaraPainter extends CustomPainter {
  final double twinklePhase;

  TiaraPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.02, h * 0.60, w * 0.96, h * 0.35),
        Radius.circular(h * 0.15),
      ).shift(Offset(0, h * 0.04)),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Band with silver-pink metallic gradient that responds to animation
    final shimmerOffset = sin(twinklePhase * 2 * pi) * 0.1;
    final bandGrad = LinearGradient(
      colors: [
        _warmHighlight(const Color(0xFFFFB6C1), 0.25 + shimmerOffset),
        _lighten(const Color(0xFFFFB6C1), 0.1),
        const Color(0xFFFFB6C1),
        _coolShadow(const Color(0xFFFFB6C1), 0.1),
        _warmHighlight(const Color(0xFFFFB6C1), 0.15 + shimmerOffset),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.55, w, h * 0.35),
        Radius.circular(h * 0.15),
      ),
      Paint()..shader = bandGrad.createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.35)),
    );

    // Filigree scrollwork along the band
    final filigreePaint = Paint()
      ..color = _warmHighlight(const Color(0xFFFFB6C1), 0.4).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.005
      ..strokeCap = StrokeCap.round;
    // Left scrollwork
    final scrollL = Path()
      ..moveTo(w * 0.08, h * 0.72)
      ..cubicTo(w * 0.12, h * 0.62, w * 0.18, h * 0.65, w * 0.15, h * 0.72)
      ..cubicTo(w * 0.12, h * 0.78, w * 0.20, h * 0.80, w * 0.25, h * 0.72);
    canvas.drawPath(scrollL, filigreePaint);
    // Right scrollwork
    final scrollR = Path()
      ..moveTo(w * 0.92, h * 0.72)
      ..cubicTo(w * 0.88, h * 0.62, w * 0.82, h * 0.65, w * 0.85, h * 0.72)
      ..cubicTo(w * 0.88, h * 0.78, w * 0.80, h * 0.80, w * 0.75, h * 0.72);
    canvas.drawPath(scrollR, filigreePaint);

    // Spires with smooth curves
    final spirePath = Path()
      ..moveTo(w * 0.08, h * 0.65)
      ..cubicTo(w * 0.12, h * 0.45, w * 0.16, h * 0.25, w * 0.20, h * 0.20)
      ..cubicTo(w * 0.24, h * 0.35, w * 0.26, h * 0.50, w * 0.30, h * 0.52)
      ..cubicTo(w * 0.34, h * 0.38, w * 0.37, h * 0.15, w * 0.40, h * 0.10)
      ..cubicTo(w * 0.43, h * 0.25, w * 0.46, h * 0.40, w * 0.50, h * 0.42)
      ..cubicTo(w * 0.54, h * 0.40, w * 0.57, h * 0.25, w * 0.60, h * 0.10)
      ..cubicTo(w * 0.63, h * 0.15, w * 0.66, h * 0.38, w * 0.70, h * 0.52)
      ..cubicTo(w * 0.74, h * 0.50, w * 0.76, h * 0.35, w * 0.80, h * 0.20)
      ..cubicTo(w * 0.84, h * 0.25, w * 0.88, h * 0.45, w * 0.92, h * 0.65)
      ..close();

    final spireGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFFFFB6C1), 0.3),
        const Color(0xFFFFB6C1),
        _coolShadow(const Color(0xFFFFB6C1), 0.1),
      ],
    );
    canvas.drawPath(
        spirePath, Paint()..shader = spireGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

    // Edge highlight
    canvas.drawPath(
      spirePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.008,
    );

    // Small diamond accents along the band
    final diamondPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final dx in [0.15, 0.30, 0.50, 0.70, 0.85]) {
      final dc = Offset(w * dx, h * 0.68);
      final dr = w * 0.012;
      final diamondPath = Path()
        ..moveTo(dc.dx, dc.dy - dr)
        ..lineTo(dc.dx + dr * 0.7, dc.dy)
        ..lineTo(dc.dx, dc.dy + dr)
        ..lineTo(dc.dx - dr * 0.7, dc.dy)
        ..close();
      canvas.drawPath(diamondPath, diamondPaint);
      // Diamond sparkle
      canvas.drawCircle(
        dc.translate(-dr * 0.2, -dr * 0.2),
        dr * 0.2,
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }

    // Main Jewels
    _drawJewel(canvas, Offset(w * 0.40, h * 0.17), w * 0.035, const Color(0xFFE0559D));
    _drawJewel(canvas, Offset(w * 0.60, h * 0.17), w * 0.035, const Color(0xFFE0559D));
    _drawJewel(canvas, Offset(w * 0.50, h * 0.48), w * 0.04, AppColors.starGold);
  }

  @override
  bool shouldRepaint(TiaraPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  BUNNY EARS (accessory index 10) — soft fur texture
// ══════════════════════════════════════════════════════════════════════

class BunnyEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow beneath ears at base
    for (final sx in [w * 0.27, w * 0.73]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(sx, h * 0.95), width: w * 0.18, height: h * 0.06),
        Paint()
          ..color = const Color(0xFF1A1040).withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Outer ear gradient (white fur with warm highlights and cool shadows)
    final outerGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFFF5F5F5), 0.05),
        const Color(0xFFF5F5F5),
        _coolShadow(const Color(0xFFE8E8E8), 0.08),
      ],
    );

    // Inner ear gradient (pink tissue — warmer and translucent)
    final innerGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFFFD0DD),
        const Color(0xFFFFB6C1),
        _coolShadow(const Color(0xFFFFB6C1), 0.1),
      ],
    );

    for (final isLeft in [true, false]) {
      final mx = isLeft ? 1.0 : -1.0;
      final cx = isLeft ? w * 0.27 : w * 0.73;

      // Outer ear with bezier curves and natural droop at tip
      final tipDroop = h * 0.03; // slight bend/droop
      final outer = Path()
        ..moveTo(cx - mx * w * 0.07, h * 0.95)
        ..cubicTo(
          cx - mx * w * 0.14, h * 0.60,
          cx - mx * w * 0.10, h * 0.20,
          cx - mx * w * 0.04, h * 0.05 + tipDroop,
        )
        ..cubicTo(
          cx - mx * w * 0.02, h * 0.02 + tipDroop,
          cx + mx * w * 0.01, h * 0.01,
          cx + mx * w * 0.07, h * 0.15,
        )
        ..cubicTo(
          cx + mx * w * 0.10, h * 0.50,
          cx + mx * w * 0.08, h * 0.75,
          cx + mx * w * 0.07, h * 0.95,
        )
        ..close();
      canvas.drawPath(outer, Paint()..shader = outerGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

      // Inner ear with subtle veining
      final inner = Path()
        ..moveTo(cx - mx * w * 0.04, h * 0.85)
        ..cubicTo(
          cx - mx * w * 0.09, h * 0.55,
          cx - mx * w * 0.06, h * 0.25,
          cx - mx * w * 0.02, h * 0.15,
        )
        ..cubicTo(
          cx, h * 0.10,
          cx + mx * w * 0.01, h * 0.12,
          cx + mx * w * 0.04, h * 0.22,
        )
        ..cubicTo(
          cx + mx * w * 0.06, h * 0.50,
          cx + mx * w * 0.05, h * 0.70,
          cx + mx * w * 0.04, h * 0.85,
        )
        ..close();
      canvas.drawPath(inner, Paint()..shader = innerGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

      // Inner ear veining — subtle pink lines
      final veinPaint = Paint()
        ..color = const Color(0xFFFF8FAA).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.004
        ..strokeCap = StrokeCap.round;
      // Center vein
      canvas.drawLine(
        Offset(cx, h * 0.20),
        Offset(cx, h * 0.70),
        veinPaint,
      );
      // Branch veins
      canvas.drawLine(
        Offset(cx, h * 0.35),
        Offset(cx - mx * w * 0.025, h * 0.45),
        veinPaint,
      );
      canvas.drawLine(
        Offset(cx, h * 0.50),
        Offset(cx + mx * w * 0.02, h * 0.60),
        veinPaint,
      );

      // Fur edge softness — tiny fur strokes along outer edge
      final furPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = w * 0.005
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 8; i++) {
        final t = 0.1 + i * 0.1;
        final fy = h * t;
        final edgeX = cx - mx * w * (0.07 + 0.05 * sin(t * pi));
        canvas.drawLine(
          Offset(edgeX, fy),
          Offset(edgeX - mx * w * 0.015, fy - h * 0.02),
          furPaint,
        );
      }

      // Fur edge outline softness
      canvas.drawPath(
        outer,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.012
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(BunnyEarsPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  CAT EARS (accessory index 11)
// ══════════════════════════════════════════════════════════════════════

class CatEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outerGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFFB794F6), 0.1),
        const Color(0xFFB794F6),
        _coolShadow(const Color(0xFFB794F6), 0.15),
      ],
    );

    const innerGrad = RadialGradient(
      center: Alignment(0.0, -0.2),
      colors: [
        Color(0xFFFFD0DD),
        Color(0xFFFFB6C1),
      ],
    );

    for (final isLeft in [true, false]) {
      final tipX = isLeft ? w * 0.18 : w * 0.82;
      final baseL = isLeft ? w * 0.10 : w * 0.60;
      final baseR = isLeft ? w * 0.40 : w * 0.90;

      // Ear back shadow for depth
      final backShadow = Path()
        ..moveTo(baseL - w * 0.01, h * 0.90)
        ..cubicTo(baseL - w * 0.03, h * 0.58, tipX - w * 0.04, h * 0.18, tipX - w * 0.01, h * 0.08)
        ..cubicTo(tipX + w * 0.04, h * 0.18, baseR + w * 0.03, h * 0.58, baseR + w * 0.01, h * 0.78)
        ..close();
      canvas.drawPath(backShadow, Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

      // Outer with curved edges — more triangular with slight curve
      final outer = Path()
        ..moveTo(baseL, h * 0.88)
        ..cubicTo(baseL - w * 0.02, h * 0.55, tipX - w * 0.03, h * 0.15, tipX, h * 0.05)
        ..cubicTo(tipX + w * 0.03, h * 0.15, baseR + w * 0.02, h * 0.55, baseR, h * 0.75)
        ..cubicTo(baseR - w * 0.02, h * 0.82, baseL + w * 0.05, h * 0.90, baseL, h * 0.88)
        ..close();
      canvas.drawPath(outer, Paint()..shader = outerGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

      // Inner pink with lighter colored fluff
      final innerPath = Path()
        ..moveTo(baseL + w * 0.04, h * 0.78)
        ..cubicTo(baseL + w * 0.02, h * 0.52, tipX, h * 0.22, tipX + w * 0.01, h * 0.18)
        ..cubicTo(tipX + w * 0.02, h * 0.22, baseR - w * 0.02, h * 0.52, baseR - w * 0.04, h * 0.68)
        ..cubicTo(baseR - w * 0.05, h * 0.74, baseL + w * 0.06, h * 0.80, baseL + w * 0.04, h * 0.78)
        ..close();
      final innerBounds = innerPath.getBounds();
      canvas.drawPath(innerPath, Paint()..shader = innerGrad.createShader(innerBounds));

      // Inner ear fur fluff — lighter colored strokes
      final fluffPaint = Paint()
        ..color = const Color(0xFFFFD8E8).withValues(alpha: 0.25)
        ..strokeWidth = w * 0.006
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 5; i++) {
        final t = 0.3 + i * 0.1;
        final fy = h * t;
        final fx = tipX + (isLeft ? 1 : -1) * w * 0.01 * (i - 2);
        canvas.drawLine(
          Offset(fx, fy),
          Offset(fx + (isLeft ? -1 : 1) * w * 0.012, fy - h * 0.025),
          fluffPaint,
        );
      }

      // Fur tufts at tips — small hair strands poking up
      final tuftPaint = Paint()
        ..color = _lighten(const Color(0xFFB794F6), 0.1).withValues(alpha: 0.6)
        ..strokeWidth = w * 0.005
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 3; i++) {
        final angle = -pi / 2 + (i - 1) * 0.25;
        canvas.drawLine(
          Offset(tipX, h * 0.05),
          Offset(
            tipX + w * 0.025 * cos(angle),
            h * 0.05 + h * 0.03 * sin(angle),
          ),
          tuftPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CatEarsPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  UNICORN HORN (accessory index 12) — spiral rainbow with ridges
// ══════════════════════════════════════════════════════════════════════

class UnicornHornPainter extends CustomPainter {
  final double twinklePhase;

  UnicornHornPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final hornPath = Path()
      ..moveTo(w * 0.50, 0)
      ..cubicTo(w * 0.42, h * 0.20, w * 0.32, h * 0.55, w * 0.30, h * 0.90)
      ..lineTo(w * 0.70, h * 0.90)
      ..cubicTo(w * 0.68, h * 0.55, w * 0.58, h * 0.20, w * 0.50, 0)
      ..close();

    // Soft radial glow around horn tip
    final glowR = w * 0.15;
    final tipGlow = RadialGradient(
      colors: [
        const Color(0xFFE0C3FC).withValues(alpha: 0.35),
        const Color(0xFFE0C3FC).withValues(alpha: 0.15),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.04),
      glowR,
      Paint()..shader = tipGlow.createShader(
          Rect.fromCircle(center: Offset(w * 0.50, h * 0.04), radius: glowR)),
    );

    // Magical glow behind horn
    canvas.drawPath(
      hornPath,
      Paint()
        ..color = const Color(0xFFE0C3FC).withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Rainbow gradient that wraps around the spiral using SweepGradient
    final hornCenter = Offset(w * 0.50, h * 0.45);
    final sweepGrad = ui.Gradient.sweep(
      hornCenter,
      [
        const Color(0xFFF0E0FF),
        const Color(0xFFFFB6C1),
        const Color(0xFFFFD700),
        const Color(0xFF90E0C0),
        const Color(0xFFB0C0FF),
        const Color(0xFFE0C3FC),
        const Color(0xFFF0E0FF),
      ],
      [0.0, 0.15, 0.3, 0.5, 0.65, 0.85, 1.0],
    );
    canvas.drawPath(hornPath, Paint()..shader = sweepGrad);

    // Lighter overlay for depth
    final depthGrad = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white.withValues(alpha: 0.15),
        Colors.transparent,
        _darken(const Color(0xFFE0C3FC), 0.1).withValues(alpha: 0.15),
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    canvas.drawPath(hornPath, Paint()..shader = depthGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

    // Spiral ridge grooves — actual 3D-looking spiral ridges
    for (int i = 1; i < 7; i++) {
      final y = h * (0.08 + i * 0.12);
      final hornWidthAtY = w * 0.20 * (1 - (y / h) * 0.6);
      final ridgeOffset = (i.isEven ? 1 : -1) * hornWidthAtY * 0.1;

      // Ridge shadow (cool-shifted) — wider for 3D depth
      final ridgePath = Path()
        ..moveTo(w * 0.50 - hornWidthAtY + ridgeOffset, y + h * 0.01)
        ..cubicTo(
          w * 0.50 - hornWidthAtY * 0.3 + ridgeOffset, y + h * 0.025,
          w * 0.50 + hornWidthAtY * 0.3 + ridgeOffset, y + h * 0.025,
          w * 0.50 + hornWidthAtY + ridgeOffset, y + h * 0.03,
        );
      canvas.drawPath(
        ridgePath,
        Paint()
          ..color = const Color(0xFF8060B0).withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );

      // Ridge highlight (warm-shifted)
      final highlightPath = Path()
        ..moveTo(w * 0.50 - hornWidthAtY + ridgeOffset, y - h * 0.005)
        ..cubicTo(
          w * 0.50 - hornWidthAtY * 0.3 + ridgeOffset, y + h * 0.008,
          w * 0.50 + hornWidthAtY * 0.3 + ridgeOffset, y + h * 0.008,
          w * 0.50 + hornWidthAtY + ridgeOffset, y + h * 0.015,
        );
      canvas.drawPath(
        highlightPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.018
          ..strokeCap = StrokeCap.round,
      );
    }

    // Sparkle particles at the tip
    for (int i = 0; i < 5; i++) {
      final phase = (twinklePhase * 2 + i * 0.2) % 1.0;
      final sparkleAngle = phase * 2 * pi + i * 1.2;
      final sparkleR = w * 0.04 + w * 0.025 * sin(phase * pi);
      final sparkleAlpha = (sin(phase * pi) * 0.6 + 0.1).clamp(0.0, 0.7);
      canvas.drawCircle(
        Offset(
          w * 0.50 + sparkleR * cos(sparkleAngle),
          h * 0.02 + sparkleR * sin(sparkleAngle).abs() * 0.5,
        ),
        w * 0.008,
        Paint()..color = Colors.white.withValues(alpha: sparkleAlpha),
      );
    }

    // Tip sparkle (main)
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.02),
      w * 0.03,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(UnicornHornPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  STAR HEADBAND (accessory index 13)
// ══════════════════════════════════════════════════════════════════════

class StarHeadbandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Metallic gold band with brushed metal gradient
    final bandGrad = LinearGradient(
      colors: [
        _darken(AppColors.starGold, 0.15),
        _coolShadow(AppColors.starGold, 0.08),
        _warmHighlight(AppColors.starGold, 0.3),
        AppColors.starGold,
        _warmHighlight(AppColors.starGold, 0.2),
        _coolShadow(AppColors.starGold, 0.12),
        _darken(AppColors.starGold, 0.1),
      ],
      stops: const [0.0, 0.15, 0.3, 0.5, 0.65, 0.8, 1.0],
    );
    final bandPaint = Paint()
      ..shader = bandGrad.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.22
      ..strokeCap = StrokeCap.round;

    // Band follows head curvature
    final bandArcRect = Rect.fromLTWH(w * 0.02, -h * 0.2, w * 0.96, h * 1.4);
    canvas.drawArc(
      bandArcRect,
      pi * 0.05,
      pi * 0.90,
      false,
      bandPaint,
    );

    // Brushed metal texture hint — fine horizontal lines on band
    final brushPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.002;
    for (int i = 0; i < 5; i++) {
      final deflation = h * (0.04 + i * 0.03);
      canvas.drawArc(
        bandArcRect.deflate(deflation),
        pi * 0.10,
        pi * 0.80,
        false,
        brushPaint,
      );
    }

    // Stars with glow at each position
    final positions = [
      Offset(w * 0.15, h * 0.45),
      Offset(w * 0.35, h * 0.20),
      Offset(w * 0.50, h * 0.12),
      Offset(w * 0.65, h * 0.20),
      Offset(w * 0.85, h * 0.45),
    ];

    final starGlowPaint = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final starSpecularPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);

    for (int i = 0; i < positions.length; i++) {
      final starSize = (i == 2) ? w * 0.08 : w * 0.055;

      // Glow
      canvas.drawCircle(
        positions[i],
        starSize * 1.8,
        starGlowPaint,
      );

      // Star with metallic gradient
      final starBounds = Rect.fromCircle(center: positions[i], radius: starSize);
      canvas.drawPath(
        _starPath(positions[i], starSize),
        _metallicPaint(starBounds, AppColors.starGold),
      );

      // Star facets — geometric inner detail
      final innerStarSize = starSize * 0.5;
      canvas.drawPath(
        _starPath(positions[i], innerStarSize),
        Paint()
          ..color = _warmHighlight(AppColors.starGold, 0.4).withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.003,
      );

      // Light rays from center star (thin radiating lines)
      if (i == 2) {
        for (int r = 0; r < 8; r++) {
          final rayAngle = r * pi / 4;
          final rayLen = starSize * 2.0;
          canvas.drawLine(
            positions[i],
            Offset(
              positions[i].dx + rayLen * cos(rayAngle),
              positions[i].dy + rayLen * sin(rayAngle),
            ),
            Paint()
              ..color = AppColors.starGold.withValues(alpha: 0.06)
              ..strokeWidth = w * 0.004
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
          );
        }
      }

      // Specular on star
      canvas.drawCircle(
        positions[i].translate(-starSize * 0.15, -starSize * 0.2),
        starSize * 0.15,
        starSpecularPaint,
      );
    }
  }

  @override
  bool shouldRepaint(StarHeadbandPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  HALO (accessory index 14) — golden glow ring with depth
// ══════════════════════════════════════════════════════════════════════

class HaloPainter extends CustomPainter {
  final double twinklePhase;

  HaloPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.50, h * 0.50);
    final rect = Rect.fromCenter(center: center, width: w * 0.85, height: h * 0.70);

    // Volumetric glow — multiple soft rings with decreasing opacity
    for (int i = 3; i >= 0; i--) {
      final inflate = w * 0.03 * (i + 1);
      final alpha = 0.05 + (3 - i) * 0.02;
      final blurAmount = 6.0 + i * 4.0;
      canvas.drawOval(
        rect.inflate(inflate),
        Paint()
          ..color = AppColors.starGold.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * (0.15 + i * 0.08)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurAmount),
      );
    }

    // Main ring with metallic sweep gradient and animated golden shimmer
    final shimmerAngle = twinklePhase * 2 * pi;
    final ringGrad = ui.Gradient.sweep(
      center,
      [
        _warmHighlight(AppColors.starGold, 0.4),
        AppColors.starGold,
        _coolShadow(AppColors.starGold, 0.15),
        _darken(AppColors.starGold, 0.1),
        _warmHighlight(AppColors.starGold, 0.5), // shimmer hotspot
        _warmHighlight(AppColors.starGold, 0.25),
        AppColors.starGold,
      ],
      [0.0, 0.15, 0.35, 0.5, 0.65, 0.8, 1.0],
      TileMode.clamp,
      shimmerAngle,
      shimmerAngle + 2 * pi,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ringGrad
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.18,
    );

    // Inner bright edge
    canvas.drawOval(
      rect.deflate(h * 0.06),
      Paint()
        ..color = _warmHighlight(AppColors.starGold, 0.5).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.03,
    );

    // Outer subtle edge
    canvas.drawOval(
      rect.inflate(h * 0.06),
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.02,
    );

    // Light particles orbiting the halo
    for (int i = 0; i < 6; i++) {
      final particleAngle = shimmerAngle + i * pi / 3;
      final rx = w * 0.42;
      final ry = h * 0.35;
      final px = center.dx + rx * cos(particleAngle);
      final py = center.dy + ry * sin(particleAngle);
      final particleAlpha = (sin(particleAngle * 2 + twinklePhase * pi * 4) * 0.3 + 0.3).clamp(0.0, 0.6);
      canvas.drawCircle(
        Offset(px, py),
        w * 0.01,
        Paint()
          ..color = Colors.white.withValues(alpha: particleAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(HaloPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  HEADBAND (accessory index 15)
// ══════════════════════════════════════════════════════════════════════

class HeadbandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arcRect = Rect.fromLTWH(0, -h * 0.5, w, h * 2.0);

    // Shadow
    canvas.drawArc(
      arcRect.translate(0, h * 0.05),
      pi * 0.08,
      pi * 0.84,
      false,
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.52
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Band with fabric gradient — wider for proper head-conforming look
    final bandGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFFFF7EB3), 0.2),
        const Color(0xFFFF7EB3),
        _coolShadow(const Color(0xFFFF7EB3), 0.15),
      ],
    );
    canvas.drawArc(
      arcRect,
      pi * 0.08,
      pi * 0.84,
      false,
      Paint()
        ..shader = bandGrad.createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.48
        ..strokeCap = StrokeCap.round,
    );

    // Polka dot pattern on the band
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15);
    for (int i = 0; i < 7; i++) {
      final angle = pi * (0.12 + i * 0.11);
      final dx = w * 0.50 + w * 0.46 * cos(angle);
      final dy = h * 0.25 + h * 0.75 * sin(angle);
      canvas.drawCircle(Offset(dx, dy), w * 0.018, dotPaint);
    }

    // Satin highlight stripe
    canvas.drawArc(
      arcRect.deflate(h * 0.06),
      pi * 0.12,
      pi * 0.76,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.10,
    );

    // Fabric weave texture hint — subtle lines
    final weavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.002;
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        arcRect.deflate(h * (0.02 + i * 0.04)),
        pi * 0.10,
        pi * 0.80,
        false,
        weavePaint,
      );
    }

    // Bow accent on one side
    final bowCenter = Offset(w * 0.88, h * 0.52);
    final bowR = w * 0.06;
    // Left lobe
    final bowL = Path()
      ..moveTo(bowCenter.dx, bowCenter.dy)
      ..cubicTo(
        bowCenter.dx - bowR * 0.2, bowCenter.dy - bowR * 1.2,
        bowCenter.dx + bowR * 0.8, bowCenter.dy - bowR * 1.0,
        bowCenter.dx + bowR * 0.6, bowCenter.dy,
      )
      ..close();
    final bowGrad = RadialGradient(
      center: const Alignment(0, -0.3),
      colors: [
        _warmHighlight(const Color(0xFFFF7EB3), 0.3),
        const Color(0xFFFF7EB3),
        _darken(const Color(0xFFFF7EB3), 0.15),
      ],
    );
    canvas.drawPath(bowL, Paint()..shader = bowGrad.createShader(bowL.getBounds()));
    // Right lobe
    final bowR2 = Path()
      ..moveTo(bowCenter.dx, bowCenter.dy)
      ..cubicTo(
        bowCenter.dx - bowR * 0.2, bowCenter.dy + bowR * 1.2,
        bowCenter.dx + bowR * 0.8, bowCenter.dy + bowR * 1.0,
        bowCenter.dx + bowR * 0.6, bowCenter.dy,
      )
      ..close();
    canvas.drawPath(bowR2, Paint()..shader = bowGrad.createShader(bowR2.getBounds()));
    // Bow knot
    canvas.drawCircle(
      bowCenter,
      bowR * 0.2,
      Paint()..color = _darken(const Color(0xFFFF7EB3), 0.1),
    );

    // Fabric edge detail
    canvas.drawArc(
      arcRect.inflate(h * 0.02),
      pi * 0.08,
      pi * 0.84,
      false,
      Paint()
        ..color = _darken(const Color(0xFFFF7EB3), 0.1).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.03,
    );
  }

  @override
  bool shouldRepaint(HeadbandPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  FLOWER CROWN (accessory index 16)
// ══════════════════════════════════════════════════════════════════════

class FlowerCrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Vine with organic gradient
    final vineGrad = LinearGradient(
      colors: [
        _warmHighlight(const Color(0xFF4CBB8A), 0.1),
        const Color(0xFF4CBB8A),
        _coolShadow(const Color(0xFF4CBB8A), 0.15),
      ],
    );
    canvas.drawArc(
      Rect.fromLTWH(w * 0.02, h * 0.20, w * 0.96, h * 1.0),
      pi * 0.08,
      pi * 0.84,
      false,
      Paint()
        ..shader = vineGrad.createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.12
        ..strokeCap = StrokeCap.round,
    );

    // Leaves along vine with tiny leaves
    final leafPositions = [
      (pos: Offset(w * 0.18, h * 0.45), angle: -0.5, size: 0.7),
      (pos: Offset(w * 0.28, h * 0.35), angle: -0.3, size: 1.0),
      (pos: Offset(w * 0.42, h * 0.26), angle: -0.1, size: 0.8),
      (pos: Offset(w * 0.55, h * 0.25), angle: 0.1, size: 0.6),
      (pos: Offset(w * 0.62, h * 0.28), angle: 0.3, size: 1.0),
      (pos: Offset(w * 0.72, h * 0.35), angle: 0.4, size: 0.7),
      (pos: Offset(w * 0.82, h * 0.45), angle: 0.6, size: 0.8),
    ];
    for (final leaf in leafPositions) {
      _drawLeaf(canvas, leaf.pos, w * 0.06 * leaf.size, leaf.angle);
    }

    // Multiple flower types at different sizes for depth layering
    // Background flowers (smaller, faded — behind)
    final bgFlowers = [
      (pos: Offset(w * 0.25, h * 0.40), color: const Color(0xFFFFD0E0), r: w * 0.03),
      (pos: Offset(w * 0.45, h * 0.30), color: const Color(0xFFD0D0FF), r: w * 0.025),
      (pos: Offset(w * 0.75, h * 0.40), color: const Color(0xFFFFE0C0), r: w * 0.03),
    ];
    for (final bf in bgFlowers) {
      _drawSmallBud(canvas, bf.pos, bf.r, bf.color);
    }

    // Main foreground flowers — different types
    final flowerPositions = [
      Offset(w * 0.15, h * 0.55),
      Offset(w * 0.32, h * 0.32),
      Offset(w * 0.50, h * 0.22),
      Offset(w * 0.68, h * 0.32),
      Offset(w * 0.85, h * 0.55),
    ];
    final flowerColors = [
      const Color(0xFFFF7EB3),
      const Color(0xFFFFBF69),
      const Color(0xFFFF4D6A),
      const Color(0xFFB794F6),
      const Color(0xFFFF7EB3),
    ];
    final flowerTypes = [0, 1, 2, 1, 0]; // 0=daisy, 1=rose, 2=big rose

    final flowerShadowPaint = Paint()
      ..color = const Color(0xFF1A1040).withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final petalPaint = Paint();
    final centerDomePaint = Paint();
    final whiteAlpha08 = Colors.white.withValues(alpha: 0.8);

    for (int i = 0; i < flowerPositions.length; i++) {
      final fc = flowerPositions[i];
      final r = w * (flowerTypes[i] == 2 ? 0.06 : 0.05);

      // Shadow beneath flower
      canvas.drawCircle(
        fc.translate(0, r * 0.2),
        r * 0.8,
        flowerShadowPaint,
      );

      if (flowerTypes[i] == 0) {
        // Daisy style — many thin petals
        _drawDaisy(canvas, fc, r, flowerColors[i], petalPaint, centerDomePaint);
      } else {
        // Rose style — overlapping round petals
        _drawRose(canvas, fc, r, flowerColors[i], petalPaint, centerDomePaint, whiteAlpha08);
      }
    }

    // Petal scatter — a few loose petals falling
    final scatterPaint = Paint()..color = const Color(0xFFFF7EB3).withValues(alpha: 0.25);
    for (final sp in [
      Offset(w * 0.20, h * 0.70),
      Offset(w * 0.60, h * 0.75),
      Offset(w * 0.40, h * 0.80),
    ]) {
      final petalPath = Path()
        ..moveTo(sp.dx, sp.dy)
        ..cubicTo(sp.dx + w * 0.015, sp.dy - w * 0.015,
            sp.dx + w * 0.025, sp.dy - w * 0.005, sp.dx + w * 0.02, sp.dy + w * 0.01)
        ..cubicTo(sp.dx + w * 0.01, sp.dy + w * 0.015,
            sp.dx - w * 0.005, sp.dy + w * 0.01, sp.dx, sp.dy)
        ..close();
      canvas.drawPath(petalPath, scatterPaint);
    }
  }

  void _drawDaisy(Canvas canvas, Offset fc, double r, Color color, Paint petalPaint, Paint centerDomePaint) {
    final petalGrad = RadialGradient(
      center: const Alignment(0.0, -0.3),
      colors: [
        Colors.white.withValues(alpha: 0.9),
        color,
        _coolShadow(color, 0.15),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    for (int j = 0; j < 8; j++) {
      final angle = j * 2 * pi / 8 - pi / 2;
      final petalPath = Path()
        ..moveTo(fc.dx, fc.dy)
        ..cubicTo(
          fc.dx + r * 0.3 * cos(angle + 0.4), fc.dy + r * 0.3 * sin(angle + 0.4),
          fc.dx + r * 0.8 * cos(angle + 0.15), fc.dy + r * 0.8 * sin(angle + 0.15),
          fc.dx + r * cos(angle), fc.dy + r * sin(angle),
        )
        ..cubicTo(
          fc.dx + r * 0.8 * cos(angle - 0.15), fc.dy + r * 0.8 * sin(angle - 0.15),
          fc.dx + r * 0.3 * cos(angle - 0.4), fc.dy + r * 0.3 * sin(angle - 0.4),
          fc.dx, fc.dy,
        )
        ..close();
      canvas.drawPath(petalPath, petalPaint..shader = petalGrad.createShader(petalPath.getBounds()));
    }
    _drawFlowerCenter(canvas, fc, r, centerDomePaint);
  }

  void _drawRose(Canvas canvas, Offset fc, double r, Color color, Paint petalPaint, Paint centerDomePaint, Color whiteAlpha08) {
    final petalGrad = RadialGradient(
      center: const Alignment(0.0, -0.3),
      colors: [
        whiteAlpha08,
        color,
        _coolShadow(color, 0.15),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    for (int j = 0; j < 5; j++) {
      final angle = j * 2 * pi / 5 - pi / 2;
      final petalCenter =
          Offset(fc.dx + r * 0.6 * cos(angle), fc.dy + r * 0.6 * sin(angle));
      canvas.drawCircle(
        petalCenter,
        r * 0.42,
        petalPaint..shader = petalGrad.createShader(
            Rect.fromCircle(center: petalCenter, radius: r * 0.42)),
      );
    }
    _drawFlowerCenter(canvas, fc, r, centerDomePaint);
  }

  void _drawFlowerCenter(Canvas canvas, Offset fc, double r, Paint centerDomePaint) {
    final centerGrad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        _warmHighlight(AppColors.starGold, 0.3),
        AppColors.starGold,
      ],
    );
    canvas.drawCircle(
      fc,
      r * 0.25,
      centerDomePaint..shader = centerGrad.createShader(
          Rect.fromCircle(center: fc, radius: r * 0.25)),
    );
  }

  void _drawSmallBud(Canvas canvas, Offset pos, double r, Color color) {
    // Simple small bud — 3 overlapping circles
    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 - pi / 2;
      canvas.drawCircle(
        Offset(pos.dx + r * 0.3 * cos(angle), pos.dy + r * 0.3 * sin(angle)),
        r * 0.5,
        Paint()..color = color.withValues(alpha: 0.4),
      );
    }
    canvas.drawCircle(pos, r * 0.2, Paint()..color = AppColors.starGold.withValues(alpha: 0.4));
  }

  void _drawLeaf(Canvas canvas, Offset pos, double size, double angle) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(size * 0.3, -size * 0.4, size * 0.7, -size * 0.3, size, 0)
      ..cubicTo(size * 0.7, size * 0.3, size * 0.3, size * 0.4, 0, 0)
      ..close();

    final leafGrad = LinearGradient(
      colors: [
        _lighten(const Color(0xFF3DA07A), 0.1),
        const Color(0xFF3DA07A),
      ],
    );
    canvas.drawPath(
        leafPath, Paint()..shader = leafGrad.createShader(Rect.fromLTWH(0, -size * 0.4, size, size * 0.8)));

    // Leaf vein
    canvas.drawLine(
      Offset.zero,
      Offset(size * 0.8, 0),
      Paint()
        ..color = const Color(0xFF2D8060).withValues(alpha: 0.3)
        ..strokeWidth = size * 0.04
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(FlowerCrownPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  DEVIL HORNS (accessory index 17)
// ══════════════════════════════════════════════════════════════════════

class DevilHornsPainter extends CustomPainter {
  final double twinklePhase;

  DevilHornsPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (final isLeft in [true, false]) {
      final cx = isLeft ? w * 0.25 : w * 0.75;
      final hornBounds = Rect.fromLTWH(
          isLeft ? 0 : w * 0.5, 0, w * 0.5, h);

      final hornGrad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _warmHighlight(const Color(0xFFFF4444), 0.2), // hot tip
          const Color(0xFFFF4444),
          _coolShadow(const Color(0xFFCC2222), 0.2),
          _darken(const Color(0xFFAA1111), 0.1),
        ],
        stops: const [0.0, 0.25, 0.65, 1.0],
      );

      // Horn shape with smooth curves
      final horn = Path()
        ..moveTo(cx - w * 0.06, h * 0.95)
        ..cubicTo(
          cx - w * 0.10, h * 0.60,
          cx - w * 0.08, h * 0.25,
          cx - w * 0.02, h * 0.05,
        )
        ..cubicTo(
          cx, h * 0.02,
          cx + w * 0.02, h * 0.03,
          cx + w * 0.04, h * 0.10,
        )
        ..cubicTo(
          cx + w * 0.06, h * 0.30,
          cx + w * 0.06, h * 0.65,
          cx + w * 0.06, h * 0.95,
        )
        ..close();

      _drawShadow(canvas, horn, dy: h * 0.02, blur: 2, alpha: 0.15);
      canvas.drawPath(horn, Paint()..shader = hornGrad.createShader(hornBounds));

      // Left side highlight
      canvas.drawPath(
        horn,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008,
      );

      // Fire glow effect at tips — animated flickering
      final tipCenter = Offset(cx - w * 0.01, h * 0.05);
      final firePhase = (twinklePhase + (isLeft ? 0 : 0.5)) % 1.0;
      final fireIntensity = 0.3 + sin(firePhase * pi * 2) * 0.15;

      // Outer fire glow
      canvas.drawCircle(
        tipCenter,
        w * 0.06,
        Paint()
          ..color = const Color(0xFFFF6600).withValues(alpha: fireIntensity * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Inner fire glow
      canvas.drawCircle(
        tipCenter,
        w * 0.035,
        Paint()
          ..color = const Color(0xFFFFAA00).withValues(alpha: fireIntensity * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      // Hot center
      canvas.drawCircle(
        tipCenter,
        w * 0.015,
        Paint()
          ..color = const Color(0xFFFFDD44).withValues(alpha: fireIntensity * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );

      // Tiny flame wisps
      for (int f = 0; f < 3; f++) {
        final fAngle = -pi / 2 + (f - 1) * 0.5 + sin(firePhase * pi * 4 + f) * 0.2;
        final fLen = w * (0.02 + sin(firePhase * pi * 2 + f * 1.5).abs() * 0.015);
        canvas.drawLine(
          tipCenter,
          Offset(tipCenter.dx + fLen * cos(fAngle),
              tipCenter.dy + fLen * sin(fAngle)),
          Paint()
            ..color = const Color(0xFFFF8800).withValues(alpha: 0.3)
            ..strokeWidth = w * 0.006
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(DevilHornsPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  PIRATE HAT (accessory index 18) — weathered leather
// ══════════════════════════════════════════════════════════════════════

class PirateHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Brim shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.82), width: w * 1.0, height: h * 0.22),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Brim with leather gradient
    const brimGrad = LinearGradient(
      colors: [
        Color(0xFF2A2A2A),
        Color(0xFF1A1A1A),
        Color(0xFF151515),
      ],
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.78), width: w * 0.98, height: h * 0.28),
      Paint()..shader = brimGrad.createShader(
          Rect.fromCenter(center: Offset(w * 0.50, h * 0.78), width: w * 0.98, height: h * 0.28)),
    );

    // Main body with weathered leather texture gradient
    final hat = Path()
      ..moveTo(w * 0.05, h * 0.75)
      ..cubicTo(w * 0.08, h * 0.50, w * 0.15, h * 0.30, w * 0.25, h * 0.20)
      ..cubicTo(w * 0.38, h * 0.08, w * 0.62, h * 0.08, w * 0.75, h * 0.20)
      ..cubicTo(w * 0.85, h * 0.30, w * 0.92, h * 0.50, w * 0.95, h * 0.75)
      ..close();

    // Weathered leather: multiple gradient stops to simulate texture
    const leatherGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF3D3D3D),
        Color(0xFF353535),
        Color(0xFF2D2D2D),
        Color(0xFF333333), // wear spot
        Color(0xFF2A2A2A),
        Color(0xFF1E1E1E),
      ],
      stops: [0.0, 0.15, 0.35, 0.5, 0.7, 1.0],
    );
    canvas.drawPath(hat, Paint()..shader = leatherGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

    // Leather texture — subtle grain lines
    final grainPaint = Paint()
      ..color = const Color(0xFF3A3A3A).withValues(alpha: 0.15)
      ..strokeWidth = w * 0.003
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 8; i++) {
      final gx1 = w * (0.15 + i * 0.08);
      final gy1 = h * (0.25 + (i % 3) * 0.08);
      canvas.drawLine(
        Offset(gx1, gy1),
        Offset(gx1 + w * 0.04, gy1 + h * 0.06),
        grainPaint,
      );
    }

    // Worn edge scratches
    final scratchPaint = Paint()
      ..color = const Color(0xFF444444).withValues(alpha: 0.2)
      ..strokeWidth = w * 0.004
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.20, h * 0.45), Offset(w * 0.28, h * 0.48), scratchPaint);
    canvas.drawLine(Offset(w * 0.70, h * 0.40), Offset(w * 0.78, h * 0.42), scratchPaint);
    canvas.drawLine(Offset(w * 0.55, h * 0.35), Offset(w * 0.60, h * 0.38), scratchPaint);

    // Gold trim band
    final trimY = h * 0.70;
    final trimGrad = LinearGradient(
      colors: [
        _coolShadow(AppColors.starGold, 0.1),
        _warmHighlight(AppColors.starGold, 0.3),
        AppColors.starGold,
        _coolShadow(AppColors.starGold, 0.15),
      ],
      stops: const [0.0, 0.3, 0.6, 1.0],
    );
    canvas.drawLine(
      Offset(w * 0.08, trimY),
      Offset(w * 0.92, trimY),
      Paint()
        ..shader = trimGrad.createShader(Rect.fromLTWH(0, trimY - h * 0.02, w, h * 0.04))
        ..strokeWidth = h * 0.03
        ..strokeCap = StrokeCap.round,
    );

    // Skull with 3D gradient (improved)
    final skullCenter = Offset(w * 0.50, h * 0.42);
    const skullGrad = RadialGradient(
      center: Alignment(-0.2, -0.3),
      colors: [Colors.white, Color(0xFFE0E0E0), Color(0xFFCCCCCC)],
    );
    // Skull shadow
    canvas.drawCircle(
      skullCenter.translate(0, w * 0.01),
      w * 0.085,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      skullCenter,
      w * 0.08,
      Paint()..shader = skullGrad.createShader(
          Rect.fromCircle(center: skullCenter, radius: w * 0.08)),
    );
    // Skull jaw
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.50, h * 0.47), width: w * 0.10, height: w * 0.05),
      Paint()..color = const Color(0xFFE8E8E8),
    );

    // Skull eyes (tiny dark voids with red glow)
    for (final eyeX in [w * 0.47, w * 0.53]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(eyeX, h * 0.41), width: w * 0.025, height: w * 0.03),
        Paint()..color = const Color(0xFF1A1A1A),
      );
      // Subtle red eye glow
      canvas.drawCircle(
        Offset(eyeX, h * 0.41),
        w * 0.008,
        Paint()
          ..color = const Color(0xFFFF4444).withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }

    // Cross bones with 3D feel
    final bonePaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = w * 0.020
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.38, h * 0.55), Offset(w * 0.62, h * 0.65), bonePaint);
    canvas.drawLine(Offset(w * 0.62, h * 0.55), Offset(w * 0.38, h * 0.65), bonePaint);
    // Bone highlight
    final boneHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.39, h * 0.555), Offset(w * 0.61, h * 0.645), boneHighlight);
    // Bone joint dots
    final jointPaint = Paint()..color = const Color(0xFFE8E8E8);
    for (final pos in [
      Offset(w * 0.37, h * 0.54), Offset(w * 0.63, h * 0.54),
      Offset(w * 0.37, h * 0.66), Offset(w * 0.63, h * 0.66),
    ]) {
      canvas.drawCircle(pos, w * 0.012, jointPaint);
    }
  }

  @override
  bool shouldRepaint(PirateHatPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  ANTENNAE (accessory index 19)
// ══════════════════════════════════════════════════════════════════════

class AntennaePainter extends CustomPainter {
  final double swayValue;
  final double twinklePhase;

  AntennaePainter({this.swayValue = 0.5, this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stalkGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFF00E68A), 0.2),
        const Color(0xFF00E68A),
        _coolShadow(const Color(0xFF00E68A), 0.2),
      ],
    );

    final stalkPaint = Paint()
      ..shader = stalkGrad.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;

    // Bobbing animation offset
    final bobOffset = sin(twinklePhase * 2 * pi) * h * 0.02;

    // Stalks with organic bezier curves (animated bob)
    final leftPath = Path()
      ..moveTo(w * 0.28, h)
      ..cubicTo(w * 0.22, h * 0.70, w * 0.12, h * 0.40, w * 0.15, h * 0.12 + bobOffset);
    canvas.drawPath(leftPath, stalkPaint);

    final rightPath = Path()
      ..moveTo(w * 0.72, h)
      ..cubicTo(w * 0.78, h * 0.70, w * 0.88, h * 0.40, w * 0.85, h * 0.12 - bobOffset);
    canvas.drawPath(rightPath, stalkPaint);

    // Ball tips with 3D radial gradient + specular + glow
    final tipPositions = [
      Offset(w * 0.15, h * 0.10 + bobOffset),
      Offset(w * 0.85, h * 0.10 - bobOffset),
    ];
    final ballR = w * 0.10;
    final ballShadowPaint = Paint()
      ..color = const Color(0xFF1A1040).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final ballGrad = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      colors: [
        _warmHighlight(const Color(0xFF00E68A), 0.45),
        _lighten(const Color(0xFF00E68A), 0.1),
        const Color(0xFF00E68A),
        _coolShadow(const Color(0xFF00E68A), 0.25),
      ],
      stops: const [0.0, 0.25, 0.6, 1.0],
    );
    final ballFillPaint = Paint();
    final softSpecularPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final sharpSpecularPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);

    for (int idx = 0; idx < tipPositions.length; idx++) {
      final cx = tipPositions[idx];

      // Glowing orb effect at tips
      final glowPhase = (twinklePhase + idx * 0.5) % 1.0;
      final glowIntensity = 0.15 + sin(glowPhase * 2 * pi) * 0.1;
      canvas.drawCircle(
        cx,
        ballR * 1.5,
        Paint()
          ..color = const Color(0xFF00E68A).withValues(alpha: glowIntensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      // Shadow beneath ball
      canvas.drawCircle(
        cx.translate(0, ballR * 0.3),
        ballR * 0.8,
        ballShadowPaint,
      );

      canvas.drawCircle(
        cx,
        ballR,
        ballFillPaint..shader = ballGrad.createShader(Rect.fromCircle(center: cx, radius: ballR)),
      );

      // Specular highlights (large soft + small sharp)
      canvas.drawOval(
        Rect.fromCenter(
          center: cx.translate(-ballR * 0.2, -ballR * 0.2),
          width: ballR * 0.5,
          height: ballR * 0.3,
        ),
        softSpecularPaint,
      );
      canvas.drawCircle(
        cx.translate(-ballR * 0.15, -ballR * 0.2),
        ballR * 0.1,
        sharpSpecularPaint,
      );
    }
  }

  @override
  bool shouldRepaint(AntennaePainter old) =>
      (old.swayValue * 30).round() != (swayValue * 30).round() ||
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  PROPELLER HAT (accessory index 20)
// ══════════════════════════════════════════════════════════════════════

class PropellerHatPainter extends CustomPainter {
  final double twinklePhase;

  PropellerHatPainter({this.twinklePhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow beneath hat
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.95), width: w * 0.95, height: h * 0.08),
      Paint()
        ..color = const Color(0xFF1A1040).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Beanie with fabric gradient
    final beanie = Path()
      ..moveTo(w * 0.05, h * 0.90)
      ..cubicTo(w * 0.05, h * 0.50, w * 0.25, h * 0.32, w * 0.50, h * 0.30)
      ..cubicTo(w * 0.75, h * 0.32, w * 0.95, h * 0.50, w * 0.95, h * 0.90)
      ..close();
    final beanieGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _warmHighlight(const Color(0xFF4A90D9), 0.15),
        const Color(0xFF4A90D9),
        _coolShadow(const Color(0xFF4A90D9), 0.15),
      ],
    );
    canvas.drawPath(beanie, Paint()..shader = beanieGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

    // Red brim band with gradient
    final brimGrad = LinearGradient(
      colors: [
        _warmHighlight(const Color(0xFFFF4444), 0.1),
        const Color(0xFFFF4444),
        _coolShadow(const Color(0xFFFF4444), 0.15),
      ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.02, h * 0.80, w * 0.96, h * 0.14),
        Radius.circular(h * 0.07),
      ),
      Paint()..shader = brimGrad.createShader(
          Rect.fromLTWH(w * 0.02, h * 0.80, w * 0.96, h * 0.14)),
    );

    // Propeller post (metallic dome)
    final postCenter = Offset(w * 0.50, h * 0.30);
    final postR = w * 0.05;
    final postGrad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        _warmHighlight(AppColors.starGold, 0.4),
        AppColors.starGold,
        _darken(AppColors.starGold, 0.15),
      ],
    );
    canvas.drawCircle(
      postCenter,
      postR,
      Paint()..shader = postGrad.createShader(Rect.fromCircle(center: postCenter, radius: postR)),
    );

    // Propeller blades with spinning animation effect and metallic sheen
    final spinAngle = twinklePhase * 2 * pi; // Full rotation per cycle
    canvas.save();
    canvas.translate(postCenter.dx, postCenter.dy);
    canvas.rotate(spinAngle);
    canvas.translate(-postCenter.dx, -postCenter.dy);

    final bladeColors = [
      _warmHighlight(const Color(0xFFFF4444), 0.2),
      const Color(0xFFFF4444),
      _coolShadow(const Color(0xFFCC2222), 0.2),
    ];
    final bladePaint = Paint();
    final bladeRect = Rect.fromLTWH(0, 0, w, h);

    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 - pi / 6;
      final bladeGrad = LinearGradient(
        begin: Alignment.center,
        end: Alignment(cos(angle), sin(angle)),
        colors: bladeColors,
      );
      final path = Path()
        ..moveTo(postCenter.dx, postCenter.dy)
        ..cubicTo(
          postCenter.dx + w * 0.10 * cos(angle + 0.4),
          postCenter.dy + h * 0.08 * sin(angle + 0.4),
          postCenter.dx + w * 0.18 * cos(angle + 0.2),
          postCenter.dy + h * 0.15 * sin(angle + 0.2),
          postCenter.dx + w * 0.22 * cos(angle),
          postCenter.dy + h * 0.18 * sin(angle),
        )
        ..cubicTo(
          postCenter.dx + w * 0.18 * cos(angle - 0.2),
          postCenter.dy + h * 0.15 * sin(angle - 0.2),
          postCenter.dx + w * 0.10 * cos(angle - 0.4),
          postCenter.dy + h * 0.08 * sin(angle - 0.4),
          postCenter.dx,
          postCenter.dy,
        )
        ..close();
      canvas.drawPath(path, bladePaint..shader = bladeGrad.createShader(bladeRect));

      // Metallic sheen on each blade
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }
    canvas.restore();

    // Post specular on top
    canvas.drawCircle(
      postCenter.translate(-postR * 0.2, -postR * 0.2),
      postR * 0.2,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(PropellerHatPainter old) =>
      (old.twinklePhase * 30).round() != (twinklePhase * 30).round();
}

// ══════════════════════════════════════════════════════════════════════
//  NINJA MASK (accessory index 21) — fabric with depth
// ══════════════════════════════════════════════════════════════════════

class NinjaMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Mask with dark fabric gradient
    const maskGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF2E2E42),
        Color(0xFF1A1A2E),
        Color(0xFF0E0E1E),
        Color(0xFF1A1A2E), // bottom catch light
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    );
    final maskRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.10, w, h * 0.70),
      Radius.circular(h * 0.20),
    );
    canvas.drawRRect(maskRect,
        Paint()..shader = maskGrad.createShader(Rect.fromLTWH(0, h * 0.10, w, h * 0.70)));

    // Fabric weave texture — subtle cross-hatch
    final weavePaint = Paint()
      ..color = const Color(0xFF252540).withValues(alpha: 0.15)
      ..strokeWidth = w * 0.003
      ..strokeCap = StrokeCap.round;
    for (double y = h * 0.15; y < h * 0.75; y += h * 0.04) {
      canvas.drawLine(Offset(w * 0.05, y), Offset(w * 0.95, y), weavePaint);
    }
    for (double x = w * 0.08; x < w * 0.92; x += w * 0.04) {
      canvas.drawLine(Offset(x, h * 0.15), Offset(x, h * 0.75), weavePaint);
    }

    // Fabric wrinkle lines (more detailed)
    final wrinklePaint = Paint()
      ..color = const Color(0xFF252540).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.005
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.15, h * 0.25), Offset(w * 0.22, h * 0.65), wrinklePaint);
    canvas.drawLine(Offset(w * 0.78, h * 0.25), Offset(w * 0.85, h * 0.65), wrinklePaint);
    // Additional wrinkles near eye slits
    canvas.drawLine(Offset(w * 0.38, h * 0.32), Offset(w * 0.35, h * 0.55),
        Paint()
          ..color = const Color(0xFF252540).withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.004
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(w * 0.62, h * 0.32), Offset(w * 0.65, h * 0.55),
        Paint()
          ..color = const Color(0xFF252540).withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.004
          ..strokeCap = StrokeCap.round);

    // Knot tails on right side with fabric detail
    const knotGrad = LinearGradient(
      colors: [Color(0xFF1E1E30), Color(0xFF141425)],
    );
    final knotPaint = Paint()
      ..shader = knotGrad.createShader(Rect.fromLTWH(w * 0.92, h * 0.30, w * 0.15, h * 0.30))
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.95, h * 0.38), Offset(w * 1.06, h * 0.52), knotPaint);
    canvas.drawLine(Offset(w * 0.95, h * 0.48), Offset(w * 1.06, h * 0.32), knotPaint);
    // Tail edge highlight
    canvas.drawLine(
      Offset(w * 0.96, h * 0.39),
      Offset(w * 1.05, h * 0.51),
      Paint()
        ..color = const Color(0xFF353550).withValues(alpha: 0.3)
        ..strokeWidth = h * 0.02
        ..strokeCap = StrokeCap.round,
    );

    // Eye slits with depth and detail
    for (final cx in [w * 0.30, w * 0.70]) {
      // Ambient occlusion around slit
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, h * 0.45), width: w * 0.26, height: h * 0.30),
          Radius.circular(h * 0.10),
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Eye slit shape — more angular/menacing
      final slitPath = Path()
        ..moveTo(cx - w * 0.10, h * 0.45)
        ..cubicTo(cx - w * 0.08, h * 0.36, cx + w * 0.08, h * 0.36, cx + w * 0.10, h * 0.42)
        ..cubicTo(cx + w * 0.08, h * 0.52, cx - w * 0.08, h * 0.52, cx - w * 0.10, h * 0.45)
        ..close();

      // Inner slit cutout (white to show eyes through)
      final slitGrad = RadialGradient(
        center: const Alignment(0.0, -0.1),
        colors: [
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.85),
        ],
      );
      canvas.drawPath(
        slitPath,
        Paint()..shader = slitGrad.createShader(slitPath.getBounds()),
      );

      // Slit edge shadow for depth
      canvas.drawPath(
        slitPath,
        Paint()
          ..color = const Color(0xFF0A0A15).withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.006,
      );
    }
  }

  @override
  bool shouldRepaint(NinjaMaskPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  ACCESSORY DISPATCHER
// ══════════════════════════════════════════════════════════════════════

/// Returns the appropriate accessory painter for the given index.
/// Returns null for index 0 (None) or 1 (legacy Glasses — handled by GlassesPainter).
/// [swayValue] (0.0-1.0) drives specular highlight shift on metallic surfaces.
/// [twinklePhase] (0.0-1.0) drives animated sparkle/twinkle effects.
CustomPainter? accessoryPainter(int index,
    {double swayValue = 0.5, double twinklePhase = 0.0}) {
  switch (index) {
    case 2:
      return CrownPainter(
          color: AppColors.starGold, jewels: true, swayValue: swayValue);
    case 3:
      return FlowerPainter();
    case 4:
      return BowPainter();
    case 5:
      return CapPainter();
    case 6:
      return WizardHatPainter(twinklePhase: twinklePhase);
    case 7:
      return WingsPainter(swayValue: swayValue);
    case 8:
      return RoyalCrownPainter(swayValue: swayValue);
    case 9:
      return TiaraPainter(twinklePhase: twinklePhase);
    case 10:
      return BunnyEarsPainter();
    case 11:
      return CatEarsPainter();
    case 12:
      return UnicornHornPainter(twinklePhase: twinklePhase);
    case 13:
      return StarHeadbandPainter();
    case 14:
      return HaloPainter(twinklePhase: twinklePhase);
    case 15:
      return HeadbandPainter();
    case 16:
      return FlowerCrownPainter();
    case 17:
      return DevilHornsPainter(twinklePhase: twinklePhase);
    case 18:
      return PirateHatPainter();
    case 19:
      return AntennaePainter(swayValue: swayValue, twinklePhase: twinklePhase);
    case 20:
      return PropellerHatPainter(twinklePhase: twinklePhase);
    case 21:
      return NinjaMaskPainter();
    default:
      return null;
  }
}

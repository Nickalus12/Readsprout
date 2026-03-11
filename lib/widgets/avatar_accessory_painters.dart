import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

    // Embossed rim along top edge
    final rimHighlight = Paint()
      ..color = _warmHighlight(color, 0.5).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(crownPath, rimHighlight);

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

    // 6 petals with individual petal-shaped bezier curves and gradient
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

      // Petal gradient: white center → pink edge
      final petalGrad = RadialGradient(
        center: Alignment(cos(angle) * -0.5, sin(angle) * -0.5),
        radius: 1.2,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          const Color(0xFFFFD0E0),
          const Color(0xFFFF7EB3),
          _coolShadow(const Color(0xFFFF7EB3), 0.2),
        ],
        stops: const [0.0, 0.25, 0.6, 1.0],
      );
      final petalBounds = petalPath.getBounds();
      canvas.drawPath(
          petalPath, Paint()..shader = petalGrad.createShader(petalBounds));

      // Petal vein line
      canvas.drawLine(
        Offset(c.dx + petalR * 0.1 * cos(angle),
            c.dy + petalR * 0.1 * sin(angle)),
        Offset(c.dx + petalR * 0.85 * cos(angle),
            c.dy + petalR * 0.85 * sin(angle)),
        Paint()
          ..color = const Color(0xFFFF7EB3).withValues(alpha: 0.25)
          ..strokeWidth = w * 0.008
          ..strokeCap = StrokeCap.round,
      );
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
    for (int i = 0; i < 8; i++) {
      final a = i * 2 * pi / 8 + 0.2;
      final dotCenter = Offset(
          c.dx + petalR * 0.18 * cos(a), c.dy + petalR * 0.18 * sin(a));
      canvas.drawCircle(dotCenter, petalR * 0.05, dotPaint);
      canvas.drawCircle(
        dotCenter.translate(-petalR * 0.015, -petalR * 0.015),
        petalR * 0.02,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Ribbon tails hanging down with gravity curve
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

    // Left tail
    final leftTail = Path()
      ..moveTo(w * 0.44, h * 0.52)
      ..cubicTo(w * 0.38, h * 0.65, w * 0.32, h * 0.82, w * 0.26, h * 0.98)
      ..lineTo(w * 0.32, h * 0.85)
      ..cubicTo(w * 0.37, h * 0.72, w * 0.41, h * 0.62, w * 0.47, h * 0.52)
      ..close();
    canvas.drawPath(leftTail, tailPaint);

    // Right tail
    final rightTail = Path()
      ..moveTo(w * 0.56, h * 0.52)
      ..cubicTo(w * 0.62, h * 0.65, w * 0.68, h * 0.82, w * 0.74, h * 0.98)
      ..lineTo(w * 0.68, h * 0.85)
      ..cubicTo(w * 0.63, h * 0.72, w * 0.59, h * 0.62, w * 0.53, h * 0.52)
      ..close();
    canvas.drawPath(rightTail, tailPaint);

    // Center knot — 3D dome shape
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
    // Knot fold line
    canvas.drawLine(
      knotCenter.translate(0, -knotR * 0.5),
      knotCenter.translate(0, knotR * 0.5),
      Paint()
        ..color = _darken(const Color(0xFFE0559D), 0.15).withValues(alpha: 0.3)
        ..strokeWidth = knotR * 0.15
        ..strokeCap = StrokeCap.round,
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

    // Fabric fold highlight
    canvas.drawPath(
      lobe,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Fabric panel seam lines
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
    }

    // Fabric weave texture — subtle horizontal lines
    final weavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = w * 0.003;
    for (double y = h * 0.2; y < h * 0.8; y += h * 0.06) {
      canvas.drawLine(Offset(w * 0.08, y), Offset(w * 0.92, y), weavePaint);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Fabric fold shadows (diagonal creases)
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

    // Brim with depth
    final brimGrad = RadialGradient(
      colors: [
        _lighten(AppColors.violet, 0.05),
        AppColors.violet,
        _darken(AppColors.violet, 0.15),
      ],
    );
    final brimRect = Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.85), width: w, height: h * 0.30);
    canvas.drawOval(brimRect, Paint()..shader = brimGrad.createShader(brimRect));

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
    for (int i = 0; i < dotPositions.length; i++) {
      final phase = (twinklePhase + i * 0.14) % 1.0;
      final alpha = (sin(phase * 2 * pi) * 0.35 + 0.45).clamp(0.1, 0.8);
      final dotR = w * 0.010 + w * 0.005 * sin(phase * 2 * pi);
      canvas.drawCircle(
        dotPositions[i],
        dotR,
        Paint()..color = Colors.white.withValues(alpha: alpha),
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
      // Outer edge curving down
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

    // Iridescent gradient — hue shifts based on position
    final iridescentGrad = LinearGradient(
      begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      colors: [
        AppColors.electricBlue.withValues(alpha: 0.10),
        AppColors.electricBlue.withValues(alpha: 0.25),
        AppColors.violet.withValues(alpha: 0.20),
        AppColors.magenta.withValues(alpha: 0.15),
        AppColors.electricBlue.withValues(alpha: 0.30),
        AppColors.cyan.withValues(alpha: 0.18),
      ],
      stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    );

    // Use saveLayer for proper translucent compositing
    final wingBounds = wingPath.getBounds();
    canvas.saveLayer(wingBounds, Paint());
    canvas.drawPath(
        wingPath, Paint()..shader = iridescentGrad.createShader(wingBounds));

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Embossed border along top
    canvas.drawPath(
      crownPath,
      Paint()
        ..color = _warmHighlight(AppColors.starGold, 0.45).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.010,
    );

    // Engraved decorative band
    final bandY = h * 0.78;
    final bandPath = Path()
      ..moveTo(w * 0.03, bandY)
      ..cubicTo(w * 0.25, bandY - h * 0.02, w * 0.75, bandY - h * 0.02, w * 0.97, bandY);
    canvas.drawPath(
      bandPath,
      Paint()
        ..color = _darken(AppColors.starGold, 0.2).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.035
        ..strokeCap = StrokeCap.round,
    );
    // Band highlight
    canvas.drawPath(
      bandPath.shift(Offset(0, -h * 0.01)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.01,
    );

    // Cross/orb on top
    final orbCenter = Offset(w * 0.50, h * 0.06);
    _drawJewel(canvas, orbCenter, w * 0.04, AppColors.starGold);

    final crossPaint = Paint()
      ..shader = _metallicPaint(bounds, AppColors.starGold).shader
      ..strokeWidth = w * 0.018
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.50, h * 0.01), Offset(w * 0.50, h * 0.12), crossPaint);
    canvas.drawLine(Offset(w * 0.44, h * 0.05), Offset(w * 0.56, h * 0.05), crossPaint);

    // Multiple jewels with refraction
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

    // Band with silver-pink gradient
    final bandGrad = LinearGradient(
      colors: [
        _warmHighlight(const Color(0xFFFFB6C1), 0.25),
        const Color(0xFFFFB6C1),
        _coolShadow(const Color(0xFFFFB6C1), 0.1),
      ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.55, w, h * 0.35),
        Radius.circular(h * 0.15),
      ),
      Paint()..shader = bandGrad.createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.35)),
    );

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

    // Jewels
    _drawJewel(canvas, Offset(w * 0.40, h * 0.17), w * 0.035, const Color(0xFFE0559D));
    _drawJewel(canvas, Offset(w * 0.60, h * 0.17), w * 0.035, const Color(0xFFE0559D));
    _drawJewel(canvas, Offset(w * 0.50, h * 0.48), w * 0.04, AppColors.starGold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

      // Outer ear with bezier curves
      final outer = Path()
        ..moveTo(cx - mx * w * 0.07, h * 0.95)
        ..cubicTo(
          cx - mx * w * 0.14, h * 0.60,
          cx - mx * w * 0.10, h * 0.20,
          cx - mx * w * 0.04, h * 0.05,
        )
        ..cubicTo(
          cx, h * 0.00,
          cx + mx * w * 0.02, h * 0.02,
          cx + mx * w * 0.07, h * 0.15,
        )
        ..cubicTo(
          cx + mx * w * 0.10, h * 0.50,
          cx + mx * w * 0.08, h * 0.75,
          cx + mx * w * 0.07, h * 0.95,
        )
        ..close();
      canvas.drawPath(outer, Paint()..shader = outerGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

      // Inner ear
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

      // Fur edge softness
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

      // Outer with curved edges (no straight lines)
      final outer = Path()
        ..moveTo(baseL, h * 0.88)
        ..cubicTo(baseL - w * 0.02, h * 0.55, tipX - w * 0.03, h * 0.15, tipX, h * 0.05)
        ..cubicTo(tipX + w * 0.03, h * 0.15, baseR + w * 0.02, h * 0.55, baseR, h * 0.75)
        ..cubicTo(baseR - w * 0.02, h * 0.82, baseL + w * 0.05, h * 0.90, baseL, h * 0.88)
        ..close();
      canvas.drawPath(outer, Paint()..shader = outerGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

      // Inner pink
      final innerPath = Path()
        ..moveTo(baseL + w * 0.04, h * 0.78)
        ..cubicTo(baseL + w * 0.02, h * 0.52, tipX, h * 0.22, tipX + w * 0.01, h * 0.18)
        ..cubicTo(tipX + w * 0.02, h * 0.22, baseR - w * 0.02, h * 0.52, baseR - w * 0.04, h * 0.68)
        ..cubicTo(baseR - w * 0.05, h * 0.74, baseL + w * 0.06, h * 0.80, baseL + w * 0.04, h * 0.78)
        ..close();
      final innerBounds = innerPath.getBounds();
      canvas.drawPath(innerPath, Paint()..shader = innerGrad.createShader(innerBounds));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  UNICORN HORN (accessory index 12) — spiral rainbow with ridges
// ══════════════════════════════════════════════════════════════════════

class UnicornHornPainter extends CustomPainter {
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

    // Magical glow behind horn
    canvas.drawPath(
      hornPath,
      Paint()
        ..color = const Color(0xFFE0C3FC).withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Rainbow gradient that wraps around the spiral
    // Using a sweep gradient centered on the horn to create wrap effect
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

    // Spiral ridge grooves — these wrap around the horn
    for (int i = 1; i < 7; i++) {
      final y = h * (0.08 + i * 0.12);
      final hornWidthAtY = w * 0.20 * (1 - (y / h) * 0.6);
      final ridgeOffset = (i.isEven ? 1 : -1) * hornWidthAtY * 0.1;

      // Ridge shadow (cool-shifted)
      canvas.drawLine(
        Offset(w * 0.50 - hornWidthAtY + ridgeOffset, y + h * 0.01),
        Offset(w * 0.50 + hornWidthAtY + ridgeOffset, y + h * 0.03),
        Paint()
          ..color = const Color(0xFF8060B0).withValues(alpha: 0.2)
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );

      // Ridge highlight (warm-shifted)
      canvas.drawLine(
        Offset(w * 0.50 - hornWidthAtY + ridgeOffset, y - h * 0.005),
        Offset(w * 0.50 + hornWidthAtY + ridgeOffset, y + h * 0.015),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = w * 0.018
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tip sparkle
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.02),
      w * 0.03,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  STAR HEADBAND (accessory index 13)
// ══════════════════════════════════════════════════════════════════════

class StarHeadbandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Metallic gold band
    final bandGrad = LinearGradient(
      colors: [
        _darken(AppColors.starGold, 0.1),
        _warmHighlight(AppColors.starGold, 0.25),
        AppColors.starGold,
        _coolShadow(AppColors.starGold, 0.15),
      ],
      stops: const [0.0, 0.3, 0.6, 1.0],
    );
    final bandPaint = Paint()
      ..shader = bandGrad.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.22
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromLTWH(w * 0.02, -h * 0.2, w * 0.96, h * 1.4),
      pi * 0.05,
      pi * 0.90,
      false,
      bandPaint,
    );

    // Stars with glow at each position
    final positions = [
      Offset(w * 0.15, h * 0.45),
      Offset(w * 0.35, h * 0.20),
      Offset(w * 0.50, h * 0.12),
      Offset(w * 0.65, h * 0.20),
      Offset(w * 0.85, h * 0.45),
    ];

    for (int i = 0; i < positions.length; i++) {
      final starSize = (i == 2) ? w * 0.08 : w * 0.055;

      // Glow
      canvas.drawCircle(
        positions[i],
        starSize * 1.8,
        Paint()
          ..color = AppColors.starGold.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Star with metallic gradient
      final starBounds = Rect.fromCircle(center: positions[i], radius: starSize);
      canvas.drawPath(
        _starPath(positions[i], starSize),
        _metallicPaint(starBounds, AppColors.starGold),
      );

      // Specular on star
      canvas.drawCircle(
        positions[i].translate(-starSize * 0.15, -starSize * 0.2),
        starSize * 0.15,
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  HALO (accessory index 14) — golden glow ring with depth
// ══════════════════════════════════════════════════════════════════════

class HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.50, h * 0.50);
    final rect = Rect.fromCenter(center: center, width: w * 0.85, height: h * 0.70);

    // Outer ethereal glow (wide, soft)
    canvas.drawOval(
      rect.inflate(w * 0.05),
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.55
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Main ring with metallic sweep gradient
    final ringGrad = ui.Gradient.sweep(
      center,
      [
        _warmHighlight(AppColors.starGold, 0.4),
        AppColors.starGold,
        _coolShadow(AppColors.starGold, 0.15),
        _darken(AppColors.starGold, 0.1),
        _warmHighlight(AppColors.starGold, 0.25),
        AppColors.starGold,
      ],
      [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Band with fabric gradient
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Leaves along vine
    final leafPositions = [
      (pos: Offset(w * 0.22, h * 0.40), angle: -0.4),
      (pos: Offset(w * 0.38, h * 0.28), angle: -0.2),
      (pos: Offset(w * 0.55, h * 0.25), angle: 0.1),
      (pos: Offset(w * 0.62, h * 0.28), angle: 0.3),
      (pos: Offset(w * 0.78, h * 0.40), angle: 0.5),
    ];
    for (final leaf in leafPositions) {
      _drawLeaf(canvas, leaf.pos, w * 0.06, leaf.angle);
    }

    // Flowers with 3D petals
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

    for (int i = 0; i < flowerPositions.length; i++) {
      final fc = flowerPositions[i];
      final r = w * 0.05;

      // Shadow beneath flower
      canvas.drawCircle(
        fc.translate(0, r * 0.2),
        r * 0.8,
        Paint()
          ..color = const Color(0xFF1A1040).withValues(alpha: 0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );

      // Petals with gradient
      final petalGrad = RadialGradient(
        center: const Alignment(0.0, -0.3),
        colors: [
          Colors.white.withValues(alpha: 0.8),
          flowerColors[i],
          _coolShadow(flowerColors[i], 0.15),
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
          Paint()
            ..shader = petalGrad.createShader(
                Rect.fromCircle(center: petalCenter, radius: r * 0.42)),
        );
      }

      // Gold center dome
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
        Paint()
          ..shader =
              centerGrad.createShader(Rect.fromCircle(center: fc, radius: r * 0.25)),
      );
    }
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  DEVIL HORNS (accessory index 17)
// ══════════════════════════════════════════════════════════════════════

class DevilHornsPainter extends CustomPainter {
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

      // Hot tip glow
      final tipCenter = Offset(cx - w * 0.01, h * 0.05);
      canvas.drawCircle(
        tipCenter,
        w * 0.04,
        Paint()
          ..color = const Color(0xFFFF8888).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Worn edge scratches
    final scratchPaint = Paint()
      ..color = const Color(0xFF444444).withValues(alpha: 0.2)
      ..strokeWidth = w * 0.004
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.20, h * 0.45), Offset(w * 0.28, h * 0.48), scratchPaint);
    canvas.drawLine(Offset(w * 0.70, h * 0.40), Offset(w * 0.78, h * 0.42), scratchPaint);

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

    // Skull with 3D gradient
    final skullCenter = Offset(w * 0.50, h * 0.44);
    const skullGrad = RadialGradient(
      center: Alignment(-0.2, -0.3),
      colors: [Colors.white, Color(0xFFE0E0E0), Color(0xFFCCCCCC)],
    );
    canvas.drawCircle(
      skullCenter,
      w * 0.08,
      Paint()..shader = skullGrad.createShader(
          Rect.fromCircle(center: skullCenter, radius: w * 0.08)),
    );

    // Skull eyes (tiny dark voids)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.47, h * 0.42), width: w * 0.025, height: w * 0.03),
      Paint()..color = const Color(0xFF1A1A1A),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.53, h * 0.42), width: w * 0.025, height: w * 0.03),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Cross bones with 3D feel
    final bonePaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = w * 0.020
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.38, h * 0.55), Offset(w * 0.62, h * 0.65), bonePaint);
    canvas.drawLine(Offset(w * 0.62, h * 0.55), Offset(w * 0.38, h * 0.65), bonePaint);
    // Bone joint dots
    for (final pos in [
      Offset(w * 0.37, h * 0.54), Offset(w * 0.63, h * 0.54),
      Offset(w * 0.37, h * 0.66), Offset(w * 0.63, h * 0.66),
    ]) {
      canvas.drawCircle(pos, w * 0.012, Paint()..color = const Color(0xFFE8E8E8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  ANTENNAE (accessory index 19)
// ══════════════════════════════════════════════════════════════════════

class AntennaePainter extends CustomPainter {
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

    // Stalks with organic bezier curves
    final leftPath = Path()
      ..moveTo(w * 0.28, h)
      ..cubicTo(w * 0.22, h * 0.70, w * 0.12, h * 0.40, w * 0.15, h * 0.12);
    canvas.drawPath(leftPath, stalkPaint);

    final rightPath = Path()
      ..moveTo(w * 0.72, h)
      ..cubicTo(w * 0.78, h * 0.70, w * 0.88, h * 0.40, w * 0.85, h * 0.12);
    canvas.drawPath(rightPath, stalkPaint);

    // Ball tips with 3D radial gradient + specular
    for (final cx in [Offset(w * 0.15, h * 0.10), Offset(w * 0.85, h * 0.10)]) {
      final ballR = w * 0.10;

      // Shadow beneath ball
      canvas.drawCircle(
        cx.translate(0, ballR * 0.3),
        ballR * 0.8,
        Paint()
          ..color = const Color(0xFF1A1040).withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

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
      canvas.drawCircle(
        cx,
        ballR,
        Paint()..shader = ballGrad.createShader(Rect.fromCircle(center: cx, radius: ballR)),
      );

      // Specular highlights (large soft + small sharp)
      canvas.drawOval(
        Rect.fromCenter(
          center: cx.translate(-ballR * 0.2, -ballR * 0.2),
          width: ballR * 0.5,
          height: ballR * 0.3,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
      canvas.drawCircle(
        cx.translate(-ballR * 0.15, -ballR * 0.2),
        ballR * 0.1,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  PROPELLER HAT (accessory index 20)
// ══════════════════════════════════════════════════════════════════════

class PropellerHatPainter extends CustomPainter {
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

    // Propeller blades with gradient and smooth bezier shape
    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 - pi / 6;
      final bladeGrad = LinearGradient(
        begin: Alignment.center,
        end: Alignment(cos(angle), sin(angle)),
        colors: [
          _warmHighlight(const Color(0xFFFF4444), 0.15),
          const Color(0xFFFF4444),
          _coolShadow(const Color(0xFFCC2222), 0.2),
        ],
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
      canvas.drawPath(path, Paint()..shader = bladeGrad.createShader(Rect.fromLTWH(0, 0, w, h)));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // Fabric wrinkle lines
    final wrinklePaint = Paint()
      ..color = const Color(0xFF252540).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.005
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.15, h * 0.25), Offset(w * 0.22, h * 0.65), wrinklePaint);
    canvas.drawLine(Offset(w * 0.78, h * 0.25), Offset(w * 0.85, h * 0.65), wrinklePaint);

    // Knot tails on right side
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

    // Eye slits with depth
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

      // Inner slit cutout (white to show eyes through)
      final slitGrad = RadialGradient(
        center: const Alignment(0.0, -0.1),
        colors: [
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.85),
        ],
      );
      final slitRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, h * 0.45), width: w * 0.22, height: h * 0.25),
        Radius.circular(h * 0.08),
      );
      canvas.drawRRect(
        slitRect,
        Paint()
          ..shader = slitGrad.createShader(
              Rect.fromCenter(center: Offset(cx, h * 0.45), width: w * 0.22, height: h * 0.25)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      return WingsPainter();
    case 8:
      return RoyalCrownPainter(swayValue: swayValue);
    case 9:
      return TiaraPainter();
    case 10:
      return BunnyEarsPainter();
    case 11:
      return CatEarsPainter();
    case 12:
      return UnicornHornPainter();
    case 13:
      return StarHeadbandPainter();
    case 14:
      return HaloPainter();
    case 15:
      return HeadbandPainter();
    case 16:
      return FlowerCrownPainter();
    case 17:
      return DevilHornsPainter();
    case 18:
      return PirateHatPainter();
    case 19:
      return AntennaePainter();
    case 20:
      return PropellerHatPainter();
    case 21:
      return NinjaMaskPainter();
    default:
      return null;
  }
}

import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
//  HAND POSE — gesture states for hand rendering
// ═══════════════════════════════════════════════════════════════════════

/// Hand gesture poses used by [HandPainter].
enum HandPose {
  /// Relaxed fingers, slight inward curl.
  rest,

  /// Spread fingers (5 distinct finger shapes).
  open,

  /// Index finger extended, others curled.
  point,

  /// Fist with thumb up.
  thumbsUp,

  /// Open hand, slightly spread (greeting).
  wave,
}

// ═══════════════════════════════════════════════════════════════════════
//  CLIP NAME → HAND POSE MAPPING
// ═══════════════════════════════════════════════════════════════════════

/// Map an active animation clip name to the appropriate [HandPose] for
/// each hand. Returns a record of (left, right) poses.
///
/// When no clip is playing (null), both hands return [HandPose.rest].
({HandPose left, HandPose right}) handPoseForClip(String? clipName) {
  return switch (clipName) {
    'wave'      => (left: HandPose.rest, right: HandPose.wave),
    'thumbsUp'  => (left: HandPose.rest, right: HandPose.thumbsUp),
    'pointAt'   => (left: HandPose.rest, right: HandPose.point),
    'celebrate' => (left: HandPose.open, right: HandPose.open),
    'clap'      => (left: HandPose.open, right: HandPose.open),
    'shrug'     => (left: HandPose.open, right: HandPose.open),
    'surprise'  => (left: HandPose.open, right: HandPose.open),
    'think'     => (left: HandPose.rest, right: HandPose.point),
    _           => (left: HandPose.rest, right: HandPose.rest),
  };
}

// ═══════════════════════════════════════════════════════════════════════
//  SHARED SKIN HELPERS
// ═══════════════════════════════════════════════════════════════════════

/// Warm highlight direction (same as FacePainter).
Color _warmHighlight(Color skin) =>
    Color.lerp(skin, const Color(0xFFFFF8E0), 0.12)!;

/// Cool shadow direction (same as FacePainter).
Color _coolShadow(Color skin) =>
    Color.lerp(skin, const Color(0xFF6A5A8E), 0.15)!;

// ═══════════════════════════════════════════════════════════════════════
//  NECK PAINTER
//  Cylindrical neck connecting head to chest.
// ═══════════════════════════════════════════════════════════════════════

/// Renders the neck as a 3D cylinder with skin tone gradient, chin
/// contact shadow, and collarbone hint. Responds to head tilt by
/// stretching on the opposite side.
///
/// Proportions: width ~18-20% of widget, positioned at ~65-70% down.
/// Exposes logical top/bottom Y as proportions for avatar_widget alignment:
///   topY  = 0.65 * height
///   baseY = topY + neckHeight
class NeckPainter extends CustomPainter {
  final Color skinColor;
  final double headTilt; // radians, positive = tilt right
  final double breathingValue; // 0.0-1.0

  /// Proportion of widget height where neck top sits.
  static const double topProportion = 0.65;

  /// Proportion of widget height for neck length.
  static const double heightProportion = 0.14;

  /// Proportion of widget height where neck base sits.
  static double get baseProportion => topProportion + heightProportion;

  NeckPainter({
    required this.skinColor,
    this.headTilt = 0.0,
    this.breathingValue = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final highlight = _warmHighlight(skinColor);
    final shadow = _coolShadow(skinColor);

    final neckW = w * 0.19;
    final neckH = h * heightProportion;
    final cx = w * 0.5;
    final top = h * topProportion;

    // Head tilt stretches neck on opposite side
    final tiltStretch = headTilt.clamp(-0.3, 0.3);
    final leftH = neckH * (1.0 + tiltStretch * 0.3);
    final rightH = neckH * (1.0 - tiltStretch * 0.3);

    // ── Organic cylindrical shape via cubic beziers ──
    final neckPath = Path();
    // Start at top-left (under chin, narrower)
    neckPath.moveTo(cx - neckW * 0.42, top);
    // Left side: organic outward curve toward base (widens naturally)
    neckPath.cubicTo(
      cx - neckW * 0.44, top + leftH * 0.25,
      cx - neckW * 0.54, top + leftH * 0.6,
      cx - neckW * 0.60, top + leftH,
    );
    // Bottom curve: gentle convex connecting left base to right base
    neckPath.cubicTo(
      cx - neckW * 0.30, top + (leftH + rightH) / 2 + 4,
      cx + neckW * 0.30, top + (leftH + rightH) / 2 + 4,
      cx + neckW * 0.60, top + rightH,
    );
    // Right side: organic inward curve toward top
    neckPath.cubicTo(
      cx + neckW * 0.54, top + rightH * 0.6,
      cx + neckW * 0.44, top + rightH * 0.25,
      cx + neckW * 0.42, top,
    );
    // Top curve under chin
    neckPath.quadraticBezierTo(cx, top - 1.5, cx - neckW * 0.42, top);
    neckPath.close();

    final neckRect = Rect.fromLTRB(
      cx - neckW * 0.65, top, cx + neckW * 0.65, top + max(leftH, rightH),
    );

    // Cylindrical gradient: shadow → highlight → skin → highlight → shadow
    final neckPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [shadow, highlight, skinColor, highlight, shadow],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(neckRect);

    canvas.drawPath(neckPath, neckPaint);

    // ── Chin contact shadow (blurred oval at top) ──
    final chinShadowPaint = Paint()
      ..color = shadow.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, top + 1.5),
        width: neckW * 1.4,
        height: 5,
      ),
      chinShadowPaint,
    );

    // ── Throat shadow — subtle vertical crease ──
    final throatPaint = Paint()
      ..color = shadow.withValues(alpha: 0.10)
      ..strokeWidth = 1.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawLine(
      Offset(cx, top + 4),
      Offset(cx, top + neckH * 0.65),
      throatPaint,
    );

    // ── Collarbone hints at base ──
    final collarbonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = shadow.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final baseY = top + max(leftH, rightH) - 2;
    for (final side in [-1.0, 1.0]) {
      final cbPath = Path()
        ..moveTo(cx, baseY)
        ..quadraticBezierTo(
          cx + side * neckW * 0.45, baseY + 1.5,
          cx + side * neckW * 0.75, baseY - 1,
        );
      canvas.drawPath(cbPath, collarbonePaint);
    }
  }

  @override
  bool shouldRepaint(NeckPainter old) =>
      old.skinColor != skinColor ||
      (old.headTilt * 100).round() != (headTilt * 100).round() ||
      (old.breathingValue * 100).round() != (breathingValue * 100).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  TORSO PAINTER
//  Shirt/clothing with collar, fabric folds, breathing animation.
//  Entirely bezier curves — no rectangles.
// ═══════════════════════════════════════════════════════════════════════

/// Renders the upper torso / children's shirt with organic bezier curves.
/// Includes dome shoulders, natural waist taper, collarbone depression,
/// belly curve, fabric folds with 3D ridges, and bottom alpha fade.
class TorsoPainter extends CustomPainter {
  final Color shirtColor;
  final int collarStyle; // 0 = crew, 1 = v-neck, 2 = collared
  final double breathingValue;
  final double swayValue;

  TorsoPainter({
    required this.shirtColor,
    this.collarStyle = 0,
    this.breathingValue = 0.0,
    this.swayValue = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Quantize sway/breath to reduce sub-pixel jitter that causes shimmer
    final qSway = (swayValue * 20).roundToDouble() / 20;
    final qBreath = (breathingValue * 20).roundToDouble() / 20;
    final cx = w * 0.5 + sin(qSway * pi) * w * 0.004;
    final breathExpand = sin(qBreath * pi) * 0.008;
    final shoulderW = w * (0.72 + breathExpand);
    final waistW = w * (0.55 + breathExpand * 0.5);
    final shoulderY = h * 0.78;
    final torsoBottom = h * 1.08;

    final shirtHL = Color.lerp(shirtColor, Colors.white, 0.15)!;
    final shirtSH = Color.lerp(shirtColor, Colors.black, 0.22)!;

    // ── Torso shape: entirely cubic bezier curves ──
    final torsoPath = Path();
    // Start at neckline center
    torsoPath.moveTo(cx, shoulderY + h * 0.015);

    // Right shoulder — gentle dome curve outward
    torsoPath.cubicTo(
      cx + shoulderW * 0.15, shoulderY - h * 0.014,
      cx + shoulderW * 0.33, shoulderY - h * 0.020,
      cx + shoulderW * 0.46, shoulderY + h * 0.018,
    );
    // Right shoulder cap — smooth dome to arm junction
    torsoPath.cubicTo(
      cx + shoulderW * 0.50, shoulderY + h * 0.035,
      cx + shoulderW * 0.52, shoulderY + h * 0.058,
      cx + shoulderW * 0.50, shoulderY + h * 0.078,
    );
    // Right side — natural taper from shoulder to waist
    torsoPath.cubicTo(
      cx + shoulderW * 0.47, shoulderY + h * 0.14,
      cx + waistW * 0.52, torsoBottom - h * 0.08,
      cx + waistW * 0.48, torsoBottom,
    );
    // Bottom — gentle belly curve
    torsoPath.cubicTo(
      cx + waistW * 0.20, torsoBottom + h * 0.012,
      cx - waistW * 0.20, torsoBottom + h * 0.012,
      cx - waistW * 0.48, torsoBottom,
    );
    // Left side — mirror waist taper
    torsoPath.cubicTo(
      cx - waistW * 0.52, torsoBottom - h * 0.08,
      cx - shoulderW * 0.47, shoulderY + h * 0.14,
      cx - shoulderW * 0.50, shoulderY + h * 0.078,
    );
    // Left shoulder cap
    torsoPath.cubicTo(
      cx - shoulderW * 0.52, shoulderY + h * 0.058,
      cx - shoulderW * 0.50, shoulderY + h * 0.035,
      cx - shoulderW * 0.46, shoulderY + h * 0.018,
    );
    // Left shoulder — dome back to center
    torsoPath.cubicTo(
      cx - shoulderW * 0.33, shoulderY - h * 0.020,
      cx - shoulderW * 0.15, shoulderY - h * 0.014,
      cx, shoulderY + h * 0.015,
    );
    torsoPath.close();

    // Use stable bounds for the gradient to prevent shimmer from
    // sub-pixel shader coordinate changes each frame
    final stableShoulderW = w * 0.73; // slightly wider than max to avoid clipping
    final torsoRect = Rect.fromLTRB(
      w * 0.5 - stableShoulderW / 2, shoulderY,
      w * 0.5 + stableShoulderW / 2, torsoBottom,
    );

    // ── 3D fabric gradient (left-to-right) ──
    final torsoPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [shirtSH, shirtColor, shirtHL, shirtColor, shirtSH],
        stops: const [0.0, 0.18, 0.5, 0.82, 1.0],
      ).createShader(torsoRect);

    canvas.drawPath(torsoPath, torsoPaint);

    // ── Bottom alpha fade (body continues below) ──
    final fadeHeight = (torsoBottom - shoulderY) * 0.15;
    final fadeRect = Rect.fromLTRB(
      cx - shoulderW * 0.55, torsoBottom - fadeHeight,
      cx + shoulderW * 0.55, torsoBottom + h * 0.015,
    );
    final fadePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF0A0A1A).withValues(alpha: 0.85),
        ],
      ).createShader(fadeRect);
    canvas.drawRect(fadeRect, fadePaint);

    // ── Subtle collarbone depression below neck ──
    final collarbonePaint = Paint()
      ..color = shirtSH.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final cbPath = Path()
      ..moveTo(cx - shoulderW * 0.15, shoulderY + h * 0.018)
      ..quadraticBezierTo(
        cx, shoulderY + h * 0.028,
        cx + shoulderW * 0.15, shoulderY + h * 0.018,
      );
    canvas.drawPath(
      cbPath,
      collarbonePaint..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );

    // ── Collar ──
    _drawCollar(canvas, cx, shoulderY, shoulderW, h);

    // ── Fabric folds (3D ridge effect) ──
    _drawFolds(canvas, cx, shoulderY, shoulderW, h, torsoBottom);

    // ── Shirt bottom hem ──
    final hemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Color.lerp(shirtColor, Colors.black, 0.18)!;
    final hemPath = Path()
      ..moveTo(cx - waistW * 0.50, torsoBottom)
      ..quadraticBezierTo(
        cx, torsoBottom + 2.5,
        cx + waistW * 0.50, torsoBottom,
      );
    canvas.drawPath(hemPath, hemPaint);
  }

  void _drawCollar(
      Canvas canvas, double cx, double sy, double sw, double h) {
    final collarPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Color.lerp(shirtColor, Colors.black, 0.28)!;

    final collarPath = Path();
    switch (collarStyle) {
      case 1: // V-neck
        collarPath.moveTo(cx - sw * 0.12, sy + h * 0.01);
        collarPath.lineTo(cx, sy + h * 0.065);
        collarPath.lineTo(cx + sw * 0.12, sy + h * 0.01);

      case 2: // Collared shirt — two wing shapes
        for (final side in [-1.0, 1.0]) {
          collarPath.moveTo(cx + side * sw * 0.10, sy + h * 0.01);
          collarPath.cubicTo(
            cx + side * sw * 0.16, sy - h * 0.012,
            cx + side * sw * 0.09, sy - h * 0.022,
            cx + side * sw * 0.03, sy + h * 0.02,
          );
        }
        // Collar fill (white triangle hint)
        final collarFill = Paint()
          ..color = Colors.white.withValues(alpha: 0.15);
        final fillPath = Path()
          ..moveTo(cx - sw * 0.08, sy + h * 0.01)
          ..lineTo(cx, sy + h * 0.04)
          ..lineTo(cx + sw * 0.08, sy + h * 0.01)
          ..close();
        canvas.drawPath(fillPath, collarFill);

      default: // Crew neck (round)
        collarPath.moveTo(cx - sw * 0.12, sy + h * 0.015);
        collarPath.quadraticBezierTo(
          cx, sy + h * 0.042,
          cx + sw * 0.12, sy + h * 0.015,
        );
    }
    canvas.drawPath(collarPath, collarPaint);
  }

  void _drawFolds(Canvas canvas, double cx, double sy, double sw, double h,
      double bottom) {
    final foldDark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Color.lerp(shirtColor, Colors.black, 0.10)!
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

    final foldLight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Color.lerp(shirtColor, Colors.white, 0.08)!
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    // Center fold — subtle vertical crease (dark + light pair for ridge)
    final fold1 = Path()
      ..moveTo(cx - 1, sy + h * 0.06)
      ..quadraticBezierTo(cx + 1, (sy + bottom) * 0.52, cx, bottom);
    canvas.drawPath(fold1, foldDark);

    final fold1hl = Path()
      ..moveTo(cx + 1.5, sy + h * 0.065)
      ..quadraticBezierTo(cx + 2.5, (sy + bottom) * 0.52, cx + 1.5, bottom);
    canvas.drawPath(fold1hl, foldLight);

    // Side folds — converge toward waist (2 per side = 3 total fold pairs)
    for (final side in [-1.0, 1.0]) {
      // Outer fold
      final foldOuter = Path()
        ..moveTo(cx + side * sw * 0.34, sy + h * 0.04)
        ..cubicTo(
          cx + side * sw * 0.32, sy + h * 0.10,
          cx + side * sw * 0.26, (sy + bottom) * 0.52,
          cx + side * sw * 0.28, bottom,
        );
      canvas.drawPath(foldOuter, foldDark);

      final foldOuterHL = Path()
        ..moveTo(cx + side * sw * 0.30, sy + h * 0.04)
        ..cubicTo(
          cx + side * sw * 0.28, sy + h * 0.10,
          cx + side * sw * 0.22, (sy + bottom) * 0.52,
          cx + side * sw * 0.24, bottom,
        );
      canvas.drawPath(foldOuterHL, foldLight);

      // Inner fold (shorter, starts lower)
      final foldInner = Path()
        ..moveTo(cx + side * sw * 0.16, sy + h * 0.07)
        ..cubicTo(
          cx + side * sw * 0.15, sy + h * 0.12,
          cx + side * sw * 0.12, (sy + bottom) * 0.53,
          cx + side * sw * 0.13, bottom,
        );
      canvas.drawPath(foldInner, foldDark);

      // Armpit crease shadow
      final armpitShadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Color.lerp(shirtColor, Colors.black, 0.12)!
            .withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final armpit = Path()
        ..moveTo(cx + side * sw * 0.46, sy + h * 0.04)
        ..quadraticBezierTo(
          cx + side * sw * 0.42, sy + h * 0.065,
          cx + side * sw * 0.36, sy + h * 0.05,
        );
      canvas.drawPath(armpit, armpitShadow);
    }
  }

  @override
  bool shouldRepaint(TorsoPainter old) =>
      old.shirtColor != shirtColor ||
      old.collarStyle != collarStyle ||
      (old.breathingValue * 20).round() != (breathingValue * 20).round() ||
      (old.swayValue * 20).round() != (swayValue * 20).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  SHOULDER PAINTER
//  Rounded shoulder shapes connecting torso to upper arms.
// ═══════════════════════════════════════════════════════════════════════

/// Renders the rounded shoulder caps. Matches shirt fabric color with
/// a soft top highlight for 3D roundness.
class ShoulderPainter extends CustomPainter {
  final Color shirtColor;
  final double swayValue;
  final double breathingValue;

  /// Bone-driven vertical offset for left shoulder (normalized, positive = down).
  final double leftShoulderDy;

  /// Bone-driven vertical offset for right shoulder (normalized, positive = down).
  final double rightShoulderDy;

  ShoulderPainter({
    required this.shirtColor,
    this.swayValue = 0.0,
    this.breathingValue = 0.0,
    this.leftShoulderDy = 0.0,
    this.rightShoulderDy = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5 + sin(swayValue * pi) * w * 0.006;
    final breathExpand = sin(breathingValue * pi) * 0.01;
    final shoulderW = w * (0.72 + breathExpand);
    final shoulderY = h * 0.78;

    final shirtHL = Color.lerp(shirtColor, Colors.white, 0.22)!;
    final shirtMid = Color.lerp(shirtColor, Colors.white, 0.08)!;
    final shirtSH = Color.lerp(shirtColor, Colors.black, 0.15)!;

    for (final side in [-1.0, 1.0]) {
      final dy = side < 0 ? leftShoulderDy : rightShoulderDy;
      // Align with torso shoulder dome (0.48 * shoulderW from center)
      final sCx = cx + side * shoulderW * 0.48;
      final sCy = shoulderY + dy * h;
      // Wider, flatter cap for child-like roundness (matches wider arms)
      final capW = w * 0.18;
      final capH = h * 0.060;

      // Cap top sits slightly above shoulderY for overlap with torso dome
      final capTop = sCy - capH * 0.15;
      // Cap bottom aligns with arm start (shoulderY + h*0.035)
      final capBottom = sCy + h * 0.035;

      final capRect = Rect.fromLTRB(
        sCx - capW * 0.55, capTop,
        sCx + capW * 0.55, capBottom,
      );

      // Soft rounded dome via cubic beziers for child-like shape
      final capPath = Path();
      // Start at inner-bottom (torso side)
      capPath.moveTo(sCx - side * capW * 0.5, capBottom);
      // Rise up the inner edge into the dome peak
      capPath.cubicTo(
        sCx - side * capW * 0.45, sCy - capH * 0.05,
        sCx - side * capW * 0.2, capTop - capH * 0.1,
        sCx, capTop - capH * 0.15,
      );
      // Dome peak down to outer edge
      capPath.cubicTo(
        sCx + side * capW * 0.2, capTop - capH * 0.1,
        sCx + side * capW * 0.45, sCy + capH * 0.05,
        sCx + side * capW * 0.5, capBottom,
      );
      // Smooth bottom connecting to arm zone
      capPath.quadraticBezierTo(
        sCx, capBottom + capH * 0.08,
        sCx - side * capW * 0.5, capBottom,
      );
      capPath.close();

      // 3D curvature: radial-like effect via top-to-bottom + side gradient
      final capPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shirtHL, shirtMid, shirtColor, shirtSH],
          stops: const [0.0, 0.35, 0.7, 1.0],
        ).createShader(capRect);
      canvas.drawPath(capPath, capPaint);

      // Side highlight for 3D curvature (light catches top-outer edge)
      final sideHLPaint = Paint()
        ..shader = LinearGradient(
          begin: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
          end: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            shirtHL.withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5],
        ).createShader(capRect);
      canvas.drawPath(capPath, sideHLPaint);

      // Soft seam line at shoulder-torso junction (blended, not harsh)
      final seamPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = shirtSH.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      final seamPath = Path()
        ..moveTo(sCx - side * capW * 0.4, capBottom - 1)
        ..quadraticBezierTo(
          sCx, capBottom + capH * 0.04,
          sCx + side * capW * 0.4, capBottom - 1,
        );
      canvas.drawPath(seamPath, seamPaint);
    }
  }

  @override
  bool shouldRepaint(ShoulderPainter old) =>
      old.shirtColor != shirtColor ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.breathingValue * 100).round() != (breathingValue * 100).round() ||
      (old.leftShoulderDy * 100).round() != (leftShoulderDy * 100).round() ||
      (old.rightShoulderDy * 100).round() != (rightShoulderDy * 100).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  ARM PAINTER
//  Upper arm + forearm with elbow crease, sleeve covering upper portion.
//  Bezier contours with tapered thickness: shoulder ~8% → wrist ~5%.
// ═══════════════════════════════════════════════════════════════════════

/// Renders both arms with organic bezier contours — upper arm with
/// sleeve, natural elbow bend, forearm tapering to wrist.
class ArmPainter extends CustomPainter {
  final Color skinColor;
  final Color shirtColor;
  final double swayValue;
  final double breathingValue;

  /// Bone-driven rotation for left arm (radians).
  final double leftArmRotation;

  /// Bone-driven rotation for right arm (radians).
  final double rightArmRotation;

  ArmPainter({
    required this.skinColor,
    required this.shirtColor,
    this.swayValue = 0.0,
    this.breathingValue = 0.0,
    this.leftArmRotation = 0.0,
    this.rightArmRotation = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final highlight = _warmHighlight(skinColor);
    final shadow = _coolShadow(skinColor);

    final cx = w * 0.5 + sin(swayValue * pi) * w * 0.006;
    final shoulderW = w * 0.72;
    final shoulderY = h * 0.78;

    for (final side in [-1.0, 1.0]) {
      final rotation = side < 0 ? leftArmRotation : rightArmRotation;
      _drawArm(canvas, w, h, cx, shoulderW, shoulderY, side,
          highlight, shadow, rotation);
    }
  }

  void _drawArm(Canvas canvas, double w, double h, double cx,
      double shoulderW, double shoulderY, double side,
      Color highlight, Color shadow, double boneRotation) {
    // Align arm center with shoulder cap center (0.48)
    final armCx = cx + side * shoulderW * 0.48;
    // Chubby child proportions: wider, rounder arm tubes
    final shoulderArmW = w * 0.095;
    final wristArmW = w * 0.065;

    // Arm top blends with shoulder cap bottom (shoulderY + h*0.035)
    final upperArmTop = shoulderY + h * 0.033;

    // Natural resting angle: arms hang slightly outward (~3 degrees)
    final naturalAngle = side * 0.052; // ~3 degrees in radians
    final totalRotation = boneRotation + naturalAngle;

    if (totalRotation.abs() > 0.001) {
      canvas.save();
      canvas.translate(armCx, shoulderY);
      canvas.rotate(totalRotation);
      canvas.translate(-armCx, -shoulderY);
    }

    final elbowY = shoulderY + h * 0.125;
    final forearmBottom = shoulderY + h * 0.225;

    // ── Upper arm — soft rounded tube for cartoon child look ──
    final upperPath = Path();
    // Outer contour: gentle outward curve (no angular bicep)
    upperPath.moveTo(armCx - shoulderArmW * 0.48, upperArmTop);
    upperPath.cubicTo(
      armCx - shoulderArmW * 0.55, upperArmTop + (elbowY - upperArmTop) * 0.25,
      armCx - shoulderArmW * 0.52, elbowY - (elbowY - upperArmTop) * 0.2,
      armCx - shoulderArmW * 0.44, elbowY,
    );
    // Elbow: smooth rounded curve (no crease)
    upperPath.quadraticBezierTo(
      armCx, elbowY + 2.5,
      armCx + shoulderArmW * 0.44, elbowY,
    );
    // Inner contour: gentle mirror curve
    upperPath.cubicTo(
      armCx + shoulderArmW * 0.52, elbowY - (elbowY - upperArmTop) * 0.2,
      armCx + shoulderArmW * 0.55, upperArmTop + (elbowY - upperArmTop) * 0.25,
      armCx + shoulderArmW * 0.48, upperArmTop,
    );
    upperPath.close();

    final upperRect = Rect.fromLTRB(
      armCx - shoulderArmW, upperArmTop, armCx + shoulderArmW, elbowY,
    );

    // Skin gradient for 3D cylindrical roundness
    final upperSkinPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadow, highlight, skinColor, highlight, shadow],
        stops: const [0.0, 0.12, 0.5, 0.88, 1.0],
      ).createShader(upperRect);
    canvas.drawPath(upperPath, upperSkinPaint);

    // Sleeve overlay (covers top ~55% of upper arm)
    final sleeveBottom = upperArmTop + (elbowY - upperArmTop) * 0.55;
    final sleevePath = Path();
    // Sleeve top aligns with shoulder cap — slightly wider for overlap
    sleevePath.moveTo(armCx - shoulderArmW * 0.62, upperArmTop - 2);
    sleevePath.cubicTo(
      armCx - shoulderArmW * 0.60, (upperArmTop + sleeveBottom) * 0.5,
      armCx - shoulderArmW * 0.54, sleeveBottom - 2,
      armCx - shoulderArmW * 0.48, sleeveBottom,
    );
    sleevePath.quadraticBezierTo(
      armCx, sleeveBottom + 2.5,
      armCx + shoulderArmW * 0.48, sleeveBottom,
    );
    sleevePath.cubicTo(
      armCx + shoulderArmW * 0.54, sleeveBottom - 2,
      armCx + shoulderArmW * 0.60, (upperArmTop + sleeveBottom) * 0.5,
      armCx + shoulderArmW * 0.62, upperArmTop - 2,
    );
    sleevePath.close();

    final sleeveRect = Rect.fromLTRB(
      armCx - shoulderArmW * 0.68, upperArmTop,
      armCx + shoulderArmW * 0.68, sleeveBottom,
    );
    final sleevePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          shirtColor,
          Color.lerp(shirtColor, Colors.black, 0.06)!,
          Color.lerp(shirtColor, Colors.black, 0.12)!,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(sleeveRect);
    canvas.drawPath(sleevePath, sleevePaint);

    // Sleeve cuff edge — clean band at sleeve-to-skin transition
    final cuffDark = Color.lerp(shirtColor, Colors.black, 0.25)!;
    final cuffLight = Color.lerp(shirtColor, Colors.white, 0.08)!;
    // Dark cuff line (bottom edge of fabric)
    final cuffDarkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = cuffDark;
    final cuffPath = Path()
      ..moveTo(armCx - shoulderArmW * 0.46, sleeveBottom)
      ..quadraticBezierTo(
        armCx, sleeveBottom + 2,
        armCx + shoulderArmW * 0.46, sleeveBottom,
      );
    canvas.drawPath(cuffPath, cuffDarkPaint);
    // Light cuff highlight (top edge of cuff band for 3D rim)
    final cuffHLPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = cuffLight.withValues(alpha: 0.5);
    final cuffHLPath = Path()
      ..moveTo(armCx - shoulderArmW * 0.44, sleeveBottom - 1)
      ..quadraticBezierTo(
        armCx, sleeveBottom + 1,
        armCx + shoulderArmW * 0.44, sleeveBottom - 1,
      );
    canvas.drawPath(cuffHLPath, cuffHLPaint);

    // ── Forearm — chubby rounded tube tapering gently to wrist ──
    final elbowHalfW = shoulderArmW * 0.44;
    final wristHalfW = wristArmW * 0.50;

    final forearmPath = Path();
    forearmPath.moveTo(armCx - elbowHalfW, elbowY);
    // Outer contour — gentle taper with slight swell (baby fat)
    forearmPath.cubicTo(
      armCx - elbowHalfW * 1.05, elbowY + (forearmBottom - elbowY) * 0.30,
      armCx - wristHalfW * 1.10, forearmBottom - (forearmBottom - elbowY) * 0.25,
      armCx - wristHalfW, forearmBottom,
    );
    // Wrist curve — rounded end (wider for cartoon look)
    forearmPath.quadraticBezierTo(
      armCx, forearmBottom + wristArmW * 0.30,
      armCx + wristHalfW, forearmBottom,
    );
    // Inner contour
    forearmPath.cubicTo(
      armCx + wristHalfW * 1.10, forearmBottom - (forearmBottom - elbowY) * 0.25,
      armCx + elbowHalfW * 1.05, elbowY + (forearmBottom - elbowY) * 0.30,
      armCx + elbowHalfW, elbowY,
    );
    forearmPath.close();

    final forearmRect = Rect.fromLTRB(
      armCx - elbowHalfW * 1.15, elbowY,
      armCx + elbowHalfW * 1.15, forearmBottom,
    );
    final forearmPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadow, highlight, skinColor, highlight, shadow],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(forearmRect);
    canvas.drawPath(forearmPath, forearmPaint);

    // ── Elbow hint — very subtle shadow, no hard crease for cartoon style ──
    final elbowCreasePaint = Paint()
      ..color = shadow.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(armCx, elbowY + 1),
        width: elbowHalfW * 1.4,
        height: 4,
      ),
      elbowCreasePaint,
    );

    if (totalRotation.abs() > 0.001) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ArmPainter old) =>
      old.skinColor != skinColor ||
      old.shirtColor != shirtColor ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.breathingValue * 100).round() != (breathingValue * 100).round() ||
      (old.leftArmRotation * 100).round() != (leftArmRotation * 100).round() ||
      (old.rightArmRotation * 100).round() != (rightArmRotation * 100).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  HAND PAINTER
//  Cartoon mitt-style hands (Animal Crossing / Mii inspired).
//  Rounded, friendly shapes — no individual fingers.
//  Supports rest/open/point/thumbsUp/wave poses via shape variations.
// ═══════════════════════════════════════════════════════════════════════

/// Renders cartoon mitt-style hands at the ends of the arms.
/// Each hand is a rounded oval with a small thumb nub, styled for
/// a children's app with warm, friendly proportions.
class HandPainter extends CustomPainter {
  final Color skinColor;
  final HandPose leftPose;
  final HandPose rightPose;
  final double swayValue;
  final double wavePhase; // 0.0-1.0 oscillation for wave animation

  late final Color _highlight = _warmHighlight(skinColor);
  late final Color _shadow = _coolShadow(skinColor);

  HandPainter({
    required this.skinColor,
    this.leftPose = HandPose.rest,
    this.rightPose = HandPose.rest,
    this.swayValue = 0.0,
    this.wavePhase = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final cx = w * 0.5 + sin(swayValue * pi) * w * 0.006;
    final shoulderW = w * 0.72;
    final handY = h * 0.78 + h * 0.22; // at bottom of arms

    // Mitt scale relative to widget
    final mittSize = w * 0.11;

    // Left hand
    _drawMitt(canvas, cx - shoulderW * 0.48, handY, mittSize, -1.0, leftPose);

    // Right hand
    _drawMitt(canvas, cx + shoulderW * 0.48, handY, mittSize, 1.0, rightPose);
  }

  void _drawMitt(Canvas canvas, double cx, double cy, double ms,
      double side, HandPose pose) {
    // Wave rotation
    final waveAngle =
        (pose == HandPose.wave) ? sin(wavePhase * pi * 2) * 0.35 : 0.0;

    canvas.save();
    canvas.translate(cx, cy);
    if (waveAngle != 0.0) {
      canvas.rotate(waveAngle);
    }

    // Mitt dimensions — rounded oval with slight taper at wrist
    final mittW = ms * 0.92;
    final mittH = ms * 0.72;
    final mittCy = -mittH * 0.3; // center offset upward from wrist

    // ── Wrist connection (tapered cylinder) ──
    final wristW = mittW * 0.55;
    final wristPath = Path()
      ..moveTo(-wristW / 2, 0)
      ..cubicTo(
        -wristW * 0.6, -mittH * 0.15,
        -mittW * 0.42, mittCy + mittH * 0.35,
        -mittW * 0.42, mittCy + mittH * 0.15,
      )
      ..lineTo(mittW * 0.42, mittCy + mittH * 0.15)
      ..cubicTo(
        mittW * 0.42, mittCy + mittH * 0.35,
        wristW * 0.6, -mittH * 0.15,
        wristW / 2, 0,
      )
      ..close();

    final wristRect = Rect.fromCenter(
      center: Offset(0, -mittH * 0.1),
      width: mittW,
      height: mittH * 0.5,
    );
    canvas.drawPath(wristPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [_shadow, _highlight, skinColor, _highlight, _shadow],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(wristRect));

    // ── Main mitt body ──
    final mittRect = Rect.fromCenter(
      center: Offset(0, mittCy),
      width: mittW,
      height: mittH,
    );

    // Mitt body shape — soft rounded rectangle via RRect
    final mittRR = RRect.fromRectAndCorners(
      mittRect,
      topLeft: Radius.circular(mittW * 0.45),
      topRight: Radius.circular(mittW * 0.45),
      bottomLeft: Radius.circular(mittW * 0.35),
      bottomRight: Radius.circular(mittW * 0.35),
    );

    // 3D radial gradient
    final mittPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(side * -0.2, -0.3),
        radius: 1.1,
        colors: [_highlight, skinColor, _shadow],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(mittRect);

    canvas.drawRRect(mittRR, mittPaint);

    // ── Thumb nub ──
    final thumbAngle = switch (pose) {
      HandPose.thumbsUp => side * -0.8,     // thumb points up
      HandPose.point    => side * -0.4,      // thumb slightly up
      HandPose.open     => side * -0.55,     // thumb spread out
      HandPose.wave     => side * -0.55,
      HandPose.rest     => side * -0.2,      // thumb at rest alongside
    };
    final thumbLen = ms * 0.30;
    final thumbW = ms * 0.20;

    // Thumb base position: outer side of mitt
    final thumbBaseX = side * mittW * 0.38;
    final thumbBaseY = mittCy + mittH * 0.05;

    canvas.save();
    canvas.translate(thumbBaseX, thumbBaseY);
    canvas.rotate(thumbAngle);

    // Thumb shape — rounded capsule
    final thumbPath = Path()
      ..moveTo(-thumbW / 2, 0)
      ..cubicTo(
        -thumbW * 0.55, -thumbLen * 0.3,
        -thumbW * 0.45, -thumbLen * 0.8,
        0, -thumbLen,
      )
      ..cubicTo(
        thumbW * 0.45, -thumbLen * 0.8,
        thumbW * 0.55, -thumbLen * 0.3,
        thumbW / 2, 0,
      )
      ..close();

    final thumbRect = Rect.fromCenter(
      center: Offset(0, -thumbLen * 0.5),
      width: thumbW,
      height: thumbLen,
    );
    canvas.drawPath(thumbPath, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 1.1,
        colors: [_highlight, skinColor, _shadow],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(thumbRect));

    canvas.restore(); // thumb transform

    // ── Pose-specific details ──
    if (pose == HandPose.point) {
      // Point: small nub extending upward from top of mitt (index finger hint)
      final pointLen = ms * 0.22;
      final pointW = ms * 0.12;
      final pointPath = Path()
        ..moveTo(-pointW / 2, mittCy - mittH * 0.42)
        ..cubicTo(
          -pointW * 0.4, mittCy - mittH * 0.42 - pointLen * 0.5,
          -pointW * 0.3, mittCy - mittH * 0.42 - pointLen * 0.9,
          0, mittCy - mittH * 0.42 - pointLen,
        )
        ..cubicTo(
          pointW * 0.3, mittCy - mittH * 0.42 - pointLen * 0.9,
          pointW * 0.4, mittCy - mittH * 0.42 - pointLen * 0.5,
          pointW / 2, mittCy - mittH * 0.42,
        )
        ..close();
      canvas.drawPath(pointPath, Paint()..color = skinColor);
    }

    // ── Soft highlight on top of mitt for 3D roundness ──
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-mittW * 0.08, mittCy - mittH * 0.12),
        width: mittW * 0.35,
        height: mittH * 0.25,
      ),
      Paint()
        ..color = _highlight.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ms * 0.06),
    );

    // ── Knuckle line (subtle crease across mitt) ──
    final knucklePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ms * 0.012
      ..color = _shadow.withValues(alpha: 0.15)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, ms * 0.02);
    canvas.drawLine(
      Offset(-mittW * 0.28, mittCy - mittH * 0.08),
      Offset(mittW * 0.28, mittCy - mittH * 0.08),
      knucklePaint,
    );

    canvas.restore(); // main transform
  }

  @override
  bool shouldRepaint(HandPainter old) =>
      old.skinColor != skinColor ||
      old.leftPose != leftPose ||
      old.rightPose != rightPose ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.wavePhase * 100).round() != (wavePhase * 100).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  COMBINED BODY PAINTER (convenience wrapper)
//  Single painter that renders the full body below the head.
// ═══════════════════════════════════════════════════════════════════════

/// Convenience painter that renders the full body in a single pass.
/// Use this when you don't need separate layering control over
/// individual body parts. Draws in order: neck → torso → shoulders →
/// arms → hands.
class BodyPainter extends CustomPainter {
  final Color skinColor;
  final Color shirtColor;
  final int collarStyle;
  final double headTilt;
  final double breathingValue;
  final double swayValue;
  final HandPose leftHandPose;
  final HandPose rightHandPose;
  final double wavePhase;

  /// Bone-driven arm rotations (radians).
  final double leftArmRotation;
  final double rightArmRotation;

  /// Bone-driven shoulder vertical offsets (normalized).
  final double leftShoulderDy;
  final double rightShoulderDy;

  BodyPainter({
    required this.skinColor,
    this.shirtColor = const Color(0xFF4A90D9),
    this.collarStyle = 0,
    this.headTilt = 0.0,
    this.breathingValue = 0.0,
    this.swayValue = 0.0,
    this.leftHandPose = HandPose.rest,
    this.rightHandPose = HandPose.rest,
    this.wavePhase = 0.0,
    this.leftArmRotation = 0.0,
    this.rightArmRotation = 0.0,
    this.leftShoulderDy = 0.0,
    this.rightShoulderDy = 0.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    NeckPainter(
      skinColor: skinColor,
      headTilt: headTilt,
      breathingValue: breathingValue,
    ).paint(canvas, size);

    TorsoPainter(
      shirtColor: shirtColor,
      collarStyle: collarStyle,
      breathingValue: breathingValue,
      swayValue: swayValue,
    ).paint(canvas, size);

    ShoulderPainter(
      shirtColor: shirtColor,
      swayValue: swayValue,
      breathingValue: breathingValue,
      leftShoulderDy: leftShoulderDy,
      rightShoulderDy: rightShoulderDy,
    ).paint(canvas, size);

    ArmPainter(
      skinColor: skinColor,
      shirtColor: shirtColor,
      swayValue: swayValue,
      breathingValue: breathingValue,
      leftArmRotation: leftArmRotation,
      rightArmRotation: rightArmRotation,
    ).paint(canvas, size);

    HandPainter(
      skinColor: skinColor,
      leftPose: leftHandPose,
      rightPose: rightHandPose,
      swayValue: swayValue,
      wavePhase: wavePhase,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(BodyPainter old) =>
      old.skinColor != skinColor ||
      old.shirtColor != shirtColor ||
      old.collarStyle != collarStyle ||
      old.leftHandPose != leftHandPose ||
      old.rightHandPose != rightHandPose ||
      (old.headTilt * 100).round() != (headTilt * 100).round() ||
      (old.breathingValue * 100).round() != (breathingValue * 100).round() ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.wavePhase * 100).round() != (wavePhase * 100).round() ||
      (old.leftArmRotation * 100).round() != (leftArmRotation * 100).round() ||
      (old.rightArmRotation * 100).round() != (rightArmRotation * 100).round() ||
      (old.leftShoulderDy * 100).round() != (leftShoulderDy * 100).round() ||
      (old.rightShoulderDy * 100).round() != (rightShoulderDy * 100).round();
}

// ═══════════════════════════════════════════════════════════════════════
//  SHIRT COLOR OPTIONS
// ═══════════════════════════════════════════════════════════════════════

/// 8 default shirt colors indexed 0-7, chosen to contrast well against
/// the avatar background colors.
const List<Color> shirtColorOptions = [
  Color(0xFF4A90D9), // blue
  Color(0xFFE85D75), // coral
  Color(0xFF5BB85D), // green
  Color(0xFFEE9B3E), // orange
  Color(0xFF9B6BC4), // purple
  Color(0xFF45B7D1), // teal
  Color(0xFFFF6B8A), // pink
  Color(0xFF6BCB77), // mint
];

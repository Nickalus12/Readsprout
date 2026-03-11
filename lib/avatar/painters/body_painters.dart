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

    final cx = w * 0.5 + sin(swayValue * pi) * w * 0.006;
    final breathExpand = sin(breathingValue * pi) * 0.012;
    final shoulderW = w * (0.70 + breathExpand);
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

    final torsoRect = Rect.fromLTRB(
      cx - shoulderW / 2, shoulderY, cx + shoulderW / 2, torsoBottom,
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
      (old.breathingValue * 100).round() != (breathingValue * 100).round() ||
      (old.swayValue * 100).round() != (swayValue * 100).round();
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

    final shirtHL = Color.lerp(shirtColor, Colors.white, 0.20)!;
    final shirtSH = Color.lerp(shirtColor, Colors.black, 0.15)!;

    for (final side in [-1.0, 1.0]) {
      final dy = side < 0 ? leftShoulderDy : rightShoulderDy;
      final sCx = cx + side * shoulderW * 0.48;
      final sCy = shoulderY + dy * h;
      final capW = w * 0.14;
      final capH = h * 0.06;

      final capRect = Rect.fromCenter(
        center: Offset(sCx, sCy + capH * 0.3),
        width: capW,
        height: capH,
      );

      // Rounded dome shape via quadratic beziers
      final capPath = Path();
      capPath.moveTo(sCx - capW * 0.5, sCy + capH * 0.5);
      capPath.quadraticBezierTo(
        sCx - capW * 0.4, sCy - capH * 0.2,
        sCx, sCy - capH * 0.3,
      );
      capPath.quadraticBezierTo(
        sCx + capW * 0.4, sCy - capH * 0.2,
        sCx + capW * 0.5, sCy + capH * 0.5,
      );
      capPath.close();

      final capPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shirtHL, shirtColor, shirtSH],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(capRect);

      canvas.drawPath(capPath, capPaint);

      // Seam line at shoulder-torso junction
      final seamPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = shirtSH.withValues(alpha: 0.4);
      final seamPath = Path()
        ..moveTo(sCx - capW * 0.45, sCy + capH * 0.45)
        ..quadraticBezierTo(
          sCx, sCy + capH * 0.55,
          sCx + capW * 0.45, sCy + capH * 0.45,
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
    final armCx = cx + side * shoulderW * 0.52;
    // Shoulder width ~8% of widget, wrist ~5%
    final shoulderArmW = w * 0.08;
    final wristArmW = w * 0.05;

    final upperArmTop = shoulderY + h * 0.035;

    if (boneRotation.abs() > 0.001) {
      canvas.save();
      canvas.translate(armCx, shoulderY);
      canvas.rotate(boneRotation);
      canvas.translate(-armCx, -shoulderY);
    }

    final elbowY = shoulderY + h * 0.12;
    final forearmBottom = shoulderY + h * 0.22;

    // ── Upper arm (bezier contours, not rectangles) ──
    final upperPath = Path();
    // Left contour: organic outward bulge
    upperPath.moveTo(armCx - shoulderArmW * 0.5, upperArmTop);
    upperPath.cubicTo(
      armCx - shoulderArmW * 0.65, (upperArmTop + elbowY) * 0.48,
      armCx - shoulderArmW * 0.58, elbowY - 3,
      armCx - shoulderArmW * 0.48, elbowY,
    );
    // Bottom of upper arm
    upperPath.lineTo(armCx + shoulderArmW * 0.48, elbowY);
    // Right contour: mirror bulge
    upperPath.cubicTo(
      armCx + shoulderArmW * 0.58, elbowY - 3,
      armCx + shoulderArmW * 0.65, (upperArmTop + elbowY) * 0.48,
      armCx + shoulderArmW * 0.5, upperArmTop,
    );
    upperPath.close();

    final upperRect = Rect.fromLTRB(
      armCx - shoulderArmW, upperArmTop, armCx + shoulderArmW, elbowY,
    );

    // Skin gradient for 3D roundness
    final upperSkinPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadow, highlight, skinColor, highlight, shadow],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(upperRect);
    canvas.drawPath(upperPath, upperSkinPaint);

    // Sleeve overlay (covers top ~55% of upper arm)
    final sleeveBottom = upperArmTop + (elbowY - upperArmTop) * 0.55;
    final sleevePath = Path();
    sleevePath.moveTo(armCx - shoulderArmW * 0.60, upperArmTop - 1);
    sleevePath.cubicTo(
      armCx - shoulderArmW * 0.58, (upperArmTop + sleeveBottom) * 0.5,
      armCx - shoulderArmW * 0.54, sleeveBottom - 1,
      armCx - shoulderArmW * 0.50, sleeveBottom,
    );
    sleevePath.quadraticBezierTo(
      armCx, sleeveBottom + 3,
      armCx + shoulderArmW * 0.50, sleeveBottom,
    );
    sleevePath.cubicTo(
      armCx + shoulderArmW * 0.54, sleeveBottom - 1,
      armCx + shoulderArmW * 0.58, (upperArmTop + sleeveBottom) * 0.5,
      armCx + shoulderArmW * 0.60, upperArmTop - 1,
    );
    sleevePath.close();

    final sleeveRect = Rect.fromLTRB(
      armCx - shoulderArmW * 0.65, upperArmTop,
      armCx + shoulderArmW * 0.65, sleeveBottom,
    );
    final sleevePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [shirtColor, Color.lerp(shirtColor, Colors.black, 0.08)!],
      ).createShader(sleeveRect);
    canvas.drawPath(sleevePath, sleevePaint);

    // Sleeve hem
    final hemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Color.lerp(shirtColor, Colors.black, 0.22)!;
    final hemPath = Path()
      ..moveTo(armCx - shoulderArmW * 0.48, sleeveBottom)
      ..quadraticBezierTo(
        armCx, sleeveBottom + 2,
        armCx + shoulderArmW * 0.48, sleeveBottom,
      );
    canvas.drawPath(hemPath, hemPaint);

    // ── Forearm (tapers from elbow to wrist) ──
    // Interpolate width from shoulder width at elbow to wrist width at bottom
    final elbowHalfW = shoulderArmW * 0.48;
    final wristHalfW = wristArmW * 0.48;

    final forearmPath = Path();
    forearmPath.moveTo(armCx - elbowHalfW, elbowY);
    // Left contour — organic taper
    forearmPath.cubicTo(
      armCx - elbowHalfW * 1.05, (elbowY + forearmBottom) * 0.5,
      armCx - wristHalfW * 1.1, forearmBottom - 4,
      armCx - wristHalfW, forearmBottom,
    );
    // Wrist curve
    forearmPath.quadraticBezierTo(
      armCx, forearmBottom + wristArmW * 0.25,
      armCx + wristHalfW, forearmBottom,
    );
    // Right contour — mirror taper
    forearmPath.cubicTo(
      armCx + wristHalfW * 1.1, forearmBottom - 4,
      armCx + elbowHalfW * 1.05, (elbowY + forearmBottom) * 0.5,
      armCx + elbowHalfW, elbowY,
    );
    forearmPath.close();

    final forearmRect = Rect.fromLTRB(
      armCx - elbowHalfW * 1.1, elbowY,
      armCx + elbowHalfW * 1.1, forearmBottom,
    );
    final forearmPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadow, highlight, skinColor, highlight, shadow],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(forearmRect);
    canvas.drawPath(forearmPath, forearmPaint);

    // ── Elbow crease ──
    final elbowCreasePaint = Paint()
      ..color = shadow.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(armCx, elbowY + 1),
        width: elbowHalfW * 1.4,
        height: 3,
      ),
      elbowCreasePaint,
    );

    if (boneRotation.abs() > 0.001) {
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
//  5-fingered hand rendering with bezier segments per finger.
//  Supports rest/open/point/thumbsUp/wave poses.
// ═══════════════════════════════════════════════════════════════════════

/// Finger definition: base angle, length multiplier, width multiplier.
class _FingerDef {
  final double angleDeg;
  final double lengthMul;
  final double widthMul;
  const _FingerDef(this.angleDeg, this.lengthMul, this.widthMul);
}

/// Renders realistic 5-fingered hands at the ends of the arms.
/// Each finger is built from bezier segments with knuckle bumps,
/// tapered width, and fingernail crescents.
class HandPainter extends CustomPainter {
  final Color skinColor;
  final HandPose leftPose;
  final HandPose rightPose;
  final double swayValue;
  final double wavePhase; // 0.0-1.0 oscillation for wave animation

  // Cached paints (created once, not per-frame allocation in loops)
  late final Color _highlight = _warmHighlight(skinColor);
  late final Color _shadow = _coolShadow(skinColor);
  late final Paint _skinPaint = Paint()..color = skinColor;
  late final Paint _nailPaint = Paint()
    ..color = _highlight.withValues(alpha: 0.55);
  late final Paint _knucklePaint = Paint()
    ..color = _shadow.withValues(alpha: 0.12)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

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

    // Hand scale relative to widget — works at all sizes
    final handSize = w * 0.13;

    // Left hand
    _drawHand(canvas, cx - shoulderW * 0.52, handY, handSize, -1.0, leftPose,
        false);

    // Right hand
    _drawHand(canvas, cx + shoulderW * 0.52, handY, handSize, 1.0, rightPose,
        true);
  }

  void _drawHand(Canvas canvas, double cx, double cy, double hs,
      double side, HandPose pose, bool isRight) {
    // Wave rotation
    final waveAngle =
        (pose == HandPose.wave) ? sin(wavePhase * pi * 2) * 0.35 : 0.0;

    canvas.save();
    if (waveAngle != 0.0) {
      canvas.translate(cx, cy);
      canvas.rotate(waveAngle);
      canvas.translate(-cx, -cy);
    }

    switch (pose) {
      case HandPose.rest:
        _drawRestHand(canvas, cx, cy, hs, side);
      case HandPose.open:
      case HandPose.wave:
        _drawOpenHand(canvas, cx, cy, hs, side);
      case HandPose.point:
        _drawPointHand(canvas, cx, cy, hs, side);
      case HandPose.thumbsUp:
        _drawThumbsUp(canvas, cx, cy, hs, side);
    }

    canvas.restore();
  }

  // ── FINGER DRAWING ENGINE ──

  /// Draws a single finger using 2-3 bezier segments with tapered width,
  /// knuckle bumps, and fingernail crescent.
  void _drawFinger(
    Canvas canvas, {
    required double baseX,
    required double baseY,
    required double length,
    required double baseWidth,
    required double tipWidth,
    required double angle, // radians from vertical (0 = straight up)
    required double curl, // 0.0 = straight, 1.0 = fully curled
  }) {
    canvas.save();
    canvas.translate(baseX, baseY);
    canvas.rotate(angle);

    // Scale dimensions
    final bw = baseWidth;
    final tw = tipWidth;
    final len = length * (1.0 - curl * 0.55); // curl shortens visible finger

    // Curl bends the finger inward
    final curlOffsetX = curl * bw * 0.8;
    final curlOffsetY = curl * len * 0.3;

    // Finger path: base → middle (knuckle bump) → tip
    final fingerPath = Path();

    // Left contour
    fingerPath.moveTo(-bw / 2, 0);
    // First knuckle bump (subtle outward curve)
    fingerPath.cubicTo(
      -bw / 2 - bw * 0.08, -len * 0.25,
      -bw * 0.42 + curlOffsetX * 0.3, -len * 0.45 + curlOffsetY * 0.3,
      -tw * 0.45 + curlOffsetX * 0.6, -len * 0.55 + curlOffsetY * 0.5,
    );
    // Second segment to tip
    fingerPath.cubicTo(
      -tw * 0.48 + curlOffsetX * 0.8, -len * 0.72 + curlOffsetY * 0.7,
      -tw * 0.40 + curlOffsetX, -len * 0.92 + curlOffsetY,
      curlOffsetX, -len + curlOffsetY,
    );
    // Tip (rounded)
    fingerPath.quadraticBezierTo(
      tw * 0.40 + curlOffsetX, -len * 0.92 + curlOffsetY,
      tw * 0.48 + curlOffsetX * 0.8, -len * 0.72 + curlOffsetY * 0.7,
    );
    // Right contour back down
    fingerPath.cubicTo(
      tw * 0.45 + curlOffsetX * 0.6, -len * 0.55 + curlOffsetY * 0.5,
      bw * 0.42 + curlOffsetX * 0.3, -len * 0.45 + curlOffsetY * 0.3,
      bw / 2 + bw * 0.08, -len * 0.25,
    );
    // Back to base with knuckle bump
    fingerPath.cubicTo(
      bw / 2, -len * 0.12,
      bw / 2, 0,
      bw / 2, 0,
    );
    fingerPath.close();

    canvas.drawPath(fingerPath, _skinPaint);

    // ── Knuckle bump shadow (at ~35% up the finger) ──
    if (curl < 0.6) {
      final knuckleY = -len * 0.30 + curlOffsetY * 0.25;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(curlOffsetX * 0.2, knuckleY),
          width: bw * 0.85,
          height: bw * 0.25,
        ),
        _knucklePaint,
      );
    }

    // ── Fingernail crescent at tip ──
    if (curl < 0.4) {
      final nailCx = curlOffsetX * 0.9;
      final nailCy = -len * 0.90 + curlOffsetY * 0.85;
      final nailW = tw * 0.75;
      final nailH = tw * 0.50;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(nailCx, nailCy),
            width: nailW,
            height: nailH,
          ),
          Radius.circular(nailW * 0.5),
        ),
        _nailPaint,
      );
    }

    canvas.restore();
  }

  /// Draws the palm as a rounded trapezoid connecting wrist to finger bases.
  void _drawPalm(Canvas canvas, double cx, double cy, double palmW,
      double palmH, double side) {
    final palmRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: palmW,
      height: palmH,
    );
    final palmPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(side * -0.2, -0.3),
        radius: 1.2,
        colors: [_highlight, skinColor, _shadow],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(palmRect);

    // Rounded trapezoid: wider at top (finger bases), narrower at wrist
    const wristNarrow = 0.85; // wrist is 85% of palm width
    final path = Path();
    // Top-left (finger base side)
    path.moveTo(cx - palmW * 0.48, cy - palmH * 0.45);
    // Top curve
    path.quadraticBezierTo(
      cx, cy - palmH * 0.52,
      cx + palmW * 0.48, cy - palmH * 0.45,
    );
    // Right side taper
    path.cubicTo(
      cx + palmW * 0.50, cy - palmH * 0.15,
      cx + palmW * wristNarrow * 0.50, cy + palmH * 0.25,
      cx + palmW * wristNarrow * 0.48, cy + palmH * 0.48,
    );
    // Bottom (wrist)
    path.quadraticBezierTo(
      cx, cy + palmH * 0.52,
      cx - palmW * wristNarrow * 0.48, cy + palmH * 0.48,
    );
    // Left side taper
    path.cubicTo(
      cx - palmW * wristNarrow * 0.50, cy + palmH * 0.25,
      cx - palmW * 0.50, cy - palmH * 0.15,
      cx - palmW * 0.48, cy - palmH * 0.45,
    );
    path.close();

    canvas.drawPath(path, palmPaint);
  }

  // ── REST POSE: slight inward curl, fingers relaxed together ──

  /// Finger definitions for rest pose: angle, length multiplier, width multiplier
  static const _restFingers = [
    _FingerDef(-20, 0.70, 1.10), // thumb (angled outward, shorter, wider)
    _FingerDef(-4, 0.90, 0.90),  // index
    _FingerDef(0, 1.00, 0.95),   // middle (longest)
    _FingerDef(4, 0.88, 0.88),   // ring
    _FingerDef(9, 0.72, 0.78),   // pinky (shortest, narrowest)
  ];

  void _drawRestHand(Canvas canvas, double cx, double cy, double hs,
      double side) {
    final palmW = hs * 0.78;
    final palmH = hs * 0.58;
    final palmCy = cy + palmH * 0.15;

    _drawPalm(canvas, cx, palmCy, palmW, palmH, side);

    // Base finger dimensions
    final baseFingerLen = hs * 0.38;
    final baseFingerW = hs * 0.10;

    // Draw 5 fingers with slight curl
    for (int i = 0; i < 5; i++) {
      final def = _restFingers[i];
      final isThumb = i == 0;

      // Position fingers along top of palm
      final double fx;
      final double fy;
      final double angle;

      if (isThumb) {
        // Thumb: positioned on the side of the palm, angled outward
        fx = cx + side * palmW * 0.42;
        fy = palmCy - palmH * 0.05;
        angle = side * def.angleDeg * pi / 180;
      } else {
        // Fingers: spread across top of palm
        final t = (i - 1) / 3.0; // 0.0 to 1.0 for index through pinky
        fx = cx + (t - 0.5) * palmW * 0.72;
        fy = palmCy - palmH * 0.42;
        angle = side * def.angleDeg * pi / 180;
      }

      final fingerLen = baseFingerLen * def.lengthMul;
      final fingerW = baseFingerW * def.widthMul;
      final tipW = fingerW * 0.55; // tapers to ~55% at tip

      _drawFinger(
        canvas,
        baseX: fx,
        baseY: fy,
        length: fingerLen,
        baseWidth: fingerW,
        tipWidth: tipW,
        angle: angle,
        curl: isThumb ? 0.15 : 0.35, // slight curl for rest
      );
    }
  }

  // ── OPEN POSE: fingers spread apart with visible gaps ──

  static const _openFingers = [
    _FingerDef(-35, 0.70, 1.10), // thumb (more spread)
    _FingerDef(-10, 0.92, 0.90), // index
    _FingerDef(-2, 1.00, 0.95),  // middle
    _FingerDef(8, 0.88, 0.88),   // ring
    _FingerDef(18, 0.72, 0.78),  // pinky
  ];

  void _drawOpenHand(Canvas canvas, double cx, double cy, double hs,
      double side) {
    final palmW = hs * 0.78;
    final palmH = hs * 0.58;
    final palmCy = cy + palmH * 0.15;

    _drawPalm(canvas, cx, palmCy, palmW, palmH, side);

    final baseFingerLen = hs * 0.42;
    final baseFingerW = hs * 0.09;

    for (int i = 0; i < 5; i++) {
      final def = _openFingers[i];
      final isThumb = i == 0;

      final double fx;
      final double fy;
      final double angle;

      if (isThumb) {
        fx = cx + side * palmW * 0.45;
        fy = palmCy - palmH * 0.02;
        angle = side * def.angleDeg * pi / 180;
      } else {
        final t = (i - 1) / 3.0;
        fx = cx + (t - 0.5) * palmW * 0.78; // wider spread
        fy = palmCy - palmH * 0.42;
        angle = side * def.angleDeg * pi / 180;
      }

      final fingerLen = baseFingerLen * def.lengthMul;
      final fingerW = baseFingerW * def.widthMul;
      final tipW = fingerW * 0.50;

      _drawFinger(
        canvas,
        baseX: fx,
        baseY: fy,
        length: fingerLen,
        baseWidth: fingerW,
        tipWidth: tipW,
        angle: angle,
        curl: isThumb ? 0.05 : 0.08, // nearly straight
      );
    }
  }

  // ── POINT POSE: index extended, others curled ──

  void _drawPointHand(Canvas canvas, double cx, double cy, double hs,
      double side) {
    final palmW = hs * 0.72;
    final palmH = hs * 0.55;
    final palmCy = cy + palmH * 0.15;

    _drawPalm(canvas, cx, palmCy, palmW, palmH, side);

    final baseFingerLen = hs * 0.42;
    final baseFingerW = hs * 0.09;

    // Finger defs for point: thumb curled against palm, index extended, rest curled
    final pointFingers = [
      (def: const _FingerDef(-20, 0.65, 1.10), curl: 0.55), // thumb curled
      (def: const _FingerDef(-2, 1.00, 0.92), curl: 0.05),  // index extended
      (def: const _FingerDef(2, 0.95, 0.95), curl: 0.75),   // middle curled
      (def: const _FingerDef(5, 0.85, 0.88), curl: 0.80),   // ring curled
      (def: const _FingerDef(9, 0.70, 0.78), curl: 0.85),   // pinky curled
    ];

    for (int i = 0; i < 5; i++) {
      final finger = pointFingers[i];
      final isThumb = i == 0;

      final double fx;
      final double fy;
      final double angle;

      if (isThumb) {
        fx = cx + side * palmW * 0.40;
        fy = palmCy + palmH * 0.05;
        angle = side * finger.def.angleDeg * pi / 180;
      } else {
        final t = (i - 1) / 3.0;
        fx = cx + (t - 0.5) * palmW * 0.70;
        fy = palmCy - palmH * 0.42;
        angle = side * finger.def.angleDeg * pi / 180;
      }

      final fingerLen = baseFingerLen * finger.def.lengthMul;
      final fingerW = baseFingerW * finger.def.widthMul;
      final tipW = fingerW * 0.55;

      _drawFinger(
        canvas,
        baseX: fx,
        baseY: fy,
        length: fingerLen,
        baseWidth: fingerW,
        tipWidth: tipW,
        angle: angle,
        curl: finger.curl,
      );
    }
  }

  // ── THUMBS UP POSE: fist with thumb extended upward ──

  void _drawThumbsUp(Canvas canvas, double cx, double cy, double hs,
      double side) {
    final palmW = hs * 0.70;
    final palmH = hs * 0.52;
    final palmCy = cy + palmH * 0.10;

    _drawPalm(canvas, cx, palmCy, palmW, palmH, side);

    final baseFingerLen = hs * 0.40;
    final baseFingerW = hs * 0.09;

    // All fingers curled into fist, thumb extended upward
    final thumbsUpFingers = [
      (def: const _FingerDef(-5, 0.80, 1.15), curl: 0.02),  // thumb UP
      (def: const _FingerDef(-3, 0.85, 0.90), curl: 0.85),  // index curled
      (def: const _FingerDef(0, 0.90, 0.92), curl: 0.88),   // middle curled
      (def: const _FingerDef(3, 0.82, 0.88), curl: 0.88),   // ring curled
      (def: const _FingerDef(7, 0.68, 0.78), curl: 0.90),   // pinky curled
    ];

    for (int i = 0; i < 5; i++) {
      final finger = thumbsUpFingers[i];
      final isThumb = i == 0;

      final double fx;
      final double fy;
      final double angle;

      if (isThumb) {
        // Thumb: side of palm, pointing up with slight outward lean
        fx = cx + side * palmW * 0.38;
        fy = palmCy - palmH * 0.25;
        angle = side * finger.def.angleDeg * pi / 180;
      } else {
        final t = (i - 1) / 3.0;
        fx = cx + (t - 0.5) * palmW * 0.65;
        fy = palmCy - palmH * 0.38;
        angle = side * finger.def.angleDeg * pi / 180;
      }

      final fingerLen = baseFingerLen * finger.def.lengthMul;
      final fingerW = baseFingerW * finger.def.widthMul;
      final tipW = fingerW * 0.55;

      _drawFinger(
        canvas,
        baseX: fx,
        baseY: fy,
        length: fingerLen,
        baseWidth: fingerW,
        tipWidth: tipW,
        angle: angle,
        curl: finger.curl,
      );
    }

    // Extra: draw curled finger bumps visible on fist front
    for (int i = 0; i < 3; i++) {
      final bx = cx - palmW * 0.15 + i * palmW * 0.18;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx, palmCy + palmH * 0.35),
          width: palmW * 0.14,
          height: palmW * 0.10,
        ),
        _knucklePaint,
      );
    }
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

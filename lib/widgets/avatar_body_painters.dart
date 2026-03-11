import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
//  HAND POSE — gesture states for hand rendering
// ═══════════════════════════════════════════════════════════════════════

/// Hand gesture poses used by [HandPainter].
enum HandPose {
  /// Relaxed mitten, fingers loosely together.
  rest,

  /// Spread fingers (5 rounded finger shapes).
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
class NeckPainter extends CustomPainter {
  final Color skinColor;
  final double headTilt; // radians, positive = tilt right
  final double breathingValue; // 0.0-1.0

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

    final neckW = w * 0.18;
    final neckH = h * 0.12;
    final cx = w * 0.5;
    final top = h * 0.70;

    // Head tilt stretches neck on opposite side
    final tiltStretch = headTilt.clamp(-0.3, 0.3);
    final leftH = neckH * (1.0 + tiltStretch * 0.3);
    final rightH = neckH * (1.0 - tiltStretch * 0.3);

    // Build asymmetric neck shape
    final neckPath = Path();
    neckPath.moveTo(cx - neckW * 0.5, top);
    neckPath.lineTo(cx - neckW * 0.55, top + leftH); // left side (wider at base)
    neckPath.quadraticBezierTo(
      cx, top + (leftH + rightH) / 2 + 2,
      cx + neckW * 0.55, top + rightH,
    );
    neckPath.lineTo(cx + neckW * 0.5, top);
    neckPath.close();

    final neckRect = Rect.fromLTRB(
      cx - neckW * 0.6, top, cx + neckW * 0.6, top + max(leftH, rightH),
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

    // Chin contact shadow
    final chinShadowPaint = Paint()
      ..color = shadow.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, top + 1),
        width: neckW * 1.3,
        height: 4,
      ),
      chinShadowPaint,
    );

    // Throat shadow — subtle vertical crease
    final throatPaint = Paint()
      ..color = shadow.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawLine(
      Offset(cx, top + 3),
      Offset(cx, top + neckH * 0.7),
      throatPaint..strokeWidth = 1.5,
    );

    // Collarbone hints at base
    final collarbonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = shadow.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final baseY = top + max(leftH, rightH) - 2;
    for (final side in [-1.0, 1.0]) {
      final cbPath = Path()
        ..moveTo(cx, baseY)
        ..quadraticBezierTo(
          cx + side * neckW * 0.4, baseY + 1,
          cx + side * neckW * 0.7, baseY - 1,
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
// ═══════════════════════════════════════════════════════════════════════

/// Renders the upper torso / children's shirt. Includes collar styles,
/// fabric fold shading, and breathing expansion.
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
    final breathExpand = sin(breathingValue * pi) * 0.01;
    final shoulderW = w * (0.72 + breathExpand);
    final shoulderY = h * 0.78;
    final torsoBottom = h * 1.08;

    final shirtHL = Color.lerp(shirtColor, Colors.white, 0.15)!;
    final shirtSH = Color.lerp(shirtColor, Colors.black, 0.22)!;

    // ── Torso shape: rounded shoulders, slight taper to bottom ──
    final torsoPath = Path();
    torsoPath.moveTo(cx, shoulderY + h * 0.02);

    // Right shoulder
    torsoPath.cubicTo(
      cx + shoulderW * 0.15, shoulderY - h * 0.01,
      cx + shoulderW * 0.38, shoulderY - h * 0.005,
      cx + shoulderW * 0.50, shoulderY + h * 0.035,
    );
    // Right side (slight taper in)
    torsoPath.cubicTo(
      cx + shoulderW * 0.50, shoulderY + h * 0.08,
      cx + shoulderW * 0.46, torsoBottom - h * 0.04,
      cx + shoulderW * 0.44, torsoBottom,
    );
    // Bottom
    torsoPath.lineTo(cx - shoulderW * 0.44, torsoBottom);
    // Left side
    torsoPath.cubicTo(
      cx - shoulderW * 0.46, torsoBottom - h * 0.04,
      cx - shoulderW * 0.50, shoulderY + h * 0.08,
      cx - shoulderW * 0.50, shoulderY + h * 0.035,
    );
    // Left shoulder
    torsoPath.cubicTo(
      cx - shoulderW * 0.38, shoulderY - h * 0.005,
      cx - shoulderW * 0.15, shoulderY - h * 0.01,
      cx, shoulderY + h * 0.02,
    );
    torsoPath.close();

    final torsoRect = Rect.fromLTRB(
      cx - shoulderW / 2, shoulderY, cx + shoulderW / 2, torsoBottom,
    );

    // 3D fabric gradient
    final torsoPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [shirtSH, shirtColor, shirtHL, shirtColor, shirtSH],
        stops: const [0.0, 0.18, 0.5, 0.82, 1.0],
      ).createShader(torsoRect);

    canvas.drawPath(torsoPath, torsoPaint);

    // ── Collar ──
    _drawCollar(canvas, cx, shoulderY, shoulderW, h);

    // ── Fabric folds ──
    _drawFolds(canvas, cx, shoulderY, shoulderW, h, torsoBottom);

    // ── Shirt bottom hem ──
    final hemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Color.lerp(shirtColor, Colors.black, 0.18)!;
    final hemPath = Path()
      ..moveTo(cx - shoulderW * 0.42, torsoBottom)
      ..quadraticBezierTo(cx, torsoBottom + 2, cx + shoulderW * 0.42, torsoBottom);
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
    final foldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Color.lerp(shirtColor, Colors.black, 0.10)!
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

    // Center fold
    final fold1 = Path()
      ..moveTo(cx - 1, sy + h * 0.06)
      ..quadraticBezierTo(cx + 1, (sy + bottom) * 0.52, cx, bottom);
    canvas.drawPath(fold1, foldPaint);

    // Side folds
    for (final side in [-1.0, 1.0]) {
      final fold = Path()
        ..moveTo(cx + side * sw * 0.30, sy + h * 0.04)
        ..quadraticBezierTo(
          cx + side * sw * 0.25, (sy + bottom) * 0.53,
          cx + side * sw * 0.28, bottom,
        );
      canvas.drawPath(fold, foldPaint);
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
/// a soft top highlight for 3D roundness (kids have round shoulders).
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

      // Rounded dome shape
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

      // Top highlight gradient for roundness
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
// ═══════════════════════════════════════════════════════════════════════

/// Renders both arms as chibi/cartoon style: short, round, slightly
/// oversized relative to realistic proportions. Upper arm has shirt
/// sleeve, forearm is bare skin, elbow has a natural crease shadow.
class ArmPainter extends CustomPainter {
  final Color skinColor;
  final Color shirtColor;
  final double swayValue;
  final double breathingValue;

  /// Bone-driven rotation for left arm (radians, positive = rotate clockwise).
  final double leftArmRotation;

  /// Bone-driven rotation for right arm (radians, positive = rotate clockwise).
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
    final armW = w * 0.11;

    // Chibi proportions: short, stubby arms
    final upperArmTop = shoulderY + h * 0.035;

    // Apply bone-driven rotation at the shoulder pivot point
    if (boneRotation.abs() > 0.001) {
      canvas.save();
      canvas.translate(armCx, shoulderY);
      canvas.rotate(boneRotation);
      canvas.translate(-armCx, -shoulderY);
    }
    final elbowY = shoulderY + h * 0.12;
    final forearmBottom = shoulderY + h * 0.22;

    // ── Upper arm (under sleeve) ──
    final upperPath = Path();
    upperPath.moveTo(armCx - armW * 0.5, upperArmTop);
    // Slight outward bulge (roundness)
    upperPath.cubicTo(
      armCx - armW * 0.6, (upperArmTop + elbowY) * 0.5,
      armCx - armW * 0.55, elbowY - 2,
      armCx - armW * 0.45, elbowY,
    );
    upperPath.lineTo(armCx + armW * 0.45, elbowY);
    upperPath.cubicTo(
      armCx + armW * 0.55, elbowY - 2,
      armCx + armW * 0.6, (upperArmTop + elbowY) * 0.5,
      armCx + armW * 0.5, upperArmTop,
    );
    upperPath.close();

    final upperRect = Rect.fromLTRB(
      armCx - armW, upperArmTop, armCx + armW, elbowY,
    );

    // Skin under sleeve
    final upperSkinPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [highlight, skinColor, shadow],
      ).createShader(upperRect);
    canvas.drawPath(upperPath, upperSkinPaint);

    // Sleeve overlay (covers top ~55% of upper arm)
    final sleeveBottom = upperArmTop + (elbowY - upperArmTop) * 0.55;
    final sleevePath = Path();
    sleevePath.moveTo(armCx - armW * 0.58, upperArmTop - 1);
    sleevePath.lineTo(armCx - armW * 0.52, sleeveBottom);
    sleevePath.quadraticBezierTo(
      armCx, sleeveBottom + 3,
      armCx + armW * 0.52, sleeveBottom,
    );
    sleevePath.lineTo(armCx + armW * 0.58, upperArmTop - 1);
    sleevePath.close();

    final sleeveRect = Rect.fromLTRB(
      armCx - armW * 0.6, upperArmTop, armCx + armW * 0.6, sleeveBottom,
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
      ..moveTo(armCx - armW * 0.50, sleeveBottom)
      ..quadraticBezierTo(armCx, sleeveBottom + 2, armCx + armW * 0.50, sleeveBottom);
    canvas.drawPath(hemPath, hemPaint);

    // ── Forearm (bare skin) ──
    final forearmPath = Path();
    forearmPath.moveTo(armCx - armW * 0.45, elbowY);
    forearmPath.cubicTo(
      armCx - armW * 0.50, (elbowY + forearmBottom) * 0.5,
      armCx - armW * 0.45, forearmBottom - 3,
      armCx - armW * 0.35, forearmBottom,
    );
    // Wrist (narrower)
    forearmPath.quadraticBezierTo(
      armCx, forearmBottom + armW * 0.2,
      armCx + armW * 0.35, forearmBottom,
    );
    forearmPath.cubicTo(
      armCx + armW * 0.45, forearmBottom - 3,
      armCx + armW * 0.50, (elbowY + forearmBottom) * 0.5,
      armCx + armW * 0.45, elbowY,
    );
    forearmPath.close();

    final forearmRect = Rect.fromLTRB(
      armCx - armW, elbowY, armCx + armW, forearmBottom,
    );
    final forearmPaint = Paint()
      ..shader = LinearGradient(
        begin: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: [highlight, skinColor, shadow],
      ).createShader(forearmRect);
    canvas.drawPath(forearmPath, forearmPaint);

    // ── Elbow crease (natural shadow, not a hard line) ──
    final elbowCreasePaint = Paint()
      ..color = shadow.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(armCx, elbowY + 1),
        width: armW * 0.7,
        height: 3,
      ),
      elbowCreasePaint,
    );

    // Restore canvas if bone rotation was applied
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
//  Pose-aware hand rendering with mitten/open/point/thumbsUp/wave.
// ═══════════════════════════════════════════════════════════════════════

/// Renders cartoon-style oversized hands at the ends of the arms.
/// Supports [HandPose] gestures with fingernail hints on open poses.
class HandPainter extends CustomPainter {
  final Color skinColor;
  final HandPose leftPose;
  final HandPose rightPose;
  final double swayValue;
  final double wavePhase; // 0.0-1.0 oscillation for wave animation

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
    final highlight = _warmHighlight(skinColor);
    final shadow = _coolShadow(skinColor);

    final cx = w * 0.5 + sin(swayValue * pi) * w * 0.006;
    final shoulderW = w * 0.72;
    final handY = h * 0.78 + h * 0.22; // at bottom of arms

    // Chibi oversized hands — ~1.2x arm width
    final handSize = w * 0.13;

    // Left hand
    final leftCx = cx - shoulderW * 0.52;
    _drawHand(canvas, leftCx, handY, handSize, -1.0, leftPose,
        highlight, shadow, false);

    // Right hand
    final rightCx = cx + shoulderW * 0.52;
    _drawHand(canvas, rightCx, handY, handSize, 1.0, rightPose,
        highlight, shadow, true);
  }

  void _drawHand(Canvas canvas, double cx, double cy, double hs,
      double side, HandPose pose, Color highlight, Color shadow,
      bool isRight) {
    // Wave rotation for wave pose
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
        _drawMitten(canvas, cx, cy, hs, side, highlight, shadow);
      case HandPose.open:
      case HandPose.wave:
        _drawOpenHand(canvas, cx, cy, hs, side, highlight, shadow);
      case HandPose.point:
        _drawPointHand(canvas, cx, cy, hs, side, highlight, shadow);
      case HandPose.thumbsUp:
        _drawThumbsUp(canvas, cx, cy, hs, side, highlight, shadow);
    }

    canvas.restore();
  }

  /// Relaxed mitten — fingers loosely together.
  void _drawMitten(Canvas canvas, double cx, double cy, double hs,
      double side, Color highlight, Color shadow) {
    final palmW = hs * 0.85;
    final palmH = hs * 0.75;

    final palmRect = Rect.fromCenter(
      center: Offset(cx, cy + palmH * 0.2),
      width: palmW,
      height: palmH,
    );

    final palmPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 1.2,
        colors: [highlight, skinColor, shadow],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(palmRect);

    // Rounded mitten shape
    final mittenPath = Path();
    mittenPath.addRRect(
      RRect.fromRectAndRadius(palmRect, Radius.circular(palmW * 0.4)),
    );
    canvas.drawPath(mittenPath, palmPaint);

    // Thumb bump on the side
    final thumbCx = cx + side * palmW * 0.45;
    final thumbCy = cy + palmH * 0.1;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(thumbCx, thumbCy),
        width: hs * 0.25,
        height: hs * 0.32,
      ),
      Paint()..color = skinColor,
    );

    // Knuckle line hint
    final knucklePaint = Paint()
      ..color = shadow.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawLine(
      Offset(cx - palmW * 0.25, cy - palmH * 0.05),
      Offset(cx + palmW * 0.25, cy - palmH * 0.05),
      knucklePaint..strokeWidth = 1.0,
    );
  }

  /// Spread fingers (5 rounded shapes) with fingernail hints.
  void _drawOpenHand(Canvas canvas, double cx, double cy, double hs,
      double side, Color highlight, Color shadow) {
    final palmW = hs * 0.7;
    final palmH = hs * 0.6;

    // Palm base
    final palmRect = Rect.fromCenter(
      center: Offset(cx, cy + palmH * 0.3),
      width: palmW,
      height: palmH,
    );
    final palmPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 1.2,
        colors: [highlight, skinColor, shadow],
      ).createShader(palmRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, Radius.circular(palmW * 0.3)),
      palmPaint,
    );

    // 4 fingers + thumb
    final fingerPaint = Paint()..color = skinColor;
    final nailPaint = Paint()
      ..color = highlight.withValues(alpha: 0.5);
    const fingerCount = 4;
    final fingerW = palmW * 0.22;
    final fingerH = hs * 0.40;
    final startX = cx - palmW * 0.35;
    final spacing = palmW * 0.70 / (fingerCount - 1);
    final baseY = cy - palmH * 0.08;

    // Spread angle
    for (int i = 0; i < fingerCount; i++) {
      final fx = startX + i * spacing;
      final spreadAngle = (i - 1.5) * 0.06 * side;

      canvas.save();
      canvas.translate(fx, baseY);
      canvas.rotate(spreadAngle);

      // Finger
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, -fingerH * 0.4),
            width: fingerW,
            height: fingerH,
          ),
          Radius.circular(fingerW * 0.5),
        ),
        fingerPaint,
      );

      // Fingernail hint (lighter arc at tip)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, -fingerH * 0.58),
            width: fingerW * 0.7,
            height: fingerW * 0.5,
          ),
          Radius.circular(fingerW * 0.4),
        ),
        nailPaint,
      );

      canvas.restore();
    }

    // Thumb
    final thumbCx = cx + side * palmW * 0.48;
    final thumbCy = cy + palmH * 0.1;
    canvas.save();
    canvas.translate(thumbCx, thumbCy);
    canvas.rotate(side * 0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -hs * 0.12),
          width: fingerW * 1.15,
          height: fingerH * 0.8,
        ),
        Radius.circular(fingerW * 0.5),
      ),
      fingerPaint,
    );
    // Thumb nail
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -hs * 0.22),
          width: fingerW * 0.75,
          height: fingerW * 0.5,
        ),
        Radius.circular(fingerW * 0.4),
      ),
      nailPaint,
    );
    canvas.restore();
  }

  /// Index finger extended, others curled into fist.
  void _drawPointHand(Canvas canvas, double cx, double cy, double hs,
      double side, Color highlight, Color shadow) {
    final palmW = hs * 0.7;
    final palmH = hs * 0.6;

    // Fist base (rounded, compact)
    final fistRect = Rect.fromCenter(
      center: Offset(cx, cy + palmH * 0.2),
      width: palmW * 0.85,
      height: palmH * 0.9,
    );
    final fistPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 1.2,
        colors: [highlight, skinColor, shadow],
      ).createShader(fistRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fistRect, Radius.circular(palmW * 0.35)),
      fistPaint,
    );

    // Curled finger bumps on top (3 small arcs)
    final bumpPaint = Paint()..color = skinColor;
    for (int i = 0; i < 3; i++) {
      final bx = cx - palmW * 0.15 + i * palmW * 0.18;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx, cy - palmH * 0.15),
          width: palmW * 0.16,
          height: palmW * 0.12,
        ),
        bumpPaint,
      );
    }

    // Extended index finger
    final fingerW = palmW * 0.22;
    final fingerH = hs * 0.48;
    final indexX = cx + side * palmW * 0.10;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(indexX, cy - fingerH * 0.35),
          width: fingerW,
          height: fingerH,
        ),
        Radius.circular(fingerW * 0.5),
      ),
      Paint()..color = skinColor,
    );

    // Nail on index
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(indexX, cy - fingerH * 0.55),
          width: fingerW * 0.7,
          height: fingerW * 0.5,
        ),
        Radius.circular(fingerW * 0.4),
      ),
      Paint()..color = highlight.withValues(alpha: 0.5),
    );

    // Thumb
    final thumbCx = cx + side * palmW * 0.45;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(thumbCx, cy + palmH * 0.05),
        width: hs * 0.22,
        height: hs * 0.28,
      ),
      Paint()..color = skinColor,
    );
  }

  /// Fist with thumb up.
  void _drawThumbsUp(Canvas canvas, double cx, double cy, double hs,
      double side, Color highlight, Color shadow) {
    final palmW = hs * 0.7;
    final palmH = hs * 0.6;

    // Fist
    final fistRect = Rect.fromCenter(
      center: Offset(cx, cy + palmH * 0.15),
      width: palmW * 0.80,
      height: palmH * 0.85,
    );
    final fistPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 1.2,
        colors: [highlight, skinColor, shadow],
      ).createShader(fistRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fistRect, Radius.circular(palmW * 0.35)),
      fistPaint,
    );

    // Curled fingers on front of fist
    final knucklePaint = Paint()
      ..color = shadow.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    for (int i = 0; i < 3; i++) {
      final kx = cx - palmW * 0.18 + i * palmW * 0.18;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(kx, cy + palmH * 0.45),
          width: palmW * 0.16,
          height: palmW * 0.10,
        ),
        knucklePaint,
      );
    }

    // Thumb up
    final thumbW = hs * 0.20;
    final thumbH = hs * 0.40;
    final thumbCx = cx + side * palmW * 0.30;
    final thumbCy = cy - palmH * 0.25;

    canvas.save();
    canvas.translate(thumbCx, thumbCy);
    canvas.rotate(side * -0.15); // slight outward lean

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -thumbH * 0.3),
          width: thumbW,
          height: thumbH,
        ),
        Radius.circular(thumbW * 0.5),
      ),
      Paint()..color = skinColor,
    );

    // Thumbnail
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -thumbH * 0.48),
          width: thumbW * 0.7,
          height: thumbW * 0.5,
        ),
        Radius.circular(thumbW * 0.4),
      ),
      Paint()..color = highlight.withValues(alpha: 0.5),
    );

    canvas.restore();
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

  // Delegate painters (created fresh each paint — cheap value objects)
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

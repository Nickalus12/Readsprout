import 'dart:math';
import 'package:flutter/material.dart';
import '../shader_loader.dart';

/// Whether the hair color index is the special rainbow gradient.
bool isRainbowHair(int colorIndex) => colorIndex == 13;

// ── Color helpers ────────────────────────────────────────────────────

/// Derive a warm highlight (mix toward warm yellow-white, not cold white).
Color _warmHighlight(Color base, [double t = 0.25]) =>
    Color.lerp(base, const Color(0xFFFFF8E0), t)!;

/// Derive a cool shadow (shift toward blue-black for realism).
Color _coolShadow(Color base, [double t = 0.25]) =>
    Color.lerp(base, const Color(0xFF1A1A3E), t)!;

/// Mid-tone between highlight and shadow for strand body.
Color _midTone(Color base) =>
    Color.lerp(base, const Color(0xFFE8E0D0), 0.06)!;

// ── Rainbow spectrum for SweepGradient ──────────────────────────────

const List<Color> _rainbowColors = [
  Color(0xFFFF4444),
  Color(0xFFFF8C42),
  Color(0xFFFFD700),
  Color(0xFF00E68A),
  Color(0xFF4A90D9),
  Color(0xFF9B59B6),
  Color(0xFFFF4444),
];

// ── Sway / bounce constants ─────────────────────────────────────────

/// Sway amplitude for the single natural style (medium-length hair).
const double _swayAmplitude = 0.020;

/// Wind sensitivity for medium-length hair.
const double _windSens = 0.08;

/// Bounce sensitivity for medium-length hair.
const double _bounceSens = 0.05;

/// Phase offsets for follow-through delay between strand groups.
const List<double> _phaseOffsets = [0.0, 0.3, 0.6, 0.9, 1.2];

// ── Shared geometry helpers ─────────────────────────────────────────

/// Compute sway offset with follow-through phase, wind, and bounce.
double _computeSway(double swayValue,
    [int phase = 0, double windStrength = 0.0]) {
  final offset = _phaseOffsets[phase.clamp(0, 4)];
  final baseSway = sin(swayValue * pi + offset) * _swayAmplitude;
  final wind = windStrength * _windSens;
  return baseSway + wind;
}

/// Compute vertical bounce offset.
double _computeBounce(double bounceValue, [int phase = 0]) {
  if (bounceValue <= 0.001) return 0.0;
  final offset = _phaseOffsets[phase.clamp(0, 4)];
  return sin(bounceValue * pi * 2 + offset) * _bounceSens * bounceValue;
}

/// Build a hair strand as a filled bezier shape with width tapering
/// from root to tip. Uses computed normals for smooth edges.
Path _buildStrand(List<Offset> points, double baseWidth) {
  if (points.length < 2) return Path();
  final left = <Offset>[];
  final right = <Offset>[];
  for (int i = 0; i < points.length; i++) {
    final t = i / (points.length - 1);
    // Taper: full width at root, 25% at tip
    final w = baseWidth * (1.0 - t * 0.75);
    Offset tangent;
    if (i == 0) {
      tangent = points[1] - points[0];
    } else if (i == points.length - 1) {
      tangent = points[i] - points[i - 1];
    } else {
      tangent = points[i + 1] - points[i - 1];
    }
    final len = tangent.distance;
    if (len < 0.001) {
      left.add(points[i]);
      right.add(points[i]);
      continue;
    }
    final normal = Offset(-tangent.dy / len, tangent.dx / len);
    left.add(points[i] + normal * w);
    right.add(points[i] - normal * w);
  }
  final path = Path();
  path.moveTo(left[0].dx, left[0].dy);
  for (int i = 1; i < left.length; i++) {
    final prev = left[i - 1];
    final curr = left[i];
    path.quadraticBezierTo(
        prev.dx, prev.dy, (prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
  }
  path.lineTo(left.last.dx, left.last.dy);
  path.lineTo(right.last.dx, right.last.dy);
  for (int i = right.length - 2; i >= 0; i--) {
    final prev = right[i + 1];
    final curr = right[i];
    path.quadraticBezierTo(
        prev.dx, prev.dy, (prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
  }
  path.lineTo(right[0].dx, right[0].dy);
  path.close();
  return path;
}

/// Create anisotropic highlight paint — a traveling specular band
/// that shifts with sway for a living shimmer effect.
Paint _anisotropicHighlightPaint(
    Color color, bool isRainbow, Rect bounds, double swayValue) {
  final hlColor =
      _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color, 0.35);
  final bandCenter = 0.25 + sin(swayValue * pi) * 0.15;
  return Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        hlColor.withValues(alpha: 0.0),
        hlColor.withValues(alpha: 0.22),
        hlColor.withValues(alpha: 0.32),
        hlColor.withValues(alpha: 0.22),
        hlColor.withValues(alpha: 0.0),
      ],
      stops: [
        (bandCenter - 0.15).clamp(0.0, 1.0),
        (bandCenter - 0.05).clamp(0.0, 1.0),
        bandCenter.clamp(0.0, 1.0),
        (bandCenter + 0.05).clamp(0.0, 1.0),
        (bandCenter + 0.15).clamp(0.0, 1.0),
      ],
    ).createShader(bounds);
}

/// Draw a strand group (3-5 strands offset for volume).
/// Reusable helper — new styles can call this with different control points.
void _drawStrandGroup(
  Canvas canvas,
  List<Offset> centerPoints,
  double baseWidth,
  Paint fillPaint,
  Paint? highlightPaint, {
  int strandCount = 4,
  double spreadFactor = 0.3,
}) {
  for (int s = 0; s < strandCount; s++) {
    final offset = (s - strandCount / 2) * baseWidth * spreadFactor;
    final strandPoints =
        centerPoints.map((p) => Offset(p.dx + offset, p.dy)).toList();
    final path = _buildStrand(strandPoints, baseWidth * 0.6);
    canvas.drawPath(path, fillPaint);
  }
  if (highlightPaint != null) {
    final hlPath = _buildStrand(centerPoints, baseWidth * 0.3);
    canvas.drawPath(hlPath, highlightPaint);
  }
}

// ── Face edge data ──────────────────────────────────────────────────

typedef _BackEdge = ({double left, double right, double top});
typedef _FrontEdge = ({
  double oL,
  double oR,
  double oB,
  double iL,
  double iR,
  double iT
});

_BackEdge _backEdge(int faceShape) {
  switch (faceShape) {
    case 1:
      return (left: 0.16, right: 0.84, top: 0.19);
    case 2:
      return (left: 0.22, right: 0.78, top: 0.18);
    case 3:
      return (left: 0.20, right: 0.80, top: 0.19);
    case 4:
      return (left: 0.26, right: 0.74, top: 0.18);
    default:
      return (left: 0.18, right: 0.82, top: 0.19);
  }
}

_FrontEdge _frontEdge(int faceShape) {
  switch (faceShape) {
    case 1:
      return (
        oL: 0.12, oR: 0.88, oB: 0.38, iL: 0.16, iR: 0.84, iT: 0.20
      );
    case 2:
      return (
        oL: 0.14, oR: 0.86, oB: 0.36, iL: 0.22, iR: 0.78, iT: 0.19
      );
    case 3:
      return (
        oL: 0.12, oR: 0.88, oB: 0.37, iL: 0.18, iR: 0.82, iT: 0.20
      );
    case 4:
      return (
        oL: 0.14, oR: 0.86, oB: 0.36, iL: 0.24, iR: 0.76, iT: 0.19
      );
    default:
      return (
        oL: 0.13, oR: 0.87, oB: 0.37, iL: 0.18, iR: 0.82, iT: 0.20
      );
  }
}

// ======================================================================
//  HAIR BACK PAINTER — renders behind face
// ======================================================================

/// Renders the back layer of hair (behind the face).
///
/// Single perfected medium-length natural style with organic bezier curves,
/// strand texture, and sway/wind/bounce animation.
///
/// Parameters:
/// - [swayValue] 0.0-1.0 from idle sway AnimationController
/// - [windStrength] 0.0-1.0 for celebration wind effect (0 = none, 1 = strong)
/// - [bounceValue] 0.0-1.0 for jump/celebrate vertical bounce
class HairBackPainter extends CustomPainter {
  final int style;
  final Color color;
  final bool isRainbow;
  final int faceShape;
  final double swayValue;
  final double windStrength;
  final double bounceValue;

  HairBackPainter({
    required this.style,
    required this.color,
    this.isRainbow = false,
    this.faceShape = 0,
    this.swayValue = 0.0,
    this.windStrength = 0.0,
    this.bounceValue = 0.0,
    super.repaint,
  });

  // Cached paints (allocated once, not per-frame)
  static final Paint _shadowPaint = Paint()
    ..color = const Color(0xFF0A0A1A).withValues(alpha: 0.18)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  Paint _massPaint(Rect bounds) {
    if (isRainbow) {
      return Paint()
        ..shader = const SweepGradient(
          center: Alignment.center,
          colors: _rainbowColors,
        ).createShader(bounds);
    }
    final hi = _warmHighlight(color);
    final mid = _midTone(color);
    final sh = _coolShadow(color);
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [hi, mid, color, sh],
        stops: const [0.0, 0.25, 0.55, 1.0],
      ).createShader(bounds);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ie = _backEdge(faceShape);
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final paint = _massPaint(bounds)..style = PaintingStyle.fill;
    final hlPaint =
        _anisotropicHighlightPaint(color, isRainbow, bounds, swayValue);

    // All styles render the same single perfected natural style.
    _drawNaturalBack(canvas, w, h, ie, paint, hlPaint);
  }

  /// Medium-length natural hair — organic dome with flowing side strands.
  void _drawNaturalBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, 0, windStrength);
    final sway1 = _computeSway(swayValue, 1, windStrength);
    final sway2 = _computeSway(swayValue, 2, windStrength);
    final bounce0 = _computeBounce(bounceValue, 0);

    // ── Shadow silhouette ──
    final shadowPath = Path()
      ..moveTo(w * (0.08 + sway0), h * (0.72 + bounce0))
      ..cubicTo(w * 0.06, h * 0.50, w * 0.08, h * 0.18,
          w * 0.50, h * 0.04)
      ..cubicTo(w * 0.92, h * 0.18, w * 0.94, h * 0.50,
          w * (0.92 + sway0), h * (0.72 + bounce0))
      ..close();
    canvas.drawPath(shadowPath, _shadowPaint);

    // ── Main hair volume dome ──
    // Organic dome extending slightly beyond head bounds for volume.
    final massPath = Path()
      ..moveTo(w * (0.07 + sway0), h * (0.70 + bounce0))
      // Left contour — cubic curve rising from bottom-left to crown
      ..cubicTo(
          w * 0.05, h * 0.48,
          w * 0.07, h * 0.14,
          w * 0.50, h * 0.03)
      // Right contour — crown down to bottom-right
      ..cubicTo(
          w * 0.93, h * 0.14,
          w * 0.95, h * 0.48,
          w * (0.93 + sway0), h * (0.70 + bounce0))
      // Inward sweep connecting to face edge (right side)
      ..cubicTo(
          w * (0.91 + sway0 * 0.5), h * 0.76,
          w * ie.right, h * 0.72,
          w * ie.right, h * 0.35)
      // Along head top (right to left)
      ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
      ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
      // Inward sweep connecting to face edge (left side)
      ..cubicTo(
          w * ie.left, h * 0.72,
          w * (0.09 + sway0 * 0.5), h * 0.76,
          w * (0.07 + sway0), h * (0.70 + bounce0))
      ..close();
    canvas.drawPath(massPath, paint);

    // ── Side strand curtains (left) ──
    // 3 strand groups for volume, each with follow-through phase offset.
    for (int s = 0; s < 3; s++) {
      final phase = s;
      final sSway = _computeSway(swayValue, phase, windStrength);
      final sBounce = _computeBounce(bounceValue, phase);
      final xBase = ie.left - 0.01 + s * 0.015;
      final strand = [
        Offset(w * xBase, h * 0.24),
        Offset(w * (xBase - 0.02 + sSway * 0.3), h * (0.38 + sBounce * 0.2)),
        Offset(w * (xBase - 0.04 + sSway * 0.6), h * (0.52 + sBounce * 0.4)),
        Offset(w * (xBase - 0.05 + sSway * 0.8), h * (0.65 + sBounce * 0.6)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.032, paint, hlPaint,
          strandCount: 3, spreadFactor: 0.5);
    }

    // ── Side strand curtains (right) ──
    for (int s = 0; s < 3; s++) {
      final phase = s + 2;
      final sSway = _computeSway(swayValue, phase, windStrength);
      final sBounce = _computeBounce(bounceValue, phase);
      final xBase = ie.right + 0.01 - s * 0.015;
      final strand = [
        Offset(w * xBase, h * 0.24),
        Offset(w * (xBase + 0.02 + sSway * 0.3), h * (0.38 + sBounce * 0.2)),
        Offset(w * (xBase + 0.04 + sSway * 0.6), h * (0.52 + sBounce * 0.4)),
        Offset(w * (xBase + 0.05 + sSway * 0.8), h * (0.65 + sBounce * 0.6)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.032, paint, hlPaint,
          strandCount: 3, spreadFactor: 0.5);
    }

    // ── Subtle wavy texture lines on the dome ──
    // 2-3 wavy lines suggesting strand direction.
    final texPaint = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final xOff = -0.06 + i * 0.06;
      final iSway = _computeSway(swayValue, i, windStrength);
      final wavyLine = Path()
        ..moveTo(w * (0.35 + xOff), h * 0.12)
        ..cubicTo(
            w * (0.38 + xOff + iSway * 0.2), h * 0.22,
            w * (0.32 + xOff + iSway * 0.4), h * 0.35,
            w * (0.30 + xOff + sway1 * 0.5), h * 0.48)
        ..cubicTo(
            w * (0.28 + xOff + sway2 * 0.6), h * 0.56,
            w * (0.26 + xOff + sway2 * 0.7), h * 0.62,
            w * (0.24 + xOff + sway2 * 0.8), h * (0.68 + bounce0 * 0.3));
      canvas.drawPath(wavyLine, texPaint);
    }
  }

  @override
  bool shouldRepaint(HairBackPainter old) =>
      old.style != style ||
      old.color != color ||
      old.isRainbow != isRainbow ||
      old.faceShape != faceShape ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.windStrength * 100).round() != (windStrength * 100).round() ||
      (old.bounceValue * 100).round() != (bounceValue * 100).round();
}

// ======================================================================
//  HAIR FRONT PAINTER — renders on top of face
// ======================================================================

/// Renders the front layer of hair (on top of face).
///
/// Single perfected medium-length natural style with side-swept bangs,
/// individual strand groups, shine streak, and sway animation.
///
/// Parameters:
/// - [swayValue] 0.0-1.0 from idle sway AnimationController
/// - [windStrength] 0.0-1.0 for celebration wind effect (0 = none, 1 = strong)
/// - [bounceValue] 0.0-1.0 for jump/celebrate vertical bounce
class HairFrontPainter extends CustomPainter {
  final int style;
  final Color color;
  final bool isRainbow;
  final int faceShape;
  final double swayValue;
  final double windStrength;
  final double bounceValue;

  HairFrontPainter({
    required this.style,
    required this.color,
    this.isRainbow = false,
    this.faceShape = 0,
    this.swayValue = 0.0,
    this.windStrength = 0.0,
    this.bounceValue = 0.0,
    super.repaint,
  });

  // Cached paints
  static final Paint _contactShadow = Paint()
    ..color = const Color(0xFF0A0A1A).withValues(alpha: 0.12)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  Paint _massPaint(Rect bounds) {
    if (isRainbow) {
      return Paint()
        ..shader = const SweepGradient(
          center: Alignment.center,
          colors: _rainbowColors,
        ).createShader(bounds);
    }
    final hi = _warmHighlight(color);
    final mid = _midTone(color);
    final sh = _coolShadow(color);
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [hi, mid, color, sh],
        stops: const [0.0, 0.20, 0.50, 1.0],
      ).createShader(bounds);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final e = _frontEdge(faceShape);
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final paint = _massPaint(bounds)..style = PaintingStyle.fill;
    final hlPaint =
        _anisotropicHighlightPaint(color, isRainbow, bounds, swayValue);

    // All styles render the same single perfected natural style.
    _drawNaturalFront(canvas, w, h, e, paint, hlPaint);

    // ── Hair shimmer shader overlay ──
    if (!isRainbow) {
      final hairShader = ShaderLoader.hairShimmer;
      if (hairShader != null) {
        hairShader.setFloat(0, w); // uSize.x
        hairShader.setFloat(1, h); // uSize.y
        hairShader.setFloat(2, swayValue * 0.8); // uTime
        hairShader.setFloat(3, swayValue); // uSway
        // Clip to hair cap region
        final clipPath = Path()
          ..moveTo(w * e.oL, h * e.oB)
          ..cubicTo(
              w * e.oL, h * 0.12, w * 0.30, h * 0.06, w * 0.50, h * 0.055)
          ..cubicTo(
              w * 0.70, h * 0.06, w * e.oR, h * 0.12, w * e.oR, h * e.oB)
          ..lineTo(w * e.iR, h * 0.28)
          ..quadraticBezierTo(
              w * e.iR, h * e.iT, w * 0.50, h * (e.iT + 0.02))
          ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
          ..close();
        canvas.save();
        canvas.clipPath(clipPath);
        canvas.drawRect(
          bounds,
          Paint()..shader = hairShader,
        );
        canvas.restore();
      }
    }
  }

  /// The single perfected natural medium-length style with side-swept bangs.
  void _drawNaturalFront(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, 0, windStrength);
    final sway1 = _computeSway(swayValue, 1, windStrength);

    // ── Hair cap (covers top of head) ──
    _drawHairCap(canvas, paint, w, h, e, hlPaint);

    // ── Side-swept bangs ──
    // 5 individual strand groups sweeping from right to left across forehead.
    // Each strand is built from bezier control points for organic curves.
    // Strands vary in thickness and length for natural appearance.

    // Strand group 1: rightmost, short wispy strand
    {
      final strand = [
        Offset(w * 0.62, h * 0.09),
        Offset(w * (0.58 + sway0 * 0.15), h * 0.14),
        Offset(w * (0.52 + sway0 * 0.20), h * (e.iT + 0.02)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.018, paint, hlPaint,
          strandCount: 3, spreadFactor: 0.4);
    }

    // Strand group 2: mid-right, medium length
    {
      final strand = [
        Offset(w * 0.56, h * 0.08),
        Offset(w * (0.48 + sway0 * 0.18), h * 0.13),
        Offset(w * (0.40 + sway0 * 0.22), h * 0.18),
        Offset(w * (0.36 + sway1 * 0.25), h * (e.iT + 0.04)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.022, paint, hlPaint,
          strandCount: 3, spreadFactor: 0.35);
    }

    // Strand group 3: center, longest — the main bang sweep
    {
      final strand = [
        Offset(w * 0.50, h * 0.07),
        Offset(w * (0.42 + sway0 * 0.15), h * 0.12),
        Offset(w * (0.34 + sway0 * 0.22), h * 0.18),
        Offset(w * (0.28 + sway1 * 0.28), h * 0.24),
        Offset(w * (0.24 + sway1 * 0.30), h * (e.oB - 0.02)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.026, paint, null,
          strandCount: 4, spreadFactor: 0.3);
    }

    // Strand group 4: mid-left, medium
    {
      final strand = [
        Offset(w * 0.44, h * 0.08),
        Offset(w * (0.38 + sway0 * 0.12), h * 0.14),
        Offset(w * (0.32 + sway0 * 0.18), h * 0.20),
        Offset(w * (0.28 + sway1 * 0.22), h * (e.iT + 0.06)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.020, paint, hlPaint,
          strandCount: 3, spreadFactor: 0.35);
    }

    // Strand group 5: leftmost, short wispy
    {
      final strand = [
        Offset(w * 0.38, h * 0.09),
        Offset(w * (0.34 + sway0 * 0.10), h * 0.15),
        Offset(w * (0.30 + sway0 * 0.15), h * (e.iT + 0.03)),
      ];
      _drawStrandGroup(canvas, strand, w * 0.016, paint, hlPaint,
          strandCount: 2, spreadFactor: 0.4);
    }

    // ── Shine streak ──
    // One lighter streak across the main bang for specular highlight.
    final shinePaint = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color, 0.40)
          .withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.010
      ..strokeCap = StrokeCap.round;

    final shineStreak = Path()
      ..moveTo(w * 0.54, h * 0.085)
      ..cubicTo(
          w * (0.46 + sway0 * 0.10), h * 0.12,
          w * (0.38 + sway0 * 0.18), h * 0.17,
          w * (0.30 + sway1 * 0.24), h * 0.23);
    canvas.drawPath(shineStreak, shinePaint);

    // ── Forehead contact shadow beneath bangs ──
    final bangShadow = Path()
      ..moveTo(w * e.iL, h * (e.iT + 0.01))
      ..cubicTo(
          w * (e.iL + 0.05), h * (e.iT + 0.04),
          w * 0.45, h * (e.iT + 0.05),
          w * 0.55, h * (e.iT + 0.03))
      ..cubicTo(
          w * 0.65, h * (e.iT + 0.01),
          w * (e.iR - 0.05), h * e.iT,
          w * e.iR, h * (e.iT + 0.01))
      ..close();
    canvas.drawPath(bangShadow, _contactShadow);
  }

  /// Hair cap — the solid top portion covering the crown.
  void _drawHairCap(Canvas canvas, Paint paint, double w, double h,
      _FrontEdge e, Paint hlPaint) {
    final sway = _computeSway(swayValue, 0, windStrength);

    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      // Left side rising to crown — organic dome curve
      ..cubicTo(
          w * e.oL, h * 0.12,
          w * 0.30, h * (0.06 + sway * 0.15),
          w * 0.50, h * 0.055)
      // Crown to right side
      ..cubicTo(
          w * 0.70, h * (0.06 + sway * 0.15),
          w * e.oR, h * 0.12,
          w * e.oR, h * e.oB)
      // Hairline inner edge (right to left)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(
          w * e.iR, h * e.iT, w * 0.50, h * (e.iT + 0.02))
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
      ..close();

    // Contact shadow on forehead
    final shadowPath = Path()
      ..moveTo(w * e.iL, h * 0.28)
      ..quadraticBezierTo(
          w * e.iL, h * (e.iT + 0.03), w * 0.50, h * (e.iT + 0.05))
      ..quadraticBezierTo(
          w * e.iR, h * (e.iT + 0.03), w * e.iR, h * 0.28)
      ..close();
    canvas.drawPath(shadowPath, _contactShadow);

    canvas.drawPath(path, paint);

    // Anisotropic cap highlight — warm band across the crown
    final capHl = Path()
      ..moveTo(w * (e.oL + 0.04), h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.10, w * (e.oR - 0.04), h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.14, w * (e.oL + 0.04), h * 0.18)
      ..close();
    canvas.drawPath(capHl, hlPaint);
  }

  @override
  bool shouldRepaint(HairFrontPainter old) =>
      old.style != style ||
      old.color != color ||
      old.isRainbow != isRainbow ||
      old.faceShape != faceShape ||
      (old.swayValue * 100).round() != (swayValue * 100).round() ||
      (old.windStrength * 100).round() != (windStrength * 100).round() ||
      (old.bounceValue * 100).round() != (bounceValue * 100).round();
}

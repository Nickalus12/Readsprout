import 'dart:math';
import 'package:flutter/material.dart';

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

// ── Per-style amplitude tables ──────────────────────────────────────

/// Sway amplitude per style (longer = more sway).
const List<double> _swayAmplitudes = [
  0.006, // 0 Short
  0.030, // 1 Long
  0.012, // 2 Curly
  0.018, // 3 Braids
  0.028, // 4 Ponytail
  0.002, // 5 Buzz
  0.008, // 6 Afro
  0.006, // 7 Bun
  0.018, // 8 Pigtails
  0.014, // 9 Bob
  0.024, // 10 Wavy
  0.016, // 11 Side Swept
  0.004, // 12 Mohawk
  0.014, // 13 Space Buns
  0.035, // 14 Long Wavy
  0.030, // 15 Fishtail
];

/// Wind sensitivity per style (longer/lighter = more billowing).
const List<double> _windSensitivity = [
  0.02, // 0 Short
  0.12, // 1 Long
  0.05, // 2 Curly
  0.06, // 3 Braids
  0.10, // 4 Ponytail
  0.01, // 5 Buzz
  0.03, // 6 Afro
  0.02, // 7 Bun
  0.07, // 8 Pigtails
  0.06, // 9 Bob
  0.10, // 10 Wavy
  0.07, // 11 Side Swept
  0.02, // 12 Mohawk
  0.04, // 13 Space Buns
  0.14, // 14 Long Wavy
  0.10, // 15 Fishtail
];

/// Bounce sensitivity per style (heavy tops barely move, tails swing up).
const List<double> _bounceSensitivity = [
  0.01, // 0 Short
  0.06, // 1 Long
  0.03, // 2 Curly
  0.05, // 3 Braids
  0.10, // 4 Ponytail
  0.005, // 5 Buzz
  0.02, // 6 Afro
  0.03, // 7 Bun
  0.09, // 8 Pigtails
  0.04, // 9 Bob
  0.07, // 10 Wavy
  0.04, // 11 Side Swept
  0.01, // 12 Mohawk
  0.06, // 13 Space Buns
  0.08, // 14 Long Wavy
  0.07, // 15 Fishtail
];

/// Phase offsets for follow-through delay between strand groups.
const List<double> _phaseOffsets = [0.0, 0.3, 0.6, 0.9, 1.2];

// ── Shared geometry helpers ─────────────────────────────────────────

/// Compute sway offset with follow-through phase, wind, and bounce.
double _computeSway(double swayValue, int styleIndex,
    [int phase = 0, double windStrength = 0.0]) {
  final amp = _swayAmplitudes[styleIndex.clamp(0, 15)];
  final offset = _phaseOffsets[phase.clamp(0, 4)];
  final baseSway = sin(swayValue * pi + offset) * amp;
  // Wind pushes hair to the right (positive X)
  final wind =
      windStrength * _windSensitivity[styleIndex.clamp(0, 15)];
  return baseSway + wind;
}

/// Compute vertical bounce offset. Positive = hair moves up (lag behind
/// downward head motion). Value oscillates based on bounceValue.
double _computeBounce(
    double bounceValue, int styleIndex, [int phase = 0]) {
  if (bounceValue <= 0.001) return 0.0;
  final sens = _bounceSensitivity[styleIndex.clamp(0, 15)];
  final offset = _phaseOffsets[phase.clamp(0, 4)];
  // Squash on way up (negative), stretch on way down (positive)
  return sin(bounceValue * pi * 2 + offset) * sens * bounceValue;
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

/// Draw a single spiral curl (helix-like bezier path).
void _drawSpiralCurl(Canvas canvas, double cx, double cy, double radius,
    Paint hlPaint, Paint shPaint,
    {double turns = 1.5, int segments = 6}) {
  final spiral = Path();
  for (int i = 0; i <= segments; i++) {
    final t = i / segments;
    final angle = t * pi * 2 * turns;
    final r = radius * (1.0 - t * 0.55);
    final x = cx + r * cos(angle);
    final y = cy + r * sin(angle);
    if (i == 0) {
      spiral.moveTo(x, y);
    } else {
      final prevT = (i - 1) / segments;
      final prevAngle = prevT * pi * 2 * turns;
      final midAngle = (prevAngle + angle) / 2;
      final midR = radius * (1.0 - ((prevT + t) / 2) * 0.55) * 1.12;
      spiral.quadraticBezierTo(
          cx + midR * cos(midAngle), cy + midR * sin(midAngle), x, y);
    }
  }
  // Outer-curve highlight on the spiral
  canvas.drawPath(spiral.shift(const Offset(0.5, 0.5)), shPaint);
  canvas.drawPath(spiral, hlPaint);
}

/// Draw a small hair tie band.
void _drawHairTie(Canvas canvas, Offset center, double radius, Color baseColor,
    {bool showHighlight = true}) {
  // Band
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = _coolShadow(baseColor, 0.45)
      ..style = PaintingStyle.fill,
  );
  // Highlight on tie
  if (showHighlight) {
    canvas.drawCircle(
      center.translate(-radius * 0.3, -radius * 0.3),
      radius * 0.35,
      Paint()
        ..color = _warmHighlight(baseColor, 0.30).withValues(alpha: 0.40),
    );
  }
}

/// Draw a shine spot (small white oval) on a bun/space bun.
void _drawShineSpot(Canvas canvas, Offset center, double radius) {
  canvas.drawOval(
    Rect.fromCenter(
      center: center,
      width: radius * 0.55,
      height: radius * 0.35,
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.30),
  );
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

  Paint get _shadowPaint => Paint()
    ..color = const Color(0xFF0A0A1A).withValues(alpha: 0.18)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ie = _backEdge(faceShape);
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final paint = _massPaint(bounds)..style = PaintingStyle.fill;
    final hlPaint =
        _anisotropicHighlightPaint(color, isRainbow, bounds, swayValue);

    switch (style) {
      case 1:
        _drawLongBack(canvas, w, h, ie, paint, hlPaint);
      case 3:
        _drawBraidsBack(canvas, w, h, ie, paint, hlPaint);
      case 4:
        _drawPonytailBack(canvas, w, h, ie, paint, hlPaint);
      case 9:
        _drawBobBack(canvas, w, h, ie, paint);
      case 10:
        _drawWavyBack(canvas, w, h, ie, paint, hlPaint);
      case 14:
        _drawLongWavyBack(canvas, w, h, ie, paint, hlPaint);
      case 15:
        _drawFishtailBack(canvas, w, h, ie, paint, hlPaint);
    }
  }

  // ── Long back (style 1) ──

  void _drawLongBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, style, 0, windStrength);
    final sway1 = _computeSway(swayValue, style, 1, windStrength);
    final bounce0 = _computeBounce(bounceValue, style, 0);

    // Shadow
    final shadowPath = Path()
      ..moveTo(w * (0.09 + sway0), h * (0.77 + bounce0))
      ..cubicTo(w * 0.08, h * 0.55, w * 0.09, h * 0.20, w * 0.50, h * 0.06)
      ..cubicTo(w * 0.91, h * 0.20, w * 0.92, h * 0.55,
          w * (0.91 + sway0), h * (0.77 + bounce0))
      ..close();
    canvas.drawPath(shadowPath, _shadowPaint);

    // Left strand curtain
    final leftStrand = [
      Offset(w * ie.left, h * 0.22),
      Offset(w * (0.12 + sway1 * 0.3), h * (0.40 + bounce0 * 0.3)),
      Offset(w * (0.11 + sway0 * 0.6), h * (0.58 + bounce0 * 0.5)),
      Offset(w * (0.10 + sway0), h * (0.74 + bounce0)),
    ];
    _drawStrandGroup(canvas, leftStrand, w * 0.04, paint, hlPaint,
        strandCount: 4, spreadFactor: 0.6);

    // Right strand curtain
    final rightStrand = [
      Offset(w * ie.right, h * 0.22),
      Offset(w * (0.88 + sway1 * 0.3), h * (0.40 + bounce0 * 0.3)),
      Offset(w * (0.89 + sway0 * 0.6), h * (0.58 + bounce0 * 0.5)),
      Offset(w * (0.90 + sway0), h * (0.74 + bounce0)),
    ];
    _drawStrandGroup(canvas, rightStrand, w * 0.04, paint, hlPaint,
        strandCount: 4, spreadFactor: 0.6);

    // Fill mass
    final massPath = Path()
      ..moveTo(w * (0.08 + sway0), h * (0.76 + bounce0))
      ..cubicTo(w * 0.08, h * 0.50, w * 0.09, h * 0.15, w * 0.50, h * 0.05)
      ..cubicTo(w * 0.91, h * 0.15, w * 0.92, h * 0.50,
          w * (0.92 + sway0), h * (0.76 + bounce0))
      ..cubicTo(w * (0.90 + sway0), h * 0.82, w * ie.right, h * 0.78,
          w * ie.right, h * 0.35)
      ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
      ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
      ..cubicTo(w * ie.left, h * 0.78, w * (0.10 + sway0), h * 0.82,
          w * (0.08 + sway0), h * (0.76 + bounce0))
      ..close();
    canvas.drawPath(massPath, paint);
  }

  // ── Braids back (style 3) — 3-strand weave pattern ──

  void _drawBraidsBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    for (int side = 0; side < 2; side++) {
      final baseX = side == 0 ? 0.16 : 0.84;
      for (int seg = 0; seg < 4; seg++) {
        final phase = side == 0 ? seg : seg + 2;
        final segSway =
            _computeSway(swayValue, style, phase % 5, windStrength);
        final segBounce = _computeBounce(bounceValue, style, phase % 5);
        final y = h * (0.40 + seg * 0.11) + segBounce * h;
        final xOff = (seg.isEven ? -1 : 1) * w * 0.018 + segSway * w;
        final center = Offset(w * baseX + xOff, y);

        // Shadow
        canvas.drawOval(
          Rect.fromCenter(
            center: center.translate(w * 0.005, h * 0.008),
            width: w * 0.085,
            height: h * 0.095,
          ),
          _shadowPaint,
        );

        // 3 overlapping strand sections for weave illusion
        for (int strand = 0; strand < 3; strand++) {
          final sOff = (strand - 1) * w * 0.012;
          final vert = (strand == 1) ? -h * 0.008 : h * 0.004;
          canvas.drawOval(
            Rect.fromCenter(
              center: center.translate(sOff, vert),
              width: w * 0.04,
              height: h * 0.07,
            ),
            paint,
          );
        }

        // Cross-weave highlight
        final hlStroke = Paint()
          ..color =
              _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
                  .withValues(alpha: 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008
          ..strokeCap = StrokeCap.round;
        final dir = seg.isEven ? 1.0 : -1.0;
        canvas.drawLine(
          center.translate(-w * 0.025 * dir, -h * 0.025),
          center.translate(w * 0.025 * dir, h * 0.025),
          hlStroke,
        );
      }
      // Braid tie at bottom
      final tieY = h * (0.40 + 4 * 0.11);
      final tieSway = _computeSway(swayValue, style, 3, windStrength);
      _drawHairTie(canvas, Offset(w * baseX + tieSway * w, tieY), w * 0.022,
          isRainbow ? const Color(0xFF9B59B6) : color);
    }
  }

  // ── Ponytail back (style 4) — pendulum motion ──

  void _drawPonytailBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, style, 0, windStrength);
    final sway1 = _computeSway(swayValue, style, 1, windStrength);
    final sway2 = _computeSway(swayValue, style, 2, windStrength);
    final bounce0 = _computeBounce(bounceValue, style, 0);
    final bounce1 = _computeBounce(bounceValue, style, 1);

    // Ponytail swings up on bounce
    final tailCenter = [
      Offset(w * 0.50, h * 0.14),
      Offset(w * (0.52 + sway0 * 0.5), h * (0.30 + bounce0 * 0.5)),
      Offset(w * (0.54 + sway1), h * (0.48 - bounce1 * 0.8)),
      Offset(w * (0.53 + sway2 * 1.5), h * (0.65 - bounce0 * 1.2)),
      Offset(w * (0.50 + sway2 * 2.0), h * (0.78 - bounce0 * 1.5)),
    ];

    // Shadow
    final shadowPoints =
        tailCenter.map((p) => p.translate(w * 0.01, h * 0.01)).toList();
    canvas.drawPath(_buildStrand(shadowPoints, w * 0.06), _shadowPaint);

    // Main tail strands
    _drawStrandGroup(canvas, tailCenter, w * 0.045, paint, hlPaint,
        strandCount: 5, spreadFactor: 0.35);

    // Hair tie at base
    _drawHairTie(canvas, Offset(w * 0.50, h * 0.16), w * 0.025,
        isRainbow ? const Color(0xFF9B59B6) : color);
  }

  // ── Bob back (style 9) ──

  void _drawBobBack(
      Canvas canvas, double w, double h, _BackEdge ie, Paint paint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);
    final bounce = _computeBounce(bounceValue, style, 0);
    final path = Path()
      ..moveTo(w * (0.10 + sway * 0.4), h * (0.56 + bounce * 0.3))
      ..cubicTo(w * 0.08, h * 0.35, w * 0.12, h * 0.10, w * 0.50, h * 0.05)
      ..cubicTo(w * 0.88, h * 0.10, w * 0.92, h * 0.35,
          w * (0.90 + sway * 0.4), h * (0.56 + bounce * 0.3))
      ..cubicTo(w * 0.88, h * 0.62, w * ie.right, h * 0.58, w * ie.right,
          h * 0.35)
      ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
      ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
      ..cubicTo(w * ie.left, h * 0.58, w * 0.12, h * 0.62,
          w * (0.10 + sway * 0.4), h * (0.56 + bounce * 0.3))
      ..close();

    canvas.drawPath(path.shift(Offset(w * 0.005, h * 0.005)), _shadowPaint);
    canvas.drawPath(path, paint);
  }

  // ── Wavy back (style 10) ──

  void _drawWavyBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, style, 0, windStrength);
    final sway1 = _computeSway(swayValue, style, 1, windStrength);
    final bounce = _computeBounce(bounceValue, style, 0);

    final path = Path()
      ..moveTo(w * (0.07 + sway0), h * (0.79 + bounce))
      ..cubicTo(w * (0.04 + sway1 * 0.3), h * 0.68,
          w * (0.06 + sway1 * 0.2), h * 0.52, w * 0.10, h * 0.32)
      ..quadraticBezierTo(w * 0.10, h * 0.08, w * 0.50, h * 0.05)
      ..quadraticBezierTo(w * 0.90, h * 0.08, w * 0.90, h * 0.32)
      ..cubicTo(w * 0.94, h * 0.52, w * (0.96 + sway1 * 0.2), h * 0.68,
          w * (0.93 + sway0), h * (0.79 + bounce))
      ..cubicTo(w * (0.89 + sway0), h * 0.86,
          w * (0.84 + sway0 * 0.5), h * 0.80, w * ie.right, h * 0.35)
      ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
      ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
      ..cubicTo(w * (0.16 + sway0 * 0.5), h * 0.80,
          w * (0.11 + sway0), h * 0.86, w * (0.07 + sway0), h * (0.79 + bounce))
      ..close();

    canvas.drawPath(path.shift(Offset(w * 0.005, h * 0.005)), _shadowPaint);
    canvas.drawPath(path, paint);

    // Strand highlights
    for (int side = 0; side < 2; side++) {
      for (int s = 0; s < 3; s++) {
        final phase = side * 2 + s;
        final sSway = _computeSway(swayValue, style, phase % 5, windStrength);
        final baseX = side == 0 ? 0.12 + s * 0.02 : 0.88 - s * 0.02;
        final strand = [
          Offset(w * baseX, h * 0.36),
          Offset(w * (baseX + sSway * 0.4), h * 0.50),
          Offset(w * (baseX + sSway * 0.7), h * 0.64),
          Offset(w * (baseX + sSway), h * (0.76 + bounce * 0.5)),
        ];
        canvas.drawPath(_buildStrand(strand, w * 0.012), hlPaint);
      }
    }
  }

  // ── Long Wavy back (style 14) — S-curve cascading strands ──

  void _drawLongWavyBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final sway0 = _computeSway(swayValue, style, 0, windStrength);
    final sway1 = _computeSway(swayValue, style, 1, windStrength);
    final bounce = _computeBounce(bounceValue, style, 0);

    // Main mass
    final path = Path()
      ..moveTo(w * (0.05 + sway0), h * (0.90 + bounce))
      ..cubicTo(w * (0.03 + sway1 * 0.3), h * 0.72, w * 0.05, h * 0.45,
          w * 0.10, h * 0.32)
      ..quadraticBezierTo(w * 0.10, h * 0.08, w * 0.50, h * 0.05)
      ..quadraticBezierTo(w * 0.90, h * 0.08, w * 0.90, h * 0.32)
      ..cubicTo(w * 0.95, h * 0.45, w * (0.97 + sway1 * 0.3), h * 0.72,
          w * (0.95 + sway0), h * (0.90 + bounce))
      ..cubicTo(w * (0.91 + sway0), h * 0.96,
          w * (0.84 + sway0 * 0.5), h * 0.88, w * ie.right, h * 0.35)
      ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
      ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
      ..cubicTo(w * (0.16 + sway0 * 0.5), h * 0.88,
          w * (0.09 + sway0), h * 0.96, w * (0.05 + sway0), h * (0.90 + bounce))
      ..close();

    canvas.drawPath(path.shift(Offset(w * 0.005, h * 0.006)), _shadowPaint);
    canvas.drawPath(path, paint);

    // Flowing S-curve strand groups — each offset in phase
    for (int side = 0; side < 2; side++) {
      for (int s = 0; s < 4; s++) {
        final phase = side * 3 + s;
        final sSway0 = _computeSway(swayValue, style, phase % 5, windStrength);
        final sSway1 =
            _computeSway(swayValue, style, (phase + 1) % 5, windStrength);
        final sSway2 =
            _computeSway(swayValue, style, (phase + 2) % 5, windStrength);
        final baseX = side == 0 ? 0.11 + s * 0.015 : 0.89 - s * 0.015;
        final dir = side == 0 ? 1.0 : -1.0;
        // S-curve: alternating left-right offsets down the strand
        final strand = [
          Offset(w * baseX, h * 0.34),
          Offset(w * (baseX + dir * 0.015 + sSway0 * 0.3), h * 0.46),
          Offset(w * (baseX - dir * 0.010 + sSway1 * 0.6), h * 0.58),
          Offset(w * (baseX + dir * 0.012 + sSway2 * 0.8), h * 0.70),
          Offset(w * (baseX - dir * 0.008 + sSway2 * 1.0),
              h * (0.84 + bounce * 0.5)),
        ];
        canvas.drawPath(_buildStrand(strand, w * 0.009), hlPaint);
      }
    }
  }

  // ── Fishtail back (style 15) — crosshatch V-pattern ──

  void _drawFishtailBack(Canvas canvas, double w, double h, _BackEdge ie,
      Paint paint, Paint hlPaint) {
    final hlStroke = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;

    for (int seg = 0; seg < 6; seg++) {
      final segSway =
          _computeSway(swayValue, style, seg % 5, windStrength);
      final segBounce = _computeBounce(bounceValue, style, seg % 5);
      final y = h * (0.28 + seg * 0.10) + segBounce * h;
      final xCenter = w * 0.50 + segSway * w * (seg + 1) * 0.6;
      final segWidth = w * (0.10 - seg * 0.008);

      // Shadow
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(xCenter + w * 0.004, y + h * 0.006),
          width: segWidth + w * 0.01,
          height: h * 0.085,
        ),
        _shadowPaint,
      );

      // Left V-half
      final leftV = Path()
        ..moveTo(xCenter, y - h * 0.03)
        ..quadraticBezierTo(
            xCenter - segWidth * 0.6, y, xCenter - segWidth * 0.3, y + h * 0.04)
        ..quadraticBezierTo(xCenter, y + h * 0.06, xCenter, y + h * 0.03)
        ..close();
      canvas.drawPath(leftV, paint);

      // Right V-half
      final rightV = Path()
        ..moveTo(xCenter, y - h * 0.03)
        ..quadraticBezierTo(
            xCenter + segWidth * 0.6, y, xCenter + segWidth * 0.3, y + h * 0.04)
        ..quadraticBezierTo(xCenter, y + h * 0.06, xCenter, y + h * 0.03)
        ..close();
      canvas.drawPath(rightV, paint);

      // Crosshatch V-lines for braid texture
      canvas.drawLine(
        Offset(xCenter - segWidth * 0.35, y - h * 0.01),
        Offset(xCenter, y + h * 0.035),
        hlStroke,
      );
      canvas.drawLine(
        Offset(xCenter + segWidth * 0.35, y - h * 0.01),
        Offset(xCenter, y + h * 0.035),
        hlStroke,
      );

      // Highlight on alternating side
      canvas.drawPath(seg.isEven ? leftV : rightV, hlPaint);
    }

    // Tail tip
    final tipSway = _computeSway(swayValue, style, 4, windStrength);
    final tipBounce = _computeBounce(bounceValue, style, 4);
    final tipPath = Path()
      ..moveTo(w * (0.47 + tipSway * 5), h * (0.86 + tipBounce))
      ..quadraticBezierTo(w * (0.50 + tipSway * 6),
          h * (0.94 + tipBounce), w * (0.53 + tipSway * 5), h * (0.86 + tipBounce))
      ..close();
    canvas.drawPath(tipPath, paint);

    // Fishtail tie at top
    _drawHairTie(
        canvas,
        Offset(w * 0.50, h * 0.26),
        w * 0.020,
        isRainbow ? const Color(0xFF9B59B6) : color);
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

  Paint get _contactShadow => Paint()
    ..color = const Color(0xFF0A0A1A).withValues(alpha: 0.12)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final e = _frontEdge(faceShape);
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final paint = _massPaint(bounds)..style = PaintingStyle.fill;
    final hlPaint =
        _anisotropicHighlightPaint(color, isRainbow, bounds, swayValue);

    switch (style) {
      case 0:
        _drawShort(canvas, w, h, e, paint, hlPaint);
      case 1:
        _drawLongFront(canvas, w, h, e, paint, hlPaint);
      case 2:
        _drawCurly(canvas, w, h, e, paint, hlPaint);
      case 3:
        _drawBraidsFront(canvas, w, h, e, paint, hlPaint);
      case 4:
        _drawPonytailFront(canvas, w, h, e, paint, hlPaint);
      case 5:
        _drawBuzz(canvas, w, h, e, paint);
      case 6:
        _drawAfro(canvas, w, h, e, paint, hlPaint);
      case 7:
        _drawBun(canvas, w, h, e, paint, hlPaint);
      case 8:
        _drawPigtails(canvas, w, h, e, paint, hlPaint);
      case 9:
        _drawBob(canvas, w, h, e, paint, hlPaint);
      case 10:
        _drawWavyFront(canvas, w, h, e, paint, hlPaint);
      case 11:
        _drawSideSwept(canvas, w, h, e, paint, hlPaint);
      case 12:
        _drawMohawk(canvas, w, h, e, paint, hlPaint);
      case 13:
        _drawSpaceBuns(canvas, w, h, e, paint, hlPaint);
      case 14:
        _drawLongWavyFront(canvas, w, h, e, paint, hlPaint);
      case 15:
        _drawFishtailFront(canvas, w, h, e, paint, hlPaint);
    }
  }

  // ── Hair cap (shared) ──

  void _drawHairCap(Canvas canvas, Paint paint, double w, double h,
      _FrontEdge e, Paint hlPaint) {
    final path = Path()
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

    // Anisotropic cap highlight
    final capHl = Path()
      ..moveTo(w * (e.oL + 0.04), h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.10, w * (e.oR - 0.04), h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.14, w * (e.oL + 0.04), h * 0.18)
      ..close();
    canvas.drawPath(capHl, hlPaint);
  }

  /// Wispy bang strands at the hairline.
  void _drawBangStrands(Canvas canvas, double w, double h, _FrontEdge e,
      Paint hlPaint,
      {int count = 5, double startX = 0.22, double endX = 0.78}) {
    final spacing = (endX - startX) / (count - 1);
    for (int i = 0; i < count; i++) {
      final phase = i % 5;
      final sSway = _computeSway(swayValue, style, phase, windStrength);
      final x = startX + i * spacing;
      final strand = [
        Offset(w * x, h * 0.10),
        Offset(w * (x + sSway * 0.3), h * 0.16),
        Offset(w * (x + sSway * 0.2), h * (e.iT + 0.02)),
      ];
      canvas.drawPath(_buildStrand(strand, w * 0.008), hlPaint);
    }
  }

  // ── Style 0: Short ──

  void _drawShort(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);
    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      ..cubicTo(w * e.oL, h * 0.12, w * 0.30, h * (0.07 + sway * 0.2),
          w * 0.50, h * 0.04)
      ..cubicTo(w * 0.70, h * (0.07 + sway * 0.2), w * e.oR, h * 0.12,
          w * e.oR, h * e.oB)
      ..lineTo(w * e.oR, h * 0.28)
      ..quadraticBezierTo(
          w * e.iR, h * e.iT, w * 0.65, h * (e.iT + 0.04))
      ..cubicTo(w * 0.55, h * (e.iT + 0.01), w * 0.45, h * (e.iT + 0.01),
          w * 0.35, h * (e.iT + 0.04))
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.oL, h * 0.28)
      ..close();

    canvas.drawPath(path, paint);
    _drawBangStrands(canvas, w, h, e, hlPaint, count: 4);
  }

  // ── Style 1: Long front bangs ──

  void _drawLongFront(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      ..cubicTo(
          w * e.oL, h * 0.12, w * 0.30, h * 0.07, w * 0.50, h * 0.04)
      ..cubicTo(
          w * 0.70, h * 0.07, w * e.oR, h * 0.12, w * e.oR, h * e.oB)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
      ..close();

    // Contact shadow
    final shadow = Path()
      ..moveTo(w * e.iL, h * 0.26)
      ..quadraticBezierTo(w * 0.50, h * (e.iT + 0.04), w * e.iR, h * 0.26)
      ..quadraticBezierTo(w * 0.50, h * e.iT, w * e.iL, h * 0.26)
      ..close();
    canvas.drawPath(shadow, _contactShadow);

    canvas.drawPath(path, paint);
    _drawBangStrands(canvas, w, h, e, hlPaint, count: 6);
  }

  // ── Style 2: Curly — actual coil/spiral shapes ──

  void _drawCurly(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    // Main curly mass with bumpy organic silhouette
    final path = Path()..moveTo(w * 0.10, h * 0.40);
    path.cubicTo(w * 0.04, h * 0.32, w * 0.05, h * 0.22, w * 0.08, h * 0.16);
    path.cubicTo(w * 0.12, h * 0.08, w * 0.20, h * 0.04, w * 0.30, h * 0.03);
    path.cubicTo(w * 0.36, h * 0.00, w * 0.44, h * -0.01, w * 0.50, h * 0.01);
    path.cubicTo(w * 0.56, h * -0.01, w * 0.64, h * 0.00, w * 0.70, h * 0.03);
    path.cubicTo(w * 0.80, h * 0.04, w * 0.88, h * 0.08, w * 0.92, h * 0.16);
    path.cubicTo(w * 0.95, h * 0.22, w * 0.96, h * 0.32, w * 0.90, h * 0.40);
    path.cubicTo(w * 0.94, h * 0.50, w * 0.92, h * 0.54, w * 0.88, h * 0.58);
    path.lineTo(w * e.iR, h * 0.35);
    path.quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT);
    path.quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.35);
    path.lineTo(w * 0.12, h * 0.58);
    path.cubicTo(w * 0.08, h * 0.54, w * 0.06, h * 0.50, w * 0.10, h * 0.40);
    path.close();
    canvas.drawPath(path, paint);

    // Spiral curl coils overlaid — actual arcs with highlights
    final curlHl = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;
    final curlSh = Paint()
      ..color = _coolShadow(color).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.010
      ..strokeCap = StrokeCap.round;

    // Coils at key positions around the perimeter
    final curlSpots = [
      (x: 0.11, y: 0.30, r: 0.055, t: 1.8),
      (x: 0.07, y: 0.42, r: 0.045, t: 1.5),
      (x: 0.16, y: 0.07, r: 0.040, t: 1.3),
      (x: 0.32, y: 0.02, r: 0.035, t: 1.5),
      (x: 0.50, y: -0.01, r: 0.030, t: 1.2),
      (x: 0.68, y: 0.02, r: 0.035, t: 1.5),
      (x: 0.84, y: 0.07, r: 0.040, t: 1.3),
      (x: 0.89, y: 0.30, r: 0.055, t: 1.8),
      (x: 0.93, y: 0.42, r: 0.045, t: 1.5),
      (x: 0.25, y: 0.12, r: 0.030, t: 1.2),
      (x: 0.75, y: 0.12, r: 0.030, t: 1.2),
    ];
    for (final curl in curlSpots) {
      final idx = curlSpots.indexOf(curl);
      final cSway = _computeSway(swayValue, style, idx % 5, windStrength);
      _drawSpiralCurl(
        canvas,
        w * curl.x + cSway * w * 0.4,
        h * curl.y,
        w * curl.r,
        curlHl,
        curlSh,
        turns: curl.t,
        segments: 8,
      );
    }
  }

  // ── Style 3: Braids front — 3-strand weave visible ──

  void _drawBraidsFront(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);
    for (int side = 0; side < 2; side++) {
      final baseX = side == 0 ? e.oL : (e.oR - 0.07);
      for (int seg = 0; seg < 4; seg++) {
        final segSway =
            _computeSway(swayValue, style, (side * 2 + seg) % 5, windStrength);
        final segBounce =
            _computeBounce(bounceValue, style, (side * 2 + seg) % 5);
        final y = h * e.oB + seg * h * 0.072 + segBounce * h;
        final xOff = (seg.isEven ? -1 : 1) * w * 0.012 + segSway * w;
        final center = Offset(w * baseX + w * 0.035 + xOff, y + h * 0.04);

        canvas.drawOval(
          Rect.fromCenter(
            center: center.translate(0.5, 0.5),
            width: w * 0.07,
            height: h * 0.065,
          ),
          _contactShadow,
        );

        // 3 overlapping strand sections
        for (int strand = 0; strand < 3; strand++) {
          final sOff = (strand - 1) * w * 0.010;
          final vert = (strand == 1) ? -h * 0.006 : h * 0.003;
          canvas.drawOval(
            Rect.fromCenter(
              center: center.translate(sOff, vert),
              width: w * 0.032,
              height: h * 0.055,
            ),
            paint,
          );
        }

        // Highlight on center strand
        if (seg.isEven) {
          canvas.drawOval(
            Rect.fromCenter(
              center: center.translate(-w * 0.008, -h * 0.004),
              width: w * 0.020,
              height: h * 0.025,
            ),
            hlPaint,
          );
        }
      }
    }
  }

  // ── Style 4: Ponytail front ──

  void _drawPonytailFront(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);
    final sway0 = _computeSway(swayValue, style, 0, windStrength);
    final sway1 = _computeSway(swayValue, style, 1, windStrength);
    final bounce = _computeBounce(bounceValue, style, 0);

    // Side tail with pendulum physics + bounce swing-up
    final tail = Path()
      ..moveTo(w * e.iR, h * 0.22)
      ..cubicTo(w * 0.92, h * 0.18, w * 0.96, h * 0.25,
          w * (0.96 + sway0 * 0.5), h * (0.35 - bounce * 0.5))
      ..cubicTo(
          w * (0.97 + sway0), h * (0.48 - bounce * 0.8),
          w * (0.94 + sway1 * 1.5), h * (0.58 - bounce * 1.0),
          w * (0.90 + sway1 * 2), h * (0.66 - bounce * 1.2))
      ..cubicTo(w * (0.86 + sway1 * 1.5), h * (0.62 - bounce * 0.8),
          w * (0.85 + sway0), h * 0.50, w * 0.86, h * 0.40)
      ..cubicTo(w * 0.87, h * 0.30, w * 0.88, h * 0.24, w * e.iR, h * 0.26)
      ..close();

    canvas.drawPath(
        tail.shift(Offset(w * 0.004, h * 0.004)), _contactShadow);
    canvas.drawPath(tail, paint);

    // Strand highlights along tail
    for (int s = 0; s < 3; s++) {
      final sSway = _computeSway(swayValue, style, s + 1, windStrength);
      final strand = [
        Offset(w * (0.90 + s * 0.01), h * 0.28),
        Offset(w * (0.92 + s * 0.01 + sSway * 0.5),
            h * (0.42 - bounce * 0.4)),
        Offset(w * (0.91 + s * 0.01 + sSway),
            h * (0.56 - bounce * 0.8)),
      ];
      canvas.drawPath(_buildStrand(strand, w * 0.006), hlPaint);
    }

    // Hair tie
    _drawHairTie(canvas, Offset(w * 0.92, h * 0.24), w * 0.025,
        isRainbow ? const Color(0xFF9B59B6) : color);
  }

  // ── Style 5: Buzz ──

  void _drawBuzz(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint) {
    final path = Path()
      ..moveTo(w * (e.oL + 0.01), h * 0.30)
      ..cubicTo(w * (e.oL + 0.01), h * 0.15, w * 0.30, h * 0.10,
          w * 0.50, h * 0.09)
      ..cubicTo(w * 0.70, h * 0.10, w * (e.oR - 0.01), h * 0.15,
          w * (e.oR - 0.01), h * 0.30)
      ..lineTo(w * (e.iR - 0.02), h * 0.26)
      ..quadraticBezierTo(
          w * (e.iR - 0.02), h * e.iT, w * 0.50, h * (e.iT + 0.02))
      ..quadraticBezierTo(
          w * (e.iL + 0.02), h * e.iT, w * (e.iL + 0.02), h * 0.26)
      ..close();
    canvas.drawPath(path, paint);

    // Stipple texture
    final stipple = Paint()
      ..color = _coolShadow(color).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final rng = Random(42);
    for (int i = 0; i < 14; i++) {
      final x = w * (0.25 + rng.nextDouble() * 0.50);
      final y = h * (0.12 + rng.nextDouble() * 0.12);
      canvas.drawCircle(Offset(x, y), w * 0.003, stipple);
    }
  }

  // ── Style 6: Afro — volume texture with depth ──

  void _drawAfro(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);

    // Bumpy organic perimeter
    final path = Path();
    final cx = w * 0.50;
    final cy = h * 0.26;
    final rx = w * 0.44;
    final ry = h * 0.25;
    const bumpCount = 18;
    for (int i = 0; i <= bumpCount; i++) {
      final angle = -pi + (i / bumpCount) * 2 * pi;
      final bumpAmp = 1.0 + 0.06 * sin(angle * 3 + sway * pi * 2);
      final x = cx + rx * bumpAmp * cos(angle);
      final y = cy + ry * bumpAmp * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevAngle = -pi + ((i - 1) / bumpCount) * 2 * pi;
        final midAngle = (prevAngle + angle) / 2;
        final midBump = 1.0 + 0.08 * sin(midAngle * 3 + sway * pi * 2);
        path.quadraticBezierTo(
          cx + rx * midBump * 1.05 * cos(midAngle),
          cy + ry * midBump * 1.05 * sin(midAngle),
          x,
          y,
        );
      }
    }
    path.close();

    // Shadow
    canvas.drawPath(
        path.shift(Offset(w * 0.005, h * 0.006)), _contactShadow);
    canvas.drawPath(path, paint);

    // Overlapping volume shapes for depth illusion
    final volPaint = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.06);
    final volDark = Paint()
      ..color = _coolShadow(color).withValues(alpha: 0.06);
    final rng = Random(77);
    for (int i = 0; i < 10; i++) {
      final angle = rng.nextDouble() * pi * 2;
      final dist = 0.3 + rng.nextDouble() * 0.5;
      final vx = cx + rx * dist * cos(angle);
      final vy = cy + ry * dist * sin(angle);
      final vr = w * (0.04 + rng.nextDouble() * 0.04);
      // Alternate highlight and shadow for depth
      canvas.drawCircle(Offset(vx, vy), vr, i.isEven ? volPaint : volDark);
    }

    // Concentric texture arcs
    final texPaint = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    for (int ring = 0; ring < 3; ring++) {
      final r = 0.50 + ring * 0.16;
      for (int arc = 0; arc < 5; arc++) {
        final startAngle = -pi * 0.8 + arc * 0.42 + sway * 0.5;
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(cx, cy), width: rx * 2 * r, height: ry * 2 * r),
          startAngle,
          0.30,
          false,
          texPaint,
        );
      }
    }
  }

  // ── Style 7: Bun ──

  void _drawBun(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);

    final bunCenter = Offset(w * 0.50, h * 0.06);
    final bunR = w * 0.14;

    // Shadow
    canvas.drawCircle(
        bunCenter.translate(w * 0.004, h * 0.004), bunR, _contactShadow);
    canvas.drawCircle(bunCenter, bunR, paint);

    // Spiral wrap texture
    final spiralPaint = Paint()
      ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
          .withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    final spiral = Path();
    for (int i = 0; i <= 12; i++) {
      final t = i / 12;
      final angle = t * pi * 2.5;
      final r = bunR * (0.3 + t * 0.5);
      final x = bunCenter.dx + r * cos(angle);
      final y = bunCenter.dy + r * sin(angle);
      if (i == 0) {
        spiral.moveTo(x, y);
      } else {
        spiral.lineTo(x, y);
      }
    }
    canvas.drawPath(spiral, spiralPaint);

    // Shine spot
    _drawShineSpot(
        canvas, bunCenter.translate(-w * 0.03, -h * 0.02), bunR);

    // Hair tie at base of bun
    _drawHairTie(canvas, Offset(w * 0.50, h * 0.14), w * 0.020,
        isRainbow ? const Color(0xFF9B59B6) : color);
  }

  // ── Style 8: Pigtails ──

  void _drawPigtails(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);

    for (int side = 0; side < 2; side++) {
      final sway = _computeSway(swayValue, style, side * 2, windStrength);
      final bounce = _computeBounce(bounceValue, style, side);
      // Opposite phase wobble
      final wobble = sin(swayValue * pi * 2 + side * pi) * 0.008;
      final cx = side == 0
          ? w * (e.oL - 0.03 + sway * 0.5)
          : w * (e.oR + 0.03 + sway * 0.5);
      final cy = h * (0.32 + wobble - bounce * 0.5);
      final pr = w * 0.10;

      // Shadow
      canvas.drawCircle(
          Offset(cx + w * 0.003, cy + h * 0.004), pr, _contactShadow);
      canvas.drawCircle(Offset(cx, cy), pr, paint);

      // Shine spot
      _drawShineSpot(canvas, Offset(cx - pr * 0.25, cy - pr * 0.25), pr);

      // Hair tie
      _drawHairTie(canvas, Offset(cx, cy - pr * 0.02), pr + w * 0.005,
          isRainbow ? const Color(0xFF9B59B6) : color,
          showHighlight: false);
    }
  }

  // ── Style 9: Bob ──

  void _drawBob(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);
    final bounce = _computeBounce(bounceValue, style, 0);

    final path = Path()
      ..moveTo(w * (0.10 + sway * 0.3), h * (0.58 + bounce * 0.2))
      ..cubicTo(w * 0.07, h * 0.38, w * 0.10, h * 0.12, w * 0.50, h * 0.05)
      ..cubicTo(w * 0.90, h * 0.12, w * 0.93, h * 0.38,
          w * (0.90 + sway * 0.3), h * (0.58 + bounce * 0.2))
      ..cubicTo(w * 0.88, h * 0.64, w * (e.iR + 0.02), h * 0.62,
          w * e.iR, h * 0.25)
      ..quadraticBezierTo(
          w * (e.iR - 0.02), h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(
          w * (e.iL + 0.02), h * e.iT, w * e.iL, h * 0.25)
      ..cubicTo(w * (e.iL - 0.02), h * 0.62, w * 0.12, h * 0.64,
          w * (0.10 + sway * 0.3), h * (0.58 + bounce * 0.2))
      ..close();

    canvas.drawPath(path, paint);

    // Strand highlights on sides
    for (int side = 0; side < 2; side++) {
      for (int s = 0; s < 2; s++) {
        final baseX = side == 0 ? 0.12 + s * 0.02 : 0.88 - s * 0.02;
        final sSway = _computeSway(swayValue, style, side + s, windStrength);
        final strand = [
          Offset(w * baseX, h * 0.16),
          Offset(w * (baseX + sSway * 0.3), h * 0.32),
          Offset(w * (baseX + sSway * 0.4), h * 0.48),
          Offset(w * (baseX + sSway * 0.3), h * (0.56 + bounce * 0.15)),
        ];
        canvas.drawPath(_buildStrand(strand, w * 0.008), hlPaint);
      }
    }
    _drawBangStrands(canvas, w, h, e, hlPaint, count: 4);
  }

  // ── Style 10: Wavy front ──

  void _drawWavyFront(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);
    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      ..cubicTo(w * 0.08, h * 0.18, w * 0.18, h * (0.10 + sway * 0.2),
          w * 0.30, h * 0.07)
      ..cubicTo(w * 0.38, h * 0.03, w * 0.45, h * 0.04, w * 0.50, h * 0.06)
      ..cubicTo(w * 0.55, h * 0.03, w * 0.62, h * 0.02, w * 0.70, h * 0.07)
      ..cubicTo(w * 0.82, h * (0.10 + sway * 0.2), w * 0.92, h * 0.18,
          w * e.oR, h * e.oB)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
      ..close();

    canvas.drawPath(path, paint);
    _drawBangStrands(canvas, w, h, e, hlPaint, count: 5);
  }

  // ── Style 11: Side Swept ──

  void _drawSideSwept(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final path = Path()
      ..moveTo(w * e.oL, h * 0.30)
      ..cubicTo(w * 0.08, h * 0.14, w * 0.22, h * 0.07, w * 0.35, h * 0.05)
      ..cubicTo(w * 0.55, h * 0.02, w * 0.72, h * 0.04, w * 0.80, h * 0.07)
      ..cubicTo(
          w * 0.90, h * 0.10, w * e.oR, h * 0.22, w * e.oR, h * 0.38)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(w * 0.75, h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(
          w * e.iL, h * (e.iT - 0.02), w * e.oL, h * 0.30)
      ..close();

    canvas.drawPath(path, paint);

    // Swept strand accents
    for (int s = 0; s < 4; s++) {
      final sSway = _computeSway(swayValue, style, s, windStrength);
      final startX = 0.20 + s * 0.12;
      final strand = [
        Offset(w * startX, h * 0.08),
        Offset(w * (startX + 0.10 + sSway * 0.3), h * 0.06),
        Offset(w * (startX + 0.18 + sSway * 0.2), h * 0.10),
      ];
      canvas.drawPath(_buildStrand(strand, w * 0.006), hlPaint);
    }
  }

  // ── Style 12: Mohawk ──

  void _drawMohawk(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);

    // Center spike
    final spike = Path()
      ..moveTo(w * 0.34, h * 0.25)
      ..cubicTo(w * 0.36, h * 0.08, w * (0.42 + sway * 0.5), h * -0.02,
          w * 0.50, h * -0.08)
      ..cubicTo(w * (0.58 + sway * 0.5), h * -0.02, w * 0.64, h * 0.08,
          w * 0.66, h * 0.25)
      ..quadraticBezierTo(w * 0.58, h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(w * 0.42, h * e.iT, w * 0.34, h * 0.25)
      ..close();
    canvas.drawPath(spike, paint);

    // Spike strand highlights
    for (int s = 0; s < 3; s++) {
      final x = 0.44 + s * 0.04;
      final strand = [
        Offset(w * x, h * 0.18),
        Offset(w * (x + sway * 0.2), h * 0.04),
        Offset(w * (x + 0.01 + sway * 0.3), h * -0.05),
      ];
      canvas.drawPath(_buildStrand(strand, w * 0.005), hlPaint);
    }

    // Thin shaved sides
    final sidesL = Path()
      ..moveTo(w * (e.oL + 0.01), h * 0.30)
      ..cubicTo(w * (e.oL + 0.01), h * 0.20, w * 0.25, h * 0.18,
          w * 0.34, h * 0.18)
      ..lineTo(w * 0.34, h * 0.24)
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * (e.oL + 0.03), h * 0.28)
      ..close();
    canvas.drawPath(sidesL, paint);
    final sidesR = Path()
      ..moveTo(w * (e.oR - 0.01), h * 0.30)
      ..cubicTo(w * (e.oR - 0.01), h * 0.20, w * 0.75, h * 0.18,
          w * 0.66, h * 0.18)
      ..lineTo(w * 0.66, h * 0.24)
      ..quadraticBezierTo(w * e.iR, h * e.iT, w * (e.oR - 0.03), h * 0.28)
      ..close();
    canvas.drawPath(sidesR, paint);
  }

  // ── Style 13: Space Buns — wobble + shine ──

  void _drawSpaceBuns(Canvas canvas, double w, double h, _FrontEdge e,
      Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);

    for (int side = 0; side < 2; side++) {
      final wobble = sin(swayValue * pi * 2.5 + side * pi) * 0.010;
      final sway = _computeSway(swayValue, style, side * 2, windStrength);
      final bounce = _computeBounce(bounceValue, style, side);
      final cx = side == 0
          ? w * (0.28 + sway * 0.3)
          : w * (0.72 + sway * 0.3);
      // Compress then spring on bounce
      final cy = h * (0.06 + wobble - bounce * 0.4);
      final br = w * 0.12;

      // Shadow
      canvas.drawCircle(
          Offset(cx + w * 0.003, cy + h * 0.004), br, _contactShadow);
      canvas.drawCircle(Offset(cx, cy), br, paint);

      // Spiral wrap texture
      final spiralPaint = Paint()
        ..color = _warmHighlight(isRainbow ? const Color(0xFFFFD700) : color)
            .withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.006
        ..strokeCap = StrokeCap.round;
      final spiral = Path();
      for (int i = 0; i <= 8; i++) {
        final t = i / 8;
        final angle = t * pi * 2.2 + side * pi * 0.5;
        final r = br * (0.25 + t * 0.55);
        final x = cx + r * cos(angle);
        final y = cy + r * sin(angle);
        if (i == 0) {
          spiral.moveTo(x, y);
        } else {
          spiral.lineTo(x, y);
        }
      }
      canvas.drawPath(spiral, spiralPaint);

      // Shine spot — white oval highlight
      _drawShineSpot(
          canvas, Offset(cx - br * 0.2, cy - br * 0.2), br);
    }
  }

  // ── Style 14: Long Wavy front ──

  void _drawLongWavyFront(Canvas canvas, double w, double h,
      _FrontEdge e, Paint paint, Paint hlPaint) {
    final sway = _computeSway(swayValue, style, 0, windStrength);
    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      ..cubicTo(w * 0.08, h * 0.16, w * 0.18, h * (0.08 + sway * 0.15),
          w * 0.30, h * 0.05)
      ..cubicTo(w * 0.40, h * 0.02, w * 0.48, h * 0.03, w * 0.55, h * 0.05)
      ..cubicTo(w * 0.62, h * 0.02, w * 0.72, h * 0.03, w * 0.80, h * 0.05)
      ..cubicTo(w * 0.88, h * (0.08 + sway * 0.15), w * 0.92, h * 0.16,
          w * e.oR, h * e.oB)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
      ..close();

    canvas.drawPath(path, paint);
    _drawBangStrands(canvas, w, h, e, hlPaint, count: 6);
  }

  // ── Style 15: Fishtail front ──

  void _drawFishtailFront(Canvas canvas, double w, double h,
      _FrontEdge e, Paint paint, Paint hlPaint) {
    _drawHairCap(canvas, paint, w, h, e, hlPaint);

    // Braid origin showing at the nape
    final braidStart = Path()
      ..moveTo(w * 0.44, h * 0.28)
      ..cubicTo(
          w * 0.44, h * 0.32, w * 0.48, h * 0.34, w * 0.50, h * 0.36)
      ..cubicTo(
          w * 0.52, h * 0.34, w * 0.56, h * 0.32, w * 0.56, h * 0.28)
      ..close();
    canvas.drawPath(braidStart, paint);

    // Hair tie at braid start
    _drawHairTie(canvas, Offset(w * 0.50, h * 0.29), w * 0.018,
        isRainbow ? const Color(0xFF9B59B6) : color);
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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A physics-driven background with hearts that float upward into a soft
/// cloud at the top of the screen. When a heart is absorbed, the cloud
/// flashes purple at the contact point.
///
/// Uses a [ChangeNotifier]-driven repaint so only the canvas repaints
/// each frame — no widget rebuilds, no jank.
class FloatingHeartsBackground extends StatefulWidget {
  /// Height fraction (0–1) from the top where the cloud sits.
  final double cloudZoneHeight;

  const FloatingHeartsBackground({
    super.key,
    this.cloudZoneHeight = 0.18,
  });

  @override
  State<FloatingHeartsBackground> createState() =>
      FloatingHeartsBackgroundState();
}

class FloatingHeartsBackgroundState extends State<FloatingHeartsBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late _HeartsSimulation _sim;

  @override
  void initState() {
    super.initState();
    _sim = _HeartsSimulation(cloudZoneHeight: widget.cloudZoneHeight);
    _ticker = createTicker(_sim.tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sim.dispose();
    super.dispose();
  }

  /// Tap at a screen position — bursts the nearest heart with a purple flash.
  void tapAt(Offset pos) => _sim.tapAt(pos);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        _sim.size = constraints.biggest;
        return CustomPaint(
          size: constraints.biggest,
          painter: _HeartsAndCloudPainter(sim: _sim),
        );
      }),
    );
  }
}

// ── Simulation (ChangeNotifier) ──────────────────────────────────────

class _HeartsSimulation extends ChangeNotifier {
  final double cloudZoneHeight;

  final List<_Heart> hearts = [];
  final List<_CloudFlash> flashes = [];
  double time = 0;
  double _spawnTimer = 0;
  Duration _lastElapsed = Duration.zero;
  Size size = Size.zero;
  final _rng = Random();

  // ── Tuning ─────────────────────────────────────────────
  static const _spawnInterval = 0.7;
  static const _maxHearts = 14;
  static const _minVy = -55.0;
  static const _maxVy = -100.0;
  static const _wobbleAmp = 22.0;
  static const _wobbleFreq = 0.8;
  static const flashDuration = 0.55;
  static const flashMaxRadius = 60.0;

  static const heartColors = [
    Color(0xFFFF69B4),
    Color(0xFFFF1493),
    Color(0xFFFF6B9D),
    Color(0xFFFFA0C4),
    Color(0xFFEC4899),
    Color(0xFFE879AB),
    Color(0xFFFF8FAB),
    Color(0xFFD946EF),
  ];

  _HeartsSimulation({required this.cloudZoneHeight});

  void tapAt(Offset pos) {
    if (size == Size.zero) return;

    _Heart? closest;
    double closestDist = double.infinity;

    for (final h in hearts) {
      final dist = (Offset(h.x, h.y) - pos).distance;
      if (dist < 50 && dist < closestDist) {
        closestDist = dist;
        closest = h;
      }
    }

    if (closest != null) {
      // Purple flash at heart position
      flashes.add(_CloudFlash(x: closest.x, y: closest.y));
      hearts.remove(closest);
    }
  }

  void tick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final dt = dtRaw.clamp(0.0, 0.05);
    if (size == Size.zero) return;

    time += dt;
    _spawnTimer += dt;

    // ── Spawn ────────────────────────────────────────────
    if (_spawnTimer >= _spawnInterval && hearts.length < _maxHearts) {
      _spawnTimer = 0;
      _spawnHeart();
    }

    final cloudBottomY = size.height * cloudZoneHeight;

    // ── Update hearts ────────────────────────────────────
    for (int i = hearts.length - 1; i >= 0; i--) {
      final h = hearts[i];

      h.y += h.vy * dt;
      h.x += sin(time * _wobbleFreq * 2 * pi + h.wobblePhase) *
          _wobbleAmp *
          dt;
      h.rotation += h.rotationSpeed * dt;

      if (h.y < cloudBottomY + h.size) {
        h.absorbing = true;
        h.opacity -= 2.2 * dt;
        h.size *= (1.0 - 2.5 * dt).clamp(0.5, 1.0);

        if (h.opacity <= 0.0) {
          flashes.add(_CloudFlash(
            x: h.x.clamp(0, size.width),
            y: cloudBottomY * 0.6,
          ));
          hearts.removeAt(i);
          continue;
        }
      }

      if (h.y < -50 || h.x < -50 || h.x > size.width + 50) {
        hearts.removeAt(i);
      }
    }

    // ── Update flashes ───────────────────────────────────
    for (int i = flashes.length - 1; i >= 0; i--) {
      flashes[i].elapsed += dt;
      if (flashes[i].elapsed >= flashDuration) {
        flashes.removeAt(i);
      }
    }

    // Signal repaint — ONLY the CustomPaint repaints, not the widget tree
    notifyListeners();
  }

  void _spawnHeart() {
    hearts.add(_Heart(
      x: _rng.nextDouble() * size.width,
      y: size.height + 20 + _rng.nextDouble() * 40,
      vx: (_rng.nextDouble() - 0.5) * 10,
      vy: _lerpDouble(_minVy, _maxVy, _rng.nextDouble()),
      size: 14.0 + _rng.nextDouble() * 16.0,
      opacity: 0.35 + _rng.nextDouble() * 0.35,
      rotation: _rng.nextDouble() * 2 * pi,
      rotationSpeed: (_rng.nextDouble() - 0.5) * 1.5,
      wobblePhase: _rng.nextDouble() * 2 * pi,
      color: heartColors[_rng.nextInt(heartColors.length)],
    ));
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

// ── Data classes ────────────────────────────────────────────────────

class _Heart {
  double x, y;
  double vx, vy;
  double size;
  double opacity;
  double rotation;
  double rotationSpeed;
  double wobblePhase;
  Color color;
  bool absorbing = false;

  _Heart({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.rotation,
    required this.rotationSpeed,
    required this.wobblePhase,
    required this.color,
  });
}

class _CloudFlash {
  double x;
  double y;
  double elapsed = 0;

  _CloudFlash({required this.x, required this.y});
}

// ── Painter ────────────────────────────────────────────────────────

class _HeartsAndCloudPainter extends CustomPainter {
  final _HeartsSimulation sim;

  _HeartsAndCloudPainter({required this.sim}) : super(repaint: sim);

  @override
  void paint(Canvas canvas, Size size) {
    _paintCloud(canvas, size);
    _paintCloudFlashes(canvas, size);
    _paintHearts(canvas, size);
  }

  // ── Cloud ──────────────────────────────────────────────────────

  void _paintCloud(Canvas canvas, Size size) {
    final cloudMaxY = size.height * sim.cloudZoneHeight;
    final cx = size.width / 2;

    final cloudPuffs = <_Puff>[
      _Puff(cx, cloudMaxY * 0.35, size.width * 0.55, cloudMaxY * 0.55),
      _Puff(cx - size.width * 0.18, cloudMaxY * 0.40, size.width * 0.38,
          cloudMaxY * 0.45),
      _Puff(cx + size.width * 0.20, cloudMaxY * 0.38, size.width * 0.35,
          cloudMaxY * 0.48),
      _Puff(cx - size.width * 0.06, cloudMaxY * 0.50, size.width * 0.50,
          cloudMaxY * 0.42),
      _Puff(cx + size.width * 0.08, cloudMaxY * 0.28, size.width * 0.42,
          cloudMaxY * 0.40),
    ];

    for (final p in cloudPuffs) {
      final rect = Rect.fromCenter(
        center: Offset(p.x, p.y),
        width: p.w,
        height: p.h,
      );
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            const Color(0xFFD8B4FE).withValues(alpha: 0.03),
            const Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

      canvas.drawOval(rect, paint);
    }
  }

  // ── Cloud flashes ──────────────────────────────────────────────

  void _paintCloudFlashes(Canvas canvas, Size size) {
    for (final f in sim.flashes) {
      final t =
          (f.elapsed / _HeartsSimulation.flashDuration).clamp(0.0, 1.0);

      final curve = Curves.easeOut.transform(t);
      final radius = _HeartsSimulation.flashMaxRadius * (0.3 + 0.7 * curve);

      final intensity = t < 0.15
          ? (t / 0.15)
          : 1.0 - ((t - 0.15) / 0.85);

      final alpha = (intensity * 0.55).clamp(0.0, 1.0);

      final center = Offset(f.x, f.y);
      final rect = Rect.fromCircle(center: center, radius: radius);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF8B5CF6).withValues(alpha: alpha),
            const Color(0xFFD946EF).withValues(alpha: alpha * 0.5),
            const Color(0xFF8B5CF6).withValues(alpha: 0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + radius * 0.2);

      canvas.drawCircle(center, radius, paint);

      final corePaint = Paint()
        ..color = const Color(0xFFC084FC).withValues(alpha: alpha * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawCircle(center, radius * 0.2, corePaint);
    }
  }

  // ── Hearts ─────────────────────────────────────────────────────

  void _paintHearts(Canvas canvas, Size size) {
    for (final h in sim.hearts) {
      canvas.save();
      canvas.translate(h.x, h.y);
      canvas.rotate(h.rotation);

      final paint = Paint()
        ..color = h.color.withValues(alpha: h.opacity)
        ..style = PaintingStyle.fill;

      final glowPaint = Paint()
        ..color = h.color.withValues(alpha: h.opacity * 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h.size * 0.5);

      final path = _heartPath(h.size);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);

      canvas.restore();
    }
  }

  static Path _heartPath(double s) {
    final hs = s / 2;
    final path = Path();

    path.moveTo(0, hs * 0.8);

    path.cubicTo(
      -hs * 0.2, hs * 0.4,
      -hs * 1.1, -hs * 0.1,
      -hs * 0.6, -hs * 0.7,
    );
    path.cubicTo(
      -hs * 0.3, -hs * 1.0,
      0, -hs * 0.6,
      0, -hs * 0.3,
    );

    path.cubicTo(
      0, -hs * 0.6,
      hs * 0.3, -hs * 1.0,
      hs * 0.6, -hs * 0.7,
    );
    path.cubicTo(
      hs * 1.1, -hs * 0.1,
      hs * 0.2, hs * 0.4,
      0, hs * 0.8,
    );

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HeartsAndCloudPainter oldDelegate) => false;
}

class _Puff {
  final double x, y, w, h;
  const _Puff(this.x, this.y, this.w, this.h);
}

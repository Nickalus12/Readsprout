import 'dart:math';
import 'package:flutter/material.dart';
import '../models/player_profile.dart';
import '../data/avatar_options.dart';
import '../theme/app_theme.dart';

/// Reusable avatar rendering widget.
///
/// Renders the player's avatar at any size using [AvatarConfig] to drive
/// every customizable feature. All drawing is proportional to [size].
///
/// Layer order (bottom to top):
///   1. Background circle
///   2. Golden glow ring
///   3. Back hair layer (long/flowing styles behind the face)
///   4. Face shape (skin)
///   5. Nose
///   6. Cheeks (blush, freckles, hearts, stars)
///   7. Eyes (sclera, iris, pupil, highlights) + eye color
///   8. Eyelashes
///   9. Eyebrows
///  10. Mouth + lip color
///  11. Face paint / stickers
///  12. Front hair layer
///  13. Glasses
///  14. Accessories (hats, bows, crowns, horns, etc.)
///  15. Sparkle effects
class AvatarWidget extends StatelessWidget {
  final AvatarConfig config;
  final double size;
  final bool showBackground;
  final bool animateEffects;

  const AvatarWidget({
    super.key,
    required this.config,
    this.size = 80,
    this.showBackground = true,
    this.animateEffects = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.avatarBgColors[config.bgColor.clamp(0, 7)];

    Widget avatar = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Background circle
          if (showBackground)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),

          // 2. Golden glow ring
          if (config.hasGoldenGlow)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.starGold.withValues(alpha: 0.7),
                    width: size * 0.04,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.4),
                      blurRadius: size * 0.15,
                      spreadRadius: size * 0.02,
                    ),
                  ],
                ),
              ),
            ),

          // 3. Back hair layer
          Positioned.fill(
            child: CustomPaint(
              painter: _BackHairPainter(
                style: config.hairStyle,
                color: _hairColor,
                isRainbow: isRainbowHair(config.hairColor),
                faceShape: config.faceShape,
              ),
            ),
          ),

          // 4. Face shape
          Positioned(
            left: size * 0.15,
            top: size * _faceTop,
            child: CustomPaint(
              size: Size(size * 0.70, size * _faceHeightFraction),
              painter: _FacePainter(
                skinColor: _skinColor,
                faceShape: config.faceShape,
              ),
            ),
          ),

          // 5. Nose
          Positioned(
            left: size * 0.44,
            top: size * (_faceTop + _faceHeightFraction * 0.52),
            child: CustomPaint(
              size: Size(size * 0.12, size * 0.10),
              painter: _NosePainter(
                style: config.noseStyle,
                skinColor: _skinColor,
              ),
            ),
          ),

          // 6. Cheeks
          if (config.cheekStyle > 0)
            Positioned(
              left: size * 0.18,
              top: size * (_faceTop + _faceHeightFraction * 0.48),
              child: CustomPaint(
                size: Size(size * 0.64, size * 0.20),
                painter: _CheekPainter(
                  style: config.cheekStyle,
                  skinColor: _skinColor,
                ),
              ),
            ),

          // 7. Eyes + eye color
          Positioned(
            left: size * 0.26,
            top: size * (_faceTop + _faceHeightFraction * 0.28),
            child: CustomPaint(
              size: Size(size * 0.48, size * 0.16),
              painter: _EyesPainter(
                style: config.eyeStyle,
                eyeColor: _eyeColor,
              ),
            ),
          ),

          // 8. Eyelashes
          if (config.eyelashStyle > 0)
            Positioned(
              left: size * 0.26,
              top: size * (_faceTop + _faceHeightFraction * 0.22),
              child: CustomPaint(
                size: Size(size * 0.48, size * 0.20),
                painter: _EyelashPainter(
                  style: config.eyelashStyle,
                  eyeStyle: config.eyeStyle,
                ),
              ),
            ),

          // 9. Eyebrows
          Positioned(
            left: size * 0.26,
            top: size * (_faceTop + _faceHeightFraction * 0.16),
            child: CustomPaint(
              size: Size(size * 0.48, size * 0.10),
              painter: _EyebrowPainter(
                style: config.eyebrowStyle,
                color: _hairColor,
              ),
            ),
          ),

          // 10. Mouth + lip color
          Positioned(
            left: size * 0.35,
            top: size * (_faceTop + _faceHeightFraction * 0.68),
            child: CustomPaint(
              size: Size(size * 0.30, size * 0.12),
              painter: _MouthPainter(
                style: config.mouthStyle,
                lipColor: _lipColor,
              ),
            ),
          ),

          // 11. Face paint
          if (config.facePaint > 0)
            Positioned(
              left: size * 0.15,
              top: size * _faceTop,
              child: CustomPaint(
                size: Size(size * 0.70, size * _faceHeightFraction),
                painter: _FacePaintPainter(style: config.facePaint),
              ),
            ),

          // 12. Front hair layer
          Positioned.fill(
            child: CustomPaint(
              painter: _FrontHairPainter(
                style: config.hairStyle,
                color: _hairColor,
                isRainbow: isRainbowHair(config.hairColor),
                faceShape: config.faceShape,
              ),
            ),
          ),

          // 13. Glasses
          if (config.glassesStyle > 0)
            Positioned(
              left: size * 0.20,
              top: size * (_faceTop + _faceHeightFraction * 0.24),
              child: CustomPaint(
                size: Size(size * 0.60, size * 0.20),
                painter: _GlassesPainter(style: config.glassesStyle),
              ),
            ),

          // 14. Accessories
          if (config.accessory > 0) _buildAccessory(),

          // 15. Sparkle effects
          if (config.hasSparkle || config.hasRainbowSparkle)
            Positioned.fill(
              child: CustomPaint(
                painter: _SparklePainter(
                  rainbow: config.hasRainbowSparkle,
                ),
              ),
            ),
        ],
      ),
    );

    return avatar;
  }

  // ── Color helpers ──────────────────────────────────────────────────

  Color get _hairColor {
    final idx = config.hairColor.clamp(0, hairColorOptions.length - 1);
    return hairColorOptions[idx].color;
  }

  Color get _skinColor => skinColorForIndex(config.skinTone);

  Color get _eyeColor {
    final idx = config.eyeColor.clamp(0, eyeColorOptions.length - 1);
    return eyeColorOptions[idx].color;
  }

  Color get _lipColor {
    final idx = config.lipColor.clamp(0, lipColorOptions.length - 1);
    return lipColorOptions[idx].color;
  }

  // ── Face geometry ─────────────────────────────────────────────────

  double get _faceTop => 0.18;

  double get _faceHeightFraction {
    final shape =
        faceShapeOptions[config.faceShape.clamp(0, faceShapeOptions.length - 1)];
    return 0.70 * shape.heightRatio;
  }

  // ── Accessory builder ─────────────────────────────────────────────

  Widget _buildAccessory() {
    switch (config.accessory) {
      case 1: // Glasses (legacy)
        return Positioned(
          left: size * 0.20,
          top: size * (_faceTop + _faceHeightFraction * 0.24),
          child: CustomPaint(
            size: Size(size * 0.60, size * 0.20),
            painter: _GlassesPainter(style: 1),
          ),
        );
      case 2: // Crown
        return Positioned(
          left: size * 0.25,
          top: size * 0.02,
          child: CustomPaint(
            size: Size(size * 0.50, size * 0.20),
            painter: _CrownPainter(color: AppColors.starGold),
          ),
        );
      case 3: // Flower
        return Positioned(
          right: size * 0.05,
          top: size * 0.12,
          child: CustomPaint(
            size: Size(size * 0.22, size * 0.22),
            painter: _FlowerPainter(),
          ),
        );
      case 4: // Bow
        return Positioned(
          left: size * 0.30,
          top: size * 0.08,
          child: CustomPaint(
            size: Size(size * 0.24, size * 0.16),
            painter: _BowPainter(),
          ),
        );
      case 5: // Cap
        return Positioned(
          left: size * 0.10,
          top: size * 0.04,
          child: CustomPaint(
            size: Size(size * 0.70, size * 0.28),
            painter: _CapPainter(),
          ),
        );
      case 6: // Wizard Hat
        return Positioned(
          left: size * 0.18,
          top: -size * 0.15,
          child: CustomPaint(
            size: Size(size * 0.64, size * 0.45),
            painter: _WizardHatPainter(),
          ),
        );
      case 7: // Wings
        return Positioned(
          left: -size * 0.15,
          top: size * 0.25,
          child: CustomPaint(
            size: Size(size * 1.30, size * 0.55),
            painter: _WingsPainter(),
          ),
        );
      case 8: // Royal Crown
        return Positioned(
          left: size * 0.20,
          top: -size * 0.02,
          child: CustomPaint(
            size: Size(size * 0.60, size * 0.25),
            painter: _CrownPainter(
              color: AppColors.starGold,
              jewels: true,
            ),
          ),
        );
      case 9: // Tiara
        return Positioned(
          left: size * 0.22,
          top: size * 0.04,
          child: CustomPaint(
            size: Size(size * 0.56, size * 0.18),
            painter: _TiaraPainter(),
          ),
        );
      case 10: // Bunny Ears
        return Positioned(
          left: size * 0.20,
          top: -size * 0.25,
          child: CustomPaint(
            size: Size(size * 0.60, size * 0.40),
            painter: _BunnyEarsPainter(),
          ),
        );
      case 11: // Cat Ears
        return Positioned(
          left: size * 0.12,
          top: -size * 0.08,
          child: CustomPaint(
            size: Size(size * 0.76, size * 0.30),
            painter: _CatEarsPainter(),
          ),
        );
      case 12: // Unicorn Horn
        return Positioned(
          left: size * 0.35,
          top: -size * 0.20,
          child: CustomPaint(
            size: Size(size * 0.30, size * 0.35),
            painter: _UnicornHornPainter(),
          ),
        );
      case 13: // Star Headband
        return Positioned(
          left: size * 0.12,
          top: size * 0.06,
          child: CustomPaint(
            size: Size(size * 0.76, size * 0.16),
            painter: _StarHeadbandPainter(),
          ),
        );
      case 14: // Halo
        return Positioned(
          left: size * 0.22,
          top: -size * 0.06,
          child: CustomPaint(
            size: Size(size * 0.56, size * 0.20),
            painter: _HaloPainter(),
          ),
        );
      case 15: // Headband
        return Positioned(
          left: size * 0.14,
          top: size * 0.12,
          child: CustomPaint(
            size: Size(size * 0.72, size * 0.10),
            painter: _HeadbandPainter(),
          ),
        );
      case 16: // Flower Crown
        return Positioned(
          left: size * 0.12,
          top: size * 0.04,
          child: CustomPaint(
            size: Size(size * 0.76, size * 0.22),
            painter: _FlowerCrownPainter(),
          ),
        );
      case 17: // Devil Horns
        return Positioned(
          left: size * 0.15,
          top: -size * 0.08,
          child: CustomPaint(
            size: Size(size * 0.70, size * 0.28),
            painter: _DevilHornsPainter(),
          ),
        );
      case 18: // Pirate Hat
        return Positioned(
          left: size * 0.08,
          top: -size * 0.06,
          child: CustomPaint(
            size: Size(size * 0.84, size * 0.38),
            painter: _PirateHatPainter(),
          ),
        );
      case 19: // Antennae
        return Positioned(
          left: size * 0.25,
          top: -size * 0.22,
          child: CustomPaint(
            size: Size(size * 0.50, size * 0.35),
            painter: _AntennaePainter(),
          ),
        );
      case 20: // Propeller Hat
        return Positioned(
          left: size * 0.18,
          top: -size * 0.08,
          child: CustomPaint(
            size: Size(size * 0.64, size * 0.32),
            painter: _PropellerHatPainter(),
          ),
        );
      case 21: // Ninja Mask
        return Positioned(
          left: size * 0.14,
          top: size * (_faceTop + _faceHeightFraction * 0.22),
          child: CustomPaint(
            size: Size(size * 0.72, size * 0.18),
            painter: _NinjaMaskPainter(),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
//  FACE PAINTER
// ══════════════════════════════════════════════════════════════════════

class _FacePainter extends CustomPainter {
  final Color skinColor;
  final int faceShape;

  _FacePainter({required this.skinColor, required this.faceShape});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = skinColor;

    switch (faceShape) {
      case 0: // Round
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.5)),
          paint,
        );

      case 1: // Square-ish (rounded)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.28)),
          paint,
        );

      case 2: // Oval
        canvas.drawOval(Rect.fromLTWH(0, 0, w, h), paint);

      case 3: // Heart
        final path = Path()
          ..moveTo(w * 0.50, h * 0.18)
          ..cubicTo(w * 0.50, h * 0.05, w * 0.80, h * -0.02, w * 0.90, h * 0.20)
          ..cubicTo(w * 1.00, h * 0.42, w * 0.80, h * 0.65, w * 0.50, h * 0.98)
          ..cubicTo(w * 0.20, h * 0.65, w * 0.00, h * 0.42, w * 0.10, h * 0.20)
          ..cubicTo(w * 0.20, h * -0.02, w * 0.50, h * 0.05, w * 0.50, h * 0.18)
          ..close();
        canvas.drawPath(path, paint);

      case 4: // Diamond
        final path = Path()
          ..moveTo(w * 0.50, h * 0.02)
          ..quadraticBezierTo(w * 0.95, h * 0.30, w * 0.88, h * 0.55)
          ..quadraticBezierTo(w * 0.78, h * 0.85, w * 0.50, h * 0.98)
          ..quadraticBezierTo(w * 0.22, h * 0.85, w * 0.12, h * 0.55)
          ..quadraticBezierTo(w * 0.05, h * 0.30, w * 0.50, h * 0.02)
          ..close();
        canvas.drawPath(path, paint);

      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.5)),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.skinColor != skinColor || old.faceShape != faceShape;
}

// ══════════════════════════════════════════════════════════════════════
//  NOSE PAINTER
// ══════════════════════════════════════════════════════════════════════

class _NosePainter extends CustomPainter {
  final int style;
  final Color skinColor;

  _NosePainter({required this.style, required this.skinColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Slightly darker than skin for subtle shading
    final nosePaint = Paint()
      ..color = Color.lerp(skinColor, Colors.black, 0.12)!;
    final highlightPaint = Paint()
      ..color = Color.lerp(skinColor, Colors.white, 0.15)!;

    switch (style) {
      case 0: // Button — small circle
        canvas.drawCircle(
            Offset(w * 0.5, h * 0.5), w * 0.22, nosePaint);
        canvas.drawCircle(
            Offset(w * 0.55, h * 0.40), w * 0.08, highlightPaint);

      case 1: // Small — tiny dot
        canvas.drawCircle(
            Offset(w * 0.5, h * 0.5), w * 0.14, nosePaint);

      case 2: // Round — bigger circle
        canvas.drawCircle(
            Offset(w * 0.5, h * 0.5), w * 0.28, nosePaint);
        canvas.drawCircle(
            Offset(w * 0.58, h * 0.38), w * 0.10, highlightPaint);

      case 3: // Pointed — small triangle
        final path = Path()
          ..moveTo(w * 0.5, h * 0.15)
          ..lineTo(w * 0.68, h * 0.80)
          ..quadraticBezierTo(w * 0.5, h * 0.92, w * 0.32, h * 0.80)
          ..close();
        canvas.drawPath(path, nosePaint);

      case 4: // Snub — upturned
        final path = Path()
          ..moveTo(w * 0.35, h * 0.30)
          ..quadraticBezierTo(w * 0.50, h * 0.10, w * 0.65, h * 0.30)
          ..quadraticBezierTo(w * 0.72, h * 0.60, w * 0.60, h * 0.75)
          ..quadraticBezierTo(w * 0.50, h * 0.82, w * 0.40, h * 0.75)
          ..quadraticBezierTo(w * 0.28, h * 0.60, w * 0.35, h * 0.30)
          ..close();
        canvas.drawPath(path, nosePaint);
    }
  }

  @override
  bool shouldRepaint(_NosePainter old) =>
      old.style != style || old.skinColor != skinColor;
}

// ══════════════════════════════════════════════════════════════════════
//  CHEEK PAINTER
// ══════════════════════════════════════════════════════════════════════

class _CheekPainter extends CustomPainter {
  final int style;
  final Color skinColor;

  _CheekPainter({required this.style, required this.skinColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCheek = Offset(w * 0.18, h * 0.50);
    final rightCheek = Offset(w * 0.82, h * 0.50);

    switch (style) {
      case 1: // Rosy — translucent pink circles
        final paint = Paint()..color = const Color(0xFFFF7090).withValues(alpha: 0.35);
        canvas.drawOval(
          Rect.fromCenter(center: leftCheek, width: w * 0.22, height: h * 0.55),
          paint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: rightCheek, width: w * 0.22, height: h * 0.55),
          paint,
        );

      case 2: // Freckles — small dots
        final paint = Paint()
          ..color = Color.lerp(skinColor, Colors.brown, 0.35)!;
        final rng = Random(7);
        for (final center in [leftCheek, rightCheek]) {
          for (int i = 0; i < 5; i++) {
            final dx = (rng.nextDouble() - 0.5) * w * 0.14;
            final dy = (rng.nextDouble() - 0.5) * h * 0.40;
            canvas.drawCircle(
              center.translate(dx, dy),
              w * 0.012 + rng.nextDouble() * w * 0.008,
              paint,
            );
          }
        }

      case 3: // Blush — larger pink gradient
        final paint = Paint()..color = const Color(0xFFFF6090).withValues(alpha: 0.28);
        canvas.drawOval(
          Rect.fromCenter(center: leftCheek, width: w * 0.26, height: h * 0.65),
          paint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: rightCheek, width: w * 0.26, height: h * 0.65),
          paint,
        );

      case 4: // Sparkle — tiny stars on cheeks
        final paint = Paint()..color = AppColors.starGold.withValues(alpha: 0.7);
        for (final center in [leftCheek, rightCheek]) {
          _drawMiniStar(canvas, center, w * 0.04, paint);
          _drawMiniStar(canvas, center.translate(w * 0.05, -h * 0.15), w * 0.025, paint);
        }

      case 5: // Hearts — tiny heart stamps
        final paint = Paint()..color = const Color(0xFFFF4D6A).withValues(alpha: 0.6);
        for (final center in [leftCheek, rightCheek]) {
          _drawMiniHeart(canvas, center, w * 0.04, paint);
        }

      case 6: // Stars — tiny star stamps
        final paint = Paint()..color = AppColors.starGold.withValues(alpha: 0.6);
        for (final center in [leftCheek, rightCheek]) {
          _drawMiniStar(canvas, center, w * 0.05, paint);
        }
    }
  }

  void _drawMiniStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final ox = center.dx + r * cos(outerAngle);
      final oy = center.dy + r * sin(outerAngle);
      final ix = center.dx + r * 0.4 * cos(innerAngle);
      final iy = center.dy + r * 0.4 * sin(innerAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawMiniHeart(Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheekPainter old) =>
      old.style != style || old.skinColor != skinColor;
}

// ══════════════════════════════════════════════════════════════════════
//  EYES PAINTER
// ══════════════════════════════════════════════════════════════════════

class _EyesPainter extends CustomPainter {
  final int style;
  final Color eyeColor;

  _EyesPainter({required this.style, required this.eyeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCenter = Offset(w * 0.25, h * 0.5);
    final rightCenter = Offset(w * 0.75, h * 0.5);
    final eyeRadius = w * 0.12;

    switch (style) {
      case 0: // Round
        _drawRoundEyes(canvas, leftCenter, rightCenter, eyeRadius);

      case 1: // Star
        final paint = Paint()..color = AppColors.starGold;
        _drawStar(canvas, leftCenter, eyeRadius, paint);
        _drawStar(canvas, rightCenter, eyeRadius, paint);

      case 2: // Hearts
        final paint = Paint()..color = const Color(0xFFFF4D6A);
        _drawHeart(canvas, leftCenter, eyeRadius, paint);
        _drawHeart(canvas, rightCenter, eyeRadius, paint);

      case 3: // Happy Crescents
        _drawCrescentEyes(canvas, leftCenter, rightCenter, eyeRadius);

      case 4: // Sparkle
        _drawSparkleEyes(canvas, leftCenter, rightCenter, eyeRadius);

      case 5: // Almond
        _drawAlmondEyes(canvas, leftCenter, rightCenter, eyeRadius);

      case 6: // Wink — left eye open, right eye winking
        _drawRoundEye(canvas, leftCenter, eyeRadius);
        _drawWinkEye(canvas, rightCenter, eyeRadius);

      case 7: // Sleepy — half-closed
        _drawSleepyEyes(canvas, leftCenter, rightCenter, eyeRadius);
    }
  }

  void _drawRoundEyes(Canvas canvas, Offset left, Offset right, double r) {
    _drawRoundEye(canvas, left, r);
    _drawRoundEye(canvas, right, r);
  }

  void _drawRoundEye(Canvas canvas, Offset center, double r) {
    final whitePaint = Paint()..color = Colors.white;
    final irisPaint = Paint()..color = eyeColor;
    final pupilPaint = Paint()..color = const Color(0xFF1A1A2E);

    canvas.drawCircle(center, r, whitePaint);
    canvas.drawCircle(center.translate(r * 0.12, 0), r * 0.58, irisPaint);
    canvas.drawCircle(center.translate(r * 0.15, 0), r * 0.32, pupilPaint);
    // Highlight
    canvas.drawCircle(
        center.translate(r * 0.30, -r * 0.25), r * 0.18, whitePaint);
  }

  void _drawAlmondEyes(Canvas canvas, Offset left, Offset right, double r) {
    for (final center in [left, right]) {
      // Almond shape — pointed at corners
      final path = Path()
        ..moveTo(center.dx - r * 1.2, center.dy)
        ..quadraticBezierTo(
            center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy)
        ..quadraticBezierTo(
            center.dx, center.dy + r * 0.8, center.dx - r * 1.2, center.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);

      // Iris
      canvas.drawCircle(
          center.translate(r * 0.10, 0), r * 0.50, Paint()..color = eyeColor);
      // Pupil
      canvas.drawCircle(center.translate(r * 0.12, 0), r * 0.28,
          Paint()..color = const Color(0xFF1A1A2E));
      // Highlight
      canvas.drawCircle(
          center.translate(r * 0.28, -r * 0.20), r * 0.15, Paint()..color = Colors.white);
    }
  }

  void _drawWinkEye(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.2),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
  }

  void _drawSleepyEyes(Canvas canvas, Offset left, Offset right, double r) {
    for (final center in [left, right]) {
      // Half-open eye
      final whitePaint = Paint()..color = Colors.white;
      // Bottom half of eye visible
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          center.dx - r * 1.2, center.dy - r * 0.15, r * 2.4, r * 1.2));
      canvas.drawCircle(center, r, whitePaint);
      canvas.drawCircle(
          center.translate(r * 0.1, 0.05), r * 0.55, Paint()..color = eyeColor);
      canvas.drawCircle(center.translate(r * 0.12, 0.05), r * 0.30,
          Paint()..color = const Color(0xFF1A1A2E));
      canvas.restore();

      // Eyelid line
      final lidPaint = Paint()
        ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(center.dx - r * 0.9, center.dy - r * 0.1),
        Offset(center.dx + r * 0.9, center.dy - r * 0.1),
        lidPaint,
      );
    }
  }

  void _drawCrescentEyes(Canvas canvas, Offset left, Offset right, double r) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(center: left, width: r * 2, height: r * 1.5),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: right, width: r * 2, height: r * 1.5),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
  }

  void _drawSparkleEyes(Canvas canvas, Offset left, Offset right, double r) {
    final bigR = r * 1.3;
    final whitePaint = Paint()..color = Colors.white;
    final irisPaint = Paint()..color = eyeColor;

    for (final center in [left, right]) {
      canvas.drawCircle(center, bigR, whitePaint);
      canvas.drawCircle(center, bigR * 0.65, irisPaint);
      // Large sparkle highlights
      canvas.drawCircle(
          center.translate(bigR * 0.3, -bigR * 0.2), bigR * 0.28, whitePaint);
      canvas.drawCircle(
          center.translate(-bigR * 0.2, bigR * 0.25), bigR * 0.14, whitePaint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final outerX = center.dx + r * cos(outerAngle);
      final outerY = center.dy + r * sin(outerAngle);
      final innerX = center.dx + r * 0.4 * cos(innerAngle);
      final innerY = center.dy + r * 0.4 * sin(innerAngle);
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EyesPainter old) =>
      old.style != style || old.eyeColor != eyeColor;
}

// ══════════════════════════════════════════════════════════════════════
//  EYELASH PAINTER
// ══════════════════════════════════════════════════════════════════════

class _EyelashPainter extends CustomPainter {
  final int style;
  final int eyeStyle;

  _EyelashPainter({required this.style, required this.eyeStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Lashes sit above the eyes
    final leftX = w * 0.25;
    final rightX = w * 0.75;
    final eyeY = h * 0.65; // center of eye zone in this canvas
    final r = w * 0.12;

    final lashPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (style) {
      case 1: // Natural — 3 short lashes per eye
        lashPaint.strokeWidth = r * 0.12;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.4;
            canvas.drawLine(
              Offset(cx + r * 0.8 * cos(angle), eyeY + r * 0.8 * sin(angle)),
              Offset(cx + r * 1.2 * cos(angle), eyeY + r * 1.2 * sin(angle)),
              lashPaint,
            );
          }
        }

      case 2: // Long — 3 longer lashes
        lashPaint.strokeWidth = r * 0.14;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.35;
            canvas.drawLine(
              Offset(cx + r * 0.7 * cos(angle), eyeY + r * 0.7 * sin(angle)),
              Offset(cx + r * 1.5 * cos(angle), eyeY + r * 1.5 * sin(angle)),
              lashPaint,
            );
          }
        }

      case 3: // Dramatic — 5 lashes fanning out
        lashPaint.strokeWidth = r * 0.15;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 5; i++) {
            final angle = -pi * 0.75 + i * 0.25;
            canvas.drawLine(
              Offset(cx + r * 0.75 * cos(angle), eyeY + r * 0.75 * sin(angle)),
              Offset(cx + r * 1.45 * cos(angle), eyeY + r * 1.45 * sin(angle)),
              lashPaint,
            );
          }
        }

      case 4: // Flutter — curved lashes
        lashPaint.strokeWidth = r * 0.12;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 4; i++) {
            final angle = -pi * 0.7 + i * 0.28;
            final startX = cx + r * 0.78 * cos(angle);
            final startY = eyeY + r * 0.78 * sin(angle);
            final endX = cx + r * 1.4 * cos(angle - 0.15);
            final endY = eyeY + r * 1.4 * sin(angle - 0.15);
            final path = Path()
              ..moveTo(startX, startY)
              ..quadraticBezierTo(
                cx + r * 1.1 * cos(angle + 0.1),
                eyeY + r * 1.1 * sin(angle + 0.1),
                endX,
                endY,
              );
            canvas.drawPath(path, lashPaint);
          }
        }

      case 5: // Sparkle — lashes with tiny stars
        lashPaint.strokeWidth = r * 0.12;
        final starPaint = Paint()..color = AppColors.starGold;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.4;
            final ex = cx + r * 1.3 * cos(angle);
            final ey = eyeY + r * 1.3 * sin(angle);
            canvas.drawLine(
              Offset(cx + r * 0.8 * cos(angle), eyeY + r * 0.8 * sin(angle)),
              Offset(ex, ey),
              lashPaint,
            );
            // Tiny star at tip
            _drawTinyStar(canvas, Offset(ex, ey), r * 0.15, starPaint);
          }
        }
    }
  }

  void _drawTinyStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      if (i == 0) {
        path.moveTo(center.dx, center.dy - r);
      }
      path.lineTo(center.dx + r * 0.3 * cos(angle + pi / 4),
          center.dy + r * 0.3 * sin(angle + pi / 4));
      path.lineTo(center.dx + r * cos(angle + pi / 2),
          center.dy + r * sin(angle + pi / 2));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EyelashPainter old) =>
      old.style != style || old.eyeStyle != eyeStyle;
}

// ══════════════════════════════════════════════════════════════════════
//  EYEBROW PAINTER
// ══════════════════════════════════════════════════════════════════════

class _EyebrowPainter extends CustomPainter {
  final int style;
  final Color color;

  _EyebrowPainter({required this.style, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Use hair color darkened slightly for brows
    final browColor = Color.lerp(color, const Color(0xFF1A1A2E), 0.3)!;
    final paint = Paint()
      ..color = browColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final leftStart = Offset(w * 0.10, h * 0.50);
    final leftEnd = Offset(w * 0.40, h * 0.50);
    final rightStart = Offset(w * 0.60, h * 0.50);
    final rightEnd = Offset(w * 0.90, h * 0.50);

    switch (style) {
      case 0: // Natural — gentle arch
        paint.strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, paint);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, paint);

      case 1: // Thin
        paint.strokeWidth = w * 0.022;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.20, paint);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.20, paint);

      case 2: // Thick
        paint.strokeWidth = w * 0.055;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, paint);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, paint);

      case 3: // Arched — high arch
        paint.strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.50, paint);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.50, paint);

      case 4: // Straight
        paint.strokeWidth = w * 0.035;
        canvas.drawLine(leftStart, leftEnd, paint);
        canvas.drawLine(rightStart, rightEnd, paint);

      case 5: // Bushy — thick with texture
        paint.strokeWidth = w * 0.05;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.22, paint);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.22, paint);
        // Extra texture strokes
        paint.strokeWidth = w * 0.02;
        paint.color = browColor.withValues(alpha: 0.5);
        _drawBrow(
            canvas,
            leftStart.translate(0, -h * 0.08),
            leftEnd.translate(0, -h * 0.08),
            -h * 0.15,
            paint);
        _drawBrow(
            canvas,
            rightStart.translate(0, -h * 0.08),
            rightEnd.translate(0, -h * 0.08),
            -h * 0.15,
            paint);
    }
  }

  void _drawBrow(
      Canvas canvas, Offset start, Offset end, double archHeight, Paint paint) {
    final mid = Offset((start.dx + end.dx) / 2, start.dy + archHeight);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EyebrowPainter old) =>
      old.style != style || old.color != color;
}

// ══════════════════════════════════════════════════════════════════════
//  MOUTH PAINTER
// ══════════════════════════════════════════════════════════════════════

class _MouthPainter extends CustomPainter {
  final int style;
  final Color lipColor;

  _MouthPainter({required this.style, required this.lipColor});

  // Natural lip color is transparent → use default dark
  Color get _effectiveLipFill =>
      (lipColor.a * 255.0).round().clamp(0, 255) == 0 ? const Color(0xFF1A1A2E) : lipColor;

  bool get _hasLipColor => (lipColor.a * 255.0).round().clamp(0, 255) > 0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    switch (style) {
      case 0: // Smile
        final paint = Paint()
          ..color = _hasLipColor ? _effectiveLipFill : const Color(0xFF1A1A2E)
          ..style = _hasLipColor ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = w * 0.08
          ..strokeCap = StrokeCap.round;
        if (_hasLipColor) {
          // Filled smile
          final path = Path()
            ..moveTo(w * 0.10, h * 0.20)
            ..quadraticBezierTo(w * 0.50, h * 1.0, w * 0.90, h * 0.20)
            ..quadraticBezierTo(w * 0.50, h * 0.50, w * 0.10, h * 0.20)
            ..close();
          canvas.drawPath(path, paint);
        } else {
          canvas.drawArc(
            Rect.fromLTWH(w * 0.1, -h * 0.2, w * 0.8, h * 1.0),
            0.2,
            pi * 0.6,
            false,
            paint,
          );
        }

      case 1: // Big Grin
        final path = Path()
          ..moveTo(w * 0.05, h * 0.2)
          ..quadraticBezierTo(w * 0.5, h * 1.2, w * 0.95, h * 0.2)
          ..close();
        canvas.drawPath(path, Paint()..color = _effectiveLipFill);
        // Teeth
        canvas.drawRect(
          Rect.fromLTWH(w * 0.25, h * 0.2, w * 0.5, h * 0.2),
          Paint()..color = Colors.white,
        );

      case 2: // Tongue Out
        final path = Path()
          ..moveTo(w * 0.10, h * 0.15)
          ..quadraticBezierTo(w * 0.5, h * 1.0, w * 0.90, h * 0.15)
          ..close();
        canvas.drawPath(path, Paint()..color = _effectiveLipFill);
        // Tongue
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.65),
            width: w * 0.35,
            height: h * 0.55,
          ),
          Paint()..color = const Color(0xFFFF6B8A),
        );

      case 3: // Surprised O
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.45),
            width: w * 0.45,
            height: h * 0.80,
          ),
          Paint()..color = _effectiveLipFill,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.45),
            width: w * 0.30,
            height: h * 0.55,
          ),
          Paint()..color = const Color(0xFF2D2D4E),
        );

      case 4: // Kissy — puckered lips
        final path = Path()
          ..moveTo(w * 0.25, h * 0.30)
          ..quadraticBezierTo(w * 0.15, h * 0.50, w * 0.30, h * 0.70)
          ..quadraticBezierTo(w * 0.50, h * 0.90, w * 0.70, h * 0.70)
          ..quadraticBezierTo(w * 0.85, h * 0.50, w * 0.75, h * 0.30)
          ..quadraticBezierTo(w * 0.50, h * 0.45, w * 0.25, h * 0.30)
          ..close();
        canvas.drawPath(
            path, Paint()..color = _hasLipColor ? _effectiveLipFill : const Color(0xFFFF6B8A));

      case 5: // Cat Smile — w-shape
        final paint = Paint()
          ..color = _effectiveLipFill
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(w * 0.05, h * 0.30)
          ..quadraticBezierTo(w * 0.25, h * 0.70, w * 0.50, h * 0.25)
          ..quadraticBezierTo(w * 0.75, h * 0.70, w * 0.95, h * 0.30);
        canvas.drawPath(path, paint);

      case 6: // Smirk — asymmetric smile
        final paint = Paint()
          ..color = _effectiveLipFill
          ..style = _hasLipColor ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..strokeCap = StrokeCap.round;
        if (_hasLipColor) {
          final path = Path()
            ..moveTo(w * 0.15, h * 0.40)
            ..quadraticBezierTo(w * 0.55, h * 0.35, w * 0.90, h * 0.15)
            ..quadraticBezierTo(w * 0.55, h * 0.80, w * 0.15, h * 0.40)
            ..close();
          canvas.drawPath(path, paint);
        } else {
          final path = Path()
            ..moveTo(w * 0.15, h * 0.40)
            ..quadraticBezierTo(w * 0.55, h * 0.60, w * 0.90, h * 0.15);
          canvas.drawPath(path, paint);
        }

      case 7: // Tiny Smile — small gentle smile
        final paint = Paint()
          ..color = _effectiveLipFill
          ..style = _hasLipColor ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = w * 0.06
          ..strokeCap = StrokeCap.round;
        if (_hasLipColor) {
          final path = Path()
            ..moveTo(w * 0.30, h * 0.35)
            ..quadraticBezierTo(w * 0.50, h * 0.75, w * 0.70, h * 0.35)
            ..quadraticBezierTo(w * 0.50, h * 0.50, w * 0.30, h * 0.35)
            ..close();
          canvas.drawPath(path, paint);
        } else {
          canvas.drawArc(
            Rect.fromLTWH(w * 0.25, -h * 0.1, w * 0.50, h * 0.80),
            0.3,
            pi * 0.4,
            false,
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_MouthPainter old) =>
      old.style != style || old.lipColor != lipColor;
}

// ══════════════════════════════════════════════════════════════════════
//  FACE PAINT PAINTER
// ══════════════════════════════════════════════════════════════════════

class _FacePaintPainter extends CustomPainter {
  final int style;

  _FacePaintPainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    switch (style) {
      case 1: // Star on left cheek
        final paint = Paint()..color = AppColors.starGold.withValues(alpha: 0.7);
        _drawStar(canvas, Offset(w * 0.18, h * 0.55), w * 0.08, paint);

      case 2: // Butterfly on right cheek
        _drawButterfly(canvas, Offset(w * 0.80, h * 0.52), w * 0.12);

      case 3: // Heart on left cheek
        final paint = Paint()..color = const Color(0xFFFF4D6A).withValues(alpha: 0.65);
        _drawHeart(canvas, Offset(w * 0.18, h * 0.55), w * 0.07, paint);

      case 4: // Rainbow across forehead
        _drawRainbow(canvas, Offset(w * 0.50, h * 0.12), w * 0.30, h * 0.08);

      case 5: // Cat whiskers
        _drawWhiskers(canvas, w, h);

      case 6: // Tiger stripes
        _drawTigerStripes(canvas, w, h);

      case 7: // Flower on right cheek
        _drawFlower(canvas, Offset(w * 0.80, h * 0.52), w * 0.08);

      case 8: // Lightning bolt on left cheek
        _drawLightning(canvas, Offset(w * 0.15, h * 0.45), w * 0.10, h * 0.18);

      case 9: // Dots across nose bridge
        _drawDots(canvas, w, h);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      } else {
        path.lineTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      }
      path.lineTo(center.dx + r * 0.4 * cos(innerAngle),
          center.dy + r * 0.4 * sin(innerAngle));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawButterfly(Canvas canvas, Offset center, double r) {
    final paint = Paint()..color = const Color(0xFFB794F6).withValues(alpha: 0.6);
    // Left wing
    canvas.drawOval(
      Rect.fromCenter(
          center: center.translate(-r * 0.4, 0), width: r * 0.8, height: r * 0.5),
      paint,
    );
    // Right wing
    canvas.drawOval(
      Rect.fromCenter(
          center: center.translate(r * 0.4, 0), width: r * 0.8, height: r * 0.5),
      paint,
    );
    // Body
    canvas.drawLine(
      center.translate(0, -r * 0.2),
      center.translate(0, r * 0.2),
      Paint()
        ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.5)
        ..strokeWidth = r * 0.08
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawRainbow(Canvas canvas, Offset center, double width, double height) {
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
        ..color = colors[i].withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandH * 0.8;
      final r = width - i * bandH;
      canvas.drawArc(
        Rect.fromCenter(center: center, width: r * 2, height: r),
        pi,
        pi,
        false,
        paint,
      );
    }
  }

  void _drawWhiskers(Canvas canvas, double w, double h) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;
    // Left whiskers
    canvas.drawLine(Offset(w * 0.05, h * 0.50), Offset(w * 0.30, h * 0.52), paint);
    canvas.drawLine(Offset(w * 0.05, h * 0.56), Offset(w * 0.30, h * 0.56), paint);
    canvas.drawLine(Offset(w * 0.05, h * 0.62), Offset(w * 0.30, h * 0.60), paint);
    // Right whiskers
    canvas.drawLine(Offset(w * 0.70, h * 0.52), Offset(w * 0.95, h * 0.50), paint);
    canvas.drawLine(Offset(w * 0.70, h * 0.56), Offset(w * 0.95, h * 0.56), paint);
    canvas.drawLine(Offset(w * 0.70, h * 0.60), Offset(w * 0.95, h * 0.62), paint);
  }

  void _drawTigerStripes(Canvas canvas, double w, double h) {
    final paint = Paint()
      ..color = const Color(0xFFFF8C42).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    // Stripes on forehead and cheeks
    canvas.drawLine(Offset(w * 0.15, h * 0.15), Offset(w * 0.30, h * 0.22), paint);
    canvas.drawLine(Offset(w * 0.10, h * 0.25), Offset(w * 0.25, h * 0.30), paint);
    canvas.drawLine(Offset(w * 0.70, h * 0.22), Offset(w * 0.85, h * 0.15), paint);
    canvas.drawLine(Offset(w * 0.75, h * 0.30), Offset(w * 0.90, h * 0.25), paint);
  }

  void _drawFlower(Canvas canvas, Offset center, double r) {
    final petalPaint = Paint()..color = const Color(0xFFFF7EB3).withValues(alpha: 0.55);
    final centerPaint = Paint()..color = AppColors.starGold.withValues(alpha: 0.6);
    for (int i = 0; i < 5; i++) {
      final angle = i * 2 * pi / 5 - pi / 2;
      canvas.drawCircle(
        Offset(center.dx + r * 0.55 * cos(angle),
            center.dy + r * 0.55 * sin(angle)),
        r * 0.35,
        petalPaint,
      );
    }
    canvas.drawCircle(center, r * 0.25, centerPaint);
  }

  void _drawLightning(Canvas canvas, Offset start, double w, double h) {
    final paint = Paint()..color = AppColors.starGold.withValues(alpha: 0.65);
    final path = Path()
      ..moveTo(start.dx + w * 0.40, start.dy)
      ..lineTo(start.dx + w * 0.10, start.dy + h * 0.45)
      ..lineTo(start.dx + w * 0.45, start.dy + h * 0.45)
      ..lineTo(start.dx + w * 0.20, start.dy + h)
      ..lineTo(start.dx + w * 0.80, start.dy + h * 0.35)
      ..lineTo(start.dx + w * 0.50, start.dy + h * 0.35)
      ..lineTo(start.dx + w * 0.70, start.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawDots(Canvas canvas, double w, double h) {
    final colors = [
      const Color(0xFFFF4D6A).withValues(alpha: 0.5),
      AppColors.starGold.withValues(alpha: 0.5),
      const Color(0xFF4A90D9).withValues(alpha: 0.5),
      const Color(0xFF00E68A).withValues(alpha: 0.5),
      const Color(0xFFB794F6).withValues(alpha: 0.5),
    ];
    for (int i = 0; i < 5; i++) {
      canvas.drawCircle(
        Offset(w * (0.30 + i * 0.10), h * 0.42),
        w * 0.018,
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(_FacePaintPainter old) => old.style != style;
}

// ══════════════════════════════════════════════════════════════════════
//  GLASSES PAINTER
// ══════════════════════════════════════════════════════════════════════

class _GlassesPainter extends CustomPainter {
  final int style;

  _GlassesPainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035;

    switch (style) {
      case 1: // Round
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(w * 0.28, h * 0.50), width: w * 0.36, height: h * 0.80),
          paint,
        );
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(w * 0.72, h * 0.50), width: w * 0.36, height: h * 0.80),
          paint,
        );
        canvas.drawLine(
            Offset(w * 0.46, h * 0.45), Offset(w * 0.54, h * 0.45), paint);

      case 2: // Square
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.28, h * 0.50),
                width: w * 0.36,
                height: h * 0.72),
            Radius.circular(w * 0.03),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.72, h * 0.50),
                width: w * 0.36,
                height: h * 0.72),
            Radius.circular(w * 0.03),
          ),
          paint,
        );
        canvas.drawLine(
            Offset(w * 0.46, h * 0.45), Offset(w * 0.54, h * 0.45), paint);

      case 3: // Cat Eye — pointed at top corners
        for (final cx in [w * 0.28, w * 0.72]) {
          final path = Path()
            ..moveTo(cx - w * 0.16, h * 0.50)
            ..quadraticBezierTo(cx - w * 0.18, h * 0.15, cx, h * 0.20)
            ..quadraticBezierTo(cx + w * 0.18, h * 0.15, cx + w * 0.16, h * 0.50)
            ..quadraticBezierTo(cx + w * 0.14, h * 0.82, cx, h * 0.85)
            ..quadraticBezierTo(cx - w * 0.14, h * 0.82, cx - w * 0.16, h * 0.50)
            ..close();
          canvas.drawPath(path, paint);
        }
        canvas.drawLine(
            Offset(w * 0.44, h * 0.45), Offset(w * 0.56, h * 0.45), paint);

      case 4: // Star-shaped
        for (final cx in [w * 0.28, w * 0.72]) {
          _drawStarOutline(canvas, Offset(cx, h * 0.50), w * 0.17, paint);
        }
        canvas.drawLine(
            Offset(w * 0.45, h * 0.48), Offset(w * 0.55, h * 0.48), paint);

      case 5: // Heart-shaped
        for (final cx in [w * 0.28, w * 0.72]) {
          _drawHeartOutline(canvas, Offset(cx, h * 0.50), w * 0.15, paint);
        }
        canvas.drawLine(
            Offset(w * 0.43, h * 0.45), Offset(w * 0.57, h * 0.45), paint);

      case 6: // Aviator
        for (final cx in [w * 0.28, w * 0.72]) {
          final path = Path()
            ..moveTo(cx - w * 0.16, h * 0.25)
            ..lineTo(cx + w * 0.16, h * 0.25)
            ..quadraticBezierTo(
                cx + w * 0.20, h * 0.50, cx + w * 0.12, h * 0.82)
            ..quadraticBezierTo(cx, h * 0.90, cx - w * 0.12, h * 0.82)
            ..quadraticBezierTo(
                cx - w * 0.20, h * 0.50, cx - w * 0.16, h * 0.25)
            ..close();
          canvas.drawPath(path, paint);
        }
        canvas.drawLine(
            Offset(w * 0.44, h * 0.30), Offset(w * 0.56, h * 0.30), paint);
    }
  }

  void _drawStarOutline(
      Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      } else {
        path.lineTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      }
      path.lineTo(center.dx + r * 0.45 * cos(innerAngle),
          center.dy + r * 0.45 * sin(innerAngle));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeartOutline(
      Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(x - r * 1.3, y - r * 0.3, x - r * 0.5, y - r * 1.1, x, y - r * 0.3)
      ..cubicTo(x + r * 0.5, y - r * 1.1, x + r * 1.3, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GlassesPainter old) => old.style != style;
}

// ══════════════════════════════════════════════════════════════════════
//  BACK HAIR PAINTER (behind the face)
// ══════════════════════════════════════════════════════════════════════

class _BackHairPainter extends CustomPainter {
  final int style;
  final Color color;
  final bool isRainbow;
  final int faceShape;

  _BackHairPainter({
    required this.style,
    required this.color,
    this.isRainbow = false,
    this.faceShape = 0,
  });

  Paint get _paint {
    if (isRainbow) {
      return Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF4444),
            Color(0xFFFF8C42),
            Color(0xFFFFD700),
            Color(0xFF00E68A),
            Color(0xFF4A90D9),
            Color(0xFF9B59B6),
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    }
    return Paint()..color = color;
  }

  /// Get face-shape-aware inner edge offsets.
  /// Returns (innerLeft, innerRight, innerTop) as fractions of w/h.
  ({double left, double right, double top}) _innerEdge() {
    switch (faceShape) {
      case 1: // Square — wider, flatter top
        return (left: 0.16, right: 0.84, top: 0.19);
      case 2: // Oval — narrower at top
        return (left: 0.22, right: 0.78, top: 0.18);
      case 3: // Heart — dips in center top
        return (left: 0.20, right: 0.80, top: 0.19);
      case 4: // Diamond — pointed top, narrow
        return (left: 0.26, right: 0.74, top: 0.18);
      default: // Round
        return (left: 0.18, right: 0.82, top: 0.19);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = _paint..style = PaintingStyle.fill;
    final ie = _innerEdge();

    switch (style) {
      case 1: // Long — flowing down sides behind face
        final path = Path()
          ..moveTo(w * 0.10, h * 0.75)
          ..lineTo(w * 0.10, h * 0.32)
          ..quadraticBezierTo(w * 0.10, h * 0.08, w * 0.50, h * 0.05)
          ..quadraticBezierTo(w * 0.90, h * 0.08, w * 0.90, h * 0.32)
          ..lineTo(w * 0.90, h * 0.75)
          ..quadraticBezierTo(w * 0.88, h * 0.82, w * ie.right, h * 0.78)
          ..lineTo(w * ie.right, h * 0.35)
          ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
          ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
          ..lineTo(w * ie.left, h * 0.78)
          ..quadraticBezierTo(w * 0.12, h * 0.82, w * 0.10, h * 0.75)
          ..close();
        canvas.drawPath(path, paint);

      case 10: // Wavy — long wavy flowing behind
        final path = Path()
          ..moveTo(w * 0.08, h * 0.78)
          ..quadraticBezierTo(w * 0.05, h * 0.60, w * 0.10, h * 0.32)
          ..quadraticBezierTo(w * 0.10, h * 0.08, w * 0.50, h * 0.05)
          ..quadraticBezierTo(w * 0.90, h * 0.08, w * 0.90, h * 0.32)
          ..quadraticBezierTo(w * 0.95, h * 0.60, w * 0.92, h * 0.78)
          ..quadraticBezierTo(w * 0.88, h * 0.85, w * 0.84, h * 0.78)
          ..quadraticBezierTo(w * 0.86, h * 0.60, w * ie.right, h * 0.35)
          ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
          ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
          ..quadraticBezierTo(w * 0.14, h * 0.60, w * 0.16, h * 0.78)
          ..quadraticBezierTo(w * 0.12, h * 0.85, w * 0.08, h * 0.78)
          ..close();
        canvas.drawPath(path, paint);

      case 14: // Long Wavy — even longer, past shoulders
        final path = Path()
          ..moveTo(w * 0.06, h * 0.88)
          ..quadraticBezierTo(w * 0.04, h * 0.60, w * 0.10, h * 0.32)
          ..quadraticBezierTo(w * 0.10, h * 0.08, w * 0.50, h * 0.05)
          ..quadraticBezierTo(w * 0.90, h * 0.08, w * 0.90, h * 0.32)
          ..quadraticBezierTo(w * 0.96, h * 0.60, w * 0.94, h * 0.88)
          ..quadraticBezierTo(w * 0.90, h * 0.95, w * 0.84, h * 0.85)
          ..quadraticBezierTo(w * 0.86, h * 0.60, w * ie.right, h * 0.35)
          ..quadraticBezierTo(w * ie.right, h * ie.top, w * 0.50, h * ie.top)
          ..quadraticBezierTo(w * ie.left, h * ie.top, w * ie.left, h * 0.35)
          ..quadraticBezierTo(w * 0.14, h * 0.60, w * 0.16, h * 0.85)
          ..quadraticBezierTo(w * 0.10, h * 0.95, w * 0.06, h * 0.88)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BackHairPainter old) =>
      old.style != style ||
      old.color != color ||
      old.isRainbow != isRainbow ||
      old.faceShape != faceShape;
}

// ══════════════════════════════════════════════════════════════════════
//  FRONT HAIR PAINTER (on top of face)
// ══════════════════════════════════════════════════════════════════════

class _FrontHairPainter extends CustomPainter {
  final int style;
  final Color color;
  final bool isRainbow;
  final int faceShape;

  _FrontHairPainter({
    required this.style,
    required this.color,
    this.isRainbow = false,
    this.faceShape = 0,
  });

  Paint get _paint {
    if (isRainbow) {
      return Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF4444),
            Color(0xFFFF8C42),
            Color(0xFFFFD700),
            Color(0xFF00E68A),
            Color(0xFF4A90D9),
            Color(0xFF9B59B6),
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    }
    return Paint()..color = color;
  }

  /// Face-shape-aware edge positions for the hair's inner cutout.
  /// The inner edge must hug the face shape to avoid gaps.
  /// Returns (outerLeft, outerRight, outerBottom, innerLeft, innerRight, innerTop)
  ({double oL, double oR, double oB, double iL, double iR, double iT})
      _edges() {
    switch (faceShape) {
      case 1: // Square — wider face, needs wider hair
        return (
          oL: 0.12,
          oR: 0.88,
          oB: 0.38,
          iL: 0.16,
          iR: 0.84,
          iT: 0.20
        );
      case 2: // Oval — narrower, taller face
        return (
          oL: 0.14,
          oR: 0.86,
          oB: 0.36,
          iL: 0.22,
          iR: 0.78,
          iT: 0.19
        );
      case 3: // Heart — wide top with center dip
        return (
          oL: 0.12,
          oR: 0.88,
          oB: 0.37,
          iL: 0.18,
          iR: 0.82,
          iT: 0.20
        );
      case 4: // Diamond — pointed top, narrow sides
        return (
          oL: 0.14,
          oR: 0.86,
          oB: 0.36,
          iL: 0.24,
          iR: 0.76,
          iT: 0.19
        );
      default: // Round
        return (
          oL: 0.13,
          oR: 0.87,
          oB: 0.37,
          iL: 0.18,
          iR: 0.82,
          iT: 0.20
        );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _paint..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final e = _edges();

    switch (style) {
      case 0: // Short — flat top hair
        final path = Path()
          ..moveTo(w * e.oL, h * e.oB)
          ..quadraticBezierTo(w * e.oL, h * 0.10, w * 0.35, h * 0.08)
          ..quadraticBezierTo(w * 0.50, h * 0.04, w * 0.65, h * 0.08)
          ..quadraticBezierTo(w * e.oR, h * 0.10, w * e.oR, h * e.oB)
          ..lineTo(w * e.oR, h * 0.28)
          ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.65, h * (e.iT + 0.04))
          ..quadraticBezierTo(
              w * 0.50, h * e.iT, w * 0.35, h * (e.iT + 0.04))
          ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.oL, h * 0.28)
          ..close();
        canvas.drawPath(path, paint);

      case 1: // Long — front bang fringe
        final path = Path()
          ..moveTo(w * e.oL, h * e.oB)
          ..quadraticBezierTo(w * e.oL, h * 0.10, w * 0.35, h * 0.08)
          ..quadraticBezierTo(w * 0.50, h * 0.04, w * 0.65, h * 0.08)
          ..quadraticBezierTo(w * e.oR, h * 0.10, w * e.oR, h * e.oB)
          ..lineTo(w * e.iR, h * 0.28)
          ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
          ..close();
        canvas.drawPath(path, paint);

      case 2: // Curly — bumpy silhouette
        final path = Path()
          ..moveTo(w * 0.10, h * 0.40);
        path.quadraticBezierTo(w * 0.04, h * 0.30, w * 0.08, h * 0.20);
        path.quadraticBezierTo(w * 0.10, h * 0.10, w * 0.22, h * 0.07);
        path.quadraticBezierTo(w * 0.30, h * 0.01, w * 0.42, h * 0.04);
        path.quadraticBezierTo(w * 0.50, h * 0.00, w * 0.58, h * 0.04);
        path.quadraticBezierTo(w * 0.70, h * 0.01, w * 0.78, h * 0.07);
        path.quadraticBezierTo(w * 0.90, h * 0.10, w * 0.92, h * 0.20);
        path.quadraticBezierTo(w * 0.96, h * 0.30, w * 0.90, h * 0.40);
        path.quadraticBezierTo(w * 0.94, h * 0.52, w * 0.88, h * 0.58);
        path.lineTo(w * e.iR, h * 0.35);
        path.quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT);
        path.quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.35);
        path.lineTo(w * 0.12, h * 0.58);
        path.quadraticBezierTo(w * 0.06, h * 0.52, w * 0.10, h * 0.40);
        path.close();
        canvas.drawPath(path, paint);

      case 3: // Braids — top cap + two braids
        _drawHairCap(canvas, paint, w, h);
        _drawBraid(
            canvas, paint, Offset(w * e.oL, h * e.oB), w * 0.07, h * 0.08, 4);
        _drawBraid(canvas, paint, Offset(w * (e.oR - 0.07), h * e.oB),
            w * 0.07, h * 0.08, 4);

      case 4: // Ponytail — cap + side tail
        _drawHairCap(canvas, paint, w, h);
        final tail = Path()
          ..moveTo(w * e.iR, h * 0.22)
          ..quadraticBezierTo(w * 0.95, h * 0.20, w * 0.96, h * 0.35)
          ..quadraticBezierTo(w * 0.97, h * 0.55, w * 0.90, h * 0.65)
          ..quadraticBezierTo(w * 0.84, h * 0.58, w * 0.86, h * 0.40)
          ..quadraticBezierTo(w * 0.88, h * 0.28, w * e.iR, h * 0.26)
          ..close();
        canvas.drawPath(tail, paint);

      case 5: // Buzz — thin stubble
        final path = Path()
          ..moveTo(w * (e.oL + 0.01), h * 0.30)
          ..quadraticBezierTo(w * (e.oL + 0.01), h * 0.12, w * 0.50, h * 0.10)
          ..quadraticBezierTo(w * (e.oR - 0.01), h * 0.12,
              w * (e.oR - 0.01), h * 0.30)
          ..lineTo(w * (e.iR - 0.02), h * 0.26)
          ..quadraticBezierTo(w * (e.iR - 0.02), h * e.iT, w * 0.50,
              h * (e.iT + 0.02))
          ..quadraticBezierTo(w * (e.iL + 0.02), h * e.iT,
              w * (e.iL + 0.02), h * 0.26)
          ..close();
        canvas.drawPath(path, paint);

      case 6: // Afro — big round puff
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.50, h * 0.28),
            width: w * 0.86,
            height: h * 0.48,
          ),
          paint,
        );

      case 7: // Bun — cap + bun on top
        _drawHairCap(canvas, paint, w, h);
        canvas.drawCircle(Offset(w * 0.50, h * 0.06), w * 0.14, paint);

      case 8: // Pigtails — cap + two side buns
        _drawHairCap(canvas, paint, w, h);
        canvas.drawCircle(
            Offset(w * (e.oL - 0.03), h * 0.32), w * 0.10, paint);
        canvas.drawCircle(
            Offset(w * (e.oR + 0.03), h * 0.32), w * 0.10, paint);

      case 9: // Bob — chin-length with curve
        final path = Path()
          ..moveTo(w * 0.10, h * 0.58)
          ..quadraticBezierTo(w * 0.08, h * 0.30, w * e.oL, h * 0.14)
          ..quadraticBezierTo(w * 0.20, h * 0.06, w * 0.50, h * 0.05)
          ..quadraticBezierTo(w * 0.80, h * 0.06, w * e.oR, h * 0.14)
          ..quadraticBezierTo(w * 0.92, h * 0.30, w * 0.90, h * 0.58)
          ..quadraticBezierTo(w * 0.88, h * 0.64, w * e.iR, h * 0.60)
          ..quadraticBezierTo(w * e.iR, h * 0.30, w * e.iR, h * 0.25)
          ..quadraticBezierTo(w * (e.iR - 0.02), h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * (e.iL + 0.02), h * e.iT, w * e.iL, h * 0.25)
          ..quadraticBezierTo(w * e.iL, h * 0.30, w * e.iL, h * 0.60)
          ..quadraticBezierTo(w * 0.12, h * 0.64, w * 0.10, h * 0.58)
          ..close();
        canvas.drawPath(path, paint);

      case 10: // Wavy — front fringe
        final path = Path()
          ..moveTo(w * e.oL, h * e.oB)
          ..quadraticBezierTo(w * 0.10, h * 0.12, w * 0.30, h * 0.08)
          ..quadraticBezierTo(w * 0.40, h * 0.04, w * 0.50, h * 0.06)
          ..quadraticBezierTo(w * 0.60, h * 0.03, w * 0.70, h * 0.08)
          ..quadraticBezierTo(w * 0.90, h * 0.12, w * e.oR, h * e.oB)
          ..lineTo(w * e.iR, h * 0.28)
          ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
          ..close();
        canvas.drawPath(path, paint);

      case 11: // Side Swept — parted to one side
        final path = Path()
          ..moveTo(w * e.oL, h * 0.30)
          ..quadraticBezierTo(w * 0.10, h * 0.10, w * 0.35, h * 0.06)
          ..quadraticBezierTo(w * 0.60, h * 0.03, w * 0.80, h * 0.08)
          ..quadraticBezierTo(w * 0.92, h * 0.12, w * e.oR, h * 0.38)
          ..lineTo(w * e.iR, h * 0.28)
          ..quadraticBezierTo(w * 0.75, h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * e.iL, h * (e.iT - 0.02), w * e.oL, h * 0.30)
          ..close();
        canvas.drawPath(path, paint);

      case 12: // Mohawk — tall center strip
        final path = Path()
          ..moveTo(w * 0.35, h * 0.25)
          ..quadraticBezierTo(w * 0.38, h * -0.05, w * 0.50, h * -0.08)
          ..quadraticBezierTo(w * 0.62, h * -0.05, w * 0.65, h * 0.25)
          ..quadraticBezierTo(w * 0.58, h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * 0.42, h * e.iT, w * 0.35, h * 0.25)
          ..close();
        canvas.drawPath(path, paint);
        // Thin sides
        final sides = Path()
          ..moveTo(w * (e.oL + 0.01), h * 0.30)
          ..quadraticBezierTo(w * (e.oL + 0.01), h * 0.18, w * 0.35, h * 0.18)
          ..lineTo(w * 0.35, h * 0.24)
          ..quadraticBezierTo(
              w * (e.iL), h * e.iT, w * (e.oL + 0.03), h * 0.28)
          ..close();
        canvas.drawPath(sides, paint);
        final sidesR = Path()
          ..moveTo(w * (e.oR - 0.01), h * 0.30)
          ..quadraticBezierTo(
              w * (e.oR - 0.01), h * 0.18, w * 0.65, h * 0.18)
          ..lineTo(w * 0.65, h * 0.24)
          ..quadraticBezierTo(
              w * (e.iR), h * e.iT, w * (e.oR - 0.03), h * 0.28)
          ..close();
        canvas.drawPath(sidesR, paint);

      case 13: // Space Buns — cap + two buns on top
        _drawHairCap(canvas, paint, w, h);
        canvas.drawCircle(Offset(w * 0.28, h * 0.06), w * 0.12, paint);
        canvas.drawCircle(Offset(w * 0.72, h * 0.06), w * 0.12, paint);

      case 14: // Long Wavy — front fringe
        final path = Path()
          ..moveTo(w * e.oL, h * e.oB)
          ..quadraticBezierTo(w * 0.10, h * 0.10, w * 0.30, h * 0.06)
          ..quadraticBezierTo(w * 0.42, h * 0.02, w * 0.55, h * 0.05)
          ..quadraticBezierTo(w * 0.68, h * 0.02, w * 0.80, h * 0.06)
          ..quadraticBezierTo(w * 0.90, h * 0.10, w * e.oR, h * e.oB)
          ..lineTo(w * e.iR, h * 0.28)
          ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * e.iT)
          ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
          ..close();
        canvas.drawPath(path, paint);

      case 15: // Fishtail braid — cap + single braid down the back
        _drawHairCap(canvas, paint, w, h);
        _drawBraid(
            canvas, paint, Offset(w * 0.44, h * 0.30), w * 0.08, h * 0.09, 5);
    }
  }

  void _drawHairCap(Canvas canvas, Paint paint, double w, double h) {
    final e = _edges();
    final path = Path()
      ..moveTo(w * e.oL, h * e.oB)
      ..quadraticBezierTo(w * e.oL, h * 0.08, w * 0.50, h * 0.06)
      ..quadraticBezierTo(w * e.oR, h * 0.08, w * e.oR, h * e.oB)
      ..lineTo(w * e.iR, h * 0.28)
      ..quadraticBezierTo(w * e.iR, h * e.iT, w * 0.50, h * (e.iT + 0.02))
      ..quadraticBezierTo(w * e.iL, h * e.iT, w * e.iL, h * 0.28)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawBraid(Canvas canvas, Paint paint, Offset start, double w,
      double h, int segments) {
    for (int i = 0; i < segments; i++) {
      final y = start.dy + i * h * 0.9;
      final xOff = (i.isEven) ? -w * 0.2 : w * 0.2;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(start.dx + w / 2 + xOff, y + h / 2),
          width: w,
          height: h,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FrontHairPainter old) =>
      old.style != style ||
      old.color != color ||
      old.isRainbow != isRainbow ||
      old.faceShape != faceShape;
}

// ══════════════════════════════════════════════════════════════════════
//  ACCESSORY PAINTERS
// ══════════════════════════════════════════════════════════════════════

class _CrownPainter extends CustomPainter {
  final Color color;
  final bool jewels;

  _CrownPainter({required this.color, this.jewels = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = color;

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.4)
      ..lineTo(w * 0.15, h * 0.6)
      ..lineTo(w * 0.30, h * 0.1)
      ..lineTo(w * 0.50, h * 0.5)
      ..lineTo(w * 0.70, h * 0.1)
      ..lineTo(w * 0.85, h * 0.6)
      ..lineTo(w, h * 0.4)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, paint);

    if (jewels) {
      canvas.drawCircle(
          Offset(w * 0.30, h * 0.45), w * 0.05, Paint()..color = const Color(0xFFFF4D6A));
      canvas.drawCircle(
          Offset(w * 0.50, h * 0.65), w * 0.05, Paint()..color = AppColors.electricBlue);
      canvas.drawCircle(
          Offset(w * 0.70, h * 0.45), w * 0.05, Paint()..color = AppColors.emerald);
    }
  }

  @override
  bool shouldRepaint(_CrownPainter old) =>
      old.color != color || old.jewels != jewels;
}

class _FlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final petalR = size.width * 0.28;
    final paint = Paint()..color = const Color(0xFFFF7EB3);

    for (int i = 0; i < 5; i++) {
      final angle = i * 2 * pi / 5 - pi / 2;
      canvas.drawCircle(
        Offset(c.dx + petalR * cos(angle), c.dy + petalR * sin(angle)),
        petalR * 0.55,
        paint,
      );
    }
    canvas.drawCircle(c, petalR * 0.4, Paint()..color = AppColors.starGold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = const Color(0xFFFF7EB3);

    canvas.drawOval(Rect.fromLTWH(0, 0, w * 0.45, h), paint);
    canvas.drawOval(Rect.fromLTWH(w * 0.55, 0, w * 0.45, h), paint);
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.5),
      w * 0.1,
      Paint()..color = const Color(0xFFE0559D),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = const Color(0xFF4A90D9);

    final dome = Path()
      ..moveTo(w * 0.05, h * 0.85)
      ..quadraticBezierTo(w * 0.05, h * 0.15, w * 0.50, h * 0.12)
      ..quadraticBezierTo(w * 0.95, h * 0.15, w * 0.95, h * 0.85)
      ..close();
    canvas.drawPath(dome, paint);

    final brim = Path()
      ..moveTo(0, h * 0.85)
      ..quadraticBezierTo(w * 0.5, h * 0.95, w, h * 0.85)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(brim, Paint()..color = const Color(0xFF3B7AC7));

    canvas.drawCircle(
        Offset(w * 0.50, h * 0.15), w * 0.05, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WizardHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final hat = Path()
      ..moveTo(w * 0.50, 0)
      ..lineTo(w * 0.05, h * 0.85)
      ..quadraticBezierTo(w * 0.50, h * 0.75, w * 0.95, h * 0.85)
      ..close();
    canvas.drawPath(hat, Paint()..color = AppColors.violet);

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.85), width: w, height: h * 0.30),
      Paint()..color = AppColors.violet,
    );

    _drawStar(canvas, Offset(w * 0.48, h * 0.38), w * 0.10,
        Paint()..color = AppColors.starGold);
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      } else {
        path.lineTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      }
      path.lineTo(center.dx + r * 0.4 * cos(innerAngle),
          center.dy + r * 0.4 * sin(innerAngle));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final wingPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.5);
    final wingOutline = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008;

    final leftWing = Path()
      ..moveTo(w * 0.38, h * 0.45)
      ..quadraticBezierTo(w * 0.10, h * 0.10, w * 0.02, h * 0.40)
      ..quadraticBezierTo(w * 0.0, h * 0.70, w * 0.20, h * 0.90)
      ..quadraticBezierTo(w * 0.30, h * 0.75, w * 0.38, h * 0.55)
      ..close();
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(leftWing, wingOutline);

    final rightWing = Path()
      ..moveTo(w * 0.62, h * 0.45)
      ..quadraticBezierTo(w * 0.90, h * 0.10, w * 0.98, h * 0.40)
      ..quadraticBezierTo(w * 1.0, h * 0.70, w * 0.80, h * 0.90)
      ..quadraticBezierTo(w * 0.70, h * 0.75, w * 0.62, h * 0.55)
      ..close();
    canvas.drawPath(rightWing, wingPaint);
    canvas.drawPath(rightWing, wingOutline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TiaraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bandPaint = Paint()..color = const Color(0xFFFFB6C1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.55, w, h * 0.35),
        Radius.circular(h * 0.15),
      ),
      bandPaint,
    );

    final path = Path()
      ..moveTo(w * 0.10, h * 0.65)
      ..lineTo(w * 0.20, h * 0.20)
      ..lineTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.40, h * 0.10)
      ..lineTo(w * 0.50, h * 0.45)
      ..lineTo(w * 0.60, h * 0.10)
      ..lineTo(w * 0.70, h * 0.55)
      ..lineTo(w * 0.80, h * 0.20)
      ..lineTo(w * 0.90, h * 0.65)
      ..close();
    canvas.drawPath(path, bandPaint);

    canvas.drawCircle(
        Offset(w * 0.40, h * 0.18), w * 0.035, Paint()..color = const Color(0xFFE0559D));
    canvas.drawCircle(
        Offset(w * 0.60, h * 0.18), w * 0.035, Paint()..color = const Color(0xFFE0559D));
    canvas.drawCircle(
        Offset(w * 0.50, h * 0.50), w * 0.04, Paint()..color = AppColors.starGold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BunnyEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outerPaint = Paint()..color = const Color(0xFFF5F5F5);
    final innerPaint = Paint()..color = const Color(0xFFFFB6C1);

    final leftOuter = Path()
      ..moveTo(w * 0.20, h * 0.95)
      ..quadraticBezierTo(w * 0.05, h * 0.50, w * 0.15, h * 0.05)
      ..quadraticBezierTo(w * 0.25, h * 0.00, w * 0.35, h * 0.15)
      ..quadraticBezierTo(w * 0.40, h * 0.55, w * 0.35, h * 0.95)
      ..close();
    canvas.drawPath(leftOuter, outerPaint);

    final leftInner = Path()
      ..moveTo(w * 0.22, h * 0.85)
      ..quadraticBezierTo(w * 0.12, h * 0.52, w * 0.18, h * 0.15)
      ..quadraticBezierTo(w * 0.24, h * 0.08, w * 0.32, h * 0.22)
      ..quadraticBezierTo(w * 0.36, h * 0.55, w * 0.32, h * 0.85)
      ..close();
    canvas.drawPath(leftInner, innerPaint);

    final rightOuter = Path()
      ..moveTo(w * 0.65, h * 0.95)
      ..quadraticBezierTo(w * 0.60, h * 0.55, w * 0.65, h * 0.15)
      ..quadraticBezierTo(w * 0.75, h * 0.00, w * 0.85, h * 0.05)
      ..quadraticBezierTo(w * 0.95, h * 0.50, w * 0.80, h * 0.95)
      ..close();
    canvas.drawPath(rightOuter, outerPaint);

    final rightInner = Path()
      ..moveTo(w * 0.68, h * 0.85)
      ..quadraticBezierTo(w * 0.64, h * 0.55, w * 0.68, h * 0.22)
      ..quadraticBezierTo(w * 0.76, h * 0.08, w * 0.82, h * 0.15)
      ..quadraticBezierTo(w * 0.88, h * 0.52, w * 0.78, h * 0.85)
      ..close();
    canvas.drawPath(rightInner, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CatEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outerPaint = Paint()..color = const Color(0xFFB794F6);
    final innerPaint = Paint()..color = const Color(0xFFFFB6C1);

    final leftOuter = Path()
      ..moveTo(w * 0.10, h * 0.90)
      ..lineTo(w * 0.18, h * 0.05)
      ..lineTo(w * 0.40, h * 0.75)
      ..close();
    canvas.drawPath(leftOuter, outerPaint);
    final leftInner = Path()
      ..moveTo(w * 0.14, h * 0.78)
      ..lineTo(w * 0.20, h * 0.20)
      ..lineTo(w * 0.35, h * 0.68)
      ..close();
    canvas.drawPath(leftInner, innerPaint);

    final rightOuter = Path()
      ..moveTo(w * 0.60, h * 0.75)
      ..lineTo(w * 0.82, h * 0.05)
      ..lineTo(w * 0.90, h * 0.90)
      ..close();
    canvas.drawPath(rightOuter, outerPaint);
    final rightInner = Path()
      ..moveTo(w * 0.65, h * 0.68)
      ..lineTo(w * 0.80, h * 0.20)
      ..lineTo(w * 0.86, h * 0.78)
      ..close();
    canvas.drawPath(rightInner, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UnicornHornPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final hornPath = Path()
      ..moveTo(w * 0.50, 0)
      ..lineTo(w * 0.30, h * 0.90)
      ..lineTo(w * 0.70, h * 0.90)
      ..close();

    final hornPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE0C3FC), Color(0xFFFFB6C1), Color(0xFFFFD700)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(hornPath, hornPaint);

    final ridgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05;

    for (int i = 1; i < 5; i++) {
      final y = h * (0.15 + i * 0.16);
      final halfWidth = w * 0.15 * (1 - i * 0.12);
      canvas.drawLine(
        Offset(w * 0.50 - halfWidth, y),
        Offset(w * 0.50 + halfWidth, y + h * 0.04),
        ridgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarHeadbandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bandPaint = Paint()
      ..color = AppColors.starGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.25
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromLTWH(w * 0.02, -h * 0.2, w * 0.96, h * 1.4),
      pi * 0.05,
      pi * 0.90,
      false,
      bandPaint,
    );

    final starPaint = Paint()..color = AppColors.starGold;
    final positions = [
      Offset(w * 0.15, h * 0.45),
      Offset(w * 0.35, h * 0.20),
      Offset(w * 0.50, h * 0.12),
      Offset(w * 0.65, h * 0.20),
      Offset(w * 0.85, h * 0.45),
    ];

    for (int i = 0; i < positions.length; i++) {
      final starSize = (i == 2) ? w * 0.07 : w * 0.05;
      _drawStar(canvas, positions[i], starSize, starPaint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      if (i == 0) {
        path.moveTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      } else {
        path.lineTo(center.dx + r * cos(outerAngle),
            center.dy + r * sin(outerAngle));
      }
      path.lineTo(center.dx + r * 0.4 * cos(innerAngle),
          center.dy + r * 0.4 * sin(innerAngle));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── New Accessory Painters ──────────────────────────────────────────

class _HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.22;

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.50), width: w * 0.85, height: h * 0.70),
      paint,
    );

    // Inner glow
    final glow = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.40;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.50), width: w * 0.85, height: h * 0.70),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeadbandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = const Color(0xFFFF7EB3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.50
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromLTWH(0, -h * 0.5, w, h * 2.0),
      pi * 0.08,
      pi * 0.84,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlowerCrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Vine / band
    final bandPaint = Paint()
      ..color = const Color(0xFF4CBB8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromLTWH(w * 0.02, h * 0.20, w * 0.96, h * 1.0),
      pi * 0.08,
      pi * 0.84,
      false,
      bandPaint,
    );

    // Flowers along the crown
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
      final paint = Paint()..color = flowerColors[i];
      for (int j = 0; j < 5; j++) {
        final angle = j * 2 * pi / 5 - pi / 2;
        canvas.drawCircle(
          Offset(fc.dx + r * 0.6 * cos(angle), fc.dy + r * 0.6 * sin(angle)),
          r * 0.45,
          paint,
        );
      }
      canvas.drawCircle(fc, r * 0.28, Paint()..color = AppColors.starGold);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DevilHornsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = const Color(0xFFFF4444);

    // Left horn
    final left = Path()
      ..moveTo(w * 0.18, h * 0.95)
      ..quadraticBezierTo(w * 0.05, h * 0.50, w * 0.15, h * 0.05)
      ..quadraticBezierTo(w * 0.22, h * 0.02, w * 0.30, h * 0.10)
      ..quadraticBezierTo(w * 0.28, h * 0.55, w * 0.32, h * 0.95)
      ..close();
    canvas.drawPath(left, paint);

    // Right horn
    final right = Path()
      ..moveTo(w * 0.68, h * 0.95)
      ..quadraticBezierTo(w * 0.72, h * 0.55, w * 0.70, h * 0.10)
      ..quadraticBezierTo(w * 0.78, h * 0.02, w * 0.85, h * 0.05)
      ..quadraticBezierTo(w * 0.95, h * 0.50, w * 0.82, h * 0.95)
      ..close();
    canvas.drawPath(right, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PirateHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Main hat body
    final hat = Path()
      ..moveTo(w * 0.05, h * 0.75)
      ..quadraticBezierTo(w * 0.10, h * 0.40, w * 0.25, h * 0.20)
      ..quadraticBezierTo(w * 0.50, h * 0.05, w * 0.75, h * 0.20)
      ..quadraticBezierTo(w * 0.90, h * 0.40, w * 0.95, h * 0.75)
      ..close();
    canvas.drawPath(hat, Paint()..color = const Color(0xFF2A2A2A));

    // Brim
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.78), width: w * 0.98, height: h * 0.30),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Skull symbol
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.45),
      w * 0.08,
      Paint()..color = Colors.white,
    );
    // Cross bones
    final bonePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.38, h * 0.55), Offset(w * 0.62, h * 0.65), bonePaint);
    canvas.drawLine(
        Offset(w * 0.62, h * 0.55), Offset(w * 0.38, h * 0.65), bonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AntennaePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stalkPaint = Paint()
      ..color = const Color(0xFF00E68A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;

    // Left stalk
    final leftPath = Path()
      ..moveTo(w * 0.25, h)
      ..quadraticBezierTo(w * 0.10, h * 0.50, w * 0.15, h * 0.10);
    canvas.drawPath(leftPath, stalkPaint);
    // Left ball
    canvas.drawCircle(
        Offset(w * 0.15, h * 0.10), w * 0.10, Paint()..color = const Color(0xFF00E68A));

    // Right stalk
    final rightPath = Path()
      ..moveTo(w * 0.75, h)
      ..quadraticBezierTo(w * 0.90, h * 0.50, w * 0.85, h * 0.10);
    canvas.drawPath(rightPath, stalkPaint);
    // Right ball
    canvas.drawCircle(
        Offset(w * 0.85, h * 0.10), w * 0.10, Paint()..color = const Color(0xFF00E68A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PropellerHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Beanie base
    final beanie = Path()
      ..moveTo(w * 0.05, h * 0.90)
      ..quadraticBezierTo(w * 0.05, h * 0.35, w * 0.50, h * 0.30)
      ..quadraticBezierTo(w * 0.95, h * 0.35, w * 0.95, h * 0.90)
      ..close();
    canvas.drawPath(beanie, Paint()..color = const Color(0xFF4A90D9));

    // Brim band
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.02, h * 0.80, w * 0.96, h * 0.15),
        Radius.circular(h * 0.08),
      ),
      Paint()..color = const Color(0xFFFF4444),
    );

    // Propeller post
    canvas.drawCircle(
        Offset(w * 0.50, h * 0.30), w * 0.05, Paint()..color = const Color(0xFFFFD700));

    // Propeller blades
    final bladePaint = Paint()..color = const Color(0xFFFF4444);
    final center = Offset(w * 0.50, h * 0.28);
    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 - pi / 6;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          center.dx + w * 0.15 * cos(angle + 0.3),
          center.dy + h * 0.12 * sin(angle + 0.3),
          center.dx + w * 0.22 * cos(angle),
          center.dy + h * 0.18 * sin(angle),
        )
        ..quadraticBezierTo(
          center.dx + w * 0.15 * cos(angle - 0.3),
          center.dy + h * 0.12 * sin(angle - 0.3),
          center.dx,
          center.dy,
        )
        ..close();
      canvas.drawPath(path, bladePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NinjaMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Dark mask band across eyes
    final maskPaint = Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.10, w, h * 0.70),
        Radius.circular(h * 0.20),
      ),
      maskPaint,
    );

    // Eye slits
    final slitPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.30, h * 0.45), width: w * 0.22, height: h * 0.25),
        Radius.circular(h * 0.08),
      ),
      slitPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.70, h * 0.45), width: w * 0.22, height: h * 0.25),
        Radius.circular(h * 0.08),
      ),
      slitPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
//  SPARKLE EFFECT PAINTER
// ══════════════════════════════════════════════════════════════════════

class _SparklePainter extends CustomPainter {
  final bool rainbow;

  _SparklePainter({required this.rainbow});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    const sparkleCount = 6;
    final colors = rainbow
        ? [
            Colors.red,
            Colors.orange,
            Colors.yellow,
            Colors.green,
            Colors.blue,
            Colors.purple,
          ]
        : [
            AppColors.starGold,
            Colors.white,
            AppColors.starGold,
            Colors.white,
            AppColors.starGold,
            Colors.white,
          ];

    for (int i = 0; i < sparkleCount; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = size.width * 0.02 + rng.nextDouble() * size.width * 0.025;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 0.8);

      // 4-pointed sparkle
      final path = Path();
      path.moveTo(x, y - r);
      path.lineTo(x + r * 0.3, y);
      path.lineTo(x, y + r);
      path.lineTo(x - r * 0.3, y);
      path.close();
      path.moveTo(x - r, y);
      path.lineTo(x, y + r * 0.3);
      path.lineTo(x + r, y);
      path.lineTo(x, y - r * 0.3);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.rainbow != rainbow;
}

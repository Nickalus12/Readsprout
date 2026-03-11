import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../avatar/data/avatar_options.dart';
import '../models/player_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// Activity-based treasure chest widget.
///
/// Chests are earned at 10, 25, and 50 words per day (max 3 per day).
/// Chest tier (wooden/silver/golden) based on streak affects reward rarity.
/// Rewards are VISUAL (icons, colors, effects) — never text labels.
///
/// States:
/// - [_ChestState.earning]  — progress arc filling toward next chest
/// - [_ChestState.ready]    — chest glowing, tap to open
/// - [_ChestState.opening]  — dramatic open animation
/// - [_ChestState.revealed] — reward icon displayed with celebration
/// - [_ChestState.complete] — all 3 daily chests claimed, come back tomorrow
class DailyTreasure extends StatefulWidget {
  final ProfileService profileService;
  final int wordsPlayedToday;
  final int currentStreak;

  /// Called when the chest is opened with the reward item ID.
  final ValueChanged<String>? onRewardEarned;

  const DailyTreasure({
    super.key,
    required this.profileService,
    required this.wordsPlayedToday,
    required this.currentStreak,
    this.onRewardEarned,
  });

  @override
  State<DailyTreasure> createState() => _DailyTreasureState();
}

enum _ChestState { earning, ready, opening, revealed, complete }

enum _ChestTier { wooden, silver, golden }

// ═══════════════════════════════════════════════════════════════════════════
// _TreasureChestPainter — Full 3D treasure chest with wood grain, metal trim,
// clasp, and tier-specific appearance.
// ═══════════════════════════════════════════════════════════════════════════

class _TreasureChestPainter extends CustomPainter {
  final Color tierColor;
  final _ChestTier tier;
  final double openAmount;
  final double glowIntensity;
  final double wobbleAngle;
  final double fillLevel;

  _TreasureChestPainter({
    required this.tierColor,
    required this.tier,
    this.openAmount = 0.0,
    this.glowIntensity = 0.0,
    this.wobbleAngle = 0.0,
    this.fillLevel = 0.0,
  });

  _ChestColors get _colors => switch (tier) {
        _ChestTier.wooden => const _ChestColors(
            woodLight: Color(0xFFC49A3C),
            woodDark: Color(0xFF7A5518),
            woodMid: Color(0xFF9E7A28),
            lidLight: Color(0xFFD4AA4C),
            lidDark: Color(0xFF8A6520),
            metalPrimary: Color(0xFFCD7F32),
            metalSecondary: Color(0xFF8B5A1B),
            metalHighlight: Color(0xFFE8B060),
            claspColor: Color(0xFFA0682A),
            glowColor: Color(0xFFCD7F32),
          ),
        _ChestTier.silver => const _ChestColors(
            woodLight: Color(0xFF8899AA),
            woodDark: Color(0xFF556677),
            woodMid: Color(0xFF6E7F90),
            lidLight: Color(0xFF99AACC),
            lidDark: Color(0xFF607088),
            metalPrimary: Color(0xFFD0D8E8),
            metalSecondary: Color(0xFF8898B8),
            metalHighlight: Color(0xFFEEF2FF),
            claspColor: Color(0xFFA0B0D0),
            glowColor: Color(0xFF88BBFF),
          ),
        _ChestTier.golden => const _ChestColors(
            woodLight: Color(0xFF8B3A3A),
            woodDark: Color(0xFF5C1E1E),
            woodMid: Color(0xFF6E2C2C),
            lidLight: Color(0xFF9B4040),
            lidDark: Color(0xFF6A2828),
            metalPrimary: Color(0xFFFFD700),
            metalSecondary: Color(0xFFC8A800),
            metalHighlight: Color(0xFFFFF4AA),
            claspColor: Color(0xFFFFE44D),
            glowColor: Color(0xFFFFD700),
          ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = _colors;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final bodyW = size.width * 0.78;
    final bodyH = size.height * 0.42;
    final lidH = size.height * 0.26;
    final bodyLeft = cx - bodyW / 2;
    final bodyRight = cx + bodyW / 2;
    final bodyTop = cy + size.height * 0.02;
    final bodyBottom = bodyTop + bodyH;
    final lidBottom = bodyTop;
    final lidTop = lidBottom - lidH;

    canvas.save();

    if (wobbleAngle != 0) {
      canvas.translate(cx, bodyBottom);
      canvas.rotate(wobbleAngle);
      canvas.translate(-cx, -bodyBottom);
    }

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, bodyBottom + 4),
        width: bodyW * 0.85,
        height: 10,
      ),
      shadowPaint,
    );

    // Glow effect
    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = c.glowColor.withValues(alpha: glowIntensity * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: bodyW * 1.4,
          height: (bodyH + lidH) * 1.4,
        ),
        glowPaint,
      );
    }

    // Light leaking from lid seam
    if (glowIntensity > 0 || openAmount > 0) {
      final leakIntensity =
          openAmount > 0 ? min(1.0, openAmount * 3) : glowIntensity;
      final seamGlowPaint = Paint()
        ..color = c.glowColor.withValues(alpha: leakIntensity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..strokeWidth = 3 + leakIntensity * 3;
      canvas.drawLine(
        Offset(bodyLeft + 8, lidBottom),
        Offset(bodyRight - 8, lidBottom),
        seamGlowPaint,
      );
    }

    // ══════════════════ BODY ══════════════════

    final bodyPath = Path();
    const bodyR = 6.0;
    bodyPath.moveTo(bodyLeft, bodyTop);
    bodyPath.lineTo(bodyLeft, bodyBottom - bodyR);
    bodyPath.quadraticBezierTo(
        bodyLeft, bodyBottom, bodyLeft + bodyR, bodyBottom);
    bodyPath.lineTo(bodyRight - bodyR, bodyBottom);
    bodyPath.quadraticBezierTo(
        bodyRight, bodyBottom, bodyRight, bodyBottom - bodyR);
    bodyPath.lineTo(bodyRight, bodyTop);
    bodyPath.close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.woodLight, c.woodMid, c.woodDark],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(
          Rect.fromLTRB(bodyLeft, bodyTop, bodyRight, bodyBottom));
    canvas.drawPath(bodyPath, bodyPaint);

    // Wood grain planks
    final grainPaint = Paint()
      ..color = c.woodDark.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var i = 1; i <= 3; i++) {
      final y = bodyTop + bodyH * i / 4;
      final grain = Path()
        ..moveTo(bodyLeft + 3, y)
        ..cubicTo(
          bodyLeft + bodyW * 0.25, y - 2.5 + (i % 2) * 5,
          bodyLeft + bodyW * 0.75, y + 2.5 - (i % 2) * 5,
          bodyRight - 3, y,
        );
      canvas.drawPath(grain, grainPaint);
    }

    // Subtle wood grain texture
    final texturePaint = Paint()
      ..color = c.woodDark.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) {
      final y = bodyTop + 4 + (bodyH - 8) * i / 5;
      final grain = Path()
        ..moveTo(bodyLeft + 6, y + 1.5)
        ..cubicTo(
          bodyLeft + bodyW * 0.3, y - 1 + (i % 3) * 1.5,
          bodyLeft + bodyW * 0.7, y + 1 - (i % 3) * 1.5,
          bodyRight - 6, y - 0.5,
        );
      canvas.drawPath(grain, texturePaint);
    }

    // Magic fill level inside chest (earning state)
    if (fillLevel > 0 && openAmount == 0) {
      final fillH = bodyH * fillLevel;
      final fillTop = bodyBottom - fillH;
      canvas.save();
      canvas.clipPath(bodyPath);
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            c.glowColor.withValues(alpha: 0.5),
            c.glowColor.withValues(alpha: 0.15),
          ],
        ).createShader(
            Rect.fromLTRB(bodyLeft, fillTop, bodyRight, bodyBottom));
      canvas.drawRect(
        Rect.fromLTRB(bodyLeft, fillTop, bodyRight, bodyBottom),
        fillPaint,
      );
      final shimPaint = Paint()
        ..color = c.glowColor.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(bodyLeft + 6, fillTop),
        Offset(bodyRight - 6, fillTop),
        shimPaint,
      );
      canvas.restore();
    }

    // Body outline
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = c.woodDark.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Specular highlight on body
    final specBodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTRB(
          bodyLeft, bodyTop, bodyLeft + bodyW * 0.3, bodyBottom));
    canvas.save();
    canvas.clipPath(bodyPath);
    canvas.drawRect(
      Rect.fromLTRB(
          bodyLeft, bodyTop, bodyLeft + bodyW * 0.3, bodyBottom),
      specBodyPaint,
    );
    canvas.restore();

    // ══════════════════ METAL TRIM BAND ══════════════════

    final bandTop = bodyTop + bodyH * 0.35;
    final bandBottom = bandTop + bodyH * 0.3;
    final bandRect =
        Rect.fromLTRB(bodyLeft - 2, bandTop, bodyRight + 2, bandBottom);

    final bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          c.metalHighlight,
          c.metalPrimary,
          c.metalSecondary,
          c.metalPrimary,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(bandRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bandRect, const Radius.circular(2)),
      bandPaint,
    );

    // Band edge lines
    final bandEdge = Paint()
      ..color = c.metalSecondary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(bodyLeft - 1, bandTop),
        Offset(bodyRight + 1, bandTop), bandEdge);
    canvas.drawLine(Offset(bodyLeft - 1, bandBottom),
        Offset(bodyRight + 1, bandBottom), bandEdge);

    // Band specular highlight
    final bandSpecPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTRB(bodyLeft, bandTop, bodyRight,
          bandTop + (bandBottom - bandTop) * 0.4));
    canvas.drawRect(
      Rect.fromLTRB(bodyLeft, bandTop, bodyRight,
          bandTop + (bandBottom - bandTop) * 0.4),
      bandSpecPaint,
    );

    // Rivets
    final rivetPaint = Paint()..color = c.metalHighlight;
    final rivetShadow = Paint()
      ..color = c.metalSecondary.withValues(alpha: 0.6);
    final rivetY = (bandTop + bandBottom) / 2;
    for (final rx in [bodyLeft + 10.0, bodyRight - 10.0]) {
      canvas.drawCircle(Offset(rx, rivetY + 0.5), 2.5, rivetShadow);
      canvas.drawCircle(Offset(rx, rivetY), 2.5, rivetPaint);
      canvas.drawCircle(
        Offset(rx - 0.5, rivetY - 0.5),
        1.0,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }

    // ══════════════════ CLASP / LOCK ══════════════════

    final claspCx = cx;
    final claspCy = rivetY;
    const claspW = 14.0;
    const claspH = 18.0;

    final claspRect = RRect.fromRectAndCorners(
      Rect.fromCenter(
          center: Offset(claspCx, claspCy),
          width: claspW,
          height: claspH),
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
      bottomLeft: const Radius.circular(5),
      bottomRight: const Radius.circular(5),
    );
    final claspPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.metalHighlight, c.claspColor, c.metalSecondary],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(claspRect.outerRect);
    canvas.drawRRect(claspRect, claspPaint);

    canvas.drawRRect(
      claspRect,
      Paint()
        ..color = c.metalSecondary.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Keyhole
    final keyholePaint = Paint()
      ..color = c.woodDark.withValues(alpha: 0.8);
    canvas.drawCircle(
        Offset(claspCx, claspCy - 1.5), 2.5, keyholePaint);
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(claspCx, claspCy + 2.5),
          width: 2,
          height: 5),
      keyholePaint,
    );
    canvas.drawCircle(
      Offset(claspCx - 0.5, claspCy - 2),
      0.8,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // ══════════════════ GEMS (Golden tier only) ══════════════════

    if (tier == _ChestTier.golden) {
      _drawGem(canvas, Offset(bodyLeft + 22, rivetY), 5.0,
          const Color(0xFFFF1744), const Color(0xFFFF8A80));
      _drawGem(canvas, Offset(bodyRight - 22, rivetY), 5.0,
          const Color(0xFF00C853), const Color(0xFF69F0AE));
      _drawGem(canvas, Offset(cx - 26, rivetY), 4.0,
          const Color(0xFF2979FF), const Color(0xFF82B1FF));
      _drawGem(canvas, Offset(cx + 26, rivetY), 4.0,
          const Color(0xFF2979FF), const Color(0xFF82B1FF));
    }

    // ══════════════════ SILVER CRYSTALLINE HIGHLIGHTS ══════════════════

    if (tier == _ChestTier.silver) {
      final crystalPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2);
      for (final offset in [
        Offset(bodyLeft + 18, bodyTop + bodyH * 0.2),
        Offset(bodyRight - 18, bodyTop + bodyH * 0.2),
        Offset(bodyLeft + 18, bodyTop + bodyH * 0.75),
        Offset(bodyRight - 18, bodyTop + bodyH * 0.75),
      ]) {
        final dp = Path()
          ..moveTo(offset.dx, offset.dy - 3)
          ..lineTo(offset.dx + 2, offset.dy)
          ..lineTo(offset.dx, offset.dy + 3)
          ..lineTo(offset.dx - 2, offset.dy)
          ..close();
        canvas.drawPath(dp, crystalPaint);
      }
    }

    // ══════════════════ LID ══════════════════

    if (openAmount > 0) {
      canvas.save();
      canvas.translate(cx, lidBottom);
      final lidAngle = -openAmount * pi * 0.55;
      canvas.rotate(lidAngle);
      canvas.translate(-cx, -lidBottom);

      // Light burst from inside
      if (openAmount > 0.2) {
        final burstIntensity =
            ((openAmount - 0.2) / 0.8).clamp(0.0, 1.0);
        final burstPaint = Paint()
          ..shader = RadialGradient(
            center: Alignment.topCenter,
            radius: 0.8,
            colors: [
              c.glowColor
                  .withValues(alpha: burstIntensity * 0.8),
              c.glowColor
                  .withValues(alpha: burstIntensity * 0.2),
              c.glowColor.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(Rect.fromLTRB(bodyLeft,
              lidBottom - bodyH * 0.8, bodyRight, lidBottom));
        canvas.drawRect(
          Rect.fromLTRB(bodyLeft - 10, lidBottom - bodyH * 0.8,
              bodyRight + 10, lidBottom),
          burstPaint,
        );
      }

      _drawLid(
          canvas, bodyLeft, bodyRight, lidTop, lidBottom, lidH, c);
      canvas.restore();
    } else {
      _drawLid(
          canvas, bodyLeft, bodyRight, lidTop, lidBottom, lidH, c);
    }

    // Ambient occlusion under lid seam
    if (openAmount == 0) {
      final aoP = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(bodyLeft + 2, lidBottom + 1),
        Offset(bodyRight - 2, lidBottom + 1),
        aoP,
      );
    }

    canvas.restore();
  }

  void _drawLid(Canvas canvas, double bodyLeft, double bodyRight,
      double lidTop, double lidBottom, double lidH, _ChestColors c) {
    final lidLeft = bodyLeft - 2;
    final lidRight = bodyRight + 2;
    final lidW = lidRight - lidLeft;

    final lidPath = Path();
    const lidR = 8.0;
    lidPath.moveTo(lidLeft, lidBottom);
    lidPath.lineTo(lidLeft, lidTop + lidR);
    lidPath.quadraticBezierTo(lidLeft, lidTop, lidLeft + lidR, lidTop);
    lidPath.quadraticBezierTo(
      (lidLeft + lidRight) / 2,
      lidTop - lidH * 0.15,
      lidRight - lidR,
      lidTop,
    );
    lidPath.quadraticBezierTo(
        lidRight, lidTop, lidRight, lidTop + lidR);
    lidPath.lineTo(lidRight, lidBottom);
    lidPath.close();

    final lidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.lidLight, c.lidDark],
      ).createShader(
          Rect.fromLTRB(lidLeft, lidTop, lidRight, lidBottom));
    canvas.drawPath(lidPath, lidPaint);

    // Lid wood grain
    final lidGrainPaint = Paint()
      ..color = c.lidDark.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final midY = (lidTop + lidBottom) / 2;
    final grain = Path()
      ..moveTo(lidLeft + 4, midY)
      ..cubicTo(
        lidLeft + lidW * 0.3, midY - 2,
        lidLeft + lidW * 0.7, midY + 2,
        lidRight - 4, midY,
      );
    canvas.drawPath(grain, lidGrainPaint);

    // Lid specular highlight
    final lidSpecPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTRB(lidLeft, lidTop, lidRight,
          lidTop + (lidBottom - lidTop) * 0.4));
    canvas.save();
    canvas.clipPath(lidPath);
    canvas.drawRect(
      Rect.fromLTRB(lidLeft, lidTop, lidRight,
          lidTop + (lidBottom - lidTop) * 0.4),
      lidSpecPaint,
    );
    canvas.restore();

    // Lid outline
    canvas.drawPath(
      lidPath,
      Paint()
        ..color = c.lidDark.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Metal trim on lid bottom edge
    final lidBandRect = Rect.fromLTRB(
        lidLeft + 1, lidBottom - 5, lidRight - 1, lidBottom);
    final lidBandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          c.metalHighlight,
          c.metalPrimary,
          c.metalSecondary
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(lidBandRect);
    canvas.drawRect(lidBandRect, lidBandPaint);

    // Golden tier sunburst glow on lid
    if (tier == _ChestTier.golden && glowIntensity > 0) {
      final sunburstPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD700)
                .withValues(alpha: glowIntensity * 0.15),
            const Color(0xFFFFD700).withValues(alpha: 0),
          ],
        ).createShader(
            Rect.fromLTRB(lidLeft, lidTop, lidRight, lidBottom));
      canvas.save();
      canvas.clipPath(lidPath);
      canvas.drawRect(
        Rect.fromLTRB(lidLeft, lidTop, lidRight, lidBottom),
        sunburstPaint,
      );
      canvas.restore();
    }
  }

  void _drawGem(Canvas canvas, Offset center, double r, Color dark,
      Color light) {
    final gemPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.9,
        colors: [light, dark],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r * 0.8, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r * 0.8, center.dy)
      ..close();
    canvas.drawPath(path, gemPaint);
    canvas.drawCircle(
      Offset(center.dx - r * 0.2, center.dy - r * 0.2),
      r * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_TreasureChestPainter oldDelegate) =>
      oldDelegate.tierColor != tierColor ||
      oldDelegate.tier != tier ||
      oldDelegate.openAmount != openAmount ||
      oldDelegate.glowIntensity != glowIntensity ||
      oldDelegate.wobbleAngle != wobbleAngle ||
      oldDelegate.fillLevel != fillLevel;
}

// ═══════════════════════════════════════════════════════════════════════════
// _ChestProgressArcPainter — Circular arc around the chest showing progress
// ═══════════════════════════════════════════════════════════════════════════

class _ChestProgressArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double glowPulse;

  _ChestProgressArcPainter({
    required this.progress,
    required this.color,
    this.glowPulse = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(cx, cy) - 6;
    final center = Offset(cx, cy);
    const strokeWidth = 5.0;
    const startAngle = -pi / 2; // Start from top

    // Background track
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // Glow behind the arc
    final glowAlpha = (0.2 + glowPulse * 0.15).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * pi * progress,
      false,
      glowPaint,
    );

    // Filled arc
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * pi * progress,
      false,
      arcPaint,
    );

    // Bright dot at the leading edge
    if (progress > 0.02 && progress < 1.0) {
      final endAngle = startAngle + 2 * pi * progress;
      final dotX = cx + cos(endAngle) * radius;
      final dotY = cy + sin(endAngle) * radius;
      canvas.drawCircle(
        Offset(dotX, dotY),
        4,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ChestProgressArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.glowPulse != glowPulse;
}

// ═══════════════════════════════════════════════════════════════════════════
// Tier color helper
// ═══════════════════════════════════════════════════════════════════════════

class _ChestColors {
  final Color woodLight;
  final Color woodDark;
  final Color woodMid;
  final Color lidLight;
  final Color lidDark;
  final Color metalPrimary;
  final Color metalSecondary;
  final Color metalHighlight;
  final Color claspColor;
  final Color glowColor;

  const _ChestColors({
    required this.woodLight,
    required this.woodDark,
    required this.woodMid,
    required this.lidLight,
    required this.lidDark,
    required this.metalPrimary,
    required this.metalSecondary,
    required this.metalHighlight,
    required this.claspColor,
    required this.glowColor,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Particle painters
// ═══════════════════════════════════════════════════════════════════════════

class _MagicParticlesPainter extends CustomPainter {
  final Color color;
  final double progress;
  final double intensity;

  _MagicParticlesPainter({
    required this.color,
    required this.progress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rng = Random(42);

    for (var i = 0; i < 12; i++) {
      final baseAngle = i * (pi * 2 / 12) + progress * pi * 2;
      final radiusX = 40.0 + rng.nextDouble() * 15;
      final radiusY = 30.0 + rng.nextDouble() * 12;
      final phaseOffset = rng.nextDouble() * pi * 2;
      final angle = baseAngle + phaseOffset;

      final x = cx + cos(angle) * radiusX;
      final y = cy + sin(angle) * radiusY;
      final alpha =
          (intensity * 0.6 * (0.4 + 0.6 * sin(progress * pi * 4 + i)))
              .clamp(0.0, 1.0);
      final r = 1.5 + intensity * 1.5;

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_MagicParticlesPainter oldDelegate) => true;
}

class _SparkleOrbitPainter extends CustomPainter {
  final Color color;
  final double progress;

  _SparkleOrbitPainter({
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (var i = 0; i < 6; i++) {
      final angle = progress * pi * 2 + i * (pi / 3);
      final rx = 55.0 + sin(progress * pi * 4 + i) * 8;
      final ry = 42.0 + cos(progress * pi * 3 + i) * 6;
      final x = cx + cos(angle) * rx;
      final y = cy + sin(angle) * ry;

      final alpha =
          (0.5 + 0.5 * sin(progress * pi * 6 + i * 1.5))
              .clamp(0.0, 1.0);
      final sparkColor = i.isEven ? color : AppColors.starGold;
      final paint = Paint()
        ..color = sparkColor.withValues(alpha: alpha)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      const r = 4.0;
      canvas.drawLine(
          Offset(x - r, y), Offset(x + r, y), paint);
      canvas.drawLine(
          Offset(x, y - r), Offset(x, y + r), paint);

      canvas.drawCircle(
        Offset(x, y),
        1.5,
        Paint()
          ..color = sparkColor.withValues(alpha: alpha * 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkleOrbitPainter oldDelegate) => true;
}

class _MagicTrailPainter extends CustomPainter {
  final Color color;
  final double progress;

  _MagicTrailPainter({
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    for (var i = 0; i < 8; i++) {
      final t = (progress + i / 8) % 1.0;
      final y = size.height * (1.0 - t);
      final x = cx + sin(t * pi * 3 + i) * 6;
      final alpha = (sin(t * pi) * 0.6).clamp(0.0, 1.0);
      final r = 1.5 + sin(t * pi) * 1.0;

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_MagicTrailPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// State widget
// ═══════════════════════════════════════════════════════════════════════════

class _DailyTreasureState extends State<DailyTreasure>
    with TickerProviderStateMixin {
  late _ChestState _state;
  TreasureReward? _reward;
  late AnimationController _wobbleController;
  late AnimationController _glowController;
  late AnimationController _revealController;
  late AnimationController _openController;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();

    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _updateState();
  }

  @override
  void didUpdateWidget(DailyTreasure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wordsPlayedToday != widget.wordsPlayedToday) {
      if (_state != _ChestState.opening &&
          _state != _ChestState.revealed) {
        _updateState();
      }
    }
  }

  void _updateState() {
    if (widget.profileService.allDailyChestsComplete) {
      _state = _ChestState.complete;
    } else if (widget.profileService.hasChestReady) {
      _state = _ChestState.ready;
    } else {
      _state = _ChestState.earning;
    }
  }

  _ChestTier get _tier {
    if (widget.currentStreak >= 7) return _ChestTier.golden;
    if (widget.currentStreak >= 3) return _ChestTier.silver;
    return _ChestTier.wooden;
  }

  Color get _tierColor => switch (_tier) {
        _ChestTier.wooden => AppColors.chestWood,
        _ChestTier.silver => AppColors.chestSilver,
        _ChestTier.golden => AppColors.chestGold,
      };

  Set<RewardRarity> get _allowedRarities => switch (_tier) {
        _ChestTier.wooden => {RewardRarity.common},
        _ChestTier.silver => {
            RewardRarity.common,
            RewardRarity.uncommon
          },
        _ChestTier.golden => {
            RewardRarity.common,
            RewardRarity.uncommon,
            RewardRarity.rare,
          },
      };

  TreasureReward _pickReward() {
    final rng = Random();
    final owned = widget.profileService.unlockedItems;
    final rarities = _allowedRarities;

    final available = allTreasureRewards
        .where((r) =>
            !owned.contains(r.id) && rarities.contains(r.rarity))
        .toList();

    if (available.isNotEmpty) {
      return available[rng.nextInt(available.length)];
    }

    final stickers = allTreasureRewards
        .where((r) =>
            r.category == TreasureCategory.sticker &&
            rarities.contains(r.rarity))
        .toList();
    if (stickers.isNotEmpty) {
      return stickers[rng.nextInt(stickers.length)];
    }

    final allStickers = allTreasureRewards
        .where((r) => r.category == TreasureCategory.sticker)
        .toList();
    return allStickers[rng.nextInt(allStickers.length)];
  }

  Future<void> _applyReward(TreasureReward reward) async {
    await widget.profileService.unlockItem(reward.id);

    if (reward.category == TreasureCategory.effect &&
        reward.effectFlag != null) {
      final avatar = widget.profileService.avatar;
      AvatarConfig updated;
      switch (reward.effectFlag) {
        case 'hasSparkle':
          updated = avatar.copyWith(hasSparkle: true);
        case 'hasRainbowSparkle':
          updated = avatar.copyWith(hasRainbowSparkle: true);
        case 'hasGoldenGlow':
          updated = avatar.copyWith(hasGoldenGlow: true);
        default:
          return;
      }
      await widget.profileService.setAvatar(updated);
    }

    if (reward.category == TreasureCategory.facePaint &&
        reward.facePaintIndex != null) {
      final avatar = widget.profileService.avatar;
      final updated =
          avatar.copyWith(facePaint: reward.facePaintIndex);
      await widget.profileService.setAvatar(updated);
    }

    if (reward.category == TreasureCategory.glasses &&
        reward.glassesIndex != null) {
      final avatar = widget.profileService.avatar;
      final updated =
          avatar.copyWith(glassesStyle: reward.glassesIndex);
      await widget.profileService.setAvatar(updated);
    }

    if (reward.category == TreasureCategory.sticker) {
      await widget.profileService.awardSticker(
        StickerRecord(
          stickerId: reward.id,
          dateEarned: DateTime.now(),
          category: 'treasure',
        ),
      );
    }

    await widget.profileService.setLastChestRewardId(reward.id);
    await widget.profileService.setLastChestReward(reward.id);
  }

  void _onTap() async {
    switch (_state) {
      case _ChestState.earning:
      case _ChestState.complete:
        _wobbleController.forward(from: 0);

      case _ChestState.ready:
        setState(() => _state = _ChestState.opening);
        _openController.forward(from: 0);

        final reward = _pickReward();

        await Future.delayed(const Duration(milliseconds: 1800));

        if (!mounted) return;
        setState(() {
          _state = _ChestState.revealed;
          _reward = reward;
        });

        _revealController.forward(from: 0);

        await widget.profileService.markChestOpened();
        await _applyReward(reward);
        widget.onRewardEarned?.call(reward.id);

      case _ChestState.opening:
        break;

      case _ChestState.revealed:
        setState(() {
          _reward = null;
          _updateState();
        });
    }
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    _glowController.dispose();
    _revealController.dispose();
    _openController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  double get _progress => widget.profileService.chestProgress;
  int get _chestsAvailable => widget.profileService.chestsAvailable;
  int get _chestsEarnedToday =>
      widget.profileService.currentChestIndex;
  int get _chestsClaimedToday =>
      _chestsEarnedToday - _chestsAvailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Simple title header — no confusing mini-chest tracker
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                size: 20,
                color: _tierColor.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                'Daily Treasure',
                style: AppFonts.fredoka(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _onTap,
          child: Container(
            width: double.infinity,
            height: 190,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _tierColor.withValues(alpha: 0.3),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildCurrentState(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentState() {
    return switch (_state) {
      _ChestState.earning => _buildEarning(),
      _ChestState.ready => _buildReady(),
      _ChestState.opening => _buildOpening(),
      _ChestState.revealed => _buildRevealed(),
      _ChestState.complete => _buildComplete(),
    };
  }

  // ── Earning State ─────────────────────────────────────────────────

  Widget _buildEarning() {
    final wordsNeeded = widget.profileService.wordsUntilNextChest;
    final chestNumber = _chestsEarnedToday + 1;

    return AnimatedBuilder(
      animation:
          Listenable.merge([_wobbleController, _particleController, _glowController]),
      builder: (context, child) {
        final wobble = sin(_wobbleController.value * pi * 4) *
            (1 - _wobbleController.value) *
            0.05;
        final breathe =
            sin(_particleController.value * pi * 2) * 0.02;

        return Transform.rotate(
          angle: wobble,
          child: Transform.scale(
            scale: 1.0 + breathe,
            child: child,
          ),
        );
      },
      child: Column(
        key: const ValueKey('earning'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Chest with circular progress arc around it
          SizedBox(
            width: 130,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress arc around the chest
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(130, 110),
                      painter: _ChestProgressArcPainter(
                        progress: _progress,
                        color: _tierColor,
                        glowPulse: _glowController.value,
                      ),
                    );
                  },
                ),
                // Magic particles (subtle, scales with progress)
                AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(120, 100),
                      painter: _MagicParticlesPainter(
                        color: _tierColor,
                        progress: _particleController.value,
                        intensity: _progress * 0.6,
                      ),
                    );
                  },
                ),
                // The chest itself
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(80, 62),
                    painter: _TreasureChestPainter(
                      tierColor: _tierColor,
                      tier: _tier,
                      fillLevel: _progress,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Kid-friendly progress text
          Text(
            wordsNeeded > 0
                ? 'Play $wordsNeeded more word${wordsNeeded == 1 ? '' : 's'}!'
                : 'Almost there!',
            style: AppFonts.fredoka(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _tierColor,
            ),
          ),
          const SizedBox(height: 6),
          // Simple chest counter: "Chest 1 of 3" with indicator circles
          _buildChestCounter(chestNumber),
        ],
      ),
    );
  }

  /// Three small circles showing chest progress: filled = claimed,
  /// outlined with ring = current target, dim = remaining.
  Widget _buildChestCounter(int currentChestNumber) {
    final claimed = _chestsClaimedToday.clamp(0, ProfileService.maxDailyChests);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Chest $currentChestNumber of ${ProfileService.maxDailyChests}',
          style: AppFonts.fredoka(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(ProfileService.maxDailyChests, (i) {
          final isClaimed = i < claimed;
          final isCurrent = i == currentChestNumber - 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: isCurrent ? 10 : 8,
              height: isCurrent ? 10 : 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isClaimed
                    ? AppColors.success
                    : isCurrent
                        ? _tierColor.withValues(alpha: 0.3)
                        : AppColors.border.withValues(alpha: 0.2),
                border: isCurrent && !isClaimed
                    ? Border.all(color: _tierColor, width: 2)
                    : null,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: _tierColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Complete State ─────────────────────────────────────────────────

  Widget _buildComplete() {
    return AnimatedBuilder(
      animation:
          Listenable.merge([_wobbleController, _glowController]),
      builder: (context, child) {
        final wobble = sin(_wobbleController.value * pi * 4) *
            (1 - _wobbleController.value) *
            0.05;
        return Transform.rotate(angle: wobble, child: child);
      },
      child: Column(
        key: const ValueKey('complete'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Three claimed chests in a row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(ProfileService.maxDailyChests, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, _) {
                        return Opacity(
                          opacity: 0.7,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: const Size(50, 40),
                              painter: _TreasureChestPainter(
                                tierColor: _tierColor,
                                tier: _tier,
                                glowIntensity:
                                    _glowController.value * 0.1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Moon icon + "Come back tomorrow!" text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.nightlight_rounded,
                size: 18,
                color: AppColors.starGold.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                'Come back tomorrow!',
                style: AppFonts.fredoka(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'All 3 chests collected today',
            style: AppFonts.fredoka(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.secondaryText.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ready State ───────────────────────────────────────────────────

  Widget _buildReady() {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_glowController, _particleController]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _tierColor.withValues(
                    alpha:
                        0.15 + _glowController.value * 0.2),
                blurRadius:
                    24 + _glowController.value * 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        key: const ValueKey('ready'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(140, 110),
                      painter: _SparkleOrbitPainter(
                        color: _tierColor,
                        progress: _particleController.value,
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, _) {
                    final wobble =
                        sin(_glowController.value * pi * 2) *
                            0.03;
                    return Transform.rotate(
                      angle: wobble,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(100, 78),
                          painter: _TreasureChestPainter(
                            tierColor: _tierColor,
                            tier: _tier,
                            glowIntensity: 0.4 +
                                _glowController.value * 0.4,
                            wobbleAngle: wobble,
                          ),
                        ),
                      ),
                    );
                  },
                )
                    .animate(
                        onPlay: (c) =>
                            c.repeat(reverse: true))
                    .scaleXY(
                        begin: 0.95,
                        end: 1.05,
                        duration: 900.ms),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Pulsing "Tap to open!" text
          Text(
            'Tap to open!',
            style: AppFonts.fredoka(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _tierColor,
            ),
          )
              .animate(
                  onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(begin: 0.5, duration: 800.ms),
        ],
      ),
    );
  }

  // ── Opening State ─────────────────────────────────────────────────

  Widget _buildOpening() {
    return SizedBox(
      key: const ValueKey('opening'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating light beams
          ...List.generate(8, (i) {
            final angle = i * (pi / 4);
            return Transform.rotate(
              angle: angle,
              child: Container(
                width: 3,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _tierColor.withValues(alpha: 0.8),
                      _tierColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            );
          })
              .animate()
              .rotate(
                  begin: 0, end: 0.5, duration: 1800.ms)
              .fadeIn(duration: 400.ms),

          // Expanding glow circle
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _tierColor.withValues(alpha: 0.5),
                  _tierColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          )
              .animate()
              .scaleXY(
                  begin: 0.5, end: 2.0, duration: 1500.ms)
              .fadeOut(
                  delay: 1000.ms, duration: 500.ms),

          // Chest opening animation
          AnimatedBuilder(
            animation: _openController,
            builder: (context, _) {
              final openVal = Curves.easeInOut.transform(
                _openController.value.clamp(0.0, 1.0),
              );
              final shakeAmount = _openController.value < 0.4
                  ? sin(_openController.value * pi * 16) *
                      (1 - _openController.value / 0.4) *
                      0.04
                  : 0.0;
              final scale = _openController.value > 0.8
                  ? 1.0 -
                      (_openController.value - 0.8) /
                          0.2 *
                          0.3
                  : 1.0;

              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: _openController.value > 0.9
                      ? 1.0 -
                          (_openController.value - 0.9) / 0.1
                      : 1.0,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(100, 78),
                      painter: _TreasureChestPainter(
                        tierColor: _tierColor,
                        tier: _tier,
                        openAmount: openVal,
                        glowIntensity: openVal,
                        wobbleAngle: shakeAmount,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Sparkle particles
          ...List.generate(6, (i) {
            final angle = i * (pi / 3) + pi / 6;
            final dx = cos(angle) * 50;
            final dy = sin(angle) * 50;
            return Icon(
              Icons.auto_awesome,
              size: 14,
              color: AppColors.confettiColors[
                  i % AppColors.confettiColors.length],
            )
                .animate(delay: 1200.ms)
                .fadeIn(duration: 200.ms)
                .moveX(
                    begin: 0,
                    end: dx,
                    duration: 500.ms,
                    curve: Curves.easeOut)
                .moveY(
                    begin: 0,
                    end: dy,
                    duration: 500.ms,
                    curve: Curves.easeOut)
                .fadeOut(
                    delay: 300.ms, duration: 200.ms);
          }),
        ],
      ),
    );
  }

  // ── Revealed State ────────────────────────────────────────────────

  Widget _buildRevealed() {
    final reward = _reward;
    if (reward == null) {
      return const SizedBox(key: ValueKey('revealed_empty'));
    }

    return Column(
      key: const ValueKey('revealed'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 115,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Open chest at bottom
              Positioned(
                bottom: 0,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(80, 62),
                    painter: _TreasureChestPainter(
                      tierColor: _tierColor,
                      tier: _tier,
                      openAmount: 1.0,
                      glowIntensity: 0.6,
                    ),
                  ),
                ),
              ),

              // Magical trail from chest to reward
              Positioned(
                bottom: 30,
                child: AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(40, 50),
                      painter: _MagicTrailPainter(
                        color: reward.color,
                        progress:
                            _particleController.value,
                      ),
                    );
                  },
                ),
              ),

              // Glow behind reward
              Positioned(
                top: 0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        reward.color
                            .withValues(alpha: 0.4),
                        reward.color
                            .withValues(alpha: 0.1),
                        reward.color
                            .withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                )
                    .animate(
                        onPlay: (c) =>
                            c.repeat(reverse: true))
                    .scaleXY(
                        begin: 0.9,
                        end: 1.1,
                        duration: 1200.ms),
              ),

              // Reward icon floating above chest
              Positioned(
                top: 4,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: reward.color
                        .withValues(alpha: 0.15),
                    border: Border.all(
                      color: reward.color
                          .withValues(alpha: 0.6),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: reward.color
                            .withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    reward.icon,
                    size: 28,
                    color: reward.color,
                  ),
                )
                    .animate()
                    .scaleXY(
                        begin: 0.0,
                        end: 1.0,
                        duration: 500.ms,
                        curve: Curves.elasticOut)
                    .fadeIn(duration: 200.ms),
              ),

              // Orbiting sparkles
              ...List.generate(4, (i) {
                final angle = i * (pi / 2);
                return Positioned(
                  left: 70 + cos(angle) * 50 - 6,
                  top: 30 + sin(angle) * 40 - 6,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 12,
                    color: AppColors.confettiColors[i],
                  )
                      .animate(
                          delay: (200 + i * 100).ms)
                      .fadeIn(duration: 300.ms)
                      .scaleXY(
                          begin: 0,
                          end: 1,
                          duration: 400.ms),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildRewardCategoryIndicator(reward),
        const SizedBox(height: 6),
        if (_chestsAvailable > 0)
          Icon(
            Icons.touch_app_rounded,
            size: 20,
            color: _tierColor.withValues(alpha: 0.5),
          )
              .animate(
                  delay: 1500.ms,
                  onPlay: (c) =>
                      c.repeat(reverse: true))
              .moveY(
                  begin: 0, end: 3, duration: 500.ms)
        else
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color:
                AppColors.success.withValues(alpha: 0.6),
          )
              .animate(delay: 1000.ms)
              .fadeIn(duration: 400.ms)
              .scaleXY(
                  begin: 0,
                  end: 1,
                  duration: 300.ms),
      ],
    );
  }

  Widget _buildRewardCategoryIndicator(
      TreasureReward reward) {
    final IconData categoryIcon;
    final Color categoryColor;

    switch (reward.category) {
      case TreasureCategory.accessory:
        categoryIcon = Icons.face_retouching_natural;
        categoryColor = const Color(0xFFFFB6C1);
      case TreasureCategory.bgColor:
        categoryIcon = Icons.palette_rounded;
        categoryColor = const Color(0xFF6BB8F0);
      case TreasureCategory.effect:
        categoryIcon = Icons.auto_awesome;
        categoryColor = AppColors.starGold;
      case TreasureCategory.sticker:
        categoryIcon = Icons.emoji_events_rounded;
        categoryColor = const Color(0xFFFF7EB3);
      case TreasureCategory.facePaint:
        categoryIcon = Icons.brush_rounded;
        categoryColor = const Color(0xFFFF6B8A);
      case TreasureCategory.glasses:
        categoryIcon = Icons.visibility_rounded;
        categoryColor = const Color(0xFF4A90D9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Icon(
        categoryIcon,
        size: 18,
        color: categoryColor,
      ),
    )
        .animate()
        .fadeIn(delay: 400.ms, duration: 300.ms)
        .slideY(begin: 0.3, end: 0, duration: 300.ms);
  }
}

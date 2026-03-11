import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/dolch_words.dart';
import '../services/audio_service.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';

/// An interactive star-map constellation showing all levels.
/// Mastered levels are bright glowing nodes with tappable word-stars.
/// Locked levels shimmer dimly in the distance, waiting to be discovered.
class WordConstellation extends StatelessWidget {
  final ProgressService progressService;
  final AudioService audioService;

  const WordConstellation({
    super.key,
    required this.progressService,
    required this.audioService,
  });

  @override
  Widget build(BuildContext context) {
    // Count mastered words for the subtitle
    int masteredCount = 0;
    for (int l = 1; l <= DolchWords.totalLevels; l++) {
      if (progressService.getLevel(l).highestCompletedTier >= 3) {
        masteredCount += DolchWords.wordsForLevel(l).length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => audioService.playWord('words_mastered'),
                child: Text(
                  'Words Mastered',
                  style: AppFonts.fredoka(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.electricBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$masteredCount / 220',
                style: AppFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.electricBlue.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.electricBlue.withValues(alpha: 0.1),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            height: 340,
            child: _ConstellationMap(
              progressService: progressService,
              audioService: audioService,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Main constellation map ──────────────────────────────────────────────

class _ConstellationMap extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;

  const _ConstellationMap({
    required this.progressService,
    required this.audioService,
  });

  @override
  State<_ConstellationMap> createState() => _ConstellationMapState();
}

class _ConstellationMapState extends State<_ConstellationMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _twinkleController;
  int? _expandedLevel;
  String? _tappedWord;

  // Expand word ring radius
  static const double _wordOrbitRadius = 58.0;
  // Padding from map edges for node centers
  static const double _edgePad = 70.0;

  @override
  void initState() {
    super.initState();
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Make map wide enough so nodes + expanded words never clip
        final mapWidth = max(constraints.maxWidth,
            DolchWords.totalLevels * 52.0 + _edgePad * 2);
        final mapHeight = constraints.maxHeight;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: mapWidth,
            height: mapHeight,
            child: AnimatedBuilder(
              animation: _twinkleController,
              builder: (context, _) {
                final t = _twinkleController.value;
                final positions = _getNodePositions(mapWidth, mapHeight);
                return RepaintBoundary(
                  child: CustomPaint(
                    painter: _BackgroundPainter(
                      time: t,
                      nodePositions: positions,
                      progressService: widget.progressService,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: _buildAllWidgets(
                          positions, mapWidth, mapHeight, t),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Offset> _getNodePositions(double width, double height) {
    final total = DolchWords.totalLevels;
    final positions = <Offset>[];
    final rng = Random(77);

    for (int i = 0; i < total; i++) {
      final t = i / (total - 1);
      final x = _edgePad + t * (width - _edgePad * 2);
      final baseY = height * 0.5;
      final wave = sin(t * pi * 3.2 + 0.5) * (height * 0.24);
      final jitter = (rng.nextDouble() - 0.5) * 20;
      final y = (baseY + wave + jitter).clamp(_edgePad, height - _edgePad);
      positions.add(Offset(x, y));
    }
    return positions;
  }

  List<Widget> _buildAllWidgets(
      List<Offset> positions, double mapW, double mapH, double time) {
    final widgets = <Widget>[];

    // Zone labels (behind everything)
    _addZoneLabels(widgets, positions, mapH);

    for (int i = 0; i < DolchWords.totalLevels; i++) {
      final level = i + 1;
      final pos = positions[i];
      final lp = widget.progressService.getLevel(level);
      final isMastered = lp.highestCompletedTier >= 3;
      final isUnlocked = widget.progressService.isLevelUnlocked(level);
      final stars = lp.highestCompletedTier;
      final isExpanded = _expandedLevel == level;

      final gradientColors =
          AppColors.levelGradients[i % AppColors.levelGradients.length];
      final color = gradientColors[0];

      // Expanded word chips — clamped inside bounds
      if (isExpanded) {
        final words = DolchWords.wordsForLevel(level);
        for (int j = 0; j < words.length; j++) {
          final word = words[j];
          final angle = (j / words.length) * 2 * pi - (pi / 2);
          final orbitR = _wordOrbitRadius + (j.isEven ? 0 : 10);
          // Raw position
          var wx = pos.dx + cos(angle) * orbitR;
          var wy = pos.dy + sin(angle) * orbitR;
          // Clamp to stay inside the map container with margin
          wx = wx.clamp(6.0, mapW - 50.0);
          wy = wy.clamp(6.0, mapH - 18.0);

          final isTapped = _tappedWord == '${level}_${word.text}';

          widgets.add(Positioned(
            left: wx - 2,
            top: wy - 9,
            child: GestureDetector(
              onTap: isMastered
                  ? () {
                      widget.audioService.playWord(word.text);
                      setState(
                          () => _tappedWord = '${level}_${word.text}');
                      Future.delayed(const Duration(milliseconds: 600),
                          () {
                        if (mounted) setState(() => _tappedWord = null);
                      });
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isMastered
                      ? (isTapped
                          ? color.withValues(alpha: 0.35)
                          : color.withValues(alpha: 0.1))
                      : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMastered
                        ? color.withValues(alpha: isTapped ? 0.9 : 0.35)
                        : Colors.white.withValues(alpha: 0.06),
                    width: isTapped ? 1.5 : 0.8,
                  ),
                  boxShadow: [
                    if (isTapped)
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 14,
                        spreadRadius: 1,
                      )
                    else if (isMastered)
                      BoxShadow(
                        color: color.withValues(alpha: 0.12),
                        blurRadius: 6,
                      ),
                  ],
                ),
                child: Text(
                  word.text,
                  style: AppFonts.fredoka(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isMastered
                        ? color.withValues(alpha: isTapped ? 1.0 : 0.85)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: (j * 35).ms, duration: 200.ms).scale(
                begin: const Offset(0.4, 0.4),
                delay: (j * 35).ms,
                duration: 280.ms,
                curve: Curves.easeOutBack,
              ));
        }

        // Draw faint lines from node to each word
        widgets.insert(
            0,
            Positioned.fill(
              child: CustomPaint(
                painter: _WordLinePainter(
                  center: pos,
                  words: DolchWords.wordsForLevel(level),
                  wordCount: DolchWords.wordsForLevel(level).length,
                  orbitRadius: _wordOrbitRadius,
                  color: color,
                  mapW: mapW,
                  mapH: mapH,
                ),
              ),
            ));
      }

      // Main constellation node
      final nodeSize = isMastered ? 38.0 : (isUnlocked ? 30.0 : 22.0);
      widgets.add(Positioned(
        left: pos.dx - nodeSize / 2,
        top: pos.dy - nodeSize / 2,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _expandedLevel = isExpanded ? null : level;
              _tappedWord = null;
            });
          },
          child: _ConstellationNode(
            level: level,
            size: nodeSize,
            color: color,
            isMastered: isMastered,
            isUnlocked: isUnlocked,
            isExpanded: isExpanded,
            stars: stars,
            time: time,
          ),
        ),
      ));
    }

    return widgets;
  }

  void _addZoneLabels(
      List<Widget> widgets, List<Offset> positions, double mapH) {
    for (final zone in DolchWords.zones) {
      // Place label at the average x of the zone's levels
      final startIdx = zone.startLevel - 1;
      final endIdx = min(zone.endLevel - 1, positions.length - 1);
      double avgX = 0;
      double minY = mapH;
      for (int i = startIdx; i <= endIdx; i++) {
        avgX += positions[i].dx;
        if (positions[i].dy < minY) minY = positions[i].dy;
      }
      avgX /= (endIdx - startIdx + 1);

      // Place zone name above the highest node
      final labelY = max(6.0, minY - 50);

      widgets.add(Positioned(
        left: avgX - 60,
        top: labelY,
        child: GestureDetector(
          onTap: () => widget.audioService.playWord(
            zone.name.toLowerCase().replaceAll(' ', '_'),
          ),
          child: SizedBox(
            width: 120,
            child: Text(
              '${zone.icon} ${zone.name}',
              textAlign: TextAlign.center,
              style: AppFonts.nunito(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.18),
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ));
    }
  }
}

// ── Individual constellation node ──────────────────────────────────────

class _ConstellationNode extends StatelessWidget {
  final int level;
  final double size;
  final Color color;
  final bool isMastered;
  final bool isUnlocked;
  final bool isExpanded;
  final int stars;
  final double time;

  const _ConstellationNode({
    required this.level,
    required this.size,
    required this.color,
    required this.isMastered,
    required this.isUnlocked,
    required this.isExpanded,
    required this.stars,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = isMastered
        ? 0.55 + sin(time * 2 * pi * 1.2 + level * 0.7) * 0.3
        : (isUnlocked
            ? 0.2 + sin(time * 2 * pi * 0.7 + level) * 0.1
            : 0.06 + sin(time * 2 * pi * 0.35 + level * 1.3) * 0.04);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isExpanded ? size + 6 : size,
      height: isExpanded ? size + 6 : size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isMastered
            ? RadialGradient(
                colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.08),
                ],
              )
            : null,
        color: isMastered
            ? null
            : (isUnlocked
                ? color.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02)),
        border: Border.all(
          color: isMastered
              ? color.withValues(alpha: pulse)
              : (isUnlocked
                  ? color.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05)),
          width: isMastered ? 1.5 : 0.8,
        ),
        boxShadow: [
          if (isMastered) ...[
            BoxShadow(
              color: color.withValues(alpha: pulse * 0.4),
              blurRadius: isExpanded ? 28 : 18,
              spreadRadius: isExpanded ? 5 : 2,
            ),
            BoxShadow(
              color: color.withValues(alpha: pulse * 0.15),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
          if (isUnlocked && !isMastered)
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
            ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$level',
              style: AppFonts.fredoka(
                fontSize: isMastered ? 14 : (isUnlocked ? 11 : 9),
                fontWeight: FontWeight.w600,
                color: isMastered
                    ? Colors.white.withValues(alpha: 0.95)
                    : (isUnlocked
                        ? color.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.1)),
                shadows: isMastered
                    ? [
                        Shadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            if (stars > 0 && size > 28)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (idx) => Icon(
                    Icons.star_rounded,
                    size: 7,
                    color: idx < stars
                        ? AppColors.starGold.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Background: star field + nebulae + constellation lines ──────────────

class _BackgroundPainter extends CustomPainter {
  final double time;
  final List<Offset> nodePositions;
  final ProgressService progressService;

  _BackgroundPainter({
    required this.time,
    required this.nodePositions,
    required this.progressService,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Deep space background
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050510),
            Color(0xFF080820),
            Color(0xFF060614),
          ],
        ).createShader(Offset.zero & size),
    );

    final rng = Random(42);

    // Nebula clouds
    final nebulaData = [
      (const Color(0xFF1a0a3a), 0.18),
      (const Color(0xFF0a1530), 0.15),
      (const Color(0xFF180828), 0.12),
      (const Color(0xFF0c1e30), 0.10),
      (const Color(0xFF200a20), 0.08),
    ];
    for (final (color, alpha) in nebulaData) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 60.0 + rng.nextDouble() * 80;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
      );
    }

    // Twinkling stars
    final starPaint = Paint();
    for (int i = 0; i < 120; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final baseR = rng.nextDouble() * 1.0 + 0.15;
      final phase = rng.nextDouble() * 2 * pi;
      final speed = 0.4 + rng.nextDouble() * 1.8;
      final twinkle =
          (0.25 + (sin(time * 2 * pi * speed + phase) + 1) * 0.375)
              .clamp(0.0, 1.0);

      starPaint.color = Colors.white.withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), baseR, starPaint);

      if (baseR > 0.85 && twinkle > 0.65) {
        final rayPaint = Paint()
          ..color = Colors.white.withValues(alpha: twinkle * 0.25)
          ..strokeWidth = 0.4
          ..strokeCap = StrokeCap.round;
        final r = baseR * 3;
        canvas.drawLine(Offset(x - r, y), Offset(x + r, y), rayPaint);
        canvas.drawLine(Offset(x, y - r), Offset(x, y + r), rayPaint);
      }
    }

    // Constellation path lines
    _drawConstellationLines(canvas, size);
  }

  void _drawConstellationLines(Canvas canvas, Size size) {
    if (nodePositions.length < 2) return;

    for (int i = 0; i < nodePositions.length - 1; i++) {
      final from = nodePositions[i];
      final to = nodePositions[i + 1];
      final level = i + 1;
      final nextLevel = i + 2;

      final isMastered =
          progressService.getLevel(level).highestCompletedTier >= 3;
      final nextMastered =
          progressService.getLevel(nextLevel).highestCompletedTier >= 3;
      final bothMastered = isMastered && nextMastered;
      final eitherUnlocked = progressService.isLevelUnlocked(level) ||
          progressService.isLevelUnlocked(nextLevel);

      final color = AppColors
          .levelGradients[i % AppColors.levelGradients.length][0];

      if (bothMastered) {
        final pulse = 0.25 + sin(time * 2 * pi * 1.2 + i * 0.6) * 0.12;
        // Glow layer
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = color.withValues(alpha: pulse * 0.25)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        // Core line
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = color.withValues(alpha: pulse)
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round,
        );
      } else if (eitherUnlocked) {
        _drawDashedLine(
            canvas, from, to, color.withValues(alpha: 0.1), 0.8, 4, 7);
      } else {
        _drawDashedLine(canvas, from, to,
            Colors.white.withValues(alpha: 0.035), 0.5, 2, 10);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Color color,
      double width, double dashLen, double gapLen) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;

    double d = 0;
    while (d < dist) {
      final end = min(d + dashLen, dist);
      canvas.drawLine(
        Offset(from.dx + ux * d, from.dy + uy * d),
        Offset(from.dx + ux * end, from.dy + uy * end),
        paint,
      );
      d += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => true;
}

// ── Faint lines from expanded node to word chips ────────────────────────

class _WordLinePainter extends CustomPainter {
  final Offset center;
  final List<dynamic> words;
  final int wordCount;
  final double orbitRadius;
  final Color color;
  final double mapW;
  final double mapH;

  _WordLinePainter({
    required this.center,
    required this.words,
    required this.wordCount,
    required this.orbitRadius,
    required this.color,
    required this.mapW,
    required this.mapH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;

    for (int j = 0; j < wordCount; j++) {
      final angle = (j / wordCount) * 2 * pi - (pi / 2);
      final r = orbitRadius + (j.isEven ? 0 : 10);
      var wx = center.dx + cos(angle) * r;
      var wy = center.dy + sin(angle) * r;
      wx = wx.clamp(6.0, mapW - 50.0);
      wy = wy.clamp(6.0, mapH - 18.0);
      canvas.drawLine(center, Offset(wx, wy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

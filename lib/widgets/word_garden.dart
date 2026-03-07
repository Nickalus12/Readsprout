import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/dolch_words.dart';
import '../models/progress.dart';
import '../services/audio_service.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kGardenHeight = 175.0;
const double _kLevelWidth = 180.0;
const double _kSkyHeight = 42.0;
const double _kGroundTop = 115.0;
const double _kGrassHeight = 18.0;

// Flower positions within a level section (10 flowers: 2 staggered rows).
// Back row (indices 0-4): smaller, higher (further away) — anchored just above ground.
// Front row (indices 5-9): larger, lower (closer) — anchored at ground + grass line.
// Y values represent the ground anchor point for each flower's stem base.
const List<Offset> _kBackRow = [
  Offset(14, 0),
  Offset(50, 0),
  Offset(86, 0),
  Offset(122, 0),
  Offset(158, 0),
];
const List<Offset> _kFrontRow = [
  Offset(32, 0),
  Offset(68, 0),
  Offset(104, 0),
  Offset(140, 0),
  Offset(168, 0),
];

// Decorative mushroom positions per level (deterministic scatter).
const List<Offset> _kMushroomSlots = [
  Offset(25, 0),
  Offset(95, 2),
  Offset(155, -1),
];

/// Flower growth tiers.
enum FlowerTier { bud, bloom, golden }

// ---------------------------------------------------------------------------
// WordGarden — main public widget
// ---------------------------------------------------------------------------

class WordGarden extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;

  const WordGarden({
    super.key,
    required this.progressService,
    required this.audioService,
  });

  @override
  State<WordGarden> createState() => _WordGardenState();
}

class _WordGardenState extends State<WordGarden>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _showRightFade = true;
  bool _showLeftFade = false;

  late final AnimationController _swayController;
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _swayController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _scrollOffset.value = pos.pixels;
    final newRight = pos.pixels < pos.maxScrollExtent - 8;
    final newLeft = pos.pixels > 8;
    if (newRight != _showRightFade || newLeft != _showLeftFade) {
      setState(() {
        _showRightFade = newRight;
        _showLeftFade = newLeft;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: GestureDetector(
            onTap: () => widget.audioService.playWord('garden'),
            child: Text(
              'Garden',
              style: GoogleFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.gardenStem,
              ),
            ),
          ),
        ),
        SizedBox(
          height: _kGardenHeight,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  if (_showLeftFade) Colors.transparent else Colors.white,
                  Colors.white,
                  Colors.white,
                  if (_showRightFade) Colors.transparent else Colors.white,
                ],
                stops: const [0.0, 0.06, 0.92, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: Stack(
              children: [
                // -- Parallax sky & hills (behind everything) --
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scrollOffset,
                      builder: (_, offset, __) {
                        return CustomPaint(
                          painter: _SkyPainter(
                            scrollOffset: offset,
                            viewportWidth: screenWidth,
                            totalLevels: DolchWords.totalLevels,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // -- Scrollable garden content --
                ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: DolchWords.totalLevels,
                  itemBuilder: (context, index) {
                    final level = index + 1;
                    final levelProgress =
                        widget.progressService.getLevel(level);
                    final words =
                        DolchWords.wordsForLevel(level).map((w) => w.text).toList();
                    final colors = AppColors.levelGradients[
                        index % AppColors.levelGradients.length];

                    return _LevelSection(
                      level: level,
                      levelProgress: levelProgress,
                      words: words,
                      flowerColor: colors[0],
                      audioService: widget.audioService,
                      swayController: _swayController,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sky painter — night sky, stars, moon, parallax hills, moonbeam, sky tints
// ---------------------------------------------------------------------------

class _SkyPainter extends CustomPainter {
  final double scrollOffset;
  final double viewportWidth;
  final int totalLevels;

  _SkyPainter({
    required this.scrollOffset,
    required this.viewportWidth,
    required this.totalLevels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Sky color shifts based on scroll position:
    // Early levels = cool night, later levels = warm sunset tones
    final scrollFraction = totalLevels > 1
        ? (scrollOffset / (totalLevels * _kLevelWidth)).clamp(0.0, 1.0)
        : 0.0;

    final skyTopColor = Color.lerp(
      const Color(0xFF0D1B2A), // cool night
      const Color(0xFF1A0F2E), // warm deep purple
      scrollFraction,
    )!;
    final skyMidColor = Color.lerp(
      const Color(0xFF152238), // cool mid
      const Color(0xFF2A1525), // warm mid (sunset mauve)
      scrollFraction,
    )!;

    // Night sky gradient with dynamic tint
    final skyRect = Rect.fromLTWH(0, 0, size.width, _kSkyHeight + 30);
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        skyTopColor,
        skyMidColor,
        const Color(0xFF111127).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.6, 1.0],
    );
    canvas.drawRect(skyRect, Paint()..shader = skyGradient.createShader(skyRect));

    // Stars (deterministic)
    final starPaint = Paint()..color = Colors.white;
    final rng = math.Random(42);
    for (int i = 0; i < 30; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = rng.nextDouble() * (_kSkyHeight - 5) + 2;
      final sr = 0.4 + rng.nextDouble() * 0.8;
      final alpha = 0.3 + rng.nextDouble() * 0.7;
      starPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(sx, sy), sr, starPaint);
    }

    // Moon
    final moonPaint = Paint()
      ..color = const Color(0x55FFE4B5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final moonX = size.width * 0.82 - scrollOffset * 0.05;
    canvas.drawCircle(Offset(moonX, 14), 8, moonPaint);
    canvas.drawCircle(
      Offset(moonX, 14),
      6,
      Paint()..color = const Color(0xAAFFF8DC),
    );

    // Moonbeam — subtle diagonal light ray from the moon
    _drawMoonbeam(canvas, size, moonX);

    // Far hills (parallax 0.15x)
    _drawHillLayer(
      canvas,
      size,
      offset: scrollOffset * 0.15,
      baseY: _kSkyHeight + 18,
      amplitude: 14,
      frequency: 0.006,
      color: Color.lerp(
        const Color(0xFF1A1A3E),
        const Color(0xFF2A1A2E), // warmer purple for later levels
        scrollFraction,
      )!,
      seed: 7,
    );

    // Near hills (parallax 0.3x)
    _drawHillLayer(
      canvas,
      size,
      offset: scrollOffset * 0.3,
      baseY: _kSkyHeight + 26,
      amplitude: 10,
      frequency: 0.01,
      color: Color.lerp(
        const Color(0xFF15152E),
        const Color(0xFF201520), // warmer dark for later levels
        scrollFraction,
      )!,
      seed: 13,
    );
  }

  void _drawMoonbeam(Canvas canvas, Size size, double moonX) {
    // A subtle triangular beam from the moon downward
    final beamPath = Path();
    final beamStartX = moonX;
    const beamStartY = 22.0;
    // Beam fans out diagonally
    final beamEndX1 = beamStartX - 30 - scrollOffset * 0.03;
    final beamEndX2 = beamStartX - 10 - scrollOffset * 0.03;
    const beamEndY = _kGroundTop - 10.0;

    beamPath.moveTo(beamStartX, beamStartY);
    beamPath.lineTo(beamEndX1, beamEndY);
    beamPath.lineTo(beamEndX2, beamEndY);
    beamPath.close();

    final beamRect = Rect.fromLTRB(
      beamEndX1, beamStartY, beamStartX, beamEndY,
    );
    final beamGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.06),
        Colors.white.withValues(alpha: 0.0),
      ],
    );
    canvas.drawPath(
      beamPath,
      Paint()..shader = beamGradient.createShader(beamRect),
    );
  }

  void _drawHillLayer(
    Canvas canvas,
    Size size, {
    required double offset,
    required double baseY,
    required double amplitude,
    required double frequency,
    required Color color,
    required int seed,
  }) {
    final path = Path();
    path.moveTo(0, _kGroundTop);
    for (double x = 0; x <= size.width; x += 2) {
      final worldX = x + offset;
      final y = baseY -
          amplitude *
              math.sin(worldX * frequency + seed) *
              math.cos(worldX * frequency * 0.7 + seed * 2);
      if (x == 0) {
        path.lineTo(0, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(size.width, _kGroundTop);
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) =>
      oldDelegate.scrollOffset != scrollOffset;
}

// ---------------------------------------------------------------------------
// Level section — one level's worth of ground + flowers
// ---------------------------------------------------------------------------

class _LevelSection extends StatelessWidget {
  final int level;
  final LevelProgress levelProgress;
  final List<String> words;
  final Color flowerColor;
  final AudioService audioService;
  final AnimationController swayController;

  const _LevelSection({
    required this.level,
    required this.levelProgress,
    required this.words,
    required this.flowerColor,
    required this.audioService,
    required this.swayController,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kLevelWidth,
      height: _kGardenHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Ground painting for this level
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _GroundPainter(level: level),
              ),
            ),
          ),

          // Level sign at left edge
          Positioned(
            left: 2,
            bottom: _kGardenHeight - _kGroundTop - 10,
            child: _LevelSign(level: level, color: flowerColor),
          ),

          // Decorative mushrooms
          ..._buildMushrooms(),

          // Ladybug decoration (every 2-3 levels)
          if (level % 3 == 0) _buildLadybug(),

          // Butterfly decoration (every 3rd level)
          if (level % 3 == 1) _buildButterfly(),

          // Ambient fireflies (especially near golden flowers)
          ..._buildFireflies(),

          // Flowers — back row (indices 0-4): anchored at ground line
          for (int i = 0; i < 5 && i < words.length; i++)
            Positioned(
              left: _kBackRow[i].dx - 14,
              bottom: _kGardenHeight - _kGroundTop + 2,
              child: _GardenFlower(
                word: words[i],
                tier: _tierForWord(words[i]),
                color: flowerColor,
                audioService: audioService,
                swayController: swayController,
                phaseOffset: (level * 10 + i) * 0.47,
                scale: 0.72,
              ),
            ),

          // Flowers — front row (indices 5-9): anchored at grass line
          for (int i = 0; i < 5 && i + 5 < words.length; i++)
            Positioned(
              left: _kFrontRow[i].dx - 18,
              bottom: _kGardenHeight - _kGroundTop - _kGrassHeight + 4,
              child: _GardenFlower(
                word: words[i + 5],
                tier: _tierForWord(words[i + 5]),
                color: flowerColor,
                audioService: audioService,
                swayController: swayController,
                phaseOffset: (level * 10 + i + 5) * 0.47,
                scale: 1.0,
              ),
            ),
        ],
      ),
    );
  }

  FlowerTier? _tierForWord(String word) {
    final stats = levelProgress.wordStats[word];
    final hasAttempted = stats != null && stats.attempts > 0;
    if (!hasAttempted) return null; // seed/empty
    final hasMastered = levelProgress.highestCompletedTier >= 3;
    final hasPerfect = stats.perfectAttempts > 0;
    if (hasMastered) return FlowerTier.golden;
    if (hasPerfect) return FlowerTier.bloom;
    return FlowerTier.bud;
  }

  List<Widget> _buildMushrooms() {
    // Place mushrooms only if level is odd (scatter variety)
    if (level.isEven) return [];
    final rng = math.Random(level * 37);
    final mushroomIndex = rng.nextInt(_kMushroomSlots.length);
    final pos = _kMushroomSlots[mushroomIndex];
    return [
      Positioned(
        left: pos.dx,
        top: _kGroundTop - 10 + pos.dy,
        child: RepaintBoundary(
          child: CustomPaint(
            size: const Size(12, 12),
            painter: _MushroomPainter(seed: level),
          ),
        ),
      ),
    ];
  }

  Widget _buildLadybug() {
    final rng = math.Random(level * 53);
    final lx = 40.0 + rng.nextDouble() * 100;
    return Positioned(
      left: lx,
      top: _kGroundTop - 2,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(10, 8),
          painter: _LadybugPainter(seed: level),
        ),
      ),
    );
  }

  Widget _buildButterfly() {
    final rng = math.Random(level * 19);
    final bx = 30.0 + rng.nextDouble() * 100;
    final by = 30.0 + rng.nextDouble() * 20;
    return Positioned(
      left: bx,
      top: by,
      child: _Butterfly(seed: level),
    );
  }

  List<Widget> _buildFireflies() {
    // Check if any words are golden tier
    final hasGolden = words.any((w) => _tierForWord(w) == FlowerTier.golden);
    final count = hasGolden ? 3 : 1;
    final rng = math.Random(level * 71);
    final widgets = <Widget>[];

    for (int i = 0; i < count; i++) {
      final fx = 20.0 + rng.nextDouble() * (_kLevelWidth - 40);
      final fy = 40.0 + rng.nextDouble() * 50;
      widgets.add(
        Positioned(
          left: fx,
          top: fy,
          child: _Firefly(seed: level * 10 + i, isGolden: hasGolden),
        ),
      );
    }
    return widgets;
  }
}

// ---------------------------------------------------------------------------
// Ground painter — grass, soil, dirt patches
// ---------------------------------------------------------------------------

class _GroundPainter extends CustomPainter {
  final int level;

  _GroundPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(level * 23);

    // Soil base — full ground area below the grass line
    final soilRect = Rect.fromLTWH(0, _kGroundTop, size.width, size.height - _kGroundTop);
    const soilGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.gardenSoil,
        Color(0xFF1E1508),
      ],
    );
    canvas.drawRect(
      soilRect,
      Paint()..shader = soilGradient.createShader(soilRect),
    );

    // Grass strip on top of soil — wavy top edge
    final grassPath = Path();
    grassPath.moveTo(0, _kGroundTop + _kGrassHeight);
    for (double x = 0; x <= size.width; x += 3) {
      final variation = rng.nextDouble() * 4 - 2;
      grassPath.lineTo(x, _kGroundTop + variation);
    }
    grassPath.lineTo(size.width, _kGroundTop + _kGrassHeight);
    grassPath.close();

    const grassGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF0D4A32),
        Color(0xFF0A3D2A),
        Color(0xFF0B3022),
      ],
      stops: [0.0, 0.5, 1.0],
    );
    canvas.drawPath(
      grassPath,
      Paint()..shader = grassGradient.createShader(soilRect),
    );

    // Garden bed rows — subtle tilled soil stripes in the dirt area
    final tilledPaint = Paint()
      ..color = const Color(0xFF352718).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    for (double y = _kGroundTop + _kGrassHeight + 6;
        y < size.height - 4;
        y += 8 + rng.nextDouble() * 4) {
      canvas.drawLine(
        Offset(4, y),
        Offset(size.width - 4, y + rng.nextDouble() * 2 - 1),
        tilledPaint,
      );
    }

    // Grass blades — small triangular tufts along the grass line
    final bladePaint = Paint()..style = PaintingStyle.fill;
    for (double x = 2; x < size.width - 2; x += 5 + rng.nextDouble() * 7) {
      final bladeHeight = 4.0 + rng.nextDouble() * 7;
      final baseY = _kGroundTop + rng.nextDouble() * 2;
      final lean = (rng.nextDouble() - 0.5) * 3;

      final alpha = 0.35 + rng.nextDouble() * 0.45;
      bladePaint.color = Color.lerp(
        const Color(0xFF10B981),
        const Color(0xFF059669),
        rng.nextDouble(),
      )!.withValues(alpha: alpha);

      final bladePath = Path()
        ..moveTo(x - 1.2, baseY)
        ..lineTo(x + lean, baseY - bladeHeight)
        ..lineTo(x + 1.2, baseY)
        ..close();
      canvas.drawPath(bladePath, bladePaint);
    }

    // Dirt patches — subtle darker spots in the soil
    final dirtPaint = Paint()
      ..color = const Color(0xFF1F170D).withValues(alpha: 0.4);
    for (int i = 0; i < 3; i++) {
      final dx = rng.nextDouble() * (size.width - 20) + 10;
      final dy = _kGroundTop + _kGrassHeight + rng.nextDouble() * 15 + 5;
      final rx = 4.0 + rng.nextDouble() * 6;
      final ry = 2.0 + rng.nextDouble() * 2;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dx, dy), width: rx * 2, height: ry * 2),
        dirtPaint,
      );
    }

    // Small pebbles scattered on soil
    final pebblePaint = Paint()
      ..color = const Color(0xFF3A3530).withValues(alpha: 0.5);
    for (int i = 0; i < 5; i++) {
      final px = rng.nextDouble() * size.width;
      final py = _kGroundTop + _kGrassHeight + 2 + rng.nextDouble() * 20;
      canvas.drawCircle(Offset(px, py), 1.0 + rng.nextDouble() * 0.8, pebblePaint);
    }

    // Front garden edge — a low wooden border at the very bottom
    final edgeY = size.height - 3.0;
    final edgePaint = Paint()
      ..color = const Color(0xFF3D2B14)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, edgeY), Offset(size.width, edgeY), edgePaint);
    // Highlight on top of the edge
    canvas.drawLine(
      Offset(0, edgeY - 1.5),
      Offset(size.width, edgeY - 1.5),
      Paint()
        ..color = const Color(0xFF5C4A2A).withValues(alpha: 0.5)
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_GroundPainter oldDelegate) =>
      oldDelegate.level != level;
}

// ---------------------------------------------------------------------------
// Level sign — small garden sign post with vine decoration
// ---------------------------------------------------------------------------

class _LevelSign extends StatelessWidget {
  final int level;
  final Color color;

  const _LevelSign({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 34,
      child: CustomPaint(
        painter: _SignPainter(level: level, color: color),
      ),
    );
  }
}

class _SignPainter extends CustomPainter {
  final int level;
  final Color color;

  _SignPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final postCx = size.width / 2;

    // Wooden post
    final postPaint = Paint()..color = const Color(0xFF5C3A1E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(postCx - 2, 10, 4, size.height - 10),
        const Radius.circular(1),
      ),
      postPaint,
    );

    // Vine wrapping around the post
    final vinePaint = Paint()
      ..color = AppColors.gardenStem.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    final vinePath = Path();
    vinePath.moveTo(postCx - 2, size.height - 4);
    vinePath.quadraticBezierTo(postCx + 5, size.height - 10, postCx - 1, size.height - 14);
    vinePath.quadraticBezierTo(postCx - 5, size.height - 18, postCx + 1, size.height - 22);
    canvas.drawPath(vinePath, vinePaint);

    // Tiny leaf on the vine
    final leafPaint = Paint()..color = AppColors.gardenLeaf.withValues(alpha: 0.6);
    canvas.save();
    canvas.translate(postCx + 4, size.height - 11);
    canvas.rotate(0.5);
    final leafPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(2, -2, 0, -4)
      ..quadraticBezierTo(-2, -2, 0, 0)
      ..close();
    canvas.drawPath(leafPath, leafPaint);
    canvas.restore();

    // Small flower at top of post
    const flowerY = 11.0;
    final flowerX = postCx + 6;
    // Tiny stem to flower
    canvas.drawLine(
      Offset(postCx + 2, 14),
      Offset(flowerX, flowerY),
      Paint()
        ..color = AppColors.gardenStem.withValues(alpha: 0.5)
        ..strokeWidth = 0.8,
    );
    // Tiny 4-petal flower
    final petalPaint = Paint()..color = color.withValues(alpha: 0.7);
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final px = flowerX + math.cos(angle) * 2.0;
      final py = flowerY + math.sin(angle) * 2.0;
      canvas.drawCircle(Offset(px, py), 1.2, petalPaint);
    }
    canvas.drawCircle(Offset(flowerX, flowerY), 0.8, Paint()..color = const Color(0xFFFFE082));

    // Sign board
    final boardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 0, size.width - 2, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(boardRect, Paint()..color = const Color(0xFF8B6914));
    canvas.drawRRect(
      boardRect,
      Paint()
        ..color = const Color(0xFFA07D1C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Level number
    final tp = TextPainter(
      text: TextSpan(
        text: '$level',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (16 - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_SignPainter old) =>
      old.level != level || old.color != color;
}

// ---------------------------------------------------------------------------
// Mushroom painter — tiny decorative mushroom
// ---------------------------------------------------------------------------

class _MushroomPainter extends CustomPainter {
  final int seed;

  _MushroomPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;

    // Stem
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 1.5, bottom - 6, 3, 6),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFFE8D5B8),
    );

    // Cap
    final capPath = Path()
      ..moveTo(cx - 5, bottom - 5)
      ..quadraticBezierTo(cx - 5.5, bottom - 11, cx, bottom - 12)
      ..quadraticBezierTo(cx + 5.5, bottom - 11, cx + 5, bottom - 5)
      ..close();

    final rng = math.Random(seed);
    final capColor = rng.nextBool()
        ? const Color(0xFFE84040) // Red
        : const Color(0xFFD4883E); // Brown
    canvas.drawPath(capPath, Paint()..color = capColor);

    // White dots on cap
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(cx - 2, bottom - 9), 0.8, dotPaint);
    canvas.drawCircle(Offset(cx + 2, bottom - 8), 0.7, dotPaint);
    canvas.drawCircle(Offset(cx, bottom - 10.5), 0.6, dotPaint);
  }

  @override
  bool shouldRepaint(_MushroomPainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------
// Ladybug painter — tiny red ladybug crawling on the ground
// ---------------------------------------------------------------------------

class _LadybugPainter extends CustomPainter {
  final int seed;

  _LadybugPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Body (red oval)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 8, height: 6),
      Paint()..color = const Color(0xFFE84040),
    );

    // Head (black circle)
    canvas.drawCircle(
      Offset(cx - 4.5, cy),
      2.0,
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Center line
    canvas.drawLine(
      Offset(cx - 1, cy - 3),
      Offset(cx - 1, cy + 3),
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..strokeWidth = 0.6,
    );

    // Black spots
    final spotPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(Offset(cx + 1, cy - 1), 0.8, spotPaint);
    canvas.drawCircle(Offset(cx + 2, cy + 1.5), 0.7, spotPaint);
    canvas.drawCircle(Offset(cx - 2.5, cy + 1), 0.6, spotPaint);
  }

  @override
  bool shouldRepaint(_LadybugPainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------
// Firefly — ambient glowing dot with fade animation
// ---------------------------------------------------------------------------

class _Firefly extends StatelessWidget {
  final int seed;
  final bool isGolden;

  const _Firefly({required this.seed, required this.isGolden});

  @override
  Widget build(BuildContext context) {
    final rng = math.Random(seed);
    final duration = 1500 + rng.nextInt(1500);
    final delay = rng.nextInt(2000);
    final glowColor = isGolden
        ? const Color(0xFFFFD700)
        : const Color(0xFF90EE90);

    return SizedBox(
      width: 6,
      height: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: glowColor.withValues(alpha: 0.6),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.3),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    )
        .animate(
          delay: Duration(milliseconds: delay),
          onPlay: (c) => c.repeat(reverse: true),
        )
        .fadeIn(duration: Duration(milliseconds: duration))
        .fadeOut(
          begin: 1.0,
          duration: Duration(milliseconds: duration),
        )
        .moveY(begin: 0, end: -3, duration: Duration(milliseconds: duration + 500), curve: Curves.easeInOut)
        .moveX(begin: -2, end: 2, duration: Duration(milliseconds: duration + 800), curve: Curves.easeInOut);
  }
}

// ---------------------------------------------------------------------------
// Butterfly — animated decorative element
// ---------------------------------------------------------------------------

class _Butterfly extends StatelessWidget {
  final int seed;

  const _Butterfly({required this.seed});

  @override
  Widget build(BuildContext context) {
    final rng = math.Random(seed);
    final hue = rng.nextDouble() * 360;
    final color =
        HSLColor.fromAHSL(1.0, hue, 0.7, 0.65).toColor();

    return SizedBox(
      width: 14,
      height: 10,
      child: CustomPaint(
        painter: _ButterflyPainter(color: color),
      ),
    )
        .animate(
          onPlay: (c) => c.repeat(reverse: true),
        )
        .moveY(begin: 0, end: -4, duration: 1800.ms, curve: Curves.easeInOut)
        .moveX(begin: -2, end: 2, duration: 2400.ms, curve: Curves.easeInOut)
        .scaleXY(begin: 0.9, end: 1.1, duration: 600.ms);
  }
}

class _ButterflyPainter extends CustomPainter {
  final Color color;

  _ButterflyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final wingPaint = Paint()..color = color.withValues(alpha: 0.75);

    // Left wing
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - 3.5, cy - 1),
        width: 6,
        height: 7,
      ),
      wingPaint,
    );
    // Right wing
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 3.5, cy - 1),
        width: 6,
        height: 7,
      ),
      wingPaint,
    );
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 1.5, height: 6),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF2A2A2A),
    );
  }

  @override
  bool shouldRepaint(_ButterflyPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Garden flower — individual tappable flower with sway animation
// ---------------------------------------------------------------------------

class _GardenFlower extends StatefulWidget {
  final String word;
  final FlowerTier? tier; // null = empty seed slot
  final Color color;
  final AudioService audioService;
  final AnimationController swayController;
  final double phaseOffset;
  final double scale;

  const _GardenFlower({
    required this.word,
    required this.tier,
    required this.color,
    required this.audioService,
    required this.swayController,
    required this.phaseOffset,
    required this.scale,
  });

  @override
  State<_GardenFlower> createState() => _GardenFlowerState();
}

class _GardenFlowerState extends State<_GardenFlower> {
  bool _showBubble = false;

  void _onTap() async {
    if (widget.tier == null) return; // don't play audio for empty seeds
    setState(() => _showBubble = true);
    widget.audioService.playWord(widget.word);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _showBubble = false);
  }

  @override
  Widget build(BuildContext context) {
    // Seed / empty slot — dirt mound at the bottom (anchored to ground)
    if (widget.tier == null) {
      return SizedBox(
        width: 36,
        height: 20,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(22, 14),
              painter: _SeedPainter(),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 70,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Animated flower
            AnimatedBuilder(
              animation: widget.swayController,
              builder: (_, __) {
                final t = widget.swayController.value;
                final angle =
                    math.sin(t * 2 * math.pi + widget.phaseOffset) * 0.04;
                return Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..rotateZ(angle)
                    ..scaleByDouble(widget.scale, widget.scale, 1.0, 1.0),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(36, 60),
                      painter: _FlowerPainter(
                        tier: widget.tier!,
                        color: widget.color,
                        swayValue: t,
                        phaseOffset: widget.phaseOffset,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Word bubble popup
            if (_showBubble)
              Positioned(
                top: -24,
                child: _WordBubble(
                  word: widget.word,
                  color: widget.tier == FlowerTier.golden
                      ? AppColors.starGold
                      : widget.color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seed painter — small dirt mound for unplanted slots
// ---------------------------------------------------------------------------

class _SeedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;

    // Dirt mound (half ellipse)
    final moundPath = Path()
      ..moveTo(0, bottom)
      ..quadraticBezierTo(cx, bottom - 10, size.width, bottom)
      ..close();
    canvas.drawPath(
      moundPath,
      Paint()..color = const Color(0xFF3D2B18).withValues(alpha: 0.7),
    );

    // Tiny seed
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, bottom - 5),
        width: 3,
        height: 2,
      ),
      Paint()..color = const Color(0xFF5C4A32).withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Flower painter — draws bud, bloom, or golden flower
// ---------------------------------------------------------------------------

class _FlowerPainter extends CustomPainter {
  final FlowerTier tier;
  final Color color;
  final double swayValue;
  final double phaseOffset;

  _FlowerPainter({
    required this.tier,
    required this.color,
    required this.swayValue,
    required this.phaseOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (tier) {
      case FlowerTier.bud:
        _paintBud(canvas, size);
      case FlowerTier.bloom:
        _paintBloom(canvas, size);
      case FlowerTier.golden:
        _paintGolden(canvas, size);
    }
  }

  // -- BUD: short stem, closed bud, one leaf --
  void _paintBud(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;
    final stemTop = bottom - 28;

    // Stem
    final stemPath = Path()
      ..moveTo(cx, bottom)
      ..cubicTo(cx - 1, bottom - 10, cx + 2, bottom - 20, cx, stemTop);
    canvas.drawPath(
      stemPath,
      Paint()
        ..color = AppColors.gardenStem.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Small leaf
    _drawLeaf(canvas, Offset(cx + 1, bottom - 14), 6, 3, 0.3);

    // Closed bud — 3 overlapping petals
    final budCenter = Offset(cx, stemTop + 2);
    final budPaint = Paint()..color = AppColors.gardenStem;
    // Left petal
    canvas.save();
    canvas.translate(budCenter.dx, budCenter.dy);
    canvas.rotate(-0.25);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 5, height: 9),
      budPaint,
    );
    canvas.restore();
    // Right petal
    canvas.save();
    canvas.translate(budCenter.dx, budCenter.dy);
    canvas.rotate(0.25);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 5, height: 9),
      budPaint,
    );
    canvas.restore();
    // Center petal (slightly lighter)
    canvas.drawOval(
      Rect.fromCenter(center: budCenter, width: 4, height: 10),
      Paint()..color = const Color(0xFF34D399),
    );
  }

  // -- BLOOM: taller stem, open petals, center, two leaves, dewdrops --
  void _paintBloom(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;
    final stemTop = bottom - 38;
    final flowerCenter = Offset(cx, stemTop + 2);

    // Stem with gentle curve
    final stemPath = Path()
      ..moveTo(cx, bottom)
      ..cubicTo(
        cx + 3, bottom - 12,
        cx - 3, bottom - 26,
        cx, stemTop + 8,
      );
    canvas.drawPath(
      stemPath,
      Paint()
        ..color = AppColors.gardenStem.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // Two leaves
    _drawLeaf(canvas, Offset(cx + 2, bottom - 16), 8, 4, 0.4);
    _drawLeaf(canvas, Offset(cx - 2, bottom - 24), 7, 3.5, -0.5);

    // Glow behind flower
    canvas.drawCircle(
      flowerCenter,
      10,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 6 petals
    final petalPaint = Paint()..color = color.withValues(alpha: 0.85);
    for (int i = 0; i < 6; i++) {
      final angle = (i * math.pi * 2 / 6);
      canvas.save();
      canvas.translate(flowerCenter.dx, flowerCenter.dy);
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -6), width: 5.5, height: 9),
        petalPaint,
      );
      canvas.restore();
    }

    // Center
    canvas.drawCircle(
      flowerCenter,
      3.5,
      Paint()..color = const Color(0xFFFFE082),
    );
    canvas.drawCircle(
      flowerCenter,
      2.0,
      Paint()..color = const Color(0xFFFFF3C4),
    );

    // Dewdrops on petal tips (2-3 tiny translucent circles)
    final dewPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35);
    final dewHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.55);
    for (int i = 0; i < 3; i++) {
      final angle = i * math.pi * 2 / 3 + 0.3; // offset so they sit nicely
      final dx = flowerCenter.dx + math.cos(angle) * 9.0;
      final dy = flowerCenter.dy + math.sin(angle) * 9.0;
      canvas.drawCircle(Offset(dx, dy), 1.5, dewPaint);
      canvas.drawCircle(Offset(dx - 0.3, dy - 0.3), 0.6, dewHighlight);
    }
  }

  // -- GOLDEN: star flower, glow, sparkles --
  void _paintGolden(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;
    final stemTop = bottom - 42;
    final flowerCenter = Offset(cx, stemTop);

    // Stem
    final stemPath = Path()
      ..moveTo(cx, bottom)
      ..cubicTo(
        cx + 4, bottom - 14,
        cx - 3, bottom - 30,
        cx, stemTop + 8,
      );
    canvas.drawPath(
      stemPath,
      Paint()
        ..color = AppColors.gardenStem
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Two leaves
    _drawLeaf(canvas, Offset(cx + 3, bottom - 16), 9, 4.5, 0.4);
    _drawLeaf(canvas, Offset(cx - 3, bottom - 28), 8, 4, -0.5);

    // Outer glow
    canvas.drawCircle(
      flowerCenter,
      14,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Star-shaped petals (6-pointed star)
    final starPath = _buildStarPath(flowerCenter, 6, 11, 5.5);
    canvas.drawPath(
      starPath,
      Paint()..color = AppColors.starGold,
    );
    // Inner highlight
    final innerStarPath = _buildStarPath(flowerCenter, 6, 7, 4);
    canvas.drawPath(
      innerStarPath,
      Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: 0.6),
    );

    // Center
    canvas.drawCircle(
      flowerCenter,
      3,
      Paint()..color = Colors.white,
    );

    // Sparkles around the flower
    final sparkleAlpha =
        0.3 + 0.7 * ((math.sin(swayValue * math.pi * 4 + phaseOffset) + 1) / 2);
    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: sparkleAlpha);
    _drawSparkle(canvas, Offset(cx - 12, stemTop - 6), 2.5, sparklePaint);
    _drawSparkle(canvas, Offset(cx + 11, stemTop - 3), 2.0, sparklePaint);
    _drawSparkle(canvas, Offset(cx + 6, stemTop - 12), 1.8, sparklePaint);
    _drawSparkle(canvas, Offset(cx - 7, stemTop + 8), 1.5, sparklePaint);
  }

  // -- Helpers --

  void _drawLeaf(Canvas canvas, Offset base, double length, double width, double angle) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final leafPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(width, -length * 0.4, 0, -length)
      ..quadraticBezierTo(-width, -length * 0.4, 0, 0)
      ..close();
    canvas.drawPath(
      leafPath,
      Paint()..color = AppColors.gardenLeaf.withValues(alpha: 0.7),
    );
    // Leaf vein
    canvas.drawLine(
      Offset.zero,
      Offset(0, -length * 0.85),
      Paint()
        ..color = AppColors.gardenStem.withValues(alpha: 0.4)
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  Path _buildStarPath(Offset center, int points, double outerR, double innerR) {
    final path = Path();
    final step = math.pi / points;
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = i * step - math.pi / 2;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  void _drawSparkle(Canvas canvas, Offset center, double r, Paint paint) {
    // 4-pointed sparkle (cross)
    paint.strokeWidth = 0.8;
    canvas.drawLine(
      Offset(center.dx - r, center.dy),
      Offset(center.dx + r, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - r),
      Offset(center.dx, center.dy + r),
      paint,
    );
    // Diagonal arms (smaller) for a twinkle effect
    final d = r * 0.6;
    paint.strokeWidth = 0.5;
    canvas.drawLine(
      Offset(center.dx - d, center.dy - d),
      Offset(center.dx + d, center.dy + d),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + d, center.dy - d),
      Offset(center.dx - d, center.dy + d),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.tier != tier ||
      old.color != color ||
      (tier == FlowerTier.golden && old.swayValue != swayValue);
}

// ---------------------------------------------------------------------------
// Word bubble — animated popup when a flower is tapped
// ---------------------------------------------------------------------------

class _WordBubble extends StatelessWidget {
  final String word;
  final Color color;

  const _WordBubble({required this.word, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        word,
        style: GoogleFonts.fredoka(
          fontSize: 12,
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 180.ms)
        .slideY(begin: 0.4, end: 0, duration: 200.ms, curve: Curves.easeOut)
        .scaleXY(begin: 0.8, end: 1.0, duration: 200.ms, curve: Curves.easeOut);
  }
}

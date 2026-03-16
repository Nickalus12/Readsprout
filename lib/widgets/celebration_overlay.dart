import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../data/phrase_templates.dart';
import '../data/word_context.dart';

/// Words that are notably tricky for young readers — irregular spelling,
/// silent letters, or unusual phonics. Getting these right deserves extra praise.
const _hardWords = <String>{
  'because', 'could', 'would', 'should', 'their', 'there', 'where',
  'which', 'about', 'again', 'always', 'around', 'before', 'better',
  'bring', 'carry', 'clean', 'does', 'done', 'draw', 'drink', 'eight',
  'every', 'found', 'funny', 'goes', 'going', 'have', 'hold', 'hurt',
  'keep', 'kind', 'laugh', 'light', 'live', 'long', 'made', 'many',
  'much', 'must', 'never', 'once', 'only', 'open', 'own', 'pick',
  'please', 'pull', 'read', 'right', 'said', 'shall', 'show', 'small',
  'some', 'start', 'take', 'tell', 'thank', 'these', 'thing',
  'think', 'those', 'thought', 'today', 'together', 'under', 'upon',
  'very', 'walk', 'want', 'warm', 'wash', 'were', 'while', 'wish',
  'work', 'world', 'write', 'your',
};

/// Extra praise messages for hard words.
const _hardWordPraise = [
  "Wow, that's a tough one!",
  'Big word, no problem!',
  'That was a tricky word!',
  'You nailed a hard one!',
  'Super speller!',
];

class CelebrationOverlay extends StatefulWidget {
  final String word;
  final String playerName;
  final int? zoneIndex;
  final int inLevelStreak;
  final String? zoneEncouragement;

  /// Current tier: 1 = Explorer, 2 = Adventurer, 3 = Champion.
  final int tier;

  /// Number of mistakes on this word.
  final int mistakes;

  /// True when a Champion completes all words with 0 mistakes.
  final bool isPerfectChampionRun;

  const CelebrationOverlay({
    super.key,
    required this.word,
    this.playerName = '',
    this.zoneIndex,
    this.inLevelStreak = 0,
    this.zoneEncouragement,
    this.tier = 1,
    this.mistakes = 0,
    this.isPerfectChampionRun = false,
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _glowController;
  late final AnimationController _sparkleController;
  late final String _praise;
  late final Color _zoneAccent;
  late final String? _hardWordMessage;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Sparkle rotation for tier 2+ effects
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Pick zone accent color for tinting
    _zoneAccent = _zoneAccentColor(widget.zoneIndex);

    // Hard word detection
    final wordLower = widget.word.toLowerCase();
    if (_hardWords.contains(wordLower) && widget.mistakes == 0) {
      _hardWordMessage = (_hardWordPraise.toList()..shuffle()).first;
    } else {
      _hardWordMessage = null;
    }

    // Zone-aware praise: use provided encouragement, or generate from zone
    if (widget.zoneEncouragement != null && widget.zoneEncouragement!.isNotEmpty) {
      _praise = widget.zoneEncouragement!;
    } else if (widget.zoneIndex != null && widget.playerName.isNotEmpty) {
      final zoneName = _zoneNameFromIndex(widget.zoneIndex!);
      final key = PhraseTemplates.zoneKey(zoneName);
      _praise = PhraseTemplates.randomZoneEncouragement(key, widget.playerName);
    } else {
      const genericPraise = [
        'Great job!',
        'Awesome!',
        'You got it!',
        'Well done!',
        'Perfect!',
        'Nice work!',
        'Way to go!',
        'Fantastic!',
      ];
      _praise = (List.of(genericPraise)..shuffle()).first;
    }
  }

  static String _zoneNameFromIndex(int index) {
    const names = [
      'Whispering Woods',
      'Shimmer Shore',
      'Crystal Peaks',
      'Skyward Kingdom',
      'Celestial Crown',
    ];
    return names[index.clamp(0, 4)];
  }

  static Color _zoneAccentColor(int? zoneIndex) {
    if (zoneIndex == null) return AppColors.success;
    const accents = [
      Color(0xFF3DA55D), // Whispering Woods — forest green
      Color(0xFF48A9C5), // Shimmer Shore — ocean blue
      Color(0xFFC8D4FF), // Crystal Peaks — icy lavender
      Color(0xFFF0C8A0), // Skyward Kingdom — warm gold
      Color(0xFFC8B4F0), // Celestial Crown — nebula purple
    ];
    return accents[zoneIndex.clamp(0, 4)];
  }

  @override
  void dispose() {
    _glowController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  Color _lerpThroughColors(double t, List<Color> colors) {
    if (colors.length < 2) return colors.first;
    final segmentCount = colors.length - 1;
    final scaledT = t * segmentCount;
    final index = scaledT.floor().clamp(0, segmentCount - 1);
    final localT = scaledT - index;
    return Color.lerp(colors[index], colors[index + 1], localT)!;
  }

  List<Color> get _glowColors {
    if (widget.isPerfectChampionRun) {
      return [
        AppColors.starGold,
        const Color(0xFFFFF176),
        AppColors.starGold,
        const Color(0xFFFFE082),
        AppColors.starGold,
      ];
    }
    return [
      _zoneAccent,
      AppColors.electricBlue,
      _zoneAccent,
      AppColors.starGold,
      _zoneAccent,
    ];
  }

  /// Number of stars to show based on tier.
  int get _starCount => widget.tier.clamp(1, 3);

  /// Star color based on tier and performance.
  Color get _starColor {
    if (widget.isPerfectChampionRun) return AppColors.starGold;
    if (widget.tier == 3) return AppColors.starGold;
    if (widget.tier == 2) return const Color(0xFFC0C0C0); // silver
    return AppColors.electricBlue;
  }

  /// Glow intensity for star color.
  double get _starGlowIntensity {
    if (widget.isPerfectChampionRun) return 0.8;
    if (widget.tier == 3) return 0.6;
    if (widget.tier == 2) return 0.4;
    return 0.3;
  }

  @override
  Widget build(BuildContext context) {
    final showStreakBadge = widget.inLevelStreak >= 3;
    final isGoldenCelebration = widget.isPerfectChampionRun;

    return Semantics(
      label: '$_praise Word: ${widget.word}',
      liveRegion: true,
      child: Container(
      color: Color(isGoldenCelebration ? 0xFF1A1400 : 0xFF0A0A1A)
          .withValues(alpha: isGoldenCelebration ? 0.92 : 0.88),
      child: Stack(
        children: [
          // ── Tier 2+: Sparkle ring effect ──────────
          if (widget.tier >= 2)
            _buildSparkleRing(),

          // ── Tier 3 perfect: Radial golden glow ────
          if (isGoldenCelebration)
            _buildGoldenGlow(),

          // ── Main content ──────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Perfect Champion banner ───────────
                if (isGoldenCelebration) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.starGold.withValues(alpha: 0.0),
                          AppColors.starGold.withValues(alpha: 0.2),
                          AppColors.starGold.withValues(alpha: 0.0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PERFECT CHAMPION!',
                      style: AppFonts.fredoka(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.starGold,
                        letterSpacing: 4,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .shimmer(
                        duration: 1500.ms,
                        color: AppColors.starGold.withValues(alpha: 0.5),
                      ),
                  const SizedBox(height: 12),
                ],

                // ── Streak indicator (3+ in a row) ──────────
                if (showStreakBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _zoneAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _zoneAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                          color: widget.inLevelStreak >= 5
                              ? AppColors.starGold
                              : _zoneAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.inLevelStreak} in a row!',
                          style: AppFonts.fredoka(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: widget.inLevelStreak >= 5
                                ? AppColors.starGold
                                : _zoneAccent,
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .scaleXY(
                        begin: 0.5,
                        end: 1.0,
                        duration: 400.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: 200.ms),

                if (showStreakBadge) const SizedBox(height: 12),

                // ── Word with animated zone-tinted glow ──────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        final glowColor = _lerpThroughColors(
                          _glowController.value,
                          _glowColors,
                        );
                        return Text(
                          widget.word.toUpperCase(),
                          style: AppFonts.fredoka(
                            fontSize: 68,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 10,
                            shadows: [
                              Shadow(color: glowColor, blurRadius: 28),
                              Shadow(
                                color: glowColor.withValues(alpha: 0.5),
                                blurRadius: 56,
                              ),
                              Shadow(
                                color: glowColor.withValues(alpha: 0.2),
                                blurRadius: 80,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                )
                    .animate()
                    .scaleXY(
                      begin: 0.3,
                      end: 1.0,
                      curve: Curves.elasticOut,
                      duration: 700.ms,
                    )
                    .fadeIn(duration: 200.ms)
                    .shimmer(
                      delay: 700.ms,
                      duration: 1200.ms,
                      color: (isGoldenCelebration
                              ? AppColors.starGold
                              : _zoneAccent)
                          .withValues(alpha: 0.3),
                    ),

                // ── Hard word extra praise ───────────────
                if (_hardWordMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.starGold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.starGold.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _hardWordMessage,
                      style: AppFonts.fredoka(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.starGold,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 300.ms)
                      .scaleXY(
                        begin: 0.7,
                        end: 1.0,
                        delay: 400.ms,
                        duration: 400.ms,
                        curve: Curves.elasticOut,
                      ),
                ],

                // ── Emoji + context sentence ───────────────
                if (getWordContext(widget.word) != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    getWordEmoji(widget.word),
                    style: const TextStyle(fontSize: 48),
                  )
                      .animate()
                      .scaleXY(
                        begin: 0.0,
                        end: 1.0,
                        delay: 300.ms,
                        duration: 500.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(delay: 300.ms, duration: 200.ms),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      getWordSentence(widget.word),
                      textAlign: TextAlign.center,
                      style: AppFonts.nunito(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 400.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 500.ms,
                        duration: 400.ms,
                        curve: Curves.easeOut,
                      ),
                ],

                const SizedBox(height: 16),

                // ── Zone-aware praise in a pill badge ─────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _zoneAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _zoneAccent.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _zoneAccent.withValues(alpha: 0.1),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Text(
                      _praise,
                      textAlign: TextAlign.center,
                      style: AppFonts.fredoka(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: _zoneAccent,
                        shadows: [
                          Shadow(
                            color: _zoneAccent.withValues(alpha: 0.5),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                    .animate()
                    .scaleXY(
                      begin: 0.4,
                      end: 1.0,
                      delay: 200.ms,
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                    )
                    .fadeIn(delay: 200.ms, duration: 250.ms),

                const SizedBox(height: 20),

                // ── Tier-scaled star burst ──────────────────────
                _buildStarBurst(),
              ],
            ),
          ),
        ],
      ),
    ))
        .animate()
        .fadeIn(duration: 200.ms);
  }

  // ── Star burst: 1 star for T1, 2 for T2, 3 for T3 ────────────

  Widget _buildStarBurst() {
    final count = _starCount;
    final color = _starColor;
    final glowIntensity = _starGlowIntensity;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        // For single star, make it the "hero" size. For multi, middle is largest.
        final bool isHero;
        if (count == 1) {
          isHero = true;
        } else if (count == 3) {
          isHero = i == 1;
        } else {
          isHero = false; // 2 stars: equal size
        }

        final size = isHero ? 52.0 : (count == 2 ? 40.0 : 34.0);
        final iconSize = isHero ? 32.0 : (count == 2 ? 26.0 : 22.0);
        // Dramatic staggered reveal: each star appears one at a time
        final starDelay = 400 + (i * 280);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color,
                  color.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glowIntensity),
                  blurRadius: widget.tier >= 3 ? 24 : 16,
                  spreadRadius: widget.tier >= 3 ? 6 : 3,
                ),
              ],
            ),
            child: Icon(
              Icons.star_rounded,
              size: iconSize,
              color: Colors.white,
            ),
          )
              .animate()
              .scaleXY(
                begin: 0,
                end: 1.3,
                delay: Duration(milliseconds: starDelay),
                duration: 400.ms,
                curve: Curves.easeOut,
              )
              .then()
              .scaleXY(
                begin: 1.3,
                end: 1.0,
                duration: 300.ms,
                curve: Curves.bounceOut,
              )
              .rotate(
                begin: -0.15,
                end: 0,
                delay: Duration(milliseconds: starDelay),
                duration: 500.ms,
                curve: Curves.elasticOut,
              ),
        );
      }),
    );
  }

  // ── Sparkle ring (Tier 2+): rotating dots around the word ─────

  Widget _buildSparkleRing() {
    final sparkleCount = widget.tier >= 3 ? 12 : 6;
    final sparkleRadius = widget.tier >= 3 ? 140.0 : 120.0;
    final sparkleColor = widget.tier >= 3
        ? AppColors.starGold
        : AppColors.electricBlue;

    return Center(
      child: AnimatedBuilder(
        animation: _sparkleController,
        builder: (context, _) {
          return SizedBox(
            width: sparkleRadius * 2,
            height: sparkleRadius * 2,
            child: CustomPaint(
              painter: _SparklePainter(
                count: sparkleCount,
                radius: sparkleRadius,
                color: sparkleColor,
                rotation: _sparkleController.value * 2 * pi,
                intensity: widget.tier >= 3 ? 1.0 : 0.6,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Golden radial glow (perfect Champion) ─────────────────────

  Widget _buildGoldenGlow() {
    return Center(
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, _) {
          final pulse = 0.8 + 0.2 * sin(_glowController.value * 2 * pi);
          return Container(
            width: 300 * pulse,
            height: 300 * pulse,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.starGold.withValues(alpha: 0.15),
                  AppColors.starGold.withValues(alpha: 0.05),
                  AppColors.starGold.withValues(alpha: 0.0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Sparkle painter for tier 2+ celebrations ────────────────────

class _SparklePainter extends CustomPainter {
  final int count;
  final double radius;
  final Color color;
  final double rotation;
  final double intensity;

  _SparklePainter({
    required this.count,
    required this.radius,
    required this.color,
    required this.rotation,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color.withValues(alpha: 0.6 * intensity);

    for (int i = 0; i < count; i++) {
      final angle = rotation + (i * 2 * pi / count);
      // Oscillate radius slightly for twinkling effect
      final r = radius * (0.9 + 0.1 * sin(angle * 3 + rotation * 2));
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      final dotRadius = 1.5 + 1.0 * sin(angle * 2 + rotation * 3).abs();
      canvas.drawCircle(Offset(x, y), dotRadius * intensity, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.rotation != rotation;
}

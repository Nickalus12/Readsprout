import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../data/phrase_templates.dart';
class CelebrationOverlay extends StatefulWidget {
  final String word;
  final String playerName;
  final int? zoneIndex;
  final int inLevelStreak;
  final String? zoneEncouragement;

  const CelebrationOverlay({
    super.key,
    required this.word,
    this.playerName = '',
    this.zoneIndex,
    this.inLevelStreak = 0,
    this.zoneEncouragement,
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final String _praise;
  late final Color _zoneAccent;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Pick zone accent color for tinting
    _zoneAccent = _zoneAccentColor(widget.zoneIndex);

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

  List<Color> get _glowColors => [
        _zoneAccent,
        AppColors.electricBlue,
        _zoneAccent,
        AppColors.starGold,
        _zoneAccent,
      ];

  @override
  Widget build(BuildContext context) {
    final showStreakBadge = widget.inLevelStreak >= 3;

    return Container(
      color: const Color(0xFF0A0A1A).withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 8,
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
                  color: _zoneAccent.withValues(alpha: 0.3),
                ),

            const SizedBox(height: 20),

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
                    fontSize: 22,
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

            // ── Star burst (3 stars) ──────────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Middle star is slightly larger
                final size = i == 1 ? 28.0 : 22.0;
                final iconSize = i == 1 ? 18.0 : 14.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.starGold,
                          AppColors.starGold.withValues(alpha: 0.6),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.starGold.withValues(alpha: 0.6),
                          blurRadius: 14,
                          spreadRadius: 2,
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
                        end: 1.0,
                        delay: Duration(milliseconds: 300 + (i * 140)),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      )
                      .rotate(
                        begin: -0.1,
                        end: 0,
                        delay: Duration(milliseconds: 300 + (i * 140)),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      ),
                );
              }),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms);
  }
}

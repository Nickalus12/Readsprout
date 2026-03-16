import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../data/dolch_words.dart';
import 'zone_background.dart';

/// Full-screen celebration overlay when a player unlocks a new zone.
///
/// Sequence:
/// 1. Screen dims with zone-themed gradient
/// 2. Confetti burst with zone colors
/// 3. Mastered zone icon scales up with glow
/// 4. Story text: "You've mastered [old zone]!"
/// 5. New zone icon reveals with sparkle
/// 6. "Welcome to {new zone}, {name}!" text
/// 7. Tap to dismiss
///
/// Use [ZoneUnlockOverlay.show] to trigger from anywhere.
class ZoneUnlockOverlay extends StatefulWidget {
  final int masteredZoneIndex;
  final int newZoneIndex;
  final String playerName;
  final bool isAllComplete;
  final VoidCallback? onComplete;

  const ZoneUnlockOverlay({
    super.key,
    required this.masteredZoneIndex,
    required this.newZoneIndex,
    this.playerName = '',
    this.isAllComplete = false,
    this.onComplete,
  });

  /// Show the zone unlock celebration as a dialog overlay.
  static Future<void> show(
    BuildContext context, {
    required int masteredZoneIndex,
    required int newZoneIndex,
    bool isAllComplete = false,
    String playerName = '',
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, _, __) {
        return ZoneUnlockOverlay(
          masteredZoneIndex: masteredZoneIndex,
          newZoneIndex: newZoneIndex,
          playerName: playerName,
          isAllComplete: isAllComplete,
          onComplete: () => Navigator.of(context).pop(),
        );
      },
      transitionDuration: Duration.zero,
    );
  }

  @override
  State<ZoneUnlockOverlay> createState() => _ZoneUnlockOverlayState();
}

class _ZoneUnlockOverlayState extends State<ZoneUnlockOverlay>
    with TickerProviderStateMixin {
  late final ConfettiController _confettiController;
  late final AnimationController _glowController;
  bool _canDismiss = false;

  Zone get _masteredZone => DolchWords.zones[widget.masteredZoneIndex];
  Zone get _newZone => DolchWords.zones[widget.newZoneIndex];

  List<Color> get _masteredZoneColors =>
      ZoneColors.particles[widget.masteredZoneIndex.clamp(0, 4)];
  List<Color> get _newZoneColors =>
      ZoneColors.particles[widget.newZoneIndex.clamp(0, 4)];

  Color get _masteredAccent => _masteredZoneColors.first;
  Color get _newAccent => _newZoneColors.first;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Fire confetti after a short delay
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _confettiController.play();
    });

    // Allow dismissal after the full animation plays
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _canDismiss = true);
    });
  }

  @override
  void dispose() {
    _confettiController.stop();
    _confettiController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!_canDismiss) return;
    widget.onComplete?.call();
  }

  Color _lerpThroughColors(double t, List<Color> colors) {
    if (colors.length < 2) return colors.first;
    final segmentCount = colors.length - 1;
    final scaledT = t * segmentCount;
    final index = scaledT.floor().clamp(0, segmentCount - 1);
    final localT = scaledT - index;
    return Color.lerp(colors[index], colors[index + 1], localT)!;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    final nameText = widget.playerName.isNotEmpty
        ? ', ${widget.playerName}'
        : '';

    return GestureDetector(
      onTap: _dismiss,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // ── Dimmed background with zone gradient ──
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0A1A).withValues(alpha: 0.95),
                    _masteredAccent.withValues(alpha: 0.15),
                    _newAccent.withValues(alpha: 0.1),
                    const Color(0xFF0A0A1A).withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.35, 0.65, 1.0],
                ),
              ),
            ),

            // ── Confetti (from top center) ──
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 40,
                maxBlastForce: 30,
                minBlastForce: 10,
                emissionFrequency: 0.06,
                gravity: 0.15,
                colors: [
                  ..._masteredZoneColors,
                  ..._newZoneColors,
                  AppColors.starGold,
                  Colors.white,
                ],
              ),
            ),

            // ── Center content ──
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Mastered zone icon with glow ──
                      AnimatedBuilder(
                        animation: _glowController,
                        builder: (context, child) {
                          final glowColor = _lerpThroughColors(
                            _glowController.value,
                            [_masteredAccent, AppColors.starGold, _masteredAccent],
                          );
                          return Container(
                            width: 80 * sf,
                            height: 80 * sf,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _masteredAccent.withValues(alpha: 0.15),
                              border: Border.all(
                                color: glowColor.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.2),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: child,
                          );
                        },
                        child: Text(
                          _masteredZone.icon,
                          style: TextStyle(fontSize: 40 * sf),
                        ),
                      )
                          .animate()
                          .scaleXY(
                            begin: 0.0,
                            end: 1.0,
                            duration: 800.ms,
                            curve: Curves.elasticOut,
                          )
                          .fadeIn(duration: 300.ms),

                      SizedBox(height: 20 * sf),

                      // ── "You've mastered [zone]!" text ──
                      Text(
                        "You've mastered",
                        style: AppFonts.nunito(
                          fontSize: 16 * sf,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 400.ms)
                          .slideY(
                            begin: 0.3,
                            end: 0,
                            delay: 400.ms,
                            duration: 400.ms,
                            curve: Curves.easeOut,
                          ),

                      SizedBox(height: 4 * sf),

                      Text(
                        '${_masteredZone.name}!',
                        style: AppFonts.fredoka(
                          fontSize: 28 * sf,
                          fontWeight: FontWeight.w700,
                          color: _masteredAccent,
                          shadows: [
                            Shadow(
                              color: _masteredAccent.withValues(alpha: 0.6),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 600.ms, duration: 400.ms)
                          .scaleXY(
                            begin: 0.5,
                            end: 1.0,
                            delay: 600.ms,
                            duration: 500.ms,
                            curve: Curves.elasticOut,
                          ),

                      SizedBox(height: 32 * sf),

                      // ── Divider sparkle ──
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSparkle(sf, 0),
                          SizedBox(width: 12 * sf),
                          _buildSparkle(sf, 1),
                          SizedBox(width: 12 * sf),
                          _buildSparkle(sf, 2),
                        ],
                      ),

                      SizedBox(height: 32 * sf),

                      // ── New zone icon reveal (or crown for all complete) ──
                      AnimatedBuilder(
                        animation: _glowController,
                        builder: (context, child) {
                          final accent = widget.isAllComplete
                              ? AppColors.starGold
                              : _newAccent;
                          final glowColor = _lerpThroughColors(
                            _glowController.value,
                            [accent, AppColors.electricBlue, accent],
                          );
                          return Container(
                            width: 96 * sf,
                            height: 96 * sf,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.12),
                              border: Border.all(
                                color: glowColor.withValues(alpha: 0.6),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.2),
                                  blurRadius: 80,
                                  spreadRadius: 15,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: child,
                          );
                        },
                        child: Text(
                          widget.isAllComplete ? '\u{1F3C6}' : _newZone.icon,
                          style: TextStyle(fontSize: 48 * sf),
                        ),
                      )
                          .animate()
                          .scaleXY(
                            begin: 0.0,
                            end: 1.0,
                            delay: 1200.ms,
                            duration: 800.ms,
                            curve: Curves.elasticOut,
                          )
                          .fadeIn(delay: 1200.ms, duration: 300.ms)
                          .shimmer(
                            delay: 2000.ms,
                            duration: 1500.ms,
                            color: _newAccent.withValues(alpha: 0.4),
                          ),

                      SizedBox(height: 16 * sf),

                      // ── "Welcome to [new zone]!" or "All zones complete!" ──
                      Text(
                        widget.isAllComplete
                            ? 'Reading Champion$nameText!'
                            : '${_newZone.name} awaits$nameText!',
                        textAlign: TextAlign.center,
                        style: AppFonts.fredoka(
                          fontSize: 24 * sf,
                          fontWeight: FontWeight.w700,
                          color: widget.isAllComplete
                              ? AppColors.starGold
                              : _newAccent,
                          shadows: [
                            Shadow(
                              color: (widget.isAllComplete
                                      ? AppColors.starGold
                                      : _newAccent)
                                  .withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 1600.ms, duration: 500.ms)
                          .slideY(
                            begin: 0.3,
                            end: 0,
                            delay: 1600.ms,
                            duration: 500.ms,
                            curve: Curves.easeOut,
                          ),

                      SizedBox(height: 40 * sf),

                      // ── Tap to continue hint with hand pointer ──
                      if (_canDismiss)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 32 * sf,
                              color: Colors.white.withValues(alpha: 0.5),
                            )
                                .animate(
                                  onPlay: (c) => c.repeat(reverse: true),
                                )
                                .scaleXY(
                                  begin: 0.9,
                                  end: 1.1,
                                  duration: 1000.ms,
                                  curve: Curves.easeInOut,
                                )
                                .fade(
                                  begin: 0.3,
                                  end: 0.8,
                                  duration: 1000.ms,
                                ),
                            SizedBox(height: 4 * sf),
                            Text(
                              'Tap to continue',
                              style: AppFonts.nunito(
                                fontSize: 14 * sf,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            )
                                .animate(
                                  onPlay: (c) => c.repeat(reverse: true),
                                )
                                .fade(
                                  begin: 0.3,
                                  end: 1.0,
                                  duration: 1200.ms,
                                ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSparkle(double sf, int index) {
    return Icon(
      Icons.auto_awesome,
      size: 16 * sf,
      color: AppColors.starGold,
    )
        .animate()
        .scaleXY(
          begin: 0.0,
          end: 1.0,
          delay: Duration(milliseconds: 1000 + index * 100),
          duration: 500.ms,
          curve: Curves.elasticOut,
        )
        .fadeIn(
          delay: Duration(milliseconds: 1000 + index * 100),
          duration: 200.ms,
        );
  }
}

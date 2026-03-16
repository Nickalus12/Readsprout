import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/audio_service.dart';
import '../widgets/floating_hearts_bg.dart';

class AlphabetScreen extends StatelessWidget {
  final AudioService audioService;

  const AlphabetScreen({
    super.key,
    required this.audioService,
  });

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // Rainbow palette cycling through level gradients
  static const _cardColors = [
    Color(0xFFFF6B6B), // Red
    Color(0xFFFF8E53), // Orange
    Color(0xFFFFBF69), // Honey
    Color(0xFFFFD93D), // Yellow
    Color(0xFF6BCB77), // Green
    Color(0xFF4ECDC4), // Teal
    Color(0xFF45B7D1), // Cyan
    Color(0xFF6BB8F0), // Sky
    Color(0xFF7B68EE), // Blue-violet
    Color(0xFFB794F6), // Lavender
    Color(0xFFD946EF), // Magenta
    Color(0xFFFF69B4), // Pink
    Color(0xFFFF6B6B), // Red (wrap)
  ];

  Color _colorForIndex(int index) {
    final t = index / 26.0 * (_cardColors.length - 1);
    final i = t.floor();
    final f = t - i;
    return Color.lerp(_cardColors[i], _cardColors[i + 1], f)!;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

    // Calculate card width: 4 columns with padding & spacing
    final gridPadding = 16.0 * sf;
    final gridSpacing = 10.0 * sf;
    final cardW = ((screenW - gridPadding * 2 - gridSpacing * 3) / 4)
        .clamp(60.0, 100.0);
    final cardH = cardW * 1.15; // keep aspect ratio

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  AppColors.backgroundEnd,
                ],
              ),
            ),
          ),

          // Floating hearts background
          const Positioned.fill(
            child: ExcludeSemantics(
              child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
            ),
          ),

          // Foreground content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(8 * sf, 8 * sf, 16 * sf, 0),
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Go back',
                        hint: 'Return to home screen',
                        button: true,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.primaryText,
                            size: 28 * sf,
                          ),
                        ),
                      ),
                      SizedBox(width: 4 * sf),
                      Text(
                        'Alphabet',
                        style: AppFonts.fredoka(
                          fontSize: 28 * sf,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8 * sf),
                      GestureDetector(
                        onTap: () => audioService.playWord('alphabet'),
                        child: Icon(
                          Icons.volume_up_rounded,
                          color: AppColors.electricBlue.withValues(alpha: 0.8),
                          size: 26 * sf,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 8 * sf),

                // Letter grid
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        gridPadding, 0, gridPadding, 24 * sf),
                    child: Center(
                      child: Wrap(
                        spacing: gridSpacing,
                        runSpacing: gridSpacing,
                        alignment: WrapAlignment.center,
                        children: [
                          for (int i = 0; i < _letters.length; i++)
                            _LetterCard(
                              letter: _letters[i],
                              color: _colorForIndex(i),
                              index: i,
                              audioService: audioService,
                              cardWidth: cardW,
                              cardHeight: cardH,
                              scaleFactor: sf,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual letter card widget ──────────────────────────────────────

class _LetterCard extends StatefulWidget {
  final String letter;
  final Color color;
  final int index;
  final AudioService audioService;
  final double cardWidth;
  final double cardHeight;
  final double scaleFactor;

  const _LetterCard({
    required this.letter,
    required this.color,
    required this.index,
    required this.audioService,
    required this.cardWidth,
    required this.cardHeight,
    required this.scaleFactor,
  });

  @override
  State<_LetterCard> createState() => _LetterCardState();
}

class _LetterCardState extends State<_LetterCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _onTap() {
    widget.audioService.playLetter(widget.letter.toLowerCase());
    _glowController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Staggered fade-in on load
    final delay = (widget.index * 50).ms;
    final sf = widget.scaleFactor;

    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final t = _glowController.value;
          final glow = sin(t * pi);
          final bounce = 1.0 + glow * 0.1;

          return Transform.scale(
            scale: bounce,
            child: RepaintBoundary(
              child: Container(
                width: widget.cardWidth,
                height: widget.cardHeight,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16 * sf),
                  border: Border.all(
                    color: glow > 0.01
                        ? AppColors.electricBlue.withValues(alpha: 0.4 + glow * 0.4)
                        : widget.color.withValues(alpha: 0.35),
                    width: 1.5 * sf,
                  ),
                  boxShadow: [
                    if (glow > 0.01)
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: glow * 0.35),
                        blurRadius: 16 * glow * sf,
                        spreadRadius: 2 * glow * sf,
                      )
                    else
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.1),
                        blurRadius: 8 * sf,
                        spreadRadius: 1 * sf,
                      ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Uppercase letter
                    Text(
                      widget.letter,
                      style: AppFonts.fredoka(
                        fontSize: 36 * sf,
                        fontWeight: FontWeight.w700,
                        color: glow > 0.01
                            ? Color.lerp(Colors.white, AppColors.electricBlue, glow * 0.4)
                            : Colors.white,
                        height: 1.1,
                        shadows: glow > 0.01
                            ? [
                                Shadow(
                                  color: AppColors.electricBlue.withValues(alpha: glow * 0.8),
                                  blurRadius: 20 * glow * sf,
                                ),
                                Shadow(
                                  color: AppColors.violet.withValues(alpha: glow * 0.4),
                                  blurRadius: 32 * glow * sf,
                                ),
                              ]
                            : [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                    ),
                    // Lowercase letter
                    Text(
                      widget.letter.toLowerCase(),
                      style: AppFonts.fredoka(
                        fontSize: 24 * sf,
                        fontWeight: FontWeight.w400,
                        color: glow > 0.01
                            ? Color.lerp(
                                widget.color.withValues(alpha: 0.8),
                                AppColors.electricBlue,
                                glow * 0.5,
                              )
                            : widget.color.withValues(alpha: 0.8),
                        height: 1.0,
                        shadows: glow > 0.01
                            ? [
                                Shadow(
                                  color: AppColors.electricBlue.withValues(alpha: glow * 0.5),
                                  blurRadius: 12 * glow * sf,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    )
        .animate()
        .fadeIn(delay: delay, duration: 400.ms)
        .scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1.0, 1.0),
          delay: delay,
          duration: 400.ms,
          curve: Curves.easeOutBack,
        );
  }
}

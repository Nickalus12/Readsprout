import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
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
            child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
          ),

          // Foreground content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primaryText,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Alphabet',
                        style: GoogleFonts.fredoka(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => audioService.playWord('alphabet'),
                        child: Icon(
                          Icons.volume_up_rounded,
                          color: AppColors.electricBlue.withValues(alpha: 0.8),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Letter grid
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Center(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          for (int i = 0; i < _letters.length; i++)
                            _LetterCard(
                              letter: _letters[i],
                              color: _colorForIndex(i),
                              index: i,
                              audioService: audioService,
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

  const _LetterCard({
    required this.letter,
    required this.color,
    required this.index,
    required this.audioService,
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
                width: 80,
                height: 92,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: glow > 0.01
                        ? AppColors.electricBlue.withValues(alpha: 0.4 + glow * 0.4)
                        : widget.color.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (glow > 0.01)
                      BoxShadow(
                        color: AppColors.electricBlue.withValues(alpha: glow * 0.35),
                        blurRadius: 16 * glow,
                        spreadRadius: 2 * glow,
                      )
                    else
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Uppercase letter
                    Text(
                      widget.letter,
                      style: GoogleFonts.fredoka(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        color: glow > 0.01
                            ? Color.lerp(Colors.white, AppColors.electricBlue, glow * 0.4)
                            : Colors.white,
                        height: 1.1,
                        shadows: glow > 0.01
                            ? [
                                Shadow(
                                  color: AppColors.electricBlue.withValues(alpha: glow * 0.8),
                                  blurRadius: 20 * glow,
                                ),
                                Shadow(
                                  color: AppColors.violet.withValues(alpha: glow * 0.4),
                                  blurRadius: 32 * glow,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    // Lowercase letter
                    Text(
                      widget.letter.toLowerCase(),
                      style: GoogleFonts.fredoka(
                        fontSize: 22,
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
                                  blurRadius: 12 * glow,
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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/progress_service.dart';
import '../services/audio_service.dart';
import '../services/high_score_service.dart';
import '../services/profile_service.dart';
import '../services/stats_service.dart';
import 'mini_games/unicorn_flight_game.dart';
import 'mini_games/lightning_speller_game.dart';
import 'mini_games/word_bubbles_game.dart';
import 'mini_games/memory_match_game.dart';
import 'mini_games/falling_letters_game.dart';
import 'mini_games/cat_letter_toss_game.dart';
import 'mini_games/letter_drop_game.dart';
import 'mini_games/rhyme_time_game.dart';
import 'mini_games/star_catcher_game.dart';
import 'mini_games/paint_splash_game.dart';

class MiniGamesScreen extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final HighScoreService highScoreService;
  final String playerName;
  final ProfileService? profileService;
  final StatsService? statsService;

  const MiniGamesScreen({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.highScoreService,
    required this.playerName,
    this.profileService,
    this.statsService,
  });

  @override
  State<MiniGamesScreen> createState() => _MiniGamesScreenState();
}

class _MiniGamesScreenState extends State<MiniGamesScreen> {
  static const _hintsPrefKey = 'mini_game_hints_enabled';
  bool _hintsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadHintsPref();
  }

  Future<void> _loadHintsPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hintsEnabled = prefs.getBool(_hintsPrefKey) ?? true;
    });
  }

  Future<void> _toggleHints() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hintsEnabled = !_hintsEnabled;
    });
    await prefs.setBool(_hintsPrefKey, _hintsEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.backgroundEnd],
              ),
            ),
          ),

          // Floating particles
          const Positioned.fill(child: _MiniGameParticles()),

          // Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _buildGameBtn(
                          context, 'Unicorn Flight',
                          const _UnicornIconPainter(), AppColors.magenta, 0,
                          UnicornFlightGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Lightning Speller',
                          const _StormCloudPainter(), AppColors.electricBlue, 1,
                          LightningSpellerGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Word Bubbles',
                          const _BubblesIconPainter(), AppColors.cyan, 2,
                          WordBubblesGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Memory Match',
                          const _CardsIconPainter(), AppColors.violet, 3,
                          MemoryMatchGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Falling Letters',
                          const _FallingIconPainter(), AppColors.starGold, 4,
                          FallingLettersGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Cat Toss',
                          const _CatIconPainter(), AppColors.magenta, 5,
                          CatLetterTossGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Letter Drop',
                          const _DropIconPainter(), AppColors.emerald, 6,
                          LetterDropGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Rhyme Time',
                          const _RhymeIconPainter(), AppColors.magenta, 7,
                          RhymeTimeGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Star Catcher',
                          const _StarCatcherIconPainter(), AppColors.violet, 8,
                          StarCatcherGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                        _buildGameBtn(
                          context, 'Paint Splash',
                          const _PaintSplashIconPainter(), AppColors.magenta, 9,
                          PaintSplashGame(
                            progressService: widget.progressService,
                            audioService: widget.audioService,
                            playerName: widget.playerName,
                            profileService: widget.profileService,
                            hintsEnabled: _hintsEnabled,
                          ),
                        ),
                      ],
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: 28,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.audioService.playWord('mini_games'),
              child: Text(
                'Mini Games',
                textAlign: TextAlign.center,
                style: AppFonts.fredoka(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ),
          Tooltip(
            message: _hintsEnabled ? 'Hints ON' : 'Hints OFF',
            child: IconButton(
              onPressed: _toggleHints,
              icon: Icon(
                _hintsEnabled
                    ? Icons.lightbulb_rounded
                    : Icons.lightbulb_outline_rounded,
                color: _hintsEnabled
                    ? AppColors.starGold
                    : AppColors.secondaryText,
              ),
              iconSize: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameBtn(BuildContext context, String label,
      CustomPainter painter, Color glow, int index, Widget game) {
    return _GameButton(
      label: label,
      painter: painter,
      glowColor: glow,
      onTap: () => Navigator.push(context, _smoothRoute(game)),
    )
        .animate()
        .fadeIn(delay: (index * 80).ms, duration: 400.ms)
        .scale(
          begin: const Offset(0.8, 0.8),
          curve: Curves.easeOutBack,
          delay: (index * 80).ms,
          duration: 500.ms,
        );
  }

  PageRouteBuilder _smoothRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity:
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}

// ── Compact floating game button ──────────────────────────────────────────

class _GameButton extends StatefulWidget {
  final String label;
  final CustomPainter painter;
  final Color glowColor;
  final VoidCallback onTap;

  const _GameButton({
    required this.label,
    required this.painter,
    required this.glowColor,
    required this.onTap,
  });

  @override
  State<_GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<_GameButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovering = true),
      onTapUp: (_) => setState(() => _hovering = false),
      onTapCancel: () => setState(() => _hovering = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
            _hovering ? 1.08 : 1.0, _hovering ? 1.08 : 1.0, 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon circle
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                    color: widget.glowColor.withValues(alpha: _hovering ? 0.8 : 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.glowColor
                          .withValues(alpha: _hovering ? 0.4 : 0.15),
                      blurRadius: _hovering ? 24 : 12,
                      spreadRadius: _hovering ? 4 : 1,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: widget.painter,
                  size: const Size(68, 68),
                ),
              ),
              const SizedBox(height: 6),
              // Label
              Text(
                widget.label,
                style: AppFonts.fredoka(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Unicorn icon painter (compact, fits 88x88 circle) ─────────────────────

class _UnicornIconPainter extends CustomPainter {
  const _UnicornIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Body
    final bodyPaint = Paint()
      ..color = const Color(0xFFF0E6FF)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 2, cy + 6), width: 36, height: 20),
      bodyPaint,
    );

    // Head
    final headPaint = Paint()
      ..color = const Color(0xFFF5F0FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 14, cy - 4), 10, headPaint);

    // Horn (golden)
    final hornPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx + 18, cy - 12),
      Offset(cx + 22, cy - 26),
      hornPaint,
    );

    // Horn glow dot
    canvas.drawCircle(
      Offset(cx + 22, cy - 26),
      2,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Rainbow mane
    final maneColors = [
      const Color(0xFFFF4757),
      const Color(0xFFFF8C42),
      const Color(0xFFFFD700),
      const Color(0xFF00E68A),
      const Color(0xFF00D4FF),
      const Color(0xFF8B5CF6),
    ];
    for (int i = 0; i < maneColors.length; i++) {
      final mp = Paint()
        ..color = maneColors[i].withValues(alpha: 0.8)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final yOff = cy - 10.0 + i * 3.5;
      final path = Path()
        ..moveTo(cx + 8, yOff)
        ..quadraticBezierTo(cx - 4, yOff - 4 + i * 1.5, cx - 10, yOff + 2);
      canvas.drawPath(path, mp);
    }

    // Legs
    final legPaint = Paint()
      ..color = const Color(0xFFE0D4F5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 10, cy + 14), Offset(cx - 12, cy + 26), legPaint);
    canvas.drawLine(Offset(cx - 2, cy + 15), Offset(cx - 2, cy + 27), legPaint);
    canvas.drawLine(Offset(cx + 6, cy + 15), Offset(cx + 6, cy + 27), legPaint);
    canvas.drawLine(Offset(cx + 12, cy + 14), Offset(cx + 14, cy + 26), legPaint);

    // Wing
    final wingPaint = Paint()
      ..color = const Color(0xFFD0BFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    final wingPath = Path()
      ..moveTo(cx - 2, cy)
      ..quadraticBezierTo(cx - 14, cy - 20, cx + 4, cy - 16)
      ..quadraticBezierTo(cx + 6, cy - 6, cx - 2, cy);
    canvas.drawPath(wingPath, wingPaint);

    // Eye
    canvas.drawCircle(
      Offset(cx + 18, cy - 5),
      1.5,
      Paint()..color = const Color(0xFF4A2080),
    );

    // Sparkles
    _drawSparkle(canvas, Offset(cx + 26, cy - 22), 3, const Color(0xFFFFD700));
    _drawSparkle(canvas, Offset(cx - 18, cy - 14), 2, AppColors.electricBlue);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Storm cloud icon painter (compact, fits 88x88 circle) ─────────────────

class _StormCloudPainter extends CustomPainter {
  const _StormCloudPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 6;

    // Cloud body
    final cloudPaint = Paint()
      ..color = const Color(0xFF3A3555)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 10, cy), 12, cloudPaint);
    canvas.drawCircle(Offset(cx + 6, cy - 3), 15, cloudPaint);
    canvas.drawCircle(Offset(cx + 18, cy + 1), 10, cloudPaint);
    canvas.drawCircle(Offset(cx - 2, cy + 4), 11, cloudPaint);

    // Cloud highlight
    final hlPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 4, cy - 6), 9, hlPaint);

    // Main lightning bolt
    final boltPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final bolt = Path()
      ..moveTo(cx + 2, cy + 10)
      ..lineTo(cx - 4, cy + 24)
      ..lineTo(cx + 2, cy + 22)
      ..lineTo(cx - 2, cy + 34);
    canvas.drawPath(bolt, boltPaint);

    // Bolt glow
    canvas.drawPath(
      bolt,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.3)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Small secondary bolt
    final bolt2 = Path()
      ..moveTo(cx + 14, cy + 12)
      ..lineTo(cx + 11, cy + 22)
      ..lineTo(cx + 14, cy + 20)
      ..lineTo(cx + 12, cy + 28);
    canvas.drawPath(
      bolt2,
      Paint()
        ..color = AppColors.electricBlue.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Rain dots
    final rainPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final rx = cx - 14.0 + i * 10;
      final ry = cy + 14.0 + (i % 3) * 5;
      canvas.drawLine(Offset(rx, ry), Offset(rx - 0.5, ry + 4), rainPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Bubbles icon painter (compact, fits 88x88 circle) ────────────────────

class _BubblesIconPainter extends CustomPainter {
  const _BubblesIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Main bubble
    final mainPaint = Paint()
      ..color = const Color(0xFF00D4FF).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy - 2), 18, mainPaint);
    // Highlight
    canvas.drawCircle(
      Offset(cx - 5, cy - 10),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    // Border
    canvas.drawCircle(
      Offset(cx, cy - 2),
      18,
      Paint()
        ..color = const Color(0xFF00D4FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Small bubble 1
    canvas.drawCircle(Offset(cx - 18, cy + 12), 8, mainPaint);
    canvas.drawCircle(
      Offset(cx - 20, cy + 9),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      Offset(cx - 18, cy + 12),
      8,
      Paint()
        ..color = const Color(0xFFFF69B4).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Small bubble 2
    canvas.drawCircle(
      Offset(cx + 16, cy + 10),
      10,
      Paint()..color = const Color(0xFF90EE90).withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(cx + 13, cy + 6),
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    // Word text in main bubble
    final tp = TextPainter(
      text: TextSpan(
        text: 'abc',
        style: AppFonts.fredoka(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Cards icon painter (compact, fits 88x88 circle) ──────────────────────

class _CardsIconPainter extends CustomPainter {
  const _CardsIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Back card (rotated slightly)
    canvas.save();
    canvas.translate(cx + 4, cy);
    canvas.rotate(0.15);
    final backCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-14, -18, 28, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      backCard,
      Paint()..color = const Color(0xFF2D1B69),
    );
    canvas.drawRRect(
      backCard,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Question mark
    final tp1 = TextPainter(
      text: TextSpan(
        text: '?',
        style: AppFonts.fredoka(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.violet.withValues(alpha: 0.3),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(-tp1.width / 2, -tp1.height / 2));
    canvas.restore();

    // Front card (face up)
    canvas.save();
    canvas.translate(cx - 6, cy + 2);
    canvas.rotate(-0.1);
    final frontCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-14, -18, 28, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      frontCard,
      Paint()..color = const Color(0xFFF8F8FF),
    );
    canvas.drawRRect(
      frontCard,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Star on front
    canvas.drawCircle(
      Offset.zero,
      3,
      Paint()..color = AppColors.starGold,
    );
    // Word
    final tp2 = TextPainter(
      text: TextSpan(
        text: 'the',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2A2A4A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(-tp2.width / 2, 6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Falling letters icon painter (compact, fits 88x88 circle) ────────────

class _FallingIconPainter extends CustomPainter {
  const _FallingIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Falling letter tiles
    final letters = ['A', 'B', 'C'];
    final offsets = [
      Offset(cx - 16, cy - 14),
      Offset(cx + 2, cy - 4),
      Offset(cx + 14, cy + 8),
    ];
    final rotations = [-0.15, 0.08, -0.1];
    final alphas = [0.9, 1.0, 0.7];

    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(offsets[i].dx, offsets[i].dy);
      canvas.rotate(rotations[i]);

      // Tile background
      final tileRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -12, 20, 24),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        tileRect,
        Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: alphas[i]),
      );
      canvas.drawRRect(
        tileRect,
        Paint()
          ..color = AppColors.electricBlue.withValues(alpha: 0.5 * alphas[i])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Letter text
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: AppFonts.fredoka(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.electricBlue.withValues(alpha: alphas[i]),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Sparkle trail from top letter
    _drawSparkle(canvas, Offset(cx - 16, cy - 26), 2, AppColors.starGold);
    _drawSparkle(canvas, Offset(cx + 6, cy - 16), 1.5, AppColors.electricBlue);

    // Slots at bottom
    final slotPaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final sx = cx - 16.0 + i * 16;
      canvas.drawLine(Offset(sx, cy + 22), Offset(sx + 10, cy + 22), slotPaint);
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Cat icon painter (compact, fits 88x88 circle) ────────────────────────

class _CatIconPainter extends CustomPainter {
  const _CatIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow aura
    canvas.drawCircle(
      Offset(cx, cy),
      28,
      Paint()
        ..color = AppColors.magenta.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Body
    final bodyPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 6), width: 32, height: 24),
      bodyPaint,
    );

    // Head
    canvas.drawCircle(Offset(cx, cy - 8), 14, bodyPaint);

    // Ears
    final earPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..style = PaintingStyle.fill;
    final leftEar = Path()
      ..moveTo(cx - 12, cy - 14)
      ..lineTo(cx - 8, cy - 26)
      ..lineTo(cx - 2, cy - 14)
      ..close();
    final rightEar = Path()
      ..moveTo(cx + 2, cy - 14)
      ..lineTo(cx + 8, cy - 26)
      ..lineTo(cx + 12, cy - 14)
      ..close();
    canvas.drawPath(leftEar, earPaint);
    canvas.drawPath(rightEar, earPaint);

    // Inner ears
    final innerEarPaint = Paint()
      ..color = const Color(0xFFFFB8D9)
      ..style = PaintingStyle.fill;
    final leftInner = Path()
      ..moveTo(cx - 10, cy - 15)
      ..lineTo(cx - 8, cy - 22)
      ..lineTo(cx - 4, cy - 15)
      ..close();
    final rightInner = Path()
      ..moveTo(cx + 4, cy - 15)
      ..lineTo(cx + 8, cy - 22)
      ..lineTo(cx + 10, cy - 15)
      ..close();
    canvas.drawPath(leftInner, innerEarPaint);
    canvas.drawPath(rightInner, innerEarPaint);

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFF2A1040);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy - 8), width: 5, height: 6),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy - 8), width: 5, height: 6),
      eyePaint,
    );
    // Eye shine
    canvas.drawCircle(
      Offset(cx - 4, cy - 9),
      1.2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx + 6, cy - 9),
      1.2,
      Paint()..color = Colors.white,
    );

    // Nose
    canvas.drawCircle(
      Offset(cx, cy - 4),
      1.5,
      Paint()..color = const Color(0xFFFF6BA8),
    );

    // Whiskers
    final whiskerPaint = Paint()
      ..color = const Color(0xFFFFCDE0)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 4, cy - 3), Offset(cx - 18, cy - 6), whiskerPaint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 17, cy), whiskerPaint);
    canvas.drawLine(Offset(cx + 4, cy - 3), Offset(cx + 18, cy - 6), whiskerPaint);
    canvas.drawLine(Offset(cx + 4, cy - 2), Offset(cx + 17, cy), whiskerPaint);

    // Tail
    final tailPaint = Paint()
      ..color = const Color(0xFFFF8EC8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tail = Path()
      ..moveTo(cx + 14, cy + 10)
      ..quadraticBezierTo(cx + 24, cy + 4, cx + 20, cy - 4);
    canvas.drawPath(tail, tailPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Drop icon painter (compact, fits 88x88 circle) ───────────────────────

class _DropIconPainter extends CustomPainter {
  const _DropIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Letter bubble at top
    final bubblePaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy - 12), 12, bubblePaint);
    canvas.drawCircle(
      Offset(cx, cy - 12),
      12,
      Paint()
        ..color = AppColors.emerald.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Letter "A" in bubble
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: AppFonts.fredoka(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.emerald,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - 12 - tp.height / 2));

    // Downward arrow / motion lines
    final arrowPaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // Motion trails
    canvas.drawLine(Offset(cx - 6, cy + 2), Offset(cx - 6, cy + 8), arrowPaint);
    canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + 12), arrowPaint);
    canvas.drawLine(Offset(cx + 6, cy + 2), Offset(cx + 6, cy + 8), arrowPaint);

    // Slot shelf at bottom
    final shelfPaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 18, cy + 18), Offset(cx + 18, cy + 18), shelfPaint);
    // Slot dividers
    canvas.drawLine(Offset(cx - 6, cy + 14), Offset(cx - 6, cy + 18), shelfPaint);
    canvas.drawLine(Offset(cx + 6, cy + 14), Offset(cx + 6, cy + 18), shelfPaint);

    // Small bouncing letter
    final smallBubble = Paint()
      ..color = AppColors.starGold.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 16, cy - 2), 7, smallBubble);
    final tp2 = TextPainter(
      text: TextSpan(
        text: 'B',
        style: AppFonts.fredoka(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: AppColors.starGold.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx + 16 - tp2.width / 2, cy - 2 - tp2.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Rhyme icon painter (compact, fits 88x88 circle) ──────────────────────

class _RhymeIconPainter extends CustomPainter {
  const _RhymeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Two overlapping speech bubbles
    final bubble1 = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx - 8, cy - 6), width: 32, height: 24),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bubble1,
      Paint()..color = AppColors.magenta.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      bubble1,
      Paint()
        ..color = AppColors.magenta.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tail for bubble 1
    final tail1 = Path()
      ..moveTo(cx - 14, cy + 4)
      ..lineTo(cx - 20, cy + 14)
      ..lineTo(cx - 6, cy + 4);
    canvas.drawPath(
      tail1,
      Paint()..color = AppColors.magenta.withValues(alpha: 0.3),
    );

    final bubble2 = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + 8, cy + 2), width: 32, height: 24),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bubble2,
      Paint()..color = AppColors.violet.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      bubble2,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tail for bubble 2
    final tail2 = Path()
      ..moveTo(cx + 14, cy + 12)
      ..lineTo(cx + 20, cy + 22)
      ..lineTo(cx + 6, cy + 12);
    canvas.drawPath(
      tail2,
      Paint()..color = AppColors.violet.withValues(alpha: 0.3),
    );

    // Text in bubbles
    final tp1 = TextPainter(
      text: TextSpan(
        text: 'cat',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.magenta,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(cx - 8 - tp1.width / 2, cy - 6 - tp1.height / 2));

    final tp2 = TextPainter(
      text: TextSpan(
        text: 'hat',
        style: AppFonts.fredoka(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.violet,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx + 8 - tp2.width / 2, cy + 2 - tp2.height / 2));

    // Musical note sparkles
    _drawNote(canvas, Offset(cx - 16, cy - 18), AppColors.magenta);
    _drawNote(canvas, Offset(cx + 18, cy - 12), AppColors.violet);
  }

  void _drawNote(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Note stem
    canvas.drawLine(Offset(c.dx + 3, c.dy), Offset(c.dx + 3, c.dy - 8), p);
    // Note head
    canvas.drawCircle(Offset(c.dx + 1, c.dy + 1), 2.5,
        Paint()..color = color.withValues(alpha: 0.7));
    // Flag
    final flag = Path()
      ..moveTo(c.dx + 3, c.dy - 8)
      ..quadraticBezierTo(c.dx + 8, c.dy - 6, c.dx + 5, c.dy - 3);
    canvas.drawPath(flag, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Star Catcher icon painter (compact, fits 88x88 circle) ───────────────

class _StarCatcherIconPainter extends CustomPainter {
  const _StarCatcherIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dark sky background circle
    canvas.drawCircle(
      Offset(cx, cy),
      30,
      Paint()..color = const Color(0xFF0D0D2B).withValues(alpha: 0.4),
    );

    // Stars (5-pointed)
    _drawMiniStar(canvas, Offset(cx - 12, cy - 10), 8, AppColors.starGold);
    _drawMiniStar(canvas, Offset(cx + 10, cy - 6), 6, AppColors.electricBlue);
    _drawMiniStar(canvas, Offset(cx + 2, cy + 8), 7, AppColors.violet);
    _drawMiniStar(canvas, Offset(cx - 8, cy + 12), 5, const Color(0xFF00E68A));

    // Constellation lines
    final linePaint = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 12, cy - 10), Offset(cx + 10, cy - 6), linePaint);
    canvas.drawLine(Offset(cx + 10, cy - 6), Offset(cx + 2, cy + 8), linePaint);

    // Small letter on one star
    final tp = TextPainter(
      text: TextSpan(
        text: 'A',
        style: AppFonts.fredoka(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A0A00),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 12 - tp.width / 2, cy - 10 - tp.height / 2));

    // Tiny sparkles
    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 18, cy - 16), Offset(cx + 22, cy - 16), sparklePaint);
    canvas.drawLine(Offset(cx + 20, cy - 18), Offset(cx + 20, cy - 14), sparklePaint);
  }

  void _drawMiniStar(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * pi / 5) - pi / 2;
      final sr = i.isEven ? r : r * 0.45;
      final x = center.dx + cos(angle) * sr;
      final y = center.dy + sin(angle) * sr;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Paint Splash icon painter (compact, fits 88x88 circle) ───────────────

class _PaintSplashIconPainter extends CustomPainter {
  const _PaintSplashIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Canvas / easel frame
    final framePaint = Paint()
      ..color = const Color(0xFFDDCCBB).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 36),
        const Radius.circular(4),
      ),
      framePaint,
    );
    // Canvas fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 36),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFFFF8F0).withValues(alpha: 0.6),
    );

    // Paint splats
    canvas.drawCircle(Offset(cx - 8, cy - 4), 7,
        Paint()..color = const Color(0xFFFF4D6A).withValues(alpha: 0.7));
    canvas.drawCircle(Offset(cx + 6, cy + 2), 6,
        Paint()..color = const Color(0xFF4D9FFF).withValues(alpha: 0.7));
    canvas.drawCircle(Offset(cx - 2, cy + 6), 5,
        Paint()..color = const Color(0xFF4DFF88).withValues(alpha: 0.6));
    canvas.drawCircle(Offset(cx + 10, cy - 6), 4,
        Paint()..color = const Color(0xFFFFD74D).withValues(alpha: 0.7));

    // Paint brush
    final brushPaint = Paint()
      ..color = const Color(0xFF8B6914)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + 14, cy - 14), Offset(cx + 4, cy - 2), brushPaint);
    // Brush tip
    canvas.drawCircle(Offset(cx + 4, cy - 2), 2.5,
        Paint()..color = const Color(0xFFFF4D6A));

    // Letter in a splat
    final tp = TextPainter(
      text: TextSpan(
        text: 'B',
        style: AppFonts.fredoka(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 8 - tp.width / 2, cy - 4 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Floating particles ────────────────────────────────────────────────────

class _MiniGameParticles extends StatefulWidget {
  const _MiniGameParticles();

  @override
  State<_MiniGameParticles> createState() => _MiniGameParticlesState();
}

class _MiniGameParticlesState extends State<_MiniGameParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    final rng = Random(42);
    _particles = List.generate(10, (_) => _Particle(rng));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            time: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  final double x, y, speed, phase, size;
  final Color color;

  _Particle(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.2 + rng.nextDouble() * 0.5,
        phase = rng.nextDouble() * 2 * pi,
        size = 1.5 + rng.nextDouble() * 2.0,
        color = [
          AppColors.magenta,
          AppColors.violet,
          AppColors.electricBlue,
          AppColors.starGold,
        ][rng.nextInt(4)];
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;

  _ParticlePainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = time * p.speed + p.phase;
      final x = (p.x + sin(t * 2 * pi) * 0.03) * size.width;
      final y = (p.y + cos(t * 2 * pi * 0.7) * 0.02) * size.height;
      final alpha = (0.2 + sin(t * 2 * pi * 2) * 0.2).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

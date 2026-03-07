import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/floating_hearts_bg.dart';

/// First-launch screen where the parent enters their child's name.
///
/// The name is used for personalized encouragement phrases throughout
/// the app (e.g., "Great job, Emma!", "Welcome, Emma!").
class NameSetupScreen extends StatefulWidget {
  final void Function(String name) onNameSubmitted;
  final VoidCallback? onBack;
  final AudioService? audioService;

  const NameSetupScreen({
    super.key,
    required this.onNameSubmitted,
    this.onBack,
    this.audioService,
  });

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
    // Auto-focus the text field
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      widget.onNameSubmitted(name);
    }
  }

  void _playAppName() {
    widget.audioService?.playWord('reading_sprout');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        widget.onBack != null) {
      widget.onBack!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: Scaffold(
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.backgroundEnd],
              ),
            ),
          ),

          // ── Floating hearts physics layer ────────────────────
          const Positioned.fill(
            child: FloatingHeartsBackground(
              cloudZoneHeight: 0.18,
            ),
          ),

          // ── Foreground content ───────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.08),

                    // Logo (tappable)
                    GestureDetector(
                      onTap: () => _playAppName(),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 120,
                        height: 120,
                      ),
                    ).animate().scale(
                          begin: const Offset(0.5, 0.5),
                          end: const Offset(1.0, 1.0),
                          curve: Curves.elasticOut,
                          duration: 800.ms,
                        ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      'Reading Sprout',
                      style: GoogleFonts.fredoka(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                        shadows: [
                          Shadow(
                            color:
                                AppColors.electricBlue.withValues(alpha: 0.5),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

                    const SizedBox(height: 32),

                    // Prompt
                    Text(
                      "What's your name?",
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    const SizedBox(height: 8),

                    Text(
                      "We'll cheer you on by name!",
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        color:
                            AppColors.secondaryText.withValues(alpha: 0.7),
                      ),
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                    const SizedBox(height: 24),

                    // Name input field
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _hasText
                              ? AppColors.electricBlue
                                  .withValues(alpha: 0.5)
                              : AppColors.border,
                          width: _hasText ? 1.5 : 1,
                        ),
                        boxShadow: [
                          if (_hasText)
                            BoxShadow(
                              color: AppColors.electricBlue
                                  .withValues(alpha: 0.15),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.words,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.fredoka(
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryText,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter name',
                          hintStyle: GoogleFonts.fredoka(
                            fontSize: 28,
                            fontWeight: FontWeight.w400,
                            color: AppColors.secondaryText
                                .withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                    const SizedBox(height: 24),

                    // Let's Go button
                    AnimatedOpacity(
                      opacity: _hasText ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: _hasText ? _submit : null,
                        child: Container(
                          width: 200,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.electricBlue,
                                AppColors.violet,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              if (_hasText)
                                BoxShadow(
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "Let's Go!",
                              style: GoogleFonts.fredoka(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

                    // Back button (only when changing name, not first launch)
                    if (widget.onBack != null) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: widget.onBack,
                        child: Text(
                          'Back',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: AppColors.secondaryText
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
                    ],

                    SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

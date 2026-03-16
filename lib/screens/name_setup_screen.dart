import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../utils/name_validator.dart';
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
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText || _errorText != null) {
        setState(() {
          _hasText = hasText;
          _errorText = null;
        });
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
    if (name.isEmpty) return;
    final error = NameValidator.validate(name);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    setState(() => _errorText = null);
    widget.onNameSubmitted(NameValidator.formatName(name));
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
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);

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
            child: ExcludeSemantics(
              child: FloatingHeartsBackground(
                cloudZoneHeight: 0.18,
              ),
            ),
          ),

          // ── Foreground content ───────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 40 * sf),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.08),

                    // Logo (tappable)
                    GestureDetector(
                      onTap: () => _playAppName(),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 120 * sf,
                        height: 120 * sf,
                      ),
                    ).animate().scale(
                          begin: const Offset(0.5, 0.5),
                          end: const Offset(1.0, 1.0),
                          curve: Curves.elasticOut,
                          duration: 800.ms,
                        ),

                    SizedBox(height: 24 * sf),

                    // Title
                    Text(
                      'Reading Sprout',
                      style: AppFonts.fredoka(
                        fontSize: 40 * sf,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                        shadows: [
                          Shadow(
                            color:
                                AppColors.electricBlue.withValues(alpha: 0.5),
                            blurRadius: 20 * sf,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

                    SizedBox(height: 32 * sf),

                    // Prompt
                    Text(
                      "What's your name?",
                      style: AppFonts.nunito(
                        fontSize: 22 * sf,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    SizedBox(height: 8 * sf),

                    Text(
                      "We'll cheer you on by name!",
                      style: AppFonts.nunito(
                        fontSize: 17 * sf,
                        fontWeight: FontWeight.w500,
                        color:
                            AppColors.secondaryText.withValues(alpha: 0.7),
                      ),
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                    SizedBox(height: 24 * sf),

                    // Name input field
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16 * sf),
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
                              blurRadius: 12 * sf,
                            ),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.words,
                        textAlign: TextAlign.center,
                        style: AppFonts.fredoka(
                          fontSize: 28 * sf,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryText,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter name',
                          hintStyle: AppFonts.fredoka(
                            fontSize: 28 * sf,
                            fontWeight: FontWeight.w400,
                            color: AppColors.secondaryText
                                .withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 24 * sf,
                            vertical: 16 * sf,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                    // Validation error message
                    if (_errorText != null) ...[
                      SizedBox(height: 8 * sf),
                      Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: AppFonts.nunito(
                          fontSize: 14 * sf,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ],

                    SizedBox(height: 24 * sf),

                    // Let's Go button
                    Semantics(
                      label: "Let's Go",
                      hint: 'Start playing Reading Sprout',
                      button: true,
                      enabled: _hasText,
                      child: AnimatedOpacity(
                        opacity: _hasText ? 1.0 : 0.4,
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: _hasText ? _submit : null,
                        child: Container(
                          width: 200 * sf,
                          height: 56 * sf,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.electricBlue,
                                AppColors.violet,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28 * sf),
                            boxShadow: [
                              if (_hasText)
                                BoxShadow(
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.4),
                                  blurRadius: 16 * sf,
                                  offset: Offset(0, 4 * sf),
                                ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "Let's Go!",
                              style: AppFonts.fredoka(
                                fontSize: 24 * sf,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )).animate().fadeIn(delay: 700.ms, duration: 500.ms),

                    // Back button (only when changing name, not first launch)
                    if (widget.onBack != null) ...[
                      SizedBox(height: 12 * sf),
                      GestureDetector(
                        onTap: widget.onBack,
                        child: Text(
                          'Back',
                          style: AppFonts.nunito(
                            fontSize: 14 * sf,
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

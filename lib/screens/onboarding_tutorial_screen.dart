import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/audio_service.dart';

/// Animated onboarding tutorial for first-time users.
/// Shows 4 visual steps: hear word, tap letters, word complete, celebration.
/// Designed for a 4-year-old who cannot read — all guidance is visual/audio.
class OnboardingTutorialScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final AudioService? audioService;

  const OnboardingTutorialScreen({
    super.key,
    required this.onComplete,
    this.audioService,
  });

  @override
  State<OnboardingTutorialScreen> createState() =>
      _OnboardingTutorialScreenState();
}

class _OnboardingTutorialScreenState extends State<OnboardingTutorialScreen>
    with TickerProviderStateMixin {
  int _currentPage = 0;
  late final PageController _pageController;
  late final AnimationController _handController;
  late final AnimationController _glowController;

  static const _totalPages = 4;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _handController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _handController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  void _skip() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final sf = (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.2);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    label: 'Skip tutorial',
                    button: true,
                    child: GestureDetector(
                      onTap: _skip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Skip',
                          style: AppFonts.nunito(
                            fontSize: 14 * sf,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Tutorial pages
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) =>
                      setState(() => _currentPage = page),
                  children: [
                    _buildListenPage(sf),
                    _buildTapPage(sf),
                    _buildCompletePage(sf),
                    _buildCelebratePage(sf),
                  ],
                ),
              ),

              // Page dots + next button
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Page indicator dots
                    Row(
                      children: List.generate(_totalPages, (i) {
                        final isActive = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          width: isActive ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.electricBlue
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    // Next / Done button
                    Semantics(
                      label: _currentPage == _totalPages - 1
                          ? 'Start playing'
                          : 'Next step',
                      button: true,
                      child: GestureDetector(
                        onTap: _nextPage,
                        child: AnimatedBuilder(
                          animation: _glowController,
                          builder: (context, child) {
                            final glow = _glowController.value * 0.3;
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24 * sf, vertical: 12 * sf),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.electricBlue,
                                    AppColors.violet,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.electricBlue
                                        .withValues(alpha: 0.3 + glow),
                                    blurRadius: 12 + glow * 20,
                                    spreadRadius: glow * 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _currentPage == _totalPages - 1
                                        ? Icons.play_arrow_rounded
                                        : Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 24 * sf,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Page 1: Listen to the word ──────────────────────────────────

  Widget _buildListenPage(double sf) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * sf),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Speaker icon with pulsing glow
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final pulse = _glowController.value;
              return Container(
                width: 100 * sf,
                height: 100 * sf,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.electricBlue.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricBlue
                          .withValues(alpha: 0.1 + pulse * 0.2),
                      blurRadius: 20 + pulse * 20,
                      spreadRadius: pulse * 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  size: 48 * sf,
                  color: AppColors.electricBlue,
                ),
              );
            },
          ),
          SizedBox(height: 32 * sf),

          // Visual: sound waves emanating
          Text(
            'Listen!',
            style: AppFonts.fredoka(
              fontSize: 36 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ).animate().fadeIn(duration: 600.ms),

          SizedBox(height: 12 * sf),

          // Demo word
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: 24 * sf, vertical: 12 * sf),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.electricBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hearing_rounded,
                    size: 20 * sf, color: AppColors.electricBlue),
                SizedBox(width: 8 * sf),
                Text(
                  '"cat"',
                  style: AppFonts.fredoka(
                    fontSize: 28 * sf,
                    fontWeight: FontWeight.w500,
                    color: AppColors.electricBlue,
                  ),
                ),
              ],
            ),
          )
              .animate(delay: 400.ms)
              .fadeIn(duration: 500.ms)
              .scaleXY(begin: 0.8, end: 1.0, duration: 500.ms),
        ],
      ),
    );
  }

  // ── Page 2: Tap the letters ─────────────────────────────────────

  Widget _buildTapPage(double sf) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * sf),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Letter tiles with hand pointer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final letter in ['c', 'a', 't'])
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * sf),
                  child: _DemoLetterTile(
                    letter: letter,
                    isRevealed: letter == 'c',
                    isActive: letter == 'a',
                    sf: sf,
                  ),
                ),
            ],
          ).animate().fadeIn(duration: 500.ms),

          SizedBox(height: 16 * sf),

          // Animated hand pointing at the active tile
          AnimatedBuilder(
            animation: _handController,
            builder: (context, child) {
              final bounce = _handController.value * 8;
              return Transform.translate(
                offset: Offset(0, -bounce),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 48 * sf,
                  color: AppColors.starGold,
                ),
              );
            },
          ),

          SizedBox(height: 24 * sf),

          Text(
            'Tap!',
            style: AppFonts.fredoka(
              fontSize: 36 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ).animate().fadeIn(duration: 600.ms),

          SizedBox(height: 8 * sf),

          // Show keyboard hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in ['a', 's', 'd'])
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3 * sf),
                  child: Container(
                    width: 36 * sf,
                    height: 36 * sf,
                    decoration: BoxDecoration(
                      color: key == 'a'
                          ? AppColors.electricBlue.withValues(alpha: 0.2)
                          : AppColors.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: key == 'a'
                            ? AppColors.electricBlue.withValues(alpha: 0.5)
                            : AppColors.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        key.toUpperCase(),
                        style: AppFonts.fredoka(
                          fontSize: 16 * sf,
                          fontWeight: FontWeight.w500,
                          color: key == 'a'
                              ? AppColors.electricBlue
                              : AppColors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ).animate(delay: 300.ms).fadeIn(duration: 500.ms),
        ],
      ),
    );
  }

  // ── Page 3: Word complete ───────────────────────────────────────

  Widget _buildCompletePage(double sf) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * sf),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // All letters revealed
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final letter in ['c', 'a', 't'])
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * sf),
                  child: _DemoLetterTile(
                    letter: letter,
                    isRevealed: true,
                    isActive: false,
                    sf: sf,
                  ),
                ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scaleXY(begin: 0.9, end: 1.0, duration: 500.ms),

          SizedBox(height: 24 * sf),

          // Checkmark
          Container(
            width: 64 * sf,
            height: 64 * sf,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              size: 36 * sf,
              color: AppColors.success,
            ),
          ).animate(delay: 300.ms).fadeIn(duration: 400.ms).scaleXY(
                begin: 0.5,
                end: 1.0,
                duration: 400.ms,
                curve: Curves.elasticOut,
              ),

          SizedBox(height: 24 * sf),

          Text(
            'You did it!',
            style: AppFonts.fredoka(
              fontSize: 36 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ).animate(delay: 500.ms).fadeIn(duration: 600.ms),
        ],
      ),
    );
  }

  // ── Page 4: Celebration ─────────────────────────────────────────

  Widget _buildCelebratePage(double sf) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * sf),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Stars burst
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < 5; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * sf),
                  child: Icon(
                    Icons.star_rounded,
                    size: 36 * sf,
                    color: AppColors.starGold,
                  )
                      .animate(delay: Duration(milliseconds: 100 * i))
                      .fadeIn(duration: 300.ms)
                      .scaleXY(
                        begin: 0.3,
                        end: 1.0,
                        duration: 400.ms,
                        curve: Curves.elasticOut,
                      ),
                ),
            ],
          ),

          SizedBox(height: 32 * sf),

          Text(
            'Ready?',
            style: AppFonts.fredoka(
              fontSize: 40 * sf,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              shadows: [
                Shadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.5),
                  blurRadius: 20,
                ),
              ],
            ),
          ).animate(delay: 500.ms).fadeIn(duration: 600.ms),

          SizedBox(height: 12 * sf),

          Text(
            "Let's learn some words!",
            style: AppFonts.nunito(
              fontSize: 18 * sf,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ).animate(delay: 700.ms).fadeIn(duration: 500.ms),
        ],
      ),
    );
  }
}

// ── Demo letter tile for tutorial ───────────────────────────────────

class _DemoLetterTile extends StatelessWidget {
  final String letter;
  final bool isRevealed;
  final bool isActive;
  final double sf;

  const _DemoLetterTile({
    required this.letter,
    required this.isRevealed,
    required this.isActive,
    required this.sf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52 * sf,
      height: 62 * sf,
      decoration: BoxDecoration(
        color: isRevealed
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.electricBlue.withValues(alpha: 0.5)
              : isRevealed
                  ? AppColors.success.withValues(alpha: 0.4)
                  : AppColors.border.withValues(alpha: 0.4),
          width: isRevealed ? 2.0 : 1.5,
        ),
        boxShadow: [
          if (isRevealed)
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.2),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          if (isActive)
            BoxShadow(
              color: AppColors.electricBlue.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
        ],
      ),
      child: Center(
        child: Text(
          isRevealed ? letter.toUpperCase() : '?',
          style: AppFonts.fredoka(
            fontSize: 28 * sf,
            fontWeight: FontWeight.w600,
            color: isRevealed
                ? AppColors.success
                : AppColors.secondaryText.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

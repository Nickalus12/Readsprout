import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';
import '../services/player_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/floating_hearts_bg.dart';

/// "Who's Playing?" profile picker screen.
/// Large colorful cards, voice on tap, kid-friendly (no reading required).
class ProfilePickerScreen extends StatefulWidget {
  final PlayerSettingsService settingsService;
  final AudioService audioService;
  final void Function(String profileId) onProfileSelected;
  final void Function(String name) onNewProfile;

  const ProfilePickerScreen({
    super.key,
    required this.settingsService,
    required this.audioService,
    required this.onProfileSelected,
    required this.onNewProfile,
  });

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  bool _showingNameInput = false;
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final hasText = _nameController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });

    // Play "Who's playing?" voice
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.audioService.playWord('whos_playing');
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onProfileTap(PlayerEntry profile) {
    // Play the child's name, then sign them in after a short delay
    if (profile.name.isNotEmpty) {
      widget.audioService.playWord(profile.name.toLowerCase());
    }
    // Brief delay so the child hears their name before navigating
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.onProfileSelected(profile.id);
    });
  }

  void _showAddPlayer() {
    setState(() {
      _showingNameInput = true;
      _nameController.clear();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _submitNewName() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      widget.onNewProfile(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.settingsService.profiles;
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);
    final cardSize = (140 * sf).roundToDouble();

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.backgroundEnd],
              ),
            ),
          ),

          // Hearts
          const Positioned.fill(
            child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24 * sf),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        height: MediaQuery.of(context).size.height * 0.04),

                    // Logo
                    GestureDetector(
                      onTap: () =>
                          widget.audioService.playWord('reading_sprout'),
                      child: Builder(builder: (context) {
                        final logoSize = (screenW / 400 * 80).clamp(60.0, 100.0);
                        return Image.asset(
                          'assets/images/logo.png',
                          width: logoSize,
                          height: logoSize,
                        );
                      }),
                    ).animate().scale(
                          begin: const Offset(0.7, 0.7),
                          curve: Curves.elasticOut,
                          duration: 800.ms,
                        ),

                    SizedBox(height: 16 * sf),

                    // "Who's Playing?" — tappable to replay voice
                    GestureDetector(
                      onTap: () =>
                          widget.audioService.playWord('whos_playing'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up_rounded,
                              color: AppColors.electricBlue, size: 28 * sf),
                          SizedBox(width: 10 * sf),
                          Text(
                            "Who's Playing?",
                            style: AppFonts.fredoka(
                              fontSize: 26 * sf,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.5),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 600.ms),

                    SizedBox(height: 28 * sf),

                    // Profile cards
                    if (!_showingNameInput) ...[
                      Wrap(
                        spacing: 16 * sf,
                        runSpacing: 16 * sf,
                        alignment: WrapAlignment.center,
                        children: [
                          for (int i = 0; i < profiles.length; i++)
                            _ProfileCard(
                              profile: profiles[i],
                              audioService: widget.audioService,
                              onTap: () => _onProfileTap(profiles[i]),
                              index: i,
                              sf: sf,
                            ),
                        ],
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 500.ms),

                      SizedBox(height: 24 * sf),

                      // Add player button
                      GestureDetector(
                        onTap: _showAddPlayer,
                        child: Container(
                          width: cardSize,
                          height: cardSize,
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(24 * sf),
                            border: Border.all(
                              color: AppColors.border.withValues(alpha: 0.4),
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 52 * sf,
                                height: 52 * sf,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: AppColors.electricBlue
                                        .withValues(alpha: 0.4),
                                    width: 2,
                                  ),
                                ),
                                child: Icon(Icons.add_rounded,
                                    color: AppColors.electricBlue, size: 32 * sf),
                              ),
                              SizedBox(height: 8 * sf),
                              Text(
                                'Add Player',
                                style: AppFonts.fredoka(
                                  fontSize: 14 * sf,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 400.ms),
                    ],

                    // Name input (when adding new player)
                    if (_showingNameInput) ...[
                      _buildNameInput(sf),
                    ],

                    SizedBox(
                        height: MediaQuery.of(context).size.height * 0.06),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameInput(double sf) {
    return Column(
      children: [
        // Back arrow
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => setState(() => _showingNameInput = false),
            icon: Icon(Icons.arrow_back_rounded,
                color: AppColors.primaryText, size: 24 * sf),
          ),
        ),

        SizedBox(height: 8 * sf),

        Text(
          "What's your name?",
          style: AppFonts.fredoka(
            fontSize: 24 * sf,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
        ),

        SizedBox(height: 16 * sf),

        // Name field
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16 * sf),
            border: Border.all(
              color: _hasText
                  ? AppColors.electricBlue.withValues(alpha: 0.5)
                  : AppColors.border,
              width: _hasText ? 1.5 : 1,
            ),
            boxShadow: [
              if (_hasText)
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.15),
                  blurRadius: 12,
                ),
            ],
          ),
          child: TextField(
            controller: _nameController,
            focusNode: _nameFocus,
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
                color: AppColors.secondaryText.withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 24 * sf,
                vertical: 16 * sf,
              ),
            ),
            onSubmitted: (_) => _submitNewName(),
          ),
        ),

        SizedBox(height: 20 * sf),

        // Let's Go button
        AnimatedOpacity(
          opacity: _hasText ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _hasText ? _submitNewName : null,
            child: Container(
              width: 200 * sf,
              height: 56 * sf,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.electricBlue, AppColors.violet],
                ),
                borderRadius: BorderRadius.circular(28 * sf),
                boxShadow: [
                  if (_hasText)
                    BoxShadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
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
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Profile Card ────────────────────────────────────────────────────────

class _ProfileCard extends StatefulWidget {
  final PlayerEntry profile;
  final AudioService audioService;
  final VoidCallback onTap;
  final int index;
  final double sf;

  const _ProfileCard({
    required this.profile,
    required this.audioService,
    required this.onTap,
    required this.index,
    required this.sf,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _onTap() {
    _glowController.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.sf;
    final color = widget.profile.color;
    final initial = widget.profile.name.isNotEmpty
        ? widget.profile.name[0].toUpperCase()
        : '?';
    final cardSize = (140 * sf).roundToDouble();

    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glow = sin(_glowController.value * pi);
          return Transform.scale(
            scale: 1.0 + glow * 0.08,
            child: Container(
              width: cardSize,
              height: cardSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24 * sf),
                border: Border.all(
                  color: color.withValues(alpha: 0.5 + glow * 0.5),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2 + glow * 0.3),
                    blurRadius: 16 + glow * 16,
                    spreadRadius: glow * 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Large avatar circle with initial
                  Container(
                    width: 64 * sf,
                    height: 64 * sf,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [
                          color.withValues(alpha: 0.6),
                          color.withValues(alpha: 0.3),
                        ],
                      ),
                      border: Border.all(
                        color: color.withValues(alpha: 0.8),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: AppFonts.fredoka(
                          fontSize: 32 * sf,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 8 * sf),

                  // Name
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8 * sf),
                    child: Text(
                      widget.profile.name,
                      style: AppFonts.fredoka(
                        fontSize: 16 * sf,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Small speaker hint
                  Icon(
                    Icons.volume_up_rounded,
                    size: 14 * sf,
                    color: AppColors.secondaryText.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

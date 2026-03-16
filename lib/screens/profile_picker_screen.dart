import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/audio_service.dart';
import '../services/player_settings_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/name_validator.dart';
import '../widgets/floating_hearts_bg.dart';

/// "Who's Playing?" profile picker screen.
/// Large colorful cards with avatar thumbnails, voice on tap, kid-friendly.
class ProfilePickerScreen extends StatefulWidget {
  final PlayerSettingsService settingsService;
  final AudioService audioService;
  final ProfileService? profileService;
  final void Function(String profileId) onProfileSelected;
  final void Function(String name) onNewProfile;

  const ProfilePickerScreen({
    super.key,
    required this.settingsService,
    required this.audioService,
    this.profileService,
    required this.onProfileSelected,
    required this.onNewProfile,
  });

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen>
    with TickerProviderStateMixin {
  bool _showingNameInput = false;
  bool _selecting = false;
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _hasText = false;
  String? _nameError;
  late AnimationController _addButtonGlowController;
  late AnimationController _addButtonRotateController;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final hasText = _nameController.text.trim().isNotEmpty;
      if (hasText != _hasText || _nameError != null) {
        setState(() {
          _hasText = hasText;
          _nameError = null;
        });
      }
    });

    _addButtonGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _addButtonRotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    // Play "Who's playing?" voice
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.audioService.playWord('whos_playing');
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _addButtonGlowController.dispose();
    _addButtonRotateController.dispose();
    super.dispose();
  }

  void _onProfileTap(PlayerEntry profile) {
    if (_selecting) return;
    _selecting = true;
    if (profile.name.isNotEmpty) {
      widget.audioService.playWord(profile.name.toLowerCase());
    }
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
    if (name.isEmpty) return;
    final error = NameValidator.validate(name);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    setState(() => _nameError = null);
    widget.onNewProfile(NameValidator.formatName(name));
  }

  void _showProfileOptions(PlayerEntry profile) {
    final sf = (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.2);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24 * sf)),
      ),
      builder: (ctx) => _ProfileOptionsSheet(
        profile: profile,
        sf: sf,
        onRename: () {
          Navigator.pop(ctx);
          _showRenameDialog(profile);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _showDeleteConfirmation(profile);
        },
      ),
    );
  }

  void _showRenameDialog(PlayerEntry profile) {
    final renameController = TextEditingController(text: profile.name);
    final sf = (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.2);
    String? renameError;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20 * sf),
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            title: Text(
              'Rename Player',
              style: AppFonts.fredoka(
                fontSize: 22 * sf,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12 * sf),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: renameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: 22 * sf,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryText,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16 * sf,
                        vertical: 12 * sf,
                      ),
                    ),
                    onChanged: (_) {
                      if (renameError != null) {
                        setDialogState(() => renameError = null);
                      }
                    },
                  ),
                ),
                if (renameError != null) ...[
                  SizedBox(height: 8 * sf),
                  Text(
                    renameError!,
                    textAlign: TextAlign.center,
                    style: AppFonts.nunito(
                      fontSize: 13 * sf,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: AppFonts.nunito(
                    fontSize: 16 * sf,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final newName = renameController.text.trim();
                  if (newName.isEmpty) return;
                  final error = NameValidator.validate(newName);
                  if (error != null) {
                    setDialogState(() => renameError = error);
                    return;
                  }
                  final formatted = NameValidator.formatName(newName);
                  await widget.settingsService.renameProfile(profile.id, formatted);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: Text(
                  'Save',
                  style: AppFonts.nunito(
                    fontSize: 16 * sf,
                    fontWeight: FontWeight.w700,
                    color: AppColors.electricBlue,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(PlayerEntry profile) {
    final sf = (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.2);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * sf),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        title: Text(
          'Delete Profile?',
          style: AppFonts.fredoka(
            fontSize: 22 * sf,
            fontWeight: FontWeight.w600,
            color: AppColors.error,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${profile.name}"?\n\nAll progress and stickers will be lost forever.',
          style: AppFonts.nunito(
            fontSize: 15 * sf,
            color: AppColors.secondaryText,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep',
              style: AppFonts.nunito(
                fontSize: 16 * sf,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await widget.settingsService.removeProfile(profile.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                setState(() {});
              }
            },
            child: Text(
              'Delete',
              style: AppFonts.nunito(
                fontSize: 16 * sf,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.settingsService.profiles;
    final screenW = MediaQuery.of(context).size.width;
    final sf = (screenW / 400).clamp(0.7, 1.2);
    final cardSize = (150 * sf).roundToDouble();

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
          const ExcludeSemantics(
            child: Positioned.fill(
              child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
            ),
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

                    // "Who's Playing?" -- tappable to replay voice
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
                              profileService: widget.profileService,
                              onTap: () => _onProfileTap(profiles[i]),
                              onLongPress: () => _showProfileOptions(profiles[i]),
                              index: i,
                              sf: sf,
                              cardSize: cardSize,
                            )
                                .animate()
                                .fadeIn(
                                  delay: Duration(milliseconds: 150 + i * 100),
                                  duration: 500.ms,
                                )
                                .scale(
                                  begin: const Offset(0.8, 0.8),
                                  end: const Offset(1.0, 1.0),
                                  delay: Duration(milliseconds: 150 + i * 100),
                                  duration: 400.ms,
                                  curve: Curves.easeOutBack,
                                ),
                        ],
                      ),

                      SizedBox(height: 24 * sf),

                      // Add player button -- enhanced with glow and sparkle
                      _buildAddPlayerButton(sf, cardSize),
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

  Widget _buildAddPlayerButton(double sf, double cardSize) {
    return GestureDetector(
      onTap: _showAddPlayer,
      child: AnimatedBuilder(
        animation: _addButtonGlowController,
        builder: (context, child) {
          final glowVal = _addButtonGlowController.value;
          return Container(
            width: cardSize,
            height: cardSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withValues(alpha: 0.5),
                  AppColors.surfaceVariant.withValues(alpha: 0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(24 * sf),
              border: Border.all(
                color: Color.lerp(
                  AppColors.electricBlue.withValues(alpha: 0.3),
                  AppColors.violet.withValues(alpha: 0.5),
                  glowVal,
                )!,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.1 + glowVal * 0.15),
                  blurRadius: 20 + glowVal * 10,
                  spreadRadius: glowVal * 4,
                ),
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.05 + glowVal * 0.1),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated plus icon with rainbow ring
                AnimatedBuilder(
                  animation: _addButtonRotateController,
                  builder: (context, child) {
                    return Container(
                      width: 56 * sf,
                      height: 56 * sf,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          startAngle: _addButtonRotateController.value * 2 * pi,
                          colors: [
                            AppColors.electricBlue.withValues(alpha: 0.3 + glowVal * 0.2),
                            AppColors.violet.withValues(alpha: 0.3 + glowVal * 0.2),
                            AppColors.magenta.withValues(alpha: 0.3 + glowVal * 0.2),
                            AppColors.emerald.withValues(alpha: 0.3 + glowVal * 0.2),
                            AppColors.electricBlue.withValues(alpha: 0.3 + glowVal * 0.2),
                          ],
                        ),
                      ),
                      child: Container(
                        margin: EdgeInsets.all(2.5 * sf),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: Color.lerp(
                            AppColors.electricBlue,
                            AppColors.violet,
                            glowVal,
                          ),
                          size: 34 * sf,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 10 * sf),
                Text(
                  'Add Player',
                  style: AppFonts.fredoka(
                    fontSize: 15 * sf,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryText.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    )
        .animate()
        .fadeIn(delay: 500.ms, duration: 400.ms)
        .scale(
          begin: const Offset(0.9, 0.9),
          delay: 500.ms,
          duration: 350.ms,
          curve: Curves.easeOutBack,
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

        // Cute icon
        Icon(
          Icons.emoji_emotions_rounded,
          size: 48 * sf,
          color: AppColors.starGold,
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1.0, end: 1.1, duration: 800.ms)
            .then()
            .rotate(begin: -0.02, end: 0.02, duration: 600.ms),

        SizedBox(height: 12 * sf),

        Text(
          "What's your name?",
          style: AppFonts.fredoka(
            fontSize: 24 * sf,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
        ),

        SizedBox(height: 16 * sf),

        // Name field with enhanced styling
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

        // Validation error message
        if (_nameError != null) ...[
          SizedBox(height: 8 * sf),
          Text(
            _nameError!,
            textAlign: TextAlign.center,
            style: AppFonts.nunito(
              fontSize: 14 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],

        SizedBox(height: 8 * sf),

        // Character count hint
        AnimatedOpacity(
          opacity: _hasText ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Text(
            _nameController.text.trim(),
            style: AppFonts.fredoka(
              fontSize: 14 * sf,
              fontWeight: FontWeight.w400,
              color: AppColors.emerald.withValues(alpha: 0.6),
              letterSpacing: 4,
            ),
          ),
        ),

        SizedBox(height: 16 * sf),

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Let's Go!",
                      style: AppFonts.fredoka(
                        fontSize: 24 * sf,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8 * sf),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 24 * sf,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Profile Options Bottom Sheet ──────────────────────────────────────────

class _ProfileOptionsSheet extends StatelessWidget {
  final PlayerEntry profile;
  final double sf;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ProfileOptionsSheet({
    required this.profile,
    required this.sf,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24 * sf, vertical: 20 * sf),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40 * sf,
            height: 4 * sf,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2 * sf),
            ),
          ),
          SizedBox(height: 16 * sf),
          Text(
            profile.name,
            style: AppFonts.fredoka(
              fontSize: 22 * sf,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          SizedBox(height: 20 * sf),
          _OptionTile(
            icon: Icons.edit_rounded,
            label: 'Rename',
            color: AppColors.electricBlue,
            sf: sf,
            onTap: onRename,
          ),
          SizedBox(height: 8 * sf),
          _OptionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Profile',
            color: AppColors.error,
            sf: sf,
            onTap: onDelete,
          ),
          SizedBox(height: 16 * sf),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double sf;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.sf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * sf, vertical: 14 * sf),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14 * sf),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22 * sf),
            SizedBox(width: 12 * sf),
            Text(
              label,
              style: AppFonts.nunito(
                fontSize: 16 * sf,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile Card ────────────────────────────────────────────────────────

class _ProfileCard extends StatefulWidget {
  final PlayerEntry profile;
  final AudioService audioService;
  final ProfileService? profileService;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final int index;
  final double sf;
  final double cardSize;

  const _ProfileCard({
    required this.profile,
    required this.audioService,
    this.profileService,
    required this.onTap,
    required this.onLongPress,
    required this.index,
    required this.sf,
    required this.cardSize,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _shimmerController;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => setState(() => _pressed = true);
  void _onTapUp(TapUpDetails _) => setState(() => _pressed = false);
  void _onTapCancel() => setState(() => _pressed = false);

  void _onTap() {
    _glowController.forward(from: 0);
    _shimmerController.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.sf;
    final color = widget.profile.color;
    final initial = widget.profile.name.isNotEmpty
        ? widget.profile.name[0].toUpperCase()
        : '?';
    final cardSize = widget.cardSize;

    return GestureDetector(
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([_glowController, _shimmerController]),
        builder: (context, child) {
          final glow = sin(_glowController.value * pi);
          final shimmerProgress = _shimmerController.value;
          final pressScale = _pressed ? 0.95 : 1.0;

          return Transform.scale(
            scale: (1.0 + glow * 0.06) * pressScale,
            child: Container(
              width: cardSize,
              height: cardSize,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.2),
                    color.withValues(alpha: 0.08),
                    AppColors.surface.withValues(alpha: 0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(24 * sf),
                border: Border.all(
                  color: color.withValues(alpha: 0.5 + glow * 0.5),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15 + glow * 0.25),
                    blurRadius: 16 + glow * 16,
                    spreadRadius: glow * 3,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Shimmer sweep overlay
                  if (shimmerProgress > 0 && shimmerProgress < 1)
                    Positioned.fill(
                      child: ShaderMask(
                        shaderCallback: (rect) {
                          return LinearGradient(
                            begin: Alignment(-2 + shimmerProgress * 4, 0),
                            end: Alignment(-1 + shimmerProgress * 4, 0),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.srcATop,
                        child: Container(color: Colors.white),
                      ),
                    ),

                  // Settings gear icon
                  Positioned(
                    top: 6 * sf,
                    right: 6 * sf,
                    child: GestureDetector(
                      onTap: widget.onLongPress,
                      child: Container(
                        width: 30 * sf,
                        height: 30 * sf,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface.withValues(alpha: 0.5),
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          size: 15 * sf,
                          color: AppColors.secondaryText.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),

                  // Card content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 4 * sf),
                        // Avatar circle with gradient and initial
                        Container(
                          width: 68 * sf,
                          height: 68 * sf,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.3, -0.3),
                              colors: [
                                color.withValues(alpha: 0.6),
                                color.withValues(alpha: 0.25),
                              ],
                            ),
                            border: Border.all(
                              color: color.withValues(alpha: 0.8),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.25),
                                blurRadius: 10,
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
                              fontSize: 17 * sf,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        SizedBox(height: 4 * sf),

                        // Speaker hint + tap hint
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.volume_up_rounded,
                              size: 13 * sf,
                              color: AppColors.secondaryText.withValues(alpha: 0.4),
                            ),
                            SizedBox(width: 4 * sf),
                            Text(
                              'Tap to play',
                              style: AppFonts.nunito(
                                fontSize: 10 * sf,
                                color: AppColors.secondaryText.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../avatar/data/avatar_options.dart';
import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../avatar/avatar_widget.dart';
import '../utils/haptics.dart';

/// Full-screen avatar editor designed as a fun dress-up game for ages 3-6.
///
/// 5 kid-friendly tabs (Hair, Skin, Shirt, Eyes, Extras) with large tap targets,
/// live avatar preview in the top 40%, and glowing selection indicators.
class AvatarEditorScreen extends StatefulWidget {
  final ProfileService profileService;
  final AudioService? audioService;
  final int wordsMastered;
  final int streakDays;

  const AvatarEditorScreen({
    super.key,
    required this.profileService,
    this.audioService,
    this.wordsMastered = 0,
    this.streakDays = 0,
  });

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen>
    with SingleTickerProviderStateMixin {
  late AvatarConfig _config;
  late TabController _tabController;
  int _selectedTab = 0;

  // Sub-category index within each tab (for tabs with multiple sub-sections)
  int _hairSubIndex = 0; // 0=style, 1=color
  int _eyeSubIndex = 0; // 0=style, 1=color, 2=lashes, 3=brows
  int _extrasSubIndex = 0; // 0=accessories, 1=glasses, 2=face paint, 3=cheeks, 4=mouth, 5=nose, 6=bg

  int get _evolutionStage {
    final level = ReadingLevel.forWordCount(widget.wordsMastered);
    return level.index + 1;
  }

  // ── Tab Definitions ────────────────────────────────────────────────

  static const List<_TabDef> _tabs = [
    _TabDef('Hair', Icons.content_cut),
    _TabDef('Skin', Icons.palette),
    _TabDef('Shirt', Icons.checkroom),
    _TabDef('Eyes', Icons.visibility),
    _TabDef('Extras', Icons.auto_awesome),
  ];

  @override
  void initState() {
    super.initState();
    _config = widget.profileService.avatar;
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateConfig(AvatarConfig newConfig) {
    setState(() => _config = newConfig);
    // Auto-save on every change
    widget.profileService.setAvatar(newConfig);
    Haptics.tap();
  }

  void _showLockedHint(String hint) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.starGold, size: 18),
            const SizedBox(width: 8),
            Text(
              'Keep playing to unlock! $hint',
              style: AppFonts.fredoka(fontSize: 13, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _save() async {
    await widget.profileService.setAvatar(_config);
    widget.audioService?.playSuccess();
    if (mounted) Navigator.of(context).pop(_config);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeTop = MediaQuery.of(context).padding.top;
    // Avatar preview takes ~38% of usable screen height
    final previewHeight = (screenHeight - safeTop) * 0.38;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header (close + randomize) ──
            _buildHeader()
                .animate()
                .fadeIn(duration: 300.ms)
                .slideY(begin: -0.3, end: 0, duration: 300.ms, curve: Curves.easeOut),
            // ── Avatar Preview (top ~38%) ──
            SizedBox(
              height: previewHeight.clamp(180.0, 320.0),
              child: _buildPreview(),
            )
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms)
                .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0),
                    delay: 100.ms, duration: 400.ms, curve: Curves.easeOut),
            const SizedBox(height: 8),
            // ── Tab Bar ──
            _buildTabBar()
                .animate()
                .fadeIn(delay: 250.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 250.ms, duration: 300.ms, curve: Curves.easeOut),
            const SizedBox(height: 4),
            // ── Options Area (rest of screen) ──
            Expanded(
              child: _buildTabContent()
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 300.ms),
            ),
            // ── Done Button ──
            _buildDoneButton(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  double _diceTurns = 0;

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Text(
            'Dress Up!',
            style: AppFonts.fredoka(
              fontSize: 20,
              color: AppColors.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() => _diceTurns += 1.0);
              _randomize();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
              ),
              child: AnimatedRotation(
                turns: _diceTurns,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.casino_rounded,
                    color: AppColors.secondaryText, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _randomize() {
    final rng = Random();
    _updateConfig(AvatarConfig(
      faceShape: rng.nextInt(faceShapeOptions.length),
      skinTone: 0,
      skinToneValue: rng.nextDouble(),
      hairStyle: rng.nextInt(hairStyleOptions.length),
      hairColor: rng.nextInt(8), // only free colors
      eyeStyle: rng.nextInt(eyeStyleOptions.length),
      mouthStyle: rng.nextInt(mouthStyleOptions.length),
      accessory: rng.nextInt(6), // only free accessories
      bgColor: rng.nextInt(bgColorOptions.length),
      eyeColor: rng.nextInt(eyeColorOptions.length),
      eyelashStyle: rng.nextInt(eyelashStyleOptions.length),
      eyebrowStyle: rng.nextInt(eyebrowStyleOptions.length),
      lipColor: rng.nextInt(lipColorOptions.length),
      cheekStyle: rng.nextInt(cheekStyleOptions.length),
      noseStyle: rng.nextInt(noseStyleOptions.length),
      glassesStyle: rng.nextInt(glassesStyleOptions.length),
      facePaint: rng.nextInt(facePaintOptions.length),
      shirtColor: rng.nextInt(shirtColorOptions.length),
      shirtStyle: rng.nextInt(shirtStyleOptions.length),
      hasSparkle: _config.hasSparkle,
      hasRainbowSparkle: _config.hasRainbowSparkle,
      hasGoldenGlow: _config.hasGoldenGlow,
    ));
  }

  // ── Live Preview ────────────────────────────────────────────────────

  Widget _buildPreview() {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.78,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.violet.withValues(alpha: 0.45),
                AppColors.magenta.withValues(alpha: 0.35),
                AppColors.electricBlue.withValues(alpha: 0.35),
                AppColors.violet.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.violet.withValues(alpha: 0.06),
                  AppColors.surface,
                  AppColors.surface,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.20),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth.clamp(120.0, 280.0);
                  return Center(
                    child: AvatarWidget(
                      config: _config,
                      size: size,
                      animateEffects: true,
                    )
                        .animate(key: ValueKey(_config.hashCode))
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1.0, 1.0),
                          duration: 280.ms,
                          curve: Curves.elasticOut,
                        ),
                  );
                },
              ),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .custom(
              duration: 2500.ms,
              builder: (context, value, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.violet
                            .withValues(alpha: 0.10 + 0.08 * value),
                        blurRadius: 20 + 8 * value,
                        spreadRadius: 2 + 2 * value,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
            ),
      ),
    );
  }

  // ── Tab Bar ─────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final selected = index == _selectedTab;
          final tab = _tabs[index];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(index);
                setState(() => _selectedTab = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: selected
                      ? AppColors.violet.withValues(alpha: 0.25)
                      : AppColors.surface,
                  border: Border.all(
                    color: selected ? AppColors.violet : AppColors.border,
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.violet.withValues(alpha: 0.30),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 22,
                      color: selected ? AppColors.violet : AppColors.secondaryText,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab.label,
                      style: AppFonts.fredoka(
                        fontSize: 11,
                        color: selected ? AppColors.violet : AppColors.secondaryText,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Tab Content ─────────────────────────────────────────────────────

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildHairTab(),
        _buildSkinTab(),
        _buildShirtTab(),
        _buildEyesTab(),
        _buildExtrasTab(),
      ],
    );
  }

  // ── Hair Tab (Style + Color) ────────────────────────────────────────

  Widget _buildHairTab() {
    return _SubTabLayout(
      subTabs: const ['Style', 'Color'],
      selectedIndex: _hairSubIndex,
      onSubTabChanged: (i) => setState(() => _hairSubIndex = i),
      children: [
        _buildHairStyleGrid(),
        _buildHairColorGrid(),
      ],
    );
  }

  Widget _buildHairStyleGrid() {
    return _optionGrid(
      itemCount: hairStyleOptions.length,
      selectedIndex: _config.hairStyle,
      labelForIndex: (i) => hairStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(hairStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(hairStyle: index)),
    );
  }

  Widget _buildHairColorGrid() {
    return _optionGrid(
      itemCount: hairColorOptions.length,
      selectedIndex: _config.hairColor,
      labelForIndex: (i) => hairColorOptions[i].label,
      builder: (index) {
        final opt = hairColorOptions[index];
        final locked = opt.isLocked &&
            !isUnlocked(
              requirement: opt.unlock,
              wordsMastered: widget.wordsMastered,
              evolutionStage: _evolutionStage,
              streakDays: widget.streakDays,
            );

        Widget swatch;
        if (index == 13) {
          swatch = Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF4444),
                  Color(0xFFFF8C42),
                  Color(0xFFFFD700),
                  Color(0xFF00E68A),
                  Color(0xFF4A90D9),
                  Color(0xFF9B59B6),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          );
        } else {
          swatch = Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: locked ? opt.color.withValues(alpha: 0.3) : opt.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          );
        }

        return _OptionTileContent(
          locked: locked,
          hint: opt.unlock?.hint,
          child: Center(child: swatch),
        );
      },
      onTap: (index) {
        final opt = hairColorOptions[index];
        final locked = opt.isLocked &&
            !isUnlocked(
              requirement: opt.unlock,
              wordsMastered: widget.wordsMastered,
              evolutionStage: _evolutionStage,
              streakDays: widget.streakDays,
            );
        if (!locked) {
          _updateConfig(_config.copyWith(hairColor: index));
        } else {
          _showLockedHint(opt.unlock?.hint ?? '');
        }
      },
    );
  }

  // ── Skin Tab (Tone + Face Shape) ────────────────────────────────────

  Widget _buildSkinTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skin tone slider
          const _SectionHeader(label: 'Skin Tone'),
          const SizedBox(height: 8),
          _buildSkinToneSlider(),
          const SizedBox(height: 16),
          // Face shape
          const _SectionHeader(label: 'Face Shape'),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: _buildFaceShapeRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildSkinToneSlider() {
    final sliderValue = _config.skinToneValue >= 0.0
        ? _config.skinToneValue
        : _config.skinTone / (skinToneOptions.length - 1).toDouble();
    final currentColor = skinColorFromSlider(sliderValue);

    return Column(
      children: [
        // Color preview
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: currentColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: currentColor.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 20,
            trackShape: _SkinToneTrackShape(),
            thumbShape: _SkinToneThumbShape(color: currentColor),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            overlayColor: currentColor.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: sliderValue,
            onChanged: (value) {
              _updateConfig(_config.copyWith(skinToneValue: value));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Light',
                  style: AppFonts.fredoka(
                      fontSize: 11, color: AppColors.secondaryText)),
              Text('Dark',
                  style: AppFonts.fredoka(
                      fontSize: 11, color: AppColors.secondaryText)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaceShapeRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: faceShapeOptions.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final opt = faceShapeOptions[index];
        final selected = index == _config.faceShape;
        final previewSkin = _config.skinToneValue >= 0.0
            ? skinColorFromSlider(_config.skinToneValue)
            : skinColorForIndex(_config.skinTone);
        final r = opt.borderRadius * 30;
        return GestureDetector(
          onTap: () => _updateConfig(_config.copyWith(faceShape: index)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 64,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.violet.withValues(alpha: 0.20)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.violet : AppColors.border,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.30),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: (32 * opt.heightRatio).toDouble(),
                  decoration: BoxDecoration(
                    color: previewSkin,
                    borderRadius: BorderRadius.circular(r),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  opt.label,
                  style: AppFonts.fredoka(
                    fontSize: 9,
                    color: selected
                        ? AppColors.violet
                        : AppColors.secondaryText,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Shirt Tab (Color + Style) ───────────────────────────────────────

  int _shirtSubIndex = 0; // 0=color, 1=style

  Widget _buildShirtTab() {
    return _SubTabLayout(
      subTabs: const ['Color', 'Style'],
      selectedIndex: _shirtSubIndex,
      onSubTabChanged: (i) => setState(() => _shirtSubIndex = i),
      children: [
        _buildShirtColorGrid(),
        _buildShirtStyleGrid(),
      ],
    );
  }

  Widget _buildShirtColorGrid() {
    return _optionGrid(
      itemCount: shirtColorOptions.length,
      selectedIndex: _config.shirtColor,
      labelForIndex: (i) => shirtColorOptions[i].label,
      builder: (index) {
        final opt = shirtColorOptions[index];
        return Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: opt.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(shirtColor: index)),
    );
  }

  Widget _buildShirtStyleGrid() {
    return _optionGrid(
      itemCount: shirtStyleOptions.length,
      selectedIndex: _config.shirtStyle,
      labelForIndex: (i) => shirtStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(shirtStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(shirtStyle: index)),
    );
  }

  // ── Eyes Tab (Style, Color, Lashes, Brows) ──────────────────────────

  Widget _buildEyesTab() {
    return _SubTabLayout(
      subTabs: const ['Shape', 'Color', 'Lashes', 'Brows'],
      selectedIndex: _eyeSubIndex,
      onSubTabChanged: (i) => setState(() => _eyeSubIndex = i),
      children: [
        _buildEyeStyleGrid(),
        _buildEyeColorGrid(),
        _buildEyelashGrid(),
        _buildEyebrowGrid(),
      ],
    );
  }

  Widget _buildEyeStyleGrid() {
    return _optionGrid(
      itemCount: eyeStyleOptions.length,
      selectedIndex: _config.eyeStyle,
      labelForIndex: (i) => eyeStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(eyeStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyeStyle: index)),
    );
  }

  Widget _buildEyeColorGrid() {
    return _optionGrid(
      itemCount: eyeColorOptions.length,
      selectedIndex: _config.eyeColor,
      labelForIndex: (i) => eyeColorOptions[i].label,
      builder: (index) {
        final opt = eyeColorOptions[index];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: opt.color,
                  ),
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyeColor: index)),
    );
  }

  Widget _buildEyelashGrid() {
    return _optionGrid(
      itemCount: eyelashStyleOptions.length,
      selectedIndex: _config.eyelashStyle,
      labelForIndex: (i) => eyelashStyleOptions[i].label,
      builder: (index) {
        if (index == 0) {
          return Center(
            child: Icon(Icons.block,
                size: 28,
                color: AppColors.secondaryText.withValues(alpha: 0.5)),
          );
        }
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(eyelashStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyelashStyle: index)),
    );
  }

  Widget _buildEyebrowGrid() {
    return _optionGrid(
      itemCount: eyebrowStyleOptions.length,
      selectedIndex: _config.eyebrowStyle,
      labelForIndex: (i) => eyebrowStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(eyebrowStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyebrowStyle: index)),
    );
  }

  // ── Extras Tab (Accessories, Glasses, FacePaint, Cheeks, Mouth, Nose, Lips, BG) ──

  Widget _buildExtrasTab() {
    return _SubTabLayout(
      subTabs: const ['Hats', 'Glasses', 'Paint', 'Cheeks', 'Mouth', 'Lips', 'Nose', 'BG'],
      selectedIndex: _extrasSubIndex,
      onSubTabChanged: (i) => setState(() => _extrasSubIndex = i),
      children: [
        _buildAccessoryGrid(),
        _buildGlassesGrid(),
        _buildFacePaintGrid(),
        _buildCheekGrid(),
        _buildMouthGrid(),
        _buildLipColorGrid(),
        _buildNoseGrid(),
        _buildBgColorGrid(),
      ],
    );
  }

  bool _isAccessoryLocked(AccessoryOption opt) {
    if (!opt.isLocked) return false;
    if (opt.unlock?.type == UnlockType.treasureChest) {
      return !widget.profileService.isItemUnlocked(opt.unlockId);
    }
    return !isUnlocked(
      requirement: opt.unlock,
      wordsMastered: widget.wordsMastered,
      evolutionStage: _evolutionStage,
      streakDays: widget.streakDays,
    );
  }

  Widget _buildAccessoryGrid() {
    return _optionGrid(
      itemCount: accessoryOptions.length,
      selectedIndex: _config.accessory,
      labelForIndex: (i) => accessoryOptions[i].label,
      builder: (index) {
        final opt = accessoryOptions[index];
        final locked = _isAccessoryLocked(opt);
        return _OptionTileContent(
          locked: locked,
          hint: opt.unlock?.hint,
          child: Center(
            child: index == 0
                ? Icon(Icons.block,
                    size: 28,
                    color: AppColors.secondaryText.withValues(alpha: 0.5))
                : SizedBox(
                    width: 48,
                    height: 48,
                    child: AvatarWidget(
                      animateEffects: false,
                      config: _config.copyWith(accessory: index),
                      size: 48,
                      showBackground: false,
                    ),
                  ),
          ),
        );
      },
      onTap: (index) {
        final opt = accessoryOptions[index];
        if (!_isAccessoryLocked(opt)) {
          _updateConfig(_config.copyWith(accessory: index));
        } else {
          _showLockedHint(opt.unlock?.hint ?? '');
        }
      },
    );
  }

  Widget _buildGlassesGrid() {
    return _optionGrid(
      itemCount: glassesStyleOptions.length,
      selectedIndex: _config.glassesStyle,
      labelForIndex: (i) => glassesStyleOptions[i].label,
      builder: (index) {
        if (index == 0) {
          return Center(
            child: Icon(Icons.block,
                size: 28,
                color: AppColors.secondaryText.withValues(alpha: 0.5)),
          );
        }
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(glassesStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(glassesStyle: index)),
    );
  }

  Widget _buildFacePaintGrid() {
    return _optionGrid(
      itemCount: facePaintOptions.length,
      selectedIndex: _config.facePaint,
      labelForIndex: (i) => facePaintOptions[i].label,
      builder: (index) {
        if (index == 0) {
          return Center(
            child: Icon(Icons.block,
                size: 28,
                color: AppColors.secondaryText.withValues(alpha: 0.5)),
          );
        }
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(facePaint: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(facePaint: index)),
    );
  }

  Widget _buildCheekGrid() {
    return _optionGrid(
      itemCount: cheekStyleOptions.length,
      selectedIndex: _config.cheekStyle,
      labelForIndex: (i) => cheekStyleOptions[i].label,
      builder: (index) {
        if (index == 0) {
          return Center(
            child: Icon(Icons.block,
                size: 28,
                color: AppColors.secondaryText.withValues(alpha: 0.5)),
          );
        }
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(cheekStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(cheekStyle: index)),
    );
  }

  Widget _buildMouthGrid() {
    return _optionGrid(
      itemCount: mouthStyleOptions.length,
      selectedIndex: _config.mouthStyle,
      labelForIndex: (i) => mouthStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(mouthStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(mouthStyle: index)),
    );
  }

  Widget _buildLipColorGrid() {
    return _optionGrid(
      itemCount: lipColorOptions.length,
      selectedIndex: _config.lipColor,
      labelForIndex: (i) => lipColorOptions[i].label,
      builder: (index) {
        final opt = lipColorOptions[index];
        if (index == 0) {
          return Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: Icon(Icons.block,
                  size: 20,
                  color: AppColors.secondaryText.withValues(alpha: 0.5)),
            ),
          );
        }
        return Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: opt.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(lipColor: index)),
    );
  }

  Widget _buildNoseGrid() {
    return _optionGrid(
      itemCount: noseStyleOptions.length,
      selectedIndex: _config.noseStyle,
      labelForIndex: (i) => noseStyleOptions[i].label,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(noseStyle: index),
              size: 48,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(noseStyle: index)),
    );
  }

  Widget _buildBgColorGrid() {
    return _optionGrid(
      itemCount: bgColorOptions.length,
      selectedIndex: _config.bgColor,
      labelForIndex: (i) => bgColorOptions[i].label,
      builder: (index) {
        final opt = bgColorOptions[index];
        return Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: opt.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(bgColor: index)),
    );
  }

  // ── Shared Grid Builder ─────────────────────────────────────────────

  Widget _optionGrid({
    required int itemCount,
    required int selectedIndex,
    required Widget Function(int index) builder,
    required void Function(int index) onTap,
    String Function(int index)? labelForIndex,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final selected = index == selectedIndex;
        return GestureDetector(
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.violet.withValues(alpha: 0.20)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.violet : AppColors.border,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Expanded(
                  child: selected
                      ? builder(index)
                          .animate()
                          .scale(
                            begin: const Offset(0.88, 0.88),
                            end: const Offset(1.0, 1.0),
                            duration: 320.ms,
                            curve: Curves.elasticOut,
                          )
                      : builder(index),
                ),
                if (labelForIndex != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      labelForIndex(index),
                      style: AppFonts.fredoka(
                        fontSize: 9,
                        color: selected
                            ? AppColors.violet
                            : AppColors.secondaryText,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Done Button ─────────────────────────────────────────────────────

  Widget _buildDoneButton() {
    return Center(
      child: GestureDetector(
        onTap: _save,
        child: Container(
          width: 140,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: AppColors.success,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 6),
              Text(
                'Done!',
                style: AppFonts.fredoka(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 300.ms)
        .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.0, 1.0),
            duration: 300.ms,
            curve: Curves.elasticOut);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

/// Tab definition with label and icon.
class _TabDef {
  final String label;
  final IconData icon;
  const _TabDef(this.label, this.icon);
}

/// A small circular icon button used in the header.
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.primaryText, size: 22),
      ),
    );
  }
}

/// Section header label for the Skin and Shirt tabs.
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppFonts.fredoka(
        fontSize: 14,
        color: AppColors.primaryText,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Layout with a row of sub-tab chips above swappable content.
class _SubTabLayout extends StatelessWidget {
  final List<String> subTabs;
  final int selectedIndex;
  final ValueChanged<int> onSubTabChanged;
  final List<Widget> children;

  const _SubTabLayout({
    required this.subTabs,
    required this.selectedIndex,
    required this.onSubTabChanged,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-tab chips
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: subTabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final selected = index == selectedIndex;
              return GestureDetector(
                onTap: () => onSubTabChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected
                        ? AppColors.violet.withValues(alpha: 0.25)
                        : AppColors.surface,
                    border: Border.all(
                      color: selected ? AppColors.violet : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    subTabs[index],
                    style: AppFonts.fredoka(
                      fontSize: 12,
                      color: selected
                          ? AppColors.violet
                          : AppColors.secondaryText,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // Content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(selectedIndex),
              child: children[selectedIndex],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Locked option overlay ────────────────────────────────────────────

class _OptionTileContent extends StatelessWidget {
  final bool locked;
  final String? hint;
  final Widget child;

  const _OptionTileContent({
    required this.locked,
    this.hint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;

    final starCount = hint != null
        ? RegExp(r'\d+').firstMatch(hint!)?.group(0)
        : null;
    final isTreasure = hint == 'Treasure!';

    return Stack(
      children: [
        Opacity(opacity: 0.25, child: child),
        Positioned.fill(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Sparkle-lock icon instead of plain lock
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 20,
                    color: isTreasure
                        ? AppColors.starGold.withValues(alpha: 0.6)
                        : AppColors.secondaryText.withValues(alpha: 0.6),
                  ),
                  Positioned(
                    top: 0,
                    right: -2,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 10,
                      color: isTreasure
                          ? AppColors.starGold.withValues(alpha: 0.8)
                          : AppColors.violet.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (isTreasure)
                Text(
                  'Treasure!',
                  style: AppFonts.fredoka(
                    fontSize: 8,
                    color: AppColors.starGold.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (starCount != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: AppColors.starGold.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 1),
                    Text(
                      starCount,
                      style: AppFonts.fredoka(
                        fontSize: 10,
                        color: AppColors.starGold.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Custom Skin Tone Slider Track ───────────────────────────────────

class _SkinToneTrackShape extends SliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 20;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx + 12,
      trackTop,
      parentBox.size.width - 24,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    final gradient = LinearGradient(
      colors: skinToneGradientColors,
      stops: skinToneGradientStops,
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    context.canvas.drawRRect(rrect, paint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    context.canvas.drawRRect(rrect, borderPaint);
  }
}

// ── Custom Skin Tone Slider Thumb ───────────────────────────────────

class _SkinToneThumbShape extends SliderComponentShape {
  final Color color;
  const _SkinToneThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(28, 28);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    final outerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 14, outerPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 11, fillPaint);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, 14, shadowPaint);
  }
}

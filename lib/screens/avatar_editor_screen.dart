import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../avatar/data/avatar_options.dart';
import '../models/player_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../avatar/avatar_widget.dart';

/// Full-screen avatar editor with live preview and category-based customization.
///
/// 16 customization categories, each displayed as a horizontal scrollable
/// row of large tappable option tiles. Categories are swiped/tapped via
/// a top tab bar. Designed for children aged 3-6 with big tap targets.
class AvatarEditorScreen extends StatefulWidget {
  final ProfileService profileService;
  final int wordsMastered;
  final int streakDays;

  const AvatarEditorScreen({
    super.key,
    required this.profileService,
    this.wordsMastered = 0,
    this.streakDays = 0,
  });

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  late AvatarConfig _config;
  late PageController _pageController;
  int _selectedCategory = 0;

  int get _evolutionStage {
    final level = ReadingLevel.forWordCount(widget.wordsMastered);
    return level.index + 1;
  }

  // ── Category Definitions ────────────────────────────────────────────

  static const List<_Category> _categories = [
    _Category('Face', Icons.face),
    _Category('Skin', Icons.palette),
    _Category('Hair', Icons.content_cut),
    _Category('Hair Color', Icons.color_lens),
    _Category('Eyes', Icons.visibility),
    _Category('Eye Color', Icons.remove_red_eye),
    _Category('Lashes', Icons.auto_awesome),
    _Category('Brows', Icons.linear_scale),
    _Category('Mouth', Icons.sentiment_satisfied_alt),
    _Category('Lips', Icons.brush),
    _Category('Cheeks', Icons.favorite),
    _Category('Nose', Icons.radio_button_unchecked),
    _Category('Glasses', Icons.preview),
    _Category('Paint', Icons.format_paint),
    _Category('Extras', Icons.star),
    _Category('BG', Icons.circle),
  ];

  @override
  void initState() {
    super.initState();
    _config = widget.profileService.avatar;
    _pageController = PageController(initialPage: _selectedCategory);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _updateConfig(AvatarConfig newConfig) {
    setState(() => _config = newConfig);
  }

  void _selectCategory(int index) {
    setState(() => _selectedCategory = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _save() async {
    await widget.profileService.setAvatar(_config);
    if (mounted) Navigator.of(context).pop(_config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 6),
            _buildPreview(),
            const SizedBox(height: 12),
            _buildCategoryTabs(),
            const SizedBox(height: 8),
            Expanded(child: _buildOptionsPageView()),
            _buildDoneButton(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Header (icon-only: close X, dice randomize) ────────────────────

  bool _diceSpinning = false;

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Close button — X icon
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close_rounded, color: AppColors.primaryText, size: 22),
            ),
          ),
          const Spacer(),
          // Randomize — spinning dice
          GestureDetector(
            onTap: () {
              setState(() => _diceSpinning = true);
              _randomize();
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setState(() => _diceSpinning = false);
              });
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
                turns: _diceSpinning ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.casino_rounded, color: AppColors.secondaryText, size: 22),
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
      skinTone: rng.nextInt(skinToneOptions.length),
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
      hasSparkle: _config.hasSparkle,
      hasRainbowSparkle: _config.hasRainbowSparkle,
      hasGoldenGlow: _config.hasGoldenGlow,
    ));
  }

  // ── Live Preview ────────────────────────────────────────────────────

  Widget _buildPreview() {
    return Center(
      child: GestureDetector(
        onTap: () {
          // Fun tap reaction — bouncy scale
          setState(() {});
        },
        child: Container(
          width: 164,
          height: 164,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: AvatarWidget(
            config: _config,
            size: 160.0,
            animateEffects: true,
          )
              .animate(key: ValueKey(_config.hashCode))
              .scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.0, 1.0),
                duration: 280.ms,
                curve: Curves.elasticOut,
              ),
        ),
      ),
    );
  }

  // ── Category Tab Bar ────────────────────────────────────────────────

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final selected = index == _selectedCategory;
          final cat = _categories[index];
          return GestureDetector(
            onTap: () => _selectCategory(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppColors.violet.withValues(alpha: 0.30)
                    : AppColors.surface,
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
              child: Icon(
                cat.icon,
                size: 20,
                color: selected ? AppColors.violet : AppColors.secondaryText,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Options PageView ────────────────────────────────────────────────

  Widget _buildOptionsPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _categories.length,
      onPageChanged: (index) {
        setState(() => _selectedCategory = index);
      },
      itemBuilder: (context, index) {
        return _buildCategoryContent(index);
      },
    );
  }

  Widget _buildCategoryContent(int categoryIndex) {
    switch (categoryIndex) {
      case 0:
        return _buildFaceShapeOptions();
      case 1:
        return _buildSkinToneOptions();
      case 2:
        return _buildHairStyleOptions();
      case 3:
        return _buildHairColorOptions();
      case 4:
        return _buildEyeStyleOptions();
      case 5:
        return _buildEyeColorOptions();
      case 6:
        return _buildEyelashOptions();
      case 7:
        return _buildEyebrowOptions();
      case 8:
        return _buildMouthStyleOptions();
      case 9:
        return _buildLipColorOptions();
      case 10:
        return _buildCheekOptions();
      case 11:
        return _buildNoseOptions();
      case 12:
        return _buildGlassesOptions();
      case 13:
        return _buildFacePaintOptions();
      case 14:
        return _buildAccessoryOptions();
      case 15:
        return _buildBgColorOptions();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Face Shape ──────────────────────────────────────────────────────

  Widget _buildFaceShapeOptions() {
    return _optionGrid(
      itemCount: faceShapeOptions.length,
      selectedIndex: _config.faceShape,
      builder: (index) {
        final opt = faceShapeOptions[index];
        final r = opt.borderRadius * 28;
        return Center(
          child: Container(
            width: 34,
            height: (34 * opt.heightRatio).toDouble(),
            decoration: BoxDecoration(
              color: skinColorForIndex(_config.skinTone),
              borderRadius: BorderRadius.circular(r),
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(faceShape: index)),
    );
  }

  // ── Skin Tone ───────────────────────────────────────────────────────

  Widget _buildSkinToneOptions() {
    return _optionGrid(
      itemCount: skinToneOptions.length,
      selectedIndex: _config.skinTone,
      builder: (index) {
        final opt = skinToneOptions[index];
        return Center(
          child: Container(
            width: 36,
            height: 36,
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
      onTap: (index) => _updateConfig(_config.copyWith(skinTone: index)),
    );
  }

  // ── Hair Style ──────────────────────────────────────────────────────

  Widget _buildHairStyleOptions() {
    return _optionGrid(
      itemCount: hairStyleOptions.length,
      selectedIndex: _config.hairStyle,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(hairStyle: index),
              size: 42,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(hairStyle: index)),
    );
  }

  // ── Hair Color ──────────────────────────────────────────────────────

  Widget _buildHairColorOptions() {
    return _optionGrid(
      itemCount: hairColorOptions.length,
      selectedIndex: _config.hairColor,
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
          // Rainbow — show gradient
          swatch = Container(
            width: 38,
            height: 38,
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
            width: 38,
            height: 38,
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
        if (!locked) _updateConfig(_config.copyWith(hairColor: index));
      },
    );
  }

  // ── Eye Style ───────────────────────────────────────────────────────

  Widget _buildEyeStyleOptions() {
    return _optionGrid(
      itemCount: eyeStyleOptions.length,
      selectedIndex: _config.eyeStyle,
      builder: (index) {
        return Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: AvatarWidget(
              animateEffects: false,
              config: _config.copyWith(eyeStyle: index),
              size: 42,
              showBackground: false,
            ),
          ),
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyeStyle: index)),
    );
  }

  // ── Eye Color ───────────────────────────────────────────────────────

  Widget _buildEyeColorOptions() {
    return _optionGrid(
      itemCount: eyeColorOptions.length,
      selectedIndex: _config.eyeColor,
      builder: (index) {
        final opt = eyeColorOptions[index];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
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
                  width: 22,
                  height: 22,
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

  // ── Eyelash Style ───────────────────────────────────────────────────

  Widget _buildEyelashOptions() {
    return _optionGrid(
      itemCount: eyelashStyleOptions.length,
      selectedIndex: _config.eyelashStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (index == 0)
              Icon(Icons.block,
                  size: 28,
                  color: AppColors.secondaryText.withValues(alpha: 0.5))
            else
              SizedBox(
                width: 42,
                height: 42,
                child: AvatarWidget(
                  animateEffects: false,
                  config: _config.copyWith(eyelashStyle: index),
                  size: 42,
                  showBackground: false,
                ),
              ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyelashStyle: index)),
    );
  }

  // ── Eyebrow Style ──────────────────────────────────────────────────

  Widget _buildEyebrowOptions() {
    return _optionGrid(
      itemCount: eyebrowStyleOptions.length,
      selectedIndex: _config.eyebrowStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: AvatarWidget(
                animateEffects: false,
                config: _config.copyWith(eyebrowStyle: index),
                size: 42,
                showBackground: false,
              ),
            ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(eyebrowStyle: index)),
    );
  }

  // ── Mouth Style ────────────────────────────────────────────────────

  Widget _buildMouthStyleOptions() {
    return _optionGrid(
      itemCount: mouthStyleOptions.length,
      selectedIndex: _config.mouthStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: AvatarWidget(
                animateEffects: false,
                config: _config.copyWith(mouthStyle: index),
                size: 42,
                showBackground: false,
              ),
            ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(mouthStyle: index)),
    );
  }

  // ── Lip Color ──────────────────────────────────────────────────────

  Widget _buildLipColorOptions() {
    return _optionGrid(
      itemCount: lipColorOptions.length,
      selectedIndex: _config.lipColor,
      builder: (index) {
        final opt = lipColorOptions[index];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (index == 0)
              // "Natural" — no lip color
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                    color: AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.block,
                    size: 20,
                    color: AppColors.secondaryText.withValues(alpha: 0.5)),
              )
            else
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: opt.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(lipColor: index)),
    );
  }

  // ── Cheek Style ────────────────────────────────────────────────────

  Widget _buildCheekOptions() {
    return _optionGrid(
      itemCount: cheekStyleOptions.length,
      selectedIndex: _config.cheekStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (index == 0)
              Icon(Icons.block,
                  size: 28,
                  color: AppColors.secondaryText.withValues(alpha: 0.5))
            else
              SizedBox(
                width: 42,
                height: 42,
                child: AvatarWidget(
                  animateEffects: false,
                  config: _config.copyWith(cheekStyle: index),
                  size: 42,
                  showBackground: false,
                ),
              ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(cheekStyle: index)),
    );
  }

  // ── Nose Style ─────────────────────────────────────────────────────

  Widget _buildNoseOptions() {
    return _optionGrid(
      itemCount: noseStyleOptions.length,
      selectedIndex: _config.noseStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: AvatarWidget(
                animateEffects: false,
                config: _config.copyWith(noseStyle: index),
                size: 42,
                showBackground: false,
              ),
            ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(noseStyle: index)),
    );
  }

  // ── Glasses ─────────────────────────────────────────────────────────

  Widget _buildGlassesOptions() {
    return _optionGrid(
      itemCount: glassesStyleOptions.length,
      selectedIndex: _config.glassesStyle,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (index == 0)
              Icon(Icons.block,
                  size: 28,
                  color: AppColors.secondaryText.withValues(alpha: 0.5))
            else
              SizedBox(
                width: 42,
                height: 42,
                child: AvatarWidget(
                  animateEffects: false,
                  config: _config.copyWith(glassesStyle: index),
                  size: 42,
                  showBackground: false,
                ),
              ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(glassesStyle: index)),
    );
  }

  // ── Face Paint ──────────────────────────────────────────────────────

  Widget _buildFacePaintOptions() {
    return _optionGrid(
      itemCount: facePaintOptions.length,
      selectedIndex: _config.facePaint,
      builder: (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (index == 0)
              Icon(Icons.block,
                  size: 28,
                  color: AppColors.secondaryText.withValues(alpha: 0.5))
            else
              SizedBox(
                width: 42,
                height: 42,
                child: AvatarWidget(
                  animateEffects: false,
                  config: _config.copyWith(facePaint: index),
                  size: 42,
                  showBackground: false,
                ),
              ),
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(facePaint: index)),
    );
  }

  // ── Accessories ────────────────────────────────────────────────────

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

  Widget _buildAccessoryOptions() {
    return _optionGrid(
      itemCount: accessoryOptions.length,
      selectedIndex: _config.accessory,
      builder: (index) {
        final opt = accessoryOptions[index];
        final locked = _isAccessoryLocked(opt);
        return _OptionTileContent(
          locked: locked,
          hint: opt.unlock?.hint,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (index == 0)
                Icon(Icons.block,
                    size: 28,
                    color: AppColors.secondaryText.withValues(alpha: 0.5))
              else
                SizedBox(
                  width: 42,
                  height: 42,
                  child: AvatarWidget(
                  animateEffects: false,
                    config: _config.copyWith(accessory: index),
                    size: 42,
                    showBackground: false,
                  ),
                ),
            ],
          ),
        );
      },
      onTap: (index) {
        final opt = accessoryOptions[index];
        if (!_isAccessoryLocked(opt)) {
          _updateConfig(_config.copyWith(accessory: index));
        }
      },
    );
  }

  // ── Background Color ───────────────────────────────────────────────

  Widget _buildBgColorOptions() {
    return _optionGrid(
      itemCount: bgColorOptions.length,
      selectedIndex: _config.bgColor,
      builder: (index) {
        final opt = bgColorOptions[index];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
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
          ],
        );
      },
      onTap: (index) => _updateConfig(_config.copyWith(bgColor: index)),
    );
  }

  // ── Shared Grid Builder ────────────────────────────────────────────

  Widget _optionGrid({
    required int itemCount,
    required int selectedIndex,
    required Widget Function(int index) builder,
    required void Function(int index) onTap,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.violet : AppColors.border,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.30),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
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
        );
      },
    );
  }

  // ── Done Button ────────────────────────────────────────────────────

  Widget _buildDoneButton() {
    return Center(
      child: GestureDetector(
        onTap: _save,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 300.ms)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.elasticOut);
  }

}

// ── Category data ───────────────────────────────────────────────────

class _Category {
  final String label;
  final IconData icon;

  const _Category(this.label, this.icon);
}

// ── Locked option overlay ───────────────────────────────────────────

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

    // Extract number from hint (e.g. "25 words!" → 25) for star display
    final starCount = hint != null
        ? RegExp(r'\d+').firstMatch(hint!)?.group(0)
        : null;

    return Stack(
      children: [
        Opacity(opacity: 0.3, child: child),
        Positioned.fill(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_rounded,
                size: 18,
                color: AppColors.secondaryText.withValues(alpha: 0.7),
              ),
              if (starCount != null) ...[
                const SizedBox(height: 2),
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
            ],
          ),
        ),
      ],
    );
  }
}

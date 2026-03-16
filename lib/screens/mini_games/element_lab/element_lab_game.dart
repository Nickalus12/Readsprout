import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/audio_service.dart';
import '../../../services/progress_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/haptics.dart';

import 'element_registry.dart';
import 'simulation_engine.dart';
import 'element_behaviors.dart';
import 'pixel_renderer.dart';
import 'sandbox_input_handler.dart';
import 'element_lab_painters.dart';

// ---------------------------------------------------------------------------
// Element Lab — A kid-friendly physics sandbox (inspired by Powder Game)
// ---------------------------------------------------------------------------

/// SVG icon file names per element type (index = El.* constant).
const List<String> _elementSvgNames = [
  '',          // 0  empty
  'sand',      // 1
  'water',     // 2
  'fire',      // 3
  'ice',       // 4
  'lightning',  // 5
  'seed',      // 6
  'stone',     // 7
  'tnt',       // 8
  'rainbow',   // 9
  'mud',       // 10
  'steam',     // 11
  'ant',       // 12
  'oil',       // 13
  'acid',      // 14
  'glass',     // 15
  'dirt',      // 16
  'plant',     // 17
  'lava',      // 18
  'snow',      // 19
  'wood',      // 20
  'metal',     // 21
  'smoke',     // 22
  'bubble',    // 23
  'ash',       // 24
];

/// Cost in star coins for initial 3-minute session.
const int kElementLabCost = 5;

/// Cost in star coins for a 2-minute extension.
const int kExtensionCost = 3;

/// Initial session duration.
const Duration kSessionDuration = Duration(minutes: 3);

/// Extension duration.
const Duration kExtensionDuration = Duration(minutes: 2);

class ElementLabGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final bool freePlay;

  const ElementLabGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.freePlay = false,
  });

  @override
  State<ElementLabGame> createState() => _ElementLabGameState();
}

class _ElementLabGameState extends State<ElementLabGame>
    with SingleTickerProviderStateMixin {
  // -- Core systems ----------------------------------------------------------
  late SimulationEngine _engine;
  late PixelRenderer _renderer;
  late SandboxInputHandler _input;

  // -- Rendering buffer ------------------------------------------------------
  final ValueNotifier<ui.Image?> _frameImageNotifier = ValueNotifier(null);

  // -- Animation / ticker ---------------------------------------------------
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int get _frameCount => _engine.frameCount;

  // -- UI state --------------------------------------------------------------
  int _selectedTab = 0;
  bool _isPaused = false;
  bool _showElementInfo = false;
  int _infoElement = El.sand;
  bool _showSeedPopup = false;

  // -- Canvas layout (computed per frame in _buildCanvas) -------------------

  // -- Physics manipulation --------------------------------------------------
  int _shakeCooldown = 0;
  Offset _shakeOffset = Offset.zero;

  // -- Day/Night system -------------------------------------------------------
  bool _isNight = false;
  double _dayNightT = 0.0;

  // -- Session timer ---------------------------------------------------------
  late int _remainingSeconds;
  Timer? _sessionTimer;
  bool _sessionExpired = false;
  bool _showTimeWarning = false;
  String _timeWarningText = '';

  // -- Audio narration (mute toggle) ----------------------------------------
  bool _isMuted = false;

  bool _gridInitialized = false;
  bool _imageDecodeInFlight = false;

  @override
  void initState() {
    super.initState();
    _engine = SimulationEngine();
    _renderer = PixelRenderer(_engine);
    _input = SandboxInputHandler(_engine, _renderer);

    _remainingSeconds = widget.freePlay
        ? const Duration(minutes: 999).inSeconds
        : kSessionDuration.inSeconds;
    _ticker = createTicker(_onTick);
    _startSessionTimer();
    _loadMutePreference();
  }

  String get _muteKey => 'element_lab_muted_${widget.playerName}';

  Future<void> _loadMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isMuted = prefs.getBool(_muteKey) ?? false;
      });
    }
  }

  Future<void> _toggleMute() async {
    // Speak feedback BEFORE actually muting so the child hears it
    if (!_isMuted) {
      // About to mute — say "off" while still unmuted
      await widget.audioService.playWord('off');
    }
    setState(() => _isMuted = !_isMuted);
    Haptics.tap();
    if (!_isMuted) {
      // Just unmuted — say "on"
      _speakLabel('on');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteKey, _isMuted);
  }

  void _toggleDayNight() {
    setState(() => _isNight = !_isNight);
    _engine.isNight = _isNight;
    _engine.markAllDirty();
    Haptics.tap();
    _speakLabel(_isNight ? 'night' : 'day');
  }

  /// Map display names to audio file names when they differ.
  static const Map<String, String> _displayToAudioName = {
    'zap': 'lightning',    // display "Zap" but audio is "lightning"
    'shroom': 'mushroom',  // seed sub-type display name
  };

  Future<void> _speakElementName(int elType) async {
    if (_isMuted || elType == El.empty) return;
    final displayName = elType == El.eraser
        ? 'eraser'
        : elementNames[elType.clamp(0, elementNames.length - 1)].toLowerCase();
    if (displayName.isEmpty) return;

    // Resolve audio name: use mapping if exists, else display name
    final audioName = _displayToAudioName[displayName] ?? displayName;

    if (speakableWords.contains(audioName)) {
      await widget.audioService.playWord(audioName);
    } else if (speakableWords.contains(displayName)) {
      await widget.audioService.playWord(displayName);
    } else {
      for (final letter in displayName.split('')) {
        if (!mounted || _isMuted) break;
        await widget.audioService.playLetter(letter);
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _speakWord(String word) async {
    if (_isMuted) return;
    await widget.audioService.playWord(word);
  }

  /// Speak a UI label — tries the word audio file first, falls back to
  /// spelling it letter-by-letter so every button gives audible feedback.
  Future<void> _speakLabel(String text) async {
    if (_isMuted) return;
    final lower = text.toLowerCase();
    // Try full word audio first
    final ok = await widget.audioService.playWord(lower);
    if (ok) return;
    // Fallback: spell it out letter by letter
    for (final letter in lower.split('')) {
      if (!mounted || _isMuted) break;
      await widget.audioService.playLetter(letter);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _initGrid(double canvasW, double canvasH) {
    final baseCellSize = (canvasW / 160).clamp(1.0, 4.0);
    final gridW = (canvasW / baseCellSize).floor().clamp(40, 400);
    final gridH = (canvasH / baseCellSize).floor().clamp(40, 600);

    _engine.init(gridW, gridH);
    _renderer.init();
    _renderer.generateStars();

    // Canvas layout is recomputed every frame in _buildCanvas.
    _input.cellSize = baseCellSize;

    _gridInitialized = true;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused || _sessionExpired) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds == 60) {
          _showTimeWarning = true;
          _timeWarningText = '1 Minute Left!';
          if (!_isMuted) {
            _speakWord('one');
            Future.delayed(const Duration(milliseconds: 400), () {
              if (!mounted) return;
              _speakWord('minute');
            });
          }
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        } else if (_remainingSeconds == 30) {
          _showTimeWarning = true;
          _timeWarningText = '30 Seconds Left!';
          if (!_isMuted) {
            _speakWord('thirty');
            Future.delayed(const Duration(milliseconds: 400), () {
              if (!mounted) return;
              _speakWord('seconds');
            });
          }
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        }

        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _sessionExpired = true;
          if (!_isMuted) {
            _speakWord('time');
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _ticker.dispose();
    _frameImageNotifier.value?.dispose();
    _frameImageNotifier.dispose();
    super.dispose();
  }

  // ── Tick callback ────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_gridInitialized || _isPaused || _sessionExpired) return;

    // Throttle to ~30 fps
    final dt = elapsed - _lastTick;
    if (dt.inMilliseconds < 30) return;
    _lastTick = elapsed;
    _engine.frameCount++;

    if (_shakeCooldown > 0) _shakeCooldown--;

    // Smooth day/night transition (60 frames = 2 seconds at 30fps)
    final targetT = _isNight ? 1.0 : 0.0;
    if ((_dayNightT - targetT).abs() > 0.001) {
      _dayNightT += (_isNight ? 1.0 : -1.0) / 60.0;
      _dayNightT = _dayNightT.clamp(0.0, 1.0);
    }
    _renderer.dayNightT = _dayNightT;

    _engine.applyWind();
    _engine.step(simulateElement);
    _renderer.tickMicroParticles();
    _renderer.renderPixels();

    if (!_imageDecodeInFlight) {
      _imageDecodeInFlight = true;
      _renderer.buildImage().then((newImage) {
        _imageDecodeInFlight = false;
        if (!mounted) {
          newImage.dispose();
          return;
        }
        final oldImage = _frameImageNotifier.value;
        _frameImageNotifier.value = newImage;
        oldImage?.dispose();
      }).catchError((e) {
        _imageDecodeInFlight = false;
      });
    }
  }

  void _doShake() {
    if (_shakeCooldown > 0) return;
    _shakeCooldown = 60;
    _speakLabel('shake');
    _engine.doShake();

    // Powerful multi-frame screen shake with escalating haptics
    Haptics.tap();
    final rng = _engine.rng;
    // Frame 1: big jolt
    setState(() {
      _shakeOffset = Offset(
        (rng.nextDouble() - 0.5) * 12,
        (rng.nextDouble() - 0.5) * 12,
      );
    });
    // Frame 2: reverse jolt
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      Haptics.tap();
      setState(() => _shakeOffset = Offset(
        -_shakeOffset.dx * 0.8 + (rng.nextDouble() - 0.5) * 4,
        -_shakeOffset.dy * 0.8 + (rng.nextDouble() - 0.5) * 4,
      ));
    });
    // Frame 3: smaller wobble
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() => _shakeOffset = Offset(
        (rng.nextDouble() - 0.5) * 6,
        (rng.nextDouble() - 0.5) * 6,
      ));
    });
    // Frame 4: tiny settle
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      Haptics.tap();
      setState(() => _shakeOffset = Offset(
        (rng.nextDouble() - 0.5) * 2,
        (rng.nextDouble() - 0.5) * 2,
      ));
    });
    // Frame 5: done
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _shakeOffset = Offset.zero);
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    Haptics.tap();
    _speakLabel(_isPaused ? 'pause' : 'play');
  }

  void _addMoreTime() {
    if (!widget.freePlay) {
      final balance = widget.progressService.starCoins;
      if (balance < kExtensionCost) return;
      widget.progressService.spendStarCoins(kExtensionCost);
    }
    setState(() {
      _remainingSeconds += widget.freePlay
          ? const Duration(minutes: 999).inSeconds
          : kExtensionDuration.inSeconds;
      _sessionExpired = false;
    });
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _timerColor() {
    if (_remainingSeconds > 60) return AppColors.emerald;
    if (_remainingSeconds > 30) return const Color(0xFFFFBB33);
    return AppColors.error;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Transform.translate(
              offset: _shakeOffset,
              child: Column(
              children: [
                RepaintBoundary(child: _buildTopBar()),
                Expanded(
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (!_gridInitialized) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _initGrid(constraints.maxWidth, constraints.maxHeight);
                          });
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.electricBlue,
                            ),
                          );
                        }
                        return _buildCanvas(constraints);
                      },
                    ),
                  ),
                ),
                RepaintBoundary(child: _buildPalette()),
                RepaintBoundary(child: _buildBottomBar()),
              ],
            ),
            ),
            if (_showTimeWarning) _buildTimeWarningOverlay(),
            if (_sessionExpired) _buildSessionExpiredOverlay(),
            if (_showElementInfo) _buildElementInfoOverlay(),
            if (_isPaused && !_sessionExpired) _buildPauseOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final timerColor = _timerColor();
    final isPulsing = _remainingSeconds <= 30 && !_sessionExpired;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final iconSz = compact ? 18.0 : 22.0;
    final btnSz = compact ? 32.0 : 40.0;
    final fontSz = compact ? 14.0 : 18.0;
    final smallFont = compact ? 11.0 : 14.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primaryText,
              iconSize: iconSz,
              padding: EdgeInsets.zero,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 2),
            Text(
              'Element Lab',
              style: AppFonts.fredoka(
                fontSize: fontSz,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: _toggleMute,
              icon: Icon(
                _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: _isMuted
                    ? AppColors.secondaryText.withValues(alpha: 0.5)
                    : AppColors.electricBlue,
              ),
              iconSize: iconSz,
              padding: EdgeInsets.zero,
              tooltip: _isMuted ? 'Sound on' : 'Sound off',
            ),
          ),
          SizedBox(
            width: btnSz,
            height: btnSz,
            child: IconButton(
              onPressed: _toggleDayNight,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: 0.0, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  key: ValueKey(_isNight),
                  color: _isNight
                      ? const Color(0xFF8888CC)
                      : const Color(0xFFFFAA33),
                ),
              ),
              iconSize: iconSz,
              padding: EdgeInsets.zero,
              tooltip: _isNight ? 'Switch to day' : 'Switch to night',
            ),
          ),
          const Spacer(),
          // Session timer
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: isPulsing ? 1.15 : 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: isPulsing
                    ? 1.0 + 0.15 * sin(_frameCount * 0.15)
                    : 1.0,
                child: child,
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 3),
              decoration: BoxDecoration(
                color: timerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: timerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_rounded, color: timerColor, size: compact ? 13 : 16),
                  const SizedBox(width: 3),
                  Text(
                    _formatTime(_remainingSeconds),
                    style: AppFonts.fredoka(
                      fontSize: smallFont,
                      fontWeight: FontWeight.w700,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 4 : 8),
          // Star coin balance
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.starGold.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded,
                    color: AppColors.starGold, size: compact ? 13 : 16),
                const SizedBox(width: 3),
                Text(
                  '${widget.progressService.starCoins}',
                  style: AppFonts.fredoka(
                    fontSize: smallFont,
                    fontWeight: FontWeight.w600,
                    color: AppColors.starGold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;
    final displayCellW = viewW / _engine.gridW;
    final displayCellH = viewH / _engine.gridH;
    final displayCell = displayCellW < displayCellH ? displayCellW : displayCellH;
    final displayW = _engine.gridW * displayCell;
    final displayH = _engine.gridH * displayCell;
    final displayLeft = (viewW - displayW) / 2;
    final displayTop = (viewH - displayH) / 2;

    // Keep input handler in sync for touch mapping
    _input.cellSize = displayCell;
    _input.canvasLeft = displayLeft;
    _input.canvasTop = displayTop;

    return GestureDetector(
      onPanStart: (d) => _input.handlePanStart(d, _sessionExpired),
      onPanUpdate: (d) => _input.handlePanUpdate(d, _sessionExpired),
      onPanEnd: (d) => _input.handlePanEnd(d),
      onTapDown: (d) {
        if (_showSeedPopup) setState(() => _showSeedPopup = false);
        _input.handleTapDown(d, _sessionExpired);
      },
      onLongPressStart: (d) => _input.handleLongPressStart(d, _sessionExpired),
      onLongPressMoveUpdate: (d) => _input.handleLongPressMoveUpdate(d, _sessionExpired),
      onLongPressEnd: (d) => _input.handleLongPressEnd(d),
      child: Container(
        color: AppColors.background,
        width: viewW,
        height: viewH,
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: _frameImageNotifier,
          builder: (context, frameImage, _) {
            return CustomPaint(
              painter: GridPainter(
                image: frameImage,
                canvasLeft: displayLeft,
                canvasTop: displayTop,
                canvasPixelW: displayW,
                canvasPixelH: displayH,
                lightningFlash: _engine.lightningFlashFrames > 0,
              ),
              size: Size(viewW, viewH),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPalette() {
    final currentTabElements = tabElements[_selectedTab];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final tabH = compact ? 26.0 : 32.0;
    final chipH = compact ? 48.0 : 60.0;
    final tabIconSz = compact ? 13.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar
          SizedBox(
            height: tabH,
            child: Row(
              children: [
                for (int i = 0; i < tabIcons.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedTab = i);
                        Haptics.tap();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedTab == i
                              ? AppColors.electricBlue.withValues(alpha: 0.15)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: _selectedTab == i
                                  ? AppColors.electricBlue
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            tabIcons[i],
                            size: tabIconSz,
                            color: _selectedTab == i
                                ? AppColors.electricBlue
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Element chips for selected tab
          SizedBox(
            height: chipH,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final elType in currentTabElements)
                    if (elType == El.eraser)
                      _buildEraserChip()
                    else if (elType == El.seed)
                      _buildSeedChip()
                    else
                      _buildElementChip(elType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElementChip(int elType) {
    final isSelected = _input.selectedElement == elType;
    final color = baseColors[elType.clamp(0, baseColors.length - 1)];
    final name = elementNames[elType.clamp(0, elementNames.length - 1)];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;

    return GestureDetector(
      onTap: () {
        setState(() => _input.selectedElement = elType);
        Haptics.tap();
        _speakElementName(elType);
      },
      onLongPress: () {
        setState(() {
          _showElementInfo = true;
          _infoElement = elType;
        });
        Haptics.tap();
        _speakElementName(elType);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: hMargin),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.3)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: dotSz,
              height: dotSz,
              child: _elementSvgNames.length > elType &&
                      _elementSvgNames[elType].isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(2),
                      child: SvgPicture.asset(
                        'assets/icons/elements/${_elementSvgNames[elType]}.svg',
                        fit: BoxFit.contain,
                        placeholderBuilder: (_) => _colorDotFallback(dotSz - 4, color),
                      ),
                    )
                  : _colorDotFallback(dotSz, color),
            ),
            const SizedBox(height: 1),
            Text(
              name,
              style: AppFonts.fredoka(
                fontSize: labelSz,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback colored circle when SVG is unavailable.
  Widget _colorDotFallback(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
    );
  }

  Widget _buildEraserChip() {
    final isSelected = _input.selectedElement == El.eraser;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final iconSz = compact ? 11.0 : 14.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;

    return GestureDetector(
      onTap: () {
        setState(() => _input.selectedElement = El.eraser);
        Haptics.tap();
        _speakElementName(El.eraser);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: hMargin),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.error.withValues(alpha: 0.2)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.error : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: dotSz,
              height: dotSz,
              child: SvgPicture.asset(
                'assets/icons/elements/eraser.svg',
                width: dotSz,
                height: dotSz,
                placeholderBuilder: (_) => Icon(
                  Icons.cleaning_services_rounded,
                  size: iconSz,
                  color: AppColors.error,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Erase',
              style: AppFonts.fredoka(
                fontSize: labelSz,
                fontWeight: FontWeight.w500,
                color:
                    isSelected ? AppColors.error : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeedChip() {
    final isSelected = _input.selectedElement == El.seed;
    final color = baseColors[El.seed];
    const seedNames = ['', 'Grass', 'Flower', 'Tree', 'Shroom', 'Vine'];
    const seedColors = [
      Colors.transparent,
      Color(0xFF33CC33), // grass
      Color(0xFFFF88CC), // flower
      Color(0xFF8B6914), // tree
      Color(0xFFCC4444), // mushroom
      Color(0xFF33AA33), // vine
    ];
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final dotSz = compact ? 18.0 : 24.0;
    final iconSz = compact ? 11.0 : 14.0;
    final labelSz = compact ? 8.0 : 9.0;
    final hPad = compact ? 4.0 : 6.0;
    final hMargin = compact ? 2.0 : 4.0;
    final popupItemW = compact ? 34.0 : 40.0;
    final popupItemH = compact ? 40.0 : 48.0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _input.selectedElement = El.seed;
          _showSeedPopup = !_showSeedPopup;
        });
        Haptics.tap();
        _speakElementName(El.seed);
      },
      onLongPress: () {
        setState(() { _showElementInfo = true; _infoElement = El.seed; });
        Haptics.tap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.symmetric(horizontal: hMargin),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.3) : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: dotSz, height: dotSz,
                  child: SvgPicture.asset(
                    'assets/icons/elements/seed.svg',
                    width: dotSz,
                    height: dotSz,
                    placeholderBuilder: (_) => Icon(Icons.eco_rounded, size: iconSz, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isSelected && _input.selectedSeedType > 0
                      ? seedNames[_input.selectedSeedType]
                      : 'Seed',
                  style: AppFonts.fredoka(fontSize: labelSz, fontWeight: FontWeight.w600,
                    color: isSelected
                        ? seedColors[_input.selectedSeedType.clamp(0, 5)]
                        : AppColors.secondaryText),
                ),
              ],
            ),
          ),
          // Seed type popup
          if (_showSeedPopup && isSelected)
            Positioned(
              bottom: compact ? 52 : 64,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.4), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int st = 1; st <= 5; st++)
                      GestureDetector(
                        onTap: () {
                          setState(() { _input.selectedSeedType = st; _showSeedPopup = false; });
                          Haptics.tap();
                          // Speak the seed type name (spell it out)
                          final seedWord = seedNames[st].toLowerCase();
                          final audioName = _displayToAudioName[seedWord] ?? seedWord;
                          if (speakableWords.contains(audioName)) {
                            _speakWord(audioName);
                          } else if (speakableWords.contains(seedWord)) {
                            _speakWord(seedWord);
                          } else {
                            // Spell it out letter by letter
                            () async {
                              for (final letter in seedWord.split('')) {
                                if (!mounted || _isMuted) break;
                                await widget.audioService.playLetter(letter);
                                await Future.delayed(const Duration(milliseconds: 250));
                              }
                            }();
                          }
                        },
                        child: Container(
                          width: popupItemW, height: popupItemH,
                          margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
                          decoration: BoxDecoration(
                            color: _input.selectedSeedType == st
                                ? seedColors[st].withValues(alpha: 0.25)
                                : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _input.selectedSeedType == st ? seedColors[st] : AppColors.border,
                              width: _input.selectedSeedType == st ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CustomPaint(
                                size: Size(compact ? 18 : 24, compact ? 18 : 24),
                                painter: SeedIconPainter(st),
                              ),
                              Text(
                                seedNames[st],
                                style: AppFonts.fredoka(fontSize: compact ? 6 : 7, fontWeight: FontWeight.w500,
                                  color: _input.selectedSeedType == st ? seedColors[st] : AppColors.secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final barH = compact ? 42.0 : 50.0;
    final hPad = compact ? 4.0 : 8.0;
    final chipSz = compact ? 28.0 : 34.0;
    final iconSz = compact ? 14.0 : 17.0;
    final labelSz = compact ? 6.5 : 8.0;

    // ── Tap-animated button wrapper ──────────────────────────────────────
    Widget tapBtn({
      required Widget child,
      required VoidCallback? onTap,
      String? tooltip,
    }) {
      return Tooltip(
        message: tooltip ?? '',
        waitDuration: const Duration(milliseconds: 400),
        child: _TapScaleButton(
          onTap: onTap,
          child: child,
        ),
      );
    }

    // ── Chip button (brush size / brush mode / labeled icon) ─────────────
    Widget chipBtn({
      required bool isSelected,
      required Widget child,
      required VoidCallback onTap,
      required String tooltip,
      Color activeColor = AppColors.electricBlue,
    }) {
      return tapBtn(
        tooltip: tooltip,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: chipSz,
          height: chipSz,
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.2)
                : AppColors.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : AppColors.border.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: activeColor.withValues(alpha: 0.25), blurRadius: 6)]
                : null,
          ),
          child: child,
        ),
      );
    }

    // ── Brush size ───────────────────────────────────────────────────────
    Widget buildBrushSizeBtn(int size) {
      final label = size == 1 ? 'S' : size == 3 ? 'M' : 'L';
      final spoken = size == 1 ? 'small' : size == 3 ? 'medium' : 'big';
      final isSelected = _input.brushSize == size;
      return chipBtn(
        isSelected: isSelected,
        tooltip: '${spoken[0].toUpperCase()}${spoken.substring(1)} brush',
        onTap: () {
          setState(() => _input.brushSize = size);
          Haptics.tap();
          _speakLabel(spoken);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: size.toDouble() * 2 + 2,
              height: size.toDouble() * 2 + 2,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.electricBlue : AppColors.secondaryText,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 1),
            Text(label, style: AppFonts.fredoka(
              fontSize: labelSz,
              fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.electricBlue : AppColors.secondaryText,
            )),
          ],
        ),
      );
    }

    // ── Brush mode ───────────────────────────────────────────────────────
    Widget buildBrushModeBtn(int mode, IconData icon, String label) {
      final isSelected = _input.brushMode == mode;
      return chipBtn(
        isSelected: isSelected,
        tooltip: '${label[0].toUpperCase()}${label.substring(1)} brush',
        onTap: () {
          setState(() => _input.brushMode = mode);
          Haptics.tap();
          _speakLabel(label);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSz, color: isSelected ? AppColors.electricBlue : AppColors.secondaryText),
            const SizedBox(height: 1),
            Text(label, style: AppFonts.fredoka(
              fontSize: labelSz,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.electricBlue : AppColors.secondaryText,
            )),
          ],
        ),
      );
    }

    // ── Icon action button (gravity, wind, shake, undo, etc.) ────────────
    Widget actionBtn({
      required VoidCallback? onTap,
      required IconData icon,
      required String label,
      required Color activeColor,
      bool isActive = true,
      String? tooltip,
    }) {
      final color = onTap == null
          ? AppColors.secondaryText.withValues(alpha: 0.3)
          : isActive ? activeColor : AppColors.secondaryText;
      return tapBtn(
        tooltip: tooltip ?? label,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: chipSz,
          height: chipSz,
          decoration: BoxDecoration(
            color: isActive && onTap != null
                ? activeColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSz, color: color),
              const SizedBox(height: 1),
              Text(label, style: AppFonts.fredoka(
                fontSize: labelSz,
                fontWeight: FontWeight.w600,
                color: color,
              )),
            ],
          ),
        ),
      );
    }

    // ── Group divider ────────────────────────────────────────────────────
    Widget divider() {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
        child: Container(
          width: 1,
          height: barH * 0.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.border.withValues(alpha: 0.0),
                AppColors.border.withValues(alpha: 0.5),
                AppColors.border.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      );
    }

    final gravUp = _engine.gravityDir == -1;
    final windVal = _engine.windForce;

    return Container(
      height: barH,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // ── BRUSH GROUP ──────────────────────────────────────────
            for (final size in const [1, 3, 5])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: buildBrushSizeBtn(size),
              ),
            divider(),
            buildBrushModeBtn(0, Icons.circle, 'dot'),
            const SizedBox(width: 2),
            buildBrushModeBtn(1, Icons.horizontal_rule_rounded, 'line'),
            const SizedBox(width: 2),
            buildBrushModeBtn(2, Icons.grain_rounded, 'spray'),
            divider(),
            // ── PHYSICS GROUP ────────────────────────────────────────
            actionBtn(
              onTap: () {
                setState(() => _engine.gravityDir = -_engine.gravityDir);
                _engine.markAllDirty();
                Haptics.tap();
                _speakLabel(_engine.gravityDir == -1 ? 'up' : 'down');
              },
              icon: gravUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              label: gravUp ? 'up' : 'down',
              activeColor: AppColors.starGold,
              isActive: gravUp,
              tooltip: 'Gravity ${gravUp ? "up" : "down"}',
            ),
            // Wind controls
            actionBtn(
              onTap: () {
                setState(() => _engine.windForce = (windVal - 1).clamp(-3, 3));
                _engine.markAllDirty();
                Haptics.tap();
                _speakLabel(_engine.windForce == 0 ? 'no' : 'left');
              },
              icon: Icons.chevron_left_rounded,
              label: 'wind',
              activeColor: AppColors.electricBlue,
              isActive: windVal < 0,
              tooltip: 'Wind left',
            ),
            // Wind value badge
            SizedBox(
              width: compact ? 18 : 22,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: windVal != 0
                        ? AppColors.electricBlue.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: windVal != 0
                          ? AppColors.electricBlue.withValues(alpha: 0.4)
                          : AppColors.border.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    '$windVal',
                    style: AppFonts.fredoka(
                      fontSize: compact ? 8 : 10,
                      fontWeight: FontWeight.w700,
                      color: windVal != 0
                          ? AppColors.electricBlue
                          : AppColors.secondaryText.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            actionBtn(
              onTap: () {
                setState(() => _engine.windForce = (windVal + 1).clamp(-3, 3));
                _engine.markAllDirty();
                Haptics.tap();
                _speakLabel(_engine.windForce == 0 ? 'no' : 'right');
              },
              icon: Icons.chevron_right_rounded,
              label: 'wind',
              activeColor: AppColors.electricBlue,
              isActive: windVal > 0,
              tooltip: 'Wind right',
            ),
            // Shake — prominent with special styling
            actionBtn(
              onTap: _shakeCooldown <= 0 ? _doShake : null,
              icon: Icons.vibration_rounded,
              label: 'shake',
              activeColor: const Color(0xFFFF8C00), // orange for emphasis
              isActive: _shakeCooldown <= 0,
              tooltip: 'Shake everything!',
            ),
            divider(),
            // ── ACTION GROUP ─────────────────────────────────────────
            actionBtn(
              onTap: _input.undoHistory.isNotEmpty ? () {
                _input.undo();
                Haptics.tap();
                _speakLabel('undo');
              } : null,
              icon: Icons.undo_rounded,
              label: 'undo',
              activeColor: AppColors.electricBlue,
            ),
            actionBtn(
              onTap: _togglePause,
              icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: _isPaused ? 'play' : 'stop',
              activeColor: _isPaused ? AppColors.emerald : AppColors.electricBlue,
              isActive: true,
              tooltip: _isPaused ? 'Play' : 'Pause',
            ),
            actionBtn(
              onTap: () {
                _speakLabel('clear');
                _input.clearGrid();
                Haptics.tap();
              },
              icon: Icons.delete_outline_rounded,
              label: 'clear',
              activeColor: AppColors.error,
              isActive: true,
              tooltip: 'Clear everything',
            ),
          ],
        ),
      ),
    );
  }

  // ── Overlay widgets ────────────────────────────────────────────────────

  Widget _buildTimeWarningOverlay() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 32, vertical: compact ? 10 : 16),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _timerColor().withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: Text(
              _timeWarningText,
              style: AppFonts.fredoka(
                fontSize: compact ? 20 : 28,
                fontWeight: FontWeight.w700,
                color: _timerColor(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionExpiredOverlay() {
    final canAfford = widget.progressService.starCoins >= kExtensionCost;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final hMargin = compact ? 16.0 : 32.0;
    final pad = compact ? 16.0 : 24.0;

    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.9),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: hMargin),
            padding: EdgeInsets.all(pad),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.electricBlue.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_rounded,
                  color: AppColors.starGold,
                  size: compact ? 36 : 48,
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  "Time's Up!",
                  style: AppFonts.fredoka(
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Text(
                  'Your Element Lab session has ended.',
                  textAlign: TextAlign.center,
                  style: AppFonts.fredoka(
                    fontSize: compact ? 12 : 14,
                    color: AppColors.secondaryText,
                  ),
                ),
                SizedBox(height: compact ? 14 : 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAfford ? _addMoreTime : null,
                    icon: Icon(Icons.add_rounded, size: compact ? 16 : 20),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add 2 Min  ',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.star_rounded,
                            color: AppColors.starGold, size: compact ? 14 : 16),
                        Text(
                          ' $kExtensionCost',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.starGold,
                          ),
                        ),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? AppColors.electricBlue
                          : AppColors.surfaceVariant,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (!canAfford) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Complete words in Adventure Mode\nto earn more Star Coins!',
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 10 : 12,
                      color: AppColors.starGold.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 8 : 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Exit',
                      style: AppFonts.fredoka(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElementInfoOverlay() {
    final elType = _infoElement;
    final color = baseColors[elType.clamp(0, baseColors.length - 1)];
    final name = elementNames[elType.clamp(0, elementNames.length - 1)];
    final desc = elementDescriptions[elType] ?? 'A mysterious element.';
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    final hMargin = compact ? 24.0 : 48.0;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showElementInfo = false),
        child: Container(
          color: AppColors.background.withValues(alpha: 0.7),
          child: Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: hMargin),
              padding: EdgeInsets.all(compact ? 14 : 20),
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: compact ? 30 : 40,
                    height: compact ? 30 : 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    name,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 8),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 11 : 13,
                      color: AppColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  Text(
                    'Tap anywhere to close',
                    style: AppFonts.fredoka(
                      fontSize: compact ? 9 : 11,
                      color: AppColors.secondaryText.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;
    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pause_circle_filled_rounded,
                color: AppColors.electricBlue,
                size: compact ? 48 : 64,
              ),
              SizedBox(height: compact ? 10 : 16),
              Text(
                'Paused',
                style: AppFonts.fredoka(
                  fontSize: compact ? 24 : 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                '${_formatTime(_remainingSeconds)} remaining',
                style: AppFonts.fredoka(
                  fontSize: compact ? 13 : 16,
                  color: AppColors.secondaryText,
                ),
              ),
              SizedBox(height: compact ? 16 : 24),
              ElevatedButton.icon(
                onPressed: _togglePause,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Resume',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 24 : 32,
                    vertical: compact ? 8 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Exit Lab',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 12 : 14,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tap-scale animated button ─────────────────────────────────────────────
/// A button that briefly scales down on press for satisfying tactile feedback.
class _TapScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _TapScaleButton({required this.child, this.onTap});

  @override
  State<_TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<_TapScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _ctrl.forward() : null,
      onTapUp: widget.onTap != null
          ? (_) {
              _ctrl.reverse();
              widget.onTap!();
            }
          : null,
      onTapCancel: widget.onTap != null ? () => _ctrl.reverse() : null,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/avatar_options.dart';
import '../models/player_profile.dart';
import 'avatar_gyroscope.dart';
import '../theme/app_theme.dart';
import 'avatar_accessory_painters.dart';
import 'avatar_animation_system.dart';
import 'avatar_body_painters.dart' hide shirtColorOptions;
import 'avatar_effects_painters.dart';
import 'avatar_hair_painters.dart' show HairBackPainter, HairFrontPainter;
import 'avatar_skeleton.dart';

/// Avatar rendering engine — Pixar-quality character rendering in code.
///
/// Features:
/// - 3D skin shading (warm highlight → cool jaw shadow, ambient occlusion)
/// - Alive eyes (limbal ring, radial iris fibers, caustic patterns, dual
///   specular highlights, eyelid-sweep blink, pupil dilation, eye tracking)
/// - Gradient lips with individual teeth, tongue center-line gradient
/// - Nostril breathing micro-animation
/// - Gaussian-falloff cheek blush
/// - Curved bezier eyelashes, gradient eyebrows
/// - 5 AnimationControllers (breathing, blink, idle sway, pupil dilation, twinkle)
///
/// Layer order (bottom → top):
///   1. Background circle
///   2. Golden glow aura (GoldenGlowPainter)
///   3. Hair back layer (HairBackPainter)
///   4. Face (3D skin gradient, ears, chin shadow, nose-bridge AO)
///   5. Nose (with breathing nostril micro-anim)
///   6. Cheeks (gaussian radial blush)
///   7. Eyes (full iris detail, eyelid-sweep blink, pupil tracking)
///   8. Eyelashes (curved strokes)
///   9. Eyebrows (gradient fill)
///  10. Mouth (gradient lips, individual teeth, tongue center-line)
///  11. Face paint (FacePaintPainter)
///  12. Hair front layer (HairFrontPainter)
///  13. Glasses (GlassesPainter)
///  14. Accessories (accessoryPainter dispatcher)
///  15. Sparkle effects (SparklePainter)
// ═══════════════════════════════════════════════════════════════════════
//  AVATAR EXPRESSION SYSTEM
// ═══════════════════════════════════════════════════════════════════════

/// Expression states the avatar can show.
enum AvatarExpression {
  neutral,
  excited,    // wide eyes, big smile — word correct / level complete
  thinking,   // slightly squinted, pursed lips — wrong letter
  talking,    // mouth opens/closes rhythmically — during audio playback
  happy,      // gentle smile, slightly wider eyes — option selected in editor
  surprised,  // wide eyes, round 'O' mouth — unexpected events
}

/// External controller for driving avatar expressions from game/audio events.
///
/// Usage:
/// ```dart
/// final controller = AvatarController();
/// AvatarWidget(config: config, controller: controller);
/// controller.simulateTalking(duration: Duration(seconds: 2));
/// controller.setExpression(AvatarExpression.excited);
/// controller.setLookTarget(Offset(100, 200)); // eyes follow a point
/// ```
class AvatarController extends ChangeNotifier {
  AvatarExpression _expression = AvatarExpression.neutral;
  double _mouthOpenAmount = 0.0;
  Offset? _lookTarget;
  Timer? _expressionTimer;
  Timer? _talkingTimer;
  Timer? _talkCycleTimer;
  final _rng = Random();

  AvatarExpression get expression => _expression;
  double get mouthOpenAmount => _mouthOpenAmount;
  bool get isTalking => _expression == AvatarExpression.talking;

  /// Target point for eye tracking. Null = idle sway (default behavior).
  Offset? get lookTarget => _lookTarget;

  /// Set mouth openness directly (0.0 = closed, 1.0 = wide open).
  /// Use this for real-time lip sync when phoneme data is available.
  void setMouthOpenness(double value) {
    _mouthOpenAmount = value.clamp(0.0, 1.0);
    if (_expression != AvatarExpression.talking) {
      _expression = AvatarExpression.talking;
    }
    notifyListeners();
  }

  /// Shift pupil position toward a target point (null = center/idle sway).
  /// Coordinates are in the avatar widget's local space.
  void setLookTarget(Offset? target) {
    _lookTarget = target;
    notifyListeners();
  }

  /// Set an expression that auto-resets to neutral after [duration].
  void setExpression(AvatarExpression expr, {Duration duration = const Duration(seconds: 2)}) {
    _expressionTimer?.cancel();
    _expression = expr;
    notifyListeners();

    if (expr != AvatarExpression.neutral) {
      _expressionTimer = Timer(duration, () {
        _expression = AvatarExpression.neutral;
        _mouthOpenAmount = 0.0;
        notifyListeners();
      });
    }
  }

  /// Simulate talking with organic mouth movement for [duration].
  ///
  /// Uses randomized amplitude (0.3–0.9) and frequency (6–12 Hz) with
  /// perlin-like layering for natural feel. Ramps up over 100ms at start,
  /// ramps down over 100ms at end.
  void simulateTalking({Duration duration = const Duration(seconds: 2)}) {
    _expressionTimer?.cancel();
    _talkingTimer?.cancel();
    _talkCycleTimer?.cancel();

    _expression = AvatarExpression.talking;
    _mouthOpenAmount = 0.0;
    notifyListeners();

    final startMs = DateTime.now().millisecondsSinceEpoch;
    final durationMs = duration.inMilliseconds;
    const rampMs = 100.0; // ease in/out duration

    // Randomized per-session parameters for organic feel
    final baseFreq = 6.0 + _rng.nextDouble() * 6.0;   // 6–12 Hz
    final ampBase = 0.3 + _rng.nextDouble() * 0.3;     // 0.3–0.6 base
    final ampRange = 0.15 + _rng.nextDouble() * 0.15;  // variation range

    _talkCycleTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      final t = elapsed / 1000.0; // seconds

      // Ramp envelope: ease in at start, ease out at end
      double envelope = 1.0;
      if (elapsed < rampMs) {
        envelope = elapsed / rampMs;
      } else if (elapsed > durationMs - rampMs) {
        envelope = ((durationMs - elapsed) / rampMs).clamp(0.0, 1.0);
      }

      // Multi-layer oscillation for organic mouth movement
      final layer1 = sin(t * baseFreq * 2 * pi) * 0.5 + 0.5;
      final layer2 = sin(t * baseFreq * 1.3 * 2 * pi + 0.7) * 0.3 + 0.5;
      final layer3 = sin(t * baseFreq * 0.5 * 2 * pi + 2.1) * 0.2 + 0.5;

      // Combine layers with randomized amplitude
      final amplitude = ampBase + sin(t * 1.7) * ampRange;
      final raw = (layer1 * 0.5 + layer2 * 0.3 + layer3 * 0.2) * amplitude;

      _mouthOpenAmount = (raw * envelope).clamp(0.0, 1.0);
      notifyListeners();
    });

    _talkingTimer = Timer(duration, () {
      stopTalking();
    });
  }

  /// Stop any active talking animation and return to idle mouth.
  void stopTalking() {
    _talkCycleTimer?.cancel();
    _talkCycleTimer = null;
    _talkingTimer?.cancel();
    _talkingTimer = null;
    _mouthOpenAmount = 0.0;
    _expression = AvatarExpression.neutral;
    notifyListeners();
  }

  // ── Amplitude-based lip sync binding ─────────────────────────────────

  ValueNotifier<double>? _boundAmplitude;

  /// Bind to an amplitude [ValueNotifier] for real-time lip sync.
  ///
  /// While bound, the mouth openness tracks the notifier value directly.
  /// Call [unbindAmplitude] or [dispose] to disconnect.
  ///
  /// Typically called once during screen init:
  /// ```dart
  /// avatarController.bindAmplitude(audioService.mouthAmplitude);
  /// ```
  void bindAmplitude(ValueNotifier<double> amplitude) {
    unbindAmplitude();
    _boundAmplitude = amplitude;
    amplitude.addListener(_onAmplitudeChanged);
  }

  /// Disconnect from the amplitude notifier.
  void unbindAmplitude() {
    _boundAmplitude?.removeListener(_onAmplitudeChanged);
    _boundAmplitude = null;
  }

  void _onAmplitudeChanged() {
    final value = _boundAmplitude?.value ?? 0.0;
    if (value > 0.01) {
      // Audio is playing — drive mouth from amplitude
      _mouthOpenAmount = value.clamp(0.0, 1.0);
      if (_expression != AvatarExpression.talking) {
        _expression = AvatarExpression.talking;
      }
    } else if (_expression == AvatarExpression.talking) {
      // Audio stopped — return to neutral
      _mouthOpenAmount = 0.0;
      _expression = AvatarExpression.neutral;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unbindAmplitude();
    _expressionTimer?.cancel();
    _talkingTimer?.cancel();
    _talkCycleTimer?.cancel();
    super.dispose();
  }
}

class AvatarWidget extends StatefulWidget {
  final AvatarConfig config;
  final double size;
  final bool showBackground;

  /// When false, the tick loop is stopped and the avatar renders in its
  /// resting pose. Use this for editor preview thumbnails.
  final bool animateEffects;

  /// Optional controller for driving expressions from external events.
  final AvatarController? controller;

  /// Aspect ratio of the widget (width / height). Default ~3:4 for bust view.
  final double aspectRatio;

  /// Energy level for procedural idle animation (0.0 = sleepy, 1.0 = hyper).
  /// Driven by AvatarPersonalityService mood/energy.
  final double energyLevel;

  const AvatarWidget({
    super.key,
    required this.config,
    this.size = 80,
    this.showBackground = true,
    this.animateEffects = true,
    this.controller,
    this.aspectRatio = 0.75,
    this.energyLevel = 0.5,
  });

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget>
    with SingleTickerProviderStateMixin {
  // ── Skeleton & animation system ─────────────────────────────────────
  late final AvatarSkeleton _skeleton;
  late final AnimationMixer _mixer;
  late final AvatarTouchHandler _touchHandler;
  late final GyroscopeAdapter _gyro;

  // ── Single game-loop ticker ─────────────────────────────────────────
  late final AnimationController _tickCtrl;
  double _totalTime = 0.0;
  double _lastTickTime = 0.0;

  // ── Legacy animation values (derived from time each frame) ──────────
  double _breathingValue = 0.0;
  double _blinkValue = 0.0;
  double _idleSwayValue = 0.5;
  double _pupilDilationValue = 0.0;
  double _twinkleValue = 0.0;

  // ── Blink state machine ─────────────────────────────────────────────
  Timer? _blinkTimer;
  bool _isBlinking = false;
  double _blinkPhase = 0.0;
  final _rng = Random();

  // ── Repaint notifier ────────────────────────────────────────────────
  final _repaintNotifier = _TickNotifier();

  @override
  void initState() {
    super.initState();

    _skeleton = AvatarSkeleton();
    _mixer = AnimationMixer(ProceduralIdleSystem(energyLevel: widget.energyLevel));
    _touchHandler = AvatarTouchHandler();
    _gyro = GyroscopeAdapter();

    // Single game-loop controller — runs indefinitely
    _tickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    );
    _tickCtrl.addListener(_onTick);

    widget.controller?.addListener(_onControllerUpdate);

    if (widget.animateEffects) {
      _startLoop();
    } else {
      // Compute one frame at rest pose
      _skeleton.update(0.016);
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _startLoop() {
    _tickCtrl.repeat();
    _gyro.start();
    _scheduleNextBlink();
  }

  void _stopLoop() {
    _tickCtrl.stop();
    _gyro.stop();
    _blinkTimer?.cancel();
    _blinkTimer = null;
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final delayMs = 2000 + _rng.nextInt(4000);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || !widget.animateEffects) return;
      _isBlinking = true;
      _blinkPhase = 0.0;
    });
  }

  // ── Game loop — called every frame (~60fps) ─────────────────────────

  void _onTick() {
    if (!mounted) return;

    final now = _tickCtrl.value * 3600.0; // hours → seconds
    final dt = _lastTickTime == 0.0
        ? 0.016
        : (now - _lastTickTime).clamp(0.001, 0.05);
    _lastTickTime = now;
    _totalTime += dt;

    // 1. Advance the animation mixer (procedural idle + authored clips)
    final pose = _mixer.update(dt, _totalTime);

    // 2. Apply BonePose to skeleton animation offsets (proper channel)
    _skeleton.clearPose();
    _skeleton.applyPose(pose);

    // 3. Touch handler decay → apply to skeleton springs (physics channel)
    final touchPose = _touchHandler.update(dt);
    for (final entry in touchPose.transforms.entries) {
      final bone = _skeleton.bones[entry.key];
      if (bone == null) continue;
      final t = entry.value;
      bone.spring.applyForce(Offset(t.dx * 50, t.dy * 50));
    }

    // 4. Gyroscope head tilt → springs (physics channel)
    _gyro.update(dt);
    if (_gyro.isActive) {
      _skeleton.head.spring.applyForce(
        Offset(_gyro.headTiltX * 2.0, _gyro.headTiltY * 1.5),
      );
    }

    // 5. Step skeleton physics (springs + forward kinematics)
    _skeleton.update(dt);

    // 6. Derive legacy animation values from time for painters
    _breathingValue = sin(_totalTime * 2.094) * 0.5 + 0.5; // ~3s cycle
    _idleSwayValue = sin(_totalTime * 0.785) * 0.5 + 0.5;  // ~4s cycle
    _pupilDilationValue = sin(_totalTime * 0.628) * 0.5 + 0.5; // ~5s cycle
    _twinkleValue = (_totalTime / 3.0) % 1.0; // 3s loop

    // 7. Blink state machine
    if (_isBlinking) {
      _blinkPhase += dt / 0.15; // 150ms for each half
      if (_blinkPhase >= 2.0) {
        _isBlinking = false;
        _blinkPhase = 0.0;
        _blinkValue = 0.0;
        _scheduleNextBlink();
      } else if (_blinkPhase >= 1.0) {
        _blinkValue = 2.0 - _blinkPhase;
      } else {
        _blinkValue = _blinkPhase;
      }
    }

    // 8. Trigger repaint
    _repaintNotifier.notify();
    setState(() {});
  }

  @override
  void didUpdateWidget(AvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateEffects != oldWidget.animateEffects) {
      widget.animateEffects ? _startLoop() : _stopLoop();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
    if (widget.energyLevel != oldWidget.energyLevel) {
      _mixer.idle.energyLevel = widget.energyLevel;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    _blinkTimer?.cancel();
    _tickCtrl.removeListener(_onTick);
    _tickCtrl.dispose();
    _gyro.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  // ── Color helpers ──────────────────────────────────────────────────

  Color get _hairColor {
    final idx = widget.config.hairColor.clamp(0, hairColorOptions.length - 1);
    return hairColorOptions[idx].color;
  }

  Color get _skinColor => skinColorForIndex(widget.config.skinTone);

  Color get _eyeColor {
    final idx = widget.config.eyeColor.clamp(0, eyeColorOptions.length - 1);
    return eyeColorOptions[idx].color;
  }

  Color get _lipColor {
    final idx = widget.config.lipColor.clamp(0, lipColorOptions.length - 1);
    return lipColorOptions[idx].color;
  }

  // ── Face geometry ──────────────────────────────────────────────────

  double get _faceTop => 0.18;

  double get _faceHeightFraction {
    final shape = faceShapeOptions[
        widget.config.faceShape.clamp(0, faceShapeOptions.length - 1)];
    return 0.70 * shape.heightRatio;
  }

  // ── Bone/transform hierarchy helpers ─────────────────────────────

  /// Eyebrow vertical offset based on expression.
  /// Surprised/excited: brows UP, thinking: brows DOWN.
  double _browOffsetY(double size) {
    final expr = widget.controller?.expression ?? AvatarExpression.neutral;
    return switch (expr) {
      AvatarExpression.surprised => -size * 0.02,
      AvatarExpression.excited => -size * 0.015,
      AvatarExpression.thinking => size * 0.01,
      _ => 0.0,
    };
  }

  /// Jaw drop driven by mouth openness — pulls mouth and lower cheeks down.
  double _jawDrop(double size) {
    final openness = widget.controller?.mouthOpenAmount ?? 0.0;
    return openness * size * 0.03;
  }

  // ── Touch handling ────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _touchHandler.onTouch(d.localPosition, Offset.zero, widget.size);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _touchHandler.onTouch(d.localPosition, d.delta, widget.size);
    final norm = Offset(
      d.localPosition.dx / widget.size,
      d.localPosition.dy / widget.size,
    );
    final force = Offset(d.delta.dx / widget.size, d.delta.dy / widget.size) * 3.0;
    _skeleton.applyTouchForce(norm, force);
  }

  void _onPanEnd(DragEndDetails d) {
    _touchHandler.onTouchEnd();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final config = widget.config;
    final bgColor = AppColors.avatarBgColors[config.bgColor.clamp(0, 7)];

    // Head sway derived from skeleton head bone's world rotation
    final headStorage = _skeleton.head.worldTransform.storage;
    final swayAngle = atan2(headStorage[1], headStorage[0]);
    final centerX = size / 2;

    // Expression-driven transforms
    final browOffset = _browOffsetY(size);
    final jawDrop = _jawDrop(size);

    // Widget dimensions — bust view (~3:4 aspect ratio)
    final widgetW = size;
    final widgetH = size / widget.aspectRatio;

    // Constant-value animation wrappers for painters
    final breathingAnim = _ConstantAnimation(_breathingValue);
    final swayAnim = _ConstantAnimation(_idleSwayValue);
    final blinkAnim = _ConstantAnimation(_blinkValue);
    final pupilAnim = _ConstantAnimation(_pupilDilationValue);

    return RepaintBoundary(
      child: GestureDetector(
        onPanStart: widget.animateEffects ? _onPanStart : null,
        onPanUpdate: widget.animateEffects ? _onPanUpdate : null,
        onPanEnd: widget.animateEffects ? _onPanEnd : null,
        child: SizedBox(
          width: widgetW,
          height: widgetH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Background (rounded rect for bust view)
              if (widget.showBackground)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(widgetW * 0.5),
                    ),
                  ),
                ),

              // 2. Golden glow aura
              if (config.hasGoldenGlow)
                Positioned.fill(
                  child: CustomPaint(
                    willChange: widget.animateEffects,
                    painter: GoldenGlowPainter(
                      intensity: 1.0,
                      time: _twinkleValue,
                    ),
                  ),
                ),

              // 3. Body painters (neck, torso, shoulders, arms, hands)
              // Skip in compact mode — thumbnails and small avatars don't need body
              if (size >= 48)
                Positioned(
                  left: 0,
                  top: 0,
                  width: widgetW,
                  height: widgetH,
                  child: CustomPaint(
                    isComplex: true,
                    willChange: widget.animateEffects,
                    painter: BodyPainter(
                      skinColor: _skinColor,
                      shirtColor: shirtColorOptions[
                          (config.bgColor + 2).clamp(0, shirtColorOptions.length - 1)].color,
                      collarStyle: 0,
                      headTilt: swayAngle,
                      breathingValue: _breathingValue,
                      swayValue: _idleSwayValue,
                    ),
                  ),
                ),

              // 4. Hair back layer
              Positioned(
                left: 0,
                top: 0,
                width: widgetW,
                height: widgetW,
                child: CustomPaint(
                  isComplex: true,
                  willChange: widget.animateEffects,
                  painter: HairBackPainter(
                    style: config.hairStyle,
                    color: _hairColor,
                    isRainbow: isRainbowHair(config.hairColor),
                    faceShape: config.faceShape,
                    swayValue: _idleSwayValue,
                    repaint: _repaintNotifier,
                  ),
                ),
              ),

              // 5. Head bone: unified sway rotation for all face features
              Positioned(
                left: 0,
                top: 0,
                width: widgetW,
                height: widgetW,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(centerX, centerX / 2, 0, 0)
                    ..rotateZ(swayAngle)
                    ..translateByDouble(-centerX, -centerX / 2, 0, 0),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Face shape
                      Positioned(
                        left: size * 0.15,
                        top: size * _faceTop,
                        child: CustomPaint(
                          size: Size(size * 0.70, size * _faceHeightFraction),
                          isComplex: true,
                          willChange: widget.animateEffects,
                          painter: FacePainter(
                            skinColor: _skinColor,
                            faceShape: config.faceShape,
                            breathingValue: breathingAnim,
                            swayValue: swayAnim,
                            repaint: _repaintNotifier,
                          ),
                        ),
                      ),

                      // Nose
                      Positioned(
                        left: size * 0.44,
                        top: size * (_faceTop + _faceHeightFraction * 0.52),
                        child: CustomPaint(
                          size: Size(size * 0.12, size * 0.10),
                          isComplex: true,
                          willChange: widget.animateEffects,
                          painter: NosePainter(
                            style: config.noseStyle,
                            skinColor: _skinColor,
                            breathingValue: breathingAnim,
                            repaint: _repaintNotifier,
                          ),
                        ),
                      ),

                      // Cheeks
                      if (config.cheekStyle > 0)
                        Positioned(
                          left: size * 0.18,
                          top: size * (_faceTop + _faceHeightFraction * 0.48),
                          child: CustomPaint(
                            size: Size(size * 0.64, size * 0.20),
                            isComplex: true,
                            painter: CheekPainter(
                              style: config.cheekStyle,
                              skinColor: _skinColor,
                            ),
                          ),
                        ),

                      // Eyes
                      Positioned(
                        left: size * 0.26,
                        top: size * (_faceTop + _faceHeightFraction * 0.28),
                        child: CustomPaint(
                          size: Size(size * 0.48, size * 0.16),
                          isComplex: true,
                          willChange: widget.animateEffects,
                          painter: EyesPainter(
                            style: config.eyeStyle,
                            eyeColor: _eyeColor,
                            skinColor: _skinColor,
                            blinkValue: blinkAnim,
                            swayValue: swayAnim,
                            pupilDilationValue: pupilAnim,
                            expression: widget.controller?.expression ?? AvatarExpression.neutral,
                            lookTarget: widget.controller?.lookTarget,
                            avatarSize: size,
                            repaint: _repaintNotifier,
                          ),
                        ),
                      ),

                      // Eyelashes
                      if (config.eyelashStyle > 0)
                        Positioned(
                          left: size * 0.26,
                          top: size * (_faceTop + _faceHeightFraction * 0.22),
                          child: CustomPaint(
                            size: Size(size * 0.48, size * 0.20),
                            painter: EyelashPainter(
                              style: config.eyelashStyle,
                              eyeStyle: config.eyeStyle,
                            ),
                          ),
                        ),

                      // Eyebrows (expression-driven offset)
                      Positioned(
                        left: size * 0.26,
                        top: size * (_faceTop + _faceHeightFraction * 0.16),
                        child: Transform.translate(
                          offset: Offset(0, browOffset),
                          child: CustomPaint(
                            size: Size(size * 0.48, size * 0.10),
                            painter: EyebrowPainter(
                              style: config.eyebrowStyle,
                              color: _hairColor,
                            ),
                          ),
                        ),
                      ),

                      // Mouth (jaw transform)
                      Positioned(
                        left: size * 0.35,
                        top: size * (_faceTop + _faceHeightFraction * 0.68),
                        child: Transform.translate(
                          offset: Offset(0, jawDrop),
                          child: CustomPaint(
                            size: Size(size * 0.30, size * 0.12),
                            isComplex: true,
                            willChange: widget.controller != null,
                            painter: MouthPainter(
                              style: config.mouthStyle,
                              lipColor: _lipColor,
                              expression: widget.controller?.expression ?? AvatarExpression.neutral,
                              mouthOpenAmount: widget.controller?.mouthOpenAmount ?? 0.0,
                              repaint: widget.controller != null ? _repaintNotifier : null,
                            ),
                          ),
                        ),
                      ),

                      // Face paint
                      if (config.facePaint > 0)
                        Positioned(
                          left: size * 0.15,
                          top: size * _faceTop,
                          child: CustomPaint(
                            size: Size(size * 0.70, size * _faceHeightFraction),
                            isComplex: true,
                            painter: FacePaintPainter(
                              style: config.facePaint,
                              skinColor: _skinColor,
                            ),
                          ),
                        ),

                      // Glasses
                      if (config.glassesStyle > 0)
                        Positioned(
                          left: size * 0.26,
                          top: size * (_faceTop + _faceHeightFraction * 0.28),
                          child: CustomPaint(
                            size: Size(size * 0.48, size * 0.16),
                            isComplex: true,
                            painter: GlassesPainter(
                              style: config.glassesStyle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 6. Hair front layer
              Positioned(
                left: 0,
                top: 0,
                width: widgetW,
                height: widgetW,
                child: CustomPaint(
                  isComplex: true,
                  willChange: widget.animateEffects,
                  painter: HairFrontPainter(
                    style: config.hairStyle,
                    color: _hairColor,
                    isRainbow: isRainbowHair(config.hairColor),
                    faceShape: config.faceShape,
                    swayValue: _idleSwayValue,
                    repaint: _repaintNotifier,
                  ),
                ),
              ),

              // 7. Accessories
              if (config.accessory > 1)
                Positioned(
                  left: 0,
                  top: 0,
                  width: widgetW,
                  height: widgetW,
                  child: CustomPaint(
                    isComplex: true,
                    willChange: widget.animateEffects,
                    painter: accessoryPainter(
                      config.accessory,
                      swayValue: _idleSwayValue,
                      twinklePhase: _twinkleValue,
                    ),
                  ),
                ),

              // 8. Sparkle effects
              if (config.hasRainbowSparkle || config.hasGoldenGlow)
                Positioned.fill(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: widget.animateEffects,
                    painter: SparklePainter(
                      rainbow: config.hasRainbowSparkle,
                      time: _twinkleValue,
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

// ═══════════════════════════════════════════════════════════════════════
//  HELPER: Constant animation value wrapper for painters that expect
//  Animation<double>. Bridges skeleton-driven values to painter APIs.
// ═══════════════════════════════════════════════════════════════════════

class _ConstantAnimation extends Animation<double> {
  final double _value;
  const _ConstantAnimation(this._value);

  @override
  double get value => _value;

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  void addStatusListener(AnimationStatusListener listener) {}
  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}

// ═══════════════════════════════════════════════════════════════════════
//  HELPER: Listenable that can be manually triggered for repaint
// ═══════════════════════════════════════════════════════════════════════

class _TickNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ═══════════════════════════════════════════════════════════════════════
//  FACE PAINTER
//  - Warm-to-cool radial gradient (forehead highlight → jaw shadow)
//  - Ambient occlusion under chin, around nose bridge
//  - Gradient ears with inner shadow
//  - Breathing scaleY + idle sway rotation
// ═══════════════════════════════════════════════════════════════════════

class FacePainter extends CustomPainter {
  final Color skinColor;
  final int faceShape;
  final Animation<double> breathingValue;
  final Animation<double> swayValue;

  FacePainter({
    required this.skinColor,
    required this.faceShape,
    required this.breathingValue,
    required this.swayValue,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    final breathScale = 1.0 + breathingValue.value * 0.02;
    final swayAngle = (swayValue.value - 0.5) * 2 * (2 * pi / 180);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(swayAngle);
    canvas.scale(1.0, breathScale);
    canvas.translate(-center.dx, -center.dy);

    // ── Chin ambient occlusion ──
    final chinAO = Paint()
      ..color = const Color(0xFF3A3060).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 1.0),
        width: w * 0.65,
        height: h * 0.16,
      ),
      chinAO,
    );

    // ── Ears ──
    _drawEars(canvas, w, h);

    // ── Face with warm-to-cool 3D gradient ──
    final faceRect = Rect.fromLTWH(0, 0, w, h);
    // Warm highlight on forehead, cool shadow on jaw
    final warmHighlight = Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.15)!;
    final coolShadow = Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.12)!;
    final gradient = RadialGradient(
      center: const Alignment(-0.1, -0.35),
      radius: 0.95,
      colors: [
        warmHighlight,
        skinColor,
        Color.lerp(skinColor, coolShadow, 0.4)!,
        coolShadow,
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );
    final gradientPaint = Paint()
      ..shader = gradient.createShader(faceRect);

    final facePath = _buildFacePath(w, h);
    canvas.drawPath(facePath, gradientPaint);

    // ── Subtle rim light (warm edge highlight on the lit side) ──
    final rimLight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.6, -0.4),
        radius: 1.1,
        colors: [
          const Color(0xFFFFF0D0).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4],
      ).createShader(faceRect);
    canvas.drawPath(facePath, rimLight);

    // ── Cool edge shadow (right/bottom ambient occlusion) ──
    final edgeAO = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.4, 0.5),
        radius: 0.8,
        colors: [
          Colors.transparent,
          const Color(0xFF4A3A6E).withValues(alpha: 0.07),
        ],
        stops: const [0.5, 1.0],
      ).createShader(faceRect);
    canvas.drawPath(facePath, edgeAO);

    // ── Nose bridge ambient occlusion ──
    final noseBridgeAO = Paint()
      ..color = const Color(0xFF5A4A7E).withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.42),
        width: w * 0.15,
        height: h * 0.22,
      ),
      noseBridgeAO,
    );

    canvas.restore();
  }

  void _drawEars(Canvas canvas, double w, double h) {
    final earW = w * 0.13;
    final earH = h * 0.17;
    final earY = h * 0.38;

    for (final isLeft in [true, false]) {
      final cx = isLeft ? -earW * 0.25 : w + earW * 0.25;
      final earRect = Rect.fromCenter(
        center: Offset(cx, earY),
        width: earW,
        height: earH,
      );

      // Ear base with gradient
      final warmSide = Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.08)!;
      final coolSide = Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.08)!;
      final earGradient = RadialGradient(
        center: Alignment(isLeft ? 0.3 : -0.3, -0.2),
        radius: 0.8,
        colors: [warmSide, skinColor, coolSide],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawOval(earRect, Paint()..shader = earGradient.createShader(earRect));

      // Inner ear shadow — pinkish
      final innerCx = isLeft ? -earW * 0.15 : w + earW * 0.15;
      final innerRect = Rect.fromCenter(
        center: Offset(innerCx, earY),
        width: earW * 0.5,
        height: earH * 0.5,
      );
      final innerGradient = RadialGradient(
        colors: [
          Color.lerp(skinColor, const Color(0xFFFF9090), 0.2)!
              .withValues(alpha: 0.5),
          Colors.transparent,
        ],
      );
      canvas.drawOval(
        innerRect,
        Paint()..shader = innerGradient.createShader(innerRect),
      );
    }
  }

  Path _buildFacePath(double w, double h) {
    switch (faceShape) {
      case 0: // Round
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(w * 0.5),
          ));
      case 1: // Square-ish
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(w * 0.28),
          ));
      case 2: // Oval
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
      case 3: // Heart
        return Path()
          ..moveTo(w * 0.50, h * 0.18)
          ..cubicTo(w * 0.50, h * 0.05, w * 0.80, h * -0.02, w * 0.90,
              h * 0.20)
          ..cubicTo(w * 1.00, h * 0.42, w * 0.80, h * 0.65, w * 0.50,
              h * 0.98)
          ..cubicTo(w * 0.20, h * 0.65, w * 0.00, h * 0.42, w * 0.10,
              h * 0.20)
          ..cubicTo(w * 0.20, h * -0.02, w * 0.50, h * 0.05, w * 0.50,
              h * 0.18)
          ..close();
      case 4: // Diamond
        return Path()
          ..moveTo(w * 0.50, h * 0.02)
          ..quadraticBezierTo(w * 0.95, h * 0.30, w * 0.88, h * 0.55)
          ..quadraticBezierTo(w * 0.78, h * 0.85, w * 0.50, h * 0.98)
          ..quadraticBezierTo(w * 0.22, h * 0.85, w * 0.12, h * 0.55)
          ..quadraticBezierTo(w * 0.05, h * 0.30, w * 0.50, h * 0.02)
          ..close();
      default:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(w * 0.5),
          ));
    }
  }

  @override
  bool shouldRepaint(FacePainter old) =>
      old.skinColor != skinColor || old.faceShape != faceShape;
}

// ═══════════════════════════════════════════════════════════════════════
//  EYES PAINTER
//  - Limbal ring (dark outer iris edge)
//  - Radial fiber texture via thin lines emanating from pupil
//  - Caustic-like light patterns on iris
//  - Dual specular highlights (large soft + small sharp)
//  - Eyelid-sweep blink (skin-colored shape sweeps down, not scaleY)
//  - Pupil dilation micro-animation
//  - Eye tracking (pupils shift with idle sway)
// ═══════════════════════════════════════════════════════════════════════

class EyesPainter extends CustomPainter {
  final int style;
  final Color eyeColor;
  final Color skinColor;
  final Animation<double> blinkValue;
  final Animation<double> swayValue;
  final Animation<double> pupilDilationValue;
  final AvatarExpression expression;

  /// Target point for eye tracking (avatar-local coords). Null = idle sway.
  final Offset? lookTarget;

  /// Full avatar widget size, used to normalize lookTarget into pupil offset.
  final double avatarSize;

  EyesPainter({
    required this.style,
    required this.eyeColor,
    required this.skinColor,
    required this.blinkValue,
    required this.swayValue,
    required this.pupilDilationValue,
    this.expression = AvatarExpression.neutral,
    this.lookTarget,
    this.avatarSize = 80,
    super.repaint,
  });

  // Mutable state set during paint() for use by sub-methods
  double _currentTrackY = 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCenter = Offset(w * 0.25, h * 0.5);
    final rightCenter = Offset(w * 0.75, h * 0.5);

    // Expression-aware eye scaling
    final eyeScaleFactor = switch (expression) {
      AvatarExpression.excited => 1.15,
      AvatarExpression.surprised => 1.25,
      AvatarExpression.thinking => 0.85,
      _ => 1.0,
    };
    final eyeRadius = w * 0.12 * eyeScaleFactor;

    // Eye tracking: use lookTarget if set, otherwise idle sway
    double trackX;
    double trackY = 0.0;
    if (lookTarget != null) {
      // Normalize target relative to avatar center, clamp to ±1
      final eyeAreaLeft = avatarSize * 0.26;
      final eyeAreaTop = avatarSize * 0.28;
      final eyesCenterX = eyeAreaLeft + w * 0.5;
      final eyesCenterY = eyeAreaTop + h * 0.5;
      final dx = ((lookTarget!.dx - eyesCenterX) / avatarSize).clamp(-1.0, 1.0);
      final dy = ((lookTarget!.dy - eyesCenterY) / avatarSize).clamp(-1.0, 1.0);
      trackX = dx * eyeRadius * 0.25;
      trackY = dy * eyeRadius * 0.15;
    } else {
      trackX = (swayValue.value - 0.5) * eyeRadius * 0.15;
    }

    // Pupil dilation: radius oscillates 0.28r ↔ 0.35r
    // Surprised expression dilates more
    final baseDilation = expression == AvatarExpression.surprised ? 0.32 : 0.28;
    final pupilScale = baseDilation + pupilDilationValue.value * 0.07;

    // Store trackY for use in drawing methods
    _currentTrackY = trackY;

    switch (style) {
      case 0: // Round
        _drawFullEye(canvas, leftCenter, eyeRadius, trackX, pupilScale);
        _drawFullEye(canvas, rightCenter, eyeRadius, trackX, pupilScale);
        _drawEyelid(canvas, leftCenter, eyeRadius, w);
        _drawEyelid(canvas, rightCenter, eyeRadius, w);
      case 1: // Star
        final paint = Paint()..color = AppColors.starGold;
        _drawStar(canvas, leftCenter, eyeRadius, paint);
        _drawStar(canvas, rightCenter, eyeRadius, paint);
      case 2: // Hearts
        final paint = Paint()..color = const Color(0xFFFF4D6A);
        _drawHeart(canvas, leftCenter, eyeRadius, paint);
        _drawHeart(canvas, rightCenter, eyeRadius, paint);
      case 3: // Happy Crescents
        _drawCrescentEyes(canvas, leftCenter, rightCenter, eyeRadius);
      case 4: // Sparkle
        _drawSparkleEye(canvas, leftCenter, eyeRadius, trackX, pupilScale);
        _drawSparkleEye(canvas, rightCenter, eyeRadius, trackX, pupilScale);
        _drawEyelid(canvas, leftCenter, eyeRadius * 1.3, w);
        _drawEyelid(canvas, rightCenter, eyeRadius * 1.3, w);
      case 5: // Almond
        _drawAlmondEye(canvas, leftCenter, eyeRadius, trackX, pupilScale);
        _drawAlmondEye(canvas, rightCenter, eyeRadius, trackX, pupilScale);
        _drawAlmondEyelid(canvas, leftCenter, eyeRadius);
        _drawAlmondEyelid(canvas, rightCenter, eyeRadius);
      case 6: // Wink
        _drawFullEye(canvas, leftCenter, eyeRadius, trackX, pupilScale);
        _drawEyelid(canvas, leftCenter, eyeRadius, w);
        _drawWinkEye(canvas, rightCenter, eyeRadius);
      case 7: // Sleepy
        _drawSleepyEyes(canvas, leftCenter, rightCenter, eyeRadius, trackX);
    }
  }

  /// The fully detailed round eye with iris fibers, limbal ring, etc.
  void _drawFullEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    // ── Sclera ──
    canvas.drawCircle(center, r, Paint()..color = Colors.white);

    // Sclera top shadow (subtle blue-gray, like eyelid casting shadow)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy - r * 0.3),
          [
            const Color(0xFF8892B0).withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ),
    );

    // ── Iris ──
    final irisCenter = center.translate(r * 0.10 + trackX, _currentTrackY);
    final irisR = r * 0.58;
    final irisRect = Rect.fromCircle(center: irisCenter, radius: irisR);

    // Base iris gradient (3-stop: lighter inner, main, darker outer)
    final irisGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Color.lerp(eyeColor, Colors.white, 0.35)!,
        eyeColor,
        Color.lerp(eyeColor, Colors.black, 0.3)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()..shader = irisGradient.createShader(irisRect),
    );

    // ── Radial fiber texture ──
    // Draw thin semi-transparent lines from pupil edge outward
    final fiberPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = irisR * 0.03;
    final fiberRng = Random(42); // deterministic for consistency
    for (int i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * pi + fiberRng.nextDouble() * 0.1;
      final innerR = irisR * 0.35;
      final outerR = irisR * (0.75 + fiberRng.nextDouble() * 0.2);
      final brightness = fiberRng.nextDouble();
      fiberPaint.color = brightness > 0.5
          ? Color.lerp(eyeColor, Colors.white, 0.25)!.withValues(alpha: 0.2)
          : Color.lerp(eyeColor, Colors.black, 0.2)!.withValues(alpha: 0.15);
      canvas.drawLine(
        Offset(
          irisCenter.dx + innerR * cos(angle),
          irisCenter.dy + innerR * sin(angle),
        ),
        Offset(
          irisCenter.dx + outerR * cos(angle),
          irisCenter.dy + outerR * sin(angle),
        ),
        fiberPaint,
      );
    }

    // ── Caustic-like light pattern ──
    // A crescent of lighter color on the upper-left iris area
    canvas.save();
    canvas.clipPath(Path()..addOval(irisRect));
    final causticRect = Rect.fromCenter(
      center: irisCenter.translate(-irisR * 0.2, -irisR * 0.15),
      width: irisR * 1.0,
      height: irisR * 0.6,
    );
    canvas.drawOval(
      causticRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(eyeColor, Colors.white, 0.4)!.withValues(alpha: 0.2),
            Colors.transparent,
          ],
        ).createShader(causticRect),
    );
    canvas.restore();

    // ── Limbal ring (dark outer iris edge) ──
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = irisR * 0.08
        ..color = Color.lerp(eyeColor, Colors.black, 0.5)!
            .withValues(alpha: 0.6),
    );

    // ── Pupil ──
    final pupilR = r * pupilScale;
    final pupilCenter = center.translate(r * 0.12 + trackX, _currentTrackY);
    canvas.drawCircle(
      pupilCenter,
      pupilR,
      Paint()..color = const Color(0xFF050510),
    );

    // ── Dual specular highlights ──
    // Large soft highlight (top-left)
    final bigHighlightCenter = center.translate(r * 0.22, -r * 0.22);
    final bigHighlightRect = Rect.fromCenter(
      center: bigHighlightCenter,
      width: r * 0.42,
      height: r * 0.32,
    );
    canvas.drawOval(
      bigHighlightRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.92),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(bigHighlightRect),
    );

    // Small sharp highlight (bottom-right)
    canvas.drawCircle(
      center.translate(-r * 0.12, r * 0.18),
      r * 0.08,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  /// Eyelid-sweep blink: a skin-colored arc sweeps down over the eye.
  void _drawEyelid(Canvas canvas, Offset center, double r, double totalW) {
    final blink = blinkValue.value;
    if (blink < 0.01) return;

    // Eyelid sweeps from top of eye downward
    final lidTop = center.dy - r * 1.1;
    final lidBottom = center.dy - r * 1.1 + (r * 2.2) * blink;

    canvas.save();
    // Clip to eye area so eyelid doesn't spill outside
    canvas.clipPath(Path()..addOval(
      Rect.fromCircle(center: center, radius: r * 1.05),
    ));

    // Eyelid skin
    final lidRect = Rect.fromLTWH(
      center.dx - r * 1.1,
      lidTop,
      r * 2.2,
      lidBottom - lidTop,
    );
    final lidGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.05)!,
        skinColor,
        Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.08)!,
      ],
    );
    canvas.drawRect(lidRect, Paint()..shader = lidGradient.createShader(lidRect));

    // Eyelid crease shadow at the bottom edge
    final creasePaint = Paint()
      ..color = Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.2)!
          .withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawLine(
      Offset(center.dx - r * 0.9, lidBottom),
      Offset(center.dx + r * 0.9, lidBottom),
      creasePaint..strokeWidth = r * 0.12,
    );

    // Lash line at bottom of eyelid
    if (blink > 0.3) {
      final lashLine = Paint()
        ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.5 * blink)
        ..strokeWidth = r * 0.08
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(center.dx, lidBottom), width: r * 1.8, height: r * 0.6),
        0,
        pi,
        false,
        lashLine,
      );
    }

    canvas.restore();
  }

  /// Almond eyelid sweep adapted to almond eye shape.
  void _drawAlmondEyelid(Canvas canvas, Offset center, double r) {
    final blink = blinkValue.value;
    if (blink < 0.01) return;

    final lidTop = center.dy - r * 1.0;
    final lidBottom = center.dy - r * 1.0 + (r * 2.0) * blink;

    canvas.save();
    // Clip to almond eye shape
    final almondPath = Path()
      ..moveTo(center.dx - r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + r * 0.8, center.dx - r * 1.2, center.dy)
      ..close();
    canvas.clipPath(almondPath);

    final lidRect = Rect.fromLTWH(
      center.dx - r * 1.3,
      lidTop,
      r * 2.6,
      lidBottom - lidTop,
    );
    canvas.drawRect(
      lidRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.05)!,
            skinColor,
          ],
        ).createShader(lidRect),
    );

    canvas.restore();
  }

  void _drawSparkleEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    final bigR = r * 1.3;

    // White sclera
    canvas.drawCircle(center, bigR, Paint()..color = Colors.white);

    // Sclera top shadow
    canvas.drawCircle(
      center,
      bigR,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, center.dy - bigR),
          Offset(center.dx, center.dy - bigR * 0.3),
          [
            const Color(0xFF8892B0).withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ),
    );

    // Iris with gradient + limbal ring
    final irisR = bigR * 0.65;
    final irisRect = Rect.fromCircle(center: center, radius: irisR);
    canvas.drawCircle(
      center,
      irisR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(eyeColor, Colors.white, 0.35)!,
            eyeColor,
            Color.lerp(eyeColor, Colors.black, 0.3)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(irisRect),
    );

    // Limbal ring
    canvas.drawCircle(
      center,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = irisR * 0.07
        ..color = Color.lerp(eyeColor, Colors.black, 0.45)!
            .withValues(alpha: 0.5),
    );

    // Pupil
    canvas.drawCircle(
      center,
      bigR * pupilScale * 0.85,
      Paint()..color = const Color(0xFF050510),
    );

    // Large sparkle highlights
    canvas.drawCircle(
      center.translate(bigR * 0.3, -bigR * 0.2),
      bigR * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      center.translate(-bigR * 0.2, bigR * 0.25),
      bigR * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawAlmondEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    // Almond shape
    final path = Path()
      ..moveTo(center.dx - r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + r * 0.8, center.dx - r * 1.2, center.dy)
      ..close();

    canvas.save();
    canvas.clipPath(path);

    // White sclera fill
    canvas.drawPath(path, Paint()..color = Colors.white);

    // Sclera top shadow
    final scleraRect = Rect.fromCircle(center: center, radius: r * 1.2);
    canvas.drawRect(
      scleraRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy - r * 0.2),
          [
            const Color(0xFF8892B0).withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ),
    );

    // Iris with gradient
    final irisCenter = center.translate(r * 0.10 + trackX, _currentTrackY);
    final irisR = r * 0.50;
    final irisRect = Rect.fromCircle(center: irisCenter, radius: irisR);
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(eyeColor, Colors.white, 0.3)!,
            eyeColor,
            Color.lerp(eyeColor, Colors.black, 0.3)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(irisRect),
    );

    // Limbal ring
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = irisR * 0.08
        ..color = Color.lerp(eyeColor, Colors.black, 0.45)!
            .withValues(alpha: 0.5),
    );

    // Fiber texture (fewer for almond — 16 fibers)
    final fiberPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = irisR * 0.03;
    final fiberRng = Random(42);
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * pi + fiberRng.nextDouble() * 0.1;
      final innerR = irisR * 0.35;
      final outerR = irisR * (0.7 + fiberRng.nextDouble() * 0.25);
      fiberPaint.color = fiberRng.nextDouble() > 0.5
          ? Color.lerp(eyeColor, Colors.white, 0.2)!.withValues(alpha: 0.15)
          : Color.lerp(eyeColor, Colors.black, 0.15)!.withValues(alpha: 0.12);
      canvas.drawLine(
        Offset(
          irisCenter.dx + innerR * cos(angle),
          irisCenter.dy + innerR * sin(angle),
        ),
        Offset(
          irisCenter.dx + outerR * cos(angle),
          irisCenter.dy + outerR * sin(angle),
        ),
        fiberPaint,
      );
    }

    // Pupil
    canvas.drawCircle(
      center.translate(r * 0.12 + trackX, _currentTrackY),
      r * pupilScale,
      Paint()..color = const Color(0xFF050510),
    );

    // Highlight
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(r * 0.22, -r * 0.18),
        width: r * 0.32,
        height: r * 0.22,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Small highlight
    canvas.drawCircle(
      center.translate(-r * 0.1, r * 0.15),
      r * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    canvas.restore();
  }

  void _drawCrescentEyes(Canvas canvas, Offset left, Offset right, double r) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(center: left, width: r * 2, height: r * 1.5),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: right, width: r * 2, height: r * 1.5),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
  }

  void _drawWinkEye(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.2),
      pi * 0.1,
      pi * 0.8,
      false,
      paint,
    );
  }

  void _drawSleepyEyes(
      Canvas canvas, Offset left, Offset right, double r, double trackX) {
    for (final center in [left, right]) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          center.dx - r * 1.2, center.dy - r * 0.15, r * 2.4, r * 1.2));

      canvas.drawCircle(center, r, Paint()..color = Colors.white);

      // Iris with gradient
      final irisCenter = center.translate(r * 0.1 + trackX, 0.05 + _currentTrackY);
      final irisR = r * 0.55;
      final irisRect = Rect.fromCircle(center: irisCenter, radius: irisR);
      canvas.drawCircle(
        irisCenter,
        irisR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(eyeColor, Colors.white, 0.25)!,
              eyeColor,
              Color.lerp(eyeColor, Colors.black, 0.3)!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(irisRect),
      );

      // Limbal ring
      canvas.drawCircle(
        irisCenter,
        irisR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = irisR * 0.07
          ..color = Color.lerp(eyeColor, Colors.black, 0.4)!
              .withValues(alpha: 0.4),
      );

      // Pupil
      canvas.drawCircle(
        center.translate(r * 0.12 + trackX, 0.05 + _currentTrackY),
        r * 0.30,
        Paint()..color = const Color(0xFF050510),
      );

      // Small highlight
      canvas.drawCircle(
        center.translate(r * 0.2, -r * 0.05),
        r * 0.1,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );

      canvas.restore();

      // Eyelid line — sleepy droop
      final lidPaint = Paint()
        ..color = Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.15)!
            .withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(center.dx - r * 0.9, center.dy - r * 0.1),
        Offset(center.dx + r * 0.9, center.dy - r * 0.1),
        lidPaint,
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final ox = center.dx + r * cos(outerAngle);
      final oy = center.dy + r * sin(outerAngle);
      final ix = center.dx + r * 0.4 * cos(innerAngle);
      final iy = center.dy + r * 0.4 * sin(innerAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double r, Paint paint) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(
          x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(
          x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(EyesPainter old) =>
      old.style != style ||
      old.eyeColor != eyeColor ||
      old.skinColor != skinColor ||
      old.expression != expression ||
      old.lookTarget != lookTarget;
}

// ═══════════════════════════════════════════════════════════════════════
//  MOUTH PAINTER
//  - Gradient lips (darker top, lighter bottom with warm shift)
//  - Individual tooth shapes with rounded corners
//  - Tongue with center-line gradient (pink → red with darker center line)
// ═══════════════════════════════════════════════════════════════════════

class MouthPainter extends CustomPainter {
  final int style;
  final Color lipColor;
  final AvatarExpression expression;
  final double mouthOpenAmount;

  MouthPainter({
    required this.style,
    required this.lipColor,
    this.expression = AvatarExpression.neutral,
    this.mouthOpenAmount = 0.0,
    super.repaint,
  });

  Color get _effectiveLipFill =>
      (lipColor.a * 255.0).round().clamp(0, 255) == 0
          ? const Color(0xFF1A1A2E)
          : lipColor;

  bool get _hasLipColor => (lipColor.a * 255.0).round().clamp(0, 255) > 0;

  Paint _lipGradientPaint(Rect rect) {
    final base = _effectiveLipFill;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(base, const Color(0xFF4A2040), 0.2)!, // cool dark top lip
          base,
          Color.lerp(base, const Color(0xFFFFF0E0), 0.12)!, // warm bottom lip
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
  }

  /// Draw individual rounded teeth inside a clipped mouth area.
  void _drawIndividualTeeth(Canvas canvas, double x, double y, double teethW,
      double teethH, int count) {
    final toothW = teethW / count;
    final toothR = toothW * 0.15;

    // White base for all teeth
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, teethW, teethH),
        Radius.circular(toothR),
      ),
      Paint()..color = Colors.white,
    );

    // Individual tooth separator lines
    final sepPaint = Paint()
      ..color = const Color(0xFFD8D8E0).withValues(alpha: 0.6)
      ..strokeWidth = teethW * 0.008;
    for (int i = 1; i < count; i++) {
      final tx = x + toothW * i;
      canvas.drawLine(Offset(tx, y + teethH * 0.1),
          Offset(tx, y + teethH * 0.9), sepPaint);
    }

    // Subtle gradient on teeth for 3D feel
    final teethRect = Rect.fromLTWH(x, y, teethW, teethH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(teethRect, Radius.circular(toothR)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0xFFF0F0F5),
          ],
        ).createShader(teethRect),
    );
  }

  /// Tongue with center-line gradient.
  void _drawTongue(Canvas canvas, Offset center, double w, double h) {
    final tongueRect = Rect.fromCenter(center: center, width: w, height: h);

    // Base tongue gradient (pink edges → red center)
    canvas.drawOval(
      tongueRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [
            Color(0xFFE04060), // darker center
            Color(0xFFFF8FAB), // pink edges
          ],
        ).createShader(tongueRect),
    );

    // Center line (darker groove)
    final centerLinePaint = Paint()
      ..color = const Color(0xFFCC3050).withValues(alpha: 0.4)
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy - h * 0.3),
      Offset(center.dx, center.dy + h * 0.35),
      centerLinePaint,
    );

    // Subtle highlight on tongue
    final highlightRect = Rect.fromCenter(
      center: center.translate(-w * 0.1, -h * 0.15),
      width: w * 0.4,
      height: h * 0.3,
    );
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB0C0).withValues(alpha: 0.3),
            Colors.transparent,
          ],
        ).createShader(highlightRect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Expression overrides ──
    if (expression == AvatarExpression.talking && mouthOpenAmount > 0.01) {
      _drawTalkingMouth(canvas, w, h, mouthOpenAmount);
      return;
    }
    if (expression == AvatarExpression.excited) {
      _drawExcitedMouth(canvas, w, h);
      return;
    }
    if (expression == AvatarExpression.thinking) {
      _drawThinkingMouth(canvas, w, h);
      return;
    }
    if (expression == AvatarExpression.surprised) {
      _drawSurprisedMouth(canvas, w, h);
      return;
    }

    switch (style) {
      case 0: // Smile
        if (_hasLipColor) {
          final path = Path()
            ..moveTo(w * 0.10, h * 0.20)
            ..quadraticBezierTo(w * 0.50, h * 1.0, w * 0.90, h * 0.20)
            ..quadraticBezierTo(w * 0.50, h * 0.50, w * 0.10, h * 0.20)
            ..close();
          canvas.drawPath(path, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h)));
        } else {
          final paint = Paint()
            ..color = const Color(0xFF1A1A2E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.08
            ..strokeCap = StrokeCap.round;
          canvas.drawArc(
            Rect.fromLTWH(w * 0.1, -h * 0.2, w * 0.8, h * 1.0),
            0.2,
            pi * 0.6,
            false,
            paint,
          );
        }

      case 1: // Big Grin
        // Mouth shape
        final mouthPath = Path()
          ..moveTo(w * 0.05, h * 0.2)
          ..quadraticBezierTo(w * 0.5, h * 1.2, w * 0.95, h * 0.2)
          ..close();

        // Dark mouth interior
        canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

        // Individual teeth
        canvas.save();
        canvas.clipPath(mouthPath);
        _drawIndividualTeeth(canvas, w * 0.2, h * 0.2, w * 0.6, h * 0.22, 5);
        canvas.restore();

        // Lip outline with gradient
        canvas.drawPath(mouthPath, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h))
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.05);

      case 2: // Tongue Out
        final mouthPath = Path()
          ..moveTo(w * 0.10, h * 0.15)
          ..quadraticBezierTo(w * 0.5, h * 1.0, w * 0.90, h * 0.15)
          ..close();

        // Dark interior
        canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

        // Lip gradient
        canvas.drawPath(mouthPath, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h))
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.04);

        // Tongue with center-line
        _drawTongue(canvas, Offset(w * 0.5, h * 0.65), w * 0.35, h * 0.55);

      case 3: // Surprised O
        // Outer lip ring
        final outerRect = Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.45),
          width: w * 0.45,
          height: h * 0.80,
        );
        canvas.drawOval(outerRect, _lipGradientPaint(outerRect));

        // Dark mouth interior
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.45),
            width: w * 0.30,
            height: h * 0.55,
          ),
          Paint()..color = const Color(0xFF2D1A2E),
        );

        // Subtle teeth visible at top
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.45),
          width: w * 0.30,
          height: h * 0.55,
        )));
        _drawIndividualTeeth(canvas, w * 0.3, h * 0.2, w * 0.4, h * 0.12, 4);
        canvas.restore();

      case 4: // Kissy
        final path = Path()
          ..moveTo(w * 0.25, h * 0.30)
          ..quadraticBezierTo(w * 0.15, h * 0.50, w * 0.30, h * 0.70)
          ..quadraticBezierTo(w * 0.50, h * 0.90, w * 0.70, h * 0.70)
          ..quadraticBezierTo(w * 0.85, h * 0.50, w * 0.75, h * 0.30)
          ..quadraticBezierTo(w * 0.50, h * 0.45, w * 0.25, h * 0.30)
          ..close();
        final col = _hasLipColor ? _effectiveLipFill : const Color(0xFFFF6B8A);
        final rect = Rect.fromLTWH(0, 0, w, h);
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(col, const Color(0xFF4A2040), 0.18)!,
                col,
                Color.lerp(col, const Color(0xFFFFF0E0), 0.1)!,
              ],
            ).createShader(rect),
        );

        // Lip highlight
        final highlightRect = Rect.fromCenter(
          center: Offset(w * 0.48, h * 0.42),
          width: w * 0.15,
          height: h * 0.12,
        );
        canvas.drawOval(
          highlightRect,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.25),
                Colors.transparent,
              ],
            ).createShader(highlightRect),
        );

      case 5: // Cat Smile
        final paint = Paint()
          ..color = _effectiveLipFill
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(w * 0.05, h * 0.30)
          ..quadraticBezierTo(w * 0.25, h * 0.70, w * 0.50, h * 0.25)
          ..quadraticBezierTo(w * 0.75, h * 0.70, w * 0.95, h * 0.30);
        canvas.drawPath(path, paint);

      case 6: // Smirk
        if (_hasLipColor) {
          final path = Path()
            ..moveTo(w * 0.15, h * 0.40)
            ..quadraticBezierTo(w * 0.55, h * 0.35, w * 0.90, h * 0.15)
            ..quadraticBezierTo(w * 0.55, h * 0.80, w * 0.15, h * 0.40)
            ..close();
          canvas.drawPath(path, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h)));
        } else {
          final paint = Paint()
            ..color = _effectiveLipFill
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.07
            ..strokeCap = StrokeCap.round;
          final path = Path()
            ..moveTo(w * 0.15, h * 0.40)
            ..quadraticBezierTo(w * 0.55, h * 0.60, w * 0.90, h * 0.15);
          canvas.drawPath(path, paint);
        }

      case 7: // Tiny Smile
        if (_hasLipColor) {
          final path = Path()
            ..moveTo(w * 0.30, h * 0.35)
            ..quadraticBezierTo(w * 0.50, h * 0.75, w * 0.70, h * 0.35)
            ..quadraticBezierTo(w * 0.50, h * 0.50, w * 0.30, h * 0.35)
            ..close();
          canvas.drawPath(path, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h)));
        } else {
          final paint = Paint()
            ..color = _effectiveLipFill
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.06
            ..strokeCap = StrokeCap.round;
          canvas.drawArc(
            Rect.fromLTWH(w * 0.25, -h * 0.1, w * 0.50, h * 0.80),
            0.3,
            pi * 0.4,
            false,
            paint,
          );
        }
    }
  }

  /// Talking mouth — open oval that scales with [amount] (0..1).
  /// Talking mouth with viseme interpolation.
  ///
  /// amount 0.0 = closed (lips together)
  /// amount 0.3 = slightly_open (consonants)
  /// amount 0.7 = open (vowels like "eh", "ih")
  /// amount 1.0 = wide_open (for "ah", "oh")
  ///
  /// Bezier control points lerp between these poses for smooth blending.
  void _drawTalkingMouth(Canvas canvas, double w, double h, double amount) {
    // Jaw drops with openness — subtle Y offset for realism
    final jawDrop = h * 0.08 * amount;
    final center = Offset(w * 0.5, h * 0.4 + jawDrop * 0.5);

    // Interpolate mouth dimensions between 4 viseme keyframes
    // Closed → slightly_open → open → wide_open
    final openH = _lerpViseme(amount, h * 0.08, h * 0.25, h * 0.55, h * 0.85);
    final openW = _lerpViseme(amount, w * 0.45, w * 0.38, w * 0.48, w * 0.55);

    // Build mouth shape as bezier path (more natural than oval)
    final mouthPath = Path();
    final topY = center.dy - openH * 0.5;
    final botY = center.dy + openH * 0.5;
    final leftX = center.dx - openW * 0.5;
    final rightX = center.dx + openW * 0.5;

    // Upper lip arch (flatter) + lower lip curve (rounder)
    final upperArch = openH * (0.15 + amount * 0.1);
    final lowerArch = openH * (0.3 + amount * 0.2);

    mouthPath.moveTo(leftX, center.dy - openH * 0.1);
    mouthPath.quadraticBezierTo(center.dx, topY - upperArch, rightX, center.dy - openH * 0.1);
    mouthPath.quadraticBezierTo(center.dx, botY + lowerArch, leftX, center.dy - openH * 0.1);
    mouthPath.close();

    final mouthRect = Rect.fromLTRB(leftX, topY, rightX, botY + lowerArch);

    // Dark mouth interior
    canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

    // Lip gradient outline
    canvas.drawPath(mouthPath, _lipGradientPaint(mouthRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04);

    // Teeth when mouth is open enough (viseme > slightly_open)
    if (amount > 0.2) {
      canvas.save();
      canvas.clipPath(mouthPath);
      final teethW = openW * 0.65;
      final teethH = openH * 0.18;
      _drawIndividualTeeth(canvas, center.dx - teethW * 0.5,
          center.dy - openH * 0.35, teethW, teethH, 4);
      canvas.restore();
    }

    // Tongue when mouth is wide enough (viseme > open)
    if (amount > 0.4) {
      final tongueAmount = ((amount - 0.4) / 0.6).clamp(0.0, 1.0);
      _drawTongue(
        canvas,
        Offset(center.dx, center.dy + openH * 0.15),
        openW * 0.5 * tongueAmount,
        openH * 0.3 * tongueAmount,
      );
    }
  }

  /// 4-keyframe linear interpolation for viseme blending.
  /// amount 0.0→v0, 0.33→v1, 0.67→v2, 1.0→v3
  static double _lerpViseme(double t, double v0, double v1, double v2, double v3) {
    if (t <= 0.33) {
      return v0 + (v1 - v0) * (t / 0.33);
    } else if (t <= 0.67) {
      return v1 + (v2 - v1) * ((t - 0.33) / 0.34);
    } else {
      return v2 + (v3 - v2) * ((t - 0.67) / 0.33);
    }
  }

  /// Excited mouth — big happy grin with teeth.
  void _drawExcitedMouth(Canvas canvas, double w, double h) {
    final mouthPath = Path()
      ..moveTo(w * 0.02, h * 0.15)
      ..quadraticBezierTo(w * 0.5, h * 1.4, w * 0.98, h * 0.15)
      ..close();

    canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

    canvas.save();
    canvas.clipPath(mouthPath);
    _drawIndividualTeeth(canvas, w * 0.15, h * 0.15, w * 0.7, h * 0.25, 6);
    canvas.restore();

    canvas.drawPath(mouthPath, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05);
  }

  /// Thinking mouth — small pursed 'o'.
  void _drawThinkingMouth(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.4);
    final ovalRect = Rect.fromCenter(center: center, width: w * 0.22, height: h * 0.45);

    canvas.drawOval(ovalRect, _lipGradientPaint(ovalRect));
    canvas.drawOval(
      Rect.fromCenter(center: center, width: w * 0.12, height: h * 0.25),
      Paint()..color = const Color(0xFF2D1A2E),
    );
  }

  /// Surprised mouth — wide round 'O' with visible teeth.
  void _drawSurprisedMouth(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.4);
    final outerRect = Rect.fromCenter(center: center, width: w * 0.50, height: h * 0.85);
    final innerRect = Rect.fromCenter(center: center, width: w * 0.35, height: h * 0.60);

    // Lip ring
    canvas.drawOval(outerRect, _lipGradientPaint(outerRect));

    // Dark mouth interior
    canvas.drawOval(innerRect, Paint()..color = const Color(0xFF2D1A2E));

    // Top teeth peeking
    canvas.save();
    canvas.clipPath(Path()..addOval(innerRect));
    _drawIndividualTeeth(canvas, center.dx - w * 0.12, center.dy - h * 0.28,
        w * 0.24, h * 0.15, 3);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MouthPainter old) =>
      old.style != style || old.lipColor != lipColor ||
      old.expression != expression || old.mouthOpenAmount != mouthOpenAmount;
}

// ═══════════════════════════════════════════════════════════════════════
//  NOSE PAINTER
//  - Nostril shadows with MaskFilter.blur
//  - Bridge highlight
//  - Breathing micro-animation (subtle nostril flare)
// ═══════════════════════════════════════════════════════════════════════

class NosePainter extends CustomPainter {
  final int style;
  final Color skinColor;
  final Animation<double> breathingValue;

  NosePainter({
    required this.style,
    required this.skinColor,
    required this.breathingValue,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final nosePaint = Paint()
      ..color = Color.lerp(skinColor, Colors.black, 0.12)!;
    final highlightPaint = Paint()
      ..color = Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.22)!;
    final shadowPaint = Paint()
      ..color = Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.22)!
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Breathing: nostrils flare slightly
    final breathFlare = breathingValue.value * 0.03;

    switch (style) {
      case 0: // Button
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.22, nosePaint);
        // Nostril shadows (with breathing flare)
        canvas.drawCircle(
            Offset(w * (0.36 - breathFlare), h * 0.58), w * 0.065, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.64 + breathFlare), h * 0.58), w * 0.065, shadowPaint);
        // Bridge highlight
        canvas.drawCircle(Offset(w * 0.53, h * 0.36), w * 0.09, highlightPaint);

      case 1: // Small
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.14, nosePaint);
        // Tiny nostrils
        canvas.drawCircle(
            Offset(w * (0.42 - breathFlare), h * 0.56), w * 0.035, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.58 + breathFlare), h * 0.56), w * 0.035, shadowPaint);
        canvas.drawCircle(Offset(w * 0.53, h * 0.42), w * 0.05, highlightPaint);

      case 2: // Round
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.28, nosePaint);
        canvas.drawCircle(
            Offset(w * (0.34 - breathFlare), h * 0.58), w * 0.075, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.66 + breathFlare), h * 0.58), w * 0.075, shadowPaint);
        canvas.drawCircle(Offset(w * 0.56, h * 0.34), w * 0.11, highlightPaint);

      case 3: // Pointed
        final path = Path()
          ..moveTo(w * 0.5, h * 0.15)
          ..quadraticBezierTo(w * 0.68, h * 0.55, w * 0.65, h * 0.80)
          ..quadraticBezierTo(w * 0.5, h * 0.92, w * 0.35, h * 0.80)
          ..quadraticBezierTo(w * 0.32, h * 0.55, w * 0.5, h * 0.15)
          ..close();
        canvas.drawPath(path, nosePaint);
        canvas.drawCircle(
            Offset(w * (0.40 - breathFlare), h * 0.78), w * 0.05, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.60 + breathFlare), h * 0.78), w * 0.05, shadowPaint);
        canvas.drawCircle(Offset(w * 0.52, h * 0.32), w * 0.06, highlightPaint);

      case 4: // Snub
        final path = Path()
          ..moveTo(w * 0.35, h * 0.30)
          ..quadraticBezierTo(w * 0.50, h * 0.10, w * 0.65, h * 0.30)
          ..quadraticBezierTo(w * 0.72, h * 0.60, w * 0.60, h * 0.75)
          ..quadraticBezierTo(w * 0.50, h * 0.82, w * 0.40, h * 0.75)
          ..quadraticBezierTo(w * 0.28, h * 0.60, w * 0.35, h * 0.30)
          ..close();
        canvas.drawPath(path, nosePaint);
        canvas.drawCircle(
            Offset(w * (0.42 - breathFlare), h * 0.68), w * 0.05, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.58 + breathFlare), h * 0.68), w * 0.05, shadowPaint);
        canvas.drawCircle(Offset(w * 0.52, h * 0.28), w * 0.06, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(NosePainter old) =>
      old.style != style || old.skinColor != skinColor;
}

// ═══════════════════════════════════════════════════════════════════════
//  CHEEK PAINTER
//  - Gaussian-like falloff (multi-stop radial gradient fading to transparent)
//  - Gradient-filled sparkle shapes
//  - Freckles with slight size variation
// ═══════════════════════════════════════════════════════════════════════

class CheekPainter extends CustomPainter {
  final int style;
  final Color skinColor;

  CheekPainter({required this.style, required this.skinColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCheek = Offset(w * 0.18, h * 0.50);
    final rightCheek = Offset(w * 0.82, h * 0.50);

    switch (style) {
      case 1: // Rosy — gaussian-like multi-stop radial gradient
        for (final center in [leftCheek, rightCheek]) {
          final rect = Rect.fromCenter(
              center: center, width: w * 0.24, height: h * 0.60);
          final gradient = RadialGradient(
            colors: [
              const Color(0xFFFF7090).withValues(alpha: 0.50),
              const Color(0xFFFF7090).withValues(alpha: 0.30),
              const Color(0xFFFF7090).withValues(alpha: 0.12),
              const Color(0xFFFF7090).withValues(alpha: 0.03),
              Colors.transparent,
            ],
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          );
          canvas.drawOval(
              rect, Paint()..shader = gradient.createShader(rect));
        }

      case 2: // Freckles — dots with random size variation
        final rng = Random(7);
        for (final center in [leftCheek, rightCheek]) {
          for (int i = 0; i < 7; i++) {
            final dx = (rng.nextDouble() - 0.5) * w * 0.16;
            final dy = (rng.nextDouble() - 0.5) * h * 0.45;
            final radius = w * 0.008 + rng.nextDouble() * w * 0.012;
            final darkness = 0.25 + rng.nextDouble() * 0.15;
            canvas.drawCircle(
              center.translate(dx, dy),
              radius,
              Paint()..color = Color.lerp(skinColor, Colors.brown, darkness)!,
            );
          }
        }

      case 3: // Blush — wide gaussian gradient
        for (final center in [leftCheek, rightCheek]) {
          final rect = Rect.fromCenter(
              center: center, width: w * 0.30, height: h * 0.75);
          final gradient = RadialGradient(
            colors: [
              const Color(0xFFFF6090).withValues(alpha: 0.40),
              const Color(0xFFFF6090).withValues(alpha: 0.22),
              const Color(0xFFFF6090).withValues(alpha: 0.08),
              const Color(0xFFFF6090).withValues(alpha: 0.02),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
          );
          canvas.drawOval(
              rect, Paint()..shader = gradient.createShader(rect));
        }

      case 4: // Sparkle — 4-point stars with gold gradient
        for (final center in [leftCheek, rightCheek]) {
          _drawGradientStar(canvas, center, w * 0.045, 4);
          _drawGradientStar(
              canvas, center.translate(w * 0.05, -h * 0.15), w * 0.028, 4);
          _drawGradientStar(
              canvas, center.translate(-w * 0.03, h * 0.1), w * 0.02, 4);
        }

      case 5: // Hearts — mini hearts with gradient fill
        for (final center in [leftCheek, rightCheek]) {
          _drawGradientHeart(canvas, center, w * 0.045);
        }

      case 6: // Stars — 5-point with gold gradient
        for (final center in [leftCheek, rightCheek]) {
          _drawGradientStar(canvas, center, w * 0.055, 5);
        }
    }
  }

  void _drawGradientStar(
      Canvas canvas, Offset center, double r, int points) {
    final path = Path();
    final innerRatio = points == 4 ? 0.35 : 0.4;
    for (int i = 0; i < points; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / points;
      final innerAngle = outerAngle + pi / points;
      final ox = center.dx + r * cos(outerAngle);
      final oy = center.dy + r * sin(outerAngle);
      final ix = center.dx + r * innerRatio * cos(innerAngle);
      final iy = center.dy + r * innerRatio * sin(innerAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();

    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.starGold,
            AppColors.starGold.withValues(alpha: 0.6),
          ],
        ).createShader(rect),
    );
  }

  void _drawGradientHeart(Canvas canvas, Offset center, double r) {
    final x = center.dx;
    final y = center.dy;
    final path = Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(
          x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(
          x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();

    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          colors: [
            const Color(0xFFFF7090),
            const Color(0xFFFF4D6A).withValues(alpha: 0.7),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CheekPainter old) =>
      old.style != style || old.skinColor != skinColor;
}

// ═══════════════════════════════════════════════════════════════════════
//  EYELASH PAINTER — curved bezier lash strokes
// ═══════════════════════════════════════════════════════════════════════

class EyelashPainter extends CustomPainter {
  final int style;
  final int eyeStyle;

  EyelashPainter({required this.style, required this.eyeStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftX = w * 0.25;
    final rightX = w * 0.75;
    final eyeY = h * 0.65;
    final r = w * 0.12;

    final lashPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (style) {
      case 1: // Natural — 3 curved lashes per eye
        lashPaint.strokeWidth = r * 0.12;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.4;
            _drawCurvedLash(canvas, cx, eyeY, r, angle, 0.8, 1.25, lashPaint);
          }
        }

      case 2: // Long — 3 longer curved lashes
        lashPaint.strokeWidth = r * 0.14;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.35;
            _drawCurvedLash(canvas, cx, eyeY, r, angle, 0.7, 1.55, lashPaint);
          }
        }

      case 3: // Dramatic — 5 curved lashes fanning out
        lashPaint.strokeWidth = r * 0.14;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 5; i++) {
            final angle = -pi * 0.75 + i * 0.25;
            _drawCurvedLash(canvas, cx, eyeY, r, angle, 0.75, 1.5, lashPaint);
          }
        }

      case 4: // Flutter — gracefully curved with taper
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 4; i++) {
            final angle = -pi * 0.7 + i * 0.28;
            // Taper: outer lashes thinner
            lashPaint.strokeWidth = r * (0.14 - i * 0.01);
            _drawCurvedLash(canvas, cx, eyeY, r, angle, 0.78, 1.45, lashPaint);
          }
        }

      case 5: // Sparkle — curved lashes with tiny stars at tips
        lashPaint.strokeWidth = r * 0.12;
        final starPaint = Paint()..color = AppColors.starGold;
        for (final cx in [leftX, rightX]) {
          for (int i = 0; i < 3; i++) {
            final angle = -pi / 2 + (i - 1) * 0.4;
            final endX = cx + r * 1.3 * cos(angle - 0.08);
            final endY = eyeY + r * 1.3 * sin(angle - 0.08);
            _drawCurvedLash(canvas, cx, eyeY, r, angle, 0.8, 1.3, lashPaint);
            _drawTinyStar(canvas, Offset(endX, endY), r * 0.15, starPaint);
          }
        }
    }
  }

  /// Helper: draw a single curved lash at the given angle.
  void _drawCurvedLash(Canvas canvas, double cx, double eyeY, double r,
      double angle, double innerMul, double outerMul, Paint paint) {
    final startX = cx + r * innerMul * cos(angle);
    final startY = eyeY + r * innerMul * sin(angle);
    final endX = cx + r * outerMul * cos(angle - 0.08);
    final endY = eyeY + r * outerMul * sin(angle - 0.08);
    final ctrlX = cx + r * (innerMul + outerMul) * 0.5 * cos(angle + 0.12);
    final ctrlY = eyeY + r * (innerMul + outerMul) * 0.5 * sin(angle + 0.12);
    final path = Path()
      ..moveTo(startX, startY)
      ..quadraticBezierTo(ctrlX, ctrlY, endX, endY);
    canvas.drawPath(path, paint);
  }

  void _drawTinyStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      if (i == 0) {
        path.moveTo(center.dx, center.dy - r);
      }
      path.lineTo(center.dx + r * 0.3 * cos(angle + pi / 4),
          center.dy + r * 0.3 * sin(angle + pi / 4));
      path.lineTo(center.dx + r * cos(angle + pi / 2),
          center.dy + r * sin(angle + pi / 2));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(EyelashPainter old) =>
      old.style != style || old.eyeStyle != eyeStyle;
}

// ═══════════════════════════════════════════════════════════════════════
//  EYEBROW PAINTER — gradient fill matching hair color, warm-cool shift
// ═══════════════════════════════════════════════════════════════════════

class EyebrowPainter extends CustomPainter {
  final int style;
  final Color color;

  EyebrowPainter({required this.style, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final browColor = Color.lerp(color, const Color(0xFF1A1A2E), 0.3)!;

    final leftStart = Offset(w * 0.10, h * 0.50);
    final leftEnd = Offset(w * 0.40, h * 0.50);
    final rightStart = Offset(w * 0.60, h * 0.50);
    final rightEnd = Offset(w * 0.90, h * 0.50);

    Paint browPaint(Rect bounds) {
      return Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(browColor, const Color(0xFF4A3A6E), 0.1)!, // cool edge
            browColor, // center
            Color.lerp(browColor, const Color(0xFF4A3A6E), 0.1)!, // cool edge
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
    }

    switch (style) {
      case 0: // Natural
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, p);

      case 1: // Thin
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.022;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.20, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.20, p);

      case 2: // Thick
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.055;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, p);

      case 3: // Arched
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.50, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.50, p);

      case 4: // Straight
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        canvas.drawLine(leftStart, leftEnd, p);
        canvas.drawLine(rightStart, rightEnd, p);

      case 5: // Bushy
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.05;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.22, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.22, p);
        // Extra texture strokes for bushy look
        final pThin = Paint()
          ..color = browColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w * 0.02;
        _drawBrow(canvas, leftStart.translate(0, -h * 0.08),
            leftEnd.translate(0, -h * 0.08), -h * 0.15, pThin);
        _drawBrow(canvas, rightStart.translate(0, -h * 0.08),
            rightEnd.translate(0, -h * 0.08), -h * 0.15, pThin);
        // Additional wispy strokes
        final pWisp = Paint()
          ..color = browColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w * 0.012;
        _drawBrow(canvas, leftStart.translate(w * 0.02, h * 0.05),
            leftEnd.translate(-w * 0.02, h * 0.05), -h * 0.18, pWisp);
        _drawBrow(canvas, rightStart.translate(w * 0.02, h * 0.05),
            rightEnd.translate(-w * 0.02, h * 0.05), -h * 0.18, pWisp);
    }
  }

  void _drawBrow(
      Canvas canvas, Offset start, Offset end, double archHeight, Paint paint) {
    final mid = Offset((start.dx + end.dx) / 2, start.dy + archHeight);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(EyebrowPainter old) =>
      old.style != style || old.color != color;
}

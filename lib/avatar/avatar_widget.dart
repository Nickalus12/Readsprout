import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'data/avatar_options.dart';
import '../models/player_profile.dart';
import 'animation/gyroscope.dart';
import '../theme/app_theme.dart';
import 'painters/accessory_painters.dart';
import 'animation/animation_system.dart';
import 'painters/body_painters.dart' hide shirtColorOptions;
import 'painters/effects_painters.dart';
import 'painters/hair_painters.dart' show HairBackPainter, HairFrontPainter;
import 'shader_loader.dart';
import 'animation/skeleton.dart';

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
///   3. Body (neck, torso, shoulders, arms, hands)
///   4. Hair back layer (HairBackPainter)
///   5. Hair front layer (HairFrontPainter) — behind face so face is always visible
///   6. Head bone group (face + all features, sway-rotated together):
///      a. Face (3D skin gradient, ears, chin shadow, nose-bridge AO)
///      b. Nose (with breathing nostril micro-anim)
///      c. Cheeks (gaussian radial blush)
///      d. Eyes (full iris detail, eyelid-sweep blink, pupil tracking)
///      e. Eyelashes (curved strokes)
///      f. Eyebrows (gradient fill)
///      g. Mouth (gradient lips, individual teeth, tongue center-line)
///      h. Face paint (FacePaintPainter)
///      i. Glasses (GlassesPainter)
///   7. Accessories (accessoryPainter dispatcher)
///   8. Sparkle effects (SparklePainter)
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

  /// Expression intensity (0.0 = neutral, 1.0 = full expression).
  /// Smoothly ramps up/down for organic transitions instead of snapping.
  double _expressionIntensity = 0.0;
  AvatarExpression _targetExpression = AvatarExpression.neutral;

  AvatarExpression get expression => _expression;
  double get mouthOpenAmount => _mouthOpenAmount;
  bool get isTalking => _expression == AvatarExpression.talking;

  /// Intensity of the current expression (0.0-1.0). Use this in painters
  /// to lerp between neutral and full expression for smooth transitions.
  double get expressionIntensity => _expressionIntensity;

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
  /// Intensity ramps up smoothly over ~150ms via [updateTalkingFrame].
  void setExpression(AvatarExpression expr, {Duration duration = const Duration(seconds: 2)}) {
    _expressionTimer?.cancel();
    _expression = expr;
    _targetExpression = expr;
    // Start at partial intensity — the tick loop lerps to 1.0
    if (expr != AvatarExpression.neutral) {
      _expressionIntensity = 0.3; // start visible immediately, ramp to full
    }
    notifyListeners();

    if (expr != AvatarExpression.neutral) {
      _expressionTimer = Timer(duration, () {
        _targetExpression = AvatarExpression.neutral;
        // Don't snap — the tick loop will lerp intensity down to 0
        // and then switch expression to neutral
        notifyListeners();
      });
    }
  }

  // ── Talking state (driven by widget tick loop, not a separate timer) ──
  int _talkStartMs = 0;
  int _talkDurationMs = 0;
  double _talkBaseFreq = 7.0;
  double _talkAmpBase = 0.55;
  double _talkAmpRange = 0.20;

  /// Simulate talking with organic mouth movement for [duration].
  ///
  /// Sets up parameters for the talking animation. The actual mouth value
  /// is computed each frame by [updateTalkingFrame] called from the widget's
  /// vsync-driven tick loop, avoiding race conditions from separate timers.
  void simulateTalking({Duration duration = const Duration(seconds: 2)}) {
    _expressionTimer?.cancel();
    _talkingTimer?.cancel();
    _talkCycleTimer?.cancel();

    _expression = AvatarExpression.talking;
    _mouthOpenAmount = 0.0;

    _talkStartMs = DateTime.now().millisecondsSinceEpoch;
    _talkDurationMs = duration.inMilliseconds;

    // Randomized per-session parameters for organic feel
    _talkBaseFreq = 5.0 + _rng.nextDouble() * 5.0;   // 5–10 Hz
    _talkAmpBase = 0.45 + _rng.nextDouble() * 0.3;    // 0.45–0.75 base
    _talkAmpRange = 0.15 + _rng.nextDouble() * 0.20;  // variation range

    notifyListeners();

    // Auto-stop after duration
    _talkingTimer = Timer(duration, () {
      stopTalking();
    });
  }

  /// Called each frame from the widget's tick loop to update mouth openness
  /// and expression intensity in sync with the render cycle.
  void updateTalkingFrame() {
    // ── Expression intensity lerp (smooth transitions) ──
    const lerpSpeed = 8.0; // ~125ms to reach full intensity
    if (_targetExpression != AvatarExpression.neutral) {
      // Ramp up toward 1.0
      _expressionIntensity = (_expressionIntensity + 0.016 * lerpSpeed)
          .clamp(0.0, 1.0);
    } else if (_expression != AvatarExpression.neutral) {
      // Ramp down toward 0.0, then switch to neutral
      _expressionIntensity = (_expressionIntensity - 0.016 * lerpSpeed)
          .clamp(0.0, 1.0);
      if (_expressionIntensity <= 0.01) {
        _expression = AvatarExpression.neutral;
        _expressionIntensity = 0.0;
        _mouthOpenAmount = 0.0;
      }
    }

    // ── Talking mouth animation ──
    if (_expression != AvatarExpression.talking || _talkDurationMs == 0) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - _talkStartMs;
    final t = elapsed / 1000.0; // seconds
    const rampMs = 100.0;

    // Ramp envelope: ease in at start, ease out at end
    double envelope = 1.0;
    if (elapsed < rampMs) {
      envelope = elapsed / rampMs;
    } else if (elapsed > _talkDurationMs - rampMs) {
      envelope = ((_talkDurationMs - elapsed) / rampMs).clamp(0.0, 1.0);
    }

    // Multi-layer oscillation for organic mouth movement
    final layer1 = sin(t * _talkBaseFreq * 2 * pi) * 0.5 + 0.5;
    final layer2 = sin(t * _talkBaseFreq * 1.3 * 2 * pi + 0.7) * 0.3 + 0.5;
    final layer3 = sin(t * _talkBaseFreq * 0.5 * 2 * pi + 2.1) * 0.2 + 0.5;

    // Combine layers with randomized amplitude
    final amplitude = _talkAmpBase + sin(t * 1.7) * _talkAmpRange;
    final raw = (layer1 * 0.5 + layer2 * 0.3 + layer3 * 0.2) * amplitude;

    _mouthOpenAmount = (raw * envelope).clamp(0.0, 1.0);
    // No notifyListeners — widget tick loop handles repaints
  }

  /// Stop any active talking animation and return to idle mouth.
  void stopTalking() {
    _talkCycleTimer?.cancel();
    _talkCycleTimer = null;
    _talkingTimer?.cancel();
    _talkingTimer = null;
    _talkDurationMs = 0;
    _mouthOpenAmount = 0.0;
    _expression = AvatarExpression.neutral;
    notifyListeners();
  }

  // ── Animation clip playback (driven by widget's mixer) ──────────────
  String? _pendingClip;

  /// The name of a clip queued for playback (consumed by widget each frame).
  String? consumePendingClip() {
    final clip = _pendingClip;
    _pendingClip = null;
    return clip;
  }

  /// Trigger an authored animation clip by name (e.g. 'wave', 'celebrate').
  /// The AvatarWidget picks this up on the next frame and plays it via the mixer.
  void playAnimation(String clipName) {
    _pendingClip = clipName;
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
    // Controller changes (expression, look target) need a widget rebuild
    // to update Positioned offsets (jawDrop, browOffset). Painters are
    // driven by _repaintNotifier so they don't need setState.
    if (mounted) {
      // Only rebuild if expression or look target actually changed —
      // mouth openness during talking is handled by _repaintNotifier
      setState(() {});
    }
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
    // Natural blink interval: 3-6 seconds (every 3-5s on average)
    final delayMs = 3000 + _rng.nextInt(3000);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || !widget.animateEffects) return;
      _isBlinking = true;
      _blinkPhase = 0.0;
    });
  }

  // ── Game loop — called every frame (~60fps) ─────────────────────────

  void _onTick() {
    if (!mounted || !_tickCtrl.isAnimating) return;

    final now = _tickCtrl.value * 3600.0; // hours → seconds
    final dt = _lastTickTime == 0.0
        ? 0.016
        : (now - _lastTickTime).clamp(0.001, 0.05);
    _lastTickTime = now;
    _totalTime += dt;

    // 0. Check for pending animation clip from controller
    final pendingClip = widget.controller?.consumePendingClip();
    if (pendingClip != null) {
      final clip = AvatarAnimations.all[pendingClip];
      if (clip != null) {
        _mixer.play(clip);
      }
    }

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

    // 6b. Update talking mouth from controller (synced with vsync tick)
    // Guard: only update if widget is still mounted and controller exists
    if (mounted) widget.controller?.updateTalkingFrame();

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

    // 8. Trigger CustomPainter repaints via the shared notifier.
    //    This does NOT rebuild the widget tree — only repaints canvases.
    _repaintNotifier.notify();

    // 9. Only call setState (full widget rebuild) when skeleton-driven
    //    transforms have changed enough to matter. The head rotation
    //    drives a Transform widget, so it needs a rebuild — but only
    //    when the quantized value actually changes (saves ~90% of rebuilds).
    final headStorage = _skeleton.head.worldTransform.storage;
    final newSwayQ = (atan2(headStorage[1], headStorage[0]) * 200).round();
    final newJawQ = ((widget.controller?.mouthOpenAmount ?? 0.0) * 50).round();
    if (newSwayQ != _lastSwayQ || newJawQ != _lastJawQ) {
      _lastSwayQ = newSwayQ;
      _lastJawQ = newJawQ;
      setState(() {});
    }
  }

  int _lastSwayQ = 0;
  int _lastJawQ = 0;

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

  Color get _skinColor {
    if (widget.config.skinToneValue >= 0.0) {
      return skinColorFromSlider(widget.config.skinToneValue);
    }
    return skinColorForIndex(widget.config.skinTone);
  }

  Color get _eyeColor {
    final idx = widget.config.eyeColor.clamp(0, eyeColorOptions.length - 1);
    return eyeColorOptions[idx].color;
  }

  Color get _lipColor {
    final idx = widget.config.lipColor.clamp(0, lipColorOptions.length - 1);
    return lipColorOptions[idx].color;
  }

  // ── Face geometry ──────────────────────────────────────────────────

  double get _faceTop => 0.12;

  /// Scaled head size: 45% of widget height for chibi-realism blend.
  /// Head bottom aligns with NeckPainter.topProportion (0.65).
  double _headSize(double s) {
    final widgetH = s / widget.aspectRatio;
    return widgetH * 0.45;
  }

  double get _faceHeightFraction {
    final shape = faceShapeOptions[
        widget.config.faceShape.clamp(0, faceShapeOptions.length - 1)];
    return 0.70 * shape.heightRatio;
  }

  // ── Bone/transform hierarchy helpers ─────────────────────────────

  /// Eyebrow vertical offset based on expression, lerped by intensity
  /// for smooth transitions instead of snapping.
  double _browOffsetY(double size) {
    final expr = widget.controller?.expression ?? AvatarExpression.neutral;
    final intensity = widget.controller?.expressionIntensity ?? 1.0;
    final target = switch (expr) {
      AvatarExpression.surprised => -size * 0.04,
      AvatarExpression.excited => -size * 0.03,
      AvatarExpression.thinking => size * 0.018,
      AvatarExpression.happy => -size * 0.012,
      _ => 0.0,
    };
    return target * intensity;
  }

  /// Jaw drop driven by mouth openness — pulls mouth and lower cheeks down.
  /// Exaggerated for kids to clearly see talking animation.
  double _jawDrop(double size) {
    final openness = widget.controller?.mouthOpenAmount ?? 0.0;
    return openness * size * 0.045;
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
                          config.shirtColor.clamp(0, shirtColorOptions.length - 1)].color,
                      collarStyle: config.shirtStyle.clamp(0, 2),
                      headTilt: swayAngle,
                      breathingValue: _breathingValue,
                      swayValue: _idleSwayValue,
                      leftHandPose: handPoseForClip(_mixer.activeClipName).left,
                      rightHandPose: handPoseForClip(_mixer.activeClipName).right,
                      leftArmRotation: _skeleton.leftUpperArm.animationRotation,
                      rightArmRotation: _skeleton.rightUpperArm.animationRotation,
                      leftShoulderDy: _skeleton.leftShoulder.animationOffset.dy,
                      rightShoulderDy: _skeleton.rightShoulder.animationOffset.dy,
                    ),
                  ),
                ),

              // ── Head/hair geometry ──
              // Head: 45% of widgetH, bottom aligns with neck top (0.65)
              // Hair: 15% larger than head for volume, centered on head
              ..._buildHeadAndHair(widgetW, widgetH, size, config, swayAngle,
                  breathingAnim, swayAnim, blinkAnim, pupilAnim),

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

  // ── Head/hair/accessories builder ─────────────────────────────────
  // Returns a list of Positioned widgets for the head bone, hair layers,
  // and accessories. All positioned relative to NeckPainter.topProportion.

  List<Widget> _buildHeadAndHair(
    double widgetW,
    double widgetH,
    double size,
    AvatarConfig config,
    double swayAngle,
    Animation<double> breathingAnim,
    Animation<double> swayAnim,
    Animation<double> blinkAnim,
    Animation<double> pupilAnim,
  ) {
    final headSize = _headSize(size);
    final headTop = widgetH * 0.65 - headSize * 0.62; // chin well into neck for seamless join
    final headLeft = (widgetW - headSize) / 2;

    // Hair is 15% larger for volume, centered on head
    final hairSize = headSize * 1.15;
    final hairLeft = headLeft - (hairSize - headSize) / 2;
    final hairTop = headTop - (hairSize - headSize) / 2;

    final browOffset = _browOffsetY(headSize);
    final jawDrop = _jawDrop(headSize);

    return [
      // 4-5. Hair layers — skip at thumbnail sizes for performance
      if (size >= 48) ...[
        // 4. Hair back layer
        Positioned(
          left: hairLeft,
          top: hairTop,
          width: hairSize,
          height: hairSize,
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

        // 5. Hair front layer
        Positioned(
          left: hairLeft,
          top: hairTop,
          width: hairSize,
          height: hairSize,
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
      ],

      // 6. Head bone: unified sway rotation for all face features
      // Pivot at bottom-center (neck connection point)
      Positioned(
        left: headLeft,
        top: headTop,
        width: headSize,
        height: headSize,
        child: Transform(
          transform: Matrix4.identity()
            ..translateByDouble(headSize / 2, headSize, 0, 1.0)
            ..rotateZ(swayAngle)
            ..translateByDouble(-headSize / 2, -headSize, 0, 1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Face shape
              Positioned(
                left: headSize * 0.15,
                top: headSize * _faceTop,
                child: CustomPaint(
                  size: Size(headSize * 0.70, headSize * _faceHeightFraction),
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
                left: headSize * 0.44,
                top: headSize * (_faceTop + _faceHeightFraction * 0.52),
                child: CustomPaint(
                  size: Size(headSize * 0.12, headSize * 0.10),
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

              // Cheeks — pass expression for blush intensity changes
              if (config.cheekStyle > 0)
                Positioned(
                  left: headSize * 0.18,
                  top: headSize * (_faceTop + _faceHeightFraction * 0.48),
                  child: CustomPaint(
                    size: Size(headSize * 0.64, headSize * 0.20),
                    isComplex: true,
                    painter: CheekPainter(
                      style: config.cheekStyle,
                      skinColor: _skinColor,
                      expression: widget.controller?.expression ??
                          AvatarExpression.neutral,
                    ),
                  ),
                ),

              // Eyes — oversized for child proportions (kids have ~40% larger
              // eye-to-face ratio than adults, key to cute/appealing look)
              Positioned(
                left: headSize * 0.24,
                top: headSize * (_faceTop + _faceHeightFraction * 0.26),
                child: CustomPaint(
                  size: Size(headSize * 0.52, headSize * 0.18),
                  isComplex: true,
                  willChange: widget.animateEffects,
                  painter: EyesPainter(
                    style: config.eyeStyle,
                    eyeColor: _eyeColor,
                    skinColor: _skinColor,
                    blinkValue: blinkAnim,
                    swayValue: swayAnim,
                    pupilDilationValue: pupilAnim,
                    expression: widget.controller?.expression ??
                        AvatarExpression.neutral,
                    expressionIntensity:
                        widget.controller?.expressionIntensity ?? 1.0,
                    lookTarget: widget.controller?.lookTarget,
                    avatarSize: headSize,
                    repaint: _repaintNotifier,
                  ),
                ),
              ),

              // Eyelashes — matched to enlarged eye area
              if (config.eyelashStyle > 0)
                Positioned(
                  left: headSize * 0.24,
                  top: headSize * (_faceTop + _faceHeightFraction * 0.20),
                  child: CustomPaint(
                    size: Size(headSize * 0.52, headSize * 0.22),
                    painter: EyelashPainter(
                      style: config.eyelashStyle,
                      eyeStyle: config.eyeStyle,
                    ),
                  ),
                ),

              // Eyebrows — matched to enlarged eye area
              Positioned(
                left: headSize * 0.24,
                top: headSize * (_faceTop + _faceHeightFraction * 0.14),
                child: Transform.translate(
                  offset: Offset(0, browOffset),
                  child: CustomPaint(
                    size: Size(headSize * 0.52, headSize * 0.10),
                    painter: EyebrowPainter(
                      style: config.eyebrowStyle,
                      color: _hairColor,
                    ),
                  ),
                ),
              ),

              // Mouth (jaw transform)
              Positioned(
                left: headSize * 0.35,
                top: headSize * (_faceTop + _faceHeightFraction * 0.68),
                child: Transform.translate(
                  offset: Offset(0, jawDrop),
                  child: CustomPaint(
                    size: Size(headSize * 0.30, headSize * 0.12),
                    isComplex: true,
                    willChange: widget.controller != null,
                    painter: MouthPainter(
                      style: config.mouthStyle,
                      lipColor: _lipColor,
                      expression: widget.controller?.expression ??
                          AvatarExpression.neutral,
                      mouthOpenAmount:
                          widget.controller?.mouthOpenAmount ?? 0.0,
                      repaint: widget.controller != null
                          ? _repaintNotifier
                          : null,
                    ),
                  ),
                ),
              ),

              // Face paint
              if (config.facePaint > 0)
                Positioned(
                  left: headSize * 0.15,
                  top: headSize * _faceTop,
                  child: CustomPaint(
                    size: Size(headSize * 0.70, headSize * _faceHeightFraction),
                    isComplex: true,
                    painter: FacePaintPainter(
                      style: config.facePaint,
                      skinColor: _skinColor,
                    ),
                  ),
                ),

              // Glasses — matched to enlarged eye area
              if (config.glassesStyle > 0)
                Positioned(
                  left: headSize * 0.24,
                  top: headSize * (_faceTop + _faceHeightFraction * 0.26),
                  child: CustomPaint(
                    size: Size(headSize * 0.52, headSize * 0.18),
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

      // 7. Accessories — positioned relative to head anatomy
      if (config.accessory > 1)
        ..._buildAccessory(config, headSize, headTop, headLeft, hairSize, hairLeft, hairTop, widgetW, widgetH),
    ];
  }

  // ── Accessory positioning ─────────────────────────────────────────
  // Accessories are categorized by where they attach to the avatar:
  //  - Head-top: crowns, hats, ears, horns, headbands (sit on top of head)
  //  - Wings: extend from shoulders (wider than head, centered on torso)
  //  - Full-head: ninja mask, halo (overlay the head region)

  // Head-top accessories (crowns, hats, ears, horns): all except wings
  // and full-head overlays — handled as the default case below.

  /// Accessories that extend from shoulders/back (wings).
  static const _wingAccessories = {7};

  /// Accessories that overlay the full head (ninja mask, halo).
  static const _fullHeadAccessories = {14, 21};

  List<Widget> _buildAccessory(
    AvatarConfig config,
    double headSize,
    double headTop,
    double headLeft,
    double hairSize,
    double hairLeft,
    double hairTop,
    double widgetW,
    double widgetH,
  ) {
    final accIdx = config.accessory;
    final painter = accessoryPainter(
      accIdx,
      swayValue: _idleSwayValue,
      twinklePhase: _twinkleValue,
    );
    if (painter == null) return [];

    if (_wingAccessories.contains(accIdx)) {
      // Wings: wider region centered on the body, extending from shoulders
      final wingW = widgetW * 0.95;
      final wingH = widgetH * 0.45;
      final wingLeft = (widgetW - wingW) / 2;
      final wingTop = widgetH * 0.35;
      return [
        Positioned(
          left: wingLeft,
          top: wingTop,
          width: wingW,
          height: wingH,
          child: CustomPaint(
            isComplex: true,
            willChange: widget.animateEffects,
            painter: painter,
          ),
        ),
      ];
    }

    if (_fullHeadAccessories.contains(accIdx)) {
      // Full-head overlays: same size as hair region
      return [
        Positioned(
          left: hairLeft,
          top: hairTop,
          width: hairSize,
          height: hairSize,
          child: CustomPaint(
            isComplex: true,
            willChange: widget.animateEffects,
            painter: painter,
          ),
        ),
      ];
    }

    // Head-top accessories: compact region on top of the head
    // Height is 45% of head, width matches head, positioned so base
    // sits at the top of the forehead (faceTop proportion)
    final accH = headSize * 0.45;
    final accW = headSize * 0.80;
    final accLeft = headLeft + (headSize - accW) / 2;
    // Base of accessory sits at the top of the face (forehead)
    final accTop = headTop + headSize * _faceTop - accH * 0.85;

    return [
      Positioned(
        left: accLeft,
        top: accTop,
        width: accW,
        height: accH,
        child: CustomPaint(
          isComplex: true,
          willChange: widget.animateEffects,
          painter: painter,
        ),
      ),
    ];
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
  bool _disposed = false;
  void notify() {
    if (!_disposed) notifyListeners();
  }
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
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
  final double time;

  FacePainter({
    required this.skinColor,
    required this.faceShape,
    required this.breathingValue,
    required this.swayValue,
    this.time = 0.0,
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

    // ── Chin ambient occlusion (softer, layered) ──
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 1.02),
        width: w * 0.70,
        height: h * 0.20,
      ),
      Paint()
        ..color = const Color(0xFF3A3060).withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0),
    );
    // Secondary softer chin shadow for natural falloff
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.96),
        width: w * 0.55,
        height: h * 0.12,
      ),
      Paint()
        ..color = const Color(0xFF3A3060).withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0),
    );

    // ── Ears ──
    _drawEars(canvas, w, h);

    // ── Face with warm-to-cool 3D gradient ──
    // Centered highlight for rounder child face (not asymmetric adult lighting)
    final faceRect = Rect.fromLTWH(0, 0, w, h);
    final warmHighlight = (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.18) ?? skinColor);
    final coolShadow = (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.10) ?? skinColor);
    final gradient = RadialGradient(
      // Centered slightly above middle for natural overhead lighting
      center: const Alignment(0.0, -0.30),
      radius: 0.90,
      colors: [
        warmHighlight,
        skinColor,
        (Color.lerp(skinColor, coolShadow, 0.35) ?? skinColor),
        coolShadow,
      ],
      stops: const [0.0, 0.32, 0.68, 1.0],
    );
    final gradientPaint = Paint()
      ..shader = gradient.createShader(faceRect);

    final facePath = _buildFacePath(w, h);
    canvas.drawPath(facePath, gradientPaint);

    // ── Subsurface scattering simulation (Dart fallback) ──
    // Blood flow under thin skin areas — key to making skin feel alive
    canvas.save();
    canvas.clipPath(facePath);
    // Warm glow at cheeks (visible blood flow under thin child skin)
    for (final cheekX in [w * 0.22, w * 0.78]) {
      final cheekSSS = Rect.fromCenter(
        center: Offset(cheekX, h * 0.55),
        width: w * 0.32,
        height: h * 0.26,
      );
      canvas.drawOval(
        cheekSSS,
        Paint()
          ..blendMode = BlendMode.overlay
          ..shader = RadialGradient(
            colors: [
              (Color.lerp(skinColor, const Color(0xFFFF9080), 0.40) ?? skinColor)
                  .withValues(alpha: 0.22),
              (Color.lerp(skinColor, const Color(0xFFFF8080), 0.25) ?? skinColor)
                  .withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(cheekSSS),
      );
    }
    // Warm glow at nose tip (SSS — thinnest skin on face)
    final noseTipSSS = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.58),
      width: w * 0.16,
      height: h * 0.12,
    );
    canvas.drawOval(
      noseTipSSS,
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(skinColor, const Color(0xFFFF9090), 0.35) ?? skinColor)
                .withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ).createShader(noseTipSSS),
    );
    // Warm glow at forehead center (thin skin over bone)
    final foreheadSSS = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.18),
      width: w * 0.35,
      height: h * 0.16,
    );
    canvas.drawOval(
      foreheadSSS,
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(skinColor, const Color(0xFFFFC8A0), 0.20) ?? skinColor)
                .withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(foreheadSSS),
    );
    // ── Temple shadows ──
    for (final templeX in [w * 0.08, w * 0.92]) {
      final templeRect = Rect.fromCenter(
        center: Offset(templeX, h * 0.28),
        width: w * 0.22,
        height: h * 0.28,
      );
      canvas.drawOval(
        templeRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              (Color.lerp(skinColor, const Color(0xFF5A4A7E), 0.18) ?? skinColor)
                  .withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ).createShader(templeRect),
      );
    }
    canvas.restore(); // end SSS + temple clip

    // ── Top rim light (warm highlight at forehead for 3D roundness) ──
    final rimLight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.55),
        radius: 0.7,
        colors: [
          const Color(0xFFFFF0D0).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5],
      ).createShader(faceRect);
    canvas.drawPath(facePath, rimLight);

    // ── Bottom edge shadow (chin/jaw ambient occlusion) ──
    final edgeAO = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, 0.55),
        radius: 0.7,
        colors: [
          Colors.transparent,
          const Color(0xFF4A3A6E).withValues(alpha: 0.08),
        ],
        stops: const [0.45, 1.0],
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

    // ── Philtrum (vertical indent between nose and upper lip) ──
    canvas.save();
    canvas.clipPath(facePath);
    final philtrumX = w * 0.5;
    final philtrumTop = h * 0.64;
    final philtrumBot = h * 0.74;
    final philtrumShadow = Paint()
      ..color = (Color.lerp(skinColor, const Color(0xFF5A4A7E), 0.15) ?? skinColor)
          .withValues(alpha: 0.12)
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(philtrumX - w * 0.018, philtrumTop),
      Offset(philtrumX - w * 0.012, philtrumBot),
      philtrumShadow,
    );
    canvas.drawLine(
      Offset(philtrumX + w * 0.018, philtrumTop),
      Offset(philtrumX + w * 0.012, philtrumBot),
      philtrumShadow,
    );
    canvas.drawLine(
      Offset(philtrumX, philtrumTop + h * 0.01),
      Offset(philtrumX, philtrumBot - h * 0.01),
      Paint()
        ..color = (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.12) ?? skinColor)
            .withValues(alpha: 0.10)
        ..strokeWidth = w * 0.008
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    // ── Head silhouette outline — very soft for child look ──
    // Thinner and more transparent than adult character
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.15) ?? skinColor)
          .withValues(alpha: 0.20);
    canvas.drawPath(facePath, outlinePaint);

    // ── Skin glow shader (GPU subsurface scattering) ──
    final skinShader = ShaderLoader.skinGlow;
    if (skinShader != null) {
      skinShader.setFloat(0, w);   // uSize.x
      skinShader.setFloat(1, h);   // uSize.y
      skinShader.setFloat(2, time); // uTime — real elapsed seconds
      canvas.save();
      canvas.clipPath(facePath);
      canvas.drawRect(
        faceRect,
        Paint()..shader = skinShader,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  void _drawEars(Canvas canvas, double w, double h) {
    // Smaller ears for child proportions (kids have smaller ear-to-head ratio)
    final earW = w * 0.11;
    final earH = h * 0.14;
    final earY = h * 0.38;

    for (final isLeft in [true, false]) {
      final cx = isLeft ? -earW * 0.25 : w + earW * 0.25;
      final earRect = Rect.fromCenter(
        center: Offset(cx, earY),
        width: earW,
        height: earH,
      );

      // Ear base with gradient
      final warmSide = (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.08) ?? skinColor);
      final coolSide = (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.08) ?? skinColor);
      final earGradient = RadialGradient(
        center: Alignment(isLeft ? 0.3 : -0.3, -0.2),
        radius: 0.8,
        colors: [warmSide, skinColor, coolSide],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawOval(earRect, Paint()..shader = earGradient.createShader(earRect));

      // Inner ear shadow — pinkish (slightly larger for realism)
      final innerCx = isLeft ? -earW * 0.15 : w + earW * 0.15;
      final innerRect = Rect.fromCenter(
        center: Offset(innerCx, earY),
        width: earW * 0.55,
        height: earH * 0.55,
      );
      canvas.drawOval(
        innerRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              (Color.lerp(skinColor, const Color(0xFFFF9090), 0.25) ?? skinColor)
                  .withValues(alpha: 0.45),
              Colors.transparent,
            ],
          ).createShader(innerRect),
      );

      // ── Inner ear fold/concha detail ──
      final foldPaint = Paint()
        ..color = (Color.lerp(skinColor, const Color(0xFF8A6A5E), 0.25) ?? skinColor)
            .withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = earW * 0.06
        ..strokeCap = StrokeCap.round;
      final foldPath = Path();
      final foldCx = isLeft ? -earW * 0.10 : w + earW * 0.10;
      final foldDir = isLeft ? -1.0 : 1.0;
      foldPath.moveTo(foldCx + foldDir * earW * 0.08, earY - earH * 0.22);
      foldPath.quadraticBezierTo(
        foldCx + foldDir * earW * 0.20, earY,
        foldCx + foldDir * earW * 0.06, earY + earH * 0.18,
      );
      canvas.drawPath(foldPath, foldPaint);

      // Tragus bump
      final tragusX = isLeft ? earW * 0.1 : w - earW * 0.1;
      canvas.drawCircle(
        Offset(tragusX, earY + earH * 0.02),
        earW * 0.06,
        Paint()
          ..color = (Color.lerp(skinColor, const Color(0xFF8A6A5E), 0.12) ?? skinColor)
              .withValues(alpha: 0.18),
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
      old.skinColor != skinColor ||
      old.faceShape != faceShape ||
      // Only repaint for time changes when the GPU skin glow shader is
      // actually loaded. Without it, time has no visual effect.
      (ShaderLoader.skinGlow != null && old.time != time);
}

// ═════════════════════════════════════════════════════════════════════
//  EYES PAINTER — Pixar-quality eye rendering
//  - Soft sclera gradient with subtle pink veining at edges
//  - Multi-layered iris: limbal ring, SweepGradient fiber overlay,
//    radial fiber lines, color depth gradient, caustic crescent
//  - Soft-edged pupil with responsive dilation
//  - Dual specular highlights with slight blue tint (catch light)
//  - Eye shadow under upper eyelid for depth
//  - Lower eyelid subtle line
//  - Eyelid-sweep blink (skin-colored shape sweeps down, not scaleY)
//  - Pupil dilation micro-animation
//  - Eye tracking (pupils shift with idle sway or lookTarget)
// ═════════════════════════════════════════════════════════════════════

class EyesPainter extends CustomPainter {
  final int style;
  final Color eyeColor;
  final Color skinColor;
  final Animation<double> blinkValue;
  final Animation<double> swayValue;
  final Animation<double> pupilDilationValue;
  final AvatarExpression expression;

  /// Smooth intensity of the expression (0.0-1.0) for lerped transitions.
  final double expressionIntensity;

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
    this.expressionIntensity = 1.0,
    this.lookTarget,
    this.avatarSize = 80,
    super.repaint,
  });

  // Mutable state set during paint() and read by sub-methods within the same
  // paint call. This avoids passing trackY through every drawing method's
  // parameter list. Safe because paint() is always single-threaded.
  double _currentTrackY = 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCenter = Offset(w * 0.25, h * 0.5);
    final rightCenter = Offset(w * 0.75, h * 0.5);

    // Expression-aware eye scaling — lerped via expressionIntensity for
    // smooth transitions instead of snapping between sizes
    final targetScale = switch (expression) {
      AvatarExpression.excited => 1.25,
      AvatarExpression.surprised => 1.35,
      AvatarExpression.thinking => 0.78,
      AvatarExpression.happy => 1.10,
      _ => 1.0,
    };
    final eyeScaleFactor = 1.0 + (targetScale - 1.0) * expressionIntensity;
    final eyeRadius = w * 0.12 * eyeScaleFactor;

    // Eye tracking: use lookTarget if set, otherwise idle sway
    double trackX;
    double trackY = 0.0;
    if (lookTarget != null) {
      final eyeAreaLeft = avatarSize * 0.26;
      final eyeAreaTop = avatarSize * 0.28;
      final eyesCenterX = eyeAreaLeft + w * 0.5;
      final eyesCenterY = eyeAreaTop + h * 0.5;
      final dx =
          ((lookTarget!.dx - eyesCenterX) / avatarSize).clamp(-1.0, 1.0);
      final dy =
          ((lookTarget!.dy - eyesCenterY) / avatarSize).clamp(-1.0, 1.0);
      trackX = dx * eyeRadius * 0.25;
      trackY = dy * eyeRadius * 0.15;
    } else {
      trackX = (swayValue.value - 0.5) * eyeRadius * 0.15;
    }

    // Pupil dilation: radius oscillates 0.28r <-> 0.35r
    final baseDilation =
        expression == AvatarExpression.surprised ? 0.32 : 0.28;
    final pupilScale = baseDilation + pupilDilationValue.value * 0.07;

    _currentTrackY = trackY;

    switch (style) {
      case 0: // Round
        _drawFullEye(canvas, leftCenter, eyeRadius, trackX, pupilScale);
        _drawFullEye(canvas, rightCenter, eyeRadius, trackX, pupilScale);
        _drawEyelid(canvas, leftCenter, eyeRadius, w);
        _drawEyelid(canvas, rightCenter, eyeRadius, w);
      case 1: // Star
        _drawStarEye(canvas, leftCenter, eyeRadius);
        _drawStarEye(canvas, rightCenter, eyeRadius);
      case 2: // Hearts
        _drawHeartEye(canvas, leftCenter, eyeRadius);
        _drawHeartEye(canvas, rightCenter, eyeRadius);
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

  // ----------------------------------------------------------------
  //  Shared rendering helpers
  // ----------------------------------------------------------------

  /// Sclera: soft white-to-cream radial gradient + subtle pink veining.
  void _drawSclera(Canvas canvas, Offset center, double r) {
    final scleraRect = Rect.fromCircle(center: center, radius: r);

    // Warm white-to-cream radial gradient
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Color(0xFFFFFEFC),
            Color(0xFFFAF8F5),
            Color(0xFFF0EDE8),
          ],
          stops: [0.0, 0.65, 1.0],
        ).createShader(scleraRect),
    );

    // Subtle pink veining near left/right edges
    final veinPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final veinRng = Random(17);
    for (int i = 0; i < 5; i++) {
      final side = i < 3 ? -1.0 : 1.0;
      final baseAngle = side > 0 ? 0.0 : pi;
      final angle = baseAngle + (veinRng.nextDouble() - 0.5) * 0.7;
      final startR = r * (0.72 + veinRng.nextDouble() * 0.15);
      final endR = r * (0.88 + veinRng.nextDouble() * 0.10);
      final startPt = Offset(
        center.dx + startR * cos(angle),
        center.dy + startR * sin(angle),
      );
      final endPt = Offset(
        center.dx + endR * cos(angle + (veinRng.nextDouble() - 0.5) * 0.3),
        center.dy + endR * sin(angle + (veinRng.nextDouble() - 0.5) * 0.3),
      );
      veinPaint
        ..color = const Color(0xFFE8A0A0)
            .withValues(alpha: 0.12 + veinRng.nextDouble() * 0.08)
        ..strokeWidth = r * (0.008 + veinRng.nextDouble() * 0.012);
      canvas.drawLine(startPt, endPt, veinPaint);
    }

    // Upper eyelid shadow cast onto sclera
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy - r * 0.15),
          [
            const Color(0xFF7080A0).withValues(alpha: 0.22),
            const Color(0xFF8892B0).withValues(alpha: 0.06),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  /// Multi-layered iris: base gradient, SweepGradient fiber overlay,
  /// radial fiber lines, caustic crescent, limbal ring.
  /// Vibrant saturated colors for kid appeal — eyes should sparkle.
  void _drawIris(Canvas canvas, Offset irisCenter, double irisR) {
    final irisRect = Rect.fromCircle(center: irisCenter, radius: irisR);

    // Boost iris saturation for more vibrant kid-friendly eyes
    final saturatedEye = HSLColor.fromColor(eyeColor)
        .withSaturation((HSLColor.fromColor(eyeColor).saturation * 1.15).clamp(0.0, 1.0))
        .withLightness((HSLColor.fromColor(eyeColor).lightness * 1.05).clamp(0.0, 1.0))
        .toColor();

    // 1. Base radial gradient — brighter center, richer edge
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            (Color.lerp(saturatedEye, Colors.white, 0.50) ?? saturatedEye),
            (Color.lerp(saturatedEye, Colors.white, 0.20) ?? saturatedEye),
            saturatedEye,
            (Color.lerp(saturatedEye, Colors.black, 0.25) ?? saturatedEye),
          ],
          stops: const [0.0, 0.22, 0.58, 1.0],
        ).createShader(irisRect),
    );

    // 2. SweepGradient fiber overlay
    canvas.save();
    canvas.clipPath(Path()..addOval(irisRect));

    const fiberCount = 36;
    final fiberColors = <Color>[];
    final fiberStops = <double>[];
    final fiberRng = Random(42);
    for (int i = 0; i < fiberCount; i++) {
      final t = i / fiberCount;
      final isLight = fiberRng.nextDouble() > 0.45;
      fiberColors.add(
        isLight
            ? (Color.lerp(eyeColor, Colors.white,
                    0.30 + fiberRng.nextDouble() * 0.15) ?? eyeColor)
                .withValues(alpha: 0.18)
            : (Color.lerp(eyeColor, Colors.black,
                    0.15 + fiberRng.nextDouble() * 0.10) ?? eyeColor)
                .withValues(alpha: 0.14),
      );
      fiberStops.add(t);
    }
    fiberColors.add(fiberColors.first);
    fiberStops.add(1.0);

    final fiberPath = Path()
      ..addOval(Rect.fromCircle(center: irisCenter, radius: irisR * 0.98))
      ..addOval(Rect.fromCircle(center: irisCenter, radius: irisR * 0.32))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      fiberPath,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: fiberColors,
          stops: fiberStops,
        ).createShader(irisRect),
    );

    // 3. Crisp radial fiber lines
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = irisR * 0.025;
    for (int i = 0; i < 28; i++) {
      final angle = (i / 28) * 2 * pi + fiberRng.nextDouble() * 0.08;
      final innerR2 = irisR * (0.30 + fiberRng.nextDouble() * 0.08);
      final outerR2 = irisR * (0.78 + fiberRng.nextDouble() * 0.18);
      linePaint.color = fiberRng.nextDouble() > 0.5
          ? (Color.lerp(eyeColor, Colors.white, 0.28) ?? eyeColor).withValues(alpha: 0.16)
          : (Color.lerp(eyeColor, Colors.black, 0.18) ?? eyeColor).withValues(alpha: 0.12);
      canvas.drawLine(
        Offset(irisCenter.dx + innerR2 * cos(angle),
            irisCenter.dy + innerR2 * sin(angle)),
        Offset(irisCenter.dx + outerR2 * cos(angle),
            irisCenter.dy + outerR2 * sin(angle)),
        linePaint,
      );
    }

    // 4. Caustic crescent
    final causticRect = Rect.fromCenter(
      center: irisCenter.translate(-irisR * 0.22, -irisR * 0.18),
      width: irisR * 1.1,
      height: irisR * 0.65,
    );
    canvas.drawOval(
      causticRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(eyeColor, Colors.white, 0.50) ?? eyeColor).withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ).createShader(causticRect),
    );

    canvas.restore();

    // 5. Limbal ring — thicker and more defined for cartoon readability
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = irisR * 0.13
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            (Color.lerp(saturatedEye, const Color(0xFF0A0A1A), 0.60) ?? saturatedEye)
                .withValues(alpha: 0.72),
          ],
          stops: const [0.82, 1.0],
        ).createShader(Rect.fromCircle(center: irisCenter, radius: irisR)),
    );
  }

  /// Pupil with soft-edged gradient.
  void _drawPupil(Canvas canvas, Offset pupilCenter, double pupilR) {
    canvas.drawCircle(
      pupilCenter,
      pupilR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF020208),
            const Color(0xFF050510),
            const Color(0xFF050510).withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: pupilCenter, radius: pupilR)),
    );
  }

  /// Dual specular highlights — larger and brighter for Pixar-quality
  /// catch-lights that make the eyes feel alive and sparkly.
  void _drawHighlights(Canvas canvas, Offset center, double r) {
    // Primary: large bright oval at upper-left (main window reflection)
    final bigCenter = center.translate(r * 0.26, -r * 0.26);
    final bigRect =
        Rect.fromCenter(center: bigCenter, width: r * 0.56, height: r * 0.42);
    canvas.drawOval(
      bigRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            const Color(0xFFF0F4FF).withValues(alpha: 0.65),
            const Color(0xFFE8EEFF).withValues(alpha: 0.20),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ).createShader(bigRect),
    );

    // Secondary: crisp round spot at lower-right (fill light)
    final smallCenter = center.translate(-r * 0.16, r * 0.22);
    final smallR = r * 0.14;
    final smallRect = Rect.fromCircle(center: smallCenter, radius: smallR);
    canvas.drawCircle(
      smallCenter,
      smallR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.82),
            const Color(0xFFE8F0FF).withValues(alpha: 0.30),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(smallRect),
    );

    // Tertiary: tiny sparkle dot for extra life (Pixar signature)
    final sparkleCenter = center.translate(r * 0.12, -r * 0.38);
    canvas.drawCircle(
      sparkleCenter,
      r * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.70),
    );
  }

  /// Subtle lower eyelid line for depth — warm tone for child look.
  void _drawLowerEyelid(Canvas canvas, Offset center, double r) {
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + r * 0.05),
        width: r * 1.9,
        height: r * 1.7,
      ),
      pi * 0.05,
      pi * 0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..strokeCap = StrokeCap.round
        ..color = (Color.lerp(skinColor, const Color(0xFF9080A0), 0.15) ?? skinColor)
            .withValues(alpha: 0.25),
    );
  }

  // ----------------------------------------------------------------
  //  Case 0: Round eye
  // ----------------------------------------------------------------

  void _drawFullEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    _drawSclera(canvas, center, r);

    final irisCenter = center.translate(r * 0.10 + trackX, _currentTrackY);
    _drawIris(canvas, irisCenter, r * 0.58);

    final pupilCenter = center.translate(r * 0.12 + trackX, _currentTrackY);
    _drawPupil(canvas, pupilCenter, r * pupilScale);

    _drawHighlights(canvas, center, r);
    _drawLowerEyelid(canvas, center, r);
  }

  // ----------------------------------------------------------------
  //  Eyelid blink
  // ----------------------------------------------------------------

  void _drawEyelid(Canvas canvas, Offset center, double r, double totalW) {
    final blink = blinkValue.value;
    if (blink < 0.01) return;

    final lidTop = center.dy - r * 1.1;
    final lidBottom = center.dy - r * 1.1 + (r * 2.2) * blink;

    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: r * 1.05)));

    final lidRect = Rect.fromLTWH(
        center.dx - r * 1.1, lidTop, r * 2.2, lidBottom - lidTop);
    canvas.drawRect(
      lidRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.05) ?? skinColor),
            skinColor,
            (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.10) ?? skinColor),
          ],
        ).createShader(lidRect),
    );

    // Crease shadow
    canvas.drawLine(
      Offset(center.dx - r * 0.9, lidBottom),
      Offset(center.dx + r * 0.9, lidBottom),
      Paint()
        ..color = (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.22) ?? skinColor)
            .withValues(alpha: 0.45)
        ..strokeWidth = r * 0.14
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Lash line
    if (blink > 0.25) {
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(center.dx, lidBottom),
            width: r * 1.8,
            height: r * 0.5),
        0,
        pi,
        false,
        Paint()
          ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.55 * blink)
          ..strokeWidth = r * 0.08
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    canvas.restore();
  }

  // ----------------------------------------------------------------
  //  Case 5: Almond eyelid
  // ----------------------------------------------------------------

  void _drawAlmondEyelid(Canvas canvas, Offset center, double r) {
    final blink = blinkValue.value;
    if (blink < 0.01) return;

    final lidTop = center.dy - r * 1.0;
    final lidBottom = center.dy - r * 1.0 + (r * 2.0) * blink;

    canvas.save();
    final almondPath = Path()
      ..moveTo(center.dx - r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + r * 0.8, center.dx - r * 1.2, center.dy)
      ..close();
    canvas.clipPath(almondPath);

    final lidRect = Rect.fromLTWH(
        center.dx - r * 1.3, lidTop, r * 2.6, lidBottom - lidTop);
    canvas.drawRect(
      lidRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.05) ?? skinColor),
            skinColor,
            (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.06) ?? skinColor),
          ],
        ).createShader(lidRect),
    );

    if (blink > 0.15) {
      canvas.drawLine(
        Offset(center.dx - r * 1.0, lidBottom),
        Offset(center.dx + r * 1.0, lidBottom),
        Paint()
          ..color = (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.18) ?? skinColor)
              .withValues(alpha: 0.35)
          ..strokeWidth = r * 0.10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  // ----------------------------------------------------------------
  //  Case 4: Sparkle
  // ----------------------------------------------------------------

  void _drawSparkleEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    final bigR = r * 1.3;

    _drawSclera(canvas, center, bigR);

    final irisCenter =
        center.translate(trackX * 0.5, _currentTrackY * 0.5);
    _drawIris(canvas, irisCenter, bigR * 0.65);
    _drawPupil(canvas, irisCenter, bigR * pupilScale * 0.85);

    // Multiple sparkle highlights
    final h1 = center.translate(bigR * 0.30, -bigR * 0.22);
    canvas.drawCircle(
      h1,
      bigR * 0.30,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFF8FCFF).withValues(alpha: 0.95),
            const Color(0xFFE0ECFF).withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: h1, radius: bigR * 0.30)),
    );
    canvas.drawCircle(
      center.translate(-bigR * 0.22, bigR * 0.26),
      bigR * 0.16,
      Paint()..color = const Color(0xFFF0F4FF).withValues(alpha: 0.65),
    );
    canvas.drawCircle(
      center.translate(bigR * 0.08, bigR * 0.35),
      bigR * 0.06,
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );
    canvas.drawCircle(
      center.translate(-bigR * 0.35, -bigR * 0.10),
      bigR * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.40),
    );
  }

  // ----------------------------------------------------------------
  //  Case 5: Almond eye
  // ----------------------------------------------------------------

  void _drawAlmondEye(Canvas canvas, Offset center, double r, double trackX,
      double pupilScale) {
    final path = Path()
      ..moveTo(center.dx - r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + r * 0.8, center.dx - r * 1.2, center.dy)
      ..close();

    canvas.save();
    canvas.clipPath(path);

    final scleraRect = Rect.fromCircle(center: center, radius: r * 1.2);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFEFC), Color(0xFFF5F2EE)],
        ).createShader(scleraRect),
    );

    canvas.drawRect(
      scleraRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy - r * 0.15),
          [
            const Color(0xFF7080A0).withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ),
    );

    final irisCenter = center.translate(r * 0.10 + trackX, _currentTrackY);
    _drawIris(canvas, irisCenter, r * 0.50);

    final pupilCenter = center.translate(r * 0.12 + trackX, _currentTrackY);
    _drawPupil(canvas, pupilCenter, r * pupilScale);
    _drawHighlights(canvas, center, r);

    canvas.restore();

    // Subtle eyeliner along top edge
    final linerPath = Path()
      ..moveTo(center.dx - r * 1.2, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.0, center.dx + r * 1.2, center.dy);
    canvas.drawPath(
      linerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = const Color(0xFF2A2040).withValues(alpha: 0.35)
        ..strokeCap = StrokeCap.round,
    );
  }

  // ----------------------------------------------------------------
  //  Case 3: Happy Crescents
  // ----------------------------------------------------------------

  void _drawCrescentEyes(Canvas canvas, Offset left, Offset right, double r) {
    for (final center in [left, right]) {
      // Outer glow
      canvas.drawArc(
        Rect.fromCenter(center: center, width: r * 2.2, height: r * 1.7),
        pi * 0.05,
        pi * 0.9,
        false,
        Paint()
          ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      // Gradient crescent
      canvas.drawArc(
        Rect.fromCenter(center: center, width: r * 2, height: r * 1.5),
        pi * 0.1,
        pi * 0.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.45
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(center.dx - r, center.dy),
            Offset(center.dx + r, center.dy),
            const [Color(0xFF2A2040), Color(0xFF1A1A2E), Color(0xFF2A2040)],
            [0.0, 0.5, 1.0],
          ),
      );
      // Tiny highlight
      canvas.drawArc(
        Rect.fromCenter(center: center, width: r * 1.4, height: r * 0.9),
        pi * 0.25,
        pi * 0.5,
        false,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ----------------------------------------------------------------
  //  Case 6: Wink
  // ----------------------------------------------------------------

  void _drawWinkEye(Canvas canvas, Offset center, double r) {
    canvas.drawArc(
      Rect.fromCenter(center: center, width: r * 2.2, height: r * 1.4),
      pi * 0.05,
      pi * 0.9,
      false,
      Paint()
        ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.55
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawArc(
      Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.2),
      pi * 0.1,
      pi * 0.8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.38
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(center.dx - r, center.dy),
          Offset(center.dx + r, center.dy),
          const [Color(0xFF2A2040), Color(0xFF1A1A2E), Color(0xFF2A2040)],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // ----------------------------------------------------------------
  //  Case 7: Sleepy
  // ----------------------------------------------------------------

  void _drawSleepyEyes(
      Canvas canvas, Offset left, Offset right, double r, double trackX) {
    for (final center in [left, right]) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          center.dx - r * 1.2, center.dy - r * 0.15, r * 2.4, r * 1.2));

      _drawSclera(canvas, center, r);

      // Iris with gradient (slight downward offset for sleepy droop)
      final irisCenter =
          center.translate(r * 0.1 + trackX, r * 0.05 + _currentTrackY);
      _drawIris(canvas, irisCenter, r * 0.55);
      _drawPupil(
        canvas,
        center.translate(r * 0.12 + trackX, r * 0.05 + _currentTrackY),
        r * 0.30,
      );
      _drawHighlights(canvas, center, r * 0.85);

      canvas.restore();

      // Sleepy droop lid line with gradient
      final droopRect = Rect.fromLTWH(
          center.dx - r * 0.9, center.dy - r * 0.25, r * 1.8, r * 0.30);
      canvas.drawLine(
        Offset(center.dx - r * 0.9, center.dy - r * 0.1),
        Offset(center.dx + r * 0.9, center.dy - r * 0.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.22
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.12) ?? skinColor)
                  .withValues(alpha: 0.45),
              (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.18) ?? skinColor)
                  .withValues(alpha: 0.65),
              (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.12) ?? skinColor)
                  .withValues(alpha: 0.45),
            ],
          ).createShader(droopRect),
      );
    }
  }

  // ----------------------------------------------------------------
  //  Case 1: Star eyes
  // ----------------------------------------------------------------

  void _drawStarEye(Canvas canvas, Offset center, double r) {
    final path = _starPath(center, r);

    // Outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.starGold.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
    // Gradient fill
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(AppColors.starGold, Colors.white, 0.40) ?? AppColors.starGold),
            AppColors.starGold,
            (Color.lerp(AppColors.starGold, const Color(0xFFCC7700), 0.35) ?? AppColors.starGold),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Inner highlight
    canvas.drawPath(
      _starPath(center.translate(r * 0.08, -r * 0.12), r * 0.45),
      Paint()..color = Colors.white.withValues(alpha: 0.30),
    );
  }

  // ----------------------------------------------------------------
  //  Case 2: Heart eyes
  // ----------------------------------------------------------------

  void _drawHeartEye(Canvas canvas, Offset center, double r) {
    final path = _heartPath(center, r);

    // Outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF4D6A).withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    // Gradient fill
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, -0.3),
          colors: [
            (Color.lerp(const Color(0xFFFF4D6A), Colors.white, 0.30) ?? const Color(0xFFFF4D6A)),
            const Color(0xFFFF4D6A),
            (Color.lerp(
                const Color(0xFFFF4D6A), const Color(0xFF9B1030), 0.40) ?? const Color(0xFFFF4D6A)),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Shine highlight
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-r * 0.25, -r * 0.35),
        width: r * 0.4,
        height: r * 0.3,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  // ----------------------------------------------------------------
  //  Shape helpers
  // ----------------------------------------------------------------

  Path _starPath(Offset center, double r) {
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
    return path;
  }

  Path _heartPath(Offset center, double r) {
    final x = center.dx;
    final y = center.dy;
    return Path()
      ..moveTo(x, y + r * 0.5)
      ..cubicTo(
          x - r * 1.2, y - r * 0.3, x - r * 0.5, y - r * 1.0, x, y - r * 0.3)
      ..cubicTo(
          x + r * 0.5, y - r * 1.0, x + r * 1.2, y - r * 0.3, x, y + r * 0.5)
      ..close();
  }

  @override
  bool shouldRepaint(EyesPainter old) =>
      old.style != style ||
      old.eyeColor != eyeColor ||
      old.skinColor != skinColor ||
      old.expression != expression ||
      old.lookTarget != lookTarget ||
      old.avatarSize != avatarSize;
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

  /// Falls back to dark fill when lip color is fully transparent.
  Color get _effectiveLipFill =>
      lipColor.a < 0.004 ? const Color(0xFF1A1A2E) : lipColor;

  /// True when the lip color has visible alpha (not fully transparent).
  bool get _hasLipColor => lipColor.a >= 0.004;

  Paint _lipGradientPaint(Rect rect) {
    final base = _effectiveLipFill;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (Color.lerp(base, const Color(0xFF4A2040), 0.2) ?? base), // cool dark top lip
          base,
          (Color.lerp(base, const Color(0xFFFFF0E0), 0.12) ?? base), // warm bottom lip
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
  }

  /// Draw cupid's bow detail on upper lip
  void _drawCupidsBow(Canvas canvas, double centerX, double topY, double mouthW) {
    final bowPath = Path()
      ..moveTo(centerX - mouthW * 0.12, topY + mouthW * 0.02)
      ..quadraticBezierTo(centerX - mouthW * 0.04, topY - mouthW * 0.04,
          centerX, topY + mouthW * 0.01)
      ..quadraticBezierTo(centerX + mouthW * 0.04, topY - mouthW * 0.04,
          centerX + mouthW * 0.12, topY + mouthW * 0.02);
    canvas.drawPath(
      bowPath,
      Paint()
        ..color = (Color.lerp(_effectiveLipFill, const Color(0xFF4A2040), 0.25) ?? _effectiveLipFill)
            .withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = mouthW * 0.015
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Draw subtle highlight line at center of lower lip
  void _drawLowerLipHighlight(Canvas canvas, double centerX, double lipY, double lipW) {
    final highlightRect = Rect.fromCenter(
      center: Offset(centerX, lipY),
      width: lipW * 0.25,
      height: lipW * 0.06,
    );
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ).createShader(highlightRect),
    );
  }

  /// Draw lip line where lips meet when closed
  void _drawLipLine(Canvas canvas, double centerX, double lineY, double lineW) {
    canvas.drawLine(
      Offset(centerX - lineW * 0.35, lineY),
      Offset(centerX + lineW * 0.35, lineY),
      Paint()
        ..color = (Color.lerp(_effectiveLipFill, const Color(0xFF2D1A2E), 0.35) ?? _effectiveLipFill)
            .withValues(alpha: 0.25)
        ..strokeWidth = lineW * 0.012
        ..strokeCap = StrokeCap.round,
    );
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

    // Base tongue gradient (pink tip → deeper red at back)
    canvas.drawOval(
      tongueRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFCC3050), // deeper red at back
            Color(0xFFE04060), // mid tone
            Color(0xFFFF8FAB), // pink at tip
          ],
          stops: [0.0, 0.4, 1.0],
        ).createShader(tongueRect),
    );

    // Radial overlay for natural edges
    canvas.drawOval(
      tongueRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.7,
          colors: [
            Colors.transparent,
            const Color(0xFFCC3050).withValues(alpha: 0.15),
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
    if (expression == AvatarExpression.happy) {
      _drawHappyMouth(canvas, w, h);
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
          // Lip line
          _drawLipLine(canvas, w * 0.5, h * 0.28, w);
          // Cupid's bow
          _drawCupidsBow(canvas, w * 0.5, h * 0.18, w * 0.6);
          // Lower lip highlight
          _drawLowerLipHighlight(canvas, w * 0.5, h * 0.40, w);
        } else {
          // No lip color: warm curved smile line with upturned ends
          final smilePath = Path()
            ..moveTo(w * 0.12, h * 0.28)
            ..quadraticBezierTo(w * 0.50, h * 0.85, w * 0.88, h * 0.28);
          canvas.drawPath(
            smilePath,
            Paint()
              ..color = const Color(0xFF2A2040)
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 0.065
              ..strokeCap = StrokeCap.round,
          );
          // Subtle mouth corner dots for warmth
          for (final x in [w * 0.13, w * 0.87]) {
            canvas.drawCircle(
              Offset(x, h * 0.30),
              w * 0.012,
              Paint()
                ..color = const Color(0xFF2A2040).withValues(alpha: 0.35)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
            );
          }
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
        // Cupid's bow
        _drawCupidsBow(canvas, w * 0.5, h * 0.18, w * 0.7);

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
                (Color.lerp(col, const Color(0xFF4A2040), 0.18) ?? col),
                col,
                (Color.lerp(col, const Color(0xFFFFF0E0), 0.1) ?? col),
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

    // Uvula hint when mouth is wide open
    if (amount > 0.7) {
      canvas.save();
      canvas.clipPath(mouthPath);
      final uvulaAlpha = ((amount - 0.7) / 0.3).clamp(0.0, 1.0);
      final uvulaRect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + openH * 0.08),
        width: openW * 0.06,
        height: openH * 0.10,
      );
      canvas.drawOval(
        uvulaRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFCC4060).withValues(alpha: 0.45 * uvulaAlpha),
              const Color(0xFF2D1A2E),
            ],
          ).createShader(uvulaRect),
      );
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

  /// Excited mouth — big joyful grin with teeth, the celebratory expression.
  void _drawExcitedMouth(Canvas canvas, double w, double h) {
    final mouthPath = Path()
      ..moveTo(w * 0.0, h * 0.12)
      ..quadraticBezierTo(w * 0.5, h * 1.45, w * 1.0, h * 0.12)
      ..close();

    canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

    // Teeth — wider row visible in big grin
    canvas.save();
    canvas.clipPath(mouthPath);
    _drawIndividualTeeth(canvas, w * 0.12, h * 0.12, w * 0.76, h * 0.26, 6);
    canvas.restore();

    // Thicker lip outline for excitement
    canvas.drawPath(mouthPath, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055);

    // Upturned corner creases for extreme joy
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(w * (0.5 + side * 0.49), h * 0.16),
        w * 0.022,
        Paint()
          ..color = const Color(0xFF4A3A6E).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      );
    }
  }

  /// Happy mouth — warm inviting smile with gentle teeth peek.
  /// The most common expression kids will see — should feel friendly.
  void _drawHappyMouth(Canvas canvas, double w, double h) {
    // Wider smile with upturned corners for warmth
    final mouthPath = Path()
      ..moveTo(w * 0.03, h * 0.20)
      ..quadraticBezierTo(w * 0.5, h * 1.18, w * 0.97, h * 0.20)
      ..quadraticBezierTo(w * 0.5, h * 0.48, w * 0.03, h * 0.20)
      ..close();

    // Dark mouth interior
    canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF2D1A2E));

    // Teeth peeking through the smile
    canvas.save();
    canvas.clipPath(mouthPath);
    _drawIndividualTeeth(canvas, w * 0.18, h * 0.20, w * 0.64, h * 0.20, 5);
    canvas.restore();

    // Lip gradient outline — slightly thicker for warmth
    canvas.drawPath(mouthPath, _lipGradientPaint(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05);

    // Cupid's bow
    _drawCupidsBow(canvas, w * 0.5, h * 0.18, w * 0.65);

    // Corner dimples — subtle warmth detail
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(w * (0.5 + side * 0.46), h * 0.24),
        w * 0.018,
        Paint()
          ..color = const Color(0xFF4A3A6E).withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
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

    // Uvula hint in back of throat
    canvas.save();
    canvas.clipPath(Path()..addOval(innerRect));
    final uvulaRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + h * 0.12),
      width: w * 0.04,
      height: h * 0.08,
    );
    canvas.drawOval(
      uvulaRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFCC4060).withValues(alpha: 0.5),
            const Color(0xFF2D1A2E),
          ],
        ).createShader(uvulaRect),
    );
    canvas.restore();

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
      ..color = (Color.lerp(skinColor, Colors.black, 0.12) ?? skinColor);
    final highlightPaint = Paint()
      ..color = (Color.lerp(skinColor, const Color(0xFFFFF8E0), 0.22) ?? skinColor);
    final shadowPaint = Paint()
      ..color = (Color.lerp(skinColor, const Color(0xFF4A3A6E), 0.22) ?? skinColor)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Breathing: nostrils flare subtly
    final breathFlare = breathingValue.value * 0.04;
    // Nostril size pulses with breathing
    final nostrilPulse = 1.0 + breathingValue.value * 0.12;

    switch (style) {
      case 0: // Button — soft, subtle bump rather than hard circle
        // Softer nose shape with gradient fade (not a solid circle)
        final noseRect = Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.5),
          width: w * 0.44,
          height: h * 0.44,
        );
        canvas.drawOval(
          noseRect,
          Paint()
            ..shader = RadialGradient(
              colors: [
                nosePaint.color.withValues(alpha: 0.65),
                nosePaint.color.withValues(alpha: 0.25),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(noseRect),
        );
        // Nostril shadows (with breathing flare + pulse) — smaller for child
        canvas.drawCircle(
            Offset(w * (0.38 - breathFlare), h * 0.58), w * 0.055 * nostrilPulse, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.62 + breathFlare), h * 0.58), w * 0.055 * nostrilPulse, shadowPaint);
        // Bridge highlight
        canvas.drawCircle(Offset(w * 0.53, h * 0.36), w * 0.09, highlightPaint);
        // Nose bridge shadow refinement
        _drawBridgeShadow(canvas, w, h);
        // SSS glow at tip
        _drawNoseTipGlow(canvas, w, h, Offset(w * 0.5, h * 0.5));
        // Specular highlight at tip
        _drawNoseSpecular(canvas, w, h, Offset(w * 0.52, h * 0.42));

      case 1: // Small — barely-there button nose, most kid-friendly
        final smallNoseRect = Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.5),
          width: w * 0.28,
          height: h * 0.28,
        );
        canvas.drawOval(
          smallNoseRect,
          Paint()
            ..shader = RadialGradient(
              colors: [
                nosePaint.color.withValues(alpha: 0.50),
                nosePaint.color.withValues(alpha: 0.15),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(smallNoseRect),
        );
        canvas.drawCircle(
            Offset(w * (0.42 - breathFlare), h * 0.56), w * 0.032 * nostrilPulse, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.58 + breathFlare), h * 0.56), w * 0.032 * nostrilPulse, shadowPaint);
        canvas.drawCircle(Offset(w * 0.53, h * 0.42), w * 0.05, highlightPaint);
        _drawBridgeShadow(canvas, w, h);
        _drawNoseTipGlow(canvas, w, h, Offset(w * 0.5, h * 0.5));
        _drawNoseSpecular(canvas, w, h, Offset(w * 0.52, h * 0.44));

      case 2: // Round
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.28, nosePaint);
        canvas.drawCircle(
            Offset(w * (0.34 - breathFlare), h * 0.58), w * 0.075 * nostrilPulse, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.66 + breathFlare), h * 0.58), w * 0.075 * nostrilPulse, shadowPaint);
        canvas.drawCircle(Offset(w * 0.56, h * 0.34), w * 0.11, highlightPaint);
        _drawBridgeShadow(canvas, w, h);
        _drawNoseTipGlow(canvas, w, h, Offset(w * 0.5, h * 0.5));
        _drawNoseSpecular(canvas, w, h, Offset(w * 0.54, h * 0.38));

      case 3: // Pointed
        final path = Path()
          ..moveTo(w * 0.5, h * 0.15)
          ..quadraticBezierTo(w * 0.68, h * 0.55, w * 0.65, h * 0.80)
          ..quadraticBezierTo(w * 0.5, h * 0.92, w * 0.35, h * 0.80)
          ..quadraticBezierTo(w * 0.32, h * 0.55, w * 0.5, h * 0.15)
          ..close();
        canvas.drawPath(path, nosePaint);
        canvas.drawCircle(
            Offset(w * (0.40 - breathFlare), h * 0.78), w * 0.05 * nostrilPulse, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.60 + breathFlare), h * 0.78), w * 0.05 * nostrilPulse, shadowPaint);
        canvas.drawCircle(Offset(w * 0.52, h * 0.32), w * 0.06, highlightPaint);
        _drawBridgeShadow(canvas, w, h);
        _drawNoseTipGlow(canvas, w, h, Offset(w * 0.5, h * 0.72));
        _drawNoseSpecular(canvas, w, h, Offset(w * 0.52, h * 0.30));

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
            Offset(w * (0.42 - breathFlare), h * 0.68), w * 0.05 * nostrilPulse, shadowPaint);
        canvas.drawCircle(
            Offset(w * (0.58 + breathFlare), h * 0.68), w * 0.05 * nostrilPulse, shadowPaint);
        canvas.drawCircle(Offset(w * 0.52, h * 0.28), w * 0.06, highlightPaint);
        _drawBridgeShadow(canvas, w, h);
        _drawNoseTipGlow(canvas, w, h, Offset(w * 0.5, h * 0.62));
        _drawNoseSpecular(canvas, w, h, Offset(w * 0.52, h * 0.26));
    }
  }

  /// Nose bridge shadow refinement — subtle vertical shadow along bridge
  void _drawBridgeShadow(Canvas canvas, double w, double h) {
    final bridgeRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.30),
      width: w * 0.08,
      height: h * 0.35,
    );
    canvas.drawOval(
      bridgeRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(skinColor, const Color(0xFF5A4A7E), 0.15) ?? skinColor)
                .withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(bridgeRect),
    );
  }

  /// Subsurface scattering glow at nose tip (warm pink radial)
  void _drawNoseTipGlow(Canvas canvas, double w, double h, Offset tipCenter) {
    final glowRect = Rect.fromCenter(
      center: tipCenter,
      width: w * 0.20,
      height: h * 0.16,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = RadialGradient(
          colors: [
            (Color.lerp(skinColor, const Color(0xFFFF8888), 0.30) ?? skinColor)
                .withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ).createShader(glowRect),
    );
  }

  /// Sharp specular highlight at nose tip for 3D feel
  void _drawNoseSpecular(Canvas canvas, double w, double h, Offset center) {
    final specR = w * 0.035;
    canvas.drawCircle(
      center,
      specR,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    // Tiny sharp center
    canvas.drawCircle(
      center,
      specR * 0.4,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
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
  final AvatarExpression expression;

  CheekPainter({
    required this.style,
    required this.skinColor,
    this.expression = AvatarExpression.neutral,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftCheek = Offset(w * 0.18, h * 0.50);
    final rightCheek = Offset(w * 0.82, h * 0.50);

    switch (style) {
      case 1: // Rosy — warm gaussian blush, more visible for kid appeal
        final rosyMul = switch (expression) {
          AvatarExpression.excited => 1.45,
          AvatarExpression.happy => 1.30,
          AvatarExpression.surprised => 1.20,
          _ => 1.0,
        };
        for (final center in [leftCheek, rightCheek]) {
          // Larger blush area for cute child look
          final rect = Rect.fromCenter(
              center: center, width: w * 0.28, height: h * 0.68);
          // Warmer coral-pink tone instead of cool pink
          const blushColor = Color(0xFFFF8090);
          final gradient = RadialGradient(
            colors: [
              blushColor.withValues(alpha: (0.55 * rosyMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.35 * rosyMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.15 * rosyMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.04 * rosyMul).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
            stops: const [0.0, 0.22, 0.48, 0.72, 1.0],
          );
          canvas.drawOval(
            rect,
            Paint()
              ..shader = gradient.createShader(rect)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
          );
          // Dimple when smiling (happy/excited)
          if (expression == AvatarExpression.excited ||
              expression == AvatarExpression.happy) {
            canvas.drawCircle(
              center.translate(0, h * 0.08),
              w * 0.012,
              Paint()
                ..color = (Color.lerp(skinColor, const Color(0xFF6A5A8E), 0.15) ?? skinColor)
                    .withValues(alpha: 0.18)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
            );
          }
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
              Paint()..color = (Color.lerp(skinColor, Colors.brown, darkness) ?? skinColor),
            );
          }
        }

      case 3: // Blush — wide warm gradient with MaskFilter
        final blushMul = switch (expression) {
          AvatarExpression.excited => 1.4,
          AvatarExpression.happy => 1.25,
          AvatarExpression.surprised => 1.15,
          _ => 1.0,
        };
        for (final center in [leftCheek, rightCheek]) {
          final rect = Rect.fromCenter(
              center: center, width: w * 0.32, height: h * 0.78);
          // Warmer rose tone
          const blushColor = Color(0xFFFF7090);
          final gradient = RadialGradient(
            colors: [
              blushColor.withValues(alpha: (0.48 * blushMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.28 * blushMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.10 * blushMul).clamp(0.0, 1.0)),
              blushColor.withValues(alpha: (0.03 * blushMul).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
            stops: const [0.0, 0.25, 0.50, 0.75, 1.0],
          );
          canvas.drawOval(
            rect,
            Paint()
              ..shader = gradient.createShader(rect)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
          );
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
      old.style != style ||
      old.skinColor != skinColor ||
      old.expression != expression;
}

// ═══════════════════════════════════════════════════════════════════════
//  EYELASH PAINTER — curved bezier lash strokes
// ═══════════════════════════════════════════════════════════════════════

class EyelashPainter extends CustomPainter {
  final int style;
  final int eyeStyle;
  final double blinkValue;

  EyelashPainter({
    required this.style,
    required this.eyeStyle,
    this.blinkValue = 0.0,
  });

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

  /// Helper: draw a single curved lash with bezier curvature and tapered thickness.
  /// Uses cubic bezier for more natural curvature than the old quadratic.
  void _drawCurvedLash(Canvas canvas, double cx, double eyeY, double r,
      double angle, double innerMul, double outerMul, Paint paint) {
    // Flutter offset from blink — lashes lift slightly during blink
    final blinkLift = blinkValue * r * 0.08;

    final startX = cx + r * innerMul * cos(angle);
    final startY = eyeY + r * innerMul * sin(angle) - blinkLift * 0.3;
    final endX = cx + r * outerMul * cos(angle - 0.12);
    final endY = eyeY + r * outerMul * sin(angle - 0.12) - blinkLift;

    // Two control points for cubic bezier (more natural curve)
    final mid = (innerMul + outerMul) * 0.5;
    final ctrl1X = cx + r * (innerMul + 0.15) * cos(angle + 0.15);
    final ctrl1Y = eyeY + r * (innerMul + 0.15) * sin(angle + 0.15) - blinkLift * 0.4;
    final ctrl2X = cx + r * mid * cos(angle + 0.06);
    final ctrl2Y = eyeY + r * mid * sin(angle + 0.06) - blinkLift * 0.7;

    final path = Path()
      ..moveTo(startX, startY)
      ..cubicTo(ctrl1X, ctrl1Y, ctrl2X, ctrl2Y, endX, endY);

    // Draw with original paint (base thickness)
    canvas.drawPath(path, paint);

    // Overlay thinner tip stroke for natural taper
    final tipPaint = Paint()
      ..color = paint.color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (paint.strokeWidth) * 0.5
      ..strokeCap = StrokeCap.round;
    final tipPath = Path()
      ..moveTo(ctrl2X, ctrl2Y)
      ..quadraticBezierTo(
        (ctrl2X + endX) * 0.5 + r * 0.02 * cos(angle + pi / 2),
        (ctrl2Y + endY) * 0.5 + r * 0.02 * sin(angle + pi / 2),
        endX, endY,
      );
    canvas.drawPath(tipPath, tipPaint);
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
      old.style != style ||
      old.eyeStyle != eyeStyle ||
      old.blinkValue != blinkValue;
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
    final browColor = (Color.lerp(color, const Color(0xFF1A1A2E), 0.3) ?? color);

    final leftStart = Offset(w * 0.10, h * 0.50);
    final leftEnd = Offset(w * 0.40, h * 0.50);
    final rightStart = Offset(w * 0.60, h * 0.50);
    final rightEnd = Offset(w * 0.90, h * 0.50);

    Paint browPaint(Rect bounds) {
      return Paint()
        ..shader = LinearGradient(
          colors: [
            (Color.lerp(browColor, const Color(0xFF4A3A6E), 0.1) ?? browColor), // cool edge
            browColor, // center
            (Color.lerp(browColor, const Color(0xFF4A3A6E), 0.1) ?? browColor), // cool edge
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
    }

    switch (style) {
      case 0: // Natural — with hair strokes
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, p);
        _drawBrowHairStrokes(canvas, leftStart, leftEnd, -h * 0.25, browColor, 12, w * 0.008);
        _drawBrowHairStrokes(canvas, rightStart, rightEnd, -h * 0.25, browColor, 12, w * 0.008);

      case 1: // Thin — with delicate strokes
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.022;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.20, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.20, p);
        _drawBrowHairStrokes(canvas, leftStart, leftEnd, -h * 0.20, browColor, 8, w * 0.005);
        _drawBrowHairStrokes(canvas, rightStart, rightEnd, -h * 0.20, browColor, 8, w * 0.005);

      case 2: // Thick — with dense strokes
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.055;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.25, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.25, p);
        _drawBrowHairStrokes(canvas, leftStart, leftEnd, -h * 0.25, browColor, 18, w * 0.012);
        _drawBrowHairStrokes(canvas, rightStart, rightEnd, -h * 0.25, browColor, 18, w * 0.012);

      case 3: // Arched — with strokes following high arch
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        _drawBrow(canvas, leftStart, leftEnd, -h * 0.50, p);
        _drawBrow(canvas, rightStart, rightEnd, -h * 0.50, p);
        _drawBrowHairStrokes(canvas, leftStart, leftEnd, -h * 0.50, browColor, 14, w * 0.008);
        _drawBrowHairStrokes(canvas, rightStart, rightEnd, -h * 0.50, browColor, 14, w * 0.008);

      case 4: // Straight — with strokes
        final p = browPaint(Rect.fromLTWH(0, 0, w, h))..strokeWidth = w * 0.035;
        canvas.drawLine(leftStart, leftEnd, p);
        canvas.drawLine(rightStart, rightEnd, p);
        _drawBrowHairStrokes(canvas, leftStart, leftEnd, -h * 0.02, browColor, 10, w * 0.007);
        _drawBrowHairStrokes(canvas, rightStart, rightEnd, -h * 0.02, browColor, 10, w * 0.007);

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

  /// Draw individual hair strokes along the brow path for natural look.
  /// [strandCount] determines density, [baseThickness] the inner-end width.
  void _drawBrowHairStrokes(Canvas canvas, Offset start, Offset end,
      double archHeight, Color browColor, int strandCount, double baseThickness) {
    final rng = Random(42 + style * 7);
    final mid = Offset((start.dx + end.dx) / 2, start.dy + archHeight);
    final browLen = (end - start).distance;

    for (int i = 0; i < strandCount; i++) {
      final t = i / (strandCount - 1); // 0..1 along brow

      // Position on brow curve (quadratic bezier interpolation)
      final bx = (1 - t) * (1 - t) * start.dx +
          2 * (1 - t) * t * mid.dx +
          t * t * end.dx;
      final by = (1 - t) * (1 - t) * start.dy +
          2 * (1 - t) * t * mid.dy +
          t * t * end.dy;

      // Tangent for stroke direction
      final tx = 2 * (1 - t) * (mid.dx - start.dx) + 2 * t * (end.dx - mid.dx);
      final ty = 2 * (1 - t) * (mid.dy - start.dy) + 2 * t * (end.dy - mid.dy);
      final tLen = sqrt(tx * tx + ty * ty);
      if (tLen < 0.001) continue;
      // Normal direction (perpendicular to tangent, pointing upward)
      final nx = -ty / tLen;
      final ny = tx / tLen;

      // Strand extends from brow center outward (upward) with slight randomness
      final strandLen = browLen * (0.06 + rng.nextDouble() * 0.04);
      final strandAngle = rng.nextDouble() * 0.3 - 0.15; // slight randomness
      final strandEndX = bx + (nx * cos(strandAngle) - ny * sin(strandAngle)) * strandLen;
      final strandEndY = by + (nx * sin(strandAngle) + ny * cos(strandAngle)) * strandLen;

      // Thickness: thicker at inner end (t=0), thinner at outer (t=1)
      final thickness = baseThickness * (1.0 - t * 0.5);
      final alpha = 0.2 + rng.nextDouble() * 0.15;

      canvas.drawLine(
        Offset(bx, by),
        Offset(strandEndX, strandEndY),
        Paint()
          ..color = browColor.withValues(alpha: alpha)
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(EyebrowPainter old) =>
      old.style != style || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════
//  FRECKLES PAINTER
//  - Scattered small dots across cheeks and nose bridge
//  - Slightly darker skin tone with natural variation
//  - Deterministic randomized positions (seeded)
// ═══════════════════════════════════════════════════════════════════════

class FrecklesPainter extends CustomPainter {
  final Color skinColor;
  final int seed;

  const FrecklesPainter({
    required this.skinColor,
    this.seed = 42,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rng = Random(seed);

    // Left cheek cluster
    _drawFreckleCluster(canvas, rng, Offset(w * 0.20, h * 0.55), w * 0.18, h * 0.35, 9, w);
    // Right cheek cluster
    _drawFreckleCluster(canvas, rng, Offset(w * 0.80, h * 0.55), w * 0.18, h * 0.35, 9, w);
    // Nose bridge scatter (sparser, smaller)
    _drawFreckleCluster(canvas, rng, Offset(w * 0.50, h * 0.35), w * 0.10, h * 0.25, 5, w * 0.7);
  }

  void _drawFreckleCluster(Canvas canvas, Random rng, Offset center,
      double spreadW, double spreadH, int count, double sizeRef) {
    for (int i = 0; i < count; i++) {
      final dx = (rng.nextDouble() - 0.5) * spreadW;
      final dy = (rng.nextDouble() - 0.5) * spreadH;
      final radius = sizeRef * 0.006 + rng.nextDouble() * sizeRef * 0.010;
      final darkness = 0.20 + rng.nextDouble() * 0.18;
      final alpha = 0.35 + rng.nextDouble() * 0.25;

      canvas.drawCircle(
        center.translate(dx, dy),
        radius,
        Paint()
          ..color = (Color.lerp(skinColor, Colors.brown, darkness) ?? skinColor)
              .withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(FrecklesPainter old) =>
      old.skinColor != skinColor || old.seed != seed;
}

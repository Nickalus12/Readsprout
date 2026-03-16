import 'dart:math';

import 'package:flutter/animation.dart';

// ══════════════════════════════════════════════════════════════════════
//  BONE TRANSFORM — position, rotation, scale for a single bone
// ══════════════════════════════════════════════════════════════════════

class BoneTransform {
  final double dx;
  final double dy;
  final double rotation;
  final double scaleX;
  final double scaleY;

  const BoneTransform({
    this.dx = 0.0,
    this.dy = 0.0,
    this.rotation = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
  });

  static const identity = BoneTransform();

  static BoneTransform lerp(BoneTransform a, BoneTransform b, double t) {
    return BoneTransform(
      dx: a.dx + (b.dx - a.dx) * t,
      dy: a.dy + (b.dy - a.dy) * t,
      rotation: a.rotation + (b.rotation - a.rotation) * t,
      scaleX: a.scaleX + (b.scaleX - a.scaleX) * t,
      scaleY: a.scaleY + (b.scaleY - a.scaleY) * t,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  BONE POSE — snapshot of all bone offsets for one frame
// ══════════════════════════════════════════════════════════════════════

class BonePose {
  final Map<String, BoneTransform> transforms;

  const BonePose(this.transforms);

  static const empty = BonePose({});

  BoneTransform operator [](String bone) =>
      transforms[bone] ?? BoneTransform.identity;

  /// Lerp between two poses. Bones present in only one pose blend from/to identity.
  static BonePose lerp(BonePose a, BonePose b, double t) {
    final allBones = <String>{...a.transforms.keys, ...b.transforms.keys};
    final result = <String, BoneTransform>{};
    for (final bone in allBones) {
      result[bone] = BoneTransform.lerp(
        a.transforms[bone] ?? BoneTransform.identity,
        b.transforms[bone] ?? BoneTransform.identity,
        t,
      );
    }
    return BonePose(result);
  }

  /// Additively combine two poses (add offsets, multiply scales).
  static BonePose additive(BonePose base, BonePose overlay) {
    final allBones = <String>{...base.transforms.keys, ...overlay.transforms.keys};
    final result = <String, BoneTransform>{};
    for (final bone in allBones) {
      final a = base.transforms[bone] ?? BoneTransform.identity;
      final b = overlay.transforms[bone] ?? BoneTransform.identity;
      result[bone] = BoneTransform(
        dx: a.dx + b.dx,
        dy: a.dy + b.dy,
        rotation: a.rotation + b.rotation,
        scaleX: a.scaleX * b.scaleX,
        scaleY: a.scaleY * b.scaleY,
      );
    }
    return BonePose(result);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  BONE KEYFRAME — single keyframe in an animation track
// ══════════════════════════════════════════════════════════════════════

class BoneKeyframe {
  final double time;
  final double dx;
  final double dy;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final Curve curve;

  const BoneKeyframe({
    required this.time,
    this.dx = 0.0,
    this.dy = 0.0,
    this.rotation = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.curve = Curves.easeInOut,
  });

  BoneTransform toTransform() => BoneTransform(
        dx: dx,
        dy: dy,
        rotation: rotation,
        scaleX: scaleX,
        scaleY: scaleY,
      );
}

// ══════════════════════════════════════════════════════════════════════
//  ANIMATION CLIP — authored keyframe animation
// ══════════════════════════════════════════════════════════════════════

class AnimationClip {
  final String name;
  final double duration;
  final Map<String, List<BoneKeyframe>> tracks;
  final bool loop;

  const AnimationClip({
    required this.name,
    required this.duration,
    required this.tracks,
    this.loop = false,
  });

  /// Sample the clip at [time], returning an interpolated BonePose.
  BonePose sample(double time) {
    if (loop && duration > 0) {
      time = time % duration;
    } else {
      time = time.clamp(0.0, duration);
    }

    final result = <String, BoneTransform>{};
    for (final entry in tracks.entries) {
      final bone = entry.key;
      final keyframes = entry.value;
      if (keyframes.isEmpty) continue;

      // Before first keyframe
      if (time <= keyframes.first.time) {
        result[bone] = keyframes.first.toTransform();
        continue;
      }
      // After last keyframe
      if (time >= keyframes.last.time) {
        result[bone] = keyframes.last.toTransform();
        continue;
      }

      // Find surrounding keyframes and interpolate
      for (int i = 0; i < keyframes.length - 1; i++) {
        final a = keyframes[i];
        final b = keyframes[i + 1];
        if (time >= a.time && time <= b.time) {
          final span = b.time - a.time;
          final raw = span > 0 ? (time - a.time) / span : 0.0;
          final t = b.curve.transform(raw);
          result[bone] = BoneTransform.lerp(a.toTransform(), b.toTransform(), t);
          break;
        }
      }
    }
    return BonePose(result);
  }

  /// Whether the clip has finished playing at [time] (non-looping only).
  bool isComplete(double time) => !loop && time >= duration;
}

// ══════════════════════════════════════════════════════════════════════
//  PROCEDURAL IDLE SYSTEM — organic micro-movements every frame
// ══════════════════════════════════════════════════════════════════════

class ProceduralIdleSystem {
  /// 0.0 = sleepy/calm, 1.0 = hyper/energetic. Affects amplitude of movements.
  double energyLevel;

  final Random _rng = Random();
  double _fidgetCooldown = 0.0;

  ProceduralIdleSystem({this.energyLevel = 0.5});

  /// Compute idle bone offsets for this frame.
  /// [dt] is delta time in seconds, [time] is total elapsed seconds.
  BonePose computeIdle(double dt, double time) {
    // Decrement fidget cooldown
    if (_fidgetCooldown > 0) _fidgetCooldown -= dt;

    final e = energyLevel;
    final transforms = <String, BoneTransform>{};

    // ── Root: slow weight-shift sway — visible but gentle ──
    transforms['root'] = BoneTransform(
      dx: sin(time * 0.4) * 0.014 * e,
      rotation: sin(time * 0.3 + 0.7) * 0.012 * e,
    );

    // ── Spine/Chest: breathing oscillation — clearly visible chest rise ──
    final breathPhase = sin(time * 1.05); // ~3s cycle
    transforms['chest'] = BoneTransform(
      scaleY: 1.0 + breathPhase * 0.022,
      dy: breathPhase * -0.005, // chest rises on inhale
    );

    // ── Head: layered sin waves for organic micro-movement ──
    // Slightly larger amplitude so the character feels alive, not frozen
    final headX = (sin(time * 0.7) * 0.30 +
            sin(time * 1.3) * 0.15 +
            sin(time * 2.1) * 0.05) *
        0.008 *
        e;
    final headY = (sin(time * 0.5 + 1.0) * 0.20 +
            sin(time * 1.1 + 0.5) * 0.10) *
        0.005 *
        e;
    final headRot = sin(time * 0.3) * 0.025 * e;
    transforms['head'] = BoneTransform(
      dx: headX,
      dy: headY,
      rotation: headRot,
    );

    // ── Shoulders: asymmetric micro-shifts ──
    transforms['leftShoulder'] = BoneTransform(
      dy: sin(time * 0.6 + 0.3) * 0.005 * e,
    );
    transforms['rightShoulder'] = BoneTransform(
      dy: sin(time * 0.6 + 1.8) * 0.005 * e,
    );

    // ── Arms: gentle pendulum sway at rest ──
    transforms['leftUpperArm'] = BoneTransform(
      rotation: sin(time * 0.35 + 0.5) * 0.022 * e,
    );
    transforms['rightUpperArm'] = BoneTransform(
      rotation: sin(time * 0.35 + 2.0) * 0.022 * e,
    );

    // ── Hands: very gentle follow-through lag from arm sway ──
    transforms['leftHand'] = BoneTransform(
      rotation: sin(time * 0.35 + 0.8) * 0.015 * e,
    );
    transforms['rightHand'] = BoneTransform(
      rotation: sin(time * 0.35 + 2.3) * 0.015 * e,
    );

    // ── Eyes: micro look-around (driven by head but slightly offset) ──
    final eyeTransform = BoneTransform(
      dx: sin(time * 0.8 + 0.2) * 0.005 * e,
      dy: sin(time * 0.6 + 1.5) * 0.003 * e,
    );
    transforms['leftEye'] = eyeTransform;
    transforms['rightEye'] = eyeTransform;

    // ── Hair: gentle secondary motion from head sway ──
    transforms['hairRoot'] = BoneTransform(
      rotation: sin(time * 0.4 + 0.5) * 0.018 * e,
      dx: sin(time * 0.35) * 0.004 * e,
    );

    // ── Fidgets: at high energy, occasional small gestures ──
    if (e > 0.6 && _fidgetCooldown <= 0 && _rng.nextDouble() < 0.002 * e) {
      _fidgetCooldown = 2.0 + _rng.nextDouble() * 3.0; // 2-5s cooldown
      // Small shoulder shrug fidget
      transforms['leftShoulder'] = BoneTransform(
        dy: -0.010 * e,
      );
      transforms['rightShoulder'] = BoneTransform(
        dy: -0.010 * e,
      );
    }

    return BonePose(transforms);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  ANIMATION MIXER — blends procedural idle + authored clips
// ══════════════════════════════════════════════════════════════════════

class AnimationMixer {
  final ProceduralIdleSystem _idle;

  AnimationClip? _activeClip;
  double _clipTime = 0.0;
  double _blendWeight = 0.0;
  double _blendTarget = 0.0;
  double _blendSpeed = 0.0; // weight change per second

  /// Queue of clips to play after the current one finishes.
  final List<_QueuedClip> _queue = [];

  AnimationMixer(this._idle);

  /// The currently active idle system, for external energy level adjustments.
  ProceduralIdleSystem get idle => _idle;

  /// Whether an authored clip is currently playing.
  bool get isPlaying => _activeClip != null;

  /// Name of the currently playing clip, or null.
  String? get activeClipName => _activeClip?.name;

  /// Start playing an animation clip, blending in over [transition].
  void play(AnimationClip clip,
      {Duration transition = const Duration(milliseconds: 300)}) {
    _activeClip = clip;
    _clipTime = 0.0;
    _blendTarget = 1.0;
    _blendSpeed = transition.inMilliseconds > 0
        ? 1000.0 / transition.inMilliseconds
        : 100.0;
  }

  /// Queue a clip to play after the current one finishes.
  void queue(AnimationClip clip,
      {Duration transition = const Duration(milliseconds: 300)}) {
    if (_activeClip == null) {
      play(clip, transition: transition);
    } else {
      _queue.add(_QueuedClip(clip, transition));
    }
  }

  /// Stop current clip, blend back to idle over [transition].
  void stop({Duration transition = const Duration(milliseconds: 300)}) {
    _blendTarget = 0.0;
    _blendSpeed = transition.inMilliseconds > 0
        ? 1000.0 / transition.inMilliseconds
        : 100.0;
    _queue.clear();
  }

  /// Call every frame. Returns the final blended BonePose.
  /// [dt] is delta time in seconds, [time] is total elapsed seconds.
  BonePose update(double dt, double time) {
    final idlePose = _idle.computeIdle(dt, time);

    // Update blend weight toward target
    if (_blendWeight != _blendTarget) {
      final step = _blendSpeed * dt;
      if (_blendWeight < _blendTarget) {
        _blendWeight = (_blendWeight + step).clamp(0.0, _blendTarget);
      } else {
        _blendWeight = (_blendWeight - step).clamp(_blendTarget, 1.0);
      }
    }

    // If fully blended out and no clip, return pure idle
    if (_activeClip == null || _blendWeight < 0.001) {
      if (_blendWeight < 0.001 && _activeClip != null) {
        _activeClip = null;
        _blendWeight = 0.0;
      }
      return idlePose;
    }

    // Advance clip time
    _clipTime += dt;

    // Check if clip finished (non-looping)
    if (_activeClip!.isComplete(_clipTime)) {
      if (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        play(next.clip, transition: next.transition);
      } else {
        stop();
      }
    }

    final clipPose = _activeClip!.sample(_clipTime);

    // Blend: lerp between idle and clip
    return BonePose.lerp(idlePose, clipPose, _blendWeight);
  }
}

class _QueuedClip {
  final AnimationClip clip;
  final Duration transition;
  const _QueuedClip(this.clip, this.transition);
}

// ══════════════════════════════════════════════════════════════════════
//  TOUCH HANDLER — converts touch events to bone forces
// ══════════════════════════════════════════════════════════════════════

class AvatarTouchHandler {
  /// Bone anchor positions in normalized space (0-1).
  /// These represent approximate positions of each bone on the avatar.
  static const Map<String, _BoneAnchor> _anchors = {
    'head': _BoneAnchor(0.50, 0.15),
    'chest': _BoneAnchor(0.50, 0.40),
    'root': _BoneAnchor(0.50, 0.55),
    'leftShoulder': _BoneAnchor(0.30, 0.32),
    'rightShoulder': _BoneAnchor(0.70, 0.32),
    'leftUpperArm': _BoneAnchor(0.22, 0.40),
    'rightUpperArm': _BoneAnchor(0.78, 0.40),
    'leftForearm': _BoneAnchor(0.18, 0.52),
    'rightForearm': _BoneAnchor(0.82, 0.52),
    'leftHand': _BoneAnchor(0.15, 0.62),
    'rightHand': _BoneAnchor(0.85, 0.62),
  };

  /// Active touch force per bone. Decays over time when not touched.
  final Map<String, BoneTransform> _touchForces = {};

  /// Influence radius in normalized units. Bones within this radius
  /// of the touch point receive force.
  static const double influenceRadius = 0.15;

  /// Force multiplier for translating touch delta into bone offset.
  static const double forceScale = 0.02;

  /// Decay rate per second (forces spring back when not touched).
  static const double decayRate = 5.0;

  /// Called on touch down or move. Applies force to nearby bones.
  void onTouch(Offset localPosition, Offset delta, double widgetSize) {
    if (widgetSize <= 0) return;

    // Normalize to 0-1 space
    final nx = localPosition.dx / widgetSize;
    final ny = localPosition.dy / widgetSize;
    final ndx = delta.dx / widgetSize * forceScale;
    final ndy = delta.dy / widgetSize * forceScale;

    for (final entry in _anchors.entries) {
      final bone = entry.key;
      final anchor = entry.value;
      final dist = _distance(nx, ny, anchor.x, anchor.y);

      if (dist < influenceRadius) {
        // Falloff: full force at center, zero at edge
        final falloff = 1.0 - (dist / influenceRadius);
        final weight = falloff * falloff; // quadratic falloff

        _touchForces[bone] = BoneTransform(
          dx: ndx * weight,
          dy: ndy * weight,
          rotation: ndx * weight * 2.0, // slight rotation from horizontal push
        );
      }
    }
  }

  /// Called on touch up. Forces will decay naturally via [update].
  void onTouchEnd() {
    // Forces remain and decay in update()
  }

  /// Call every frame to decay forces. Returns additive BonePose from touch.
  BonePose update(double dt) {
    final result = <String, BoneTransform>{};
    final toRemove = <String>[];

    for (final entry in _touchForces.entries) {
      final f = entry.value;
      final decay = 1.0 - (decayRate * dt).clamp(0.0, 1.0);
      final newForce = BoneTransform(
        dx: f.dx * decay,
        dy: f.dy * decay,
        rotation: f.rotation * decay,
      );

      // Remove if negligible
      if (newForce.dx.abs() < 0.0001 &&
          newForce.dy.abs() < 0.0001 &&
          newForce.rotation.abs() < 0.0001) {
        toRemove.add(entry.key);
      } else {
        _touchForces[entry.key] = newForce;
        result[entry.key] = newForce;
      }
    }
    for (final key in toRemove) {
      _touchForces.remove(key);
    }

    return BonePose(result);
  }

  static double _distance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return sqrt(dx * dx + dy * dy);
  }
}

class _BoneAnchor {
  final double x;
  final double y;
  const _BoneAnchor(this.x, this.y);
}

// ══════════════════════════════════════════════════════════════════════
//  AUTHORED ANIMATION CLIPS — predefined character animations
// ══════════════════════════════════════════════════════════════════════

class AvatarAnimations {
  AvatarAnimations._();

  // ── Wave: friendly greeting ──────────────────────────────────────
  static const wave = AnimationClip(
    name: 'wave',
    duration: 1.2,
    tracks: {
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.25, rotation: -1.2, curve: Curves.easeOut),
        BoneKeyframe(time: 1.2, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.25, rotation: -0.3, curve: Curves.easeOut),
        BoneKeyframe(time: 0.45, rotation: 0.4, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: -0.35, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: 0.35, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.2, rotation: 0.0, curve: Curves.easeIn),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.25, rotation: 0.0),
        BoneKeyframe(time: 0.45, rotation: 0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: -0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: 0.25, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.2, rotation: 0.0, curve: Curves.easeIn),
      ],
    },
  );

  // ── Clap: both hands come together ────────────────────────────────
  static const clap = AnimationClip(
    name: 'clap',
    duration: 0.8,
    tracks: {
      'leftUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.15, rotation: 0.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.25, rotation: 0.1, curve: Curves.easeIn),
        BoneKeyframe(time: 0.40, rotation: 0.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.50, rotation: 0.1, curve: Curves.easeIn),
        BoneKeyframe(time: 0.65, rotation: 0.5, curve: Curves.easeOut),
        BoneKeyframe(time: 0.80, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.15, rotation: -0.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.25, rotation: -0.1, curve: Curves.easeIn),
        BoneKeyframe(time: 0.40, rotation: -0.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.50, rotation: -0.1, curve: Curves.easeIn),
        BoneKeyframe(time: 0.65, rotation: -0.5, curve: Curves.easeOut),
        BoneKeyframe(time: 0.80, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.15, rotation: -0.4, curve: Curves.easeOut),
        BoneKeyframe(time: 0.80, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.15, rotation: 0.4, curve: Curves.easeOut),
        BoneKeyframe(time: 0.80, rotation: 0.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Thumbs up: right arm lifts, thumb gesture ─────────────────────
  static const thumbsUp = AnimationClip(
    name: 'thumbsUp',
    duration: 1.0,
    tracks: {
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.3, rotation: -0.9, curve: Curves.easeOut),
        BoneKeyframe(time: 0.7, rotation: -0.9),
        BoneKeyframe(time: 1.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.3, rotation: -0.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.7, rotation: -0.6),
        BoneKeyframe(time: 1.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.0, rotation: 0.0, scaleX: 1.0),
        BoneKeyframe(time: 0.3, rotation: 0.2, scaleX: 1.15, curve: Curves.elasticOut),
        BoneKeyframe(time: 0.7, rotation: 0.2, scaleX: 1.15),
        BoneKeyframe(time: 1.0, rotation: 0.0, scaleX: 1.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Celebrate: big arms up, bouncy — kids love exaggerated joy ────
  static const celebrate = AnimationClip(
    name: 'celebrate',
    duration: 1.8,
    tracks: {
      'leftUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.25, rotation: 1.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.45, rotation: 1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: 1.7, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: 1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.05, rotation: 1.6, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.25, rotation: 1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.25, rotation: -1.6, curve: Curves.easeOut),
        BoneKeyframe(time: 0.45, rotation: -1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: -1.7, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: -1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.05, rotation: -1.6, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.25, rotation: -1.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftHand': [
        BoneKeyframe(time: 0.25, rotation: 0.0),
        BoneKeyframe(time: 0.45, rotation: 0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: -0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: 0.25, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.05, rotation: -0.25, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.8, rotation: 0.0, curve: Curves.easeIn),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.25, rotation: 0.0),
        BoneKeyframe(time: 0.45, rotation: -0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.65, rotation: 0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.85, rotation: -0.25, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.05, rotation: 0.25, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.8, rotation: 0.0, curve: Curves.easeIn),
      ],
      'root': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.25, dy: -0.025, curve: Curves.easeOut),
        BoneKeyframe(time: 0.45, dy: 0.005, curve: Curves.bounceOut),
        BoneKeyframe(time: 0.65, dy: -0.018, curve: Curves.easeOut),
        BoneKeyframe(time: 0.85, dy: 0.003, curve: Curves.bounceOut),
        BoneKeyframe(time: 1.05, dy: -0.012, curve: Curves.easeOut),
        BoneKeyframe(time: 1.8, dy: 0.0, curve: Curves.easeInOut),
      ],
      'head': [
        BoneKeyframe(time: 0.0, dy: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.25, dy: -0.015, rotation: -0.04, curve: Curves.easeOut),
        BoneKeyframe(time: 0.65, dy: -0.01, rotation: 0.04, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.05, dy: -0.008, rotation: -0.03, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.8, dy: 0.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Nod: head bobs down and up ───────────────────────────────────
  static const nod = AnimationClip(
    name: 'nod',
    duration: 0.6,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.15, rotation: 0.15, curve: Curves.easeOut),
        BoneKeyframe(time: 0.30, rotation: -0.03, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.42, rotation: 0.08, curve: Curves.easeOut),
        BoneKeyframe(time: 0.60, rotation: 0.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Head shake: side to side "no" ────────────────────────────────
  static const headShake = AnimationClip(
    name: 'headShake',
    duration: 0.8,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.12, rotation: -0.15, curve: Curves.easeOut),
        BoneKeyframe(time: 0.30, rotation: 0.15, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.48, rotation: -0.12, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.64, rotation: 0.06, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.80, rotation: 0.0, curve: Curves.easeIn),
      ],
    },
  );

  // ── Think: visible head tilt, hand on chin, furrowed brow feel ───
  static const think = AnimationClip(
    name: 'think',
    duration: 1.5,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0, dx: 0.0),
        BoneKeyframe(time: 0.35, rotation: 0.14, dx: 0.008, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, rotation: 0.14, dx: 0.008),
        BoneKeyframe(time: 1.5, rotation: 0.0, dx: 0.0, curve: Curves.easeInOut),
      ],
      'leftBrow': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.35, dy: 0.006, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, dy: 0.006),
        BoneKeyframe(time: 1.5, dy: 0.0, curve: Curves.easeInOut),
      ],
      'rightBrow': [
        BoneKeyframe(time: 0.0, dy: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.35, dy: -0.004, rotation: -0.06, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, dy: -0.004, rotation: -0.06),
        BoneKeyframe(time: 1.5, dy: 0.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.35, rotation: -0.9, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, rotation: -0.9),
        BoneKeyframe(time: 1.5, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.35, rotation: -1.1, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, rotation: -1.1),
        BoneKeyframe(time: 1.5, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.35, rotation: 0.15, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, rotation: 0.15),
        BoneKeyframe(time: 1.5, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftEye': [
        BoneKeyframe(time: 0.0, scaleY: 1.0),
        BoneKeyframe(time: 0.35, scaleY: 0.85, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, scaleY: 0.85),
        BoneKeyframe(time: 1.5, scaleY: 1.0, curve: Curves.easeInOut),
      ],
      'rightEye': [
        BoneKeyframe(time: 0.0, scaleY: 1.0),
        BoneKeyframe(time: 0.35, scaleY: 0.85, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, scaleY: 0.85),
        BoneKeyframe(time: 1.5, scaleY: 1.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Surprise: big jump back, arms wide, eyes pop ─────────────────
  static const surprise = AnimationClip(
    name: 'surprise',
    duration: 1.0,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, dy: 0.0, scaleX: 1.0, scaleY: 1.0),
        BoneKeyframe(
            time: 0.12,
            dy: -0.022,
            scaleX: 1.06,
            scaleY: 1.06,
            curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, dy: -0.012, scaleX: 1.03, scaleY: 1.03),
        BoneKeyframe(
            time: 1.0,
            dy: 0.0,
            scaleX: 1.0,
            scaleY: 1.0,
            curve: Curves.easeInOut),
      ],
      'leftUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.12, rotation: 0.8, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: 0.65),
        BoneKeyframe(time: 1.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.12, rotation: -0.8, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: -0.65),
        BoneKeyframe(time: 1.0, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftHand': [
        BoneKeyframe(time: 0.0, scaleX: 1.0, scaleY: 1.0),
        BoneKeyframe(time: 0.12, scaleX: 1.2, scaleY: 1.2, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, scaleX: 1.0, scaleY: 1.0, curve: Curves.easeInOut),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.0, scaleX: 1.0, scaleY: 1.0),
        BoneKeyframe(time: 0.12, scaleX: 1.2, scaleY: 1.2, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, scaleX: 1.0, scaleY: 1.0, curve: Curves.easeInOut),
      ],
      'root': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.12, dy: -0.015, curve: Curves.easeOut),
        BoneKeyframe(time: 0.35, dy: 0.003, curve: Curves.bounceOut),
        BoneKeyframe(time: 1.0, dy: 0.0, curve: Curves.easeInOut),
      ],
      'chest': [
        BoneKeyframe(time: 0.0, scaleY: 1.0),
        BoneKeyframe(time: 0.12, scaleY: 1.05, curve: Curves.easeOut),
        BoneKeyframe(time: 1.0, scaleY: 1.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Giggle: bouncy head + slight shoulder shakes ─────────────────
  static const giggle = AnimationClip(
    name: 'giggle',
    duration: 1.0,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.10, rotation: -0.04, dy: -0.003, curve: Curves.easeOut),
        BoneKeyframe(time: 0.22, rotation: 0.04, dy: 0.002, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.34, rotation: -0.03, dy: -0.003, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.46, rotation: 0.03, dy: 0.002, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.58, rotation: -0.02, dy: -0.002, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.70, rotation: 0.02, dy: 0.001, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.0, rotation: 0.0, dy: 0.0, curve: Curves.easeIn),
      ],
      'leftShoulder': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.15, dy: -0.008, curve: Curves.easeOut),
        BoneKeyframe(time: 0.30, dy: 0.0, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.45, dy: -0.006, curve: Curves.easeOut),
        BoneKeyframe(time: 0.60, dy: 0.0, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.0, dy: 0.0),
      ],
      'rightShoulder': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.15, dy: -0.008, curve: Curves.easeOut),
        BoneKeyframe(time: 0.30, dy: 0.0, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.45, dy: -0.006, curve: Curves.easeOut),
        BoneKeyframe(time: 0.60, dy: 0.0, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.0, dy: 0.0),
      ],
      'chest': [
        BoneKeyframe(time: 0.0, scaleY: 1.0),
        BoneKeyframe(time: 0.12, scaleY: 1.02, curve: Curves.easeOut),
        BoneKeyframe(time: 0.24, scaleY: 0.98, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.36, scaleY: 1.015, curve: Curves.easeInOut),
        BoneKeyframe(time: 0.48, scaleY: 0.99, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.0, scaleY: 1.0, curve: Curves.easeIn),
      ],
    },
  );

  // ── Shrug: both shoulders up, palms out ──────────────────────────
  static const shrug = AnimationClip(
    name: 'shrug',
    duration: 0.8,
    tracks: {
      'leftShoulder': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.2, dy: -0.02, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, dy: -0.02),
        BoneKeyframe(time: 0.8, dy: 0.0, curve: Curves.easeInOut),
      ],
      'rightShoulder': [
        BoneKeyframe(time: 0.0, dy: 0.0),
        BoneKeyframe(time: 0.2, dy: -0.02, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, dy: -0.02),
        BoneKeyframe(time: 0.8, dy: 0.0, curve: Curves.easeInOut),
      ],
      'leftUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: 0.4, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: 0.4),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.4, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: -0.4),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.5, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: -0.5),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: 0.5, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: 0.5),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'leftHand': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.3, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: -0.3),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: 0.3, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: 0.3),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: 0.05, curve: Curves.easeOut),
        BoneKeyframe(time: 0.5, rotation: 0.05),
        BoneKeyframe(time: 0.8, rotation: 0.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Point at: right arm extends forward/right ────────────────────
  static const pointAt = AnimationClip(
    name: 'pointAt',
    duration: 0.6,
    tracks: {
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.7, curve: Curves.easeOut),
        BoneKeyframe(time: 0.4, rotation: -0.7),
        BoneKeyframe(time: 0.6, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightForearm': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.2, curve: Curves.easeOut),
        BoneKeyframe(time: 0.4, rotation: -0.2),
        BoneKeyframe(time: 0.6, rotation: 0.0, curve: Curves.easeInOut),
      ],
      'rightHand': [
        BoneKeyframe(time: 0.0, rotation: 0.0, scaleX: 1.0),
        BoneKeyframe(time: 0.2, rotation: 0.15, scaleX: 1.1, curve: Curves.easeOut),
        BoneKeyframe(time: 0.4, rotation: 0.15, scaleX: 1.1),
        BoneKeyframe(time: 0.6, rotation: 0.0, scaleX: 1.0, curve: Curves.easeInOut),
      ],
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.0),
        BoneKeyframe(time: 0.2, rotation: -0.05, curve: Curves.easeOut),
        BoneKeyframe(time: 0.4, rotation: -0.05),
        BoneKeyframe(time: 0.6, rotation: 0.0, curve: Curves.easeInOut),
      ],
    },
  );

  // ── Sleepy: slow drooping head, heavy eyelids ────────────────────
  static const sleepy = AnimationClip(
    name: 'sleepy',
    duration: 2.0,
    loop: true,
    tracks: {
      'head': [
        BoneKeyframe(time: 0.0, rotation: 0.06, dy: 0.005),
        BoneKeyframe(time: 0.8, rotation: 0.10, dy: 0.008, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.2, rotation: 0.04, dy: 0.003, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, rotation: 0.06, dy: 0.005, curve: Curves.easeInOut),
      ],
      'chest': [
        BoneKeyframe(time: 0.0, scaleY: 1.0),
        BoneKeyframe(time: 1.0, scaleY: 1.02, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, scaleY: 1.0, curve: Curves.easeInOut),
      ],
      'leftUpperArm': [
        BoneKeyframe(time: 0.0, rotation: 0.05),
        BoneKeyframe(time: 1.0, rotation: 0.08, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, rotation: 0.05, curve: Curves.easeInOut),
      ],
      'rightUpperArm': [
        BoneKeyframe(time: 0.0, rotation: -0.05),
        BoneKeyframe(time: 1.0, rotation: -0.08, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, rotation: -0.05, curve: Curves.easeInOut),
      ],
      'leftEye': [
        BoneKeyframe(time: 0.0, scaleY: 0.5),
        BoneKeyframe(time: 0.8, scaleY: 0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.2, scaleY: 0.6, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, scaleY: 0.5, curve: Curves.easeInOut),
      ],
      'rightEye': [
        BoneKeyframe(time: 0.0, scaleY: 0.5),
        BoneKeyframe(time: 0.8, scaleY: 0.3, curve: Curves.easeInOut),
        BoneKeyframe(time: 1.2, scaleY: 0.6, curve: Curves.easeInOut),
        BoneKeyframe(time: 2.0, scaleY: 0.5, curve: Curves.easeInOut),
      ],
    },
  );

  /// All available clips for lookup by name.
  static final Map<String, AnimationClip> all = {
    'wave': wave,
    'clap': clap,
    'thumbsUp': thumbsUp,
    'celebrate': celebrate,
    'nod': nod,
    'headShake': headShake,
    'think': think,
    'surprise': surprise,
    'giggle': giggle,
    'shrug': shrug,
    'pointAt': pointAt,
    'sleepy': sleepy,
  };
}

import 'dart:math';
import 'package:flutter/material.dart';

import 'animation_system.dart' show BonePose, BoneTransform;

// ═══════════════════════════════════════════════════════════════════════
//  BONE SPRING — Damped harmonic oscillator for touch interaction
// ═══════════════════════════════════════════════════════════════════════

/// Spring physics for a single bone. Produces displacement that decays
/// naturally after an external force is applied (e.g. a poke/drag).
class BoneSpring {
  double stiffness;
  double damping;
  double mass;
  Offset displacement = Offset.zero;
  Offset velocity = Offset.zero;

  BoneSpring({
    this.stiffness = 150,
    this.damping = 12,
    this.mass = 1.0,
  });

  /// Apply an instantaneous force impulse (from touch/drag).
  void applyForce(Offset force) {
    velocity += force / mass;
  }

  /// Advance the spring simulation by [dt] seconds.
  ///
  /// Uses semi-implicit Euler: update velocity first, then position.
  /// This is unconditionally stable for the stiffness/damping ranges we use.
  void update(double dt) {
    // Clamp dt to avoid instability on frame spikes
    final clamped = dt.clamp(0.0, 0.033); // cap at ~30fps worth

    // F = -kx - cv  (spring + damping)
    final springForce = -displacement * stiffness;
    final dampingForce = -velocity * damping;
    final acceleration = (springForce + dampingForce) / mass;

    // Semi-implicit Euler
    velocity += acceleration * clamped;
    displacement += velocity * clamped;

    // Rest threshold — stop jiggling when nearly still
    if (displacement.distance < 0.01 && velocity.distance < 0.01) {
      displacement = Offset.zero;
      velocity = Offset.zero;
    }
  }

  /// Whether the spring is at rest (no motion).
  bool get isAtRest =>
      displacement == Offset.zero && velocity == Offset.zero;

  /// Reset to rest state immediately.
  void reset() {
    displacement = Offset.zero;
    velocity = Offset.zero;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BONE — Single node in the skeleton hierarchy
// ═══════════════════════════════════════════════════════════════════════

/// A bone in the avatar skeleton tree. Each bone has a local transform
/// relative to its parent, spring physics for touch reactions, and a
/// cached world transform computed via forward kinematics.
class Bone {
  final String name;
  Bone? parent;
  final List<Bone> children = [];

  // Local transform (relative to parent, in normalized 0-1 coordinates)
  Offset localPosition;
  double localRotation; // radians
  double localScale;

  // Spring physics for touch interaction
  final BoneSpring spring;

  // Influence radius for touch force falloff (normalized units)
  final double influenceRadius;

  // Additive offset from animation system (set each frame, NOT spring-driven)
  Offset animationOffset = Offset.zero;
  double animationRotation = 0.0;
  double animationScaleX = 1.0;
  double animationScaleY = 1.0;

  // Cached world transform — recomputed each frame via updateWorldTransform()
  Matrix4 _worldTransform = Matrix4.identity();
  Matrix4 get worldTransform => _worldTransform;

  Bone({
    required this.name,
    required this.localPosition,
    this.localRotation = 0.0,
    this.localScale = 1.0,
    BoneSpring? spring,
    this.influenceRadius = 0.08,
  }) : spring = spring ?? BoneSpring();

  /// Add a child bone to this bone's subtree.
  void addChild(Bone child) {
    child.parent = this;
    children.add(child);
  }

  /// Compute the world-space position of this bone (translation component).
  Offset get worldPosition {
    final storage = _worldTransform.storage;
    return Offset(storage[12], storage[13]);
  }

  /// Forward kinematics: compute world transform from parent chain,
  /// then recurse into children.
  void updateWorldTransform() {
    final local = Matrix4.identity()
      ..translateByDouble(
        localPosition.dx + spring.displacement.dx + animationOffset.dx,
        localPosition.dy + spring.displacement.dy + animationOffset.dy,
        0.0,
        1.0,
      )
      ..rotateZ(localRotation + animationRotation)
      ..scaleByDouble(
        localScale * animationScaleX,
        localScale * animationScaleY,
        1.0,
        1.0,
      );

    _worldTransform =
        parent != null ? parent!.worldTransform.multiplied(local) : local;

    for (final child in children) {
      child.updateWorldTransform();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  AVATAR SKELETON — Full ~28-bone hierarchy with spring physics
// ═══════════════════════════════════════════════════════════════════════

/// Builds and manages the avatar's bone hierarchy.
///
/// All bone positions are in normalized coordinates (0.0-1.0) relative
/// to the widget size. Multiply by the actual pixel size at render time.
///
/// Usage:
/// ```dart
/// final skeleton = AvatarSkeleton();
///
/// // Each frame:
/// skeleton.update(dt); // step physics + recompute transforms
///
/// // On touch:
/// skeleton.applyTouchForce(normalizedPos, force);
/// ```
class AvatarSkeleton {
  late final Bone root;
  late final Map<String, Bone> bones;

  // ── Quick accessors for important bones ─────────────────────────────

  Bone get head => bones['head']!;
  Bone get jaw => bones['jaw']!;
  Bone get leftEye => bones['leftEye']!;
  Bone get rightEye => bones['rightEye']!;
  Bone get leftBrow => bones['leftBrow']!;
  Bone get rightBrow => bones['rightBrow']!;
  Bone get nose => bones['nose']!;
  Bone get leftCheek => bones['leftCheek']!;
  Bone get rightCheek => bones['rightCheek']!;
  Bone get leftEar => bones['leftEar']!;
  Bone get rightEar => bones['rightEar']!;
  Bone get neck => bones['neck']!;
  Bone get chest => bones['chest']!;
  Bone get spine => bones['spine']!;
  Bone get leftShoulder => bones['leftShoulder']!;
  Bone get rightShoulder => bones['rightShoulder']!;
  Bone get leftUpperArm => bones['leftUpperArm']!;
  Bone get rightUpperArm => bones['rightUpperArm']!;
  Bone get leftForearm => bones['leftForearm']!;
  Bone get rightForearm => bones['rightForearm']!;
  Bone get leftHand => bones['leftHand']!;
  Bone get rightHand => bones['rightHand']!;
  Bone get hairRoot => bones['hairRoot']!;

  AvatarSkeleton() {
    _buildSkeleton();
  }

  // ── Skeleton construction ───────────────────────────────────────────

  void _buildSkeleton() {
    // Root — bottom center of widget
    root = Bone(
      name: 'root',
      localPosition: const Offset(0.5, 0.85),
      spring: BoneSpring(stiffness: 300, damping: 20, mass: 5.0),
      influenceRadius: 0.05,
    );

    // Spine chain: root → spine → chest → neck → head
    final spineBone = _makeBone('spine', const Offset(0.0, -0.15),
        stiffness: 200, damping: 16, mass: 3.0, radius: 0.06);
    final chestBone = _makeBone('chest', const Offset(0.0, -0.15),
        stiffness: 180, damping: 14, mass: 2.5, radius: 0.08);
    final neckBone = _makeBone('neck', const Offset(0.0, -0.08),
        stiffness: 180, damping: 14, mass: 1.5, radius: 0.05);
    final headBone = _makeBone('head', const Offset(0.0, -0.25),
        stiffness: 200, damping: 15, mass: 2.0, radius: 0.15);

    root.addChild(spineBone);
    spineBone.addChild(chestBone);
    chestBone.addChild(neckBone);
    neckBone.addChild(headBone);

    // Head children — face features
    final jawBone = _makeBone('jaw', const Offset(0.0, 0.15),
        stiffness: 180, damping: 14, mass: 1.0, radius: 0.06);
    final leftEyeBone = _makeBone('leftEye', const Offset(-0.12, -0.05),
        stiffness: 300, damping: 20, mass: 0.2, radius: 0.04);
    final rightEyeBone = _makeBone('rightEye', const Offset(0.12, -0.05),
        stiffness: 300, damping: 20, mass: 0.2, radius: 0.04);
    final leftBrowBone = _makeBone('leftBrow', const Offset(-0.12, -0.12),
        stiffness: 250, damping: 18, mass: 0.3, radius: 0.04);
    final rightBrowBone = _makeBone('rightBrow', const Offset(0.12, -0.12),
        stiffness: 250, damping: 18, mass: 0.3, radius: 0.04);
    final noseBone = _makeBone('nose', const Offset(0.0, 0.03),
        stiffness: 250, damping: 18, mass: 0.3, radius: 0.04);
    final leftCheekBone = _makeBone('leftCheek', const Offset(-0.15, 0.05),
        stiffness: 60, damping: 6, mass: 0.4, radius: 0.07);
    final rightCheekBone = _makeBone('rightCheek', const Offset(0.15, 0.05),
        stiffness: 60, damping: 6, mass: 0.4, radius: 0.07);
    final leftEarBone = _makeBone('leftEar', const Offset(-0.22, 0.0),
        stiffness: 120, damping: 10, mass: 0.5, radius: 0.04);
    final rightEarBone = _makeBone('rightEar', const Offset(0.22, 0.0),
        stiffness: 120, damping: 10, mass: 0.5, radius: 0.04);
    final hairRootBone = _makeBone('hairRoot', const Offset(0.0, -0.18),
        stiffness: 30, damping: 3, mass: 0.3, radius: 0.10);

    for (final child in [
      jawBone, leftEyeBone, rightEyeBone, leftBrowBone, rightBrowBone,
      noseBone, leftCheekBone, rightCheekBone, leftEarBone, rightEarBone,
      hairRootBone,
    ]) {
      headBone.addChild(child);
    }

    // Shoulder chain: chest → shoulder → upperArm → forearm → hand
    final leftShoulderBone = _makeBone(
        'leftShoulder', const Offset(-0.22, 0.0),
        stiffness: 150, damping: 12, mass: 1.5, radius: 0.06);
    final rightShoulderBone = _makeBone(
        'rightShoulder', const Offset(0.22, 0.0),
        stiffness: 150, damping: 12, mass: 1.5, radius: 0.06);

    chestBone.addChild(leftShoulderBone);
    chestBone.addChild(rightShoulderBone);

    // Left arm
    final leftUpperArmBone = _makeBone(
        'leftUpperArm', const Offset(0.0, 0.10),
        stiffness: 120, damping: 10, mass: 1.0, radius: 0.05);
    final leftForearmBone = _makeBone(
        'leftForearm', const Offset(0.0, 0.12),
        stiffness: 120, damping: 10, mass: 1.0, radius: 0.05);
    final leftHandBone = _makeBone(
        'leftHand', const Offset(0.0, 0.10),
        stiffness: 100, damping: 8, mass: 0.5, radius: 0.04);

    leftShoulderBone.addChild(leftUpperArmBone);
    leftUpperArmBone.addChild(leftForearmBone);
    leftForearmBone.addChild(leftHandBone);

    // Right arm
    final rightUpperArmBone = _makeBone(
        'rightUpperArm', const Offset(0.0, 0.10),
        stiffness: 120, damping: 10, mass: 1.0, radius: 0.05);
    final rightForearmBone = _makeBone(
        'rightForearm', const Offset(0.0, 0.12),
        stiffness: 120, damping: 10, mass: 1.0, radius: 0.05);
    final rightHandBone = _makeBone(
        'rightHand', const Offset(0.0, 0.10),
        stiffness: 100, damping: 8, mass: 0.5, radius: 0.04);

    rightShoulderBone.addChild(rightUpperArmBone);
    rightUpperArmBone.addChild(rightForearmBone);
    rightForearmBone.addChild(rightHandBone);

    // Flatten tree into lookup map
    bones = {};
    _collectBones(root);
  }

  /// Helper: create a Bone with specified spring properties.
  Bone _makeBone(
    String name,
    Offset position, {
    double stiffness = 150,
    double damping = 12,
    double mass = 1.0,
    double radius = 0.08,
  }) {
    return Bone(
      name: name,
      localPosition: position,
      spring: BoneSpring(stiffness: stiffness, damping: damping, mass: mass),
      influenceRadius: radius,
    );
  }

  /// Recursively collect all bones into the [bones] map.
  void _collectBones(Bone bone) {
    bones[bone.name] = bone;
    for (final child in bone.children) {
      _collectBones(child);
    }
  }

  // ── Per-frame update ────────────────────────────────────────────────

  /// Step all spring physics and recompute forward kinematics.
  /// Call once per frame with [dt] in seconds (typically 1/60).
  void update(double dt) {
    for (final bone in bones.values) {
      bone.spring.update(dt);
    }
    root.updateWorldTransform();
  }

  /// Whether any bone spring is still in motion.
  bool get isAnimating => bones.values.any((b) => !b.spring.isAtRest);

  // ── Touch interaction ───────────────────────────────────────────────

  /// Apply a force at a world-space normalized position.
  ///
  /// Finds all bones within their influence radius of [worldPos] and
  /// applies [force] with distance-based falloff. Neighboring bones
  /// receive partial force for a natural, connected feel.
  ///
  /// [worldPos] and [force] are in normalized 0-1 coordinates.
  void applyTouchForce(Offset worldPos, Offset force) {
    for (final bone in bones.values) {
      final bonePos = bone.worldPosition;
      final dist = (worldPos - bonePos).distance;
      final radius = bone.influenceRadius;

      if (dist < radius) {
        // Smooth falloff: 1.0 at center → 0.0 at edge (cosine curve)
        final t = dist / radius;
        final falloff = 0.5 * (1.0 + cos(t * pi));
        bone.spring.applyForce(force * falloff);
      }
    }
  }

  /// Apply a force to a specific bone by name, with optional propagation
  /// to parent/children at reduced strength.
  void applyForceToNamed(String boneName, Offset force,
      {double propagation = 0.3}) {
    final bone = bones[boneName];
    if (bone == null) return;

    bone.spring.applyForce(force);

    // Propagate to parent
    if (bone.parent != null) {
      bone.parent!.spring.applyForce(force * propagation);
    }

    // Propagate to children
    for (final child in bone.children) {
      child.spring.applyForce(force * propagation);
    }
  }

  /// Find the nearest bone to a normalized world position.
  Bone? nearestBone(Offset worldPos) {
    Bone? nearest;
    double bestDist = double.infinity;

    for (final bone in bones.values) {
      final dist = (worldPos - bone.worldPosition).distance;
      if (dist < bestDist) {
        bestDist = dist;
        nearest = bone;
      }
    }
    return nearest;
  }

  // ── Animation pose application ─────────────────────────────────────

  /// Apply a pose from the animation system to bones.
  void applyPose(BonePose pose) {
    for (final entry in pose.transforms.entries) {
      final bone = bones[entry.key];
      if (bone == null) continue;
      final BoneTransform t = entry.value;
      bone.animationOffset = Offset(t.dx, t.dy);
      bone.animationRotation = t.rotation;
      bone.animationScaleX = t.scaleX;
      bone.animationScaleY = t.scaleY;
    }
  }

  /// Clear all animation offsets back to identity.
  void clearPose() {
    for (final bone in bones.values) {
      bone.animationOffset = Offset.zero;
      bone.animationRotation = 0.0;
      bone.animationScaleX = 1.0;
      bone.animationScaleY = 1.0;
    }
  }

  // ── Reset ───────────────────────────────────────────────────────────

  /// Reset all springs to rest state (no displacement or velocity).
  void resetAllSprings() {
    for (final bone in bones.values) {
      bone.spring.reset();
    }
    root.updateWorldTransform();
  }
}

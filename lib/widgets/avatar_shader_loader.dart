import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Loads and caches fragment shaders for the avatar system.
///
/// Call [init] once during app startup. If shader loading fails (e.g. on
/// platforms that don't support runtime shaders), the fields remain null
/// and the avatar system falls back to non-shader rendering.
///
/// Usage:
///   await ShaderLoader.init();
///   final shader = ShaderLoader.hairShimmer; // nullable
class ShaderLoader {
  ShaderLoader._();

  /// Loaded hair shimmer fragment shader, or null if unavailable.
  static ui.FragmentShader? hairShimmer;

  /// Loaded skin glow fragment shader, or null if unavailable.
  static ui.FragmentShader? skinGlow;

  /// Whether shaders were successfully loaded.
  static bool get isAvailable => hairShimmer != null || skinGlow != null;

  /// Load both fragment shaders. Safe to call multiple times (no-ops after first).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    hairShimmer = await _loadShader('shaders/hair_shimmer.frag');
    skinGlow = await _loadShader('shaders/skin_glow.frag');

    debugPrint('ShaderLoader: hair=${hairShimmer != null}, skin=${skinGlow != null}');
  }

  static bool _initialized = false;

  static Future<ui.FragmentShader?> _loadShader(String assetKey) async {
    try {
      final program = await ui.FragmentProgram.fromAsset(assetKey);
      return program.fragmentShader();
    } catch (e) {
      debugPrint('ShaderLoader: failed to load $assetKey: $e');
      return null;
    }
  }
}

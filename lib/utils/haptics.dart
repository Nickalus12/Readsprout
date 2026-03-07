import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Centralized haptic feedback helpers.
/// Wraps platform checks so callers don't need to worry about it.
class Haptics {
  Haptics._();

  static bool get _supported {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Wrong answer — medium buzz, noticeable but not harsh.
  static void wrong() {
    if (_supported) HapticFeedback.mediumImpact();
  }

  /// Correct letter tap — light, satisfying tick.
  static void correct() {
    if (_supported) HapticFeedback.lightImpact();
  }

  /// Word completed or level up — heavy, celebratory thud.
  static void success() {
    if (_supported) HapticFeedback.heavyImpact();
  }

  /// Selection tap — minimal feedback for UI interactions.
  static void tap() {
    if (_supported) HapticFeedback.selectionClick();
  }
}

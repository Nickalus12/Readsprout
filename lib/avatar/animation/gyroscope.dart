import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

// ═══════════════════════════════════════════════════════════════════════
//  GYROSCOPE ADAPTER
//  Smart orientation detection with auto-calibration for avatar head tilt.
// ═══════════════════════════════════════════════════════════════════════

/// Provides smoothed, relative head-tilt values from the device
/// accelerometer.
///
/// Key features:
/// - **Calibrate on open**: captures baseline when avatar screen appears
/// - **Lying-in-bed solution**: auto-recalibrates after 3s of stillness,
///   so the current holding angle becomes the new neutral
/// - **Major reposition detection**: >45° instant jump triggers immediate
///   recalibration (kid flipped the phone)
/// - **Low-pass smoothing**: exponential filter removes jitter
/// - **Platform guard**: no-ops on desktop (tilt stays 0.0)
///
/// Integration:
/// ```dart
/// final gyro = GyroscopeAdapter();
/// gyro.start();  // begins listening + calibrates
///
/// // In animation frame:
/// gyro.update(dt);
/// final tiltX = gyro.headTiltX; // -0.26..+0.26 radians (±15°)
/// final tiltY = gyro.headTiltY;
///
/// gyro.dispose();
/// ```
class GyroscopeAdapter {
  // ── Configuration ───────────────────────────────────────────────────

  /// Low-pass filter factor. Lower = smoother but more lag.
  static const double _smoothing = 0.15;

  /// Seconds of near-stillness before auto-recalibration.
  static const double _recalibrateAfterStill = 3.0;

  /// Movement threshold to count as "still" (radians change per update).
  static const double _stillnessThreshold = 0.02;

  /// Instant-recalibrate threshold (~45° = 0.785 radians).
  static const double _majorShiftThreshold = 0.785;

  /// Max output clamp (±15° ≈ ±0.26 radians).
  static const double _maxTilt = 0.26;

  /// Deadzone — ignore micro-tilts below this (radians).
  static const double _deadzone = 0.008;

  // ── Public output ───────────────────────────────────────────────────

  /// Smoothed left-right tilt in radians. Negative = left, positive = right.
  /// Clamped to ±0.26 rad (±15°).
  double get headTiltX => _headTiltX;
  double _headTiltX = 0.0;

  /// Smoothed forward-back tilt in radians. Negative = forward, positive = back.
  /// Clamped to ±0.26 rad (±15°).
  double get headTiltY => _headTiltY;
  double _headTiltY = 0.0;

  /// Whether the adapter is actively reading sensors.
  bool get isActive => _isActive;
  bool _isActive = false;

  /// Whether sensors are available on this platform.
  bool get isAvailable => _isMobile;

  // ── Internal state ──────────────────────────────────────────────────

  // Platform check (cached)
  static final bool _isMobile = Platform.isAndroid || Platform.isIOS;

  // Calibrated base orientation
  double _baseX = 0.0;
  double _baseY = 0.0;

  // Latest raw tilt from accelerometer (radians)
  double _rawX = 0.0;
  double _rawY = 0.0;

  // Previous frame raw values (for stillness/shift detection)
  double _prevRawX = 0.0;
  double _prevRawY = 0.0;

  // Stillness timer
  double _stillnessTimer = 0.0;

  // Whether we've received at least one sensor reading
  bool _hasReading = false;

  // Calibration sample collection
  static const int _calibrationSampleCount = 10;
  final List<double> _calSamplesX = [];
  final List<double> _calSamplesY = [];
  bool _isCalibrating = false;

  // Sensor subscription
  StreamSubscription<AccelerometerEvent>? _subscription;

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Start listening to accelerometer and calibrate to current orientation.
  /// No-op on desktop platforms.
  void start() {
    if (!_isMobile || _isActive) return;

    _isActive = true;
    _isCalibrating = true;
    _calSamplesX.clear();
    _calSamplesY.clear();
    _stillnessTimer = 0.0;
    _hasReading = false;

    _subscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 33), // ~30 Hz
    ).listen(_onAccelerometerData);

    debugPrint('GyroscopeAdapter: started, calibrating...');
  }

  /// Stop listening to sensors. Tilt values reset to 0.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isActive = false;
    _headTiltX = 0.0;
    _headTiltY = 0.0;
    _hasReading = false;
  }

  /// Manually trigger recalibration to current orientation.
  void calibrate() {
    if (!_hasReading) return;
    _baseX = _rawX;
    _baseY = _rawY;
    _stillnessTimer = 0.0;
    debugPrint('GyroscopeAdapter: calibrated '
        '(baseX=${_baseX.toStringAsFixed(3)}, baseY=${_baseY.toStringAsFixed(3)})');
  }

  /// Release resources. Call when avatar screen is disposed.
  void dispose() {
    stop();
  }

  // ── Per-frame update ────────────────────────────────────────────────

  /// Advance the adapter by [dt] seconds (call once per frame).
  ///
  /// Processes the latest sensor reading, runs the stillness timer,
  /// applies smoothing, and clamps output.
  void update(double dt) {
    if (!_isActive || !_hasReading || _isCalibrating) return;

    // ── Relative tilt from baseline ──
    final targetX = _rawX - _baseX;
    final targetY = _rawY - _baseY;

    // ── Major orientation change detection (>45°) ──
    final deltaX = (_rawX - _prevRawX).abs();
    final deltaY = (_rawY - _prevRawY).abs();

    if (deltaX > _majorShiftThreshold || deltaY > _majorShiftThreshold) {
      debugPrint('GyroscopeAdapter: major shift detected, recalibrating');
      calibrate();
      return;
    }

    // ── Stillness tracking ──
    if (deltaX < _stillnessThreshold && deltaY < _stillnessThreshold) {
      _stillnessTimer += dt;
      if (_stillnessTimer >= _recalibrateAfterStill) {
        // Gently drift baseline toward current position
        _baseX = _baseX * 0.92 + _rawX * 0.08;
        _baseY = _baseY * 0.92 + _rawY * 0.08;
        _stillnessTimer = 0.0;
        debugPrint('GyroscopeAdapter: stillness recalibration');
      }
    } else {
      _stillnessTimer = 0.0;
    }

    _prevRawX = _rawX;
    _prevRawY = _rawY;

    // ── Low-pass filter (exponential smoothing) ──
    _headTiltX = _headTiltX * (1.0 - _smoothing) + targetX * _smoothing;
    _headTiltY = _headTiltY * (1.0 - _smoothing) + targetY * _smoothing;

    // ── Deadzone ──
    if (_headTiltX.abs() < _deadzone) _headTiltX = 0.0;
    if (_headTiltY.abs() < _deadzone) _headTiltY = 0.0;

    // ── Clamp to ±15° ──
    _headTiltX = _headTiltX.clamp(-_maxTilt, _maxTilt);
    _headTiltY = _headTiltY.clamp(-_maxTilt, _maxTilt);
  }

  // ── Sensor callback ─────────────────────────────────────────────────

  void _onAccelerometerData(AccelerometerEvent event) {
    // Compute tilt angles from gravity vector
    final x = event.x;
    final y = event.y;
    final z = event.z;

    final magnitude = sqrt(x * x + y * y + z * z);
    if (magnitude < 0.1) return; // free-fall, skip

    // Normalize and compute tilt via asin
    final nx = (x / magnitude).clamp(-1.0, 1.0);
    final ny = (y / magnitude).clamp(-1.0, 1.0);

    _rawX = asin(nx); // left-right tilt
    _rawY = asin(ny); // forward-back tilt
    _hasReading = true;

    // ── Calibration phase: collect samples then average ──
    if (_isCalibrating) {
      _calSamplesX.add(_rawX);
      _calSamplesY.add(_rawY);

      if (_calSamplesX.length >= _calibrationSampleCount) {
        _baseX =
            _calSamplesX.reduce((a, b) => a + b) / _calSamplesX.length;
        _baseY =
            _calSamplesY.reduce((a, b) => a + b) / _calSamplesY.length;
        _isCalibrating = false;
        _prevRawX = _rawX;
        _prevRawY = _rawY;
        debugPrint('GyroscopeAdapter: calibration complete '
            '(baseX=${_baseX.toStringAsFixed(3)}, '
            'baseY=${_baseY.toStringAsFixed(3)})');
      }
    }
  }
}

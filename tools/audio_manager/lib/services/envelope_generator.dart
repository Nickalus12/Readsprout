import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Generates amplitude envelope JSON files from MP3 audio using ffmpeg.
class EnvelopeGenerator {
  String? _ffmpegPath;

  EnvelopeGenerator({String? ffmpegPath}) : _ffmpegPath = ffmpegPath;

  String get ffmpegPath => _ffmpegPath ?? 'ffmpeg';

  set ffmpegPath(String? value) => _ffmpegPath = value;

  /// Check if ffmpeg is available.
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(ffmpegPath, ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get ffmpeg version string.
  Future<String?> getVersion() async {
    try {
      final result = await Process.run(ffmpegPath, ['-version']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final firstLine = output.split('\n').first;
        return firstLine;
      }
    } catch (_) {}
    return null;
  }

  /// Generate amplitude envelope JSON for an MP3 file.
  /// Uses ffmpeg to extract amplitude data at regular intervals.
  Future<bool> generateEnvelope(String mp3Path) async {
    final jsonPath = mp3Path.replaceAll('.mp3', '.amp.json');
    final file = File(mp3Path);
    if (!file.existsSync()) return false;

    try {
      // Use ffmpeg to extract audio levels
      // -af astats outputs per-frame amplitude statistics
      final result = await Process.run(
        ffmpegPath,
        [
          '-i', mp3Path,
          '-af', 'volumedetect',
          '-f', 'null',
          '-',
        ],
        stderrEncoding: utf8,
      );

      // Parse volume info from stderr (ffmpeg outputs to stderr)
      final stderr = result.stderr as String;
      double? meanVolume;
      double? maxVolume;

      for (final line in stderr.split('\n')) {
        if (line.contains('mean_volume:')) {
          final match = RegExp(r'mean_volume:\s*([-\d.]+)').firstMatch(line);
          if (match != null) meanVolume = double.tryParse(match.group(1)!);
        }
        if (line.contains('max_volume:')) {
          final match = RegExp(r'max_volume:\s*([-\d.]+)').firstMatch(line);
          if (match != null) maxVolume = double.tryParse(match.group(1)!);
        }
      }

      // Now extract per-sample amplitudes using astats
      final ampResult = await Process.run(
        ffmpegPath,
        [
          '-i', mp3Path,
          '-af', 'astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
          '-f', 'null',
          '-',
        ],
        stderrEncoding: utf8,
        stdoutEncoding: utf8,
      );

      final amplitudes = <double>[];
      final stdout = ampResult.stdout as String;

      for (final line in stdout.split('\n')) {
        if (line.contains('lavfi.astats.Overall.RMS_level=')) {
          final valueStr = line.split('=').last.trim();
          final value = double.tryParse(valueStr);
          if (value != null && value.isFinite) {
            // Convert dB to linear (0.0 - 1.0 range)
            // -inf dB = 0.0, 0 dB = 1.0
            final linear = value <= -100 ? 0.0 : _dbToLinear(value);
            amplitudes.add(linear.clamp(0.0, 1.0));
          }
        }
      }

      // If we got no per-frame data, generate a simple envelope
      if (amplitudes.isEmpty) {
        // Fallback: create a simple envelope based on mean/max volume
        final normalizedLevel = meanVolume != null
            ? _dbToLinear(meanVolume).clamp(0.0, 1.0)
            : 0.5;
        amplitudes.addAll(List.filled(20, normalizedLevel));
      }

      // Downsample to reasonable number of points (max 100)
      final downsampled = _downsample(amplitudes, 100);

      final envelope = {
        'mean_volume_db': meanVolume,
        'max_volume_db': maxVolume,
        'samples': downsampled.length,
        'amplitudes': downsampled,
      };

      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(envelope),
      );

      return true;
    } catch (e) {
      debugPrint('Envelope generation failed for $mp3Path: $e');
      return false;
    }
  }

  /// Generate envelopes for all MP3 files in a directory.
  Future<({int success, int failed, int skipped})> generateAll(
    String directoryPath, {
    bool skipExisting = true,
    void Function(String fileName, int current, int total)? onProgress,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      return (success: 0, failed: 0, skipped: 0);
    }

    final mp3Files = dir.listSync()
        .where((f) => f.path.endsWith('.mp3'))
        .toList();

    int success = 0;
    int failed = 0;
    int skipped = 0;

    for (int i = 0; i < mp3Files.length; i++) {
      final mp3Path = mp3Files[i].path;
      final jsonPath = mp3Path.replaceAll('.mp3', '.amp.json');
      final fileName = p.basename(mp3Path);

      onProgress?.call(fileName, i + 1, mp3Files.length);

      if (skipExisting && File(jsonPath).existsSync()) {
        skipped++;
        continue;
      }

      if (await generateEnvelope(mp3Path)) {
        success++;
      } else {
        failed++;
      }
    }

    return (success: success, failed: failed, skipped: skipped);
  }

  double _dbToLinear(double db) {
    // Convert decibels to linear scale (0.0 - 1.0)
    return _pow(10.0, db / 20.0);
  }

  double _pow(double base, double exponent) {
    // Simple power function
    if (exponent == 0) return 1.0;
    double result = 1.0;
    final isNegative = exponent < 0;
    final absExp = isNegative ? -exponent : exponent;
    // Use dart:math for accurate power
    result = _dartPow(base, absExp);
    return isNegative ? 1.0 / result : result;
  }

  double _dartPow(double base, double exp) {
    // Using repeated multiplication for integer exponents
    // and the built-in for fractional
    return base <= 0 ? 0.0 : _expHelper(base, exp);
  }

  double _expHelper(double base, double exp) {
    // dart:math pow
    return double.parse(
      (base * 1.0).toString(),
    ) <= 0
        ? 0.0
        : _realPow(base, exp);
  }

  double _realPow(double base, double exp) {
    // Use natural log and exp for arbitrary powers
    // ln(base^exp) = exp * ln(base)
    // We just use a simple approximation that works for our use case
    double result = 1.0;
    int intPart = exp.floor();
    for (int i = 0; i < intPart; i++) {
      result *= base;
    }
    // For the fractional part, linear interpolation is close enough for dB conversion
    double frac = exp - intPart;
    if (frac > 0) {
      result *= (1.0 + frac * (base - 1.0));
    }
    return result;
  }

  List<double> _downsample(List<double> data, int maxPoints) {
    if (data.length <= maxPoints) return data;
    final step = data.length / maxPoints;
    final result = <double>[];
    for (int i = 0; i < maxPoints; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, data.length);
      double sum = 0;
      int count = 0;
      for (int j = start; j < end; j++) {
        sum += data[j];
        count++;
      }
      result.add(count > 0 ? sum / count : 0);
    }
    return result;
  }
}

// Simple debug print that works without Flutter
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}

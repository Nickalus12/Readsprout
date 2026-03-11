import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Result of a TTS generation request.
class GenerationResult {
  final bool success;
  final String? error;
  final Uint8List? audioBytes;
  final int? statusCode;

  const GenerationResult({
    required this.success,
    this.error,
    this.audioBytes,
    this.statusCode,
  });
}

/// Deepgram Aura-2 TTS service.
class DeepgramService {
  static const String _apiUrl = 'https://api.deepgram.com/v1/speak';
  static const String _fallbackApiKey =
      'e357c884d089ea4d1829625bf41759bcc8e9359f';

  String apiKey;
  String defaultVoice;
  double defaultSpeed;
  final http.Client _client;

  int totalRequests = 0;
  int totalBytes = 0;

  DeepgramService({
    String? apiKey,
    this.defaultVoice = 'aura-2-cordelia-en',
    this.defaultSpeed = 0.8,
  })  : apiKey = apiKey ??
            Platform.environment['DEEPGRAM_API_KEY'] ??
            _fallbackApiKey,
        _client = http.Client();

  /// Generate speech from text and return raw MP3 bytes.
  Future<GenerationResult> generate(
    String text, {
    String? voice,
    double? speed,
  }) async {
    final params = <String, String>{
      'model': voice ?? defaultVoice,
      'encoding': 'mp3',
    };
    final effectiveSpeed = speed ?? defaultSpeed;
    if (effectiveSpeed != 1.0) {
      params['speed'] = effectiveSpeed.toStringAsFixed(2);
    }

    final uri = Uri.parse(_apiUrl).replace(queryParameters: params);

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Token $apiKey',
          'Content-Type': 'text/plain',
        },
        body: text,
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        if (bytes.length < 100) {
          return GenerationResult(
            success: false,
            error: 'Suspiciously small audio (${bytes.length} bytes)',
            statusCode: response.statusCode,
          );
        }
        totalRequests++;
        totalBytes += bytes.length;
        return GenerationResult(
          success: true,
          audioBytes: bytes,
          statusCode: response.statusCode,
        );
      }

      String errorMsg;
      switch (response.statusCode) {
        case 401:
          errorMsg = 'Invalid API key (401). Check your key.';
        case 402:
          errorMsg = 'Insufficient credits (402). Top up your Deepgram account.';
        case 429:
          errorMsg = 'Rate limited (429). Try again in a few seconds.';
        default:
          errorMsg = 'API error ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}';
      }

      return GenerationResult(
        success: false,
        error: errorMsg,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return GenerationResult(
        success: false,
        error: 'Request failed: $e',
      );
    }
  }

  /// Generate speech and save to a file path.
  Future<GenerationResult> generateToFile(
    String text,
    String outputPath, {
    String? voice,
    double? speed,
  }) async {
    final result = await generate(text, voice: voice, speed: speed);
    if (result.success && result.audioBytes != null) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(result.audioBytes!);
    }
    return result;
  }

  /// Test the API key by making a tiny request.
  Future<bool> testConnection() async {
    final result = await generate('test');
    return result.success;
  }

  void dispose() {
    _client.close();
  }
}

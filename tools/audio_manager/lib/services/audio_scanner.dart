import 'dart:io';

import 'package:path/path.dart' as p;

/// Status of a single audio item.
enum AudioStatus { exists, missing }

/// Information about a single audio file.
class AudioFileInfo {
  final String key; // e.g., 'hello', 'a', 'word_complete_0'
  final String displayText; // what gets spoken
  final String category; // 'words', 'letters', 'letter_names', 'phonics', 'phrases', 'effects'
  final String expectedPath; // full file path
  final AudioStatus status;
  final int? fileSize; // bytes, null if missing
  final bool hasAmplitudeJson;

  const AudioFileInfo({
    required this.key,
    required this.displayText,
    required this.category,
    required this.expectedPath,
    required this.status,
    this.fileSize,
    this.hasAmplitudeJson = false,
  });

  String get fileName => p.basename(expectedPath);

  String get fileSizeDisplay {
    if (fileSize == null) return '--';
    if (fileSize! < 1024) return '${fileSize}B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)}KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Scans the Reading Sprout assets/audio directory for existing files.
class AudioScanner {
  final String audioBasePath;

  AudioScanner(this.audioBasePath);

  /// Check if a single file exists and return info.
  AudioFileInfo checkFile({
    required String key,
    required String displayText,
    required String category,
    required String subdir,
  }) {
    final filePath = p.join(audioBasePath, subdir, '$key.mp3');
    final file = File(filePath);
    final ampFile = File(p.join(audioBasePath, subdir, '$key.amp.json'));

    if (file.existsSync()) {
      return AudioFileInfo(
        key: key,
        displayText: displayText,
        category: category,
        expectedPath: filePath,
        status: AudioStatus.exists,
        fileSize: file.lengthSync(),
        hasAmplitudeJson: ampFile.existsSync(),
      );
    }

    return AudioFileInfo(
      key: key,
      displayText: displayText,
      category: category,
      expectedPath: filePath,
      status: AudioStatus.missing,
    );
  }

  /// Scan a list of items and return AudioFileInfo for each.
  List<AudioFileInfo> scanItems({
    required Map<String, String> items, // key -> displayText
    required String category,
    required String subdir,
  }) {
    return items.entries.map((e) => checkFile(
      key: e.key,
      displayText: e.value,
      category: category,
      subdir: subdir,
    )).toList();
  }

  /// Get summary counts for all categories.
  Map<String, ({int total, int existing, int missing})> summarize(
    Map<String, List<AudioFileInfo>> allItems,
  ) {
    final summary = <String, ({int total, int existing, int missing})>{};
    for (final entry in allItems.entries) {
      final existing = entry.value.where((f) => f.status == AudioStatus.exists).length;
      summary[entry.key] = (
        total: entry.value.length,
        existing: existing,
        missing: entry.value.length - existing,
      );
    }
    return summary;
  }

  /// List all MP3 files in a subdirectory.
  List<FileSystemEntity> listMp3Files(String subdir) {
    final dir = Directory(p.join(audioBasePath, subdir));
    if (!dir.existsSync()) return [];
    return dir.listSync().where((f) => f.path.endsWith('.mp3')).toList();
  }
}

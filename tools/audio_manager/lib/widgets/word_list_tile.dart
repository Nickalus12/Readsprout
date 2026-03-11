import 'package:flutter/material.dart';

import '../services/audio_scanner.dart';
import '../theme.dart';
import 'audio_player_widget.dart';

/// A list tile representing a single audio item (word, letter, phrase, etc.).
class WordListTile extends StatelessWidget {
  final AudioFileInfo info;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onGenerate;

  const WordListTile({
    super.key,
    required this.info,
    this.isSelected = false,
    this.onTap,
    this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final exists = info.status == AudioStatus.exists;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isSelected
            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.4))
            : null,
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          exists ? Icons.check_circle : Icons.cancel,
          color: exists ? AppTheme.success : AppTheme.error,
          size: 18,
        ),
        title: Text(
          info.displayText,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${info.fileName}  ${info.fileSizeDisplay}${info.hasAmplitudeJson ? '  [AMP]' : ''}',
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exists)
              AudioPlayerWidget(
                filePath: info.expectedPath,
                compact: true,
              ),
            if (onGenerate != null)
              IconButton(
                icon: Icon(
                  exists ? Icons.refresh : Icons.download,
                  size: 18,
                  color: exists ? AppTheme.warning : AppTheme.accent,
                ),
                tooltip: exists ? 'Regenerate' : 'Generate',
                onPressed: onGenerate,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/voices.dart';
import '../theme.dart';

/// Dropdown widget for selecting a Deepgram Aura-2 voice.
class VoiceSelector extends StatelessWidget {
  final String selectedVoiceId;
  final ValueChanged<String> onChanged;
  final bool compact;

  const VoiceSelector({
    super.key,
    required this.selectedVoiceId,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedVoiceId,
      decoration: InputDecoration(
        labelText: compact ? null : 'Voice',
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : null,
        isDense: compact,
      ),
      dropdownColor: AppTheme.surfaceLight,
      items: Voices.all.map((voice) {
        return DropdownMenuItem<String>(
          value: voice.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                voice.gender == 'Male' ? Icons.male : Icons.female,
                size: 16,
                color: voice.gender == 'Male'
                    ? Colors.lightBlue
                    : Colors.pinkAccent,
              ),
              const SizedBox(width: 8),
              Text(
                voice.name,
                style: const TextStyle(fontSize: 14),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(
                  voice.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

/// Speed slider widget.
class SpeedSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool compact;

  const SpeedSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Speed: ${value.toStringAsFixed(2)}x',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        Row(
          children: [
            const Text('0.5x', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            Expanded(
              child: Slider(
                value: value,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                label: '${value.toStringAsFixed(2)}x',
                onChanged: onChanged,
              ),
            ),
            const Text('2.0x', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ],
    );
  }
}

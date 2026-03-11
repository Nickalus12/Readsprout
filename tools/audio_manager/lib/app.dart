import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/batch_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/generate_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/voice_lab_screen.dart';
import 'services/audio_scanner.dart';
import 'services/deepgram_service.dart';
import 'services/envelope_generator.dart';
import 'theme.dart';

class AudioManagerApp extends StatelessWidget {
  const AudioManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reading Sprout Audio Manager',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  // Default audio base path: the main Reading Sprout app's assets/audio/
  late String _audioBasePath;

  late DeepgramService _deepgram;
  late AudioScanner _scanner;
  late EnvelopeGenerator _envelopeGen;

  bool? _apiConnected;

  @override
  void initState() {
    super.initState();

    // Resolve the audio base path relative to project root
    // This tool lives at tools/audio_manager/, so go up 2 levels
    final scriptDir = Directory.current.path;
    // Try to find the main project root
    String basePath;
    if (FileSystemEntity.isDirectorySync(
        '$scriptDir/../../assets/audio')) {
      basePath = '$scriptDir/../../assets/audio';
    } else {
      // Fallback: assume we're running from the main project root
      basePath = 'D:/Projects/sight_words/assets/audio';
    }
    _audioBasePath = basePath.replaceAll('\\', '/');

    _deepgram = DeepgramService();
    _scanner = AudioScanner(_audioBasePath);
    _envelopeGen = EnvelopeGenerator();
  }

  void _updateAudioBasePath(String newPath) {
    setState(() {
      _audioBasePath = newPath.replaceAll('\\', '/');
      _scanner = AudioScanner(_audioBasePath);
    });
  }

  @override
  void dispose() {
    _deepgram.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left sidebar
          _buildSidebar(),
          // Vertical divider
          const VerticalDivider(width: 1, color: AppTheme.divider),
          // Main content
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildContent()),
                _buildStatusBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: AppTheme.surface,
      child: Column(
        children: [
          // App title
          Container(
            padding: const EdgeInsets.all(16),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Manager',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Reading Sprout',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // Nav items
          _navItem(0, Icons.library_music, 'Browse'),
          _navItem(1, Icons.mic, 'Generate'),
          _navItem(2, Icons.science, 'Voice Lab'),
          _navItem(3, Icons.batch_prediction, 'Batch'),
          _navItem(4, Icons.settings, 'Settings'),
          const Spacer(),
          // API status indicator
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildApiStatus(),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppTheme.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApiStatus() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _apiConnected == true
                ? AppTheme.success
                : _apiConnected == false
                    ? AppTheme.error
                    : AppTheme.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _apiConnected == true
                ? 'API Connected'
                : _apiConnected == false
                    ? 'API Error'
                    : 'Not tested',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return BrowseScreen(
          scanner: _scanner,
          deepgram: _deepgram,
          audioBasePath: _audioBasePath,
        );
      case 1:
        return GenerateScreen(
          deepgram: _deepgram,
          scanner: _scanner,
          audioBasePath: _audioBasePath,
        );
      case 2:
        return VoiceLabScreen(deepgram: _deepgram);
      case 3:
        return BatchScreen(
          deepgram: _deepgram,
          scanner: _scanner,
          envelopeGen: _envelopeGen,
          audioBasePath: _audioBasePath,
        );
      case 4:
        return SettingsScreen(
          deepgram: _deepgram,
          envelopeGen: _envelopeGen,
          audioBasePath: _audioBasePath,
          onAudioBasePathChanged: _updateAudioBasePath,
          onApiKeyChanged: () {
            _deepgram.testConnection().then((ok) {
              if (mounted) setState(() => _apiConnected = ok);
            });
          },
        );
      default:
        return const Center(child: Text('Unknown'));
    }
  }

  Widget _buildStatusBar() {
    // Count files
    final wordFiles = _scanner.listMp3Files('words').length;
    final letterNameFiles = _scanner.listMp3Files('letter_names').length;
    final phonicsFiles = _scanner.listMp3Files('phonics').length;
    final effectFiles = _scanner.listMp3Files('effects').length;
    final phraseFiles = _scanner.listMp3Files('phrases').length;
    final total =
        wordFiles + letterNameFiles + phonicsFiles + effectFiles + phraseFiles;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Text(
            'Audio: $_audioBasePath',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          Text(
            '$total total files  |  words: $wordFiles  letters: $letterNameFiles  phonics: $phonicsFiles  effects: $effectFiles  phrases: $phraseFiles',
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'API: ${_deepgram.totalRequests} reqs / ${(_deepgram.totalBytes / 1024).toStringAsFixed(0)}KB',
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

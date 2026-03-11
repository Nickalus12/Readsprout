import 'package:flutter/material.dart';

import '../data/voices.dart';
import '../data/word_data.dart';
import '../services/audio_scanner.dart';
import '../services/deepgram_service.dart';
import '../theme.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/voice_selector.dart';
import '../widgets/word_list_tile.dart';

/// Main word browser screen with tabbed categories.
class BrowseScreen extends StatefulWidget {
  final AudioScanner scanner;
  final DeepgramService deepgram;
  final String audioBasePath;

  const BrowseScreen({
    super.key,
    required this.scanner,
    required this.deepgram,
    required this.audioBasePath,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  AudioFileInfo? _selectedItem;
  bool _isGenerating = false;
  String _selectedVoice = Voices.defaultVoice;
  double _speed = 0.8;
  int _selectedLevel = 0; // 0 = all

  // Cached scan results
  Map<String, List<AudioFileInfo>> _allItems = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedItem = null;
          _selectedLevel = 0;
        });
      }
    });
    _scanAll();
  }

  void _scanAll() {
    // Words
    final wordItems = <String, String>{};
    for (final w in WordData.allWords) {
      wordItems[w] = w;
    }
    for (final w in WordData.extraWords) {
      wordItems[w] = w;
    }
    // Add sticker audio keys
    wordItems.addAll(WordData.stickerAudio);
    // Add generic welcomes
    wordItems.addAll(WordData.genericWelcomes);

    _allItems = {
      'words': widget.scanner.scanItems(
        items: wordItems,
        category: 'words',
        subdir: 'words',
      ),
      'letters': widget.scanner.scanItems(
        items: {for (var l in 'abcdefghijklmnopqrstuvwxyz'.split('')) l: l},
        category: 'letters',
        subdir: 'letters',
      ),
      'letter_names': widget.scanner.scanItems(
        items: WordData.letterNames,
        category: 'letter_names',
        subdir: 'letter_names',
      ),
      'phonics': widget.scanner.scanItems(
        items: WordData.letterPhonics,
        category: 'phonics',
        subdir: 'phonics',
      ),
      'phrases': _scanPhrases(),
      'effects': widget.scanner.scanItems(
        items: WordData.effects,
        category: 'effects',
        subdir: 'effects',
      ),
    };
    setState(() {});
  }

  List<AudioFileInfo> _scanPhrases() {
    final items = <AudioFileInfo>[];
    for (final entry in WordData.phraseTemplates.entries) {
      final category = entry.key;
      for (int i = 0; i < entry.value.length; i++) {
        items.add(widget.scanner.checkFile(
          key: '${category}_$i',
          displayText: entry.value[i],
          category: 'phrases',
          subdir: 'phrases',
        ));
      }
    }
    return items;
  }

  List<AudioFileInfo> _getFilteredItems() {
    final tabIndex = _tabController.index;
    List<AudioFileInfo> items;

    switch (tabIndex) {
      case 0: // Words by level
        items = _allItems['words'] ?? [];
        if (_selectedLevel > 0 && _selectedLevel <= 22) {
          final levelWords = WordData.dolchWordsByLevel[_selectedLevel - 1]
              .map((w) => w.toLowerCase())
              .toSet();
          items = items.where((i) => levelWords.contains(i.key)).toList();
        }
      case 1: // Letters
        items = _allItems['letters'] ?? [];
      case 2: // Letter Names
        items = _allItems['letter_names'] ?? [];
      case 3: // Phonics
        items = _allItems['phonics'] ?? [];
      case 4: // Phrases
        items = _allItems['phrases'] ?? [];
      case 5: // Effects
        items = _allItems['effects'] ?? [];
      default:
        items = [];
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((i) {
        return i.key.toLowerCase().contains(query) ||
            i.displayText.toLowerCase().contains(query);
      }).toList();
    }

    return items;
  }

  Future<void> _generateSingle(AudioFileInfo info) async {
    setState(() => _isGenerating = true);

    final result = await widget.deepgram.generateToFile(
      info.displayText,
      info.expectedPath,
      voice: _selectedVoice,
      speed: _speed,
    );

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated: ${info.key}'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
        _scanAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${result.error}'),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      setState(() => _isGenerating = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredItems();
    final existingCount = filteredItems.where((i) => i.status == AudioStatus.exists).length;
    final missingCount = filteredItems.length - existingCount;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search words...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        // Tabs
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            _buildTab('Words', _allItems['words']?.length ?? 0),
            _buildTab('Letters', _allItems['letters']?.length ?? 0),
            _buildTab('Letter Names', _allItems['letter_names']?.length ?? 0),
            _buildTab('Phonics', _allItems['phonics']?.length ?? 0),
            _buildTab('Phrases', _allItems['phrases']?.length ?? 0),
            _buildTab('Effects', _allItems['effects']?.length ?? 0),
          ],
        ),
        // Level selector for Words tab
        if (_tabController.index == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildLevelChip('All', 0),
                  for (int i = 1; i <= 22; i++)
                    _buildLevelChip('L$i', i),
                  _buildLevelChip('Bonus', -1),
                  _buildLevelChip('Stickers', -2),
                ],
              ),
            ),
          ),
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: AppTheme.surface,
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: AppTheme.success),
              const SizedBox(width: 4),
              Text(
                '$existingCount',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.cancel, size: 14, color: AppTheme.error),
              const SizedBox(width: 4),
              Text(
                '$missingCount',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${filteredItems.length} items',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _scanAll,
                tooltip: 'Rescan files',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: Row(
            children: [
              // Word list
              Expanded(
                flex: 3,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return WordListTile(
                      info: item,
                      isSelected: _selectedItem?.key == item.key &&
                          _selectedItem?.category == item.category,
                      onTap: () => setState(() => _selectedItem = item),
                      onGenerate: _isGenerating
                          ? null
                          : () => _generateSingle(item),
                    );
                  },
                ),
              ),
              // Detail panel
              if (_selectedItem != null)
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(
                      left: BorderSide(color: AppTheme.divider),
                    ),
                  ),
                  child: _buildDetailPanel(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelChip(String label, int level) {
    final isSelected = _selectedLevel == level;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.surfaceLight,
        side: BorderSide(
          color: isSelected ? AppTheme.accent : AppTheme.divider,
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textSecondary,
        ),
        onSelected: (_) => setState(() => _selectedLevel = level),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildDetailPanel() {
    final item = _selectedItem!;
    final exists = item.status == AudioStatus.exists;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  item.displayText,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _selectedItem = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // File info
          _infoRow('File', item.fileName),
          _infoRow('Category', item.category),
          _infoRow('Status', exists ? 'Exists' : 'Missing',
              color: exists ? AppTheme.success : AppTheme.error),
          if (exists) ...[
            _infoRow('Size', item.fileSizeDisplay),
            _infoRow('Amplitude', item.hasAmplitudeJson ? 'Yes' : 'No'),
          ],
          const SizedBox(height: 16),
          // Player
          if (exists)
            AudioPlayerWidget(
              filePath: item.expectedPath,
              label: 'Current Audio',
            ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.divider),
          const SizedBox(height: 16),
          // Generation controls
          const Text(
            'Generate',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          VoiceSelector(
            selectedVoiceId: _selectedVoice,
            onChanged: (v) => setState(() => _selectedVoice = v),
          ),
          const SizedBox(height: 8),
          SpeedSlider(
            value: _speed,
            onChanged: (v) => setState(() => _speed = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(exists ? Icons.refresh : Icons.download),
                  label: Text(exists ? 'Regenerate' : 'Generate'),
                  onPressed: _isGenerating
                      ? null
                      : () => _generateSingle(item),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color ?? AppTheme.textPrimary,
                fontWeight: color != null ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

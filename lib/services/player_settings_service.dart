import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single player profile entry.
class PlayerEntry {
  final String id;
  final String name;
  final int colorIndex; // index into a predefined color list
  final DateTime createdAt;

  PlayerEntry({
    required this.id,
    required this.name,
    required this.colorIndex,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PlayerEntry.fromJson(Map<String, dynamic> json) => PlayerEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        colorIndex: json['colorIndex'] as int? ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Predefined avatar colors for profile cards.
  static const profileColors = [
    Color(0xFFFF69B4), // pink
    Color(0xFF00D4FF), // cyan
    Color(0xFF10B981), // emerald
    Color(0xFFFFD700), // gold
    Color(0xFF8B5CF6), // violet
    Color(0xFFFF6B6B), // coral
    Color(0xFF06B6D4), // teal
    Color(0xFFF59E0B), // amber
    Color(0xFFEC4899), // magenta
    Color(0xFF3B82F6), // blue
  ];

  Color get color => profileColors[colorIndex % profileColors.length];
}

/// Persists player profile settings (name, preferences).
/// Supports multiple profiles with last-active auto-sign-in.
class PlayerSettingsService {
  static const _nameKey = 'player_name';
  static const _setupCompleteKey = 'setup_complete';
  static const _profilesKey = 'player_profiles';
  static const _activeProfileKey = 'active_profile_id';
  static const _lastPlayedLevelKey = 'last_played_level';
  static const _lastPlayedTierKey = 'last_played_tier';

  late SharedPreferences _prefs;

  String _playerName = '';
  bool _setupComplete = false;
  List<PlayerEntry> _profiles = [];
  String? _activeProfileId;
  int? _lastPlayedLevel;
  int? _lastPlayedTier;

  /// The active player's display name.
  String get playerName => _playerName;

  /// Whether any profile has been set up.
  bool get setupComplete => _setupComplete;

  /// Whether a player name is configured.
  bool get hasName => _playerName.isNotEmpty;

  /// All registered profiles.
  List<PlayerEntry> get profiles => List.unmodifiable(_profiles);

  /// The currently active profile ID (null if none).
  String? get activeProfileId => _activeProfileId;

  /// The currently active profile entry (null if none).
  PlayerEntry? get activeProfile {
    if (_activeProfileId == null) return null;
    try {
      return _profiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return null;
    }
  }

  /// Whether there are multiple profiles.
  bool get hasMultipleProfiles => _profiles.length > 1;

  /// The last level the player was playing (null if never played).
  int? get lastPlayedLevel => _lastPlayedLevel;

  /// The last tier the player was playing (null if never played).
  int? get lastPlayedTier => _lastPlayedTier;

  /// Whether the player has a last-played session to continue.
  bool get hasContinue => _lastPlayedLevel != null;

  /// Record the level and tier the player is currently playing.
  Future<void> setLastPlayed(int level, int tier) async {
    _lastPlayedLevel = level;
    _lastPlayedTier = tier;
    final profileKey = _activeProfileId ?? '';
    await _prefs.setInt('${_lastPlayedLevelKey}_$profileKey', level);
    await _prefs.setInt('${_lastPlayedTierKey}_$profileKey', tier);
  }

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _playerName = _prefs.getString(_nameKey) ?? '';
    _setupComplete = _prefs.getBool(_setupCompleteKey) ?? false;
    _activeProfileId = _prefs.getString(_activeProfileKey);

    // Load profiles
    final raw = _prefs.getString(_profilesKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _profiles = list.map((e) => PlayerEntry.fromJson(e)).toList();
      } catch (_) {
        _profiles = [];
      }
    }

    // Migrate: if we have an old single-profile setup but no profiles list,
    // create a profile entry from the existing name.
    if (_profiles.isEmpty && _playerName.isNotEmpty) {
      final entry = PlayerEntry(
        id: 'profile_0',
        name: _playerName,
        colorIndex: 0,
      );
      _profiles.add(entry);
      _activeProfileId = entry.id;
      await _saveProfiles();
    }

    // Load last-played level/tier for active profile
    _loadLastPlayed();
  }

  void _loadLastPlayed() {
    final profileKey = _activeProfileId ?? '';
    final level = _prefs.getInt('${_lastPlayedLevelKey}_$profileKey');
    final tier = _prefs.getInt('${_lastPlayedTierKey}_$profileKey');
    _lastPlayedLevel = level;
    _lastPlayedTier = tier;
  }

  Future<void> _saveProfiles() async {
    final json = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await _prefs.setString(_profilesKey, json);
    if (_activeProfileId != null) {
      await _prefs.setString(_activeProfileKey, _activeProfileId!);
    }
  }

  /// Add a new player profile and make it active.
  Future<PlayerEntry> addProfile(String name) async {
    final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final entry = PlayerEntry(
      id: id,
      name: name.trim(),
      colorIndex: _profiles.length % PlayerEntry.profileColors.length,
    );
    _profiles.add(entry);
    await switchToProfile(entry.id);
    return entry;
  }

  /// Switch to an existing profile.
  Future<void> switchToProfile(String profileId) async {
    _activeProfileId = profileId;
    final profile = activeProfile;
    if (profile != null) {
      _playerName = profile.name;
      _setupComplete = true;
      _loadLastPlayed();
      await _prefs.setString(_nameKey, _playerName);
      await _prefs.setBool(_setupCompleteKey, true);
    }
    await _saveProfiles();
  }

  /// Rename an existing profile.
  Future<void> renameProfile(String profileId, String newName) async {
    final idx = _profiles.indexWhere((p) => p.id == profileId);
    if (idx < 0) return;
    final old = _profiles[idx];
    _profiles[idx] = PlayerEntry(
      id: old.id,
      name: newName.trim(),
      colorIndex: old.colorIndex,
      createdAt: old.createdAt,
    );
    if (_activeProfileId == profileId) {
      _playerName = newName.trim();
      await _prefs.setString(_nameKey, _playerName);
    }
    await _saveProfiles();
  }

  /// Remove a profile. If it's the active one, clear active.
  Future<void> removeProfile(String profileId) async {
    _profiles.removeWhere((p) => p.id == profileId);
    if (_activeProfileId == profileId) {
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
      if (_activeProfileId != null) {
        await switchToProfile(_activeProfileId!);
      } else {
        _playerName = '';
        _setupComplete = false;
        await _prefs.remove(_nameKey);
        await _prefs.remove(_setupCompleteKey);
        await _prefs.remove(_activeProfileKey);
      }
    }
    await _saveProfiles();
  }

  /// Sign out — clears active profile but keeps profiles list.
  Future<void> signOut() async {
    _activeProfileId = null;
    _playerName = '';
    await _prefs.remove(_activeProfileKey);
    // Keep setupComplete true so we show picker, not name entry
  }

  /// Save the player's name and mark setup as complete.
  /// Legacy — creates a profile if none exist.
  Future<void> setPlayerName(String name) async {
    _playerName = name.trim();
    _setupComplete = true;
    await _prefs.setString(_nameKey, _playerName);
    await _prefs.setBool(_setupCompleteKey, true);

    if (_profiles.isEmpty) {
      await addProfile(name);
    }
  }

  /// Clear the player name (for resetting).
  Future<void> clearPlayerName() async {
    _playerName = '';
    _setupComplete = false;
    await _prefs.remove(_nameKey);
    await _prefs.remove(_setupCompleteKey);
  }
}

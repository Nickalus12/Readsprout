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

  late SharedPreferences _prefs;

  String _playerName = '';
  bool _setupComplete = false;
  List<PlayerEntry> _profiles = [];
  String? _activeProfileId;

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
      await _prefs.setString(_nameKey, _playerName);
      await _prefs.setBool(_setupCompleteKey, true);
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

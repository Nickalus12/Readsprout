import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_profile.dart';

/// Hive-backed persistence for profile data, stickers, and daily rewards.
///
/// Uses three separate Hive boxes:
/// - `profile` — name, avatar, unlocked items, lifetime stats
/// - `stickers` — earned sticker records
/// - `dailyRewards` — chest state, last open date
class ProfileService {
  late Box _profileBox;
  late Box<StickerRecord> _stickerBox;
  late Box _dailyBox;

  /// Active profile ID for key namespacing. Empty string = legacy/default.
  String _profileId = '';

  /// Prefix for profile-scoped keys.
  String get _p => _profileId.isEmpty ? '' : '${_profileId}_';

  /// Initialize by opening all Hive boxes.
  /// Hive.initFlutter() and adapter registration must happen before this.
  Future<void> init() async {
    _profileBox = Hive.box('profile');
    _stickerBox = Hive.box<StickerRecord>('stickers');
    _dailyBox = Hive.box('dailyRewards');
  }

  /// Switch to a different profile. All subsequent reads/writes are scoped.
  void switchProfile(String profileId) {
    _profileId = profileId;
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Read a value from a Hive box with profile-scoped key, falling back
  /// to the legacy flat key for backward compatibility.
  T _get<T>(Box box, String key, {required T defaultValue}) {
    if (_p.isNotEmpty) {
      final scoped = box.get('$_p$key');
      if (scoped != null) return scoped as T;
      // Fallback: legacy flat key (pre-multi-profile data)
      final legacy = box.get(key);
      if (legacy != null) return legacy as T;
      return defaultValue;
    }
    return box.get(key, defaultValue: defaultValue) as T;
  }

  /// Read a nullable value with profile scoping + legacy fallback.
  T? _getOrNull<T>(Box box, String key) {
    if (_p.isNotEmpty) {
      final scoped = box.get('$_p$key');
      if (scoped is T) return scoped;
      final legacy = box.get(key);
      if (legacy is T) return legacy;
      return null;
    }
    return box.get(key) as T?;
  }

  // ── Profile ────────────────────────────────────────────────────────

  String get name => _get<String>(_profileBox, 'name', defaultValue: '');

  Future<void> setName(String name) => _profileBox.put('${_p}name', name);

  bool get setupComplete =>
      _get<bool>(_profileBox, 'setupComplete', defaultValue: false);

  Future<void> markSetupComplete() =>
      _profileBox.put('${_p}setupComplete', true);

  AvatarConfig get avatar {
    final stored = _getOrNull<AvatarConfig>(_profileBox, 'avatar');
    if (stored != null) return stored;
    return AvatarConfig.defaultAvatar();
  }

  Future<void> setAvatar(AvatarConfig config) =>
      _profileBox.put('${_p}avatar', config);

  int get totalWordsEverCompleted =>
      _get<int>(_profileBox, 'totalWordsEverCompleted', defaultValue: 0);

  Future<void> setTotalWordsEverCompleted(int count) =>
      _profileBox.put('${_p}totalWordsEverCompleted', count);

  ReadingLevel get readingLevel =>
      ReadingLevel.forWordCount(totalWordsEverCompleted);

  // ── Words Played Today ────────────────────────────────────────────

  int get wordsPlayedToday {
    final lastDate = _getOrNull<DateTime>(_profileBox, 'wordsPlayedDate');
    if (lastDate == null) return 0;
    final now = DateTime.now();
    if (lastDate.year == now.year &&
        lastDate.month == now.month &&
        lastDate.day == now.day) {
      return _get<int>(_profileBox, 'wordsPlayedToday', defaultValue: 0);
    }
    return 0; // Different day, reset
  }

  Future<void> setWordsPlayedToday(int count) async {
    await _profileBox.put('${_p}wordsPlayedToday', count);
    await _profileBox.put('${_p}wordsPlayedDate', DateTime.now());
  }

  // ── Unlocked Items ─────────────────────────────────────────────────

  List<String> get unlockedItems {
    final raw = _getOrNull<List>(_profileBox, 'unlockedItems');
    if (raw != null) return List<String>.from(raw);
    return <String>[];
  }

  Future<void> unlockItem(String itemId) async {
    final items = unlockedItems;
    if (!items.contains(itemId)) {
      items.add(itemId);
      await _profileBox.put('${_p}unlockedItems', items);
    }
  }

  bool isItemUnlocked(String itemId) => unlockedItems.contains(itemId);

  // ── Stickers ───────────────────────────────────────────────────────

  /// Profile-scoped sticker key.
  String _stickerKey(String stickerId) => '$_p$stickerId';

  List<StickerRecord> get allStickers {
    if (_profileId.isEmpty) return _stickerBox.values.toList();
    // Filter stickers for the active profile
    return _stickerBox.keys
        .where((k) => (k as String).startsWith(_p))
        .map((k) => _stickerBox.get(k))
        .whereType<StickerRecord>()
        .toList();
  }

  bool hasSticker(String id) => _stickerBox.containsKey(_stickerKey(id));

  Future<void> awardSticker(StickerRecord sticker) async {
    final key = _stickerKey(sticker.stickerId);
    if (!_stickerBox.containsKey(key)) {
      await _stickerBox.put(key, sticker);
    }
  }

  /// Mark a sticker as no longer "new" (after the user views it).
  Future<void> markStickerSeen(String stickerId) async {
    final key = _stickerKey(stickerId);
    final sticker = _stickerBox.get(key);
    if (sticker != null && sticker.isNew) {
      final updated = sticker.copyWith(isNew: false);
      await _stickerBox.put(key, updated);
    }
  }

  /// Number of stickers that haven't been viewed yet.
  int get newStickerCount => allStickers.where((s) => s.isNew).length;

  // ── Activity Chest ─────────────────────────────────────────────────
  // Tiered daily chests: 1st at 10 words, 2nd at 25, 3rd at 50.
  // Max 3 chests per day. Chests should feel special, not spammable.

  /// Word thresholds for each daily chest (cumulative words played today).
  static const List<int> chestThresholds = [10, 25, 50];

  /// Maximum chests earnable per day.
  static const int maxDailyChests = 3;

  /// Total chests the player has ever opened (lifetime).
  int get chestsOpenedTotal =>
      _get<int>(_dailyBox, 'chestsOpenedTotal', defaultValue: 0);

  /// Number of chests already claimed today out of what was earned.
  int get _chestsClaimedToday {
    final lastDate = _getOrNull<DateTime>(_dailyBox, 'chestsClaimedDate');
    if (lastDate == null) return 0;
    final now = DateTime.now();
    if (lastDate.year == now.year &&
        lastDate.month == now.month &&
        lastDate.day == now.day) {
      return _get<int>(_dailyBox, 'chestsClaimedToday', defaultValue: 0);
    }
    return 0; // New day, reset claimed count
  }

  /// How many chests have been earned today based on word thresholds.
  int get _chestsEarnedToday {
    final words = wordsPlayedToday;
    int earned = 0;
    for (final threshold in chestThresholds) {
      if (words >= threshold) earned++;
    }
    return earned;
  }

  /// How many chests are currently available to open.
  int get chestsAvailable {
    final earned = _chestsEarnedToday;
    final claimed = _chestsClaimedToday;
    return (earned - claimed).clamp(0, maxDailyChests);
  }

  /// Which chest number the player is working toward (0-indexed into thresholds).
  /// Returns maxDailyChests if all chests are earned.
  int get currentChestIndex => _chestsEarnedToday;

  /// Whether all daily chests have been earned and claimed.
  bool get allDailyChestsComplete =>
      _chestsEarnedToday >= maxDailyChests &&
      _chestsClaimedToday >= maxDailyChests;

  /// Words needed to reach the next chest threshold, or 0 if all earned.
  int get wordsUntilNextChest {
    final idx = _chestsEarnedToday;
    if (idx >= maxDailyChests) return 0;
    return chestThresholds[idx] - wordsPlayedToday;
  }

  /// Progress toward the current chest threshold (0.0 to 1.0).
  double get chestProgress {
    final idx = _chestsEarnedToday;
    if (idx >= maxDailyChests) return 1.0;
    final target = chestThresholds[idx];
    final previousTarget = idx > 0 ? chestThresholds[idx - 1] : 0;
    final range = target - previousTarget;
    if (range <= 0) return 1.0;
    return ((wordsPlayedToday - previousTarget) / range).clamp(0.0, 1.0);
  }

  /// Whether at least one chest is ready to open.
  bool get hasChestReady => chestsAvailable > 0;

  /// Legacy compatibility — true if any chest was opened today.
  bool get dailyChestOpened => _chestsClaimedToday > 0;

  /// Mark one chest as opened. Returns the new total.
  Future<int> markChestOpened() async {
    final newTotal = chestsOpenedTotal + 1;
    await _dailyBox.put('${_p}chestsOpenedTotal', newTotal);

    // Track claims for today
    final newClaimed = _chestsClaimedToday + 1;
    await _dailyBox.put('${_p}chestsClaimedToday', newClaimed);
    await _dailyBox.put('${_p}chestsClaimedDate', DateTime.now());

    return newTotal;
  }

  /// Legacy — still supports old callers.
  Future<void> openDailyChest() => markChestOpened();

  /// The ID of the last reward received from a chest.
  String? get lastChestRewardId =>
      _getOrNull<String>(_dailyBox, 'lastChestRewardId');

  Future<void> setLastChestRewardId(String rewardId) =>
      _dailyBox.put('${_p}lastChestRewardId', rewardId);

  /// Legacy string-based reward (for backward compat).
  String? get lastChestReward =>
      _getOrNull<String>(_dailyBox, 'lastReward');

  Future<void> setLastChestReward(String reward) =>
      _dailyBox.put('${_p}lastReward', reward);

  // ── Migration from SharedPreferences ───────────────────────────────

  /// Migrate existing SharedPreferences data to Hive on first launch.
  /// Safe to call multiple times — skips if already migrated.
  static Future<void> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileBox = Hive.box('profile');

      // Check if migration already happened
      if (profileBox.get('_migrated', defaultValue: false) as bool) {
        return;
      }

      // Migrate player name from PlayerSettingsService
      final oldName = prefs.getString('player_name');
      final oldSetupComplete = prefs.getBool('setup_complete');
      if (oldName != null && oldName.isNotEmpty) {
        await profileBox.put('name', oldName);
        debugPrint('Migrated player name: $oldName');
      }
      if (oldSetupComplete == true) {
        await profileBox.put('setupComplete', true);
      }

      // Migrate streak data from StreakService
      final streakRaw = prefs.getString('streak_data');
      if (streakRaw != null) {
        try {
          // streak_data is JSON: {currentStreak, longestStreak, lastPracticeDate, ...}
          // We import dart:convert at top if needed, but keep it simple
          // The StreakService stores as JSON string; parse it manually
          // For safety, we just copy the raw values and let ProfileService
          // manage them going forward.
          debugPrint('Streak data found in SharedPreferences (will be read by StreakService)');
        } catch (e) {
          debugPrint('Failed to migrate streak data: $e');
        }
      }

      // Mark migration as done
      await profileBox.put('_migrated', true);
      debugPrint('SharedPreferences -> Hive migration complete');

      // Note: We do NOT delete the old SharedPreferences keys yet.
      // The old services (PlayerSettingsService, StreakService) still read
      // from them as fallback. They can be removed in a future release.
    } catch (e) {
      debugPrint('Migration from SharedPreferences failed: $e');
    }
  }
}

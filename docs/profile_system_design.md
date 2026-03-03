# Profile System Design — "My Word Garden"

## Design Philosophy

The profile is the child's **personal enchanted garden** — a living, growing world that reflects their reading journey. Every word they learn plants a flower. Every level grows a tree. Their bookworm companion evolves alongside them. The dark theme (#0A0A1A) creates a magical "nighttime garden" with glowing flowers, fireflies, and constellation-like word maps.

**Core principles:**
- Visual, not data-heavy (no percentages, no charts — kids don't understand those)
- Everything is tappable and interactive (bounce, wiggle, glow, sound)
- Growth metaphor throughout (seeds → sprouts → flowers → trees → full garden)
- Frequent, exaggerated rewards (confetti, sound effects, character reactions)
- Zero text-reliance for navigation (icons + visual cues for pre-literate users)
- Touch targets minimum 48x48dp with 64px gaps (motor skills for ages 4-7)
- **100% local storage** — no cloud, no accounts, no sign-in, no backend
- **Cross-platform** — works identically on Windows, Android, iOS, web, macOS, Linux

---

## 1. Profile Screen Layout

### Overall Structure
Vertically scrollable screen, divided into 6 sections:

```
┌──────────────────────────────────────────────┐
│  [← Back]       "My Garden"         [⚙ gear]│  ← Header
│                                              │
│             ★ Word Explorer ★                │  ← Reading Level Title (glowing)
│                                              │
│           ┌──────────────┐                   │
│           │  [Avatar]    │                   │  ← 80x80 avatar circle
│           │              │                   │
│           │ 🐛 Bookworm  │                   │  ← Companion below avatar
│           └──────────────┘                   │
│                                              │
│           "Hi, Patience!"                    │  ← Name with shimmer
│                                              │
│    ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│    │ 🌸 45    │ │ ⭐ 23    │ │ 🔥 5     │    │  ← Stats row
│    │ flowers  │ │ mastered │ │ days     │    │
│    └──────────┘ └──────────┘ └──────────┘    │
├──────────────────────────────────────────────┤
│  📖 My Bookworm                              │  ← Companion Card
│  [Animated bookworm] "Word Explorer"         │
│  ████████░░░░░░ 60/120 words to next!        │
│  [See Evolution Path →]                      │
├──────────────────────────────────────────────┤
│  🎁 Daily Treasure                           │  ← Treasure Chest
│  [Chest animation]                           │
│  "Play today to open!"                       │
│  🔥🔥🔥🔥🔥 5 Day Streak!                   │
├──────────────────────────────────────────────┤
│  🌿 My Garden                                │  ← Garden Visualization
│  [Horizontal scrolling garden rows]          │
│  Each level = one garden plot                │
│  Flowers bloom for each mastered word        │
├──────────────────────────────────────────────┤
│  🏆 Sticker Book                             │  ← Sticker Collection
│  [Horizontal scrollable sticker grid]        │
│  Earned stickers glow, unearned are shadows  │
├──────────────────────────────────────────────┤
│  ✨ Words I Know                              │  ← Word Constellation
│  [Constellation map of mastered words]       │
│  Connected by glowing lines, grouped by level│
│  "X more to discover!"                       │
└──────────────────────────────────────────────┘
```

### Hero Section (Top 40% of viewport)
- **Background:** Dark gradient (reuse existing) with animated firefly particles (adapted from FloatingHeartsBackground — smaller, brighter, golden particles)
- **Reading Level Title:** Displayed prominently above the avatar with `AppColors.starGold` glow effect, animated shimmer
- **Avatar:** 80x80 circular widget (see Avatar System below), with a soft outer glow ring in the child's chosen color
- **Bookworm Companion:** Positioned just below/beside the avatar, animated idle wiggle
- **Player Name:** Fredoka font, 28px, white with magenta/violet glow shadows (matching home screen style)
- **Stats Row:** Three glass-morphism cards in a row:
  - Flowers (total words attempted): flower icon in pink
  - Mastered (words with 3+ perfect runs): star icon in gold
  - Streak (consecutive days played): flame icon in orange-red

---

## 2. Avatar / Companion System

### Avatar Builder ("Create Your Look")

Built entirely with Flutter widgets — **no external packages needed**. Uses `Stack`, `ClipOval`, `Container`, and `CustomPaint`.

**Customizable parts:**

| Part | Options | Implementation |
|------|---------|----------------|
| Face Shape | Circle, Rounded Square, Oval (3) | `ClipRRect` with varying border radius |
| Skin Tone | 6 inclusive tones | Background `Color` of face container |
| Hair Style | Short, Long, Curly, Braids, Ponytail, Buzz, Afro, Bun (8) | `CustomPainter` drawing hair shapes above/around face |
| Hair Color | Black, Brown, Blonde, Red, Blue*, Purple* (6 + 2 unlockable) | Paint color |
| Eyes | Round, Star-shaped, Hearts, Happy Crescents, Big Sparkle (5) | Small `CustomPainter` or emoji-like widgets |
| Mouth | Smile, Big Grin, Tongue Out, Surprised O (4) | `CustomPainter` arcs/shapes |
| Accessory | None, Glasses, Crown, Flower, Bow, Cap (6 + 3 unlockable) | Positioned widget on top of avatar |
| BG Color | 8 bright colors from existing palette | Circle background behind avatar |

**Unlockable avatar items (tied to progress):**
- **Blue hair color** — unlock at 25 words mastered
- **Purple hair color** — unlock at 50 words mastered
- **Wizard hat accessory** — unlock at "Word Wizard" evolution (Stage 3)
- **Butterfly wings accessory** — unlock at "Word Champion" evolution (Stage 4)
- **Crown accessory** — unlock at "Reading Superstar" evolution (Stage 5)
- **Sparkle effect** — unlock at 7-day streak
- **Rainbow sparkle effect** — unlock at 14-day streak
- **Golden glow ring** — unlock at 30-day streak

**Avatar Editor UI:**
- Full-screen overlay/bottom sheet
- Shows live preview of avatar at top (large, 120x120)
- Horizontal scroll row for each part category
- Each option is a 64x64 tappable preview tile
- Locked items show a small lock icon + "25 words!" hint
- Selecting an option animates the preview (bounce + glow)
- "Done" button saves to SharedPreferences

### Bookworm Companion ("My Reading Buddy")

The companion is a friendly bookworm character that **evolves through 5 stages** based on total words mastered. Built with Flutter widgets + flutter_animate, NOT Rive (to avoid new dependencies).

**Evolution Stages:**

| Stage | Title | Words Needed | Appearance | Color |
|-------|-------|-------------|------------|-------|
| 1 | Word Sprout | 0-20 | Tiny green caterpillar with a leaf hat | Emerald green |
| 2 | Word Explorer | 21-60 | Bigger caterpillar carrying a small book | Teal |
| 3 | Word Wizard | 61-120 | Caterpillar wearing a wizard hat, sparkles | Violet |
| 4 | Word Champion | 121-180 | Beautiful butterfly with glowing wings | Electric blue |
| 5 | Reading Superstar | 181-269 | Magnificent butterfly with crown + rainbow trail | Gold/rainbow |

**Visual implementation:**
- Each stage is a `StatelessWidget` composed of `Container` shapes + `CustomPainter` + `flutter_animate`
- Body: Rounded `Container` segments (3-5 circles for caterpillar, wing shapes for butterfly)
- Eyes: Two white circles with small black pupils (animated to blink occasionally)
- Hat/accessories: `Positioned` widgets above the body
- Idle animation: gentle bobbing up-down (flutter_animate `slideY` loop)
- Tap reaction: wiggle animation + play random encouraging phrase audio

**Evolution celebration:**
When the child crosses a threshold (e.g., masters their 21st word):
1. Screen dims slightly
2. Current bookworm moves to center with scale-up animation
3. Sparkle particles swirl around it
4. Flash of light (white overlay fade in/out)
5. New form appears with bounce-in animation
6. Confetti explosion (existing confetti package)
7. New title appears: "You're now a Word Explorer!"
8. Audio: personalized celebration phrase plays
9. 3-second celebration, then returns to game

---

## 3. Collection / Trophy System

### Word Blossoms (Garden Collection)

Every word the child masters becomes a glowing flower in their garden.

**Flower types by tier (if tier system is implemented):**
- Tier 1 (Learning): Bud / sprout — small green dot
- Tier 2 (Practice): Blooming flower — colored circle with petals
- Tier 3 (Mastery): Full golden flower — glowing, animated petals

**Flower colors:** Match the level's gradient from `AppColors.levelGradients`

**Garden layout:**
- Horizontal scrollable `ListView` of garden "plots"
- Each plot = one level (22 plots total)
- Each plot contains a 2x5 grid of flower positions
- Empty positions: dark soil circle with "?" dimmed
- Planted positions: animated flower with gentle sway
- Completed plots have a small tree growing from the center

**Tap interaction:** Tapping a flower:
1. Flower scales up with bounce
2. Shows the word it represents in a floating label
3. Plays the word audio
4. Flower glows brighter momentarily

### Sticker Book

A physical-feeling sticker collection page.

**Sticker categories:**

| Category | Sticker | Trigger |
|----------|---------|---------|
| Level Completion | Level-themed sticker (1 per level) | Complete all 10 words in a level |
| Milestone | "First Word!" | Master 1st word |
| Milestone | "10 Words!" | Master 10 words |
| Milestone | "25 Words!" | Master 25 words |
| Milestone | "50 Words!" | Master 50 words |
| Milestone | "100 Words!" | Master 100 words |
| Milestone | "150 Words!" | Master 150 words |
| Milestone | "200 Words!" | Master 200 words |
| Milestone | "All Words!" | Master all 269 words |
| Streak | "3 Day Streak" | 3 consecutive days |
| Streak | "7 Day Streak" | 7 consecutive days |
| Streak | "14 Day Streak" | 14 consecutive days |
| Streak | "30 Day Streak" | 30 consecutive days |
| Perfect | "Perfect Level" | Complete a level with 0 mistakes |
| Evolution | Stage-specific sticker | Reach each bookworm evolution |
| Special | "Speed Reader" | Complete 5 words in under 2 minutes |

**Total: ~40 stickers**

**Sticker display:**
- Horizontal `Wrap` grid inside a rounded container
- Earned stickers: full color, soft glow, tappable
- Unearned stickers: dark silhouette (same shape, but `AppColors.surface` with 30% opacity)
- Tap earned sticker → grows to 2x, spins once, shows achievement name + date earned
- Most recent sticker has a "NEW!" badge that pulses

---

## 4. Reading Level Title System

**Display:** The reading level title is the most prominent text on the profile, shown above the avatar with a glowing effect.

**Title rendering:**
```
★ Word Explorer ★
```
- Font: Fredoka, 24px, bold
- Color: `AppColors.starGold`
- Glow: double shadow (gold 0.7 alpha, 16px blur + gold 0.3 alpha, 40px blur)
- Animation: slow shimmer sweep (flutter_animate `.shimmer()`)
- Stars flanking the title (★) rendered as actual star icons, pulsing gently

**Evolution Path Viewer:**
Accessible by tapping the title or the "See Evolution Path" button on the companion card.

Shows a vertical path with all 5 stages:
```
┌──────────────────────────────┐
│  Evolution Path              │
│                              │
│  ✅ Word Sprout (0-20)       │  ← Completed, checkmark
│  │                           │
│  ★ Word Explorer (21-60) ←── │  ← CURRENT, highlighted, glowing
│  │  ████████░░░ 45/60        │
│  │                           │
│  🔒 Word Wizard (61-120)     │  ← Locked, dimmed
│  │                           │
│  🔒 Word Champion (121-180)  │
│  │                           │
│  🔒 Reading Superstar (181+) │
└──────────────────────────────┘
```

- Completed stages: green checkmark, full color bookworm icon
- Current stage: golden border, animated glow, progress bar showing words to next
- Future stages: lock icon, dimmed, silhouette of future form
- Connecting line between stages: dotted for locked, solid for unlocked

---

## 5. Progress Visualization

### Primary: The Garden (described in Collection section)
The garden IS the progress visualization. Instead of charts, the child watches their garden grow from empty soil to a lush glowing paradise.

**Garden progress milestones:**
- 0 words: Empty dark soil with a single seed
- 10 words: First sprouts appearing
- 50 words: Several flowers blooming, first bush
- 100 words: Half garden blooming, small tree
- 150 words: Most plots have flowers, trees growing
- 200 words: Lush garden, multiple trees, butterflies appear
- 269 words: FULL GARDEN — golden glow, rainbow arch, all flowers blooming

### Secondary: Word Constellation ("Words I Know")

A visual representation of all mastered words as stars in a night sky constellation.

**Implementation:**
- Dark container with subtle star-field background (tiny white dots)
- Each mastered word rendered as a glowing text chip positioned in clusters by level
- Clusters connected by thin glowing lines (`CustomPainter` — `drawLine` with `AppColors.electricBlue` at 0.2 alpha)
- Words closer to mastery (more perfect attempts) glow brighter
- Newly mastered words appear with a "shooting star" trail animation
- Tapping a word: plays audio, shows a ripple glow effect

**Layout strategy:**
- Use a `CustomPainter` for the connecting lines
- Words positioned using a deterministic layout algorithm (not random — same position every time)
- Each level's words form a recognizable cluster shape (circle, triangle, etc.)
- Clusters arranged in a gentle spiral or grid

**"Words left" counter at bottom:**
```
✨ 45 words mastered · 224 more to discover! ✨
```

---

## 6. Daily Engagement

### Treasure Chest

**Mechanic:**
- One chest per day
- Opens when the child completes at least 5 words in a session
- Contains a random reward from the pool:
  - Garden decoration (rare flower color, garden gnome, butterfly, bird)
  - Avatar accessory (if one is available to unlock at current progress)
  - Bonus sticker (cosmetic, not tied to milestone)
  - "Word of the Day" highlight (a random word gets a special glow)

**Chest tiers based on streak:**
- 0-2 day streak: Wooden chest (brown, simple)
- 3-6 day streak: Silver chest (gray with shine)
- 7+ day streak: Golden chest (gold with sparkles)

Higher tier chests have better drop rates for rare items.

**Chest animation:**
1. Locked state: Chest gently wobbles left-right, lock icon visible
2. Tap when locked: Chest shakes more vigorously, "Play 5 words to open!" tooltip
3. Unlocked state: Chest glows, lock disappears, "Tap to open!" text pulses
4. Opening: Lid flips open (scale + rotation), golden light beams emit upward, item floats up from inside with bounce
5. Opened state: Open chest with item displayed above, "Come back tomorrow!" text

**Implementation:**
- `AnimatedSwitcher` between locked/unlocked/opening/opened states
- Light beams: Stacked `Container` widgets with gradient + rotation + opacity animation
- Item reveal: `SlideTransition` upward + `ScaleTransition` + `FadeTransition`

### Streak System — "Reading Flame"

**Visual representation:**

| Days | Icon | Size | Color | Animation |
|------|------|------|-------|-----------|
| 1 | Candle flame | Small | Orange | Gentle flicker |
| 2 | Candle flame | Small | Orange | Flicker |
| 3 | Campfire | Medium | Orange-red | Crackling |
| 5 | Campfire | Medium | Red-orange | Bigger crackle |
| 7 | Bonfire | Large | Red with gold sparks | Sparks flying up |
| 14 | Magic fire | Large | Blue-purple | Color shifting |
| 21 | Magic fire | Large | Rainbow | Prismatic shift |
| 30 | Phoenix flame | XL | Gold with rainbow | Majestic pulse |

**Implementation:**
- Stack of animated shapes (ovals, triangles) with opacity and scale oscillation
- Color interpolation using `ColorTween` based on streak count
- Particle sparks: small circles animating upward with fade-out
- All achievable with `flutter_animate` + `CustomPainter`

**Streak display:**
```
🔥🔥🔥🔥🔥  5 Day Streak!
[flame] [flame] [flame] [flame] [flame]   ← Individual flame icons for each day
```
- Each flame icon is a small version of the flame that builds up
- "Best streak: 12 days" shown in small text below
- Missing a day resets current streak, but best streak is preserved

---

## 7. Interactive Elements

### Tap Interactions

| Element | Tap Action | Animation | Sound |
|---------|-----------|-----------|-------|
| Avatar | Giggle | Bounce + wobble | Giggle sound effect |
| Bookworm | Random phrase | Wiggle side-to-side | Phrase audio |
| Treasure chest (locked) | Shake | Vigorous shake | Rattle sound |
| Treasure chest (ready) | Open sequence | Full opening animation | Fanfare |
| Sticker (earned) | Show details | Scale up + spin | Pop sound |
| Sticker (locked) | Show hint | Brief shake | Soft click |
| Word in constellation | Play audio | Ripple glow | Word audio |
| Flower in garden | Show word | Bounce + glow | Chime |
| Reading level title | Show evolution path | Pulse | Whoosh |
| Streak flame | Show streak details | Flame grows briefly | Crackle |
| Stats badges | Counter animation | Number counts up | Tick sounds |

### Long-Press Interactions

| Element | Long-Press Action |
|---------|-------------------|
| Avatar | Opens avatar editor |
| Any word | Shows word stats (attempts, accuracy) for parent |

### Swipe/Scroll Interactions

| Area | Gesture | Action |
|------|---------|--------|
| Garden | Horizontal scroll | Browse level plots |
| Sticker book | Horizontal scroll | Browse sticker collection |
| Word constellation | Pan/scroll | Explore word map |
| Profile screen | Vertical scroll | Navigate between sections |
| Evolution path | Vertical scroll | See all stages |

---

## 8. Data Model & Storage Architecture

### Storage: Hive (Local-Only, Cross-Platform)

**Why Hive over SharedPreferences:**
- SharedPreferences is fine for simple key-value pairs but struggles with structured data (nested objects, lists of objects, typed collections)
- Hive is a lightweight, fast, pure-Dart key-value database that works on **every Flutter platform** (Android, iOS, Windows, macOS, Linux, web) with zero native dependencies
- Hive supports TypeAdapters for clean serialization of custom objects (AvatarConfig, stickers, etc.)
- Hive boxes can be opened/closed independently — profile data doesn't compete with progress data
- No backend, no cloud, no accounts — all data lives in the local filesystem (or IndexedDB on web)

**New dependency:**
```yaml
# pubspec.yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0  # Hive.initFlutter() for platform-agnostic path resolution

dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.0
```

**Hive box layout:**

| Box Name | Key Type | Value Type | Contents |
|----------|----------|------------|----------|
| `profile` | String | dynamic | Single profile record: name, avatar, streak, unlocks |
| `stickers` | String | StickerRecord | Earned sticker ID → date earned + metadata |
| `dailyRewards` | String | dynamic | Chest state, last open date, reward history |
| `progress` | int | LevelProgress | Level progress (migrate from SharedPreferences) |

Each box is a separate file on disk — fast to open, independent reads/writes, no contention.

**Initialization (in `main.dart`):**
```dart
await Hive.initFlutter(); // resolves correct path per platform automatically
Hive.registerAdapter(AvatarConfigAdapter());
Hive.registerAdapter(StickerRecordAdapter());
await Hive.openBox('profile');
await Hive.openBox('stickers');
await Hive.openBox('dailyRewards');
await Hive.openBox<Map>('progress'); // or migrate existing SharedPreferences data
```

**Migration from SharedPreferences:**
The existing `ProgressService` uses SharedPreferences. During the first launch after upgrade:
1. Check if SharedPreferences `sight_words_progress` key exists
2. If yes, read it, convert to Hive `progress` box entries, delete the SharedPreferences key
3. All future reads/writes go through Hive
4. `PlayerSettingsService` (name) also migrates to the `profile` box

**Cross-platform storage locations (automatic via `hive_flutter`):**
- **Android:** App-internal storage (`getApplicationDocumentsDirectory()`)
- **iOS:** App sandbox documents directory
- **Windows:** `%APPDATA%/sight_words/`
- **macOS:** `~/Library/Application Support/sight_words/`
- **Linux:** `~/.local/share/sight_words/`
- **Web:** IndexedDB (automatic via `hive_flutter`)

No cloud sync, no user accounts, no sign-in. Data lives and dies on the device.

### New Models

```dart
// lib/models/player_profile.dart

@HiveType(typeId: 0)
class PlayerProfile extends HiveObject {
  @HiveField(0) final String name;
  @HiveField(1) final AvatarConfig avatar;
  @HiveField(2) final int currentStreak;
  @HiveField(3) final int bestStreak;
  @HiveField(4) final DateTime? lastPlayDate;
  @HiveField(5) final List<String> unlockedItems;     // avatar items + garden decorations
  @HiveField(6) final List<String> earnedStickers;    // sticker IDs
  @HiveField(7) final bool dailyChestOpened;
  @HiveField(8) final DateTime? lastChestDate;
  @HiveField(9) final int totalWordsEverCompleted;    // lifetime running count

  // Computed (not stored)
  ReadingLevel get readingLevel => ReadingLevel.forWordCount(totalMastered);
  int get totalMastered;  // pulled from ProgressService at runtime
}

@HiveType(typeId: 1)
class AvatarConfig extends HiveObject {
  @HiveField(0) final int faceShape;    // 0-2 (circle, rounded square, oval)
  @HiveField(1) final int skinTone;     // 0-5
  @HiveField(2) final int hairStyle;    // 0-7
  @HiveField(3) final int hairColor;    // 0-7 (includes unlockable)
  @HiveField(4) final int eyeStyle;     // 0-4
  @HiveField(5) final int mouthStyle;   // 0-3
  @HiveField(6) final int accessory;    // 0-8 (includes unlockable)
  @HiveField(7) final int bgColor;      // 0-7
  @HiveField(8) final bool hasSparkle;  // unlockable effect
  @HiveField(9) final bool hasRainbowSparkle;
  @HiveField(10) final bool hasGoldenGlow;

  // Default factory for first-time users
  factory AvatarConfig.defaultAvatar() => AvatarConfig(
    faceShape: 0, skinTone: 2, hairStyle: 0, hairColor: 1,
    eyeStyle: 0, mouthStyle: 0, accessory: 0, bgColor: 0,
    hasSparkle: false, hasRainbowSparkle: false, hasGoldenGlow: false,
  );
}

@HiveType(typeId: 2)
class StickerRecord extends HiveObject {
  @HiveField(0) final String stickerId;
  @HiveField(1) final DateTime dateEarned;
  @HiveField(2) final String category;  // 'milestone', 'streak', 'perfect', 'evolution'
  @HiveField(3) final bool isNew;       // true until viewed on profile screen
}

// Not a Hive object — pure enum, computed at runtime
enum ReadingLevel {
  wordSprout(0, 20, 'Word Sprout'),
  wordExplorer(21, 60, 'Word Explorer'),
  wordWizard(61, 120, 'Word Wizard'),
  wordChampion(121, 180, 'Word Champion'),
  readingSuperstar(181, 269, 'Reading Superstar');

  final int minWords;
  final int maxWords;
  final String title;
  const ReadingLevel(this.minWords, this.maxWords, this.title);

  static ReadingLevel forWordCount(int count) {
    for (final level in values.reversed) {
      if (count >= level.minWords) return level;
    }
    return wordSprout;
  }

  double progressToNext(int count) {
    if (this == readingSuperstar) return 1.0;
    final range = maxWords - minWords + 1;
    return ((count - minWords) / range).clamp(0.0, 1.0);
  }

  ReadingLevel? get next {
    final idx = index + 1;
    return idx < values.length ? values[idx] : null;
  }
}
```

### ProfileService (Hive-backed)

```dart
// lib/services/profile_service.dart

class ProfileService {
  late Box _profileBox;
  late Box<StickerRecord> _stickerBox;
  late Box _dailyBox;

  Future<void> init() async {
    _profileBox = Hive.box('profile');
    _stickerBox = Hive.box<StickerRecord>('stickers');
    _dailyBox = Hive.box('dailyRewards');
  }

  // ── Profile ────────────────────────────────────
  String get name => _profileBox.get('name', defaultValue: '');
  Future<void> setName(String name) => _profileBox.put('name', name);

  AvatarConfig get avatar =>
    _profileBox.get('avatar', defaultValue: AvatarConfig.defaultAvatar());
  Future<void> setAvatar(AvatarConfig config) => _profileBox.put('avatar', config);

  // ── Streaks ────────────────────────────────────
  int get currentStreak => _profileBox.get('currentStreak', defaultValue: 0);
  int get bestStreak => _profileBox.get('bestStreak', defaultValue: 0);
  DateTime? get lastPlayDate => _profileBox.get('lastPlayDate');

  Future<void> recordPlaySession() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastPlay = lastPlayDate;

    if (lastPlay != null) {
      final lastDay = DateTime(lastPlay.year, lastPlay.month, lastPlay.day);
      final diff = today.difference(lastDay).inDays;

      if (diff == 0) return; // Already played today
      if (diff == 1) {
        // Consecutive day
        final newStreak = currentStreak + 1;
        await _profileBox.put('currentStreak', newStreak);
        if (newStreak > bestStreak) {
          await _profileBox.put('bestStreak', newStreak);
        }
      } else {
        // Streak broken
        await _profileBox.put('currentStreak', 1);
      }
    } else {
      await _profileBox.put('currentStreak', 1);
      await _profileBox.put('bestStreak', 1);
    }

    await _profileBox.put('lastPlayDate', today);
  }

  // ── Unlocked Items ─────────────────────────────
  List<String> get unlockedItems =>
    List<String>.from(_profileBox.get('unlockedItems', defaultValue: <String>[]));
  Future<void> unlockItem(String itemId) async {
    final items = unlockedItems;
    if (!items.contains(itemId)) {
      items.add(itemId);
      await _profileBox.put('unlockedItems', items);
    }
  }

  // ── Stickers ───────────────────────────────────
  List<StickerRecord> get allStickers => _stickerBox.values.toList();
  bool hasSticker(String id) => _stickerBox.containsKey(id);
  Future<void> awardSticker(StickerRecord sticker) async {
    if (!_stickerBox.containsKey(sticker.stickerId)) {
      await _stickerBox.put(sticker.stickerId, sticker);
    }
  }

  // ── Daily Chest ────────────────────────────────
  bool get dailyChestOpened {
    final lastDate = _dailyBox.get('lastChestDate') as DateTime?;
    if (lastDate == null) return false;
    final today = DateTime.now();
    return lastDate.year == today.year &&
           lastDate.month == today.month &&
           lastDate.day == today.day;
  }
  Future<void> openDailyChest() async {
    await _dailyBox.put('lastChestDate', DateTime.now());
    await _dailyBox.put('opened', true);
  }
}
```

### New Files Required

| File | Purpose |
|------|---------|
| `lib/models/player_profile.dart` | Profile + AvatarConfig + StickerRecord + ReadingLevel models (with Hive TypeAdapters) |
| `lib/models/player_profile.g.dart` | Generated Hive adapters (via `build_runner`) |
| `lib/services/profile_service.dart` | Profile persistence via Hive boxes |
| `lib/screens/profile_screen.dart` | Main profile screen layout |
| `lib/screens/avatar_editor_screen.dart` | Avatar customization UI |
| `lib/widgets/avatar_widget.dart` | Reusable avatar rendering widget |
| `lib/widgets/bookworm_companion.dart` | Animated bookworm at each stage |
| `lib/widgets/word_garden.dart` | Garden grid visualization |
| `lib/widgets/sticker_book.dart` | Sticker collection display |
| `lib/widgets/word_constellation.dart` | "Words I Know" star map |
| `lib/widgets/daily_treasure.dart` | Treasure chest widget |
| `lib/widgets/streak_flame.dart` | Streak fire visualization |
| `lib/widgets/evolution_path.dart` | Evolution stage viewer |
| `lib/data/reading_levels.dart` | Reading level definitions |
| `lib/data/sticker_definitions.dart` | All sticker milestone data |
| `lib/data/avatar_options.dart` | Avatar customization options (colors, styles) |

### Modified Files

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `hive`, `hive_flutter`, `hive_generator`, `build_runner` |
| `lib/main.dart` | Add `Hive.initFlutter()` + register adapters before `runApp()` |
| `lib/screens/home_screen.dart` | Add profile button to bottom row, show streak flame, mini avatar |
| `lib/services/progress_service.dart` | Migrate from SharedPreferences to Hive `progress` box; add `allMasteredWords` getter |
| `lib/services/player_settings_service.dart` | Migrate name storage from SharedPreferences to Hive `profile` box (or consolidate into ProfileService) |
| `lib/app.dart` | Wire ProfileService, add profile route, Hive init |

---

## 9. Color Palette (extending existing AppColors)

```dart
// Profile-specific colors (add to app_theme.dart)

// Avatar skin tones
static const List<Color> skinTones = [
  Color(0xFFF5D6B8), // Light
  Color(0xFFE8BC98), // Light-medium
  Color(0xFFD4A57B), // Medium
  Color(0xFFC08C5A), // Medium-dark
  Color(0xFF8D5524), // Dark
  Color(0xFF5C3310), // Deep
];

// Avatar background colors
static const List<Color> avatarBgColors = [
  Color(0xFFFF9A76), // Peach
  Color(0xFF7BD4A8), // Mint
  Color(0xFF6BB8F0), // Sky
  Color(0xFFB794F6), // Lavender
  Color(0xFFFFBF69), // Honey
  Color(0xFFFF7085), // Coral
  Color(0xFF72E0ED), // Aqua
  Color(0xFFE098D0), // Mauve
];

// Garden colors
static const Color gardenSoil = Color(0xFF2A1F14);
static const Color gardenStem = Color(0xFF10B981);
static const Color gardenLeaf = Color(0xFF059669);

// Treasure chest
static const Color chestWood = Color(0xFF8B6914);
static const Color chestGold = Color(0xFFFFD700);
static const Color chestSilver = Color(0xFFC0C0C0);

// Streak flame
static const Color flameOrange = Color(0xFFFF8C42);
static const Color flameRed = Color(0xFFFF4444);
static const Color flameMagic = Color(0xFF8B5CF6);
```

---

## 10. Navigation Flow

```
Home Screen
├── [Play!] → Level Select → Game
├── [Custom Words] → Word Editor
├── [Name] → Name Setup
└── [My Garden 🌸] → Profile Screen  ← NEW
    ├── [Avatar] (long-press) → Avatar Editor
    ├── [See Evolution Path] → Evolution Path Overlay
    ├── [Treasure Chest] → Open animation (in-place)
    ├── [Garden section] → Tap flowers for word details
    ├── [Sticker Book] → Tap stickers for details
    └── [Word Constellation] → Tap words for audio
```

The profile button on the home screen shows a mini version of the child's avatar (32x32) with their reading level title below it, replacing or augmenting the current "Name" button.

---

## 11. Implementation Priority

### Phase 1: Core Profile (MVP)
1. Add `hive`, `hive_flutter` to dependencies; `hive_generator`, `build_runner` to dev_dependencies
2. `PlayerProfile` + `AvatarConfig` + `StickerRecord` data models with `@HiveType` annotations
3. Run `dart run build_runner build` to generate Hive TypeAdapters
4. `ProfileService` (Hive-backed persistence with box per data domain)
5. Migrate existing `ProgressService` + `PlayerSettingsService` from SharedPreferences to Hive
6. `Hive.initFlutter()` + adapter registration in `main.dart`
7. Basic `ProfileScreen` with hero section (name, stats, reading level)
8. Simple `AvatarWidget` (face + skin tone + eyes + mouth — no customization yet)
9. `ReadingLevel` enum with title display
10. Profile button on home screen

### Phase 2: Companion + Collection
7. `BookwormCompanion` widget (all 5 stages)
8. Evolution celebration animation
9. `WordGarden` visualization
10. `StickerBook` with milestone stickers

### Phase 3: Engagement
11. `DailyTreasure` chest mechanic
12. `StreakFlame` visualization
13. Streak tracking in `ProfileService`

### Phase 4: Customization + Polish
14. `AvatarEditor` screen (full customization)
15. Unlockable items system
16. `WordConstellation` visualization
17. All tap/long-press interactions
18. Sound effects for interactions

### Phase 5: Integration
19. Update home screen with mini avatar + streak
20. Trigger evolution celebrations from game flow
21. Award stickers from game/level completion events
22. Daily chest integration with play sessions

---

## 12. Dependencies

### New Dependencies (1 runtime + 2 dev-only)
```yaml
dependencies:
  hive: ^2.2.3              # Local key-value database (cross-platform, no native deps)
  hive_flutter: ^1.1.0      # Platform-agnostic Hive initialization

dev_dependencies:
  hive_generator: ^2.0.1    # Code-gen for Hive TypeAdapters
  build_runner: ^2.4.0      # Runs hive_generator
```

**Why Hive:**
- Pure Dart — zero platform-specific native code, works on ALL Flutter targets
- Fast — binary serialization, lazy-loaded boxes, no SQL overhead
- Structured — TypeAdapters for clean serialization of `AvatarConfig`, `StickerRecord`, etc.
- Offline-first by design — no network, no accounts, no sync
- Web support via IndexedDB adapter (automatic with `hive_flutter`)
- Battle-tested in production Flutter apps across all platforms

**SharedPreferences migration:**
The existing `shared_preferences` package can be kept temporarily for backward compatibility during migration, then removed once all data is in Hive boxes. The migration happens automatically on first launch after upgrade (read from SharedPreferences, write to Hive, delete SharedPreferences keys).

### Existing Dependencies (unchanged)
- **flutter_animate** — All animations, transitions, shimmer effects
- **confetti** — Evolution celebrations, treasure chest opening
- **google_fonts** — Fredoka + Nunito throughout
- **audioplayers** — Tap sounds, word audio playback
- **CustomPainter** — Avatar rendering, bookworm stages, constellation lines, flame effects, garden flowers
- **Flutter built-in** — GridView, ListView, Stack, AnimatedSwitcher, Hero, ClipOval

No Rive, Lottie, Flame engine, or external avatar packages needed. This keeps the dependency footprint minimal and the app lightweight.

---

## 13. Cross-Platform Guarantees

| Platform | Storage Location | Notes |
|----------|-----------------|-------|
| Android | App-internal files dir | Survives app updates, cleared on uninstall |
| iOS | App sandbox Documents | Backed up to iCloud by default |
| Windows | `%APPDATA%/sight_words/` | Persists across sessions |
| macOS | `~/Library/Application Support/` | Standard app data location |
| Linux | `~/.local/share/sight_words/` | XDG-compliant |
| Web | IndexedDB | Hive's web adapter, no localStorage limits |

**No cloud, no accounts, no sign-in, no Firebase, no backend.** All profile data (avatar, achievements, streaks, stickers, daily chest, progress) is stored locally on the device using Hive boxes. The app works completely offline on every platform Flutter supports.

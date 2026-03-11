import 'dart:math';

/// Pre-defined encouragement phrase templates with {name} placeholders.
///
/// These match the TTS script's PHRASE_TEMPLATES exactly — each phrase
/// maps to a pre-generated audio file at:
///   assets/audio/phrases/{category}_{index}.mp3
///
/// When no pre-generated audio exists, the text is shown on screen
/// and can optionally be spoken via device TTS as a fallback.
class PhraseTemplates {
  PhraseTemplates._();

  static final _rng = Random();

  // ── Word complete phrases (played randomly after spelling a word) ─────

  static const wordComplete = [
    'Great job, {name}!',
    'Way to go, {name}!',
    'Awesome, {name}!',
    'You got it, {name}!',
    'Super, {name}!',
    'Nice work, {name}!',
    'Perfect, {name}!',
    'Keep it up, {name}!',
  ];

  // ── Level complete phrases (played when finishing all words in a level) ─

  static const levelComplete = [
    'Congratulations, {name}!',
    '{name}, you\'re a superstar!',
    'Incredible, {name}! Level complete!',
    'You did it, {name}!',
    'Amazing work, {name}!',
  ];

  // ── Welcome phrases (played on app open or returning) ─────────────────

  static const welcome = [
    'Welcome, {name}!',
    'Hi, {name}! Let\'s learn!',
    'Ready to play, {name}?',
    'Let\'s go, {name}!',
  ];

  // ── All personalized categories (for TTS generation) ─────────────────

  static const Map<String, List<String>> allCategories = {
    'word_complete': wordComplete,
    'level_complete': levelComplete,
    'welcome': welcome,
  };

  // ── Zone-themed encouragement (text-only, shown on screen) ──────────
  //
  // Keys match zone names lowercased with underscores.
  // These are displayed during gameplay and at level completion to make
  // each zone feel distinct. No pre-generated audio — text only, or
  // generated on-the-fly via DeepgramTtsService when available.

  static const Map<String, List<String>> zoneEncouragement = {
    'whispering_woods': [
      'The trees are cheering for you, {name}!',
      'The forest whispers your name, {name}!',
      'Every leaf dances for you, {name}!',
      'The fireflies light up for you!',
      'The woodland creatures are proud!',
    ],
    'shimmer_shore': [
      'The waves splash with joy, {name}!',
      'You shine brighter than the sea, {name}!',
      'The dolphins are cheering!',
      'Ride the waves, {name}!',
      'The ocean sings your name!',
    ],
    'crystal_peaks': [
      'Your words echo through the crystals, {name}!',
      'The mountain glows for you, {name}!',
      'Sparkle like a snowflake!',
      'The crystals shimmer with pride!',
      'You reached new heights, {name}!',
    ],
    'skyward_kingdom': [
      'The clouds carry your voice, {name}!',
      'You soar higher than the birds, {name}!',
      'The castle bells ring for you!',
      'The sky is yours, {name}!',
      'Thunder and lightning, {name}!',
    ],
    'celestial_crown': [
      'The stars shine for you, {name}!',
      'You are a constellation, {name}!',
      'The galaxy celebrates you!',
      'Cosmic power, {name}!',
      'You light up the universe!',
    ],
  };

  // ── Zone-themed streak messages (text-only, shown as brief indicators) ─

  static const Map<String, List<String>> zoneStreakMessages = {
    'whispering_woods': ['Forest Fire!', 'Wild Run!', 'Nature Power!'],
    'shimmer_shore': ['Tidal Wave!', 'Making Waves!', 'Splash Streak!'],
    'crystal_peaks': ['Crystal Clear!', 'Peak Power!', 'Ice Storm!'],
    'skyward_kingdom': ['Sky High!', 'Cloud Burst!', 'Royal Streak!'],
    'celestial_crown': ['Supernova!', 'Star Streak!', 'Cosmic Blaze!'],
  };

  // ── Zone-themed level complete messages (text-only) ────────────────

  static const Map<String, List<String>> zoneLevelComplete = {
    'whispering_woods': [
      'The forest bows to you, {name}!',
      'You conquered the woods, {name}!',
      'The trees remember your name!',
    ],
    'shimmer_shore': [
      'You sailed across the shore, {name}!',
      'The ocean applauds you, {name}!',
      'A wave of victory for {name}!',
    ],
    'crystal_peaks': [
      'You reached the summit, {name}!',
      'The crystals glow in your honor!',
      'Mountain master, {name}!',
    ],
    'skyward_kingdom': [
      'The kingdom celebrates, {name}!',
      'You rule the skies, {name}!',
      'A royal victory for {name}!',
    ],
    'celestial_crown': [
      'You earned the crown, {name}!',
      'The stars bow to you, {name}!',
      'Cosmic champion, {name}!',
    ],
  };

  /// Get a zone-themed level complete phrase.
  /// Falls back to generic level complete if zone key not found.
  static String randomZoneLevelComplete(String zoneKey, String name) {
    final phrases = zoneLevelComplete[zoneKey];
    if (phrases == null || phrases.isEmpty) return randomLevelComplete(name);
    final template = phrases[_rng.nextInt(phrases.length)];
    return template.replaceAll('{name}', name);
  }

  /// Get a random zone-themed encouragement phrase.
  /// Falls back to generic if zone key not found.
  static String randomZoneEncouragement(String zoneKey, String name) {
    final phrases = zoneEncouragement[zoneKey];
    if (phrases == null || phrases.isEmpty) return randomWordComplete(name);
    final template = phrases[_rng.nextInt(phrases.length)];
    return template.replaceAll('{name}', name);
  }

  /// Get a zone-themed streak message.
  static String randomZoneStreakMessage(String zoneKey) {
    final messages = zoneStreakMessages[zoneKey];
    if (messages == null || messages.isEmpty) return 'Streak!';
    return messages[_rng.nextInt(messages.length)];
  }

  /// Convert a zone name to the key used in the maps above.
  static String zoneKey(String zoneName) {
    return zoneName.toLowerCase().replaceAll(' ', '_');
  }

  // ── Generic fallback praises (no name, used if name not set) ──────────

  static const genericPraises = [
    'Great job!',
    'Awesome!',
    'You got it!',
    'Super!',
    'Wow!',
    'Perfect!',
    'Nice work!',
  ];

  /// Get a random phrase from a category, filled with the player's name.
  /// If [name] is empty, returns a generic praise instead.
  static String randomWordComplete(String name) {
    if (name.isEmpty) return genericPraises[_rng.nextInt(genericPraises.length)];
    final template = wordComplete[_rng.nextInt(wordComplete.length)];
    return template.replaceAll('{name}', name);
  }

  static String randomLevelComplete(String name) {
    if (name.isEmpty) return 'Level Complete!';
    final template = levelComplete[_rng.nextInt(levelComplete.length)];
    return template.replaceAll('{name}', name);
  }

  static String randomWelcome(String name) {
    if (name.isEmpty) return 'Welcome!';
    final template = welcome[_rng.nextInt(welcome.length)];
    return template.replaceAll('{name}', name);
  }

  /// Get the audio asset path for a specific phrase.
  /// Returns the path like 'audio/phrases/word_complete_3.mp3'.
  static String? audioPath(String category, int index) {
    return 'audio/phrases/${category}_$index.mp3';
  }

  /// Get a random phrase index + its audio path for a category.
  static ({int index, String text, String audioPath}) randomWithAudio(
    String category,
    String name,
  ) {
    final List<String> templates;
    switch (category) {
      case 'word_complete':
        templates = wordComplete;
      case 'level_complete':
        templates = levelComplete;
      case 'welcome':
        templates = welcome;
      default:
        templates = genericPraises;
    }

    final index = _rng.nextInt(templates.length);
    final text = templates[index].replaceAll('{name}', name);
    final path = 'audio/phrases/${category}_$index.mp3';

    return (index: index, text: text, audioPath: path);
  }
}

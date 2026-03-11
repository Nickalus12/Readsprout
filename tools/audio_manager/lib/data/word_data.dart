// All word data for Reading Sprout audio generation.
// Mirrors the main app's dolch_words.dart, bonus_words.dart, and
// generate_tts_deepgram.py word lists.

class WordData {
  WordData._();

  // ── 220 Dolch Sight Words (22 levels x 10 words) ──────────────────────

  static const List<List<String>> dolchWordsByLevel = [
    // Level 1 — Pre-Primer (easiest)
    ['a', 'I', 'it', 'is', 'in', 'my', 'me', 'we', 'go', 'to'],
    // Level 2
    ['up', 'no', 'on', 'do', 'he', 'at', 'an', 'am', 'so', 'be'],
    // Level 3
    ['the', 'and', 'see', 'you', 'can', 'not', 'run', 'big', 'red', 'one'],
    // Level 4
    ['for', 'was', 'are', 'but', 'had', 'has', 'his', 'her', 'him', 'how'],
    // Level 5
    ['did', 'get', 'may', 'new', 'now', 'old', 'our', 'out', 'ran', 'say'],
    // Level 6 — Primer
    ['she', 'too', 'all', 'ate', 'came', 'like', 'will', 'yes', 'said', 'good'],
    // Level 7
    ['that', 'they', 'this', 'what', 'with', 'have', 'into', 'want', 'well', 'went'],
    // Level 8
    ['look', 'make', 'play', 'ride', 'must', 'stop', 'help', 'jump', 'find', 'from'],
    // Level 9
    ['come', 'give', 'just', 'know', 'let', 'live', 'over', 'take', 'tell', 'them'],
    // Level 10
    ['then', 'were', 'when', 'here', 'soon', 'open', 'upon', 'once', 'some', 'very'],
    // Level 11 — First Grade
    ['ask', 'any', 'fly', 'try', 'put', 'cut', 'hot', 'got', 'ten', 'sit'],
    // Level 12
    ['after', 'again', 'every', 'going', 'could', 'would', 'think', 'thank', 'round', 'sleep'],
    // Level 13
    ['walk', 'work', 'wash', 'wish', 'which', 'white', 'where', 'there', 'these', 'those'],
    // Level 14
    ['under', 'about', 'never', 'seven', 'eight', 'green', 'brown', 'black', 'clean', 'small'],
    // Level 15
    ['away', 'best', 'both', 'call', 'cold', 'does', 'done', 'draw', 'fall', 'fast'],
    // Level 16 — Second Grade
    ['been', 'read', 'made', 'gave', 'many', 'only', 'pull', 'full', 'keep', 'kind'],
    // Level 17
    ['long', 'much', 'pick', 'show', 'sing', 'warm', 'hold', 'hurt', 'far', 'own'],
    // Level 18
    ['carry', 'today', 'start', 'shall', 'laugh', 'light', 'right', 'write', 'first', 'found'],
    // Level 19
    ['bring', 'drink', 'funny', 'happy', 'their', 'your', 'four', 'five', 'six', 'two'],
    // Level 20 — Third Grade
    ['always', 'around', 'before', 'better', 'please', 'pretty', 'because', 'myself', 'goes', 'together'],
    // Level 21
    ['buy', 'use', 'off', 'its', 'why', 'grow', 'if', 'or', 'as', 'by'],
    // Level 22
    ['three', 'blue', 'eat', 'saw', 'down', 'little', 'who', 'yellow', 'us', 'of'],
  ];

  // ── Bonus Words ────────────────────────────────────────────────────────

  static const Map<String, List<String>> bonusWordsByCategory = {
    'Family': ['mom', 'dad', 'baby', 'love', 'family'],
    'Animals': ['dog', 'cat', 'fish', 'bird', 'bear', 'frog'],
    'Home & Play': ['home', 'food', 'book', 'ball', 'game', 'toy'],
    'My Body': ['hand', 'head', 'eyes', 'feet'],
    'Nature': ['sun', 'moon', 'star', 'tree', 'rain', 'snow'],
    'School': ['school', 'teacher', 'friend', 'learn'],
    'More Colors': ['pink', 'purple', 'orange'],
    'More Numbers': ['nine', 'zero'],
    'Feelings': ['nice', 'hard', 'soft', 'dark', 'tall', 'loud', 'quiet'],
  };

  // ── Letter Names ───────────────────────────────────────────────────────

  static const Map<String, String> letterNames = {
    'a': 'ay', 'b': 'bee', 'c': 'see', 'd': 'dee', 'e': 'ee',
    'f': 'eff', 'g': 'jee', 'h': 'aitch', 'i': 'eye', 'j': 'jay',
    'k': 'kay', 'l': 'ell', 'm': 'em', 'n': 'en', 'o': 'oh',
    'p': 'pee', 'q': 'cue', 'r': 'ar', 's': 'ess', 't': 'tee',
    'u': 'you', 'v': 'vee', 'w': 'double-you', 'x': 'ex',
    'y': 'why', 'z': 'zee',
  };

  // ── Phonics ────────────────────────────────────────────────────────────

  static const Map<String, String> letterPhonics = {
    'a': 'ah', 'b': 'buh', 'c': 'kuh', 'd': 'duh', 'e': 'eh',
    'f': 'fuh', 'g': 'guh', 'h': 'huh', 'i': 'ih', 'j': 'juh',
    'k': 'kuh', 'l': 'luh', 'm': 'muh', 'n': 'nuh', 'o': 'oh',
    'p': 'puh', 'q': 'kwuh', 'r': 'ruh', 's': 'sss', 't': 'tuh',
    'u': 'uh', 'v': 'vvv', 'w': 'wuh', 'x': 'ks', 'y': 'yuh',
    'z': 'zzz',
  };

  // ── Phrase Templates ───────────────────────────────────────────────────

  static const Map<String, List<String>> phraseTemplates = {
    'word_complete': [
      'Great job, {name}!',
      'Way to go, {name}!',
      'Awesome, {name}!',
      'You got it, {name}!',
      'Super, {name}!',
      'Nice work, {name}!',
      'Perfect, {name}!',
      'Keep it up, {name}!',
    ],
    'level_complete': [
      'Congratulations, {name}!',
      '{name}, you\'re a superstar!',
      'Incredible, {name}! Level complete!',
      'You did it, {name}!',
      'Amazing work, {name}!',
    ],
    'welcome': [
      'Welcome, {name}!',
      'Hi, {name}! Let\'s learn!',
      'Ready to play, {name}?',
      'Let\'s go, {name}!',
    ],
  };

  // ── Generic Welcomes ───────────────────────────────────────────────────

  static const Map<String, String> genericWelcomes = {
    'welcome_generic_1': 'Welcome!',
    'welcome_generic_2': 'Hi there!',
    'welcome_generic_3': 'Ready to learn?',
    'welcome_generic_4': 'Let\'s get started!',
    'welcome_generic_5': 'Time to learn!',
    'welcome_generic_6': 'Here we go!',
    'welcome_generic_7': 'Let\'s have fun!',
    'welcome_generic_8': 'You\'re going to do great!',
    'welcome_generic_9': 'Learning time!',
    'welcome_generic_10': 'Let\'s do this!',
    'welcome_generic_11': 'Good to see you!',
    'welcome_generic_12': 'Let\'s read some words!',
    'welcome_generic_13': 'Are you ready?',
  };

  // ── Sticker Audio ──────────────────────────────────────────────────────

  static Map<String, String> get stickerAudio {
    final map = <String, String>{};
    // Level completion (22 levels)
    for (int i = 1; i <= 22; i++) {
      map['level_$i'] = 'Level $i';
    }
    // Milestones
    map.addAll({
      'first_word': 'First Word',
      'ten_words': 'Ten Words',
      'twenty_five_words': 'Twenty-Five Words',
      'fifty_words': 'Fifty Words',
      'one_hundred_words': 'One Hundred Words',
      'one_hundred_fifty_words': 'One Hundred Fifty Words',
      'two_hundred_words': 'Two Hundred Words',
      'all_words': 'All Words',
      'three_day_streak': 'Three Day Streak',
      'seven_day_streak': 'Seven Day Streak',
      'fourteen_day_streak': 'Fourteen Day Streak',
      'thirty_day_streak': 'Thirty Day Streak',
      'perfect_level': 'Perfect Level',
      'word_sprout': 'Word Sprout',
      'word_explorer': 'Word Explorer',
      'word_wizard': 'Word Wizard',
      'word_champion': 'Word Champion',
      'reading_superstar': 'Reading Superstar',
      'speed_reader': 'Speed Reader',
      'first_flight': 'First Flight',
      'unicorn_rider': 'Unicorn Rider',
      'sky_champion': 'Sky Champion',
      'storm_speller': 'Storm Speller',
      'lightning_fast': 'Lightning Fast',
      'thunder_brain': 'Thunder Brain',
      'bubble_popper': 'Bubble Popper',
      'bubble_master': 'Bubble Master',
      'memory_maker': 'Memory Maker',
      'sharp_memory': 'Sharp Memory',
      'perfect_recall': 'Perfect Recall',
      'letter_catcher': 'Letter Catcher',
      'falling_star': 'Falling Star',
      'cat_tosser': 'Cat Tosser',
      'purrfect_aim': 'Purrfect Aim',
      'cat_champion': 'Cat Champion',
      'letter_dropper': 'Letter Dropper',
      'drop_expert': 'Drop Expert',
      'rhyme_rookie': 'Rhyme Rookie',
      'rhyme_master': 'Rhyme Master',
      'super_poet': 'Super Poet',
    });
    return map;
  }

  // ── Extra words ────────────────────────────────────────────────────────

  static const List<String> extraWords = ['alphabet'];

  // ── Effects ────────────────────────────────────────────────────────────

  static const Map<String, String> effects = {
    'success': 'Yay!',
    'error': 'Oops!',
    'level_complete': 'Level complete!',
  };

  // ── Computed lists ─────────────────────────────────────────────────────

  static List<String> get allDolchWords {
    final words = <String>{};
    for (final level in dolchWordsByLevel) {
      for (final w in level) {
        words.add(w.toLowerCase());
      }
    }
    final sorted = words.toList()..sort();
    return sorted;
  }

  static List<String> get allBonusWords {
    final dolch = allDolchWords.toSet();
    final bonus = <String>{};
    for (final words in bonusWordsByCategory.values) {
      for (final w in words) {
        if (!dolch.contains(w.toLowerCase())) {
          bonus.add(w.toLowerCase());
        }
      }
    }
    final sorted = bonus.toList()..sort();
    return sorted;
  }

  static List<String> get allWords {
    final words = <String>{};
    words.addAll(allDolchWords);
    words.addAll(allBonusWords);
    final sorted = words.toList()..sort();
    return sorted;
  }
}

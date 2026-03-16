/// Validates and formats player names for the name setup and profile creation flows.
class NameValidator {
  NameValidator._();

  static const int minLength = 2;
  static const int maxLength = 15;
  static const int maxConsecutiveRepeat = 3;
  static const int maxConsonantCluster = 4;

  static const _vowels = {'a', 'e', 'i', 'o', 'u'};

  static final _lettersOnly = RegExp(r'^[a-zA-Z]+$');

  /// Common profane words to reject (case-insensitive substring match).
  static const _blockedWords = <String>{
    'ass',
    'bastard',
    'bitch',
    'boob',
    'cock',
    'crap',
    'cunt',
    'damn',
    'dick',
    'dildo',
    'douche',
    'fag',
    'fuck',
    'hell',
    'hoe',
    'homo',
    'jerk',
    'nigga',
    'nigger',
    'penis',
    'piss',
    'porn',
    'prick',
    'pussy',
    'rape',
    'sex',
    'shit',
    'slut',
    'tit',
    'twat',
    'vagina',
    'whore',
  };

  /// Returns null if the name is valid, or a friendly error message if invalid.
  static String? validate(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      return 'Please enter a name!';
    }

    if (trimmed.length < minLength) {
      return 'Names need at least $minLength letters!';
    }

    if (trimmed.length > maxLength) {
      return 'Names can be up to $maxLength letters!';
    }

    if (!_lettersOnly.hasMatch(trimmed)) {
      return 'Only letters allowed!';
    }

    final lower = trimmed.toLowerCase();

    // Must contain at least one vowel
    if (!lower.split('').any((c) => _vowels.contains(c))) {
      return "Hmm, that doesn't look like a name. Try again!";
    }

    // No more than maxConsecutiveRepeat of the same letter in a row
    for (int i = 0; i <= lower.length - (maxConsecutiveRepeat + 1); i++) {
      final ch = lower[i];
      bool allSame = true;
      for (int j = 1; j <= maxConsecutiveRepeat; j++) {
        if (lower[i + j] != ch) {
          allSame = false;
          break;
        }
      }
      if (allSame) {
        return "Hmm, that doesn't look like a name. Try again!";
      }
    }

    // No more than maxConsonantCluster consecutive consonants
    int consonantRun = 0;
    for (final ch in lower.split('')) {
      if (_vowels.contains(ch)) {
        consonantRun = 0;
      } else {
        consonantRun++;
        if (consonantRun > maxConsonantCluster) {
          return "Hmm, that doesn't look like a name. Try again!";
        }
      }
    }

    // Profanity check (substring match)
    for (final word in _blockedWords) {
      if (lower.contains(word)) {
        return "That name isn't allowed. Try a different one!";
      }
    }

    return null; // valid
  }

  /// Capitalize first letter, lowercase the rest.
  static String formatName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }
}

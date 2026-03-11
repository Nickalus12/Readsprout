// Deepgram Aura-2 voice definitions.

class Voice {
  final String id;
  final String name;
  final String description;
  final String gender;

  const Voice({
    required this.id,
    required this.name,
    required this.description,
    required this.gender,
  });

  @override
  String toString() => '$name ($id)';
}

class Voices {
  Voices._();

  static const defaultVoice = 'aura-2-cordelia-en';

  static const List<Voice> all = [
    Voice(
      id: 'aura-2-cordelia-en',
      name: 'Cordelia',
      description: 'Young, Warm, Polite — Best for kids',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-cora-en',
      name: 'Cora',
      description: 'Smooth, Melodic, Caring — Storytelling',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-aurora-en',
      name: 'Aurora',
      description: 'Cheerful, Expressive, Energetic',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-apollo-en',
      name: 'Apollo',
      description: 'Confident, Comfortable, Casual',
      gender: 'Male',
    ),
    Voice(
      id: 'aura-2-draco-en',
      name: 'Draco',
      description: 'Warm, Approachable, British',
      gender: 'Male',
    ),
    Voice(
      id: 'aura-2-aries-en',
      name: 'Aries',
      description: 'Warm, Energetic, Caring — Encouragement',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-delia-en',
      name: 'Delia',
      description: 'Casual, Friendly, Cheerful',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-asteria-en',
      name: 'Asteria',
      description: 'Neutral, Clear, Balanced',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-athena-en',
      name: 'Athena',
      description: 'Calm, Smooth — Level narration',
      gender: 'Female',
    ),
    Voice(
      id: 'aura-2-thalia-en',
      name: 'Thalia',
      description: 'Clear, Confident, Energetic',
      gender: 'Female',
    ),
  ];

  static Voice findById(String id) {
    return all.firstWhere(
      (v) => v.id == id,
      orElse: () => all.first,
    );
  }
}

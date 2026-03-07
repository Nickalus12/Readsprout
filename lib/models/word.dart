class Word {
  final String id;
  final String text;
  final int level; // 1-based level number
  final bool isCustom;

  const Word({
    required this.id,
    required this.text,
    required this.level,
    this.isCustom = false,
  });

  /// Audio asset path for the full word pronunciation
  String get wordAudioPath => 'assets/audio/words/${text.toLowerCase()}.mp3';

  /// Audio asset path for a specific letter's name
  String letterAudioPath(String letter) =>
      'assets/audio/letter_names/${letter.toLowerCase()}.mp3';

  /// Audio asset path for a specific letter's phonetic sound
  String letterPhonicsPath(String letter) =>
      'assets/audio/phonics/${letter.toLowerCase()}.mp3';

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'level': level,
        'isCustom': isCustom,
      };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        id: json['id'] as String,
        text: json['text'] as String,
        level: json['level'] as int,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

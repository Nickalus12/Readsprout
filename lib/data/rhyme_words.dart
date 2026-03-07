/// Rhyming word families for the Rhyming Game mini game.
///
/// 30 easy, kid-friendly rhyming words organized into 8 families.
/// All words are simple CVC or short words appropriate for ages 4-7.
/// None of these words overlap with Dolch or Bonus word lists.
class RhymeFamily {
  final String familyName;
  final List<String> words;

  const RhymeFamily(this.familyName, this.words);
}

const List<RhymeFamily> rhymeFamilies = [
  // -at family
  RhymeFamily('-at', ['hat', 'bat', 'mat', 'rat']),
  // -an family
  RhymeFamily('-an', ['fan', 'pan', 'van', 'man']),
  // -ig family
  RhymeFamily('-ig', ['pig', 'wig', 'dig', 'jig']),
  // -op family
  RhymeFamily('-op', ['hop', 'mop', 'pop', 'top']),
  // -ug family
  RhymeFamily('-ug', ['bug', 'hug', 'mug', 'rug']),
  // -en family
  RhymeFamily('-en', ['hen', 'pen', 'den']),
  // -ip family
  RhymeFamily('-ip', ['hip', 'tip', 'dip', 'zip']),
  // -et family
  RhymeFamily('-et', ['net', 'pet', 'wet']),
];

/// Flat list of all rhyming words.
final List<String> allRhymeWords =
    rhymeFamilies.expand((f) => f.words).toList();

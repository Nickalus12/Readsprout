/// Emoji hints and simple sentences for sight words.
///
/// Each word maps to a [WordContext] containing 1-2 emoji and a short,
/// kid-friendly sentence using the word in context.
class WordContext {
  final String emoji;
  final String sentence;

  const WordContext(this.emoji, this.sentence);
}

/// Lookup table for all 220 Dolch words + 49 bonus words.
///
/// Keys are lowercase. Use [getContext] for safe lookup.
const Map<String, WordContext> _wordContexts = {
  // ── Level 1: Pre-Primer ─────────────────────────────────────
  'a': WordContext('1️⃣', 'I see a cat!'),
  'i': WordContext('🙋', 'I am happy!'),
  'it': WordContext('👉', 'Look at it!'),
  'is': WordContext('✅', 'She is nice.'),
  'in': WordContext('📦', 'The toy is in the box.'),
  'my': WordContext('💖', 'This is my book.'),
  'me': WordContext('🙋', 'Give it to me!'),
  'we': WordContext('👫', 'We play together.'),
  'go': WordContext('🚀', 'Let\'s go outside!'),
  'to': WordContext('➡️', 'Walk to the park.'),

  // ── Level 2 ─────────────────────────────────────────────────
  'up': WordContext('⬆️', 'Jump up high!'),
  'no': WordContext('🚫', 'No, thank you.'),
  'on': WordContext('💡', 'Turn on the light.'),
  'do': WordContext('💪', 'I can do it!'),
  'he': WordContext('👦', 'He is my friend.'),
  'at': WordContext('📍', 'I am at school.'),
  'an': WordContext('🍎', 'I ate an apple.'),
  'am': WordContext('😊', 'I am so happy!'),
  'so': WordContext('🌟', 'You are so smart!'),
  'be': WordContext('🌈', 'I want to be kind.'),

  // ── Level 3 ─────────────────────────────────────────────────
  'the': WordContext('👆', 'Look at the sky!'),
  'and': WordContext('🤝', 'You and me.'),
  'see': WordContext('👀', 'I can see you!'),
  'you': WordContext('🫵', 'I like you!'),
  'can': WordContext('💪', 'I can do it!'),
  'not': WordContext('🙅', 'I am not scared.'),
  'run': WordContext('🏃', 'I like to run fast!'),
  'big': WordContext('🐘', 'The elephant is big!'),
  'red': WordContext('🔴', 'I have a red ball.'),
  'one': WordContext('1️⃣', 'I have one cookie.'),

  // ── Level 4 ─────────────────────────────────────────────────
  'for': WordContext('🎁', 'This gift is for you!'),
  'was': WordContext('🕐', 'It was a fun day.'),
  'are': WordContext('👨‍👩‍👧‍👦', 'We are a family.'),
  'but': WordContext('🤔', 'I like it, but it\'s big.'),
  'had': WordContext('🧸', 'She had a teddy bear.'),
  'has': WordContext('🎈', 'He has a balloon.'),
  'his': WordContext('👦', 'That is his toy.'),
  'her': WordContext('👧', 'That is her book.'),
  'him': WordContext('👦', 'I gave it to him.'),
  'how': WordContext('❓', 'How are you?'),

  // ── Level 5 ─────────────────────────────────────────────────
  'did': WordContext('✅', 'I did my homework!'),
  'get': WordContext('🎁', 'I will get a prize!'),
  'may': WordContext('🙏', 'May I have a cookie?'),
  'new': WordContext('✨', 'I got new shoes!'),
  'now': WordContext('⏰', 'Let\'s go now!'),
  'old': WordContext('👴', 'The tree is very old.'),
  'our': WordContext('🏠', 'This is our home.'),
  'out': WordContext('🚪', 'Let\'s go out and play!'),
  'ran': WordContext('🏃', 'She ran so fast!'),
  'say': WordContext('🗣️', 'What did you say?'),

  // ── Level 6: Primer ─────────────────────────────────────────
  'she': WordContext('👩', 'She is my mom.'),
  'too': WordContext('✌️', 'I want to come too!'),
  'all': WordContext('🌎', 'We are all friends.'),
  'ate': WordContext('🍽️', 'I ate my lunch.'),
  'came': WordContext('🚶', 'She came to my house.'),
  'like': WordContext('❤️', 'I like ice cream!'),
  'will': WordContext('🔮', 'I will try my best!'),
  'yes': WordContext('👍', 'Yes, I can do it!'),
  'said': WordContext('💬', 'She said hello!'),
  'good': WordContext('⭐', 'You did a good job!'),

  // ── Level 7 ─────────────────────────────────────────────────
  'that': WordContext('👉', 'I want that one.'),
  'they': WordContext('👫', 'They are playing.'),
  'this': WordContext('👈', 'I love this song!'),
  'what': WordContext('❓', 'What is your name?'),
  'with': WordContext('🤝', 'Come with me!'),
  'have': WordContext('🎒', 'I have a backpack.'),
  'into': WordContext('🏊', 'Jump into the water!'),
  'want': WordContext('🌟', 'I want to learn!'),
  'well': WordContext('👏', 'You did well!'),
  'went': WordContext('🚶', 'We went to the park.'),

  // ── Level 8 ─────────────────────────────────────────────────
  'look': WordContext('👀', 'Look at the rainbow!'),
  'make': WordContext('🎨', 'Let\'s make a picture!'),
  'play': WordContext('⚽', 'Let\'s play a game!'),
  'ride': WordContext('🚲', 'I like to ride my bike.'),
  'must': WordContext('📝', 'I must finish my work.'),
  'stop': WordContext('🛑', 'Stop and look both ways.'),
  'help': WordContext('🤲', 'Can you help me?'),
  'jump': WordContext('🦘', 'Jump up and down!'),
  'find': WordContext('🔍', 'Can you find it?'),
  'from': WordContext('📬', 'A letter from Grandma!'),

  // ── Level 9 ─────────────────────────────────────────────────
  'come': WordContext('🏠', 'Come to my house!'),
  'give': WordContext('🎁', 'I will give you a hug.'),
  'just': WordContext('☝️', 'I just got here.'),
  'know': WordContext('🧠', 'I know the answer!'),
  'let': WordContext('🙏', 'Let me try!'),
  'live': WordContext('🏡', 'I live in a house.'),
  'over': WordContext('🌉', 'Jump over the puddle!'),
  'take': WordContext('✋', 'Take my hand.'),
  'tell': WordContext('🗣️', 'Tell me a story!'),
  'them': WordContext('👥', 'I gave them a snack.'),

  // ── Level 10 ────────────────────────────────────────────────
  'then': WordContext('➡️', 'First eat, then play.'),
  'were': WordContext('🏫', 'They were at school.'),
  'when': WordContext('🕐', 'When is my birthday?'),
  'here': WordContext('📍', 'Come over here!'),
  'soon': WordContext('⏳', 'We will be there soon!'),
  'open': WordContext('📖', 'Open your book.'),
  'upon': WordContext('📚', 'Once upon a time...'),
  'once': WordContext('1️⃣', 'I went there once.'),
  'some': WordContext('🍪', 'Can I have some cookies?'),
  'very': WordContext('🌟', 'You are very brave!'),

  // ── Level 11: First Grade ───────────────────────────────────
  'ask': WordContext('🙋', 'I will ask my teacher.'),
  'any': WordContext('🤷', 'Do you have any pets?'),
  'fly': WordContext('🦋', 'Birds can fly!'),
  'try': WordContext('💪', 'I will try again!'),
  'put': WordContext('📦', 'Put it on the shelf.'),
  'cut': WordContext('✂️', 'Cut along the line.'),
  'hot': WordContext('🔥', 'The soup is hot!'),
  'got': WordContext('🎉', 'I got a gold star!'),
  'ten': WordContext('🔟', 'I can count to ten!'),
  'sit': WordContext('🪑', 'Please sit down.'),

  // ── Level 12 ────────────────────────────────────────────────
  'after': WordContext('🕐', 'We play after school.'),
  'again': WordContext('🔄', 'Let\'s do it again!'),
  'every': WordContext('📅', 'I read every day.'),
  'going': WordContext('🚶', 'I am going to school.'),
  'could': WordContext('💭', 'I wish I could fly!'),
  'would': WordContext('🤔', 'I would like some milk.'),
  'think': WordContext('🧠', 'I think you are right!'),
  'thank': WordContext('🙏', 'Thank you so much!'),
  'round': WordContext('⭕', 'The ball is round.'),
  'sleep': WordContext('😴', 'Time to sleep. Goodnight!'),

  // ── Level 13 ────────────────────────────────────────────────
  'walk': WordContext('🚶', 'Let\'s walk to the park.'),
  'work': WordContext('📝', 'I will work hard.'),
  'wash': WordContext('🧼', 'Wash your hands!'),
  'wish': WordContext('🌠', 'I wish upon a star.'),
  'which': WordContext('🤔', 'Which one do you want?'),
  'white': WordContext('⬜', 'Snow is white.'),
  'where': WordContext('🗺️', 'Where are you going?'),
  'there': WordContext('👉', 'Look over there!'),
  'these': WordContext('👈', 'I like these colors.'),
  'those': WordContext('👉', 'Who made those cookies?'),

  // ── Level 14 ────────────────────────────────────────────────
  'under': WordContext('⬇️', 'The cat is under the bed.'),
  'about': WordContext('📖', 'Tell me about your day.'),
  'never': WordContext('🙅', 'I never give up!'),
  'seven': WordContext('7️⃣', 'I am seven years old.'),
  'eight': WordContext('8️⃣', 'There are eight crayons.'),
  'green': WordContext('🟢', 'Grass is green.'),
  'brown': WordContext('🟤', 'The dog is brown.'),
  'black': WordContext('⬛', 'I have a black cat.'),
  'clean': WordContext('🧹', 'My room is clean!'),
  'small': WordContext('🐁', 'The mouse is small.'),

  // ── Level 15 ────────────────────────────────────────────────
  'away': WordContext('👋', 'She ran far away.'),
  'best': WordContext('🏆', 'You are the best!'),
  'both': WordContext('✌️', 'I want both!'),
  'call': WordContext('📞', 'I will call my friend.'),
  'cold': WordContext('🥶', 'It is cold outside!'),
  'does': WordContext('🤔', 'What does it mean?'),
  'done': WordContext('✅', 'I am all done!'),
  'draw': WordContext('🖍️', 'I love to draw pictures.'),
  'fall': WordContext('🍂', 'Leaves fall in autumn.'),
  'fast': WordContext('⚡', 'The car goes fast!'),

  // ── Level 16: Second Grade ──────────────────────────────────
  'been': WordContext('✈️', 'I have been on a plane!'),
  'read': WordContext('📚', 'I love to read books!'),
  'made': WordContext('🎂', 'Mom made a cake.'),
  'gave': WordContext('🎁', 'I gave her a gift.'),
  'many': WordContext('🌟', 'So many stars in the sky!'),
  'only': WordContext('☝️', 'I have only one pet.'),
  'pull': WordContext('🚪', 'Pull the door open.'),
  'full': WordContext('🥤', 'My cup is full!'),
  'keep': WordContext('🧸', 'I will keep my promise.'),
  'kind': WordContext('💛', 'Always be kind.'),

  // ── Level 17 ────────────────────────────────────────────────
  'long': WordContext('📏', 'The snake is long.'),
  'much': WordContext('❤️', 'I love you so much!'),
  'pick': WordContext('🌸', 'Pick a pretty flower.'),
  'show': WordContext('📺', 'Show me your drawing!'),
  'sing': WordContext('🎵', 'I love to sing songs!'),
  'warm': WordContext('☀️', 'The sun feels warm.'),
  'hold': WordContext('🤲', 'Hold my hand.'),
  'hurt': WordContext('🩹', 'I hope it doesn\'t hurt.'),
  'far': WordContext('🏔️', 'The mountain is far away.'),
  'own': WordContext('🧸', 'I have my own room!'),

  // ── Level 18 ────────────────────────────────────────────────
  'carry': WordContext('🎒', 'I can carry my bag.'),
  'today': WordContext('📅', 'Today is a great day!'),
  'start': WordContext('🏁', 'Ready, set, start!'),
  'shall': WordContext('🤝', 'Shall we dance?'),
  'laugh': WordContext('😂', 'You make me laugh!'),
  'light': WordContext('💡', 'Turn on the light.'),
  'right': WordContext('✅', 'You got it right!'),
  'write': WordContext('✏️', 'I will write my name.'),
  'first': WordContext('🥇', 'I finished first!'),
  'found': WordContext('🔍', 'I found a treasure!'),

  // ── Level 19 ────────────────────────────────────────────────
  'bring': WordContext('🎒', 'Bring your lunch to school.'),
  'drink': WordContext('🥤', 'I want to drink water.'),
  'funny': WordContext('😄', 'That joke is so funny!'),
  'happy': WordContext('😊', 'I am so happy today!'),
  'their': WordContext('👨‍👩‍👧‍👦', 'That is their house.'),
  'your': WordContext('🫵', 'What is your name?'),
  'four': WordContext('4️⃣', 'I have four toys.'),
  'five': WordContext('5️⃣', 'Give me a high five!'),
  'six': WordContext('6️⃣', 'I have six crayons.'),
  'two': WordContext('2️⃣', 'I have two hands.'),

  // ── Level 20: Third Grade ───────────────────────────────────
  'always': WordContext('💛', 'I will always love you.'),
  'around': WordContext('🔄', 'Look around the room.'),
  'before': WordContext('⏰', 'Wash hands before eating.'),
  'better': WordContext('📈', 'I am getting better!'),
  'please': WordContext('🙏', 'Please and thank you!'),
  'pretty': WordContext('🌺', 'What a pretty flower!'),
  'because': WordContext('💡', 'I smile because I\'m happy.'),
  'myself': WordContext('🙋', 'I did it all by myself!'),
  'goes': WordContext('🚶', 'She goes to school.'),
  'together': WordContext('🤝', 'We play together!'),

  // ── Level 21 ────────────────────────────────────────────────
  'buy': WordContext('🛒', 'Let\'s buy some apples.'),
  'use': WordContext('✏️', 'I can use a pencil.'),
  'off': WordContext('💡', 'Turn off the light.'),
  'its': WordContext('🐶', 'The dog wagged its tail.'),
  'why': WordContext('❓', 'Why is the sky blue?'),
  'grow': WordContext('🌱', 'Watch the plant grow!'),
  'if': WordContext('🤔', 'What if I could fly?'),
  'or': WordContext('🤷', 'Do you want red or blue?'),
  'as': WordContext('🦁', 'Brave as a lion!'),
  'by': WordContext('🏠', 'I walked by the house.'),

  // ── Level 22 ────────────────────────────────────────────────
  'three': WordContext('3️⃣', 'I have three pets.'),
  'blue': WordContext('🔵', 'The sky is blue.'),
  'eat': WordContext('🍽️', 'Time to eat dinner!'),
  'saw': WordContext('👀', 'I saw a rainbow!'),
  'down': WordContext('⬇️', 'Sit down, please.'),
  'little': WordContext('🐣', 'The little chick is cute.'),
  'who': WordContext('❓', 'Who is your best friend?'),
  'yellow': WordContext('🟡', 'The sun is yellow.'),
  'us': WordContext('👫', 'Come play with us!'),
  'of': WordContext('🍕', 'A piece of pizza.'),

  // ── Bonus: Family ───────────────────────────────────────────
  'mom': WordContext('👩', 'I love my mom!'),
  'dad': WordContext('👨', 'My dad is funny.'),
  'baby': WordContext('👶', 'The baby is sleeping.'),
  'love': WordContext('❤️', 'I love you!'),
  'family': WordContext('👨‍👩‍👧‍👦', 'I love my family.'),

  // ── Bonus: Animals ──────────────────────────────────────────
  'dog': WordContext('🐕', 'The dog likes to play.'),
  'cat': WordContext('🐱', 'The cat is sleeping.'),
  'fish': WordContext('🐟', 'The fish can swim.'),
  'bird': WordContext('🐦', 'The bird can sing.'),
  'bear': WordContext('🐻', 'The bear is big!'),
  'frog': WordContext('🐸', 'The frog can jump high!'),

  // ── Bonus: Home & Play ──────────────────────────────────────
  'home': WordContext('🏠', 'There\'s no place like home.'),
  'food': WordContext('🍎', 'I like healthy food.'),
  'book': WordContext('📖', 'Read me a book!'),
  'ball': WordContext('⚽', 'Throw the ball!'),
  'game': WordContext('🎮', 'Let\'s play a fun game!'),
  'toy': WordContext('🧸', 'My favorite toy is a bear.'),

  // ── Bonus: My Body ──────────────────────────────────────────
  'hand': WordContext('✋', 'Raise your hand!'),
  'head': WordContext('🧠', 'Use your head and think.'),
  'eyes': WordContext('👁️', 'Close your eyes!'),
  'feet': WordContext('🦶', 'I have two feet.'),

  // ── Bonus: Nature ───────────────────────────────────────────
  'sun': WordContext('☀️', 'The sun is bright!'),
  'moon': WordContext('🌙', 'Look at the moon!'),
  'star': WordContext('⭐', 'I see a shining star.'),
  'tree': WordContext('🌳', 'The tree is tall.'),
  'rain': WordContext('🌧️', 'I love the rain!'),
  'snow': WordContext('❄️', 'Snow is cold and white.'),

  // ── Bonus: School ───────────────────────────────────────────
  'school': WordContext('🏫', 'I go to school.'),
  'teacher': WordContext('👩‍🏫', 'My teacher is kind.'),
  'friend': WordContext('🤗', 'You are my best friend!'),
  'learn': WordContext('📚', 'I love to learn new words!'),

  // ── Bonus: More Colors ──────────────────────────────────────
  'pink': WordContext('🩷', 'I like pink flowers.'),
  'purple': WordContext('🟣', 'Purple is a pretty color.'),
  'orange': WordContext('🟠', 'I ate an orange.'),

  // ── Bonus: More Numbers ─────────────────────────────────────
  'nine': WordContext('9️⃣', 'I counted to nine!'),
  'zero': WordContext('0️⃣', 'Zero means nothing.'),

  // ── Bonus: Feelings ─────────────────────────────────────────
  'nice': WordContext('😊', 'That was very nice!'),
  'hard': WordContext('💪', 'I can do hard things!'),
  'soft': WordContext('🧸', 'The pillow is soft.'),
  'dark': WordContext('🌙', 'It gets dark at night.'),
  'tall': WordContext('🦒', 'The giraffe is tall!'),
  'loud': WordContext('📢', 'The music is loud!'),
  'quiet': WordContext('🤫', 'Be quiet in the library.'),
};

/// Get the [WordContext] for a word, or `null` if not found.
WordContext? getWordContext(String word) {
  return _wordContexts[word.toLowerCase()];
}

/// Get just the emoji for a word, or empty string if not found.
String getWordEmoji(String word) {
  return _wordContexts[word.toLowerCase()]?.emoji ?? '';
}

/// Get the context sentence for a word, or empty string if not found.
String getWordSentence(String word) {
  return _wordContexts[word.toLowerCase()]?.sentence ?? '';
}

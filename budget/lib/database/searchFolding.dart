import 'package:drift/drift.dart';

// Searching without diacritics: "ca phe" also finds "Cà phê".
// SQLite LOWER and NOCASE only handle ASCII letters, so a query without
// diacritics is turned into a GLOB pattern (works on web and native).

const Map<String, String> _foldGroups = {
  'a': 'àáảãạăằắẳẵặâầấẩẫậ',
  'e': 'èéẻẽẹêềếểễệ',
  'i': 'ìíỉĩị',
  'o': 'òóỏõọôồốổỗộơờớởỡợ',
  'u': 'ùúủũụưừứửữự',
  'y': 'ỳýỷỹỵ',
  'd': 'đ',
};

final Map<String, String> diacriticFolds = {
  for (MapEntry<String, String> group in _foldGroups.entries)
    for (String letter in group.value.split(''))
      for (String variant in {letter, letter.toUpperCase()}) variant: group.key,
};

String foldDiacritics(String text) {
  return text
      .split('')
      .map((letter) => diacriticFolds[letter] ?? letter)
      .join()
      .toLowerCase();
}

bool hasFoldableDiacritics(String text) {
  return text.split('').any(diacriticFolds.containsKey);
}

// Each letter of the query becomes a character class with every accented and
// upper case variant: "ca" -> "*[cC][aAàá...ÀÁ...]*". GLOB is case sensitive and
// compares UTF-8 characters, so this matches regardless of case and accents.
String searchGlobPattern(String query) {
  Map<String, String> variants = {};
  diacriticFolds.forEach((letter, plain) {
    variants[plain] = (variants[plain] ?? '') + letter;
  });
  StringBuffer pattern = StringBuffer('*');
  for (String letter in query.toLowerCase().split('')) {
    String upper = letter.toUpperCase();
    if (letter != upper || variants.containsKey(letter)) {
      pattern.write('[' + letter + upper + (variants[letter] ?? '') + ']');
    } else if ('*?['.contains(letter)) {
      // GLOB wildcards are matched literally inside a class
      pattern.write('[' + letter + ']');
    } else {
      pattern.write(letter);
    }
  }
  pattern.write('*');
  return pattern.toString();
}

extension SearchLike on Expression<String> {
  // A query typed with diacritics keeps the exact (case insensitive) match.
  // Nested REPLACE calls would also work but overflow the sql.js parser stack.
  Expression<bool> likeSearch(String query) {
    if (hasFoldableDiacritics(query)) {
      return collate(Collate.noCase).like("%" + query + "%");
    }
    // glob(pattern, text) is the function form of "text GLOB pattern"
    return FunctionCallExpression<bool>(
        'glob', [Constant(searchGlobPattern(query)), this]);
  }

  // Filter text: "a && b" needs both terms, "a || b" either one
  Expression<bool> likeSearchTerms(String text) {
    Expression<bool>? any;
    for (String orPart in text.split('||')) {
      Expression<bool>? all;
      for (String term in orPart.split('&&')) {
        if (term.trim().isEmpty) continue;
        Expression<bool> match = likeSearch(term.trim());
        all = all == null ? match : all & match;
      }
      if (all != null) any = any == null ? all : any | all;
    }
    return any ?? likeSearch(text);
  }
}

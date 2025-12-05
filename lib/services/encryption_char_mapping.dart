class EncryptionCharMapping {
  static const Map<String, String> englishToRussian = {
    'a': 'а',
    'b': 'б',
    'c': 'ц',
    'd': 'д',
    'e': 'е',
    'f': 'ф',
    'g': 'г',
    'h': 'х',
    'i': 'и',
    'j': 'й',
    'k': 'к',
    'l': 'л',
    'm': 'м',
    'n': 'н',
    'o': 'о',
    'p': 'п',
    'q': 'ч',
    'r': 'р',
    's': 'с',
    't': 'т',
    'u': 'у',
    'v': 'в',
    'w': 'ш',
    'x': 'ж',
    'y': 'ы',
    'z': 'з',
    'A': 'А',
    'B': 'Б',
    'C': 'Ц',
    'D': 'Д',
    'E': 'Е',
    'F': 'Ф',
    'G': 'Г',
    'H': 'Х',
    'I': 'И',
    'J': 'Й',
    'K': 'К',
    'L': 'Л',
    'M': 'М',
    'N': 'Н',
    'O': 'О',
    'P': 'П',
    'Q': 'Ч',
    'R': 'Р',
    'S': 'С',
    'T': 'Т',
    'U': 'У',
    'V': 'В',
    'W': 'Ш',
    'X': 'Ж',
    'Y': 'Ы',
    'Z': 'З',
  };

  static const Map<String, String> russianToEnglish = {
    'а': 'a',
    'б': 'b',
    'ц': 'c',
    'с': 's',
    'д': 'd',
    'е': 'e',
    'ф': 'f',
    'г': 'g',
    'х': 'h',
    'и': 'i',
    'й': 'j',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'ч': 'q',
    'р': 'r',
    'т': 't',
    'у': 'u',
    'в': 'v',
    'ш': 'w',
    'ж': 'x',
    'ы': 'y',
    'з': 'z',
    'А': 'A',
    'Б': 'B',
    'Ц': 'C',
    'С': 'S',
    'Д': 'D',
    'Е': 'E',
    'Ф': 'F',
    'Г': 'G',
    'Х': 'H',
    'И': 'I',
    'Й': 'J',
    'К': 'K',
    'Л': 'L',
    'М': 'M',
    'Н': 'N',
    'О': 'O',
    'П': 'P',
    'Ч': 'Q',
    'Р': 'R',
    'Т': 'T',
    'У': 'U',
    'В': 'V',
    'Ш': 'W',
    'Ж': 'X',
    'Ы': 'Y',
    'З': 'Z',
  };

  static String replaceEnglishWithRussian(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final replacement = englishToRussian[char];
      buffer.write(replacement ?? char);
    }
    return buffer.toString();
  }

  static String replaceRussianWithEnglish(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final replacement = russianToEnglish[char];
      buffer.write(replacement ?? char);
    }
    return buffer.toString();
  }

  static String replaceBase64SpecialChars(String text) {
    return text
        .replaceAll('+', 'привет')
        .replaceAll('/', 'незнаю')
        .replaceAll('=', 'хм');
  }

  static String restoreBase64SpecialChars(String text) {
    return text
        .replaceAll('привет', '+')
        .replaceAll('незнаю', '/')
        .replaceAll('хм', '=');
  }
}

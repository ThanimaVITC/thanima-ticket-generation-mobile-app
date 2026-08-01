/// Pulls a name and registration number out of the raw text ML Kit reads off a
/// VIT ID card.
///
/// The cards are laid out predictably:
///
///     VIT
///     Vellore Institute of Technology
///     (Deemed to be University under section 3 of the UGC Act, 1956)
///     CHENNAI CAMPUS
///     Arjun Menon          <- name
///     23BCE1042           <- registration number
///     HOSTELLER
///
/// So the reg no is the anchor: find it with a regex, then the name is the
/// nearest usable line above it. That beats any "longest line of letters"
/// heuristic, which would happily return "Vellore Institute of Technology".
class IdCardScan {
  final String? name;
  final String? regNo;

  const IdCardScan({this.name, this.regNo});

  bool get isComplete => name != null && regNo != null;
}

class IdCardParser {
  /// 2 digits (year) + 3-4 letters (branch) + 4 digits. e.g. 23BCE1042
  static final RegExp regNoPattern = RegExp(r'\d{2}[A-Z]{3,4}\d{4}');

  /// Words printed on every card that are never part of a person's name.
  ///
  /// Matched as whole WORDS, never substrings. Substring matching looks
  /// tempting and is quietly wrong here: 'VIT' is inside Kavita, Savita and
  /// Vitthal, and 'CARD' is inside Cardoza — all of which are real names this
  /// would otherwise throw away.
  static const Set<String> _boilerplate = {
    'VIT',
    'VELLORE',
    'INSTITUTE',
    'TECHNOLOGY',
    'DEEMED',
    'UNIVERSITY',
    'SECTION',
    'UGC',
    'ACT',
    'CAMPUS',
    'CHENNAI',
    'HOSTELLER',
    'HOSTELER',
    'DAYSCHOLAR',
    'SCHOLAR',
    'STUDENT',
    'IDENTITY',
    'CARD',
    'NAME',
    'REG',
    'REGNO',
    'VALID',
    'SIGNATURE',
  };

  /// OCR routinely swaps these where the character shape is ambiguous. We only
  /// apply them positionally — never blindly across the whole string.
  static const Map<String, String> _toDigit = {
    'O': '0', 'Q': '0', 'D': '0',
    'I': '1', 'L': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };
  static const Map<String, String> _toLetter = {
    '0': 'O',
    '1': 'I',
    '5': 'S',
    '8': 'B',
  };

  static IdCardScan parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    int? regLineIndex;
    String? regNo;

    for (var i = 0; i < lines.length; i++) {
      final found = _findRegNo(lines[i]);
      if (found != null) {
        regNo = found;
        regLineIndex = i;
        break;
      }
    }

    final name = _findName(lines, regLineIndex);
    return IdCardScan(name: name, regNo: regNo);
  }

  /// Strict match first; if that fails, repair characters the OCR is likely to
  /// have confused, but only at positions where the format demands a digit or
  /// a letter.
  static String? _findRegNo(String line) {
    final squashed = line.replaceAll(RegExp(r'[\s._/-]'), '').toUpperCase();

    final direct = regNoPattern.firstMatch(squashed);
    if (direct != null) return direct.group(0);

    // Slide a window over every 9- and 10-char run and try to coerce it.
    for (final len in [9, 10]) {
      for (var i = 0; i + len <= squashed.length; i++) {
        final coerced = _coerce(squashed.substring(i, i + len));
        if (coerced != null && regNoPattern.hasMatch(coerced)) {
          return coerced;
        }
      }
    }
    return null;
  }

  /// Force a candidate into the YY + BRANCH + NNNN shape.
  static String? _coerce(String candidate) {
    final letterCount = candidate.length - 6; // 3 for len 9, 4 for len 10
    if (letterCount < 3 || letterCount > 4) return null;

    final out = StringBuffer();
    for (var i = 0; i < candidate.length; i++) {
      final ch = candidate[i];
      final wantsDigit = i < 2 || i >= 2 + letterCount;

      if (wantsDigit) {
        final fixed = RegExp(r'\d').hasMatch(ch) ? ch : _toDigit[ch];
        if (fixed == null) return null;
        out.write(fixed);
      } else {
        final fixed = RegExp(r'[A-Z]').hasMatch(ch) ? ch : _toLetter[ch];
        if (fixed == null) return null;
        out.write(fixed);
      }
    }
    return out.toString();
  }

  /// The nearest plausible line above the reg no. Falls back to scanning the
  /// whole card if the reg no wasn't found at all.
  static String? _findName(List<String> lines, int? regLineIndex) {
    final start = (regLineIndex ?? lines.length) - 1;

    for (var i = start; i >= 0; i--) {
      if (_looksLikeName(lines[i])) return _tidy(lines[i]);
    }

    // Nothing above it worked — try below (some cards print the name under the
    // number), then give up rather than returning boilerplate.
    if (regLineIndex != null) {
      for (var i = regLineIndex + 1; i < lines.length; i++) {
        if (_looksLikeName(lines[i])) return _tidy(lines[i]);
      }
    }
    return null;
  }

  static final RegExp _namePattern = RegExp(r"^[A-Za-z][A-Za-z .'\-]*$");
  static final RegExp _wordSeparator = RegExp(r"[^A-Z]+");

  static bool _looksLikeName(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 2 || trimmed.length > 40) return false;

    // Letters, spaces, dots, apostrophes and hyphens — no digits, no
    // punctuation soup. Apostrophes and hyphens matter: D'Souza and
    // Anne-Marie are names, not noise.
    if (!_namePattern.hasMatch(trimmed)) return false;

    // At least one run of two letters, so stray initials like "P" or "A B"
    // aren't mistaken for the name line.
    if (!RegExp(r'[A-Za-z]{2}').hasMatch(trimmed)) return false;

    final words = trimmed
        .toUpperCase()
        .split(_wordSeparator)
        .where((w) => w.isNotEmpty)
        .toSet();

    return !words.any(_boilerplate.contains);
  }

  static String _tidy(String line) => line.replaceAll(RegExp(r'\s+'), ' ').trim();
}

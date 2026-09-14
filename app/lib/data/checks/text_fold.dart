/// Vietnamese-aware ASCII folding — the normalization defence line.
///
/// Why this exists: PDF extraction of DOCX-converted files mixes Unicode
/// forms in one document. Proven on the real OTES (tool/probe_vague_otes.dart,
/// 13/09): its requirement texts contain BOTH precomposed letters (U+1EC5 ễ,
/// U+1EBF ề, U+0103 ă…) AND raw combining marks (U+0300). Every matcher that
/// compares against a literal Vietnamese string or word list is blind to the
/// form it wasn't written for: the language detector splits NFD words into
/// letter fragments, the quality phrase scan never matches, and the
/// transaction counter undercounts.
///
/// The fold is deliberately lossy and deterministic: lowercase, drop
/// combining marks (U+0300–U+036F), map precomposed Vietnamese letters to
/// their ASCII base. Matching then happens on ASCII-only patterns, so NFC,
/// NFD and mixed input all land in the same space. English text is
/// untouched by construction.
library;

/// Full precomposed set including the tone-stacked forms, built once.
final Map<int, String> _foldTable = () {
  final table = <int, String>{};
  const groups = [
    ('a', 'àáảãạăằắẳẵặâầấẩẫậ'),
    ('e', 'èéẻẽẹêềếểễệ'),
    ('i', 'ìíỉĩị'),
    ('o', 'òóỏõọôồốổỗộơờớởỡợ'),
    ('u', 'ùúủũụưừứửữự'),
    ('y', 'ỳýỷỹỵ'),
    ('d', 'đ'),
  ];
  for (final (base, letters) in groups) {
    for (final code in letters.runes) {
      table[code] = base;
    }
  }
  return table;
}();

/// Lowercase [input], strip combining marks, fold Vietnamese letters to
/// ASCII bases, and collapse every whitespace run (including the NBSPs
/// PDF extraction sprinkles everywhere) to a single space — a phrase
/// pattern with one space must match "nhanh\nchóng" as honestly as
/// "nhanh chóng". Idempotent.
String foldVietnamese(String input) {
  final buffer = StringBuffer();
  var lastWasSpace = false;
  void writeSpace() {
    if (!lastWasSpace) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }

  for (final code in input.toLowerCase().runes) {
    if (code >= 0x300 && code <= 0x36F) continue; // combining marks
    // Every Unicode whitespace flavour PDFs emit: ASCII controls, NBSP,
    // the thin/en/em space block (0x2000–0x200B, incl. zero-width),
    // and the LINE/PARAGRAPH separators (2028/2029) — the real OTES
    // uses 2028 inside table cells, which silently broke phrase matches.
    final isSpace = code == 0x20 ||
        (code >= 0x09 && code <= 0x0D) ||
        code == 0xA0 ||
        (code >= 0x2000 && code <= 0x200B) ||
        code == 0x2028 ||
        code == 0x2029 ||
        code == 0x3000;
    if (isSpace) {
      writeSpace();
      continue;
    }
    final base = _foldTable[code];
    if (base != null) {
      buffer.write(base);
    } else {
      buffer.writeCharCode(code);
    }
    lastWasSpace = false;
  }
  return buffer.toString();
}

/// Turning stored HTML into something a widget can show.
///
/// Question text, options and explanations all arrive as HTML, because
/// that is how the website stores them: superscripts in formulas, units
/// written with entities, the odd bit of emphasis. Most screens hand
/// that straight to HtmlWidget. A few cannot — the millionaire's answer
/// plates are drawn inside a hexagon and need one flat string — and
/// those are the places where a half-finished decoder shows through as
/// `kg&middot;m/s` on screen.
library;

/// The entities a Nigerian science question bank actually contains.
/// Numeric forms are handled separately, so this only has to cover the
/// named ones.
const Map<String, String> _named = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'middot': '·',
  'times': '×',
  'divide': '÷',
  'minus': '−',
  'plusmn': '±',
  'deg': '°',
  'micro': 'µ',
  'ohm': 'Ω',
  'infin': '∞',
  'ne': '≠',
  'le': '≤',
  'ge': '≥',
  'asymp': '≈',
  'prop': '∝',
  'sum': '∑',
  'radic': '√',
  'int': '∫',
  'part': '∂',
  'nabla': '∇',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'Delta': 'Δ',
  'epsilon': 'ε',
  'theta': 'θ',
  'lambda': 'λ',
  'mu': 'μ',
  'pi': 'π',
  'rho': 'ρ',
  'sigma': 'σ',
  'Sigma': 'Σ',
  'tau': 'τ',
  'phi': 'φ',
  'omega': 'ω',
  'Omega': 'Ω',
  'rarr': '→',
  'larr': '←',
  'harr': '↔',
  'uarr': '↑',
  'darr': '↓',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'bull': '•',
  'frac12': '½',
  'frac14': '¼',
  'frac34': '¾',
  'sup2': '²',
  'sup3': '³',
  'naira': '₦',
};

final RegExp _entity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');
final RegExp _tag = RegExp(r'<[^>]*>');
final RegExp _blockEnd = RegExp(r'</(p|div|li|h[1-6]|tr)\s*>', caseSensitive: false);
final RegExp _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _runOfSpace = RegExp(r'[ \t]+');

/// Decodes every entity, named or numeric. Anything unrecognised is left
/// exactly as written rather than silently dropped — a question that
/// shows `&frobnicate;` is a content bug someone can see and fix, while
/// one that quietly loses a character is not.
String decodeEntities(String input) {
  if (!input.contains('&')) return input;
  return input.replaceAllMapped(_entity, (m) {
    final body = m.group(1)!;
    if (body.startsWith('#')) {
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final digits = body.substring(hex ? 2 : 1);
      final code = int.tryParse(digits, radix: hex ? 16 : 10);
      if (code == null || code < 0 || code > 0x10FFFF) return m.group(0)!;
      // Surrogate halves are not characters on their own.
      if (code >= 0xD800 && code <= 0xDFFF) return m.group(0)!;
      return String.fromCharCode(code);
    }
    return _named[body] ?? m.group(0)!;
  });
}

/// HTML reduced to one readable run of text: tags gone, entities
/// resolved, block ends turned into single spaces.
String htmlToPlain(String html) {
  if (html.isEmpty) return '';
  final flattened = html
      .replaceAll(_lineBreak, ' ')
      .replaceAll(_blockEnd, ' ')
      .replaceAll(_tag, '');
  return decodeEntities(flattened)
      .replaceAll(_runOfSpace, ' ')
      .replaceAll('\n', ' ')
      .replaceAll(_runOfSpace, ' ')
      .trim();
}

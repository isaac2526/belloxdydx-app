import 'package:belloxdydx/core/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// The millionaire's answer plates are drawn inside a hexagon, so they
/// take a flat string rather than rendered HTML. That is the one place
/// an incomplete decoder is visible to a student — it shipped once
/// showing `kg&middot;m/s` on the board.
void main() {
  group('decodeEntities', () {
    test('handles the units a science question bank actually uses', () {
      expect(decodeEntities('kg&middot;m/s'), 'kg·m/s');
      expect(decodeEntities('9.8 m/s&sup2;'), '9.8 m/s²');
      expect(decodeEntities('&plusmn;0.5&deg;C'), '±0.5°C');
      expect(decodeEntities('3 &times; 10&sup3;'), '3 × 10³');
      expect(decodeEntities('&Delta;v / &Delta;t'), 'Δv / Δt');
      expect(decodeEntities('&pi;r&sup2;'), 'πr²');
      expect(decodeEntities('&naira;1,000'), '₦1,000');
    });

    test('handles numeric entities in both bases', () {
      expect(decodeEntities('&#8722;5'), '−5');
      expect(decodeEntities('&#x2212;5'), '−5');
      expect(decodeEntities('&#39;'), "'");
      expect(decodeEntities('&#x1F600;'), '\u{1F600}');
    });

    test('leaves anything it does not know exactly as written', () {
      // A visible oddity is a content bug somebody can fix. A silently
      // dropped character is not.
      expect(decodeEntities('&frobnicate;'), '&frobnicate;');
      expect(decodeEntities('&#xD800;'), '&#xD800;');
      expect(decodeEntities('&#999999999;'), '&#999999999;');
      expect(decodeEntities('a & b'), 'a & b');
    });

    test('costs nothing when there is nothing to decode', () {
      const plain = 'The SI unit of momentum';
      expect(identical(decodeEntities(plain), plain), isTrue);
    });
  });

  group('htmlToPlain', () {
    test('strips tags and keeps the words apart', () {
      expect(htmlToPlain('<p>First</p><p>Second</p>'), 'First Second');
      expect(htmlToPlain('one<br>two'), 'one two');
      expect(htmlToPlain('<strong>kg&middot;m/s</strong>'), 'kg·m/s');
      expect(htmlToPlain('<li>a</li><li>b</li>'), 'a b');
    });

    test('collapses whitespace and trims', () {
      expect(htmlToPlain('  <em>  spaced   out  </em>  '), 'spaced out');
      expect(htmlToPlain('line\nbreak'), 'line break');
    });

    test('survives empty and tag-only input', () {
      expect(htmlToPlain(''), '');
      expect(htmlToPlain('<p></p>'), '');
    });
  });
}

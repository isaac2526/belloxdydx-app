import 'dart:convert';

import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// shieldDeep rewrites storage URLs inside a decoded payload, and every
/// model in the app is built from its result. Its return type therefore
/// has to survive the trip.
///
/// It did not. Map.map infers its type arguments from the closure, and
/// with a dynamic key and a dynamic value that inference produces a
/// `Map<dynamic, dynamic>` — which is not a `Map<String, dynamic>` and
/// cannot be handed to any fromJson here.
///
/// The reason this needs a test rather than a code review: **the browser
/// cannot see it.** dart2js drops implicit downcast checks in release
/// builds, so on web the wrong map sails straight into fromJson and the
/// app looks healthy. Android and iOS run a sound runtime and throw. The
/// only place the two disagree is exactly here, and these tests run on
/// the VM, which behaves like a phone.
void main() {
  shieldingUrls();

  // The real thing, copied rather than imported: Backend needs a live
  // Supabase client to construct, and the defect is in this shape alone.
  dynamic shieldDeep(dynamic node) {
    if (node is String) return node;
    if (node is List) return node.map(shieldDeep).toList();
    if (node is Map) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): shieldDeep(entry.value),
      };
    }
    return node;
  }

  Map<String, dynamic> decoded(String json) =>
      Map<String, dynamic>.from(jsonDecode(json) as Map);

  group('a shielded payload is still a Map<String, dynamic>', () {
    test('at the top level', () {
      final out = shieldDeep(decoded('{"a":1,"b":"two"}'));
      expect(out, isA<Map<String, dynamic>>());
      expect(() => out as Map<String, dynamic>, returnsNormally);
    });

    test('and at every depth, which is where it actually broke', () {
      final out = shieldDeep(decoded(
        '{"question":{"options":[{"key":"A","text":"Newton"}]},"marks":1}',
      ));
      final q = (out as Map<String, dynamic>)['question'];
      expect(q, isA<Map<String, dynamic>>());
      final options = (q as Map<String, dynamic>)['options'] as List;
      expect(options.first, isA<Map<String, dynamic>>());
    });

    test('through a list of rows', () {
      final rows = shieldDeep(jsonDecode('[{"id":"1"},{"id":"2"}]')) as List;
      for (final row in rows) {
        expect(row, isA<Map<String, dynamic>>());
      }
    });

    test('a real model can be built from it', () {
      // This is the assertion that would have failed on a phone while
      // the browser said everything was fine.
      final shielded = shieldDeep(decoded(jsonEncode({
        'id': 'q1',
        'question_html': '<p>The SI unit of momentum is:</p>',
        'question_type': 'mcq',
        'marks': 1,
        'options': [
          {'key': 'A', 'text': 'Newton'},
          {'key': 'B', 'text': 'kg&middot;m/s'},
        ],
      })));
      expect(() => Question.fromJson(shielded), returnsNormally);
      final q = Question.fromJson(shielded);
      expect(q.id, 'q1');
      expect(q.displayOptions.length, 2);
    });

    test('the shape that used to be produced is genuinely unusable', () {
      // Kept as the counter-example, so nobody reintroduces it thinking
      // Map.map is equivalent.
      dynamic broken(dynamic node) {
        if (node is List) return node.map(broken).toList();
        if (node is Map) return node.map((k, v) => MapEntry(k, broken(v)));
        return node;
      }

      final out = broken(decoded('{"id":"q1"}'));
      expect(out, isNot(isA<Map<String, dynamic>>()));
      expect(() => out as Map<String, dynamic>, throwsA(isA<TypeError>()));
    });
  });
}

/// The URL shield rewrites Supabase storage links so they go through the
/// website's caching proxy on the legacy path.
///
/// It used to do that by testing whether a string CONTAINED a storage
/// URL and, if so, replacing the whole string. For a URL field that is
/// right. For a question body with an <img> in it, it replaced the
/// entire question with one `…/api/file?u=<base64 of the document>` —
/// so the student was shown that URL where the question should have
/// been, with the text and the image both gone. These pin the
/// distinction.
void shieldingUrls() {
  const storage = 'https://proj.supabase.co/storage/v1/object/public'
      '/materials/diagrams/vector.png';

  // The real proxy shape, standing in for Backend.fileUrl.
  String proxy(String raw) {
    final b64 = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
    return 'https://site.test/api/file?u=$b64';
  }

  group('the URL shield', () {
    test('a bare URL field becomes a proxied URL', () {
      expect(shieldStorageUrls(storage, proxy),
          startsWith('https://site.test/api/file?u='));
    });

    test('a question body keeps its HTML, its text and its image', () {
      final html = '<p>Identify the vector shown below:</p>'
          '<img src="$storage" alt="A vector diagram">';
      final out = shieldStorageUrls(html, proxy);

      expect(out, startsWith('<p>'), reason: 'still HTML, not a URL');
      expect(out, contains('Identify the vector shown below'),
          reason: 'the question text survives');
      expect(out, contains('<img'), reason: 'the image tag survives');
      expect(out, contains('alt="A vector diagram"'));
      expect(out, isNot(contains(storage)),
          reason: 'the storage URL itself was rewritten');
      expect(out, contains('/api/file?u='));
    });

    test('several images in one body are each rewritten', () {
      final two = '<img src="$storage"><p>and</p><img src="$storage">';
      final out = shieldStorageUrls(two, proxy);
      expect('/api/file?u='.allMatches(out).length, 2);
      expect(out, contains('<p>and</p>'));
    });

    test('single-quoted and unquoted attributes are handled', () {
      expect(shieldStorageUrls("<img src='$storage'>", proxy),
          contains('/api/file?u='));
      expect(shieldStorageUrls('<img src=$storage>', proxy),
          contains('/api/file?u='));
    });

    test('a body with no storage URL is left exactly alone', () {
      const plain = '<p>What is the SI unit of momentum?</p>';
      expect(shieldStorageUrls(plain, proxy), plain);
      expect(identical(shieldStorageUrls(plain, proxy), plain), isTrue);
    });

    test('a whole document must never collapse into one URL', () {
      // The regression, stated as a shape rather than an implementation.
      final html = '<p>text</p><img src="$storage">';
      expect(isBareUrl(shieldStorageUrls(html, proxy)), isFalse);
    });

    test('isBareUrl tells a field from a document', () {
      expect(isBareUrl(storage), isTrue);
      expect(isBareUrl('  $storage  '), isTrue);
      expect(isBareUrl('<img src="$storage">'), isFalse);
      expect(isBareUrl('See $storage for the diagram'), isFalse);
      expect(isBareUrl('not a url at all'), isFalse);
    });
  });
}

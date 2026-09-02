import 'dart:convert';

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

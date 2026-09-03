import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/core/router.dart';
import 'package:flutter_test/flutter_test.dart';

/// "I left a practice question, I am supposed to meet it back."
///
/// The app did come back to the round. It came back to the WRONG
/// QUESTION, and that is a different bug with a different fix.
///
/// The position was derived rather than restored: "open on the first
/// question with no answer". That is not where a student was. Somebody
/// who answers a question and then stops to read the explanation is
/// sitting ON an answered question — so the guess moved them one
/// further on and took away the explanation they had stopped for. On
/// the last question of a round it did something worse and jumped to
/// the end.
///
/// The server has always known the real answer. attempts.current_index
/// has existed since the first migration, /api/practice/answer advances
/// it on every committed answer, PATCH /api/practice/[id] sets it
/// directly, and /api/practice/[id] returns it. The app never read it
/// and never sent it.
void main() {
  routeMemory();
  Question q(String id) => Question(id: id, questionHtml: '<p>$id</p>');

  AttemptSession round({
    required int count,
    Set<String> answered = const {},
    int? currentIndex,
  }) =>
      AttemptSession(
        id: 'a1',
        mode: AttemptMode.practice,
        questions: [for (var i = 0; i < count; i++) q('q$i')],
        answers: {
          for (final id in answered) id: const GivenAnswer(choice: 'A'),
        },
        currentIndex: currentIndex,
      );

  group('the server position wins', () {
    test('it is used even when it sits on an answered question', () {
      // THE BUG, stated as a shape. The student answered q0, q1 and q2
      // and stopped on q2 reading why they were wrong. The old guess
      // said q3.
      final s = round(count: 20, answered: {'q0', 'q1', 'q2'}, currentIndex: 2);
      expect(s.startIndexFor(), 2,
          reason: 'they stopped on the explanation for q2, not on q3');
    });

    test('and when it sits behind the answers', () {
      // Swiping back to re-read q0 is recorded, and must be honoured.
      final s = round(count: 20, answered: {'q0', 'q1', 'q2'}, currentIndex: 0);
      expect(s.startIndexFor(), 0);
    });

    test('and on the last question, where the guess was worst', () {
      final s = round(
        count: 5,
        answered: {'q0', 'q1', 'q2', 'q3', 'q4'},
        currentIndex: 3,
      );
      expect(s.startIndexFor(), 3,
          reason: 'a fully answered round used to jump to the end');
    });
  });

  group('the guess is still there for when the backend says nothing', () {
    test('a fresh round opens at the top', () {
      expect(round(count: 20).startIndexFor(), 0);
    });

    test('a part-answered round opens at the first gap', () {
      final s = round(count: 20, answered: {'q0', 'q1'});
      expect(s.startIndexFor(), 2);
    });

    test('a fully answered round opens at the end rather than nowhere', () {
      final s = round(count: 3, answered: {'q0', 'q1', 'q2'});
      expect(s.startIndexFor(), 2);
    });
  });

  group('a position that cannot be trusted is not used', () {
    test('past the end', () {
      expect(round(count: 5, currentIndex: 99).startIndexFor(), 0,
          reason: 'a stale index from a shorter round must not crash a swipe');
    });

    test('negative', () {
      expect(round(count: 5, currentIndex: -3).startIndexFor(), 0);
    });

    test('an empty round', () {
      expect(round(count: 0, currentIndex: 4).startIndexFor(), 0);
    });
  });

  group('it survives the wire and the disk', () {
    test('read from the top level, the way the direct RPC sends it', () {
      final s = AttemptSession.fromJson({
        'id': 'a1',
        'mode': 'practice',
        'questions': [
          {'id': 'q0', 'question_html': '<p>a</p>'},
          {'id': 'q1', 'question_html': '<p>b</p>'},
          {'id': 'q2', 'question_html': '<p>c</p>'},
        ],
        'current_index': 2,
      });
      expect(s.currentIndex, 2);
      expect(s.startIndexFor(), 2);
    });

    test('read off the attempt object, the way the website sends it', () {
      // /api/practice/[id]:61 puts it inside `attempt`.
      final s = AttemptSession.fromJson({
        'attempt': {'id': 'a1', 'mode': 'practice', 'current_index': 1},
        'questions': [
          {'id': 'q0', 'question_html': '<p>a</p>'},
          {'id': 'q1', 'question_html': '<p>b</p>'},
        ],
      });
      expect(s.currentIndex, 1);
      expect(s.startIndexFor(), 1);
    });

    test('a string index is read, because JSON is not always tidy', () {
      final s = AttemptSession.fromJson({
        'id': 'a1',
        'mode': 'practice',
        'questions': [
          {'id': 'q0', 'question_html': '<p>a</p>'},
          {'id': 'q1', 'question_html': '<p>b</p>'},
        ],
        'current_index': '1',
      });
      expect(s.currentIndex, 1);
    });

    test('absent means absent, not zero', () {
      // The distinction matters: zero would silently send every
      // resuming student back to question one.
      final s = AttemptSession.fromJson({
        'id': 'a1',
        'mode': 'practice',
        'questions': [
          {'id': 'q0', 'question_html': '<p>a</p>'},
          {'id': 'q1', 'question_html': '<p>b</p>'},
        ],
        'answers': {'q0': {'choice': 'A'}},
      });
      expect(s.currentIndex, isNull);
      expect(s.startIndexFor(), 1, reason: 'falls back to the guess');
    });
  });
}

/// ============================================================
/// COMING BACK TO THE SCREEN, NOT JUST THE ANSWERS
///
/// "if I'm offline or online and I left a practice questions I suppose
///  to meet it back, if just for a second for 16 GB RAM phone the app
///  has already refreshed"
///
/// Three pieces make that true and each is tested where it lives: the
/// answers survive (offline_test), the position survives (above), and
/// the SCREEN is remembered. This is the rule that decides which
/// screens — get it too wide and the app reopens on something a student
/// walked away from on purpose.
/// ============================================================
void routeMemory() {
  group('which screens are worth coming back to', () {
    test('a round in progress is', () {
      expect(bxIsResumableRoute('/practice/abc-123'), isTrue);
      expect(bxIsResumableRoute('/cbt/abc-123'), isTrue);
    });

    test('so is something being read', () {
      expect(bxIsResumableRoute('/notes/abc'), isTrue);
      expect(bxIsResumableRoute('/view/abc'), isTrue);
      expect(bxIsResumableRoute('/watch/abc'), isTrue);
      expect(bxIsResumableRoute('/results/abc'), isTrue);
    });

    test('a tab is not', () {
      // A student who was on the dashboard is not mid-anything.
      // Reopening there is what the app does anyway.
      for (final tab in const ['/', '/courses', '/revision', '/ai',
        '/ranks', '/you']) {
        expect(bxIsResumableRoute(tab), isFalse, reason: tab);
      }
    });

    test('an auth screen is never restored', () {
      // Reopening the app on a login form for an account that is
      // already signed in would be the bug this whole area exists to
      // fix, arriving by a different door.
      for (final loc in const ['/splash', '/welcome', '/login',
        '/register', '/onboarding', '/frozen', '/new-device',
        '/reset-password', '/forgot-password']) {
        expect(bxIsResumableRoute(loc), isFalse, reason: loc);
      }
    });

    test('a bare prefix without an id is not a screen', () {
      // '/practice' with no attempt id routes nowhere. Restoring it
      // would drop the student on the error page.
      expect(bxIsResumableRoute('/practice'), isFalse);
      expect(bxIsResumableRoute('/notes'), isFalse);
    });

    test('the window is long enough for an interruption and short '
        'enough for a night', () {
      expect(bxRouteMemoryLifetime.inHours, greaterThanOrEqualTo(2),
          reason: 'a lecture, a bus ride and a flat battery all fit '
              'inside an interruption');
      expect(bxRouteMemoryLifetime.inHours, lessThanOrEqualTo(24),
          reason: 'coming back the next morning should open the app, '
              "not last night's question");
    });
  });
}

import 'package:belloxdydx/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The models must parse BOTH shapes the backend can produce: snake_case
/// rows straight from Postgres (the direct path) and the camelCase
/// envelopes the website's /api/mobile routes return (the legacy path).
/// These tests pin that down, because a silent mismatch there would show
/// up as a blank screen rather than an error.
void main() {
  aCorrectedAnnouncement();
  group('Profile', () {
    test('parses a Postgres row', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'surname': 'Adeyemi',
        'first_name': 'Kunle',
        'username': 'kunle',
        'matric_no': '235019',
        'is_activated': true,
        'current_level': '100',
      });
      expect(p.firstName, 'Kunle');
      expect(p.fullName, 'Kunle Adeyemi');
      expect(p.handle, '@kunle');
      expect(p.isActivated, isTrue);
      expect(p.watermark, '@kunle · 235019');
    });

    test('parses the mobile API envelope', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'surname': 'Okonkwo',
        'firstName': 'Amaka',
        'username': 'amaka_o',
        'matric': '235044',
        'isActivated': false,
      });
      expect(p.firstName, 'Amaka');
      expect(p.matricNo, '235044');
      expect(p.isActivated, isFalse);
    });

    test('watermark omits the separator when there is no matric', () {
      const p = Profile(id: 'u', surname: 'B', firstName: 'T', username: 'tunde');
      expect(p.watermark, '@tunde');
    });
  });

  group('Question', () {
    test('synthesises True/False options', () {
      const q = Question(
        id: 'q1',
        questionHtml: 'The earth is round.',
        type: QuestionType.trueFalse,
      );
      expect(q.displayOptions.map((o) => o.key), ['T', 'F']);
      expect(q.displayOptions.first.text, 'True');
    });

    test('short answer has no options and exposes the first accepted spelling', () {
      const q = Question(
        id: 'q2',
        questionHtml: 'Unit of momentum?',
        type: QuestionType.shortAnswer,
        answerText: 'kgm/s|kg m/s|kilogram metre per second',
      );
      expect(q.displayOptions, isEmpty);
      expect(q.acceptedAnswer, 'kgm/s');
    });

    test('merging a verdict brings the explanation in', () {
      const q = Question(id: 'q3', questionHtml: 'x');
      final merged = q.mergeAnswer(const AnswerVerdict(
        correct: true,
        correctKey: 'B',
        explanationHtml: '<p>Because.</p>',
      ));
      expect(merged.correctKey, 'B');
      expect(merged.explanationHtml, '<p>Because.</p>');
      expect(merged.hasExplanation, isTrue);
    });

    test('parses options from a jsonb array', () {
      final q = Question.fromJson({
        'id': 'q4',
        'question_html': 'Pick one',
        'question_type': 'mcq',
        'options': [
          {'key': 'a', 'text': 'Newton'},
          {'key': 'b', 'text': 'kg m/s', 'image_url': null},
        ],
      });
      expect(q.options.length, 2);
      expect(q.options.first.key, 'A', reason: 'keys are upper-cased');
    });
  });

  group('AttemptSession', () {
    test('reads the CBT shape where answers are plain choice strings', () {
      final s = AttemptSession.fromJson({
        'id': 'a1',
        'attempt': {'id': 'a1', 'mode': 'exam', 'status': 'in_progress', 'violations': 2},
        'questions': [
          {'id': 'q1', 'question_html': 'One', 'options': []},
        ],
        'answers': {'q1': 'B'},
        'endsAt': '2030-01-01T10:00:00Z',
        'serverNow': '2030-01-01T09:30:00Z',
      });
      expect(s.mode, AttemptMode.exam);
      expect(s.mode.isTimed, isTrue);
      expect(s.violations, 2);
      expect(s.answers['q1']!.choice, 'B');
      expect(s.answers['q1']!.isAnswered, isTrue);
    });

    test('reads the practice shape where answers are objects', () {
      final s = AttemptSession.fromJson({
        'id': 'a2',
        'attempt': {'id': 'a2', 'mode': 'practice', 'status': 'in_progress'},
        'questions': const [],
        'answers': {
          'q1': {'choice': 'A', 'is_correct': false},
        },
        'bookmarks': ['q1'],
      });
      expect(s.mode, AttemptMode.practice);
      expect(s.mode.isTimed, isFalse);
      expect(s.answers['q1']!.isCorrect, isFalse);
      expect(s.bookmarks.contains('q1'), isTrue);
    });

    test('clock skew is derived from the server clock', () {
      final s = AttemptSession.fromJson({
        'id': 'a3',
        'attempt': {'id': 'a3', 'mode': 'test'},
        'questions': const [],
        'serverNow': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });
      expect(s.clockSkew.inMinutes, closeTo(5, 1));
    });
  });

  group('AttemptSummary', () {
    test('computes the percentage and guards divide-by-zero', () {
      final a = AttemptSummary.fromJson({
        'id': 'x', 'mode': 'test', 'score': 8, 'total': 10,
        'courses': {'code': 'PHY 101', 'title': 'Physics'},
        'tests': {'title': 'Weekly Test'},
      });
      expect(a.percent, 80);
      expect(a.courseCode, 'PHY 101');
      expect(a.displayTitle, 'Weekly Test');

      final empty = AttemptSummary.fromJson({'id': 'y', 'mode': 'practice'});
      expect(empty.percent, 0);
      expect(empty.displayTitle, 'Practice');
    });
  });

  group('ResultReview', () {
    test('parses items and derives the verdict band', () {
      final r = ResultReview.fromJson({
        'attemptId': 'a1',
        'score': 9,
        'total': 10,
        'mode': 'exam',
        'title': 'Mock Exam',
        'beat': 72,
        'timeUsedSeconds': 930,
        'items': [
          {
            'n': 1,
            'id': 'q1',
            'question_html': 'One',
            'options': [
              {'key': 'A', 'text': 'x'},
              {'key': 'B', 'text': 'y'},
            ],
            'correct_key': 'B',
            'your_key': 'B',
            'is_correct': true,
          },
        ],
      });
      expect(r.percent, 90);
      expect(r.verdict, contains('Distinction'));
      expect(r.beatPercent, 72);
      expect(r.timeUsed, const Duration(seconds: 930));
      expect(r.items.single.answered, isTrue);
      expect(r.items.single.question.correctKey, 'B');
    });

    test('a skipped question reads as unanswered', () {
      final item = ReviewItem.fromJson({
        'n': 2, 'id': 'q2', 'question_html': 'Two', 'options': [],
      });
      expect(item.answered, isFalse);
      expect(item.isCorrect, isFalse);
    });
  });

  group('DashboardData', () {
    test('merges the nested stats envelope', () {
      final d = DashboardData.fromJson({
        'firstName': 'Kunle',
        'streak': {'current': 12, 'best': 21},
        'quote': {'content': 'Show up.', 'author': 'Tutor Bello'},
        'rank': 3,
        'points': 1840,
        'stats': {
          'attemptsSubmitted': 5,
          'averagePercent': 71,
          'questionsAnswered': 80,
          'correctCount': 56,
          'wrongCount': 24,
        },
        'courseAverages': [
          {'code': 'PHY 101', 'average': 80},
        ],
        'resume': {'id': 'a9', 'kind': 'cbt', 'courseCode': 'MTH 101'},
        'wallOfFame': [
          {'username': 'amaka_o', 'percent': 95},
        ],
      });
      expect(d.firstName, 'Kunle');
      expect(d.streakCurrent, 12);
      expect(d.averagePercent, 71);
      expect(d.correctCount, 56);
      expect(d.courseAverages.single.code, 'PHY 101');
      expect(d.resume!.isTimed, isTrue,
          reason: 'a cbt resume must route to the exam runner');
      expect(d.wallOfFame.single.percent, 95);
    });

    test('survives a completely empty payload', () {
      final d = DashboardData.fromJson(const {});
      expect(d.attemptsSubmitted, 0);
      expect(d.quote.content, isNotEmpty);
      expect(d.resume, isNull);
    });
  });

  group('StudyMaterial', () {
    test('maps every material kind the platform serves', () {
      for (final entry in {
        'note': MaterialKind.note,
        'slide': MaterialKind.slide,
        'video': MaterialKind.video,
        'series': MaterialKind.series,
        'pq': MaterialKind.pq,
        'nonsense': MaterialKind.unknown,
      }.entries) {
        final m = StudyMaterial.fromJson({
          'id': 'm', 'course_id': 'c', 'type': entry.key, 'title': 't',
        });
        expect(m.kind, entry.value, reason: 'type "${entry.key}"');
      }
    });

    test('parses attachments', () {
      final m = StudyMaterial.fromJson({
        'id': 'm', 'course_id': 'c', 'type': 'note', 'title': 't',
        'content_html': '<p>Body</p>',
        'attachments': [
          {'title': 'Slides', 'url': 'https://x/y.pdf', 'kind': 'pdf'},
        ],
      });
      expect(m.hasBody, isTrue);
      expect(m.attachments.single.kind, 'pdf');
    });
  });

  group('AnswerVerdict', () {
    test('flags the time_up error the CBT runner acts on', () {
      final v = AnswerVerdict.fromJson({'error': 'time_up'});
      expect(v.timeUp, isTrue);
    });

    test('reads a practice grading response', () {
      final v = AnswerVerdict.fromJson({
        'correct': true,
        'correctKey': 'B',
        'explanationHtml': '<p>Because momentum is mv.</p>',
      });
      expect(v.correct, isTrue);
      expect(v.correctKey, 'B');
    });
  });

  group('AttemptMode', () {
    test('labels and timing match the website', () {
      expect(AttemptMode.smart.label, 'Smart revision');
      expect(AttemptMode.bookmarks.label, 'Saved questions');
      expect(AttemptMode.exam.isTimed, isTrue);
      expect(AttemptMode.practice.isTimed, isFalse);
    });
  });
}

/// ============================================================
/// A CORRECTED ANNOUNCEMENT
///
/// An announcement is the thing most likely to need correcting after
/// it is posted — a moved venue, a changed date. A student who
/// dismissed the old version and is now being shown it again has to be
/// told why it is back, and a notice that was never touched must not
/// claim to have been edited because a trigger fired on its insert.
/// ============================================================
void aCorrectedAnnouncement() {
  group('an announcement that was edited', () {
    Announcement made({DateTime? at, DateTime? moved}) => Announcement(
          id: 'a1',
          title: 'Venue',
          body: 'LT1',
          createdAt: at,
          updatedAt: moved,
        );

    test('says so when the wording actually moved', () {
      final a = made(
        at: DateTime(2026, 9, 1, 8),
        moved: DateTime(2026, 9, 3, 17),
      );
      expect(a.wasEdited, isTrue);
    });

    test('does not, when the stamp only moved by the insert trigger', () {
      // updated_at defaults to now() alongside created_at, so the two
      // differ by microseconds on every row that was never edited.
      final at = DateTime(2026, 9, 1, 8);
      expect(
        made(at: at, moved: at.add(const Duration(milliseconds: 3))).wasEdited,
        isFalse,
      );
      expect(made(at: at, moved: at).wasEdited, isFalse);
    });

    test('does not, when either date is missing', () {
      // An older backend that sends no updated_at must not make every
      // notice in the list look freshly corrected.
      expect(made(at: DateTime(2026, 9, 1)).wasEdited, isFalse);
      expect(made(moved: DateTime(2026, 9, 1)).wasEdited, isFalse);
      expect(made().wasEdited, isFalse);
    });

    test('reads updated_at off either backend path', () {
      expect(
        Announcement.fromJson({
          'id': 'a1',
          'title': 'Venue',
          'body': 'LT2',
          'created_at': '2026-09-01T08:00:00.000Z',
          'updated_at': '2026-09-03T17:00:00.000Z',
        }).wasEdited,
        isTrue,
      );
      expect(
        Announcement.fromJson({
          'id': 'a1',
          'title': 'Venue',
          'body': 'LT2',
          'createdAt': '2026-09-01T08:00:00.000Z',
          'updatedAt': '2026-09-03T17:00:00.000Z',
        }).wasEdited,
        isTrue,
      );
    });
  });
}

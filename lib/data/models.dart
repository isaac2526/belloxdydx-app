import 'package:flutter/foundation.dart';

/// ============================================================
/// DOMAIN MODELS
///
/// Every fromJson tolerates both shapes the backend can produce:
/// snake_case rows straight from Postgres (the direct path) and the
/// camelCase envelopes the website's /api/mobile routes return (the
/// legacy path). One model, either source.
/// ============================================================

T? _pick<T>(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null) return v as T;
  }
  return null;
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _dbl(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return fallback;
}

/// Nullable variant. `bool?` fields used to be filled by a plain
/// `j['is_correct']`, which is an implicit downcast from dynamic: fine
/// on the web, where dart2js drops the check in release, and a throw on
/// Android and iOS the moment a backend sends the flag as 0/1 or "t".
bool? _boolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return null;
}

String _str(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString())?.toLocal();
}

List<Map<String, dynamic>> _rows(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
  return const [];
}

// ============================================================
// Profile
// ============================================================

@immutable
class Profile {
  final String id;
  final String surname;
  final String firstName;
  final String username;
  final String email;
  final String phone;
  final String matricNo;
  final String referralCode;
  final String currentLevel;
  final bool isActivated;
  final bool isFrozen;
  final String frozenReason;

  const Profile({
    required this.id,
    required this.surname,
    required this.firstName,
    required this.username,
    this.email = '',
    this.phone = '',
    this.matricNo = '',
    this.referralCode = '',
    this.currentLevel = '100',
    this.isActivated = false,
    this.isFrozen = false,
    this.frozenReason = '',
  });

  String get fullName => '$firstName $surname'.trim();
  String get handle => '@$username';

  /// The identity burned across every protected document.
  String get watermark =>
      '@$username${matricNo.isNotEmpty ? ' · $matricNo' : ''}';

  static const empty = Profile(id: '', surname: '', firstName: '', username: '');

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: _str(_pick(j, ['id', 'user_id'])),
        surname: _str(_pick(j, ['surname'])),
        firstName: _str(_pick(j, ['first_name', 'firstName'])),
        username: _str(_pick(j, ['username'])),
        email: _str(_pick(j, ['email'])),
        phone: _str(_pick(j, ['phone'])),
        matricNo: _str(_pick(j, ['matric_no', 'matric'])),
        referralCode: _str(_pick(j, ['referral_code', 'referralCode'])),
        currentLevel: _str(_pick(j, ['current_level', 'currentLevel']), '100'),
        isActivated: _bool(_pick(j, ['is_activated', 'isActivated'])),
        isFrozen: _bool(_pick(j, ['is_frozen', 'isFrozen'])),
        frozenReason: _str(_pick(j, ['frozen_reason', 'frozenReason'])),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'surname': surname,
        'first_name': firstName,
        'username': username,
        'email': email,
        'phone': phone,
        'matric_no': matricNo,
        'referral_code': referralCode,
        'current_level': currentLevel,
        'is_activated': isActivated,
        'is_frozen': isFrozen,
        'frozen_reason': frozenReason,
      };

  Profile copyWith({bool? isActivated, String? currentLevel}) => Profile(
        id: id,
        surname: surname,
        firstName: firstName,
        username: username,
        email: email,
        phone: phone,
        matricNo: matricNo,
        referralCode: referralCode,
        currentLevel: currentLevel ?? this.currentLevel,
        isActivated: isActivated ?? this.isActivated,
        isFrozen: isFrozen,
        frozenReason: frozenReason,
      );
}

// ============================================================
// Course & materials
// ============================================================

@immutable
class Course {
  final String id;
  final String code;
  final String title;
  final int semester;
  final int sortOrder;
  final String levelCode;

  const Course({
    required this.id,
    required this.code,
    required this.title,
    this.semester = 1,
    this.sortOrder = 0,
    this.levelCode = '100',
  });

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: _str(j['id']),
        code: _str(j['code']),
        title: _str(j['title']),
        semester: _int(j['semester'], 1),
        sortOrder: _int(j['sort_order']),
        levelCode: _str(_pick(j, ['level_code', 'levelCode']), '100'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'title': title,
        'semester': semester,
        'sort_order': sortOrder,
        'level_code': levelCode,
      };
}

/// The four kinds of study material, matching the website's sections.
enum MaterialKind { note, slide, video, series, pq, unknown }

MaterialKind materialKindOf(String raw) => switch (raw) {
      'note' => MaterialKind.note,
      'slide' => MaterialKind.slide,
      'video' => MaterialKind.video,
      'series' => MaterialKind.series,
      'pq' => MaterialKind.pq,
      _ => MaterialKind.unknown,
    };

@immutable
class Attachment {
  final String title;
  final String url;
  final String kind; // pdf | image | audio | file

  const Attachment({required this.title, required this.url, required this.kind});

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        title: _str(j['title'], 'Attachment'),
        url: _str(j['url']),
        kind: _str(j['kind'], 'file'),
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, 'kind': kind};
}

@immutable
class StudyMaterial {
  final String id;
  final String courseId;
  final MaterialKind kind;
  final String title;
  final String topic;
  final String url;
  final String contentHtml;
  final String durationLabel;
  final int sortOrder;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final List<Attachment> attachments;

  const StudyMaterial({
    required this.id,
    required this.courseId,
    required this.kind,
    required this.title,
    this.topic = '',
    this.url = '',
    this.contentHtml = '',
    this.durationLabel = '',
    this.sortOrder = 0,
    this.updatedAt,
    this.createdAt,
    this.attachments = const [],
  });

  bool get hasBody => contentHtml.trim().isNotEmpty;

  factory StudyMaterial.fromJson(Map<String, dynamic> j) => StudyMaterial(
        id: _str(j['id']),
        courseId: _str(_pick(j, ['course_id', 'courseId'])),
        kind: materialKindOf(_str(j['type'])),
        title: _str(j['title']),
        topic: _str(j['topic']),
        url: _str(j['url']),
        contentHtml: _str(_pick(j, ['content_html', 'contentHtml'])),
        durationLabel: _str(_pick(j, ['duration_label', 'durationLabel'])),
        sortOrder: _int(j['sort_order']),
        updatedAt: _date(_pick(j, ['updated_at', 'updatedAt'])),
        createdAt: _date(_pick(j, ['created_at', 'createdAt'])),
        attachments:
            _rows(j['attachments']).map(Attachment.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'type': kind.name,
        'title': title,
        'topic': topic,
        'url': url,
        'content_html': contentHtml,
        'duration_label': durationLabel,
        'sort_order': sortOrder,
        'updated_at': updatedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}

// ============================================================
// Questions
// ============================================================

enum QuestionType { multipleChoice, trueFalse, shortAnswer }

QuestionType questionTypeOf(String raw) => switch (raw) {
      'true_false' => QuestionType.trueFalse,
      'short_answer' => QuestionType.shortAnswer,
      _ => QuestionType.multipleChoice,
    };

@immutable
class QuestionOption {
  final String key;
  final String text;
  final String? imageUrl;

  const QuestionOption({required this.key, this.text = '', this.imageUrl});

  factory QuestionOption.fromJson(Map<String, dynamic> j) => QuestionOption(
        key: _str(j['key']).toUpperCase(),
        text: _str(j['text']),
        imageUrl: (j['image_url'] ?? j['imageUrl'])?.toString(),
      );

  Map<String, dynamic> toJson() =>
      {'key': key, 'text': text, 'image_url': imageUrl};
}

/// A question as the client is allowed to see it.
///
/// During a test [correctKey] is null — the server never sends it. In
/// practice it arrives only in the answer response, after the student
/// has committed. That property is what makes direct Postgres reads
/// safe: the `public_questions` view does not expose the answer at all.
@immutable
class Question {
  final String id;
  final String courseId;
  final String questionHtml;
  final String? questionImageUrl;
  final String? questionAudioUrl;
  final List<QuestionOption> options;
  final QuestionType type;
  final int marks;
  final String? correctKey;
  final String? answerText;
  final String? explanationHtml;
  final String? explanationImageUrl;
  final String? explanationAudioUrl;
  final String courseCode;

  const Question({
    required this.id,
    required this.questionHtml,
    this.courseId = '',
    this.questionImageUrl,
    this.questionAudioUrl,
    this.options = const [],
    this.type = QuestionType.multipleChoice,
    this.marks = 1,
    this.correctKey,
    this.answerText,
    this.explanationHtml,
    this.explanationImageUrl,
    this.explanationAudioUrl,
    this.courseCode = '',
  });

  /// True/False stores no options in the database; the two buttons are
  /// synthesised here exactly as the website does.
  List<QuestionOption> get displayOptions {
    if (type == QuestionType.trueFalse) {
      return const [
        QuestionOption(key: 'T', text: 'True'),
        QuestionOption(key: 'F', text: 'False'),
      ];
    }
    if (type == QuestionType.shortAnswer) return const [];
    return options;
  }

  /// The first accepted spelling for a typed answer.
  String get acceptedAnswer =>
      (answerText ?? '').split('|').first.trim();

  bool get hasExplanation =>
      (explanationHtml ?? '').trim().isNotEmpty ||
      (explanationImageUrl ?? '').isNotEmpty ||
      (explanationAudioUrl ?? '').isNotEmpty;

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: _str(j['id']),
        courseId: _str(_pick(j, ['course_id', 'courseId'])),
        questionHtml: _str(_pick(j, ['question_html', 'questionHtml'])),
        questionImageUrl:
            _pick(j, ['question_image_url', 'questionImageUrl'])?.toString(),
        questionAudioUrl:
            _pick(j, ['question_audio_url', 'questionAudioUrl'])?.toString(),
        options: _rows(j['options']).map(QuestionOption.fromJson).toList(),
        type: questionTypeOf(_str(_pick(j, ['question_type', 'questionType']))),
        marks: _int(j['marks'], 1),
        correctKey: _pick(j, ['correct_key', 'correctKey'])?.toString(),
        answerText: _pick(j, ['answer_text', 'answerText'])?.toString(),
        explanationHtml:
            _pick(j, ['explanation_html', 'explanationHtml'])?.toString(),
        explanationImageUrl: _pick(j, ['explanation_image_url', 'explanationImageUrl'])
            ?.toString(),
        explanationAudioUrl: _pick(j, ['explanation_audio_url', 'explanationAudioUrl'])
            ?.toString(),
        courseCode: _str(_pick(j, ['course', 'course_code', 'courseCode'])),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'question_html': questionHtml,
        'question_image_url': questionImageUrl,
        'question_audio_url': questionAudioUrl,
        'options': options.map((o) => o.toJson()).toList(),
        'question_type': switch (type) {
          QuestionType.trueFalse => 'true_false',
          QuestionType.shortAnswer => 'short_answer',
          QuestionType.multipleChoice => 'mcq',
        },
        'marks': marks,
        'correct_key': correctKey,
        'answer_text': answerText,
        'explanation_html': explanationHtml,
        'explanation_image_url': explanationImageUrl,
        'explanation_audio_url': explanationAudioUrl,
        'course': courseCode,
      };

  Question mergeAnswer(AnswerVerdict v) => Question(
        id: id,
        courseId: courseId,
        questionHtml: questionHtml,
        questionImageUrl: questionImageUrl,
        questionAudioUrl: questionAudioUrl,
        options: options,
        type: type,
        marks: marks,
        correctKey: v.correctKey ?? correctKey,
        answerText: v.acceptedAnswer ?? answerText,
        explanationHtml: v.explanationHtml ?? explanationHtml,
        explanationImageUrl: v.explanationImageUrl ?? explanationImageUrl,
        explanationAudioUrl: v.explanationAudioUrl ?? explanationAudioUrl,
        courseCode: courseCode,
      );
}

// ============================================================
// Tests & attempts
// ============================================================

enum TestMode { test, exam }

@immutable
class StudyTest {
  final String id;
  final String courseId;
  final String title;
  final TestMode mode;
  final int durationMinutes;
  final int questionCount;
  final int? bestPercent;
  final String? inProgressAttemptId;

  const StudyTest({
    required this.id,
    required this.title,
    this.courseId = '',
    this.mode = TestMode.test,
    this.durationMinutes = 0,
    this.questionCount = 0,
    this.bestPercent,
    this.inProgressAttemptId,
  });

  bool get isExam => mode == TestMode.exam;

  factory StudyTest.fromJson(Map<String, dynamic> j) => StudyTest(
        id: _str(j['id']),
        courseId: _str(_pick(j, ['course_id', 'courseId'])),
        title: _str(j['title']),
        mode: _str(j['mode']) == 'exam' ? TestMode.exam : TestMode.test,
        durationMinutes: _int(_pick(j, ['duration_minutes', 'durationMinutes'])),
        questionCount: _int(_pick(j, ['question_count', 'questionCount'])),
        bestPercent: j['best'] == null ? null : _int(j['best']),
        inProgressAttemptId:
            _pick(j, ['in_progress_id', 'inProgressId'])?.toString(),
      );

  StudyTest withProgress({int? best, String? inProgressId}) => StudyTest(
        id: id,
        courseId: courseId,
        title: title,
        mode: mode,
        durationMinutes: durationMinutes,
        questionCount: questionCount,
        bestPercent: best ?? bestPercent,
        inProgressAttemptId: inProgressId ?? inProgressAttemptId,
      );
}

/// Practice, smart revision, saved questions, test and exam all run
/// through the same attempt machinery.
enum AttemptMode { practice, smart, bookmarks, test, exam }

AttemptMode attemptModeOf(String raw) => switch (raw) {
      'smart' => AttemptMode.smart,
      'bookmarks' => AttemptMode.bookmarks,
      'test' => AttemptMode.test,
      'exam' => AttemptMode.exam,
      _ => AttemptMode.practice,
    };

extension AttemptModeLabel on AttemptMode {
  String get label => switch (this) {
        AttemptMode.smart => 'Smart revision',
        AttemptMode.bookmarks => 'Saved questions',
        AttemptMode.test => 'Test',
        AttemptMode.exam => 'Exam',
        AttemptMode.practice => 'Practice',
      };

  /// Timed modes run on the server clock and never reveal correctness.
  bool get isTimed => this == AttemptMode.test || this == AttemptMode.exam;
}

@immutable
class AttemptSummary {
  final String id;
  final AttemptMode mode;
  final String status;
  final int score;
  final int total;
  final DateTime? submittedAt;
  final String courseCode;
  final String courseTitle;
  final String? testTitle;
  final int violations;

  const AttemptSummary({
    required this.id,
    required this.mode,
    this.status = 'submitted',
    this.score = 0,
    this.total = 0,
    this.submittedAt,
    this.courseCode = '',
    this.courseTitle = '',
    this.testTitle,
    this.violations = 0,
  });

  int get percent => total <= 0 ? 0 : ((score / total) * 100).round();
  String get displayTitle => testTitle ?? mode.label;

  factory AttemptSummary.fromJson(Map<String, dynamic> j) {
    final courses = j['courses'];
    final tests = j['tests'];
    return AttemptSummary(
      id: _str(j['id']),
      mode: attemptModeOf(_str(j['mode'])),
      status: _str(j['status'], 'submitted'),
      score: _int(j['score']),
      total: _int(j['total']),
      submittedAt: _date(_pick(j, ['submitted_at', 'submittedAt'])),
      courseCode: _str(courses is Map
          ? courses['code']
          : _pick(j, ['course_code', 'courseCode'])),
      courseTitle: _str(courses is Map
          ? courses['title']
          : _pick(j, ['course_title', 'courseTitle'])),
      testTitle: tests is Map
          ? tests['title']?.toString()
          : _pick(j, ['test_title', 'testTitle'])?.toString(),
      violations: _int(j['violations']),
    );
  }
}

/// A live attempt with its questions and the answers so far.
@immutable
class AttemptSession {
  final String id;
  final AttemptMode mode;
  final String status;
  final List<Question> questions;
  final Map<String, GivenAnswer> answers;
  final Set<String> bookmarks;
  final DateTime? endsAt;
  final DateTime? serverNow;
  final String title;
  final String courseCode;
  final String courseTitle;
  final String courseId;
  final int violations;

  const AttemptSession({
    required this.id,
    required this.mode,
    required this.questions,
    this.status = 'in_progress',
    this.answers = const {},
    this.bookmarks = const {},
    this.endsAt,
    this.serverNow,
    this.title = '',
    this.courseCode = '',
    this.courseTitle = '',
    this.courseId = '',
    this.violations = 0,
  });

  bool get isSubmitted => status == 'submitted';

  /// Skew between the device clock and the server clock, applied on every
  /// tick so changing the phone's time gains nothing.
  Duration get clockSkew => serverNow == null
      ? Duration.zero
      : serverNow!.difference(DateTime.now());

  factory AttemptSession.fromJson(Map<String, dynamic> j) {
    final answers = <String, GivenAnswer>{};
    final rawAnswers = j['answers'];
    if (rawAnswers is Map) {
      rawAnswers.forEach((k, v) {
        if (v is Map) {
          answers['$k'] = GivenAnswer.fromJson(Map<String, dynamic>.from(v));
        } else if (v != null) {
          // The CBT route returns a plain choice string per question.
          answers['$k'] = GivenAnswer(choice: v.toString());
        }
      });
    }

    final attempt = j['attempt'] is Map
        ? Map<String, dynamic>.from(j['attempt'])
        : <String, dynamic>{};
    final test =
        j['test'] is Map ? Map<String, dynamic>.from(j['test']) : const {};
    final course =
        j['course'] is Map ? Map<String, dynamic>.from(j['course']) : const {};

    return AttemptSession(
      id: _str(_pick(j, ['id', 'attemptId']) ?? attempt['id']),
      mode: attemptModeOf(_str(attempt['mode'] ?? j['mode'] ?? test['mode'])),
      status: _str(attempt['status'] ?? j['status'], 'in_progress'),
      questions: _rows(j['questions']).map(Question.fromJson).toList(),
      answers: answers,
      bookmarks: (j['bookmarks'] is List)
          ? (j['bookmarks'] as List).map((e) => e.toString()).toSet()
          : <String>{},
      endsAt: _date(_pick(j, ['endsAt', 'ends_at'])),
      serverNow: _date(_pick(j, ['serverNow', 'server_now'])),
      title: _str(test['title'] ?? j['title']),
      courseCode: _str(course['code'] ?? _pick(j, ['course_code'])),
      courseTitle: _str(course['title'] ?? _pick(j, ['course_title'])),
      courseId: _str(course['id'] ?? _pick(j, ['course_id'])),
      violations: _int(attempt['violations'] ?? j['violations']),
    );
  }
}

@immutable
class GivenAnswer {
  final String choice;
  final String? answerText;
  final bool? isCorrect;

  const GivenAnswer({this.choice = '', this.answerText, this.isCorrect});

  bool get isAnswered =>
      choice.isNotEmpty || (answerText ?? '').trim().isNotEmpty;

  factory GivenAnswer.fromJson(Map<String, dynamic> j) => GivenAnswer(
        choice: _str(j['choice']),
        answerText: _pick(j, ['answer_text', 'answerText'])?.toString(),
        isCorrect: _boolOrNull(
            j['is_correct'] ?? j['isCorrect'] ?? j['correct']),
      );
}

/// What the server returns after a practice answer is committed.
/// Attempt ids the app minted itself, for a round taken with no signal.
const String kLocalAttemptPrefix = 'offline-';

bool isLocalAttempt(String id) => id.startsWith(kLocalAttemptPrefix);

/// The server's own comparison, transcribed.
///
/// `normalizeShortAnswer` in the website's src/lib/attempts.ts:114 —
/// lowercase, collapse runs of whitespace, strip surrounding
/// punctuation. Marking offline has to agree with marking online to the
/// letter, or the same typed answer is right on Wi-Fi and wrong on the
/// bus, and a student loses faith in the whole thing.
String normalizeShortAnswer(String v) => v
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp('^[\\s.,;:!?\'"()-]+|[\\s.,;:!?\'"()-]+\$'), '')
    .trim();

/// Marks one answer on the device. Mirrors `isAnswerCorrect`
/// (src/lib/attempts.ts:122): a typed answer matches any of the
/// pipe-separated accepted spellings; everything else compares the key.
bool gradeLocally(Question q, {String choice = '', String answerText = ''}) {
  if (q.type == QuestionType.shortAnswer) {
    final given = normalizeShortAnswer(answerText);
    if (given.isEmpty) return false;
    return (q.answerText ?? '')
        .split('|')
        .map(normalizeShortAnswer)
        .where((a) => a.isNotEmpty)
        .contains(given);
  }
  final key = q.correctKey ?? '';
  if (key.isEmpty) return false;
  return choice == key;
}

@immutable
class AnswerVerdict {
  final bool correct;
  final String? correctKey;
  final String? acceptedAnswer;
  final String? explanationHtml;
  final String? explanationImageUrl;
  final String? explanationAudioUrl;
  final DateTime? endsAt;
  final DateTime? serverNow;
  final bool timeUp;

  const AnswerVerdict({
    this.correct = false,
    this.correctKey,
    this.acceptedAnswer,
    this.explanationHtml,
    this.explanationImageUrl,
    this.explanationAudioUrl,
    this.endsAt,
    this.serverNow,
    this.timeUp = false,
  });

  factory AnswerVerdict.fromJson(Map<String, dynamic> j) => AnswerVerdict(
        correct: _bool(_pick(j, ['correct', 'is_correct', 'isCorrect'])),
        correctKey: _pick(j, ['correctKey', 'correct_key'])?.toString(),
        acceptedAnswer:
            _pick(j, ['acceptedAnswer', 'answer_text', 'answerText'])?.toString(),
        explanationHtml:
            _pick(j, ['explanationHtml', 'explanation_html'])?.toString(),
        explanationImageUrl:
            _pick(j, ['explanationImageUrl', 'explanation_image_url'])?.toString(),
        explanationAudioUrl:
            _pick(j, ['explanationAudioUrl', 'explanation_audio_url'])?.toString(),
        endsAt: _date(_pick(j, ['endsAt', 'ends_at'])),
        serverNow: _date(_pick(j, ['serverNow', 'server_now'])),
        timeUp: _str(j['error']) == 'time_up',
      );
}

/// The full post-attempt review.
@immutable
class ResultReview {
  final String attemptId;
  final int score;
  final int total;
  final AttemptMode mode;
  final String title;
  final String courseCode;
  final String courseId;
  final int violations;
  final Duration? timeUsed;
  final int? beatPercent;
  final List<ReviewItem> items;

  const ResultReview({
    required this.attemptId,
    required this.score,
    required this.total,
    required this.mode,
    this.title = '',
    this.courseCode = '',
    this.courseId = '',
    this.violations = 0,
    this.timeUsed,
    this.beatPercent,
    this.items = const [],
  });

  int get percent => total <= 0 ? 0 : ((score / total) * 100).round();

  String get verdict => percent >= 70
      ? 'Distinction energy.'
      : percent >= 50
          ? 'Solid. Now sharpen the misses.'
          : 'Rough one. The review below fixes it.';

  factory ResultReview.fromJson(Map<String, dynamic> j) {
    final secs = j['timeUsedSeconds'] ?? j['time_used_seconds'];
    return ResultReview(
      attemptId: _str(_pick(j, ['attemptId', 'attempt_id', 'id'])),
      score: _int(j['score']),
      total: _int(j['total']),
      mode: attemptModeOf(_str(j['mode'])),
      title: _str(j['title']),
      courseCode: _str(_pick(j, ['courseCode', 'course_code'])),
      courseId: _str(_pick(j, ['courseId', 'course_id'])),
      violations: _int(j['violations']),
      timeUsed: secs == null ? null : Duration(seconds: _int(secs)),
      beatPercent: j['beat'] == null ? null : _int(j['beat']),
      items: _rows(j['items']).map(ReviewItem.fromJson).toList(),
    );
  }
}

@immutable
class ReviewItem {
  final int n;
  final Question question;
  final String? yourKey;
  final String? yourText;
  final bool isCorrect;
  final bool answered;
  final bool bookmarked;

  const ReviewItem({
    required this.n,
    required this.question,
    this.yourKey,
    this.yourText,
    this.isCorrect = false,
    this.answered = false,
    this.bookmarked = false,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> j) {
    final yk = _pick(j, ['your_key', 'yourKey', 'choice'])?.toString();
    final yt = _pick(j, ['your_text', 'yourText', 'answer_text'])?.toString();
    return ReviewItem(
      n: _int(j['n']),
      question: Question.fromJson(j),
      yourKey: yk,
      yourText: yt,
      isCorrect: _bool(_pick(j, ['is_correct', 'isCorrect'])),
      answered: (yk != null && yk.isNotEmpty) ||
          (yt != null && yt.trim().isNotEmpty),
      bookmarked: _bool(j['bookmarked']),
    );
  }
}

// ============================================================
// Dashboard, gamification & social
// ============================================================

@immutable
class Quote {
  final String content;
  final String author;
  const Quote(this.content, this.author);

  static const fallback = Quote(
    'Success is the sum of small efforts repeated day in and day out.',
    'Robert Collier',
  );

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        _str(j['content'], fallback.content),
        _str(j['author'], fallback.author),
      );
}

@immutable
class ResumeCard {
  final String attemptId;
  final AttemptMode mode;
  final String courseCode;

  const ResumeCard({
    required this.attemptId,
    required this.mode,
    this.courseCode = '',
  });

  bool get isTimed => mode.isTimed;

  factory ResumeCard.fromJson(Map<String, dynamic> j) => ResumeCard(
        attemptId: _str(_pick(j, ['id', 'attemptId'])),
        mode: _str(j['kind']) == 'cbt'
            ? AttemptMode.test
            : attemptModeOf(_str(j['mode'])),
        courseCode: _str(_pick(j, ['courseCode', 'course_code'])),
      );
}

@immutable
class DashboardData {
  final String firstName;
  final int streakCurrent;
  final int streakBest;
  final Quote quote;
  final DateTime? marathonAt;
  final ResumeCard? resume;
  final int attemptsSubmitted;
  final int averagePercent;
  final int questionsAnswered;
  final int correctCount;
  final int wrongCount;
  final List<AttemptSummary> recent;
  final List<CourseAverage> courseAverages;
  final int rank;
  final int points;
  final int unreadAnnouncements;
  final List<FameEntry> wallOfFame;

  const DashboardData({
    this.firstName = '',
    this.streakCurrent = 0,
    this.streakBest = 0,
    this.quote = Quote.fallback,
    this.marathonAt,
    this.resume,
    this.attemptsSubmitted = 0,
    this.averagePercent = 0,
    this.questionsAnswered = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.recent = const [],
    this.courseAverages = const [],
    this.rank = 0,
    this.points = 0,
    this.unreadAnnouncements = 0,
    this.wallOfFame = const [],
  });

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final streak = j['streak'] is Map
        ? Map<String, dynamic>.from(j['streak'])
        : const {};
    final stats =
        j['stats'] is Map ? Map<String, dynamic>.from(j['stats']) : j;
    return DashboardData(
      firstName: _str(_pick(j, ['firstName', 'first_name'])),
      streakCurrent: _int(streak['current'] ?? streak['current_streak']),
      streakBest: _int(streak['best'] ?? streak['best_streak']),
      quote: j['quote'] is Map
          ? Quote.fromJson(Map<String, dynamic>.from(j['quote']))
          : Quote.fallback,
      marathonAt: _date(_pick(j, ['marathonIso', 'marathon_at'])),
      resume: j['resume'] is Map
          ? ResumeCard.fromJson(Map<String, dynamic>.from(j['resume']))
          : null,
      attemptsSubmitted:
          _int(_pick(stats, ['attemptsSubmitted', 'attempts_submitted'])),
      averagePercent: _int(_pick(stats, ['averagePercent', 'average_percent'])),
      questionsAnswered:
          _int(_pick(stats, ['questionsAnswered', 'questions_answered'])),
      correctCount: _int(_pick(stats, ['correctCount', 'correct_count'])),
      wrongCount: _int(_pick(stats, ['wrongCount', 'wrong_count'])),
      recent: _rows(j['recent']).map(AttemptSummary.fromJson).toList(),
      courseAverages:
          _rows(j['courseAverages'] ?? j['course_averages'])
              .map(CourseAverage.fromJson)
              .toList(),
      rank: _int(j['rank']),
      points: _int(j['points']),
      unreadAnnouncements:
          _int(_pick(j, ['unreadAnnouncements', 'unread_announcements'])),
      wallOfFame: _rows(j['wallOfFame'] ?? j['wall_of_fame'])
          .map(FameEntry.fromJson)
          .toList(),
    );
  }
}

@immutable
class CourseAverage {
  final String code;
  final int average;
  const CourseAverage(this.code, this.average);

  factory CourseAverage.fromJson(Map<String, dynamic> j) => CourseAverage(
        _str(_pick(j, ['code', 'label'])),
        _int(_pick(j, ['average', 'value'])),
      );
}

@immutable
class FameEntry {
  final String username;
  final int percent;
  const FameEntry(this.username, this.percent);

  factory FameEntry.fromJson(Map<String, dynamic> j) => FameEntry(
        _str(_pick(j, ['username', 'name'])),
        _int(_pick(j, ['percent', 'pct'])),
      );
}

@immutable
class LeaderRow {
  final int rank;
  final String username;
  final String fullName;
  final int total;
  final bool isMe;

  const LeaderRow({
    required this.rank,
    required this.username,
    this.fullName = '',
    this.total = 0,
    this.isMe = false,
  });

  factory LeaderRow.fromJson(Map<String, dynamic> j, {String? meId}) =>
      LeaderRow(
        rank: _int(j['rank']),
        username: _str(j['username']),
        fullName: _str(_pick(j, ['name', 'full_name'])),
        total: _int(_pick(j, ['total', 'points', 'pts'])),
        isMe: meId != null && _str(_pick(j, ['user_id', 'id'])) == meId,
      );
}

@immutable
class TestRanking {
  final int rank;
  final String username;
  final int score;
  final int total;
  final int percent;
  final DateTime? submittedAt;
  final bool isMe;

  const TestRanking({
    required this.rank,
    required this.username,
    this.score = 0,
    this.total = 0,
    this.percent = 0,
    this.submittedAt,
    this.isMe = false,
  });

  factory TestRanking.fromJson(Map<String, dynamic> j, {String? meId}) =>
      TestRanking(
        rank: _int(j['rank']),
        username: _str(j['username']),
        score: _int(j['score']),
        total: _int(j['total']),
        percent: _int(_pick(j, ['percent', 'pct'])),
        submittedAt: _date(_pick(j, ['submitted_at', 'submittedAt'])),
        isMe: meId != null && _str(_pick(j, ['user_id', 'id'])) == meId,
      );
}

@immutable
class LeagueRow {
  final int rank;
  final String username;
  final int points;
  final int attempts;
  final bool isMe;

  const LeagueRow({
    required this.rank,
    required this.username,
    this.points = 0,
    this.attempts = 0,
    this.isMe = false,
  });

  factory LeagueRow.fromJson(Map<String, dynamic> j, {String? meId}) =>
      LeagueRow(
        rank: _int(j['rank']),
        username: _str(_pick(j, ['username', 'name'])),
        points: _int(_pick(j, ['points', 'pts'])),
        attempts: _int(_pick(j, ['attempts', 'n'])),
        isMe: meId != null && _str(_pick(j, ['user_id', 'id'])) == meId,
      );
}

@immutable
class MillionaireWinner {
  final String username;
  final int won;
  final bool crowned;
  const MillionaireWinner(this.username, this.won, this.crowned);

  factory MillionaireWinner.fromJson(Map<String, dynamic> j) =>
      MillionaireWinner(
        _str(_pick(j, ['username', 'name'])),
        _int(j['won']),
        _bool(j['crowned']),
      );
}

@immutable
class Announcement {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool unread;
  final bool isActive;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.createdAt,
    this.unread = false,
    this.isActive = true,
  });

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        createdAt: _date(_pick(j, ['created_at', 'createdAt'])),
        unread: _bool(j['unread']),
        isActive: _bool(_pick(j, ['is_active', 'isActive']), true),
      );
}

@immutable
class WeakSpot {
  final String courseId;
  final String code;
  final String title;
  final int missed;

  const WeakSpot({
    required this.courseId,
    required this.code,
    required this.title,
    required this.missed,
  });

  factory WeakSpot.fromJson(Map<String, dynamic> j) => WeakSpot(
        courseId: _str(_pick(j, ['course_id', 'courseId'])),
        code: _str(j['code']),
        title: _str(j['title']),
        missed: _int(_pick(j, ['missed', 'count'])),
      );
}

@immutable
class StudyLevel {
  final String code;
  final String title;
  final bool owned;

  const StudyLevel({required this.code, required this.title, this.owned = false});

  factory StudyLevel.fromJson(Map<String, dynamic> j) => StudyLevel(
        code: _str(j['code']),
        title: _str(j['title']),
        owned: _bool(j['owned']),
      );
}

@immutable
class DailyChallenge {
  final String id;
  final String day;
  final Question question;

  const DailyChallenge({
    required this.id,
    required this.day,
    required this.question,
  });

  factory DailyChallenge.fromJson(Map<String, dynamic> j) => DailyChallenge(
        id: _str(j['id']),
        day: _str(j['day']),
        question: Question.fromJson(j),
      );
}

/// Thrown by the data layer with a message already fit to show a student.
class BxError implements Exception {
  final String message;
  final String? code;
  const BxError(this.message, {this.code});

  @override
  String toString() => message;

  static const notActivated = BxError(
    'Activate your account to open this.',
    code: 'not_activated',
  );
  static const offline = BxError(
    'No connection. Check your data or Wi-Fi and try again.',
    code: 'offline',
  );
}

/// A resolved connection state used by the offline banner.
enum NetState { online, offline, checking }

double dbl(dynamic v) => _dbl(v);
int intOf(dynamic v) => _int(v);

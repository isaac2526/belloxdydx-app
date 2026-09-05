import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../backend.dart';
import '../failures.dart';
import '../models.dart';
import '../repositories.dart';
import 'offline_store.dart';
import 'content_keys.dart' show sigFor, urlsInHtml, utf8Length;

/// ============================================================
/// DOWNLOADING ONE WHOLE COURSE
///
/// "every course should have its own download materials button and it
///  must download all the materials ... Even questions oo, it should
///  pull everything ... it must be sure that everything was downloaded
///  even we must be seeing the progress of the downloading"
///
/// This is that button's engine, and it is a different thing from the
/// background sync next door. The sync is careful with a student's data
/// bundle because the student did not ask for it: it is size-capped,
/// budgeted, Wi-Fi-gated and quiet. This one was asked for by name, so
/// it takes the caps off, it says exactly what it is doing, and it
/// checks its own work.
///
/// Three properties it must have, because each one is a complaint:
///
///   1. **It really pulls everything.** Notes with their bodies, slides
///      and past questions as whole files, every picture and voice note
///      inside any of them, and the entire question bank for the course
///      with the answer keys — because a question whose key never
///      reached the phone cannot be marked on the phone.
///
///   2. **It checks.** "it must be sure that everything was downloaded"
///      is not rhetoric. Every note, document and picture is read back
///      off the disk after the run, and the question bucket is counted.
///      Anything that did not land is reported as a number, not hidden
///      behind a green tick. A course that only half arrived keeps
///      asking to be downloaded.
///
///   3. **It shows progress.** Item by item, with the name of what is
///      being fetched, so a student on a slow line can see it moving.
///
/// What it does NOT do is fetch videos. Those are streamed from
/// elsewhere and are not ours to put on a phone.
/// ============================================================

/// Per-file ceiling. Generous — the student asked for this one by name —
/// but not unbounded: a single corrupt row pointing at a two-gigabyte
/// file must not fill the phone.
const int _maxFile = 200 * 1024 * 1024;

/// How many pages of the bundle to ask for at once.
const int _page = 200;

/// Transfers in flight. Three hides latency on a Nigerian mobile
/// connection without starving the UI thread.
const int _workers = 3;

enum CourseDownloadPhase {
  /// Never downloaded, or the record was thrown away.
  idle,

  /// Asking the server what it has.
  checking,

  /// Fetching.
  running,

  /// Everything the server offered is on the phone.
  done,

  /// Some of it is not, and the state says how much.
  failed,

  /// The student stopped it.
  cancelled,
}

/// One file that did not land, by name and with the reason — so the
/// card can say "Episode 2 · not found on the server" rather than a
/// bare "6 files did not save" the student can do nothing with.
@immutable
class CourseDownloadFailure {
  final String title;
  final String reason;

  const CourseDownloadFailure({required this.title, required this.reason});

  factory CourseDownloadFailure.fromJson(Map<dynamic, dynamic> j) =>
      CourseDownloadFailure(
        title: '${j['title'] ?? ''}',
        reason: '${j['reason'] ?? ''}',
      );

  Map<String, String> toJson() => {'title': title, 'reason': reason};

  /// "Episode 2 (not found on the server)"
  String get line => reason.isEmpty ? title : '$title ($reason)';
}

@immutable
class CourseDownloadState {
  final String courseId;
  final CourseDownloadPhase phase;

  /// What is being fetched right now, in words a student reads.
  final String label;

  final int done;
  final int total;
  final int bytes;
  final int failed;

  /// How many questions landed in the bucket for this course.
  final int questions;

  /// How many notes, slides and past-question files landed.
  final int materials;

  /// How many pictures and voice notes landed.
  final int assets;

  /// Set only on failure, and only ever from the closed fault set.
  final String? message;

  /// What did not save last time, by name. Empty when everything did.
  final List<CourseDownloadFailure> failures;

  /// True when the server is publishing something this phone does not
  /// hold. This is the "there's a change in this course, download now"
  /// badge.
  final bool updateAvailable;

  /// True once this course has been downloaded whole at least once.
  final bool held;

  /// When it was last downloaded, or 0.
  final int savedAtMs;

  /// When TUTOR BELLO last changed any part of this course, as an ISO
  /// string, or empty.
  ///
  /// Deliberately separate from [savedAtMs] and deliberately the one
  /// the student is shown. "You downloaded this on Tuesday" answers a
  /// question nobody asked; "Tutor Bello last updated this on Tuesday"
  /// is the one they actually have.
  final String updatedAt;

  const CourseDownloadState({
    required this.courseId,
    this.phase = CourseDownloadPhase.idle,
    this.label = '',
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
    this.failed = 0,
    this.questions = 0,
    this.materials = 0,
    this.assets = 0,
    this.message,
    this.failures = const [],
    this.updateAvailable = false,
    this.held = false,
    this.savedAtMs = 0,
    this.updatedAt = '',
  });

  bool get isRunning =>
      phase == CourseDownloadPhase.running ||
      phase == CourseDownloadPhase.checking;

  double get progress =>
      total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  /// What the button says.
  String get action {
    if (isRunning) return 'Downloading…';
    if (updateAvailable && held) return 'Update';
    if (held) return 'Downloaded';
    return 'Download';
  }

  CourseDownloadState copyWith({
    CourseDownloadPhase? phase,
    String? label,
    int? done,
    int? total,
    int? bytes,
    int? failed,
    int? questions,
    int? materials,
    int? assets,
    String? message,
    List<CourseDownloadFailure>? failures,
    bool? updateAvailable,
    bool? held,
    int? savedAtMs,
    String? updatedAt,
    bool clearMessage = false,
  }) =>
      CourseDownloadState(
        courseId: courseId,
        phase: phase ?? this.phase,
        label: label ?? this.label,
        done: done ?? this.done,
        total: total ?? this.total,
        bytes: bytes ?? this.bytes,
        failed: failed ?? this.failed,
        questions: questions ?? this.questions,
        materials: materials ?? this.materials,
        assets: assets ?? this.assets,
        message: clearMessage ? null : (message ?? this.message),
        failures: clearMessage ? const [] : (failures ?? this.failures),
        updateAvailable: updateAvailable ?? this.updateAvailable,
        held: held ?? this.held,
        savedAtMs: savedAtMs ?? this.savedAtMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// One unit of transfer inside a course download.
class _Unit {
  final String kind; // note | doc | asset
  final String id;
  final String url;
  final StudyMaterial? material;

  /// For an asset: what it belongs to, in words — "a picture in Newton's
  /// laws", "the PDF attached to Episode II" — so a failure can be
  /// named on the card.
  final String owner;

  const _Unit.note(this.material)
      : kind = 'note',
        id = '',
        url = '',
        owner = '';
  const _Unit.doc(this.material)
      : kind = 'doc',
        id = '',
        url = '',
        owner = '';
  const _Unit.asset(this.url, {this.owner = ''})
      : kind = 'asset',
        id = '',
        material = null;

  String get key => kind == 'asset' ? url : (material?.id ?? id);

  /// The name a student would recognise, and a DIFFERENT one for each
  /// file — a list that says "a picture on a question" three times
  /// names nothing.
  ///
  /// Uri.pathSegments is already decoded, so decoding it again is not
  /// only redundant: it throws on a file Tutor Bello named with a per
  /// cent sign in it, and that throw came out of the worker and took
  /// the whole download with it.
  String get title {
    if (kind != 'asset') return material?.title ?? '';
    if (owner.isNotEmpty) return owner;
    final last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    return last.isEmpty ? 'A picture' : last;
  }
}

/// What one transfer came to: whether it is on the disk, how many
/// bytes moved, and — when it is not — the reason in words.
typedef _Outcome = ({bool ok, int bytes, String? reason});

const _Outcome _held = (ok: true, bytes: 0, reason: null);

_Outcome _lost(String reason) => (ok: false, bytes: 0, reason: reason);

class CourseDownloader {
  CourseDownloader({
    required Backend backend,
    required ContentRepository content,
    required OfflineStore? store,
    required this.courseId,
    http.Client? httpClient,
  })  : _b = backend,
        _content = content,
        _store = store,
        _given = httpClient;

  final Backend _b;
  final ContentRepository _content;
  final OfflineStore? _store;
  final String courseId;

  /// Built on the first transfer, not on construction.
  ///
  /// Every tile on the course shelf watches its own downloader so it
  /// can show a chip, so a twenty-two course shelf builds twenty-two of
  /// these — and twenty-one of them will never fetch anything. A client
  /// nobody uses should not cost a client.
  final http.Client? _given;
  http.Client? _made;
  http.Client get _http => _given ?? (_made ??= http.Client());

  final _controller = StreamController<CourseDownloadState>.broadcast();
  Stream<CourseDownloadState> get updates => _controller.stream;

  late CourseDownloadState _state = _fromRecord();
  CourseDownloadState get state => _state;

  bool _cancelled = false;
  Future<void>? _inFlight;

  /// Set the first time a write is refused for want of space, so the
  /// record can say THAT rather than a generic failure — and so the
  /// next launch does not report it as a change Tutor Bello made.
  String? _outOfRoom;

  void _emit(CourseDownloadState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  /// What the phone already knows, read with no network and no await —
  /// so a course hub opens with a truthful button in its first frame
  /// rather than a spinner that resolves into one.
  CourseDownloadState _fromRecord() {
    final rec = _store?.courseRecord(courseId);
    if (rec == null) {
      return CourseDownloadState(courseId: courseId);
    }
    final ok = rec['ok'] == true;
    int held(String key, String fallback) =>
        (rec[key] as num?)?.toInt() ?? (rec[fallback] as num?)?.toInt() ?? 0;
    final failures = ok
        ? const <CourseDownloadFailure>[]
        : [
            for (final f in (rec['failures'] as List? ?? const []))
              if (f is Map) CourseDownloadFailure.fromJson(f),
          ];
    final failed = (rec['failed'] as num?)?.toInt() ?? failures.length;
    final reason = '${rec['reason'] ?? ''}';
    return CourseDownloadState(
      courseId: courseId,
      phase: ok ? CourseDownloadPhase.done : CourseDownloadPhase.failed,
      held: true,
      // What is ON THE PHONE, not what the server has. Records written
      // by an older build carry only the server's numbers, so those are
      // the fallback.
      questions: held('heldQuestions', 'questions'),
      materials: held('heldFiles', 'materials'),
      assets: held('heldAssets', 'assets'),
      bytes: (rec['bytes'] as num?)?.toInt() ?? 0,
      savedAtMs: (rec['at'] as num?)?.toInt() ?? 0,
      updatedAt: '${rec['stamp'] ?? ''}',
      // NOT `updateAvailable: !ok`.
      //
      // A file that can never be fetched — deleted from the bucket, a
      // dead URL, over the size cap, a full phone — latched ok:false
      // into the record, and the card then told the student, in Tutor
      // Bello's name, every launch for ever, that he had changed
      // something. He had not. A run that did not finish says so in its
      // own words instead, and offers to try again.
      failed: ok ? 0 : failed,
      // By name where the names were kept. The generic sentence is
      // only for a record an older build wrote, or a run the store
      // itself stopped — and the store writes its own sentence.
      message: ok
          ? null
          : (failures.isNotEmpty && (reason.isEmpty || reason == 'incomplete'))
              ? failureMessage(failed > 0 ? failed : failures.length, failures)
              : _whyItStopped(reason),
      failures: failures,
    );
  }

  static String _whyItStopped(String reason) {
    if (reason.isEmpty || reason == 'incomplete') {
      return 'Some of this course did not save last time. Tap Update on a '
          'steadier connection and only the missing pieces are fetched.';
    }
    // Anything else came from the store, which writes sentences.
    return reason;
  }

  /// The sentence under the card when a run did not land everything:
  /// how many, WHICH ones, and what to do. A number on its own — "6
  /// files did not save", every time, however steady the line — was
  /// the whole of what a student could see, and it turned out to be
  /// six notes that had no body yet and were never missing at all.
  @visibleForTesting
  static String failureMessage(int count, List<CourseDownloadFailure> named) {
    final noun = count == 1 ? 'file' : 'files';
    final buf = StringBuffer('$count $noun did not save');
    if (named.isNotEmpty) {
      final shown = named.take(3).map((f) => f.line).toList();
      // Counted against the HEADLINE, not against the list — the list
      // is capped when it is written to disk, so "and 17 more" under a
      // headline of 114 was a sentence contradicting itself.
      final more = count - shown.length;
      buf.write(': ${shown.join(' · ')}');
      if (more > 0) buf.write(' and $more more');
    }
    buf.write('. Tap Update on a steadier connection and only the missing '
        'ones are fetched.');
    return buf.toString();
  }

  /// A thrown error, in the words the card uses.
  static String _reasonFor(Object e) {
    final fault = classify(e);
    return switch (fault) {
      BxFault.offline => 'no connection',
      BxFault.timeout => 'the connection dropped',
      BxFault.notFound => 'not found on the server',
      _ => 'did not save',
    };
  }

  /// Folds a fresh manifest row in without downloading anything. This
  /// is what raises the badge.
  void applyStamp(CourseStamp? stamp) {
    if (_state.isRunning) return;
    if (stamp == null) return;
    final rec = _store?.courseRecord(courseId);
    _emit(_state.copyWith(
      updateAvailable: stamp.differsFrom(rec) && !stamp.isEmpty,
      held: rec != null,
      // Kept current even when nothing is downloaded, so a course a
      // student has not taken offline still says when it last changed.
      updatedAt: stamp.stamp,
    ));
  }

  void cancel() => _cancelled = true;

  Future<void> dispose() async {
    _cancelled = true;
    _made?.close();
    await _controller.close();
  }

  /// Runs, or joins the run already going.
  Future<void> run() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final f = _run().whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  Future<void> _run() async {
    final store = _store;
    if (store == null) {
      _emit(_state.copyWith(
        phase: CourseDownloadPhase.failed,
        message: 'This device cannot keep offline copies.',
      ));
      return;
    }

    _cancelled = false;
    _outOfRoom = null;
    _emit(_state.copyWith(
      phase: CourseDownloadPhase.checking,
      label: 'Checking what has changed',
      done: 0,
      total: 0,
      bytes: 0,
      failed: 0,
      clearMessage: true,
    ));

    try {
      // The manifest row is read FIRST and recorded LAST, so a question
      // Tutor Bello adds while the download is running shows up as a
      // change next time rather than being silently marked as held.
      final stamp = await _stampForCourse();

      final materials = await _fetchMaterials(store);
      if (_cancelled) return _stopped();

      final questionRows = await _fetchQuestions(store);
      if (_cancelled) return _stopped();

      // One `wanted` set across both halves. The same diagram is
      // routinely referenced by a note AND by a question about it, and
      // two workers downloading it at once is a wasted transfer on a
      // student's bundle.
      // Every picture, voice note and attachment this course points
      // at, whether or not it still has to be fetched. What is on the
      // phone is counted from THIS after the run — a run only knows
      // what it moved, and an Update that found every picture already
      // here used to report "0 pictures" over a phone full of them.
      final referenced = <String>{};
      final wanted = <String>{};
      final units = _plan(store, materials, wanted, referenced)
        // The pictures on the questions are planned from the BANK, not
        // from the pages that just arrived, so a re-download picks up a
        // diagram that failed last time even when its question row has
        // not changed since.
        ..addAll(await _questionAssets(store, wanted, referenced));
      // The catalogue said these were here. The disk gets the last word:
      // anything it cannot find is forgotten and fetched again now,
      // rather than trusted for ever.
      units.addAll(await _reclaim(store, referenced, wanted));
      _emit(_state.copyWith(
        phase: CourseDownloadPhase.running,
        total: units.length,
        done: 0,
        label: units.isEmpty ? 'Checking your copy' : 'Saving your material',
      ));

      var done = 0;
      var bytes = 0;
      var failed = 0;
      final failures = <CourseDownloadFailure>[];
      // Keyed by URL for a picture and by material id for a file, so a
      // file that fails in the worker is not counted AGAIN by the check
      // at the end — which is how one missing attachment came to read
      // as "2 files did not save".
      final failedKeys = <String>{};
      final queue = List<_Unit>.from(units);

      // WHAT THE PHONE HOLDS, KEPT AS A RUNNING TALLY.
      //
      // These two numbers used to be recomputed from scratch on every
      // completed unit — a SHA-1 per referenced picture and a walk of
      // the whole catalogue, three times a unit, on the UI isolate of
      // a cheap phone. Counted once here and added to as things land.
      final heldAssets = <String>{
        for (final u in referenced)
          if (store.hasAsset(u)) canonicalAssetUrl(u),
      };
      final heldFiles = store.heldFileIdsFor(courseId).toSet();

      void lost(_Unit unit, String reason) {
        failed++;
        failedKeys.add(unit.key);
        failures.add(CourseDownloadFailure(title: unit.title, reason: reason));
        debugPrint('[course] ${unit.kind} ${unit.key}: $reason');
      }

      Future<void> worker() async {
        while (!_cancelled && queue.isNotEmpty) {
          final unit = queue.removeAt(0);
          try {
            // Read into a local and add afterwards. `bytes += await …`
            // reads the counter, suspends, and writes back a value
            // three workers may all have read before any of them wrote.
            final out = await _perform(unit, store);
            if (out.ok) {
              bytes += out.bytes;
              if (unit.kind == 'asset') {
                heldAssets.add(canonicalAssetUrl(unit.url));
              } else {
                heldFiles.add(unit.key);
              }
            } else {
              lost(unit, out.reason ?? 'did not save');
            }
          } catch (e) {
            lost(unit, _reasonFor(e));
          }
          done++;
          _emit(_state.copyWith(
            done: done,
            bytes: bytes,
            failed: failed,
            failures: List.unmodifiable(failures),
            assets: heldAssets.length,
            materials: heldFiles.length,
            label: _labelFor(unit),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
      await store.flush();
      if (_cancelled) return _stopped();

      // ---- drop what Tutor Bello withdrew ------------------------
      //
      // The bank only ever merged, so a question he unpublished or
      // deleted stayed here for ever — practisable, with its answer
      // key, long after he had decided it was wrong. Same for a note or
      // a paper. Pruned only against a list the server confirmed
      // COMPLETE: a read that failed must never be read as "the course
      // is empty, delete everything".
      if (!_cancelled) {
        _emit(_state.copyWith(label: 'Clearing what was withdrawn'));
        try {
          final index = await _content.courseIndex(courseId);
          if (index.isUsable) {
            await store.pruneQuestions(courseId, index.questionIds);
            if (index.materialIds.isNotEmpty) {
              await store.pruneMaterials(courseId, index.materialIds);
            }
          }
        } catch (e) {
          debugPrint('[course] could not prune: $e');
        }
      }

      // ---- the cross-check ---------------------------------------
      //
      // "it must be sure that everything was downloaded". Not the
      // catalogue's opinion — the disk's. Every note, file and picture
      // this run went for is read back, and the question bucket is
      // counted against what the server said it was sending.
      _emit(_state.copyWith(label: 'Checking every file', done: units.length));
      // NOT questionRows - dropped: everything saved in this run came
      // from the server moments ago, so it is in the alive set and none
      // of it can have been pruned. Subtracting would only weaken the
      // check.
      final missing =
          await _verify(store, units, questionRows, failures, failedKeys);
      // Now that this course's attachments are on the phone as assets,
      // any duplicate a previous build left under a note's own id can
      // go. It is the same bytes twice, and putNote rewrote the row's
      // size to the length of the body — so those megabytes had also
      // stopped counting against the library ceiling while still
      // sitting on the disk.
      await _dropLegacyDocuments(store, materials);
      final heldQuestions = (await store.questions(courseId)).length;
      // Counted off the catalogue and the disk AFTER the run, so the
      // number is what the phone holds, not what this run happened to
      // move. One pass, once, rather than the running tally the
      // progress line used.
      final finalFiles = store.heldFilesFor(courseId);
      final finalAssets = referenced.where(store.hasAsset).length;

      final ok = missing == 0 && failed == 0;
      await store.putCourseRecord(
        courseId,
        // What actually landed, kept apart from what the server has.
        heldQuestions: heldQuestions,
        heldFiles: finalFiles,
        heldAssets: finalAssets,
        reason: ok ? '' : (_outOfRoom ?? 'incomplete'),
        failed: failed + missing,
        failures: [for (final f in failures) f.toJson()],
        // The MANIFEST's numbers, not what we saved. They differ when
        // the server withheld a question pinned to a sitting, and
        // storing what we saved would leave the badge lit forever.
        materials: stamp?.materials ?? materials.length,
        questions: stamp?.questions ?? heldQuestions,
        tests: stamp?.tests ?? 0,
        pins: stamp?.pins ?? 0,
        pinPrint: stamp?.pinPrint ?? '',
        courseStamp: stamp?.courseStamp ?? '',
        stamp: stamp?.stamp ?? '',
        ok: ok,
        bytes: bytes,
      );

      _emit(_state.copyWith(
        phase: ok ? CourseDownloadPhase.done : CourseDownloadPhase.failed,
        label: ok ? 'Ready to use offline' : 'Some of it did not save',
        done: units.length,
        total: units.length,
        bytes: bytes,
        failed: failed + missing,
        questions: heldQuestions,
        materials: finalFiles,
        assets: finalAssets,
        held: true,
        updateAvailable: !ok,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAt: stamp?.stamp ?? _state.updatedAt,
        failures: List.unmodifiable(failures),
        message: ok ? null : failureMessage(failed + missing, failures),
      ));
    } catch (e) {
      _emit(_state.copyWith(
        phase: CourseDownloadPhase.failed,
        label: 'Could not download',
        message: classify(e, hasConnection: _b.hasConnection).message,
      ));
    }
  }

  void _stopped() {
    _emit(_state.copyWith(
      phase: CourseDownloadPhase.cancelled,
      label: 'Stopped',
    ));
  }

  Future<CourseStamp?> _stampForCourse() async {
    try {
      final rows = await _content.manifest();
      for (final r in rows) {
        if (r.id == courseId) return r;
      }
    } catch (e) {
      // A manifest the app could not read is not a reason to refuse a
      // download. Without it the record simply carries what was saved,
      // and the next successful manifest raises the badge if it must.
      debugPrint('[course] manifest unavailable: $e');
    }
    return null;
  }

  // ------------------------------------------------------------
  // Pulling the course down
  // ------------------------------------------------------------

  Future<List<StudyMaterial>> _fetchMaterials(OfflineStore store) async {
    final out = <StudyMaterial>[];
    var offset = 0;
    while (!_cancelled) {
      final page = await _content.courseBundle(
        courseId,
        offset: offset,
        limit: _page,
        part: 'materials',
      );
      out.addAll(page.materials);
      _emit(_state.copyWith(
        label: 'Found ${out.length} '
            '${out.length == 1 ? 'material' : 'materials'}',
      ));
      final next = page.nextOffset;
      // Stop on an empty page too: a page can be short of its limit
      // without being the last one, but an empty one never is.
      if (next == null || next <= offset || page.materials.isEmpty) break;
      offset = next;
    }
    return out;
  }

  Future<int> _fetchQuestions(OfflineStore store) async {
    var saved = 0;
    var offset = 0;
    var announced = false;
    while (!_cancelled) {
      final page = await _content.courseBundle(
        courseId,
        offset: offset,
        limit: _page,
        part: 'questions',
      );

      if (!page.questionsIncluded) {
        // Tutor Bello has switched the offline bank off for everybody.
        // Saying nothing here would look exactly like a course with no
        // questions in it.
        if (!announced) {
          _emit(_state.copyWith(
            label: 'Questions stay online for now',
          ));
          announced = true;
        }
        break;
      }

      if (page.questions.isNotEmpty) {
        // Written page by page rather than at the end, so a download
        // that is interrupted three quarters through still leaves three
        // quarters of the bank on the phone.
        // complete: these rows came whole from the bundle, so an
        // explanation Tutor Bello CLEARED really clears rather than
        // losing to the copy already held.
        await store.putQuestions(courseId, page.questions, complete: true);
        saved += page.questions.length;
        _emit(_state.copyWith(
          questions: saved,
          label: 'Saved $saved '
              '${saved == 1 ? 'question' : 'questions'}',
        ));
      }

      final next = page.nextOffset;
      if (next == null || next <= offset) break;
      // A page can come back empty because everything in it was
      // withheld, and that is not the end of the bank — only a null
      // nextOffset is.
      offset = next;
    }
    await store.flush();
    return saved;
  }

  // ------------------------------------------------------------
  // Planning what to fetch
  // ------------------------------------------------------------

  List<_Unit> _plan(
    OfflineStore store,
    List<StudyMaterial> materials,
    Set<String> wanted,
    Set<String> referenced,
  ) {
    final units = <_Unit>[];

    void wantAsset(String? url, String owner) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _b.fileUrl(url);
      if (resolved.isEmpty) return;
      referenced.add(resolved);
      if (store.hasAsset(resolved)) return;
      if (!wanted.add(canonicalAssetUrl(resolved))) return;
      units.add(_Unit.asset(resolved, owner: owner));
    }

    for (final m in materials) {
      if (m.kind == MaterialKind.note) {
        units.add(_Unit.note(m));
        for (final u in urlsInHtml(m.contentHtml)) {
          // Named after the file, so two missing pictures in the same
          // note are two lines rather than the same line twice.
          wantAsset(u, '');
        }
        // Every attachment, whatever its kind. A note whose attached
        // PDF is missing is not saved, it is half-saved — and the
        // background sync only ever took the images and the audio.
        for (final a in m.attachments) {
          wantAsset(a.url, a.title.isEmpty ? 'attached to ${m.title}' : a.title);
        }
        continue;
      }
      if (m.kind == MaterialKind.video || m.kind == MaterialKind.series) {
        // Streamed from elsewhere. Not ours to put on a phone.
        continue;
      }
      if (m.url.isEmpty) continue;
      final ext = extensionForUrl(m.url, fallback: '');
      if (const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        wantAsset(m.url, m.title);
        continue;
      }
      units.add(_Unit.doc(m));
    }

    return units;
  }

  /// Re-checks, on the disk, every asset the catalogue claims to hold
  /// for this course. Whatever is not really there is forgotten and
  /// planned again, so a phone whose files were cleared behind the
  /// app's back gets them back on the next Update instead of reporting
  /// "on this phone" over a hole.
  Future<List<_Unit>> _reclaim(
    OfflineStore store,
    Set<String> referenced,
    Set<String> wanted,
  ) async {
    final units = <_Unit>[];
    for (final url in referenced) {
      if (_cancelled) break;
      if (!store.hasAsset(url)) continue;
      if (await store.verifyAsset(url)) continue;
      await store.forgetAsset(url);
      if (wanted.add(canonicalAssetUrl(url))) units.add(_Unit.asset(url));
    }
    return units;
  }

  /// Every picture and voice note on the questions this course holds.
  ///
  /// Run after the bank is written rather than from the pages, so a
  /// re-download picks up a diagram that failed to arrive last time
  /// even when the question row itself has not changed.
  Future<List<_Unit>> _questionAssets(
    OfflineStore store,
    Set<String> wanted,
    Set<String> referenced,
  ) async {
    final units = <_Unit>[];

    void wantAsset(String? url) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _b.fileUrl(url);
      if (resolved.isEmpty) return;
      referenced.add(resolved);
      if (store.hasAsset(resolved)) return;
      if (!wanted.add(canonicalAssetUrl(resolved))) return;
      // No owner: the file's own name is what tells one missing
      // diagram from another in the "did not save" sentence, and the
      // progress label falls back to friendly words on its own.
      units.add(_Unit.asset(resolved));
    }

    for (final row in await store.questions(courseId)) {
      for (final key in const [
        'question_image_url',
        'question_audio_url',
        'explanation_image_url',
        'explanation_audio_url',
      ]) {
        final v = row[key];
        if (v is String) wantAsset(v);
      }
      for (final key in const ['question_html', 'explanation_html']) {
        final v = row[key];
        if (v is String) {
          for (final u in urlsInHtml(v)) {
            wantAsset(u);
          }
        }
      }
      // Options carry pictures too — a chemistry question whose four
      // structures are images is unusable without them.
      final options = row['options'];
      if (options is List) {
        for (final o in options.whereType<Map>()) {
          final v = o['image_url'] ?? o['imageUrl'];
          if (v is String) wantAsset(v);
        }
      }
    }
    return units;
  }

  // ------------------------------------------------------------
  // Doing the work
  // ------------------------------------------------------------

  String _labelFor(_Unit u) => switch (u.kind) {
        'note' => u.title.isEmpty ? 'Notes' : u.title,
        'asset' => u.owner.isEmpty ? 'Pictures and voice notes' : u.owner,
        _ => u.title.isEmpty ? 'Documents' : u.title,
      };

  Future<_Outcome> _perform(_Unit unit, OfflineStore store) =>
      switch (unit.kind) {
        'note' => _saveNote(unit.material!, store),
        'asset' => _saveAsset(unit.url, store),
        _ => _saveDoc(unit.material!, store),
      };

  /// The body already arrived with the bundle, so this costs no request
  /// at all — which is the point of sending content_html with the page.
  ///
  /// A note with NO body is saved as well, with its attachment list.
  /// It used to be skipped as "not a failure, an empty note" — and
  /// then the check at the end could not find it and counted it as a
  /// file that did not save, on every run, for ever. Six notes of a
  /// series still being written were the whole of a student's stable
  /// "6 files did not save".
  Future<_Outcome> _saveNote(StudyMaterial m, OfflineStore store) async {
    final html = m.contentHtml.trim().isEmpty ? '' : m.contentHtml;
    final course = _content.courseById(m.courseId);
    await store.putNote(
      id: m.id,
      title: m.title,
      html: html,
      courseCode: course?.code ?? '',
      courseId: m.courseId.isEmpty ? courseId : m.courseId,
      sig: sigFor(m),
      // The student asked for this course by name, so nothing in it is
      // eligible for eviction to make room for a background sync.
      pinned: true,
      attachments: [
        for (final a in m.attachments)
          OfflineAttachment(title: a.title, url: a.url, kind: a.kind),
      ],
    );
    return (ok: true, bytes: utf8Length(html), reason: null);
  }

  Future<_Outcome> _saveDoc(StudyMaterial m, OfflineStore store) async {
    final url = _b.fileUrl(m.url);
    if (store.isCurrent(m.id, sigFor(m)) &&
        store.item(m.id)?.hasDoc == true &&
        await store.verifyItem(m.id)) {
      // Already held at this exact version. Not a transfer, and not a
      // failure either.
      return _held;
    }
    final got = await _download(url, cap: _maxFile);
    final bytes = got.bytes;
    if (bytes == null) return _lost(got.reason ?? 'did not save');
    if (!await _makeRoom(store, bytes.length)) return _lost('no room left');

    final course = _content.courseById(m.courseId);
    await store.putDocument(
      id: m.id,
      title: m.title,
      kind: m.kind.name,
      bytes: bytes,
      extension: extensionForUrl(url, fallback: 'pdf'),
      courseCode: course?.code ?? '',
      courseId: m.courseId.isEmpty ? courseId : m.courseId,
      sig: sigFor(m),
      pinned: true,
      attachments: [
        for (final a in m.attachments)
          OfflineAttachment(title: a.title, url: a.url, kind: a.kind),
      ],
    );
    if (!await store.verifyItem(m.id)) return _lost('could not be written');
    return (ok: true, bytes: bytes.length, reason: null);
  }

  Future<_Outcome> _saveAsset(String url, OfflineStore store) async {
    if (url.isEmpty) return _lost('has no address');
    if (store.hasAsset(url) && await store.verifyAsset(url)) return _held;
    final got = await _download(url, cap: _maxFile);
    final bytes = got.bytes;
    if (bytes == null) return _lost(got.reason ?? 'did not save');
    if (!await _makeRoom(store, bytes.length)) return _lost('no room left');
    await store.putAsset(url, bytes);
    if (!await store.verifyAsset(url)) return _lost('could not be written');
    return (ok: true, bytes: bytes.length, reason: null);
  }

  /// Room is checked BEFORE the write, not discovered by it. A failed
  /// write on a full phone still cost the student the download.
  Future<bool> _makeRoom(OfflineStore store, int bytes) async {
    final room = await store.canWrite(bytes);
    if (room.ok) return true;
    await store.evictFor(bytes);
    final again = await store.canWrite(bytes);
    if (again.ok) return true;
    _outOfRoom = again.reason;
    _emit(_state.copyWith(message: again.reason));
    return false;
  }

  /// One transfer, with one retry. The bytes, or the reason there are
  /// none — in the words the card will use, because "did not save"
  /// told a student nothing about whether to try again or to tell
  /// Tutor Bello.
  Future<({List<int>? bytes, String? reason})> _download(
    String url, {
    required int cap,
  }) async {
    if (url.isEmpty) return (bytes: null, reason: 'has no address');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return (bytes: null, reason: 'has a broken address');
    }
    ({List<int>? bytes, String? reason}) last =
        (bytes: null, reason: 'did not save');
    for (var attempt = 0; attempt < 2 && !_cancelled; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      last = await _fetchOnce(uri, cap);
      if (last.bytes != null) return last;
      // A file the server does not have, or one too big for a phone,
      // will be exactly as absent the second time. Only a line that
      // gave out is worth asking twice.
      if (!_worthAnotherGo(last.reason)) return last;
    }
    return last;
  }

  static bool _worthAnotherGo(String? reason) =>
      reason == 'the connection dropped' ||
      reason == 'no connection' ||
      reason == 'the server refused it' ||
      reason == 'came down empty';

  /// STREAMED, WITH AN IDLE TIMEOUT RATHER THAN A TOTAL ONE.
  ///
  /// The whole request used to be given 120 seconds. On the connection
  /// this app was built for that is not a timeout, it is a size limit:
  /// a 40 MB past-question paper at 30 KB/s needs twenty minutes of
  /// perfectly healthy transfer, and it was cut off every time and
  /// reported as a file that did not save. What actually means the line
  /// is gone is bytes STOPPING — so the clock is reset by every chunk
  /// that arrives, and a slow download simply takes as long as it
  /// takes.
  Future<({List<int>? bytes, String? reason})> _fetchOnce(
    Uri uri,
    int cap,
  ) async {
    try {
      final started = DateTime.now();
      final res = await _http
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 404 || res.statusCode == 410) {
        return (bytes: null, reason: 'not found on the server');
      }
      if (res.statusCode != 200) {
        return (bytes: null, reason: 'the server refused it');
      }
      final declared = res.contentLength;
      if (declared != null && declared > cap) {
        return (bytes: null, reason: 'too big to keep on a phone');
      }

      final out = BytesBuilder(copy: false);
      // Nothing at all for this long means the line is gone, however
      // long the whole transfer has been running.
      await for (final chunk in res.stream.timeout(const Duration(seconds: 45))) {
        if (_cancelled) return (bytes: null, reason: 'stopped');
        out.add(chunk);
        if (out.length > cap) {
          return (bytes: null, reason: 'too big to keep on a phone');
        }
      }
      final bytes = out.takeBytes();
      if (bytes.isEmpty) return (bytes: null, reason: 'came down empty');
      if (declared != null && declared > 0 && bytes.length < declared) {
        // The connection closed politely in the middle. Writing this
        // would put half a PDF on the phone and call it saved.
        return (bytes: null, reason: 'the connection dropped');
      }
      _b.reportTransfer(
        bytes: bytes.length,
        millis: DateTime.now().difference(started).inMilliseconds,
      );
      return (bytes: bytes, reason: null);
    } on TimeoutException {
      return (bytes: null, reason: 'the connection dropped');
    } catch (e) {
      return (bytes: null, reason: _reasonFor(e));
    }
  }

  // ------------------------------------------------------------
  // Checking its own work
  // ------------------------------------------------------------

  /// Reads back everything this run went for and returns how much of it
  /// is not actually on the disk.
  /// Removes a document filed under a NOTE's id — the shape an older
  /// build used for a note's first attached PDF — once every one of
  /// that note's attachments is really held as an asset.
  Future<void> _dropLegacyDocuments(
    OfflineStore store,
    List<StudyMaterial> materials,
  ) async {
    for (final m in materials) {
      if (_cancelled) break;
      if (m.kind != MaterialKind.note) continue;
      if (store.item(m.id)?.hasDoc != true) continue;
      var allHeld = m.attachments.isNotEmpty;
      for (final a in m.attachments) {
        if (!await store.verifyAsset(_b.fileUrl(a.url))) {
          allHeld = false;
          break;
        }
      }
      if (allHeld) await store.forgetDocument(m.id);
    }
  }

  Future<int> _verify(
    OfflineStore store,
    List<_Unit> units,
    int expectedQuestions,
    List<CourseDownloadFailure> failures,
    Set<String> alreadyFailed,
  ) async {
    var missing = 0;
    for (final u in units) {
      if (_cancelled) break;
      // Already counted, by name, when the transfer itself failed.
      // Counting it again here made every failure worth two on the
      // card: one missing attachment read as "2 files did not save".
      if (!alreadyFailed.add(u.key)) continue;
      // A note is verified by its ENTRY, which an empty body has too.
      // Checking for a non-empty body counted every note Tutor Bello
      // had not typed yet as missing, on every run, whatever the line
      // was doing.
      final ok = switch (u.kind) {
        'asset' => await store.verifyAsset(u.url),
        _ => await store.verifyItem(u.material!.id),
      };
      if (!ok) {
        missing++;
        failures.add(CourseDownloadFailure(
            title: u.title, reason: 'not on the disk after saving'));
      } else {
        // It landed after all — do not leave its key looking failed.
        alreadyFailed.remove(u.key);
      }
    }
    if (expectedQuestions > 0) {
      final held = await store.questions(courseId);
      if (held.length < expectedQuestions) {
        missing += expectedQuestions - held.length;
      }
    }
    return missing;
  }
}

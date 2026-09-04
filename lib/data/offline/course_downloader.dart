import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../backend.dart';
import '../failures.dart';
import '../models.dart';
import '../repositories.dart';
import 'offline_store.dart';
import 'sync_engine.dart' show sigFor, urlsInHtml, utf8Length;

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

  const _Unit.note(this.material)
      : kind = 'note',
        id = '',
        url = '';
  const _Unit.doc(this.material)
      : kind = 'doc',
        id = '',
        url = '';
  const _Unit.asset(this.url)
      : kind = 'asset',
        id = '',
        material = null;

  String get key => kind == 'asset' ? url : (material?.id ?? id);
  String get title => kind == 'asset' ? '' : (material?.title ?? '');
}

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
    return CourseDownloadState(
      courseId: courseId,
      phase: ok ? CourseDownloadPhase.done : CourseDownloadPhase.failed,
      held: true,
      questions: (rec['questions'] as num?)?.toInt() ?? 0,
      materials: (rec['materials'] as num?)?.toInt() ?? 0,
      bytes: (rec['bytes'] as num?)?.toInt() ?? 0,
      savedAtMs: (rec['at'] as num?)?.toInt() ?? 0,
      updatedAt: '${rec['stamp'] ?? ''}',
      // A run that did not finish must keep asking. Anything else and a
      // half-downloaded course sits there looking finished.
      updateAvailable: !ok,
    );
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
      final wanted = <String>{};
      final units = _plan(store, materials, wanted)
        // The pictures on the questions are planned from the BANK, not
        // from the pages that just arrived, so a re-download picks up a
        // diagram that failed last time even when its question row has
        // not changed since.
        ..addAll(await _questionAssets(store, wanted));
      _emit(_state.copyWith(
        phase: CourseDownloadPhase.running,
        total: units.length,
        done: 0,
        label: units.isEmpty ? 'Checking your copy' : 'Saving your material',
      ));

      var done = 0;
      var bytes = 0;
      var failed = 0;
      var savedNotes = 0;
      var savedAssets = 0;
      final queue = List<_Unit>.from(units);

      Future<void> worker() async {
        while (!_cancelled && queue.isNotEmpty) {
          final unit = queue.removeAt(0);
          try {
            // Read into a local and add afterwards. `bytes += await …`
            // reads the counter, suspends, and writes back a value
            // three workers may all have read before any of them wrote.
            final moved = await _perform(unit, store);
            if (moved > 0) {
              bytes += moved;
              if (unit.kind == 'asset') {
                savedAssets++;
              } else {
                savedNotes++;
              }
            } else {
              failed++;
            }
          } catch (e) {
            failed++;
            debugPrint('[course] ${unit.kind} ${unit.key} failed: $e');
          }
          done++;
          _emit(_state.copyWith(
            done: done,
            bytes: bytes,
            failed: failed,
            assets: savedAssets,
            materials: savedNotes,
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
      final missing = await _verify(store, units, questionRows);
      final heldQuestions = (await store.questions(courseId)).length;

      final ok = missing == 0 && failed == 0;
      await store.putCourseRecord(
        courseId,
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
        held: true,
        updateAvailable: !ok,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAt: stamp?.stamp ?? _state.updatedAt,
        message: ok
            ? null
            : '${failed + missing} '
                '${failed + missing == 1 ? 'file' : 'files'} did not save. '
                'Tap Update on a steadier connection and only the missing '
                'ones are fetched.',
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
  ) {
    final units = <_Unit>[];

    void wantAsset(String? url) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _b.fileUrl(url);
      if (resolved.isEmpty) return;
      if (store.hasAsset(resolved)) return;
      if (!wanted.add(canonicalAssetUrl(resolved))) return;
      units.add(_Unit.asset(resolved));
    }

    for (final m in materials) {
      if (m.kind == MaterialKind.note) {
        units.add(_Unit.note(m));
        for (final u in urlsInHtml(m.contentHtml)) {
          wantAsset(u);
        }
        // Every attachment, whatever its kind. A note whose attached
        // PDF is missing is not saved, it is half-saved — and the
        // background sync only ever took the images and the audio.
        for (final a in m.attachments) {
          wantAsset(a.url);
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
        wantAsset(m.url);
        continue;
      }
      units.add(_Unit.doc(m));
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
  ) async {
    final units = <_Unit>[];

    void wantAsset(String? url) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _b.fileUrl(url);
      if (resolved.isEmpty) return;
      if (store.hasAsset(resolved)) return;
      if (!wanted.add(canonicalAssetUrl(resolved))) return;
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
        'asset' => 'Pictures and voice notes',
        _ => u.title.isEmpty ? 'Documents' : u.title,
      };

  Future<int> _perform(_Unit unit, OfflineStore store) => switch (unit.kind) {
        'note' => _saveNote(unit.material!, store),
        'asset' => _saveAsset(unit.url, store),
        _ => _saveDoc(unit.material!, store),
      };

  /// The body already arrived with the bundle, so this costs no request
  /// at all — which is the point of sending content_html with the page.
  Future<int> _saveNote(StudyMaterial m, OfflineStore store) async {
    final html = m.contentHtml;
    if (html.trim().isEmpty) {
      // A note with no body is not a failure, it is an empty note.
      // Counting it as one would make a perfectly downloaded course
      // report errors forever.
      return 1;
    }
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
    );
    return utf8Length(html);
  }

  Future<int> _saveDoc(StudyMaterial m, OfflineStore store) async {
    final url = _b.fileUrl(m.url);
    if (store.isCurrent(m.id, sigFor(m)) && store.item(m.id)?.hasDoc == true) {
      // Already held at this exact version. Not a transfer, and not a
      // failure either.
      return 1;
    }
    final bytes = await _download(url, cap: _maxFile);
    if (bytes == null) return 0;
    if (!await _makeRoom(store, bytes.length)) return 0;

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
    );
    if (!await store.verifyItem(m.id)) return 0;
    return bytes.length;
  }

  Future<int> _saveAsset(String url, OfflineStore store) async {
    if (url.isEmpty) return 0;
    if (store.hasAsset(url)) return 1;
    final bytes = await _download(url, cap: _maxFile);
    if (bytes == null) return 0;
    if (!await _makeRoom(store, bytes.length)) return 0;
    await store.putAsset(url, bytes);
    if (!await store.verifyAsset(url)) return 0;
    return bytes.length;
  }

  /// Room is checked BEFORE the write, not discovered by it. A failed
  /// write on a full phone still cost the student the download.
  Future<bool> _makeRoom(OfflineStore store, int bytes) async {
    final room = await store.canWrite(bytes);
    if (room.ok) return true;
    await store.evictFor(bytes);
    final again = await store.canWrite(bytes);
    if (again.ok) return true;
    _emit(_state.copyWith(message: again.reason));
    return false;
  }

  Future<List<int>?> _download(String url, {required int cap}) async {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final started = DateTime.now();
      final res =
          await _http.get(uri).timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      if (res.bodyBytes.isEmpty) return null;
      if (res.bodyBytes.length > cap) return null;
      _b.reportTransfer(
        bytes: res.bodyBytes.length,
        millis: DateTime.now().difference(started).inMilliseconds,
      );
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // Checking its own work
  // ------------------------------------------------------------

  /// Reads back everything this run went for and returns how much of it
  /// is not actually on the disk.
  Future<int> _verify(
    OfflineStore store,
    List<_Unit> units,
    int expectedQuestions,
  ) async {
    var missing = 0;
    for (final u in units) {
      if (_cancelled) break;
      final ok = switch (u.kind) {
        'asset' => await store.verifyAsset(u.url),
        'note' => (await store.readNote(u.material!.id))?.isNotEmpty ?? false,
        _ => await store.verifyItem(u.material!.id),
      };
      if (!ok) missing++;
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

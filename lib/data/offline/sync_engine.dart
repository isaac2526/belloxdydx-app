import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../backend.dart';
import '../failures.dart';
import '../models.dart';
import '../repositories.dart';
import 'offline_store.dart';

/// ============================================================
/// THE SYNC ENGINE
///
/// What the app keeps for offline use, and why it is split this way.
///
/// The ask was "everything downloads by itself in the background". The
/// honest engineering answer is that *some* of it should and some of it
/// must not, and pretending otherwise is how you burn a student's data
/// bundle on a 400 MB lecture video they were never going to open.
///
/// So the sync runs in tiers:
///
///   TIER 1 — always, on any connection.
///     The course shelf, the material index, and every NOTE BODY. Notes
///     are HTML: a whole semester of them is a couple of megabytes. This
///     is what makes the Vault useful the moment a student logs in
///     instead of sitting empty until they remember to tap Save.
///
///   TIER 2 — always, but size-capped.
///     Pictures and voice notes referenced by the notes and by every
///     question the student has already seen. Each file must be under
///     [_maxAutoAsset]; the whole tier is capped by [_assetBudget].
///     Without this, "questions work offline" is a lie — the text would
///     be there and the diagram would be a grey box.
///
///   TIER 3 — Wi-Fi only, off by default, one switch in the Vault.
///     Whole documents: PDFs, past questions, slide decks. These are the
///     big ones. A student turns this on if they want it.
///
///   TIER 4 — never automatic.
///     Videos, and anything above [_maxAutoDoc]. Tap to save, as today.
///
/// Nothing is fetched twice. Every item carries a signature — the
/// material's `updated_at` where the backend gives us one, its URL
/// otherwise — and a matching signature means the transfer is skipped
/// entirely.
/// ============================================================

/// Per-file ceiling for an automatically fetched image or voice note.
const int _maxAutoAsset = 8 * 1024 * 1024;

/// The same ceiling on somebody's data bundle. A 6 MB voice note is
/// worth fetching over Wi-Fi and is not worth a Nigerian student's
/// airtime without them saying so.
const int _maxMeteredAsset = 2 * 1024 * 1024;

/// Total spend on tier 2 in one sync, on Wi-Fi.
const int _assetBudget = 120 * 1024 * 1024;

/// Total spend on tier 2 in one sync, on mobile data. Deliberately
/// small: enough for the diagrams on a semester of notes, nowhere near
/// enough to notice on a bill.
const int _meteredAssetBudget = 20 * 1024 * 1024;

/// Per-file ceiling for a tier 3 document.
const int _maxAutoDoc = 40 * 1024 * 1024;

/// Total spend on tier 3 in one sync.
const int _docBudget = 600 * 1024 * 1024;

/// How many transfers run at once. Three is enough to hide latency on a
/// Nigerian mobile connection without starving the UI thread.
const int _workers = 3;

enum SyncPhase { idle, running, done, failed, unsupported }

@immutable
class SyncStatus {
  final SyncPhase phase;

  /// What is being fetched right now, in words a student reads.
  final String label;
  final int done;
  final int total;
  final int bytes;

  /// Set only on failure, and only ever from the closed fault set.
  final String? message;

  final int syncedAtMs;

  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.label = '',
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
    this.message,
    this.syncedAtMs = 0,
  });

  bool get isRunning => phase == SyncPhase.running;
  double get progress => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  DateTime? get syncedAt => syncedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(syncedAtMs);

  SyncStatus copyWith({
    SyncPhase? phase,
    String? label,
    int? done,
    int? total,
    int? bytes,
    String? message,
    int? syncedAtMs,
    bool clearMessage = false,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        label: label ?? this.label,
        done: done ?? this.done,
        total: total ?? this.total,
        bytes: bytes ?? this.bytes,
        message: clearMessage ? null : (message ?? this.message),
        syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      );
}

/// One unit of transfer.
class _Job {
  final String kind; // note | asset | doc
  final String id;
  final String url;
  final StudyMaterial? material;
  final String sig;

  _Job.note(this.material, this.sig)
      : kind = 'note',
        id = material!.id,
        url = '';

  _Job.asset(this.url)
      : kind = 'asset',
        id = url,
        material = null,
        sig = '';

  _Job.doc(this.material, this.sig)
      : kind = 'doc',
        id = material!.id,
        url = material.url;
}

class SyncEngine {
  SyncEngine({
    required Backend backend,
    required ContentRepository content,
    required OfflineStore? store,
  })  : _b = backend,
        _content = content,
        _store = store;

  final Backend _b;
  final ContentRepository _content;
  final OfflineStore? _store;

  final _controller = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get updates => _controller.stream;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  bool _cancelled = false;
  Future<void>? _inFlight;

  /// Set by the student in the Vault. Off by default: nobody's data
  /// bundle gets spent on PDFs without them saying so.
  bool autoDocuments = false;

  int _assetSpend = 0;
  int _docSpend = 0;

  /// Whether this sync is running on a connection somebody pays per
  /// megabyte for. Decided once per run, not per file.
  bool _metered = true;

  int get _assetCap => _metered ? _maxMeteredAsset : _maxAutoAsset;
  int get _assetAllowance => _metered ? _meteredAssetBudget : _assetBudget;

  void _emit(SyncStatus s) {
    _status = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void cancel() => _cancelled = true;

  Future<void> dispose() async {
    _cancelled = true;
    await _controller.close();
  }

  /// True when the connection is one nobody pays per megabyte for.
  ///
  /// Read from the Backend's single connectivity watcher rather than by
  /// asking the plugin again. connectivity_plus reaches the platform
  /// differently on each OS and on some of them a failure arrives as an
  /// unhandled error in the zone rather than a rejected future — which
  /// takes down whatever is running, including a sync. One subscription,
  /// already hardened, is the safer answer.
  bool get _onWifi => _b.isUnmetered;

  /// Runs a sync, or joins the one already running.
  ///
  /// [minInterval] stops a resume, a pull-to-refresh and a reconnect all
  /// firing one after another; pass Duration.zero when the student asked
  /// for it by hand.
  Future<void> run({
    Duration minInterval = const Duration(hours: 6),
    String? level,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final f = _run(minInterval: minInterval, level: level)
        .whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  Future<void> _run({
    required Duration minInterval,
    String? level,
  }) async {
    final store = _store;
    if (store == null) {
      _emit(const SyncStatus(
        phase: SyncPhase.unsupported,
        label: 'This device cannot keep offline copies.',
      ));
      return;
    }

    final since = DateTime.now().millisecondsSinceEpoch - store.syncedAtMs;
    if (minInterval > Duration.zero &&
        store.syncedAtMs > 0 &&
        since < minInterval.inMilliseconds) {
      _emit(_status.copyWith(
        phase: SyncPhase.done,
        syncedAtMs: store.syncedAtMs,
        clearMessage: true,
      ));
      return;
    }

    _cancelled = false;
    _assetSpend = 0;
    _docSpend = 0;
    _metered = !_onWifi;
    _emit(SyncStatus(
      phase: SyncPhase.running,
      label: 'Checking for new material',
      syncedAtMs: store.syncedAtMs,
    ));

    try {
      // ---- tier 0: the index itself -------------------------------
      await _content.loadContent(level: level ?? '100', force: true);

      final jobs = await _plan(store);
      if (_cancelled) return;

      if (jobs.isEmpty) {
        await store.markSynced();
        _emit(SyncStatus(
          phase: SyncPhase.done,
          label: 'Everything is already saved',
          syncedAtMs: store.syncedAtMs,
        ));
        return;
      }

      _emit(_status.copyWith(
        total: jobs.length,
        done: 0,
        label: 'Saving your material',
      ));

      var done = 0;
      var bytes = 0;
      final queue = List<_Job>.from(jobs);

      Future<void> worker() async {
        while (!_cancelled && queue.isNotEmpty) {
          final job = queue.removeAt(0);
          try {
            bytes += await _perform(job, store);
          } catch (e) {
            // One file failing must never end the sync. A lecture note
            // that 404s is not a reason to lose the other ninety.
            debugPrint('[sync] ${job.kind} ${job.id} failed: $e');
          }
          done++;
          _emit(_status.copyWith(
            done: done,
            bytes: bytes,
            label: _labelFor(job),
          ));
          // Let the UI breathe between files.
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
      await store.flush();

      if (_cancelled) {
        _emit(_status.copyWith(phase: SyncPhase.idle, label: 'Paused'));
        return;
      }

      await store.markSynced();
      _emit(SyncStatus(
        phase: SyncPhase.done,
        label: 'Saved for offline',
        done: done,
        total: jobs.length,
        bytes: bytes,
        syncedAtMs: store.syncedAtMs,
      ));
    } catch (e) {
      _emit(_status.copyWith(
        phase: SyncPhase.failed,
        message: classify(e, hasConnection: _b.hasConnection).message,
      ));
    }
  }

  String _labelFor(_Job j) => switch (j.kind) {
        'note' => 'Notes',
        'asset' => 'Pictures and voice notes',
        _ => 'Documents',
      };

  // ------------------------------------------------------------
  // Planning
  // ------------------------------------------------------------

  Future<List<_Job>> _plan(OfflineStore store) async {
    final jobs = <_Job>[];
    final wanted = <String>{}; // asset URLs, de-duplicated

    void wantAsset(String? url) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _b.fileUrl(url);
      if (resolved.isEmpty) return;
      if (store.hasAsset(resolved)) return;
      if (!wanted.add(canonicalAssetUrl(resolved))) return;
      jobs.add(_Job.asset(resolved));
    }

    // ---- tier 1: note bodies ------------------------------------
    for (final m in _content.materials) {
      if (m.kind != MaterialKind.note) continue;
      final sig = _sigFor(m);
      if (store.isCurrent(m.id, sig)) {
        // Already held at this version. Its pictures may still be
        // missing, though — a sync interrupted halfway leaves exactly
        // that state — so read the saved copy and ask for them.
        final html = await store.readNote(m.id);
        if (html != null) {
          for (final u in _urlsInHtml(html)) {
            wantAsset(u);
          }
        }
        continue;
      }
      jobs.add(_Job.note(m, sig));
    }

    // ---- tier 2: pictures and audio on the question sets ---------
    for (final row in await store.allQuestions()) {
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
          for (final u in _urlsInHtml(v)) {
            wantAsset(u);
          }
        }
      }
    }

    // Material thumbnails and image-shaped materials.
    for (final m in _content.materials) {
      if (m.url.isEmpty) continue;
      final ext = extensionForUrl(m.url, fallback: '');
      if (const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        wantAsset(m.url);
      }
    }

    // ---- tier 3: whole documents, opt-in and Wi-Fi only ----------
    // Wi-Fi only, whatever the switch says. Whole documents are the one
    // tier big enough to matter on a bill.
    if (autoDocuments && !_metered) {
      for (final m in _content.materials) {
        if (m.kind == MaterialKind.note ||
            m.kind == MaterialKind.video ||
            m.kind == MaterialKind.series) {
          continue;
        }
        if (m.url.isEmpty) continue;
        final sig = _sigFor(m);
        if (store.isCurrent(m.id, sig) && store.item(m.id)?.hasDoc == true) {
          continue;
        }
        jobs.add(_Job.doc(m, sig));
      }
    }

    return jobs;
  }

  /// What a copy was made from. `updated_at` when the backend sends one
  /// — the direct RPC always does, and the website route now does too —
  /// otherwise the URL, which at least catches a replaced file.
  String _sigFor(StudyMaterial m) =>
      m.updatedAt?.toIso8601String() ?? '${m.url}#${m.sortOrder}';

  static Iterable<String> _urlsInHtml(String html) sync* {
    for (final m in kEmbeddedStorageUrl.allMatches(html)) {
      yield m.group(0)!;
    }
    for (final m in _proxyUrlInHtml.allMatches(html)) {
      yield m.group(0)!;
    }
  }

  static final RegExp _proxyUrlInHtml =
      RegExp(r'''https?://[^\s"'<>()]*?/api/file\?u=[A-Za-z0-9_=-]+''');

  // ------------------------------------------------------------
  // Doing the work
  // ------------------------------------------------------------

  Future<int> _perform(_Job job, OfflineStore store) async {
    switch (job.kind) {
      case 'note':
        return _fetchNote(job, store);
      case 'asset':
        return _fetchAsset(job.url, store);
      default:
        return _fetchDoc(job, store);
    }
  }

  Future<int> _fetchNote(_Job job, OfflineStore store) async {
    final m = job.material!;
    final full = await _content.material(m.id);
    final html = full.contentHtml;
    if (html.trim().isEmpty) return 0;

    final course = _content.courseById(m.courseId);
    await store.putNote(
      id: m.id,
      title: m.title.isEmpty ? full.title : m.title,
      html: html,
      courseCode: course?.code ?? '',
      courseId: m.courseId,
      sig: job.sig,
    );

    // Its pictures and voice notes, straight away — a note whose
    // diagram is missing is not saved, it is half-saved.
    for (final u in _urlsInHtml(html)) {
      if (_cancelled) break;
      try {
        await _fetchAsset(_b.fileUrl(u), store);
      } catch (_) {}
    }
    for (final a in full.attachments) {
      if (a.kind == 'image' || a.kind == 'audio') {
        try {
          await _fetchAsset(_b.fileUrl(a.url), store);
        } catch (_) {}
      }
    }
    return utf8Length(html);
  }

  Future<int> _fetchAsset(String url, OfflineStore store) async {
    if (url.isEmpty || store.hasAsset(url)) return 0;
    if (_assetSpend >= _assetAllowance) return 0;
    final bytes = await _download(url, cap: _assetCap);
    if (bytes == null) return 0;
    await store.putAsset(url, bytes);
    _assetSpend += bytes.length;
    return bytes.length;
  }

  Future<int> _fetchDoc(_Job job, OfflineStore store) async {
    if (_docSpend >= _docBudget) return 0;
    final m = job.material!;
    final url = _b.fileUrl(m.url);
    final bytes = await _download(url, cap: _maxAutoDoc);
    if (bytes == null) return 0;
    final course = _content.courseById(m.courseId);
    await store.putDocument(
      id: m.id,
      title: m.title,
      kind: m.kind.name,
      bytes: bytes,
      extension: extensionForUrl(url, fallback: 'pdf'),
      courseCode: course?.code ?? '',
      courseId: m.courseId,
      sig: job.sig,
      pinned: false,
    );
    _docSpend += bytes.length;
    return bytes.length;
  }

  /// Fetches with a hard ceiling. A HEAD first where the server offers a
  /// length, so an oversized file costs one round trip rather than the
  /// student's whole bundle.
  Future<List<int>?> _download(String url, {required int cap}) async {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final head = await http
          .head(uri)
          .timeout(const Duration(seconds: 12))
          .catchError((_) => http.Response('', 599));
      final declared = int.tryParse(head.headers['content-length'] ?? '');
      if (declared != null && declared > cap) return null;

      final res =
          await http.get(uri).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      if (res.bodyBytes.length > cap) return null;
      if (res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

int utf8Length(String s) => s.codeUnits.length;

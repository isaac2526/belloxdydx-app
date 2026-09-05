import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// ============================================================
/// THE OFFLINE STORE
///
/// Everything the app keeps on disk for offline use lives here, under
/// one directory:
///
/// ```
///   <app documents>/offline/
///     index.json            the catalogue
///     notes/<id>.html       note bodies
///     docs/<id>.<ext>       PDFs, slides, anything downloaded whole
///     assets/<hash>.<ext>   images and audio, addressed by content
///     questions/<key>.json  question sets the student has already seen
/// ```
///
/// Four decisions in here matter more than the rest, and each of them
/// replaces something that was broken:
///
/// 1. **Paths are stored relative.** The old vault index wrote absolute
///    paths into SharedPreferences. On iOS the app container is a UUID
///    that changes on restore and on some updates, so every saved file
///    would silently stop opening. Only the tail is stored; the head is
///    resolved fresh on every read.
///
/// 2. **This is not the JSON cache.** `LocalStore.clearCache()` deletes
///    `<app documents>/cache` and runs on every sign-out. Anything the
///    student downloaded must not be inside it.
///
/// 3. **Assets are keyed by their ORIGINAL storage URL.** The same image
///    has two different URLs depending on which backend path the app is
///    on — the raw Supabase URL in direct mode, a
///    `…/api/file?u=<base64>` proxy URL in legacy mode. Keying on
///    whatever URL happened to arrive would re-download the whole
///    library the first time a student's app flipped between them.
///    [canonicalAssetUrl] undoes the proxy so both paths agree.
///
/// 4. **Nothing is re-downloaded unless it changed.** Every item carries
///    a signature — the material's `updated_at` where the backend gives
///    us one, its URL otherwise. Same signature, no transfer.
/// ============================================================

/// The catalogue format. Bumping this discards the old one rather than
/// trying to read a shape we no longer write.
const int kOfflineIndexVersion = 3;

/// How many "did not save" rows one course record keeps by name.
const int kMaxRecordedFailures = 20;

/// How many recently dealt question ids one bucket remembers.
const int kServedMemory = 400;

@immutable
class OfflineItem {
  /// The material id, or a synthetic key for a question set.
  final String id;
  final String title;
  final String courseCode;
  final String courseId;

  /// `MaterialKind.name` for a material, `questions` for a question set.
  final String kind;

  /// Path of the downloaded document, relative to the offline root.
  final String? docRel;

  /// Path of the saved HTML body, relative to the offline root.
  final String? htmlRel;

  final int bytes;
  final int savedAtMs;

  /// What this copy was made from. Equal signature, no re-download.
  final String sig;

  /// True when the student asked for this one by tapping Save. Pinned
  /// items are never evicted to make room and never expire.
  final bool pinned;

  /// What was clipped to this note — each one's title, URL and kind —
  /// so the note can still list them with the data off.
  ///
  /// The bytes of an attachment live in the asset store under the URL's
  /// key, and this list is the only thing that ties them back to the
  /// note. Without it a downloaded PDF sat complete on the disk while
  /// the note it belonged to said "Nothing is attached yet either" —
  /// which is exactly what a student photographed and sent in.
  final List<OfflineAttachment> attachments;

  const OfflineItem({
    required this.id,
    required this.title,
    required this.kind,
    this.courseCode = '',
    this.courseId = '',
    this.docRel,
    this.htmlRel,
    this.bytes = 0,
    this.savedAtMs = 0,
    this.sig = '',
    this.pinned = false,
    this.attachments = const [],
  });

  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  /// When TUTOR BELLO last changed this item, when that is knowable.
  ///
  /// [sig] is the material's own `updated_at` wherever the backend sent
  /// one, and its URL otherwise — so the date is already on the disk and
  /// costs nothing to read. Null for the URL form, and for anything
  /// carried over from the old vault.
  ///
  /// This is the date worth showing. [savedAt] answers "when did I press
  /// the button", which is a question no student has ever asked about a
  /// note.
  /// When Tutor Bello last changed this, in the student's OWN time.
  ///
  /// The signature is stored as UTC. Printing it straight gives a Lagos
  /// student "yesterday" for anything he posted after 11pm — which is
  /// most of what he posts — so it comes back local and is formatted
  /// local everywhere it is shown.
  DateTime? get updatedAt {
    if (sig.isEmpty || !sig.startsWith('20')) return null;
    return DateTime.tryParse(sig)?.toLocal();
  }
  bool get hasDoc => (docRel ?? '').isNotEmpty;
  bool get hasHtml => (htmlRel ?? '').isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  String get sizeLabel => formatBytes(bytes);

  OfflineItem copyWith({
    String? title,
    String? courseCode,
    String? courseId,
    String? kind,
    String? docRel,
    String? htmlRel,
    int? bytes,
    int? savedAtMs,
    String? sig,
    bool? pinned,
    List<OfflineAttachment>? attachments,
  }) =>
      OfflineItem(
        id: id,
        title: title ?? this.title,
        courseCode: courseCode ?? this.courseCode,
        courseId: courseId ?? this.courseId,
        kind: kind ?? this.kind,
        docRel: docRel ?? this.docRel,
        htmlRel: htmlRel ?? this.htmlRel,
        bytes: bytes ?? this.bytes,
        savedAtMs: savedAtMs ?? this.savedAtMs,
        sig: sig ?? this.sig,
        pinned: pinned ?? this.pinned,
        attachments: attachments ?? this.attachments,
      );

  factory OfflineItem.fromJson(Map<String, dynamic> j) => OfflineItem(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        courseCode: '${j['course'] ?? ''}',
        courseId: '${j['courseId'] ?? ''}',
        kind: '${j['kind'] ?? 'file'}',
        docRel: j['doc']?.toString(),
        htmlRel: j['html']?.toString(),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        savedAtMs: (j['at'] as num?)?.toInt() ?? 0,
        sig: '${j['sig'] ?? ''}',
        pinned: j['pin'] == true,
        attachments: [
          for (final a in (j['att'] as List? ?? const []))
            if (a is Map) OfflineAttachment.fromJson(Map<String, dynamic>.from(a)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'course': courseCode,
        'courseId': courseId,
        'kind': kind,
        if (docRel != null) 'doc': docRel,
        if (htmlRel != null) 'html': htmlRel,
        'bytes': bytes,
        'at': savedAtMs,
        'sig': sig,
        if (pinned) 'pin': true,
        if (attachments.isNotEmpty)
          'att': [for (final a in attachments) a.toJson()],
      };
}

/// One thing clipped to a saved note. The same three fields the
/// backend sends for an attachment, kept here so the store does not
/// depend on the model layer.
@immutable
class OfflineAttachment {
  final String title;
  final String url;

  /// pdf | image | audio | file
  final String kind;

  const OfflineAttachment({
    required this.title,
    required this.url,
    this.kind = 'file',
  });

  factory OfflineAttachment.fromJson(Map<String, dynamic> j) =>
      OfflineAttachment(
        title: '${j['title'] ?? j['t'] ?? ''}',
        url: '${j['url'] ?? j['u'] ?? ''}',
        kind: '${j['kind'] ?? j['k'] ?? 'file'}',
      );

  Map<String, dynamic> toJson() => {'t': title, 'u': url, 'k': kind};
}

@immutable
class OfflineAsset {
  /// Path relative to the offline root.
  final String rel;
  final int bytes;
  final int savedAtMs;

  const OfflineAsset({
    required this.rel,
    this.bytes = 0,
    this.savedAtMs = 0,
  });

  factory OfflineAsset.fromJson(Map<String, dynamic> j) => OfflineAsset(
        rel: '${j['r'] ?? ''}',
        bytes: (j['b'] as num?)?.toInt() ?? 0,
        savedAtMs: (j['a'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'r': rel, 'b': bytes, 'a': savedAtMs};
}

String formatBytes(int n) {
  if (n <= 0) return '0 B';
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  if (n < 1024 * 1024 * 1024) {
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// One phrasing for Tutor Bello's date, everywhere it appears.
///
/// The app grew five different renderings of the same fact — "updated
/// 3 Sep", "Last updated 3 Sep", "on 3 Sep", a bare date and a green
/// chip with no date at all — which reads as five different facts. It
/// is one fact, so it is one sentence.
///
/// [t] is converted to the student's own time first: the stamps are
/// stored as UTC and Lagos is an hour ahead, so anything Tutor Bello
/// posts after midnight would otherwise read "yesterday" to the whole
/// country. The year is carried on anything from another year, because
/// Belloxdydx runs the same courses session after session and "12 Oct"
/// cannot tell them apart.
String bxBelloDate(DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  final today = now?.toLocal() ?? DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final ref = DateTime(today.year, today.month, today.day);
  final days = ref.difference(day).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days > 1 && days < 7) return '$days days ago';
  final d = local.day;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final m = months[local.month - 1];
  return local.year == today.year ? '$d $m' : '$d $m ${local.year}';
}

/// Reduces any URL for the same file to one stable key.
///
/// In legacy mode a Supabase storage URL arrives already wrapped as
/// `https://site/api/file?u=<base64url of the original>`. In direct mode
/// the same file arrives as the raw storage URL. Unwrapping here means
/// one cached copy serves both, and a student whose app switches paths
/// does not re-download their entire library.
String canonicalAssetUrl(String url) {
  final u = url.trim();
  final marker = '/api/file?u=';
  final at = u.indexOf(marker);
  if (at < 0) return u;
  var b64 = u.substring(at + marker.length);
  final amp = b64.indexOf('&');
  if (amp >= 0) b64 = b64.substring(0, amp);
  if (b64.isEmpty) return u;
  try {
    // base64Url.decode insists on the padding the shield strips.
    final padded = b64.padRight((b64.length + 3) & ~3, '=');
    final decoded = utf8.decode(base64Url.decode(padded));
    return decoded.startsWith('http') ? decoded : u;
  } catch (_) {
    return u;
  }
}

/// The filename an asset is stored under. Content-addressed, so the same
/// image referenced from four different questions is stored once.
String assetKeyFor(String url) =>
    sha1.convert(utf8.encode(canonicalAssetUrl(url))).toString();

/// A guess at the file extension, used only so the OS and the PDF
/// renderer can recognise what they are opening.
String extensionForUrl(String url, {String fallback = 'bin'}) {
  final path = canonicalAssetUrl(url).split('?').first.split('#').first;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < path.length - 6) return fallback;
  final ext = path.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : fallback;
}

class OfflineStore {
  OfflineStore._(this._root);

  final Directory _root;

  final Map<String, OfflineItem> _items = {};
  final Map<String, OfflineAsset> _assets = {};

  /// questionId -> the bucket its row lives in.
  ///
  /// Held in memory only, and deliberately not written to the
  /// catalogue: it is one entry per question, so persisting it would
  /// bloat index.json — which is re-encoded whole — for something that
  /// can be rebuilt by reading the buckets once.
  ///
  /// It exists because folding an answer verdict back into the cached
  /// question used to READ AND DECODE EVERY BUCKET to find the one row
  /// it wanted, on the UI isolate, before the student could be shown
  /// whether they were right. That cost grew with every round anybody
  /// ever played.
  final Map<String, String> _questionHome = {};
  bool _homeMapped = false;

  /// What each course looked like the last time it was downloaded
  /// whole: courseId -> {materials, questions, stamp, at, ok}.
  ///
  /// This is the memory behind "there's a change in this course,
  /// download now". The badge is the difference between this and the
  /// manifest the server serves — not a guess about time, which is why
  /// it holds counts as well as a stamp: `updated_at` cannot see a
  /// deletion, and a count cannot see an edit.
  final Map<String, Map<String, dynamic>> _courses = {};

  /// The question ids most recently handed to an offline round, per
  /// bucket, newest last. See [recentlyServed].
  final Map<String, List<String>> _served = {};
  String _owner = '';
  int _syncedAtMs = 0;

  Timer? _flush;
  bool _dirty = false;

  /// Opens (and if needed builds) the offline root. Returns null where
  /// there is no filesystem to hold it — the web build, or a platform
  /// that refuses a documents directory.
  static Future<OfflineStore?> open() async {
    if (kIsWeb) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory('${docs.path}/offline');
      if (!await root.exists()) await root.create(recursive: true);
      final store = OfflineStore._(root);
      await store._load();
      return store;
    } catch (e) {
      debugPrint('[offline] cannot open store: $e');
      return null;
    }
  }

  String get rootPath => _root.path;
  int get syncedAtMs => _syncedAtMs;
  String get ownerId => _owner;

  File get _indexFile => File('${_root.path}/index.json');

  Future<void> _load() async {
    try {
      if (!await _indexFile.exists()) return;
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      if ((map['v'] as num?)?.toInt() != kOfflineIndexVersion) {
        // A shape we no longer write. Start clean rather than guess.
        await wipe();
        return;
      }
      _owner = '${map['owner'] ?? ''}';
      _syncedAtMs = (map['syncedAt'] as num?)?.toInt() ?? 0;
      final items = map['items'];
      if (items is Map) {
        items.forEach((k, v) {
          if (v is Map) {
            _items['$k'] = OfflineItem.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
      final assets = map['assets'];
      if (assets is Map) {
        assets.forEach((k, v) {
          if (v is Map) {
            _assets['$k'] = OfflineAsset.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
      final courses = map['courses'];
      if (courses is Map) {
        courses.forEach((k, v) {
          if (v is Map) _courses['$k'] = Map<String, dynamic>.from(v);
        });
      }
      final served = map['served'];
      if (served is Map) {
        served.forEach((k, v) {
          if (v is List) _served['$k'] = [for (final id in v) '$id'];
        });
      }
    } catch (e) {
      debugPrint('[offline] unreadable index, starting clean: $e');
      _items.clear();
      _assets.clear();
      _courses.clear();
      _served.clear();
    }
  }

  /// Writes the catalogue. Coalesced, because a sync touches it once per
  /// file and the catalogue is written whole.
  ///
  /// The window used to be 600 ms, and that was too eager. The
  /// catalogue is one JSON object holding every item and every asset —
  /// thousands of entries on a phone with four courses downloaded — and
  /// encoding it happens on the UI isolate. Doing that twice a second
  /// for the length of a course download is a jank source measured in
  /// seconds, for a file nothing reads until the next launch.
  ///
  /// Two and a half seconds instead, and every path that MUST have it
  /// on disk — the end of a sync, the end of a download, a sign-out,
  /// putCourseRecord — already calls flush() directly rather than
  /// waiting for this.
  void _touch() {
    _dirty = true;
    _flush ??= Timer(const Duration(milliseconds: 2500), () {
      _flush = null;
      unawaited(flush());
    });
  }

  Future<void>? _flushing;

  Future<void> flush() {
    // Serialised. A sync has three workers touching the catalogue and
    // several callers of flush(); two overlapping writes would each
    // stage their own file and the loser's rename would fail on a file
    // the winner had already moved.
    final running = _flushing;
    if (running != null) return running.then((_) => _dirty ? flush() : null);
    final next = _flushOnce().whenComplete(() => _flushing = null);
    _flushing = next;
    return next;
  }

  Future<void> _flushOnce() async {
    if (!_dirty) return;
    _dirty = false;
    _flush?.cancel();
    _flush = null;
    try {
      final payload = jsonEncode({
        'v': kOfflineIndexVersion,
        'owner': _owner,
        'syncedAt': _syncedAtMs,
        'items': {for (final e in _items.entries) e.key: e.value.toJson()},
        'assets': {for (final e in _assets.entries) e.key: e.value.toJson()},
        'courses': _courses,
        'served': _served,
      });
      // Written aside and renamed: a kill mid-write leaves the previous
      // catalogue intact instead of a truncated one.
      await _atomicWrite(_indexFile, (f) => f.writeAsString(payload, flush: true));
    } catch (e) {
      debugPrint('[offline] index write failed: $e');
    }
  }

  /// Stages a file next to its target and renames it into place.
  ///
  /// The staging name carries a counter, which is not decoration. The
  /// sync runs three workers, and the same picture is referenced by
  /// several notes, so two of them routinely download it at once. With
  /// one shared `<target>.part` the first rename moved the file and the
  /// second failed with ENOENT — which is exactly what happened the
  /// first time this ran against a real filesystem, and what no
  /// single-threaded test would ever have shown.
  ///
  /// rename(2) onto an existing path is an atomic replace, so the loser
  /// of the race simply overwrites identical bytes.
  static int _stage = 0;

  Future<void> _atomicWrite(File target, Future<void> Function(File) write) async {
    final tmp = File('${target.path}.${_stage++}.part');
    try {
      await write(tmp);
      await tmp.rename(target.path);
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // Ownership
  // ------------------------------------------------------------

  /// Ties the store to one student. Signing in as somebody else throws
  /// the previous student's downloads away rather than showing them.
  /// Returns true when a wipe happened.
  Future<bool> claim(String userId) async {
    if (userId.isEmpty) return false;

    // An UNCLAIMED store is adopted, never wiped. This mattered more
    // than it looks: the legacy vault is carried across in main(), long
    // before a profile has loaded, so an owner check that treated
    // "nobody yet" as "somebody else" threw away every document the
    // student had saved before this version — on their first launch,
    // silently.
    if (_owner.isEmpty || _owner == userId) {
      if (_owner != userId) {
        _owner = userId;
        _touch();
        await flush();
      }
      return false;
    }

    await wipe();
    _owner = userId;
    _touch();
    await flush();
    return true;
  }

  Future<void> wipe() async {
    _items.clear();
    _assets.clear();
    _courses.clear();
    _served.clear();
    _questionHome.clear();
    _homeMapped = false;
    _owner = '';
    _syncedAtMs = 0;
    for (final name in ['notes', 'docs', 'assets', 'questions']) {
      try {
        final d = Directory('${_root.path}/$name');
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
    try {
      if (await _indexFile.exists()) await _indexFile.delete();
    } catch (_) {}
    _dirty = false;
  }

  Future<void> markSynced() async {
    _syncedAtMs = DateTime.now().millisecondsSinceEpoch;
    _touch();
    await flush();
  }

  // ------------------------------------------------------------
  // What each course looked like when it was last downloaded
  // ------------------------------------------------------------

  /// The record of the last full download of one course, or null if it
  /// has never been downloaded.
  Map<String, dynamic>? courseRecord(String courseId) =>
      courseId.isEmpty ? null : _courses[courseId];

  /// Writes the record. [ok] is false when the run did not land
  /// everything it went for, and a course that did not land completely
  /// must keep asking to be downloaded rather than sitting there
  /// looking finished.
  Future<void> putCourseRecord(
    String courseId, {
    required int materials,
    required int questions,
    required String stamp,
    required bool ok,
    int tests = 0,
    int pins = 0,
    String pinPrint = '',
    String courseStamp = '',
    int bytes = 0,
    int heldQuestions = 0,
    int heldFiles = 0,
    int heldAssets = 0,
    String reason = '',
    int failed = 0,
    List<Map<String, String>> failures = const [],
  }) async {
    if (courseId.isEmpty) return;
    _courses[courseId] = {
      'materials': materials,
      'questions': questions,
      // A pin decides which questions the bundle withholds, so it is
      // part of what a correct download contains — see CourseStamp.
      'tests': tests,
      'pins': pins,
      // A count catches a pin added or removed; only the checksum
      // catches a SWAP, which changes what the bundle withholds while
      // leaving every number identical.
      'pin_print': pinPrint,
      'course_stamp': courseStamp,
      // When TUTOR BELLO last touched any part of this course. Held so
      // the app can say so even with no signal, which is exactly when a
      // student most wants to know how old their copy is.
      'stamp': stamp,
      'ok': ok,
      'bytes': bytes,
      // WHAT THE SERVER HAS is above; WHAT ACTUALLY LANDED is here.
      //
      // They are not the same number and conflating them made the card
      // lie. With offline_questions switched off, nothing is fetched
      // and the manifest's count was stored anyway — so from the next
      // launch the course announced "works without data · 412
      // questions" with none of them on the phone. The counts above
      // must stay the server's, or the badge could never settle; the
      // ones below are what the student is told they have.
      'heldQuestions': heldQuestions,
      'heldFiles': heldFiles,
      'heldAssets': heldAssets,
      // Why it did not finish, so the app can say THAT rather than
      // telling the student in Tutor Bello's name, every launch for
      // ever, that he changed something.
      'reason': reason,
      // WHICH files did not save and WHY, by name, so the card can say
      // "Episode 2 · not found on the server" instead of a bare number
      // the student can do nothing with. Capped: the sentence on the
      // card lists a handful, and a record is re-encoded whole.
      'failed': failed,
      'failures': failures.take(kMaxRecordedFailures).toList(),
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _touch();
    await flush();
  }

  /// How many notes, slides and papers of one course are on the phone
  /// right now — counted off the catalogue, not off the last run.
  ///
  /// A run only knows what IT moved, and an Update that found every
  /// picture already here reported "0 pictures" over a phone full of
  /// them. The catalogue is the truth about what is held.
  int heldFilesFor(String courseId) => heldFileIdsFor(courseId).length;

  /// The ids of those, so a running download can keep a tally instead
  /// of re-counting the whole catalogue after every single file.
  Iterable<String> heldFileIdsFor(String courseId) => courseId.isEmpty
      ? const []
      : _items.values
          .where((i) => i.courseId == courseId && i.kind != 'questions')
          .map((i) => i.id);

  /// Drops a document filed under a MATERIAL id while keeping the row.
  ///
  /// One thing needs this: an older build filed a note's first attached
  /// PDF as a document under the note's own id, and nothing reads that
  /// any more — attachments are opened by URL out of the asset store.
  /// Left there it is the same file twice on a phone that has to count
  /// its megabytes, and worse, [putNote] rewrites the row's `bytes` to
  /// the length of the note body, so those megabytes stop counting
  /// against the library ceiling while still sitting on the disk.
  ///
  /// Only ever called once the replacement really is held.
  Future<void> forgetDocument(String id) async {
    final i = _items[id];
    if (i == null || !i.hasDoc) return;
    try {
      final f = File(resolve(i.docRel!));
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _items[id] = OfflineItem(
      id: i.id,
      title: i.title,
      courseCode: i.courseCode,
      courseId: i.courseId,
      kind: i.kind,
      docRel: null,
      htmlRel: i.htmlRel,
      bytes: i.hasHtml ? i.bytes : 0,
      savedAtMs: i.savedAtMs,
      sig: i.sig,
      pinned: i.pinned,
      attachments: i.attachments,
    );
    _touch();
    await flush();
  }

  /// Forgets one asset so the next download fetches it again. Used when
  /// the catalogue says a picture is here and the disk disagrees.
  Future<void> forgetAsset(String url) async {
    final key = assetKeyFor(url);
    final a = _assets.remove(key);
    if (a == null) return;
    try {
      final f = File(resolve(a.rel));
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _touch();
    // Written now, not in two and a half seconds. This runs at the
    // START of a download, and a download on these phones is routinely
    // killed or backgrounded early — leaving a catalogue that still
    // claims a file this call has already deleted.
    await flush();
  }

  // ------------------------------------------------------------
  // Which questions an offline round handed out last
  // ------------------------------------------------------------

  /// Question ids recently served to an offline round in this bucket,
  /// oldest first. Deliberately a memory rather than a rule: the picker
  /// prefers what is NOT in here, and only reaches into it when the
  /// bank is smaller than the round.
  ///
  /// An offline round used to be a fresh shuffle of the whole bank every
  /// time, with no memory at all — so a 75-question course dealt the
  /// same handful again and again ("it's repeating almost the same
  /// question"). Twenty from seventy-five overlap by five on average,
  /// and by the fourth round most of what comes up has been seen.
  List<String> recentlyServed(String bucket) =>
      List.unmodifiable(_served[_safeName(bucket)] ?? const []);

  /// Records the ids of the round just dealt. Kept as a ring of the
  /// last [kServedMemory] so the memory covers several rounds of the
  /// biggest bank without growing for ever.
  Future<void> rememberServed(String bucket, Iterable<String> ids) async {
    final key = _safeName(bucket);
    final ring = _served[key] ?? <String>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      ring.remove(id);
      ring.add(id);
    }
    while (ring.length > kServedMemory) {
      ring.removeAt(0);
    }
    _served[key] = ring;
    // Coalesced like every other convenience write. Flushing here put
    // a whole-catalogue encode and fsync on the UI isolate in front of
    // the first question of every offline round.
    _touch();
  }

  /// Removes a course from the phone entirely — its record, its
  /// question bank, and every note, file and picture belonging to it.
  ///
  /// This is what clears a course Tutor Bello took down. The Vault
  /// cannot do it: `readable` filters out the question bucket (kind
  /// 'questions') so the bank is invisible there, and `evictFor` skips
  /// it too — yet its bytes still count against the ceiling in
  /// [canWrite]. A withdrawn course's dead megabytes were therefore
  /// unreachable through any screen in the app while still being able
  /// to produce "your offline library is full".
  ///
  /// Returns the bytes reclaimed.
  Future<int> forgetCourse(String courseId) async {
    if (courseId.isEmpty) return 0;
    var freed = 0;

    // The question bank first: one item, one file, invisible everywhere.
    final safe = _safeName(courseId);
    final bank = _items['q:$safe'];
    if (bank != null) {
      freed += bank.bytes;
      for (final id in (await questions(courseId)).map((r) => '${r['id']}')) {
        _questionHome.remove(id);
      }
      try {
        final f = File(resolve('questions/$safe.json'));
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _items.remove('q:$safe');
    }

    // Then everything else belonging to it.
    for (final i in _items.values
        .where((i) => i.courseId == courseId)
        .toList(growable: false)) {
      freed += i.bytes;
      await removeItem(i.id);
    }

    _courses.remove(courseId);
    // And what it had dealt. Left behind, a course the student removed
    // and downloaded again came back with every question already
    // counted as seen — so the first round after a re-download was
    // dealt entirely out of the "seen lately" pile, which is the
    // repetition the ring exists to prevent.
    _served.remove(_safeName(courseId));
    _touch();
    await flush();
    debugPrint('[offline] forgot $courseId, reclaimed ${formatBytes(freed)}');
    return freed;
  }

  /// Every course this phone has downloaded, in no particular order.
  Iterable<String> get downloadedCourses => _courses.keys;

  // ------------------------------------------------------------
  // Paths
  // ------------------------------------------------------------

  /// Turns a stored relative path back into a real one. The head is
  /// always today's container, which is what makes an iOS restore
  /// survivable.
  String resolve(String rel) => '${_root.path}/$rel';

  Future<Directory> _bucket(String name) async {
    final d = Directory('${_root.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Writes bytes into a bucket atomically and returns the relative path.
  Future<String> _write(String bucket, String name, List<int> bytes) async {
    final dir = await _bucket(bucket);
    await _atomicWrite(
      File('${dir.path}/$name'),
      (f) => f.writeAsBytes(bytes, flush: true),
    );
    return '$bucket/$name';
  }

  Future<String> _writeText(String bucket, String name, String text) async {
    final dir = await _bucket(bucket);
    await _atomicWrite(
      File('${dir.path}/$name'),
      (f) => f.writeAsString(text, flush: true),
    );
    return '$bucket/$name';
  }

  // ------------------------------------------------------------
  // Room to write
  //
  // The store used to have no ceiling, no eviction and no idea how full
  // the phone was. On a nearly full 32 GB device every write failed with
  // ENOSPC, each failure was caught and logged, and the sync still
  // finished by announcing "Saved for offline" — after which every Open
  // failed, offline, with the file never having existed.
  //
  // That is the same lie as the one this app already shipped once in the
  // other direction, when it told a student with 256 GB free to clear
  // room. Being wrong about storage in either direction destroys trust
  // in the whole feature.
  // ------------------------------------------------------------

  /// Never fill a student's phone. A library beyond this is not worth
  /// the app being blamed for a device that will not take a photograph.
  static const int maxTotalBytes = 900 * 1024 * 1024;

  /// Leave this much of the DEVICE free, whatever our own ceiling says.
  static const int keepFreeBytes = 400 * 1024 * 1024;

  int _freeBytes = -1; // -1 = not measured yet

  /// How much space the phone actually has. Measured with statvfs
  /// through a temporary file, because Dart exposes no free-space API
  /// and the alternative is guessing.
  Future<int> freeSpace({bool refresh = false}) async {
    if (_freeBytes >= 0 && !refresh) return _freeBytes;
    try {
      final result = await Process.run('df', ['-kP', _root.path])
          .timeout(const Duration(seconds: 3));
      final lines = '${result.stdout}'.trim().split('\n');
      if (lines.length >= 2) {
        final cols = lines.last.trim().split(RegExp(r'\s+'));
        if (cols.length >= 4) {
          final kb = int.tryParse(cols[3]);
          if (kb != null) return _freeBytes = kb * 1024;
        }
      }
    } catch (_) {
      // df is not available on iOS or in a locked-down sandbox. Fall
      // through: unknown free space must not stop a student saving a
      // note, so it is treated as "enough" and the write itself is the
      // real test — which is why every write is checked afterwards.
    }
    return _freeBytes = -1;
  }

  /// Whether [bytes] can be written without filling the device or
  /// blowing our own ceiling. Answers honestly, and says why not.
  Future<({bool ok, String? reason})> canWrite(int bytes) async {
    if (totalBytes + bytes > maxTotalBytes) {
      return (
        ok: false,
        reason: 'Your offline library is full. Remove something from the '
            'Vault to make room.',
      );
    }
    final free = await freeSpace();
    if (free >= 0 && free - bytes < keepFreeBytes) {
      return (
        ok: false,
        reason: 'This phone is nearly out of space. Free some up and try '
            'again.',
      );
    }
    return (ok: true, reason: null);
  }

  /// Confirms a file really is on disk at the size we think.
  ///
  /// The verification pass. A catalogue entry is a claim; this is the
  /// check. Used after a download so "Saved" means saved.
  Future<bool> verifyItem(String id) async {
    final i = _items[id];
    if (i == null) return false;
    var sawSomething = false;
    for (final rel in [i.docRel, i.htmlRel]) {
      if (rel == null || rel.isEmpty) continue;
      try {
        final f = File(resolve(rel));
        if (!await f.exists()) return false;
        // A zero-length file is a truncated write — unless it is the
        // body of a note that HAS no body yet, which is saved as an
        // empty file on purpose so the note still has an entry and its
        // attachments still have a home.
        //
        // The row may ALSO carry a document: an older build filed a
        // note's first attached PDF under the note's own id, and
        // putNote carries that docRel forward. Refusing such a row
        // handed an upgrading student the "N files did not save" loop
        // back on every run, with every byte present on the disk — so
        // when a document is there it is the substance and an empty
        // body is never the thing that fails the check.
        final emptyByDesign = rel == i.htmlRel && (i.hasDoc || i.bytes == 0);
        if (await f.length() <= 0 && !emptyByDesign) return false;
        sawSomething = true;
      } catch (_) {
        return false;
      }
    }
    return sawSomething;
  }

  Future<bool> verifyAsset(String url) async {
    final a = _assets[assetKeyFor(url)];
    if (a == null) return false;
    try {
      final f = File(resolve(a.rel));
      return await f.exists() && await f.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the least recently saved unpinned items until [wanted]
  /// bytes fit under the ceiling. Pinned items — the ones a student
  /// chose by hand — are never touched.
  Future<int> evictFor(int wanted) async {
    if (totalBytes + wanted <= maxTotalBytes) return 0;
    final candidates = _items.values
        .where((i) => !i.pinned && i.kind != 'questions')
        .toList()
      ..sort((a, b) => a.savedAtMs.compareTo(b.savedAtMs));

    var freed = 0;
    for (final i in candidates) {
      if (totalBytes + wanted <= maxTotalBytes) break;
      freed += i.bytes;
      await removeItem(i.id);
    }
    if (freed > 0) debugPrint('[offline] evicted ${formatBytes(freed)}');
    return freed;
  }

  /// Sweeps staging files and files with no catalogue entry.
  ///
  /// A phone that kills the app mid-sync — which is what these phones
  /// do — leaves `.part` files behind, and an entry lost from the
  /// catalogue orphans its file forever: it does not show in the Vault,
  /// cannot be removed from it, and still counts against the student's
  /// storage.
  Future<int> sweep() async {
    var reclaimed = 0;
    final live = <String>{
      for (final i in _items.values) ...[
        if (i.docRel != null) i.docRel!,
        if (i.htmlRel != null) i.htmlRel!,
      ],
      for (final a in _assets.values) a.rel,
    };

    for (final bucket in const ['notes', 'docs', 'assets', 'questions']) {
      try {
        final dir = Directory('${_root.path}/$bucket');
        if (!await dir.exists()) continue;
        await for (final f in dir.list()) {
          if (f is! File) continue;
          final rel = '$bucket/${f.uri.pathSegments.last}';
          final isStaging = rel.contains('.part');
          if (!isStaging && live.contains(rel)) continue;
          // questions/ is indexed by item, not by path, so keep any
          // bucket file whose catalogue row exists.
          if (!isStaging && bucket == 'questions') continue;
          try {
            reclaimed += await f.length();
            await f.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
    if (reclaimed > 0) {
      debugPrint('[offline] reclaimed ${formatBytes(reclaimed)} of dead files');
    }
    return reclaimed;
  }

  // ------------------------------------------------------------
  // Items
  // ------------------------------------------------------------

  List<OfflineItem> get items {
    final list = _items.values.toList()
      ..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return list;
  }

  /// The rows the Vault screen shows: everything a student can open with
  /// no data at all. Question sets are counted separately.
  List<OfflineItem> get readable =>
      items.where((i) => i.kind != 'questions').toList();

  OfflineItem? item(String id) => _items[id];

  bool has(String id) => _items.containsKey(id);

  /// True when we already hold this exact version.
  bool isCurrent(String id, String sig) {
    final i = _items[id];
    return i != null && sig.isNotEmpty && i.sig == sig;
  }

  int get totalBytes {
    var n = 0;
    for (final i in _items.values) {
      n += i.bytes;
    }
    for (final a in _assets.values) {
      n += a.bytes;
    }
    return n;
  }

  /// Saves a note body. Cheap enough that every note is kept.
  ///
  /// An EMPTY body is saved too. A note Tutor Bello has not typed yet
  /// but has clipped a PDF to is a real note — the student opens it for
  /// the PDF — and refusing to catalogue it left every such note with
  /// no entry at all, so offline it "did not open" and every download
  /// counted it as a file that did not save.
  Future<OfflineItem> putNote({
    required String id,
    required String title,
    required String html,
    String courseCode = '',
    String courseId = '',
    String sig = '',
    bool pinned = false,
    List<OfflineAttachment>? attachments,
  }) async {
    final rel = await _writeText('notes', '$id.html', html);
    final existing = _items[id];
    final entry = OfflineItem(
      id: id,
      title: title,
      courseCode: courseCode,
      courseId: courseId,
      kind: 'note',
      htmlRel: rel,
      docRel: existing?.docRel,
      bytes: utf8.encode(html).length,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      sig: sig,
      pinned: pinned || (existing?.pinned ?? false),
      attachments: attachments ?? existing?.attachments ?? const [],
    );
    _items[id] = entry;
    _touch();
    return entry;
  }

  /// Saves a downloaded document.
  Future<OfflineItem> putDocument({
    required String id,
    required String title,
    required String kind,
    required List<int> bytes,
    required String extension,
    String courseCode = '',
    String courseId = '',
    String sig = '',
    bool pinned = true,
    String? html,
    List<OfflineAttachment>? attachments,
  }) async {
    final rel = await _write('docs', '$id.$extension', bytes);
    final existing = _items[id];
    String? htmlRel = existing?.htmlRel;
    if (html != null && html.isNotEmpty) {
      htmlRel = await _writeText('notes', '$id.html', html);
    }
    final entry = OfflineItem(
      id: id,
      title: title,
      courseCode: courseCode,
      courseId: courseId,
      kind: kind,
      docRel: rel,
      htmlRel: htmlRel,
      bytes: bytes.length,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      sig: sig,
      pinned: pinned,
      attachments: attachments ?? existing?.attachments ?? const [],
    );
    _items[id] = entry;
    _touch();
    return entry;
  }

  Future<String?> readNote(String id) async {
    final rel = _items[id]?.htmlRel;
    if (rel == null || rel.isEmpty) return null;
    try {
      final f = File(resolve(rel));
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  /// The absolute path of a document, or null when the file is gone.
  Future<String?> documentPath(String id) async {
    final rel = _items[id]?.docRel;
    if (rel == null || rel.isEmpty) return null;
    final path = resolve(rel);
    try {
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeItem(String id) async {
    final i = _items.remove(id);
    if (i == null) return;
    for (final rel in [i.docRel, i.htmlRel]) {
      if (rel == null || rel.isEmpty) continue;
      try {
        final f = File(resolve(rel));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _touch();
    await flush();
  }

  /// Drops catalogue rows whose files have gone. The website shipped the
  /// opposite bug — an index that outlived its files, so Open led
  /// nowhere.
  Future<int> reconcile() async {
    var dropped = 0;
    for (final entry in _items.entries.toList()) {
      final i = entry.value;
      var alive = false;
      for (final rel in [i.docRel, i.htmlRel]) {
        if (rel == null || rel.isEmpty) continue;
        try {
          if (await File(resolve(rel)).exists()) alive = true;
        } catch (_) {}
      }
      if (!alive) {
        _items.remove(entry.key);
        dropped++;
      }
    }
    for (final entry in _assets.entries.toList()) {
      try {
        if (!await File(resolve(entry.value.rel)).exists()) {
          _assets.remove(entry.key);
          dropped++;
        }
      } catch (_) {}
    }
    if (dropped > 0) {
      _touch();
      await flush();
    }
    return dropped;
  }

  // ------------------------------------------------------------
  // Assets
  // ------------------------------------------------------------

  /// The local path for an image or audio file, or null when it is not
  /// held. Synchronous on purpose: a widget's build() cannot await, and
  /// an image that flickers in a frame late is worse than one that is
  /// simply drawn from disk.
  String? assetPath(String? url) {
    if (url == null || url.isEmpty) return null;
    final a = _assets[assetKeyFor(url)];
    return a == null ? null : resolve(a.rel);
  }

  bool hasAsset(String url) => _assets.containsKey(assetKeyFor(url));

  Future<OfflineAsset> putAsset(String url, List<int> bytes) async {
    final key = assetKeyFor(url);
    final rel = await _write(
      'assets',
      '$key.${extensionForUrl(url, fallback: 'img')}',
      bytes,
    );
    final a = OfflineAsset(
      rel: rel,
      bytes: bytes.length,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _assets[key] = a;
    _touch();
    return a;
  }

  int get assetCount => _assets.length;

  int get assetBytes {
    var n = 0;
    for (final a in _assets.values) {
      n += a.bytes;
    }
    return n;
  }

  // ------------------------------------------------------------
  // Questions
  // ------------------------------------------------------------

  /// Question sets are stored per bucket — a course id, or `mistakes`,
  /// or `bookmarks`. Writing one whole is cheaper and far easier to
  /// reason about than a row store, and the sets are small.
  /// [complete] says the incoming rows are WHOLE — every field the
  /// backend has for that question, not a partial view.
  ///
  /// The merge below exists because a question arrives in different
  /// states of undress depending on when it is seen, and overwriting
  /// would strip a key the phone already held. But the same rule means
  /// an edit that CLEARS a field never lands: Tutor Bello deletes a
  /// wrong explanation and the phone keeps showing it, for ever,
  /// because "empty" always loses to "held".
  ///
  /// A course download sends complete rows, so it passes true and the
  /// incoming value wins outright — a cleared field really clears.
  Future<void> putQuestions(
    String bucket,
    List<Map<String, dynamic>> rows, {
    bool complete = false,
  }) async {
    if (rows.isEmpty) return;
    final safe = _safeName(bucket);

    // MERGED, not replaced, and merged field by field.
    //
    // The same question arrives in different states of undress
    // depending on when it is seen. On the direct path an attempt opens
    // with the answer key stripped and only fills it in once the
    // student has answered; a result review carries the explanation; a
    // second attempt on the same course carries neither. Overwriting
    // the bucket with whichever copy arrived last would strip a key we
    // already held — and a cached question with no key cannot be marked
    // offline, which is the whole point of keeping it.
    final merged = <String, Map<String, dynamic>>{};
    for (final existing in await questions(bucket)) {
      final id = '${existing['id'] ?? ''}';
      if (id.isNotEmpty) merged[id] = existing;
    }
    for (final row in rows) {
      final id = '${row['id'] ?? ''}';
      if (id.isEmpty) continue;
      _questionHome[id] = bucket;
      final before = merged[id];
      if (before == null) {
        merged[id] = row;
        continue;
      }
      if (complete) {
        // A whole row from a course download. It is the truth, including
        // the parts of it that are now empty.
        merged[id] = row;
        continue;
      }
      final out = Map<String, dynamic>.from(before);
      row.forEach((k, v) {
        final incomingIsEmpty =
            v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);
        final heldIsEmpty = out[k] == null ||
            (out[k] is String && (out[k] as String).trim().isEmpty) ||
            (out[k] is List && (out[k] as List).isEmpty);
        if (!incomingIsEmpty || heldIsEmpty) out[k] = v;
      });
      merged[id] = out;
    }

    await _writeText(
      'questions',
      '$safe.json',
      jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'rows': merged.values.toList(),
      }),
    );
    final bytes = await _sizeOf('questions/$safe.json');
    _items['q:$safe'] = OfflineItem(
      id: 'q:$safe',
      title: bucket,
      kind: 'questions',
      courseId: bucket,
      htmlRel: 'questions/$safe.json',
      bytes: bytes,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      sig: '${merged.length}',
    );
    _touch();
  }

  /// Drops questions the backend no longer publishes.
  ///
  /// The bank only ever merged, so a question Tutor Bello unpublished or
  /// deleted stayed here for ever — practisable, with its answer key,
  /// long after he had decided it was wrong.
  ///
  /// [alive] must be the FULL set of ids the course still SERVES —
  /// which excludes the ones pinned to a published test, so a question
  /// Tutor Bello puts on an exam after a download has its answer key
  /// taken off the phone.
  ///
  /// An empty set is a legitimate answer and prunes everything: a
  /// course whose every question is now pinned, or one emptied out.
  /// Refusing to act on emptiness left exactly those courses holding
  /// withdrawn questions for ever. A caller that could not READ the
  /// list must not call this at all — see CourseIndex.isUsable.
  ///
  /// Returns how many were dropped.
  Future<int> pruneQuestions(String bucket, Set<String> alive) async {
    final held = await questions(bucket);
    if (held.isEmpty) return 0;

    final keep = held
        .where((r) => alive.contains('${r['id'] ?? ''}'))
        .toList(growable: false);
    final dropped = held.length - keep.length;
    if (dropped <= 0) return 0;

    for (final r in held) {
      final id = '${r['id'] ?? ''}';
      if (!alive.contains(id)) _questionHome.remove(id);
    }

    final safe = _safeName(bucket);
    await _writeText(
      'questions',
      '$safe.json',
      jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'rows': keep,
      }),
    );
    final existing = _items['q:$safe'];
    if (existing != null) {
      _items['q:$safe'] = existing.copyWith(
        bytes: await _sizeOf('questions/$safe.json'),
        sig: '${keep.length}',
      );
    }
    _touch();
    await flush();
    debugPrint('[offline] dropped $dropped withdrawn questions from $bucket');
    return dropped;
  }

  /// Drops saved materials the backend no longer publishes.
  ///
  /// Same reasoning: an unpublished note, slide or past-question paper
  /// stayed readable on the phone with no way for anybody to withdraw
  /// it. Only items belonging to [courseId] are considered, so a
  /// partial view of one course cannot touch another.
  Future<int> pruneMaterials(String courseId, Set<String> alive) async {
    if (courseId.isEmpty || alive.isEmpty) return 0;
    final doomed = _items.values
        .where((i) =>
            i.kind != 'questions' &&
            i.courseId == courseId &&
            !alive.contains(i.id))
        .map((i) => i.id)
        .toList(growable: false);
    for (final id in doomed) {
      await removeItem(id);
    }
    if (doomed.isNotEmpty) {
      debugPrint('[offline] dropped ${doomed.length} withdrawn materials');
    }
    return doomed.length;
  }

  Future<List<Map<String, dynamic>>> questions(String bucket) async {
    try {
      final f = File(resolve('questions/${_safeName(bucket)}.json'));
      if (!await f.exists()) return const [];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return const [];
      final rows = decoded['rows'];
      if (rows is! List) return const [];
      final out = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final r in out) {
        final id = '${r['id'] ?? ''}';
        if (id.isNotEmpty) _questionHome[id] = bucket;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Which bucket holds one question, without decoding all of them.
  ///
  /// Answers from memory once anything has been read. A miss costs one
  /// pass over the buckets, and only the first miss — after that the map
  /// is complete.
  Future<String?> bucketFor(String questionId) async {
    final known = _questionHome[questionId];
    if (known != null) return known;
    if (_homeMapped) return null;
    for (final i in _items.values.where((i) => i.kind == 'questions')) {
      await questions(i.courseId);
      final found = _questionHome[questionId];
      if (found != null) return found;
    }
    _homeMapped = true;
    return _questionHome[questionId];
  }

  /// Patches the fields of ONE cached question, touching one file.
  ///
  /// This is what the answer-verdict path uses. It used to call
  /// putQuestions, which reads the whole bucket, merges, re-encodes and
  /// writes it back — for every bucket in the catalogue, to change one
  /// row.
  Future<bool> patchQuestion(
    String questionId,
    Map<String, dynamic> fields,
  ) async {
    if (fields.isEmpty) return false;
    final bucket = await bucketFor(questionId);
    if (bucket == null) return false;
    try {
      final rows = await questions(bucket);
      var touched = false;
      for (final r in rows) {
        if ('${r['id'] ?? ''}' != questionId) continue;
        fields.forEach((k, v) {
          final empty = v == null || (v is String && v.trim().isEmpty);
          if (!empty) r[k] = v;
        });
        touched = true;
        break;
      }
      if (!touched) return false;
      final safe = _safeName(bucket);
      await _writeText(
        'questions',
        '$safe.json',
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'rows': rows,
        }),
      );
      return true;
    } catch (e) {
      debugPrint('[offline] could not patch $questionId: $e');
      return false;
    }
  }

  /// Every question held, from every bucket, de-duplicated by id.
  Future<List<Map<String, dynamic>>> allQuestions() async {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final i in _items.values.where((i) => i.kind == 'questions')) {
      for (final row in await questions(i.courseId)) {
        final id = '${row['id'] ?? ''}';
        if (id.isEmpty || !seen.add(id)) continue;
        out.add(row);
      }
    }
    return out;
  }

  int get questionCount {
    var n = 0;
    for (final i in _items.values.where((i) => i.kind == 'questions')) {
      n += (i.sig.isEmpty ? 0 : int.tryParse(i.sig) ?? 0);
    }
    return n;
  }

  // ------------------------------------------------------------
  // Attempts done with no signal
  // ------------------------------------------------------------

  /// A practice round taken offline. Kept apart from the catalogue
  /// because it is the student's own work, not downloaded content, and
  /// it must survive a sync that rewrites everything else.
  Future<void> putAttempt(String id, Map<String, dynamic> data) =>
      _writeText('attempts', '${_safeName(id)}.json', jsonEncode(data));

  Future<Map<String, dynamic>?> attempt(String id) async {
    try {
      final f = File(resolve('attempts/${_safeName(id)}.json'));
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> attempts() async {
    final out = <Map<String, dynamic>>[];
    try {
      final dir = Directory('${_root.path}/attempts');
      if (!await dir.exists()) return out;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await f.readAsString());
          if (decoded is Map) out.add(Map<String, dynamic>.from(decoded));
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0));
    return out;
  }

  Future<void> removeAttempt(String id) async {
    try {
      final f = File(resolve('attempts/${_safeName(id)}.json'));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<int> _sizeOf(String rel) async {
    try {
      return await File(resolve(rel)).length();
    } catch (_) {
      return 0;
    }
  }

  static String _safeName(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

/// ============================================================
/// THE ONE HANDLE
///
/// `LocalStore.instance` already establishes the pattern, and this needs
/// it for a harder reason: a widget's `build()` cannot await, and
/// `WidgetFactory.imageProviderFromNetwork` — the hook that lets an
/// `<img>` inside a note body be served from disk — is a synchronous
/// override with no BuildContext and therefore no Riverpod ref.
///
/// So the store is published here once, at boot, and read from there.
/// Everything on it that a widget touches is already in memory.
/// ============================================================
abstract final class Offline {
  static OfflineStore? store;

  static bool get ready => store != null;

  /// The on-disk path for a picture or a voice note, or null when we do
  /// not hold it. Safe to call from build().
  static String? pathFor(String? url) => store?.assetPath(url);

  static bool holds(String? url) =>
      url != null && url.isNotEmpty && (store?.hasAsset(url) ?? false);
}

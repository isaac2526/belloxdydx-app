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
  });

  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);
  bool get hasDoc => (docRel ?? '').isNotEmpty;
  bool get hasHtml => (htmlRel ?? '').isNotEmpty;

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
      };
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
    } catch (e) {
      debugPrint('[offline] unreadable index, starting clean: $e');
      _items.clear();
      _assets.clear();
    }
  }

  /// Writes the catalogue. Coalesced, because a sync touches it once per
  /// file and the catalogue is written whole.
  void _touch() {
    _dirty = true;
    _flush ??= Timer(const Duration(milliseconds: 600), () {
      _flush = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
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
      });
      // Written aside and renamed: a kill mid-write leaves the previous
      // catalogue intact instead of a truncated one.
      final tmp = File('${_indexFile.path}.part');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(_indexFile.path);
    } catch (e) {
      debugPrint('[offline] index write failed: $e');
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
    final target = File('${dir.path}/$name');
    final tmp = File('${target.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    return '$bucket/$name';
  }

  Future<String> _writeText(String bucket, String name, String text) async {
    final dir = await _bucket(bucket);
    final target = File('${dir.path}/$name');
    final tmp = File('${target.path}.part');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
    return '$bucket/$name';
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
  Future<OfflineItem> putNote({
    required String id,
    required String title,
    required String html,
    String courseCode = '',
    String courseId = '',
    String sig = '',
    bool pinned = false,
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
  }) async {
    final rel = await _write('docs', '$id.$extension', bytes);
    String? htmlRel = _items[id]?.htmlRel;
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
  Future<void> putQuestions(String bucket, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final safe = _safeName(bucket);
    await _writeText(
      'questions',
      '$safe.json',
      jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'rows': rows}),
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
      sig: '${rows.length}',
    );
    _touch();
  }

  Future<List<Map<String, dynamic>>> questions(String bucket) async {
    try {
      final f = File(resolve('questions/${_safeName(bucket)}.json'));
      if (!await f.exists()) return const [];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return const [];
      final rows = decoded['rows'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
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

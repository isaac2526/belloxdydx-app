import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'failures.dart';
import 'offline/offline_store.dart';
import 'models.dart';

/// ============================================================
/// THE BACKEND GATEWAY
///
/// This is where the Vercel bill is decided.
///
/// The audit found that every student action — every page, every
/// question, every answer, every file — passed through Next.js on
/// Vercel, because Row Level Security was enabled with almost no
/// policies, so nothing could be read without the service role key.
///
/// This gateway supports two paths and picks the cheaper one it can
/// actually use:
///
///   DIRECT  — Flutter → Supabase (Postgres RPC + RLS + Storage +
///             Realtime). Vercel is not in the path at all. Grading
///             happens inside Postgres, so the answer key never
///             reaches the device.
///
///   LEGACY  — Flutter → Vercel API → Supabase. Exactly what the app
///             does today. Kept so the app works against the current
///             backend before the SQL migration is applied, and as an
///             automatic fallback if an RPC is ever unavailable.
///
/// The mode is probed once at startup by calling bx_capabilities().
/// Nothing breaks if the migration has not been run — the app simply
/// stays on the legacy path and costs what it costs today.
/// ============================================================

/// A storage URL sitting inside a larger string — an `<img src>`, an
/// `<a href>`, a CSS `url()`.
final RegExp kEmbeddedStorageUrl = RegExp(
  r'''https?://[^\s"'<>()]*?/storage/v1/object/public/[^\s"'<>()]*''',
);

/// True when the whole string is one URL and nothing else.
bool isBareUrl(String s) {
  final t = s.trim();
  if (!t.startsWith('http://') && !t.startsWith('https://')) return false;
  return !t.contains(RegExp(r'[\s<>"]'));
}

/// Rewrites Supabase storage links so they go through the website's
/// caching proxy — in place, without destroying what surrounds them.
///
/// A URL FIELD becomes a proxied URL. An HTML BODY that merely mentions
/// a storage URL keeps its markup and has just that URL swapped.
///
/// That distinction is the whole point. This used to ask whether a
/// string CONTAINED a storage URL and then replace the entire string,
/// so any question or note with an embedded image had its whole body
/// turned into one `…/api/file?u=<base64 of the document>`. Students
/// were shown that URL where the question should have been, with the
/// text and the image both gone — and only on the website path, which
/// is the path production runs on.
///
/// [proxy] takes one URL and returns its replacement.
String shieldStorageUrls(String node, String Function(String) proxy) {
  if (!node.contains('/storage/v1/object/public/')) return node;
  return isBareUrl(node)
      ? proxy(node)
      : node.replaceAllMapped(kEmbeddedStorageUrl, (m) => proxy(m.group(0)!));
}

enum BackendMode {
  /// Supabase-direct. Student traffic bypasses Vercel entirely.
  direct,

  /// Everything through the website API, as the app worked before.
  legacy,
}

class Backend {
  Backend({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  BackendMode _mode = BackendMode.legacy;
  BackendMode get mode => _mode;
  bool get isDirect => _mode == BackendMode.direct;

  int _capabilityVersion = 0;
  int get capabilityVersion => _capabilityVersion;

  SupabaseClient get sb => Supabase.instance.client;
  GoTrueClient get auth => sb.auth;
  User? get user => sb.auth.currentUser;
  String? get userId => sb.auth.currentUser?.id;
  bool get signedIn => sb.auth.currentSession != null;
  String? get accessToken => sb.auth.currentSession?.accessToken;

  /// The mobile session token the website issues for the single-session
  /// rule. Only used on the legacy path.
  String? mobileSessionToken;

  // ------------------------------------------------------------
  // Connectivity
  //
  // Only used to choose between two sentences: "no internet connection"
  // and "we could not reach Belloxdydx". A student can act on the first
  // and not the second, so telling them apart is worth a subscription.
  // It is never used to block a request — the radio can be up while the
  // network is useless, and the request itself is the real test.
  // ------------------------------------------------------------

  bool? _hasConnection;
  StreamSubscription<List<ConnectivityResult>>? _connWatch;

  bool? get hasConnection => _hasConnection;

  void watchConnectivity() {
    if (_connWatch != null) return;

    void apply(List<ConnectivityResult> r) {
      _hasConnection =
          !(r.isEmpty || r.every((x) => x == ConnectivityResult.none));
    }

    // Wrapped whole, and each call wrapped again inside.
    //
    // connectivity_plus reaches the platform differently on each OS, and
    // on some of them the failure does not arrive as a rejected future
    // at all — on Linux it surfaces as an unhandled SocketException from
    // a dbus connection deep inside the plugin, which takes down the
    // zone rather than the call. Knowing whether the radio is on is a
    // nicety; it decides which of two sentences a student is shown. It
    // may never be the reason the app stops.
    try {
      final conn = Connectivity();
      runZonedGuarded(() {
        unawaited(conn.checkConnectivity().then(apply).catchError((_) {}));
        _connWatch = conn.onConnectivityChanged.listen(apply, onError: (_) {});
      }, (e, _) => debugPrint('[net] connectivity unavailable: $e'));
    } catch (e) {
      debugPrint('[net] connectivity unavailable: $e');
    }
  }

  // ------------------------------------------------------------
  // Capability probe
  // ------------------------------------------------------------

  /// Asks the database whether the Belloxdydx RPC layer is installed.
  /// Cheap, runs once, and never throws — a failure just means legacy.
  Future<BackendMode> probeCapabilities() async {
    if (BxConfig.forceLegacyApi) {
      _mode = BackendMode.legacy;
      debugPrint('[backend] forced legacy mode');
      return _mode;
    }
    try {
      final res = await sb
          .rpc('bx_capabilities')
          .timeout(const Duration(seconds: 8));
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      final version = map == null ? 0 : (map['version'] as num?)?.toInt() ?? 0;
      if (version >= 1) {
        _capabilityVersion = version;
        _mode = BackendMode.direct;
        debugPrint('[backend] direct mode · rpc v$version (Vercel bypassed)');
      } else {
        _mode = BackendMode.legacy;
      }
    } catch (e) {
      // The RPC does not exist yet, or the network refused. Either way
      // the app keeps working on the path it already used.
      _mode = BackendMode.legacy;
      debugPrint('[backend] legacy mode · $e');
    }
    return _mode;
  }

  // ------------------------------------------------------------
  // Supabase helpers
  // ------------------------------------------------------------

  /// Calls a Postgres function. Returns the decoded payload.
  Future<Map<String, dynamic>> rpc(
    String fn, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final res = await sb.rpc(fn, params: params).timeout(timeout);
      if (res == null) return const {};
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'data': res};
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on TimeoutException {
      throw const BxError('That took too long. Try again.');
    } catch (e) {
      throw _mapGeneric(e);
    }
  }

  /// Calls a Postgres function expected to return a list.
  Future<List<Map<String, dynamic>>> rpcList(
    String fn, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final res = await sb.rpc(fn, params: params).timeout(timeout);
      if (res is List) {
        return res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (res is Map && res['items'] is List) {
        return (res['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on TimeoutException {
      throw const BxError('That took too long. Try again.');
    } catch (e) {
      throw _mapGeneric(e);
    }
  }

  /// A plain table/view read. Only ever touches tables that RLS opens
  /// to the signed-in student.
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, Object> eq = const {},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      dynamic q = sb.from(table).select(columns);
      eq.forEach((k, v) => q = q.eq(k, v));
      if (orderBy != null) q = q.order(orderBy, ascending: ascending);
      if (limit != null) q = q.limit(limit);
      final res = await q.timeout(const Duration(seconds: 20));
      return (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on TimeoutException {
      throw const BxError('That took too long. Try again.');
    } catch (e) {
      throw _mapGeneric(e);
    }
  }

  /// Public storage URL, straight from Supabase's CDN.
  ///
  /// On the direct path this is what a student's device fetches — the
  /// bytes never touch Vercel, which the audit identified as the single
  /// largest transfer cost. On the legacy path we keep the website's
  /// /api/file shield so behaviour is unchanged.
  String fileUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';

    // The website's own shield returns a ROOT-RELATIVE "/api/file?u=…".
    // A browser resolves that against the page it is on; this app has no
    // page, and Dart's HttpClient throws "No host specified in URI" —
    // which is why every CBT, millionaire and practice-explanation
    // image failed. Give it an origin whoever sent it.
    final absolute = raw.startsWith('/') ? '${BxConfig.siteUrl}$raw' : raw;

    // …then unwrap it. /api/file is a 302 to the public storage URL and
    // nothing else: it carries no bytes, holds no secret, and checks no
    // session. Going through it costs one Vercel invocation and one
    // extra round trip per picture, and it is the reason media clients
    // struggled — ExoPlayer and AVPlayer have to follow a redirect
    // before they can even ask for a byte range. The app talks to
    // storage directly. Supabase serves exactly the same bytes either
    // way, so this is pure saving.
    final direct = canonicalAssetUrl(absolute);
    if (direct.contains('/storage/v1/object/public/')) return direct;
    return absolute;
  }

  /// Walks a decoded payload and rewrites every storage URL it finds.
  /// Rewrites every storage URL in a decoded payload.
  ///
  /// The map branch rebuilds a `Map<String, dynamic>` by hand rather
  /// than using Map.map. Map.map infers its type arguments from the
  /// closure, and with a dynamic key and a dynamic value that inference
  /// lands on `Map<dynamic, dynamic>` — which is not a
  /// `Map<String, dynamic>` and cannot be passed to any fromJson in this
  /// app. On the web that failure is invisible, because dart2js drops
  /// implicit downcast checks in release; on Android and iOS the runtime
  /// is sound and every model built from a shielded payload throws.
  /// So: browser tests cannot catch this, and `backend_test.dart` does.
  dynamic shieldDeep(dynamic node) {
    if (node is String) {
      if (!node.contains('/storage/v1/object/public/')) return node;

      // A URL field becomes a proxied URL. An HTML BODY that merely
      // MENTIONS a storage URL must have that one URL rewritten in
      // place — not be replaced wholesale.
      //
      // It used to be replaced wholesale, and the consequences were
      // severe: any question or note whose HTML embedded an image had
      // its entire body swapped for a single
      // "https://…/api/file?u=<base64 of the whole document>". The
      // student saw that URL printed where the question should have
      // been, the text was gone, and the image with it. It only
      // happened on the website path, which is the path production
      // runs on.
      return shieldStorageUrls(node, fileUrl);
    }
    if (node is List) return node.map(shieldDeep).toList();
    if (node is Map) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): shieldDeep(entry.value),
      };
    }
    return node;
  }

  // ------------------------------------------------------------
  // Website API (legacy path + the few endpoints that must stay
  // server-side, such as the AI proxy which holds the Gemini key)
  // ------------------------------------------------------------

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'x-bx-client': 'app',
        if (mobileSessionToken != null) 'x-bx-session': mobileSessionToken!,
      };

  Uri _uri(String path) => Uri.parse('${BxConfig.siteUrl}$path');

  Future<Map<String, dynamic>> apiGet(
    String path, {
    Duration timeout = const Duration(seconds: 25),
    int retries = 2,
  }) async {
    Object? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final r =
            await _http.get(_uri(path), headers: _headers).timeout(timeout);
        return _decode(r);
      } catch (e) {
        last = e;
        if (attempt < retries) {
          await Future<void>.delayed(
              Duration(milliseconds: 350 * (attempt + 1)));
        }
      }
    }
    throw _mapGeneric(last ?? 'unknown');
  }

  Future<Map<String, dynamic>> apiSend(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final uri = _uri(path);
      final payload = body == null ? null : jsonEncode(body);
      final r = await switch (method) {
        'PUT' => _http.put(uri, headers: _headers, body: payload),
        'PATCH' => _http.patch(uri, headers: _headers, body: payload),
        'DELETE' => _http.delete(uri, headers: _headers, body: payload),
        _ => _http.post(uri, headers: _headers, body: payload),
      }
          .timeout(timeout);
      return _decode(r);
    } catch (e) {
      throw _mapGeneric(e);
    }
  }

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(r.body);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'data': decoded};
    } catch (_) {
      body = const {};
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;

    final code = body['error']?.toString();
    final fault = faultForStatus(r.statusCode, errorCode: code);

    // A freeze reason is written by Tutor Bello for this student, so it
    // is worth showing — but only after safeServerMessage has satisfied
    // itself that it is a sentence and not machinery.
    final reason = safeServerMessage(body['reason']) ??
        safeServerMessage(body['message']);

    throw BxError(
      fault == BxFault.frozen && reason != null ? reason : fault.message,
      code: fault.code ?? code,
    );
  }

  // ------------------------------------------------------------
  // Error mapping — a student never sees a host name or a stack trace
  // ------------------------------------------------------------

  BxError _mapPostgrest(PostgrestException e) => classify(
        e,
        hasConnection: _hasConnection,
      ).error;

  /// The one public door for turning a caught object into something a
  /// student may read. Repositories call this rather than reading any
  /// exception's own message.
  BxError faultFor(Object e) => _mapGeneric(e);

  BxError _mapGeneric(Object e) =>
      e is BxError ? e : classify(e, hasConnection: _hasConnection).error;

  void dispose() {
    _connWatch?.cancel();
    _http.close();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
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
    if (!raw.contains('/storage/v1/object/public/')) return raw;
    if (isDirect) return raw;
    final b64 = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
    return '${BxConfig.siteUrl}/api/file?u=$b64';
  }

  /// Walks a decoded payload and rewrites every storage URL it finds.
  dynamic shieldDeep(dynamic node) {
    if (node is String) {
      return node.contains('/storage/v1/object/public/') ? fileUrl(node) : node;
    }
    if (node is List) return node.map(shieldDeep).toList();
    if (node is Map) {
      return node.map((k, v) => MapEntry(k, shieldDeep(v)));
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
    throw switch (r.statusCode) {
      401 => const BxError('Your session ended. Sign in again.',
          code: 'unauthenticated'),
      403 when code == 'not_activated' => BxError.notActivated,
      423 => BxError(
          body['reason']?.toString() ??
              'Your account is frozen. Chat Tutor Bello.',
          code: 'frozen'),
      409 when code == 'device_locked' => const BxError(
          'This account is locked to a different device.',
          code: 'device_locked'),
      409 when code == 'time_up' =>
        const BxError('Time is up.', code: 'time_up'),
      503 => const BxError(
          'Belloxdydx is under maintenance. We dey come back soon.',
          code: 'maintenance'),
      _ => BxError(
          _friendlyServerMessage(body) ?? 'Something went wrong. Try again.',
          code: code),
    };
  }

  String? _friendlyServerMessage(Map<String, dynamic> body) {
    final m = body['message']?.toString();
    if (m != null && m.isNotEmpty && !m.contains('http')) return m;
    return null;
  }

  // ------------------------------------------------------------
  // Error mapping — a student never sees a host name or a stack trace
  // ------------------------------------------------------------

  BxError _mapPostgrest(PostgrestException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('not_activated')) return BxError.notActivated;
    if (msg.contains('frozen')) {
      return const BxError('Your account is frozen. Chat Tutor Bello.',
          code: 'frozen');
    }
    if (msg.contains('time_up')) {
      return const BxError('Time is up.', code: 'time_up');
    }
    if (e.code == 'PGRST202' || msg.contains('could not find the function')) {
      return const BxError('That feature is not available yet.',
          code: 'rpc_missing');
    }
    if (e.code == '42501' || msg.contains('permission denied')) {
      return const BxError('You do not have access to that.',
          code: 'forbidden');
    }
    return BxError(e.message.contains('http')
        ? 'Something went wrong. Try again.'
        : e.message);
  }

  BxError _mapGeneric(Object e) {
    if (e is BxError) return e;
    if (e is AuthException) return BxError(e.message);
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('failed host lookup') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('handshake') ||
        s.contains('clientexception')) {
      return BxError.offline;
    }
    return const BxError('Something went wrong. Try again.');
  }

  void dispose() => _http.close();
}

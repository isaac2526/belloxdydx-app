import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class DeviceLockedException implements Exception {
  final int daysLeft;
  DeviceLockedException(this.daysLeft);
}

class FrozenException implements Exception {
  final String? reason;
  FrozenException(this.reason);
  @override
  String toString() =>
      reason ?? "Your account is frozen. Contact Tutor Bello.";
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

// The app's single voice to the Belloxdydx backend. Same rules as the
// website: merciful device lock, one live session, heartbeat judgement.
class Api {
  static late SharedPreferences _prefs;
  static String? sessionToken;
  static bool activated = false;
  static Map<String, dynamic>? content;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    sessionToken = _prefs.getString("bx_session");
    activated = _prefs.getBool("bx_activated") ?? false;
  }

  static String deviceId() {
    var id = _prefs.getString("bx_device_id");
    if (id == null) {
      final r = Random.secure();
      id = List.generate(32, (_) => "0123456789abcdef"[r.nextInt(16)]).join();
      _prefs.setString("bx_device_id", id);
    }
    return id;
  }

  static Map<String, String> _headers() {
    final jwt =
        Supabase.instance.client.auth.currentSession?.accessToken ?? "";
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $jwt",
      "x-bx-client": "app",
      if (sessionToken != null) "x-bx-session": sessionToken!,
    };
  }

  static Uri _u(String path) => Uri.parse("$baseUrl$path");

  static Map<String, dynamic> _decode(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ---------- auth ----------
  // Accepts an email OR a username. If it is not an email, we ask the
  // backend for the matching email first, then sign in. Clear errors.
  static Future<bool> login(String login, String password) async {
    final auth = Supabase.instance.client.auth;
    var email = login.trim();

    if (!email.contains("@")) {
      try {
        final lr = await http.post(_u("/api/auth/resolve-username"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"username": email}));
        final lj = _decode(lr);
        if (lr.statusCode == 200 && lj["email"] != null) {
          email = lj["email"] as String;
        }
      } catch (_) {}
    }

    try {
      await auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException("Sign-in error: " + e.toString());
    }

    late http.Response r;
    try {
      r = await http.post(_u("/api/auth/login"),
          headers: _headers(), body: jsonEncode({"deviceId": deviceId()}));
    } catch (e) {
      throw ApiException("Reaching the site failed: " + e.toString());
    }
    final j = _decode(r);

    if (r.statusCode == 423 && j["error"] == "account_frozen") {
      await auth.signOut();
      throw FrozenException(j["reason"] as String?);
    }
    if (r.statusCode == 409 && j["error"] == "device_locked") {
      await auth.signOut();
      throw DeviceLockedException((j["daysLeft"] as num?)?.toInt() ?? 1);
    }
    if (r.statusCode != 200) {
      await auth.signOut();
      throw ApiException(
          "Site rejected login (" + r.statusCode.toString() + "): " +
              (j["error"]?.toString() ?? "unknown"));
    }
    sessionToken = j["mobileToken"] as String?;
    activated = j["activated"] == true;
    if (sessionToken != null) {
      await _prefs.setString("bx_session", sessionToken!);
    }
    await _prefs.setBool("bx_activated", activated);
    return activated;
  }

  static bool get signedIn =>
      Supabase.instance.client.auth.currentSession != null &&
      sessionToken != null;

  static Future<void> logout() async {
    try {
      await http.post(_u("/api/auth/logout"), headers: _headers());
    } catch (_) {}
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    sessionToken = null;
    activated = false;
    content = null;
    await _prefs.remove("bx_session");
  }

  /// true = still the crowned session; false = superseded, sign out.
  static Future<bool> heartbeat() async {
    try {
      final r = await http
          .get(_u("/api/auth/heartbeat"), headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 401) return false;
      return true;
    } catch (_) {
      return true; // offline is not a crime; judgement comes on reconnect
    }
  }

  // ---------- bootstrap ----------
  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/content_cache.json");
  }

  static Future<void> loadCachedContent() async {
    try {
      final f = await _cacheFile();
      if (await f.exists()) {
        content = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
  }

  // Strong data affinity: try the network a few times with a real
  // timeout before giving up, and always fall back to the last good
  // copy saved on disk so the app opens even on a shaky line.
  static Future<Map<String, dynamic>> fetchContent() async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await http
            .get(_u("/api/mobile/content"), headers: _headers())
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          content = _decode(r);
          try {
            final f = await _cacheFile();
            await f.writeAsString(jsonEncode(content));
          } catch (_) {}
          return content!;
        }
        lastErr = ApiException("Server said ${r.statusCode}.");
      } catch (e) {
        lastErr = e;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    // Network failed: fall back to cache if we have it.
    await loadCachedContent();
    if (content != null) return content!;
    throw ApiException(
        "Could not load your courses. You seem offline and nothing is saved yet. Connect once to download.");
  }

  // The app dashboard in one call: greeting, streak, quote, marathon,
  // and a resume card the server already verified is still openable.
  static Future<Map<String, dynamic>> fetchHome() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await http
            .get(_u("/api/mobile/home2"), headers: _headers())
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) return _decode(r);
      } catch (_) {
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return {};
  }

  // Full post exam review: every question, the pick, the answer, the why.
  static Future<Map<String, dynamic>> cbtResult(String attemptId) async {
    final r = await http.get(_u("/api/mobile/cbt-result/$attemptId"),
        headers: _headers());
    final j = _decode(r);
    if (r.statusCode != 200) {
      throw ApiException(j["error"]?.toString() ?? "Could not load the review.");
    }
    return j;
  }

  // Ask the website if a newer APK exists. Never throws; update is a
  // gentle nudge, never a blocker.
  static Future<Map<String, dynamic>> checkUpdate() async {
    try {
      final r = await http
          .get(_u("/api/mobile/version"), headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return _decode(r);
    } catch (_) {}
    return {};
  }

  static Future<Map<String, dynamic>> fetchMaterial(String id) async {
    final r =
        await http.get(_u("/api/mobile/material/$id"), headers: _headers());
    final j = _decode(r);
    if (r.statusCode == 403) throw ApiException("not_activated");
    if (r.statusCode != 200) {
      throw ApiException("Could not open this material.");
    }
    return j["material"] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> leaderboard() async {
    final r =
        await http.get(_u("/api/mobile/leaderboard"), headers: _headers());
    if (r.statusCode != 200) throw ApiException("Could not load leaderboard.");
    return _decode(r);
  }

  static Future<Map<String, dynamic>> streakTouch() async {
    final r = await http.post(_u("/api/streak/touch"), headers: _headers());
    return _decode(r);
  }

  static Future<bool> activate(String key) async {
    final r = await http.post(_u("/api/activate"),
        headers: _headers(), body: jsonEncode({"key": key}));
    if (r.statusCode == 200) {
      activated = true;
      await _prefs.setBool("bx_activated", true);
      return true;
    }
    return false;
  }

  static Future<void> ack(String announcementId) async {
    try {
      await http.post(_u("/api/announcements/ack"),
          headers: _headers(),
          body: jsonEncode({"announcementId": announcementId}));
    } catch (_) {}
  }

  static Future<void> installPingOnce() async {
    if (_prefs.getBool("bx_install_pinged") == true) return;
    await _prefs.setBool("bx_install_pinged", true);
    try {
      await http.post(_u("/api/app/install"),
          headers: _headers(), body: jsonEncode({"platform": "android"}));
    } catch (_) {}
  }

  // ---------- AI ----------
  static Future<String> aiChat(List<Map<String, String>> messages) async {
    try {
      final r = await http
          .post(_u("/api/ai/chat"),
              headers: _headers(), body: jsonEncode({"messages": messages}))
          .timeout(const Duration(seconds: 45));
      final j = _decode(r);
      if (r.statusCode == 200 && j["reply"] != null) {
        return j["reply"] as String;
      }
      return (j["message"] as String?) ??
          "Bello AI hit a snag. Try again shortly.";
    } catch (_) {
      return "Could not reach Bello AI. Check your connection and retry.";
    }
  }

  // ---------- security ----------
  static Future<void> reportViolation(String kind) async {
    try {
      await http.post(_u("/api/violations/report"),
          headers: _headers(),
          body: jsonEncode({"kind": kind, "platform": "android"}));
    } catch (_) {}
  }

  // ---------- practice ----------
  static Future<String> practiceStart(String courseId) async {
    final r = await http.post(_u("/api/practice/start"),
        headers: _headers(),
        body: jsonEncode(
            {"mode": "practice", "courseId": courseId, "count": 20}));
    final j = _decode(r);
    if (r.statusCode != 200) {
      throw ApiException(j["error"] == "not_activated"
          ? "not_activated"
          : "Could not start practice.");
    }
    return j["attemptId"] as String;
  }

  static Future<Map<String, dynamic>> practiceFeed(String attemptId) async {
    final r =
        await http.get(_u("/api/practice/$attemptId"), headers: _headers());
    if (r.statusCode != 200) throw ApiException("Could not load questions.");
    return _decode(r);
  }

  static Future<Map<String, dynamic>> practiceAnswer(String attemptId,
      String questionId, String choice, String answerText) async {
    final r = await http.post(_u("/api/practice/answer"),
        headers: _headers(),
        body: jsonEncode({
          "attemptId": attemptId,
          "questionId": questionId,
          "choice": choice,
          "answerText": answerText,
        }));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> practiceFinish(String attemptId) async {
    final r = await http.post(_u("/api/practice/$attemptId"),
        headers: _headers(), body: jsonEncode({"action": "finish"}));
    return _decode(r);
  }

  // ---------- tests / CBT ----------
  // A live/timed test keeps its deadline on the SERVER (endsAt). Leaving
  // the app never pauses it; on return we recompute the time left. This
  // is the honest behaviour: an exam is an exam.
  static Future<List<Map<String, dynamic>>> fetchTests() async {
    final r = await http
        .get(_u("/api/mobile/tests"), headers: _headers())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 403) throw ApiException("not_activated");
    if (r.statusCode != 200) throw ApiException("Could not load tests.");
    final j = _decode(r);
    return ((j["tests"] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> cbtStart(String testId) async {
    final r = await http.post(_u("/api/cbt/start"),
        headers: _headers(), body: jsonEncode({"testId": testId}));
    final j = _decode(r);
    if (r.statusCode == 403) throw ApiException("not_activated");
    if (r.statusCode != 200) {
      throw ApiException(j["error"]?.toString() ?? "Could not start.");
    }
    return j;
  }

  static Future<Map<String, dynamic>> cbtFeed(String attemptId) async {
    final r = await http
        .get(_u("/api/cbt/$attemptId"), headers: _headers())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw ApiException("Could not load the test.");
    return _decode(r);
  }

  static Future<void> cbtAnswer(
      String attemptId, String questionId, String choice, String answerText) async {
    try {
      await http.post(_u("/api/cbt/answer"),
          headers: _headers(),
          body: jsonEncode({
            "attemptId": attemptId,
            "questionId": questionId,
            "choice": choice,
            "answerText": answerText,
          }));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> cbtSubmit(String attemptId) async {
    final r = await http.post(_u("/api/cbt/submit"),
        headers: _headers(), body: jsonEncode({"attemptId": attemptId}));
    return _decode(r);
  }

  static Future<void> cbtViolation(String attemptId) async {
    try {
      await http.post(_u("/api/cbt/violation"),
          headers: _headers(), body: jsonEncode({"attemptId": attemptId}));
    } catch (_) {}
  }
}

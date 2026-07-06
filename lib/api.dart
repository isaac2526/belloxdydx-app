import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class DeviceLockedException implements Exception {
  final int daysLeft;
  DeviceLockedException(this.daysLeft);
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
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
    }

    final r = await http.post(_u("/api/auth/login"),
        headers: _headers(), body: jsonEncode({"deviceId": deviceId()}));
    final j = _decode(r);

    if (r.statusCode == 409 && j["error"] == "device_locked") {
      await auth.signOut();
      throw DeviceLockedException((j["daysLeft"] as num?)?.toInt() ?? 1);
    }
    if (r.statusCode != 200) {
      await auth.signOut();
      throw ApiException("Could not finish sign in. Try again.");
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
      final r = await http.get(_u("/api/auth/heartbeat"), headers: _headers());
      if (r.statusCode == 401) return false;
      return true;
    } catch (_) {
      return true; // offline is not a crime; judgement comes on reconnect
    }
  }

  // ---------- bootstrap ----------
  static Future<Map<String, dynamic>> fetchContent() async {
    final r = await http.get(_u("/api/mobile/content"), headers: _headers());
    if (r.statusCode != 200) throw ApiException("Could not load content.");
    content = _decode(r);
    return content!;
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
}

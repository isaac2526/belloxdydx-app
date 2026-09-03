import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// LOCAL STORE
///
/// Small values, and a JSON cache so the app opens instantly.
///
/// It used to hold the Offline Vault too, in a SharedPreferences blob
/// full of ABSOLUTE paths — which is a real defect on iOS, where the
/// app container is a UUID that changes on restore, so every saved
/// document would quietly stop opening. That job now belongs to
/// data/offline/offline_store.dart, which stores paths relative to
/// today's container and holds far more than whole documents.
///
/// Nothing here writes files any more. `clearCache()` deletes the JSON
/// cache and runs on every sign-out; the offline root sits deliberately
/// outside it, so signing out does not throw away a student's material.
/// ============================================================

class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;
  static LocalStore? _instance;
  static LocalStore get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('LocalStore.init() must run before use');
    }
    return i;
  }

  static Future<LocalStore> init() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance ??= LocalStore._(prefs);
  }

  /// Drops the singleton so a test can build a fresh store over new
  /// mock preferences. Nothing in the app calls this.
  @visibleForTesting
  static void resetForTest() => _instance = null;

  // ------------------------------------------------------------
  // Simple values
  // ------------------------------------------------------------

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int getInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  // ------------------------------------------------------------
  // JSON cache
  // ------------------------------------------------------------

  Future<File?> _cacheFile(String name) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cache = Directory('${dir.path}/cache');
      if (!await cache.exists()) await cache.create(recursive: true);
      return File('${cache.path}/$name.json');
    } catch (_) {
      return null;
    }
  }

  /// Reads a cached payload, or null when there is nothing usable.
  Future<Map<String, dynamic>?> readJson(String name) async {
    try {
      final f = await _cacheFile(name);
      if (f != null && await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return null;
      }
      // Web (and any platform without a documents dir) uses prefs.
      final raw = _prefs.getString('cache:$name');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String name, Map<String, dynamic> data) async {
    try {
      final encoded = jsonEncode(data);
      final f = await _cacheFile(name);
      if (f != null) {
        await f.writeAsString(encoded);
      } else {
        await _prefs.setString('cache:$name', encoded);
      }
    } catch (_) {
      // A cache miss is never worth an error on screen.
    }
  }

  Future<void> clearCache() async {
    try {
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        final cache = Directory('${dir.path}/cache');
        if (await cache.exists()) await cache.delete(recursive: true);
      }
      for (final k in _prefs.getKeys().where((k) => k.startsWith('cache:'))) {
        await _prefs.remove(k);
      }
    } catch (_) {}
  }

}

/// Keys used across the app, in one place so nothing collides.
abstract final class BxKeys {
  static const deviceId = 'bx_device_id';
  static const mobileSession = 'bx_session';
  static const activated = 'bx_activated';
  static const themeMode = 'bx_theme_mode';
  static const biometricOn = 'bx_biometric_on';
  static const introSeen = 'bx_intro_seen';
  static const onboardingSeen = 'bx_onboarding_seen';
  static const lastLevel = 'bx_level';
  static const readerTheme = 'bx_reader_theme';
  static const readerFont = 'bx_reader_font';
  static const readerSize = 'bx_reader_size';
  static const dailyAnswerPrefix = 'bx_daily_';
  static const installPinged = 'bx_install_pinged';
  static const autoDownloadDocs = 'bx_auto_docs';
  static const legacyVaultIndex = 'bx_vault_index_v2';
  static const screenshotPolicy = 'bx_screens';
  static const deviceTrusted = 'bx_device_trusted';
  static const lockAfterMs = 'bx_lock_after';
  static const cachedProfile = 'profile';
  static const cachedContent = 'content';
  static const cachedDashboard = 'dashboard';
}

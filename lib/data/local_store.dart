import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// LOCAL STORE
///
/// Two jobs:
///   1. A JSON cache so the app opens instantly and works offline.
///   2. The Offline Vault — real files in the app's private documents
///      directory, which is strictly better than the website's Cache
///      API approach: the browser can evict a cache under storage
///      pressure and leave the index pointing at nothing, while these
///      files survive until the student deletes them.
///
/// Web has no documents directory, so vault downloads are disabled
/// there and the cache falls back to SharedPreferences. Every call is
/// guarded, so nothing throws on an unsupported platform.
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

  // ------------------------------------------------------------
  // Offline vault
  // ------------------------------------------------------------

  static const _vaultIndexKey = 'bx_vault_index_v2';

  List<VaultEntry> vaultItems() {
    try {
      final raw = _prefs.getString(_vaultIndexKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => VaultEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeVault(List<VaultEntry> items) =>
      _prefs.setString(_vaultIndexKey, jsonEncode(items.map((e) => e.toJson()).toList()));

  bool isSaved(String materialId) =>
      vaultItems().any((v) => v.materialId == materialId);

  VaultEntry? vaultEntry(String materialId) {
    for (final v in vaultItems()) {
      if (v.materialId == materialId) return v;
    }
    return null;
  }

  Future<Directory?> _vaultDir() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final vault = Directory('${dir.path}/vault');
      if (!await vault.exists()) await vault.create(recursive: true);
      return vault;
    } catch (_) {
      return null;
    }
  }

  /// True when this platform can hold files for offline reading.
  Future<bool> get vaultSupported async => !kIsWeb;

  /// Saves a downloaded payload into the vault and indexes it.
  Future<VaultEntry?> saveToVault({
    required String materialId,
    required String title,
    required String courseCode,
    required String kind,
    required List<int> bytes,
    required String extension,
    String? html,
  }) async {
    final dir = await _vaultDir();
    if (dir == null) return null;
    try {
      final path = '${dir.path}/$materialId.$extension';
      await File(path).writeAsBytes(bytes, flush: true);

      String? htmlPath;
      if (html != null && html.isNotEmpty) {
        htmlPath = '${dir.path}/$materialId.html';
        await File(htmlPath).writeAsString(html, flush: true);
      }

      final entry = VaultEntry(
        materialId: materialId,
        title: title,
        courseCode: courseCode,
        kind: kind,
        filePath: path,
        htmlPath: htmlPath,
        sizeBytes: bytes.length,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final items = vaultItems()..removeWhere((v) => v.materialId == materialId);
      await _writeVault([entry, ...items]);
      return entry;
    } catch (e) {
      // Deliberately rethrown. Swallowing this into a null is what
      // made every failure look like a full disk to the caller.
      debugPrint('[vault] save failed: \$e');
      rethrow;
    }
  }

  /// Saves a note body with no attached file.
  Future<VaultEntry?> saveHtmlToVault({
    required String materialId,
    required String title,
    required String courseCode,
    required String html,
  }) async {
    final dir = await _vaultDir();
    if (dir == null) return null;
    try {
      final htmlPath = '${dir.path}/$materialId.html';
      await File(htmlPath).writeAsString(html, flush: true);
      final entry = VaultEntry(
        materialId: materialId,
        title: title,
        courseCode: courseCode,
        kind: 'note',
        filePath: '',
        htmlPath: htmlPath,
        sizeBytes: html.length,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final items = vaultItems()..removeWhere((v) => v.materialId == materialId);
      await _writeVault([entry, ...items]);
      return entry;
    } catch (e) {
      // Deliberately rethrown. Swallowing this into a null is what
      // made every failure look like a full disk to the caller.
      debugPrint('[vault] save failed: \$e');
      rethrow;
    }
  }

  Future<void> removeFromVault(String materialId) async {
    final items = vaultItems();
    final target = items.where((v) => v.materialId == materialId).firstOrNull;
    if (target != null) {
      for (final p in [target.filePath, target.htmlPath]) {
        if (p == null || p.isEmpty) continue;
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await _writeVault(items.where((v) => v.materialId != materialId).toList());
  }

  Future<int> vaultSizeBytes() async {
    var total = 0;
    for (final v in vaultItems()) {
      total += v.sizeBytes;
    }
    return total;
  }

  /// Reads a vaulted note body back for offline display.
  Future<String?> readVaultHtml(String materialId) async {
    final e = vaultEntry(materialId);
    if (e?.htmlPath == null) return null;
    try {
      final f = File(e!.htmlPath!);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  /// Confirms the file behind an index entry still exists. Guards the
  /// bug the audit found on the website, where the index outlived the
  /// files and "Open" led nowhere.
  Future<bool> vaultFileExists(String materialId) async {
    final e = vaultEntry(materialId);
    if (e == null) return false;
    final p = e.filePath.isNotEmpty ? e.filePath : e.htmlPath;
    if (p == null || p.isEmpty) return false;
    try {
      return await File(p).exists();
    } catch (_) {
      return false;
    }
  }

  /// Drops index rows whose files have vanished.
  Future<void> reconcileVault() async {
    final items = vaultItems();
    final alive = <VaultEntry>[];
    for (final v in items) {
      if (await vaultFileExists(v.materialId)) alive.add(v);
    }
    if (alive.length != items.length) await _writeVault(alive);
  }
}

@immutable
class VaultEntry {
  final String materialId;
  final String title;
  final String courseCode;
  final String kind;
  final String filePath;
  final String? htmlPath;
  final int sizeBytes;
  final int savedAtMs;

  const VaultEntry({
    required this.materialId,
    required this.title,
    required this.courseCode,
    required this.kind,
    required this.filePath,
    required this.savedAtMs,
    this.htmlPath,
    this.sizeBytes = 0,
  });

  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
        materialId: '${j['materialId'] ?? j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        courseCode: '${j['courseCode'] ?? j['course'] ?? ''}',
        kind: '${j['kind'] ?? 'file'}',
        filePath: '${j['filePath'] ?? ''}',
        htmlPath: j['htmlPath']?.toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        savedAtMs: (j['savedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'materialId': materialId,
        'title': title,
        'courseCode': courseCode,
        'kind': kind,
        'filePath': filePath,
        'htmlPath': htmlPath,
        'sizeBytes': sizeBytes,
        'savedAtMs': savedAtMs,
      };
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
  static const cachedProfile = 'profile';
  static const cachedContent = 'content';
  static const cachedDashboard = 'dashboard';
}

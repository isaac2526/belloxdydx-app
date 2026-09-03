import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../local_store.dart';
import 'offline_store.dart';

/// ============================================================
/// OPENING THE OFFLINE ROOT
///
/// Runs once in main(), before runApp, for a reason that is easy to miss:
/// `WidgetFactory.imageProviderFromNetwork` — the hook that lets a
/// picture inside a note body be drawn from disk — is synchronous. If
/// the catalogue is not already in memory by the time the first frame
/// builds, every offline picture misses on the first paint and only
/// appears after a rebuild that may never come.
///
/// It also carries the old vault across. The previous index lived in
/// SharedPreferences and held ABSOLUTE paths, which is a real bug on
/// iOS: the app container is a UUID that changes on restore and on some
/// updates, so every saved document would quietly stop opening. The
/// files are moved into the new root and re-indexed by their tails.
/// ============================================================

Future<OfflineStore?> openOfflineStore(LocalStore prefs) async {
  final store = await OfflineStore.open();
  if (store == null) return null;
  Offline.store = store;
  await _adoptLegacyVault(prefs, store);
  await store.reconcile();
  return store;
}

Future<void> _adoptLegacyVault(LocalStore prefs, OfflineStore store) async {
  final raw = prefs.getString(BxKeys.legacyVaultIndex);
  if (raw == null || raw.isEmpty) return;

  List<dynamic> rows;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      await prefs.remove(BxKeys.legacyVaultIndex);
      return;
    }
    rows = decoded;
  } catch (_) {
    await prefs.remove(BxKeys.legacyVaultIndex);
    return;
  }

  var carried = 0;
  for (final row in rows.whereType<Map>()) {
    final j = Map<String, dynamic>.from(row);
    final id = '${j['materialId'] ?? j['id'] ?? ''}';
    if (id.isEmpty) continue;
    try {
      final docPath = '${j['filePath'] ?? ''}';
      final htmlPath = '${j['htmlPath'] ?? ''}';

      String? html;
      if (htmlPath.isNotEmpty) {
        final f = File(htmlPath);
        if (await f.exists()) html = await f.readAsString();
      }

      if (docPath.isNotEmpty) {
        final f = File(docPath);
        if (await f.exists()) {
          final ext = docPath.split('.').last;
          await store.putDocument(
            id: id,
            title: '${j['title'] ?? ''}',
            kind: '${j['kind'] ?? 'file'}',
            bytes: await f.readAsBytes(),
            extension: ext.length <= 5 ? ext : 'bin',
            courseCode: '${j['courseCode'] ?? j['course'] ?? ''}',
            sig: 'carried-over',
            html: html,
          );
          await f.delete();
          carried++;
          continue;
        }
      }

      if (html != null) {
        await store.putNote(
          id: id,
          title: '${j['title'] ?? ''}',
          html: html,
          courseCode: '${j['courseCode'] ?? j['course'] ?? ''}',
          sig: 'carried-over',
          pinned: true,
        );
        carried++;
      }
    } catch (e) {
      debugPrint('[offline] could not carry over $id: $e');
    }
  }

  await store.flush();
  await prefs.remove(BxKeys.legacyVaultIndex);

  // The old directory, now empty of anything indexed.
  try {
    final docs = File(store.rootPath).parent;
    final old = Directory('${docs.path}/vault');
    if (await old.exists()) await old.delete(recursive: true);
  } catch (_) {}

  if (carried > 0) debugPrint('[offline] carried over $carried saved items');
}

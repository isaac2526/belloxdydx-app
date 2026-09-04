import '../backend.dart' show kEmbeddedStorageUrl;
import '../models.dart';

/// ============================================================
/// HOW A SAVED COPY IS IDENTIFIED
///
/// These three were the only part of the old background sync engine
/// worth keeping. The engine itself is gone — it promised to fill the
/// vault by itself, it did not, and one clear Download button per
/// course replaced it. These helpers move here so the downloader does
/// not have to import a dead machine to reach them.
/// ============================================================

int utf8Length(String s) => s.codeUnits.length;

/// What a copy was made from. `updated_at` when the backend sends one —
/// the direct RPC always does, and the website route does too —
/// otherwise the URL, which at least catches a replaced file.
String sigFor(StudyMaterial m) =>
    m.updatedAt?.toIso8601String() ?? '${m.url}#${m.sortOrder}';

/// Every storage URL embedded in a body, in either of the two shapes it
/// can arrive in — the raw Supabase URL on the direct path, the
/// `…/api/file?u=<base64>` proxy URL on the website path.
Iterable<String> urlsInHtml(String html) sync* {
  for (final m in kEmbeddedStorageUrl.allMatches(html)) {
    yield m.group(0)!;
  }
  for (final m in _proxyUrlInHtml.allMatches(html)) {
    yield m.group(0)!;
  }
}

final RegExp _proxyUrlInHtml =
    RegExp(r'''https?://[^\s"'<>()]*?/api/file\?u=[A-Za-z0-9_=-]+''');

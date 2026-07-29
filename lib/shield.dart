import 'dart:convert';
import 'config.dart';

// ============================================================
// THE EGRESS SHIELD (app side)
// Every file the app opens — PDFs, slides, images, audio — used to
// stream raw from Supabase storage, which is why materials loaded
// slow, sometimes blank, and burned the bandwidth purse. This mirror
// of the website's shield rewrites any public-storage address to our
// own cached door, so Vercel's edge pays instead of Supabase and
// repeat opens cost nothing.
// ============================================================

const _storageMark = "/storage/v1/object/public/";

String shieldUrl(String? raw) {
  if (raw == null || raw.isEmpty) return "";
  if (!raw.contains(_storageMark)) return raw;
  final b64 = base64Url.encode(utf8.encode(raw)).replaceAll("=", "");
  return "$baseUrl/api/file?u=$b64";
}

/// Walks any decoded JSON and shields every http url that points at
/// public storage, wherever it hides (materials, attachments, question
/// images, option images, audio).
dynamic shieldDeep(dynamic node) {
  if (node is String) {
    return node.contains(_storageMark) ? shieldUrl(node) : node;
  }
  if (node is List) return node.map(shieldDeep).toList();
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, shieldDeep(v)));
  }
  return node;
}

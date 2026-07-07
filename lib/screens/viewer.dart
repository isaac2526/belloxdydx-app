import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../watermark.dart';

// The sealed reading room. Screen is locked (screenshots black), the
// watermark names any second-phone photo, and "Save offline" keeps
// PDFs, notes AND audio inside the app's private vault, readable with
// no network, invisible to file managers, never shareable.

class VaultIndex {
  static Future<List<Map<String, dynamic>>> list() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString("vault_index") ?? "[]";
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> add(Map<String, dynamic> entry) async {
    final p = await SharedPreferences.getInstance();
    final items = await list();
    items.removeWhere((e) => e["id"] == entry["id"]);
    items.insert(0, entry);
    await p.setString("vault_index", jsonEncode(items));
  }

  static Future<void> remove(String id) async {
    final p = await SharedPreferences.getInstance();
    final items = await list();
    items.removeWhere((e) => e["id"] == id);
    await p.setString("vault_index", jsonEncode(items));
    final dir = await getApplicationDocumentsDirectory();
    for (final ext in ["pdf", "html", "mp3", "m4a"]) {
      final f = File("${dir.path}/vault/$id.$ext");
      if (await f.exists()) await f.delete();
    }
  }

  static Future<File> fileFor(String id, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final v = Directory("${dir.path}/vault");
    if (!await v.exists()) await v.create(recursive: true);
    return File("${v.path}/$id.$ext");
  }

  static Future<String?> localAudioPath(String id) async {
    for (final ext in ["mp3", "m4a"]) {
      final f = await fileFor(id, ext);
      if (await f.exists()) return f.path;
    }
    return null;
  }
}

String _audioExt(String url) {
  final u = url.toLowerCase();
  if (u.contains(".m4a")) return "m4a";
  return "mp3";
}

class ViewerScreen extends StatefulWidget {
  final String materialId;
  final String title;
  final String type;
  final bool offline;
  const ViewerScreen({
    super.key,
    required this.materialId,
    required this.title,
    required this.type,
    this.offline = false,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  String status = "loading";
  String? note;
  PdfControllerPinch? pdf;
  String? videoUrl;
  AudioPlayer? _player;
  bool saving = false;
  bool saved = false;

  String get wm {
    final me = (Api.content?["me"] as Map?) ?? {};
    final matric = me["matric"];
    return "${me["username"] ?? "belloxdydx"}${matric != null ? " · $matric" : ""}";
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.offline) {
        final audioPath = await VaultIndex.localAudioPath(widget.materialId);
        if (audioPath != null) {
          await _initAudio(audioPath, isLocal: true);
          setState(() => status = "audio");
          return;
        }
        final pdfFile = await VaultIndex.fileFor(widget.materialId, "pdf");
        if (await pdfFile.exists()) {
          pdf = PdfControllerPinch(document: PdfDocument.openData(await pdfFile.readAsBytes()));
          setState(() => status = "pdf");
          return;
        }
        final htmlFile = await VaultIndex.fileFor(widget.materialId, "html");
        if (await htmlFile.exists()) {
          note = await htmlFile.readAsString();
          setState(() => status = "note");
          return;
        }
        setState(() => status = "error");
        return;
      }

      final m = await Api.fetchMaterial(widget.materialId);
      final url = m["url"] as String?;
      final html = m["content_html"] as String?;
      final type = "${m["type"]}";

      if (type == "video" || type == "series") {
        videoUrl = url;
        setState(() => status = "video");
        return;
      }
      if (url != null && (url.toLowerCase().contains(".mp3") || url.toLowerCase().contains(".m4a"))) {
        await _initAudio(url, isLocal: false);
        setState(() => status = "audio");
        return;
      }
      if (html != null && html.trim().isNotEmpty) {
        note = html;
        setState(() => status = "note");
        return;
      }
      if (url != null && url.toLowerCase().contains(".pdf")) {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode != 200) throw ApiException("fetch");
        pdf = PdfControllerPinch(document: PdfDocument.openData(r.bodyBytes));
        setState(() => status = "pdf");
        return;
      }
      setState(() => status = "unsupported");
    } on ApiException catch (e) {
      setState(() => status = e.message == "not_activated" ? "not_activated" : "error");
    } catch (_) {
      setState(() => status = "error");
    }
  }

  Future<void> _initAudio(String path, {required bool isLocal}) async {
    _player = AudioPlayer();
    try {
      if (isLocal) {
        await _player!.setFilePath(path);
      } else {
        await _player!.setUrl(path);
      }
    } catch (_) {}
  }

  Future<void> _saveOffline() async {
    setState(() => saving = true);
    try {
      final m = await Api.fetchMaterial(widget.materialId);
      final url = m["url"] as String?;
      final html = m["content_html"] as String?;
      String kind = "";

      if (url != null && (url.toLowerCase().contains(".mp3") || url.toLowerCase().contains(".m4a"))) {
        final r = await http.get(Uri.parse(url));
        final f = await VaultIndex.fileFor(widget.materialId, _audioExt(url));
        await f.writeAsBytes(r.bodyBytes);
        kind = "audio";
      } else if (url != null && url.toLowerCase().contains(".pdf")) {
        final r = await http.get(Uri.parse(url));
        final f = await VaultIndex.fileFor(widget.materialId, "pdf");
        await f.writeAsBytes(r.bodyBytes);
        kind = "pdf";
      } else if (html != null && html.trim().isNotEmpty) {
        final f = await VaultIndex.fileFor(widget.materialId, "html");
        await f.writeAsString(html);
        kind = "html";
      }

      if (kind.isNotEmpty) {
        await VaultIndex.add({
          "id": widget.materialId,
          "title": widget.title,
          "type": widget.type,
          "kind": kind,
        });
        setState(() {
          saved = true;
          saving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Saved to your in-app vault. Readable offline, only inside Belloxdydx.")));
        }
      } else {
        setState(() => saving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("This item cannot be saved offline.")));
        }
      }
    } catch (_) {
      setState(() => saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Could not save. Try again.")));
      }
    }
  }

  @override
  void dispose() {
    pdf?.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onBg = Theme.of(context).textTheme.bodyLarge?.color;
    Widget body;
    switch (status) {
      case "loading":
        body = const Center(child: CircularProgressIndicator());
        break;
      case "pdf":
        body = Stack(children: [
          PdfViewPinch(controller: pdf!),
          Positioned.fill(child: Watermark(text: wm)),
        ]);
        break;
      case "audio":
        body = _AudioBody(player: _player!, title: widget.title, wm: wm);
        break;
      case "note":
        body = Stack(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HtmlWidget(note!, textStyle: TextStyle(fontSize: 16, color: onBg)),
          ),
          Positioned.fill(child: Watermark(text: wm)),
        ]);
        break;
      case "video":
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.ondemand_video, size: 60, color: Colors.grey),
            const SizedBox(height: 12),
            const Text("Videos play on the website for now."),
            const SizedBox(height: 12),
            if (videoUrl != null)
              FilledButton(
                onPressed: () => launchUrl(Uri.parse(videoUrl!), mode: LaunchMode.externalApplication),
                child: const Text("Open video"),
              ),
          ]),
        );
        break;
      case "not_activated":
        body = const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("🔑 This is premium content. Activate your account to read it.",
              textAlign: TextAlign.center),
        ));
        break;
      default:
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Could not open this. Check your network."),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: () {
                  setState(() => status = "loading");
                  _load();
                },
                child: const Text("Retry")),
          ]),
        );
    }

    final canSave = !widget.offline &&
        (status == "pdf" || status == "note" || status == "audio");
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (canSave)
            IconButton(
              tooltip: "Save offline (in-app vault)",
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(saved ? Icons.download_done : Icons.download, color: const Color(0xFFF5B301)),
              onPressed: saving || saved ? null : _saveOffline,
            ),
        ],
      ),
      body: body,
    );
  }
}

class _AudioBody extends StatefulWidget {
  final AudioPlayer player;
  final String title;
  final String wm;
  const _AudioBody({required this.player, required this.title, required this.wm});
  @override
  State<_AudioBody> createState() => _AudioBodyState();
}

class _AudioBodyState extends State<_AudioBody> {
  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFF5B301);
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.multitrack_audio, size: 80, color: gold),
            const SizedBox(height: 16),
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            StreamBuilder<Duration>(
              stream: widget.player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final total = widget.player.duration ?? Duration.zero;
                final max = total.inMilliseconds.toDouble();
                final val = pos.inMilliseconds.clamp(0, max == 0 ? 1 : max).toDouble();
                return Column(children: [
                  Slider(
                    value: val,
                    max: max == 0 ? 1 : max,
                    activeColor: gold,
                    onChanged: (v) => widget.player.seek(Duration(milliseconds: v.toInt())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos)),
                      Text(_fmt(total)),
                    ],
                  ),
                ]);
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<PlayerState>(
              stream: widget.player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton.filled(
                  iconSize: 44,
                  style: IconButton.styleFrom(backgroundColor: gold, foregroundColor: const Color(0xFF0B1220)),
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => playing ? widget.player.pause() : widget.player.play(),
                );
              },
            ),
          ],
        ),
      ),
      Positioned.fill(child: IgnorePointer(child: Watermark(text: widget.wm))),
    ]);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    final s = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "$m:$s";
  }
}

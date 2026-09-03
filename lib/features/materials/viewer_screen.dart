import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/local_store.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'watermark.dart';

/// ============================================================
/// THE READING ROOM
///
/// Slides and past questions open here. The document is drawn natively
/// — pinch to zoom, scroll page to page — with the reader's identity
/// flooded across it, and it can be pulled into the offline vault so it
/// still opens when the campus network dies mid-week.
/// ============================================================

const _officeExtensions = {'pptx', 'ppt', 'docx', 'doc', 'xlsx', 'xls'};

enum _DocKind { pdf, office, other }

/// The file extension of a URL, lower-cased, with the query string
/// dropped — storage links are signed, so `?token=` is common.
String documentExtension(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1).toLowerCase();
}

_DocKind? _kindFromExtension(String ext) {
  if (ext == 'pdf') return _DocKind.pdf;
  if (_officeExtensions.contains(ext)) return _DocKind.office;
  return null;
}

/// Works out what a document is from its first bytes.
///
/// On the legacy backend path every storage link is rewritten to
/// `/api/file?u=<encoded>`, which hides the extension, so the header is
/// the only honest signal left.
_DocKind _sniffKind(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return _DocKind.pdf; // "%PDF"
  }
  // Every modern Office format is a zip container.
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return _DocKind.office;
  }
  return _DocKind.other;
}

/// Downloads a document. Returns null on any failure — the caller turns
/// that into a sentence the student can act on.
Future<Uint8List?> fetchDocumentBytes(String url) async {
  if (url.isEmpty) return null;
  try {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final r = await http.get(uri);
    if (r.statusCode >= 200 && r.statusCode < 300 && r.bodyBytes.isNotEmpty) {
      return r.bodyBytes;
    }
  } catch (_) {
    // Offline, a dead link, a timeout — all the same to the reader.
  }
  return null;
}

class ViewerScreen extends ConsumerStatefulWidget {
  final String id;
  const ViewerScreen({super.key, required this.id});

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  String? _preparedFor;
  bool _preparing = false;
  bool _busy = false;
  bool _opened = false;
  bool _offline = false;
  String? _error;
  String? _filePath;
  Uint8List? _bytes;
  _DocKind _kind = _DocKind.pdf;
  int _page = 0;
  int _pages = 0;

  static const _missing =
      'This document has not been uploaded yet. Tell Tutor Bello and it '
      'will be up shortly.';
  static const _noDownload =
      'This document did not come down. Check your data or Wi-Fi, then '
      'pull to refresh.';

  Future<void> _refresh() async {
    _preparedFor = null;
    ref.invalidate(materialProvider(widget.id));
    await ref.read(materialProvider(widget.id).future);
  }

  String _sourceUrl(StudyMaterial m) =>
      ref.read(contentRepoProvider).fileUrl(m.url);

  /// Decides what this document is and gets it in hand — once per
  /// material. A vaulted copy always wins: it is instant and free.
  Future<void> _prepare(StudyMaterial m) async {
    final store = ref.read(localStoreProvider);
    final url = _sourceUrl(m);

    // A slide or past question that was typed instead of uploaded has no
    // file to draw — the note reader is the right room for it.
    if (url.isEmpty && m.hasBody) {
      if (mounted) context.pushReplacement(Routes.note(m.id));
      return;
    }

    var kind = _kindFromExtension(documentExtension(url));

    String? path;
    Uint8List? bytes;
    var offline = false;
    String? error;

    final entry = store.vaultEntry(widget.id);
    if (entry != null &&
        entry.filePath.isNotEmpty &&
        await store.vaultFileExists(widget.id)) {
      final local = _kindFromExtension(documentExtension(entry.filePath));
      if (local == _DocKind.pdf || (local == null && kind == _DocKind.pdf)) {
        path = entry.filePath;
        offline = true;
        kind = _DocKind.pdf;
      }
    }

    if (path == null) {
      if (url.isEmpty) {
        error = _missing;
      } else if (kind != _DocKind.office) {
        // A PDF has to be in memory to be drawn, and an unknown file has
        // to be read before it can be named — one download serves both.
        bytes = await fetchDocumentBytes(url);
        if (bytes == null) {
          error = _noDownload;
        } else {
          kind ??= _sniffKind(bytes);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _kind = kind ?? _DocKind.other;
      _filePath = path;
      _bytes = bytes;
      _offline = offline;
      _error = error;
      _preparing = false;
      _page = 0;
      _pages = 0;
    });
  }

  Future<void> _save(StudyMaterial m, String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = ref.read(localStoreProvider);
      if (!await store.vaultSupported) {
        if (!mounted) return;
        bxToast(context, 'This device cannot hold offline copies.',
            error: true);
        return;
      }
      final url = _sourceUrl(m);
      final bytes = _bytes ?? await fetchDocumentBytes(url);
      if (bytes == null) {
        if (!mounted) return;
        bxToast(context,
            'Could not download this one. Try again on a steadier network.',
            error: true);
        return;
      }
      var ext = documentExtension(url);
      if (ext.isEmpty) ext = _kind == _DocKind.pdf ? 'pdf' : 'bin';

      // Report what actually went wrong. This used to say "free up a
      // little space" for EVERY failed save, because saveToVault
      // returned null on any exception — so a student on a brand new
      // 256 GB phone was told to clear room for an error that had
      // nothing to do with storage. Only a genuine ENOSPC says that now.
      VaultEntry? entry;
      String? failure;
      try {
        entry = await store.saveToVault(
          materialId: m.id,
          title: m.title,
          courseCode: code,
          kind: m.kind.name,
          bytes: bytes,
          extension: ext,
        );
        if (entry == null) {
          failure = 'This device will not let the app keep offline copies.';
        }
      } catch (e) {
        failure = ref.read(backendProvider).faultFor(e).message;
      }

      ref.read(vaultProvider.notifier).refresh();
      if (!mounted) return;
      bxToast(
        context,
        failure ?? 'Saved. It opens now with no data at all.',
        error: failure != null,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await bxConfirm(
      context,
      title: 'Remove the offline copy?',
      message: 'You keep the document — it just needs data to open again.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(vaultProvider.notifier).remove(widget.id);
    if (!mounted) return;
    _preparedFor = null;
    bxToast(context, 'Removed from your offline vault.');
  }

  void _gate() =>
      showActivationGate(context, () => context.push(Routes.activate));

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final async = ref.watch(materialProvider(widget.id));
    final activated = ref.watch(profileProvider).isActivated;
    final saved = ref.watch(vaultProvider).any((v) => v.materialId == widget.id);
    final material = async.valueOrNull;

    final code = material == null
        ? null
        : ref
            .watch(contentProvider)
            .valueOrNull
            ?.courseById(material.courseId)
            ?.code;

    // One preparation pass per material, kicked off after the frame that
    // first holds it. Flipping the flag here (rather than inside the
    // callback) keeps the "opening" state from flashing the wrong body.
    if (material != null && activated && _preparedFor != material.id) {
      _preparedFor = material.id;
      _preparing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepare(material);
      });
    }
    if (material != null && !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(contentRepoProvider).markOpened(widget.id);
      });
    }

    VoidCallback? saveAction;
    if (material != null) {
      if (!activated) {
        saveAction = _gate;
      } else if (!_busy) {
        saveAction = saved ? _remove : () => _save(material, code ?? '');
      }
    }

    return Scaffold(
      appBar: BxAppBar(
        title: material?.title ?? 'Reading room',
        subtitle:
            _kind == _DocKind.pdf && _pages > 0 ? 'page $_page of $_pages' : code,
        actions: [
          if (material != null)
            IconButton(
              tooltip: saved ? 'Saved for offline' : 'Save for offline',
              onPressed: saveAction,
              icon: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.gold),
                    )
                  : Icon(
                      saved
                          ? Icons.offline_pin_rounded
                          : Icons.download_for_offline_outlined,
                      color: saved ? c.success : null,
                    ),
            ),
        ],
      ),
      body: _body(async, material, activated),
    );
  }

  Widget _body(AsyncValue<StudyMaterial> async, StudyMaterial? material,
      bool activated) {
    if (material == null) {
      if (async.hasError) {
        final e = async.error;
        return BxPage(
          onRefresh: _refresh,
          child: BxErrorState(
            title: 'This document did not open',
            message: e is BxError
                ? e.message
                : 'Check your data or Wi-Fi, then try again.',
            onRetry: _refresh,
          ),
        );
      }
      return BxPage(
        onRefresh: _refresh,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThreatStrip(),
            SizedBox(height: BxSpace.md),
            BxSkeleton(height: 420, radius: BxRadius.md),
          ],
        ),
      );
    }

    if (!activated) {
      return BxPage(
        onRefresh: _refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ThreatStrip(),
            const SizedBox(height: BxSpace.md),
            BxEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'This one opens with activation',
              message:
                  'Your key opens every slide, past question and note for '
                  'your level. Small daily reading beats midnight panic.',
              actionLabel: 'Activate my account',
              onAction: _gate,
            ),
          ],
        ),
      );
    }

    if (_preparing) {
      return const BxPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThreatStrip(),
            Expanded(child: BxThinking(message: 'Opening the document…')),
          ],
        ),
      );
    }

    if (_error != null) {
      return BxPage(
        onRefresh: _refresh,
        child: BxErrorState(
          title: 'This document did not open',
          message: _error!,
          onRetry: () => setState(() {
            _preparedFor = null;
            _error = null;
          }),
        ),
      );
    }

    return switch (_kind) {
      _DocKind.pdf => _pdfBody(),
      _DocKind.office => _officeBody(material),
      _DocKind.other => _otherBody(material),
    };
  }

  Widget _pdfBody() {
    final c = context.bx;
    return BxPage(
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThreatStrip(),
          if (_offline) ...[
            const SizedBox(height: BxSpace.xs),
            const Align(
              alignment: Alignment.centerLeft,
              child: BxChip('Offline copy',
                  accent: BxAccent.success, icon: Icons.offline_pin_rounded),
            ),
          ],
          const SizedBox(height: BxSpace.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BxRadius.card,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BxRadius.card,
                  border: Border.all(color: c.line),
                ),
                child: Stack(
                  children: [
                    PdfSurface(
                      filePath: _filePath,
                      bytes: _bytes,
                      onPages: _onPages,
                    ),
                    const Watermark(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onPages(int page, int pages) {
    if (!mounted || (page == _page && pages == _pages)) return;
    setState(() {
      _page = page;
      _pages = pages;
    });
  }

  Widget _officeBody(StudyMaterial m) {
    final c = context.bx;
    final url = _sourceUrl(m);
    return BxPage(
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThreatStrip(),
          const SizedBox(height: BxSpace.md),
          BxCard(
            padding: const EdgeInsets.all(BxSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BxEyebrow('Slide deck'),
                const SizedBox(height: BxSpace.xs),
                Text(m.title, style: BxType.h2(c.ink)),
                const SizedBox(height: BxSpace.xs),
                Text(
                  'This one was uploaded as a PowerPoint rather than a PDF, '
                  'so it opens in a viewer instead of the page reader.',
                  style: BxType.body(c.inkSoft),
                ),
                const SizedBox(height: BxSpace.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BxButton(
                    'Open the slides',
                    icon: Icons.slideshow_rounded,
                    onPressed: url.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OfficeViewerPage(
                                  title: m.title,
                                  sourceUrl: url,
                                ),
                              ),
                            ),
                  ),
                ),
                const SizedBox(height: BxSpace.md),
                const BxDivider(),
                // Honesty rather than fine print: this is the only surface
                // in the app that is not drawn by Flutter, and the student
                // should know that before it loads.
                Text(
                  'No phone can render PowerPoint, Word or Excel on its own, '
                  'so this one document type is drawn by Microsoft’s public '
                  'Office viewer. It is the only screen in the app that works '
                  'that way, and your name still sits across it.',
                  style: BxType.small(c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _otherBody(StudyMaterial m) {
    final url = _sourceUrl(m);
    return BxPage(
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThreatStrip(),
          const SizedBox(height: BxSpace.md),
          BxEmptyState(
            icon: Icons.description_outlined,
            title: 'This file opens outside the app',
            message:
                'It is not a PDF or a slide deck, so your phone will pick the '
                'app that knows it best.',
            actionLabel: url.isEmpty ? null : 'Open it',
            onAction: url.isEmpty ? null : () => _openExternally(url),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted || ok) return;
    bxToast(context, 'Nothing on this phone could open it.', error: true);
  }
}

/// The native PDF surface: scrollable, pinch-zoomable, and wrapped so a
/// renderer failure becomes a sentence instead of a red screen.
class PdfSurface extends StatefulWidget {
  final String? filePath;
  final Uint8List? bytes;
  final void Function(int page, int pages)? onPages;

  const PdfSurface({super.key, this.filePath, this.bytes, this.onPages});

  @override
  State<PdfSurface> createState() => _PdfSurfaceState();
}

class _PdfSurfaceState extends State<PdfSurface> {
  PdfControllerPinch? _controller;
  String? _error;
  int _pages = 0;

  static const _failed =
      'This document would not open. It may still be uploading — try again '
      'in a moment.';

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _controller?.pageListenable.removeListener(_onPage);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      if (!await hasPdfSupport()) {
        _fail('This device cannot draw PDFs. Open it in your files app '
            'instead.');
        return;
      }
      final path = widget.filePath;
      final bytes = widget.bytes;
      if (path == null && bytes == null) {
        _fail('There was nothing to open here.');
        return;
      }
      final controller = PdfControllerPinch(
        document:
            path != null ? PdfDocument.openFile(path) : PdfDocument.openData(bytes!),
      );
      controller.pageListenable.addListener(_onPage);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      _fail(_failed);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onPage() {
    final c = _controller;
    if (c == null || _pages == 0) return;
    _notify(c.pageListenable.value, _pages);
  }

  /// pdfx can settle the current page during layout, so the parent gets
  /// its counter on the next frame rather than a setState inside a build.
  void _notify(int page, int pages) {
    final cb = widget.onPages;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(page, pages);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(BxSpace.md),
        child: BxErrorState(
          title: 'This document did not open',
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _open();
          },
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const BxThinking(message: 'Opening the document…');
    }

    return PdfViewPinch(
      controller: controller,
      padding: 6,
      backgroundDecoration: BoxDecoration(color: c.surfaceSunken),
      onDocumentLoaded: (doc) {
        _pages = doc.pagesCount;
        _notify(controller.page, _pages);
      },
      onDocumentError: (_) => _fail(_failed),
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) =>
            const BxThinking(message: 'Opening the document…'),
        pageLoaderBuilder: (_) => const BxThinking(message: 'Drawing the page…'),
        errorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.all(BxSpace.md),
          child: BxErrorState(
            title: 'This document did not open',
            message: 'It may still be uploading. Go back and try again.',
          ),
        ),
      ),
    );
  }
}

/// A pushed full-screen reader for a PDF attached to a note.
class PdfDocumentPage extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String url;

  const PdfDocumentPage({
    super.key,
    required this.title,
    required this.url,
    this.subtitle,
  });

  @override
  State<PdfDocumentPage> createState() => _PdfDocumentPageState();
}

class _PdfDocumentPageState extends State<PdfDocumentPage> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bytes = await fetchDocumentBytes(widget.url);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
      _error = bytes == null
          ? 'This attachment did not come down. Check your data or Wi-Fi and '
              'try again.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Scaffold(
      appBar: BxAppBar(
        title: widget.title,
        subtitle: _pages > 0 ? 'page $_page of $_pages' : widget.subtitle,
      ),
      body: BxPage(
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(
            BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ThreatStrip(),
            const SizedBox(height: BxSpace.sm),
            Expanded(
              child: _loading
                  ? const BxThinking(message: 'Opening the document…')
                  : _error != null
                      ? BxErrorState(
                          title: 'This attachment did not open',
                          message: _error!,
                          onRetry: _load,
                        )
                      : ClipRRect(
                          borderRadius: BxRadius.card,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BxRadius.card,
                              border: Border.all(color: c.line),
                            ),
                            child: Stack(
                              children: [
                                PdfSurface(
                                  bytes: _bytes,
                                  onPages: (page, pages) {
                                    if (!mounted ||
                                        (page == _page && pages == _pages)) {
                                      return;
                                    }
                                    setState(() {
                                      _page = page;
                                      _pages = pages;
                                    });
                                  },
                                ),
                                const Watermark(),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one webview in the app.
///
/// PowerPoint, Word and Excel have no native renderer on a phone, so a
/// deck uploaded as .pptx is handed to Microsoft's public Office viewer.
/// Every other pixel the student touches is drawn by Flutter.
class OfficeViewerPage extends StatefulWidget {
  final String title;
  final String sourceUrl;

  const OfficeViewerPage({
    super.key,
    required this.title,
    required this.sourceUrl,
  });

  @override
  State<OfficeViewerPage> createState() => _OfficeViewerPageState();
}

class _OfficeViewerPageState extends State<OfficeViewerPage> {
  late final WebViewController _web;
  bool _loading = true;
  String? _error;

  String get _viewerUrl =>
      'https://view.officeapps.live.com/op/view.aspx?src='
      '${Uri.encodeComponent(widget.sourceUrl)}';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = 'The slide viewer did not load. Check your data or '
                  'Wi-Fi and try again.';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(_viewerUrl));
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _web.loadRequest(Uri.parse(_viewerUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BxAppBar(title: widget.title, subtitle: 'Slide viewer'),
      body: _error != null
          ? BxPage(
              child: BxErrorState(
                title: 'The slides did not open',
                message: _error!,
                onRetry: _retry,
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _web),
                const Watermark(),
                if (_loading)
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.bx.ground,
                      child: const BxThinking(message: 'Opening the slides…'),
                    ),
                  ),
              ],
            ),
    );
  }
}

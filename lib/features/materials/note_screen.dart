import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/net_speed.dart';
import '../../data/offline/offline_store.dart';
import '../../data/repositories.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'viewer_screen.dart';
import 'watermark.dart';

/// ============================================================
/// THE NOTE READER
///
/// A note is the thing students spend the most minutes inside, so this
/// screen is built for the eye rather than the demo: ten papers, five
/// faces, one size slider, all remembered. The reader's identity is
/// flooded across the page the whole time.
/// ============================================================

/// The ten reading surfaces, ported from the website's reader.
///
/// This table is the ONE place in the app that carries literal colours,
/// and deliberately so: these are content, not chrome. "Sepia" has to be
/// sepia whether the app is in light or dark mode, because the student
/// picked the paper they can stare at for an hour. `null` means "follow
/// the app's own tokens". Every other colour in this file comes from
/// context.bx.
@immutable
class _ReaderTheme {
  final String name;
  final Color? paper;
  final Color? ink;
  const _ReaderTheme(this.name, this.paper, this.ink);
}

const _readerThemes = <_ReaderTheme>[
  _ReaderTheme('Default', null, null),
  _ReaderTheme('Paper', Color(0xFFFFFDF6), Color(0xFF1B1B1B)),
  _ReaderTheme('Sepia', Color(0xFFF4ECD8), Color(0xFF4A3B28)),
  _ReaderTheme('Night', Color(0xFF11141A), Color(0xFFD9DFEA)),
  _ReaderTheme('Slate', Color(0xFF1E252E), Color(0xFFCBD5E1)),
  _ReaderTheme('Mint', Color(0xFFECF7F0), Color(0xFF1F3A2C)),
  _ReaderTheme('Rose', Color(0xFFFDEFF1), Color(0xFF43242B)),
  _ReaderTheme('Sky', Color(0xFFEDF4FC), Color(0xFF1B3049)),
  _ReaderTheme('Lemon', Color(0xFFFDF8E1), Color(0xFF3D3617)),
  _ReaderTheme('Lavender', Color(0xFFF2EFFB), Color(0xFF2F2A45)),
];

/// Five reading faces. Only Modern and Typewriter are bundled with the
/// app; the other three name the closest face the phone already has and
/// fall back down the list, so nothing is ever downloaded to read a note.
@immutable
class _ReaderFace {
  final String name;
  final String family;
  final List<String> fallback;
  const _ReaderFace(this.name, this.family, this.fallback);
}

const _readerFaces = <_ReaderFace>[
  _ReaderFace('Modern', BxFont.body, BxFont.fallback),
  _ReaderFace('Classic', 'Georgia',
      ['Times New Roman', 'Iowan Old Style', 'Noto Serif', 'serif']),
  _ReaderFace('Rounded', 'Nunito',
      ['Quicksand', 'Arial Rounded MT Bold', 'Verdana', 'sans-serif']),
  _ReaderFace('Typewriter', BxFont.data, BxFont.monoFallback),
  _ReaderFace('Friendly', 'Trebuchet MS',
      ['Segoe UI', 'Avenir Next', 'Verdana', 'sans-serif']),
];

const _minSize = 13.0;
const _maxSize = 24.0;

class NoteScreen extends ConsumerStatefulWidget {
  final String id;
  const NoteScreen({super.key, required this.id});

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  int _theme = 0;
  int _face = 0;
  double _size = 16;
  bool _vaultOk = false;
  bool _busy = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    final store = ref.read(localStoreProvider);
    _theme = store
        .getInt(BxKeys.readerTheme)
        .clamp(0, _readerThemes.length - 1)
        .toInt();
    _face =
        store.getInt(BxKeys.readerFont).clamp(0, _readerFaces.length - 1).toInt();
    _size = store
        .getInt(BxKeys.readerSize, fallback: 16)
        .toDouble()
        .clamp(_minSize, _maxSize)
        .toDouble();
    unawaited(_checkVault());
  }

  Future<void> _checkVault() async {
    final ok = ref.read(offlineStoreProvider) != null;
    if (mounted) setState(() => _vaultOk = ok);
  }

  Future<void> _refresh() async {
    ref.invalidate(materialProvider(widget.id));
    await ref.read(materialProvider(widget.id).future);
  }

  void _gate() =>
      showActivationGate(context, () => context.push(Routes.activate));

  // ----------------------------------------------------------
  // Reader settings
  // ----------------------------------------------------------

  TextStyle _readerStyle(Color ink) {
    final f = _readerFaces[_face];
    return BxType.body(ink).copyWith(
      fontFamily: f.family,
      fontFamilyFallback: f.fallback,
      fontSize: _size,
      height: 1.62,
    );
  }

  void _openSettings() {
    final c = context.bx;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.sheet),
      builder: (_) => _ReaderSheet(
        theme: _theme,
        face: _face,
        size: _size,
        onTheme: (v) => _apply(theme: v),
        onFace: (v) => _apply(face: v),
        onSize: (v) => _apply(size: v),
      ),
    );
  }

  void _apply({int? theme, int? face, double? size}) {
    setState(() {
      _theme = theme ?? _theme;
      _face = face ?? _face;
      _size = size ?? _size;
    });
    final store = ref.read(localStoreProvider);
    unawaited(store.setInt(BxKeys.readerTheme, _theme));
    unawaited(store.setInt(BxKeys.readerFont, _face));
    unawaited(store.setInt(BxKeys.readerSize, _size.round()));
  }

  // ----------------------------------------------------------
  // Offline vault
  // ----------------------------------------------------------

  Future<void> _toggleSave(StudyMaterial m, String code, bool saved) async {
    if (_busy) return;

    if (saved) {
      final ok = await bxConfirm(
        context,
        title: 'Remove the offline copy?',
        message: 'The note stays on Belloxdydx — it just needs data to open '
            'again.',
        confirmLabel: 'Remove',
        destructive: true,
      );
      if (!ok || !mounted) return;
      await ref.read(vaultProvider.notifier).remove(widget.id);
      if (!mounted) return;
      bxToast(context, 'Removed from your offline vault.');
      return;
    }

    setState(() => _busy = true);
    try {
      final store = ref.read(offlineStoreProvider);
      final repo = ref.read(contentRepoProvider);
      if (store == null) {
        if (!mounted) return;
        bxToast(context, 'This device cannot hold offline copies.', error: true);
        return;
      }

      // A note travels as its body AND its attachment list, and every
      // attachment's bytes come down with it — PDFs included — into
      // the same place the course download puts them, so the attachment
      // row finds them by URL with the data off. The first PDF used to
      // be filed as a document under the note's own id, where no screen
      // ever looked for it: the note reader opened attachments by URL,
      // and the network said no.
      String? failure;
      var missed = const <String>[];
      try {
        await store.putNote(
          id: m.id,
          title: m.title,
          courseCode: code,
          courseId: m.courseId,
          html: m.contentHtml,
          sig: m.updatedAt?.toIso8601String() ?? m.url,
          pinned: true,
          attachments: [
            for (final a in m.attachments)
              OfflineAttachment(title: a.title, url: a.url, kind: a.kind),
          ],
        );
        missed = await _keepMedia(store, m, repo);
        await store.flush();
      } catch (e) {
        // Only a genuine ENOSPC says "free up space". This used to say
        // it for every failure, on any phone, however empty.
        failure = ref.read(backendProvider).faultFor(e).message;
      }

      ref.read(vaultProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {});
      bxToast(
        context,
        failure ??
            (missed.isEmpty
                ? 'Saved. This note now opens with no data.'
                : 'Saved, but ${missed.length == 1 ? 'one attachment' : '${missed.length} attachments'} '
                    'did not come down: ${missed.take(2).join(', ')}. '
                    'Tap Save again on a steadier line.'),
        error: failure != null || missed.isNotEmpty,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pulls down every picture and voice note the body points at, and
  /// every attachment whatever its kind. Returns the titles of the
  /// attachments that did NOT come down, so the toast can name them.
  Future<List<String>> _keepMedia(
    OfflineStore store,
    StudyMaterial m,
    ContentRepository repo,
  ) async {
    final missed = <String>[];
    final urls = <String, String>{
      for (final match in kEmbeddedStorageUrl.allMatches(m.contentHtml))
        match.group(0)!: 'a picture in this note',
      for (final a in m.attachments) a.url: a.title,
    };
    for (final entry in urls.entries) {
      final url = repo.fileUrl(entry.key);
      if (url.isEmpty) continue;
      if (store.hasAsset(url) && await store.verifyAsset(url)) continue;
      try {
        final bytes = await fetchDocumentBytes(url);
        if (bytes != null && bytes.isNotEmpty) {
          await store.putAsset(url, bytes);
          continue;
        }
      } catch (_) {
        // Named below rather than swallowed.
      }
      missed.add(entry.value);
    }
    return missed;
  }


  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final async = ref.watch(materialProvider(widget.id));
    final activated = ref.watch(profileProvider).isActivated;
    final saved = ref.watch(vaultProvider).any((v) => v.id == widget.id);
    final material = async.valueOrNull;

    final code = material == null
        ? null
        : ref
            .watch(contentProvider)
            .valueOrNull
            ?.courseById(material.courseId)
            ?.code;

    // The reading point is awarded once, after the note is actually in
    // front of the student.
    if (material != null && activated && !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(contentRepoProvider).markOpened(widget.id);
      });
    }

    VoidCallback? saveAction;
    if (material != null && _vaultOk) {
      if (!activated) {
        saveAction = _gate;
      } else if (!_busy) {
        saveAction = () => _toggleSave(material, code ?? '', saved);
      }
    }

    return Scaffold(
      appBar: BxAppBar(
        title: material?.title ?? 'Note',
        subtitle: code,
        actions: [
          IconButton(
            tooltip: 'Reader settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.text_fields_rounded),
          ),
          if (material != null && _vaultOk)
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
      body: BxPage(
        onRefresh: _refresh,
        child: _body(async, material, activated, saved),
      ),
    );
  }

  Widget _body(AsyncValue<StudyMaterial> async, StudyMaterial? material,
      bool activated, bool saved) {
    if (material == null) {
      if (async.hasError) {
        final e = async.error;
        final noLine =
            ref.read(netSpeedProvider).grade == BxNetGrade.offline;
        return BxErrorState(
          title: noLine
              ? 'This note is not on this phone yet'
              : 'This note did not open',
          message: noLine
              ? 'You are offline and this one was not among the files '
                  'saved to this phone. Open the course with data on and '
                  'tap Download — it brings every note, picture and '
                  'attachment down, and then this opens with no data.'
              : e is BxError
                  ? e.message
                  : 'Check your data or Wi-Fi, then try again.',
          onRetry: _refresh,
        );
      }
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThreatStrip(),
          SizedBox(height: BxSpace.md),
          BxSkeleton(width: 220, height: 20),
          SizedBox(height: BxSpace.md),
          BxSkeleton(height: 320, radius: BxRadius.md),
        ],
      );
    }

    if (!activated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThreatStrip(),
          const SizedBox(height: BxSpace.md),
          BxEmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'This note opens with activation',
            message: 'Your key opens every note, slide, video and past '
                'question for your level. Small daily reading beats midnight '
                'panic.',
            actionLabel: 'Activate my account',
            onAction: _gate,
          ),
        ],
      );
    }

    return BxStagger(
      spacing: BxSpace.md,
      children: [
        const ThreatStrip(),
        _meta(material, saved),
        if (_behind(material)) _behindBanner(),
        if (material.hasBody)
          _surface(material)
        else
          BxEmptyState(
            icon: Icons.edit_note_rounded,
            title: 'The body of this note is still being typed',
            message: material.attachments.isEmpty
                ? 'Nothing is attached yet either. Check back after the next '
                    'class.'
                : 'What is attached below is ready to read, though.',
            actionLabel: 'Back to my courses',
            onAction: () => context.go(Routes.courses),
          ),
        if (material.attachments.isNotEmpty) _attachments(material),
        // The same Save as the icon in the bar, where a thumb finds it
        // — "add download button inside everything just in case".
        if (_vaultOk) _keepRow(material, saved),
      ],
    );
  }

  /// One plain row at the foot of the note: keep it, or it is kept.
  Widget _keepRow(StudyMaterial m, bool saved) {
    final c = context.bx;
    final code = ref
            .read(contentProvider)
            .valueOrNull
            ?.courseById(m.courseId)
            ?.code ??
        '';
    final held = m.attachments
        .where((a) => Offline.holds(ref.read(contentRepoProvider).fileUrl(a.url)))
        .length;
    final allHere = saved && held == m.attachments.length;
    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      accent: allHere ? BxAccent.success : BxAccent.neutral,
      child: Row(
        children: [
          Icon(
            allHere
                ? Icons.offline_pin_rounded
                : Icons.download_for_offline_outlined,
            color: allHere ? c.success : c.gold,
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Text(
              allHere
                  ? (m.attachments.isEmpty
                      ? 'On this phone. Opens with no data.'
                      : 'On this phone with ${m.attachments.length == 1 ? 'its attachment' : 'all ${m.attachments.length} attachments'}. Opens with no data.')
                  : saved
                      ? 'The note is on this phone, but $held of ${m.attachments.length} attachments came down. Save again to fetch the rest.'
                      : 'Keep this note on your phone, with everything attached to it.',
              style: BxType.small(allHere ? c.inkSoft : c.ink),
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          BxButton(
            allHere ? 'Saved' : 'Save',
            kind: allHere ? BxButtonKind.secondary : BxButtonKind.primary,
            onPressed: _busy || allHere
                ? null
                : () => _toggleSave(m, code, false),
          ),
        ],
      ),
    );
  }

  /// True when the shelf knows of a newer version of this note than
  /// the copy being read.
  ///
  /// Only reachable while offline: online, the reader is handed the
  /// live note and the saved copy is refreshed behind it. Offline, the
  /// shelf can still be newer than the body — the index refreshes on
  /// its own and note bodies do not — and the student deserves to know
  /// that before they revise from it.
  bool _behind(StudyMaterial m) {
    final held = m.updatedAt;
    if (held == null) return false;
    final shelf = ref
        .read(contentRepoProvider)
        .materials
        .where((h) => h.id == m.id)
        .firstOrNull
        ?.updatedAt;
    return shelf != null && shelf.isAfter(held);
  }

  Widget _behindBanner() => const BxBanner(
        title: 'Tutor Bello has rewritten this note',
        message: 'You are reading the copy saved on this phone. Open it '
            'again with a connection and the new one comes down by itself.',
        icon: Icons.system_update_alt_rounded,
        accent: BxAccent.warning,
      );

  Widget _meta(StudyMaterial m, bool saved) {
    final c = context.bx;
    final updated = m.updatedAt ?? m.createdAt;
    return Wrap(
      spacing: BxSpace.xs,
      runSpacing: BxSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (m.topic.isNotEmpty) BxChip(m.topic, icon: Icons.sell_outlined),
        if (saved)
          const BxChip('Offline copy',
              accent: BxAccent.success, icon: Icons.offline_pin_rounded),
        if (updated != null)
          Text('Tutor Bello last updated ${bxBelloDate(updated)}',
              style: BxType.tiny(c.muted)),
      ],
    );
  }

  Widget _surface(StudyMaterial m) {
    final c = context.bx;
    final t = _readerThemes[_theme];
    final paper = t.paper ?? c.surface;
    final ink = t.ink ?? c.ink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          BxSpace.lg, BxSpace.lg, BxSpace.lg, BxSpace.xl),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BxRadius.card,
        border: Border.all(color: c.line),
        boxShadow: BxShadow.card(c),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title, style: BxType.h2(ink)),
              const SizedBox(height: BxSpace.md),
              BxHtml(
                m.contentHtml,
                textStyle: _readerStyle(ink),
                onTapUrl: _openLink,
              ),
            ],
          ),
          Watermark(color: ink),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Attachments
  // ----------------------------------------------------------

  Widget _attachments(StudyMaterial m) {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BxSpace.xs),
        Row(
          children: [
            const BxEyebrow('Attached'),
            const SizedBox(width: BxSpace.xs),
            Text('${m.attachments.length}', style: BxType.mono(c.muted)),
          ],
        ),
        const SizedBox(height: BxSpace.sm),
        for (final a in m.attachments) ...[
          _attachment(m, a),
          const SizedBox(height: BxSpace.sm),
        ],
      ],
    );
  }

  Widget _attachment(StudyMaterial m, Attachment a) {
    final c = context.bx;
    final url = ref.read(contentRepoProvider).fileUrl(a.url);
    final kind = a.kind.isNotEmpty ? a.kind : documentExtension(a.url);
    final here = Offline.holds(url);

    switch (kind) {
      case 'image':
        return BxCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BxRadius.md)),
                child: Stack(
                  children: [
                    BxImage(
                      imageUrl: url,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const BxSkeleton(height: 200, radius: 0),
                      errorWidget: (_, __, ___) => Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: c.surfaceAlt,
                        child: Text('This image did not load.',
                            style: BxType.small(c.muted)),
                      ),
                    ),
                    const Watermark(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(BxSpace.sm),
                child: Text(a.title, style: BxType.smallStrong(c.ink)),
              ),
            ],
          ),
        );

      case 'audio':
        return BxAudio(url: url, label: a.title);

      case 'pdf':
        return BxListRow(
          title: a.title,
          subtitle: here ? 'PDF · on this phone' : 'PDF · opens in the reading room',
          leading: Icon(Icons.picture_as_pdf_rounded, color: c.danger),
          trailing: here
              ? Icon(Icons.offline_pin_rounded, size: 18, color: c.success)
              : null,
          onTap: url.isEmpty
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfDocumentPage(
                        title: a.title,
                        subtitle: m.title,
                        url: url,
                      ),
                    ),
                  ),
        );

      default:
        return BxListRow(
          title: a.title,
          subtitle: 'Opens outside the app · needs data',
          leading: Icon(Icons.attachment_rounded, color: c.muted),
          trailing: Icon(Icons.open_in_new_rounded, size: 18, color: c.muted),
          onTap: url.isEmpty ? null : () => _openLink(url),
        );
    }
  }

  Future<bool> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok && mounted) {
      bxToast(context, 'Nothing on this phone could open that link.',
          error: true);
    }
    return ok;
  }
}

// ============================================================
// Reader settings sheet
// ============================================================

class _ReaderSheet extends StatefulWidget {
  final int theme;
  final int face;
  final double size;
  final ValueChanged<int> onTheme;
  final ValueChanged<int> onFace;
  final ValueChanged<double> onSize;

  const _ReaderSheet({
    required this.theme,
    required this.face,
    required this.size,
    required this.onTheme,
    required this.onFace,
    required this.onSize,
  });

  @override
  State<_ReaderSheet> createState() => _ReaderSheetState();
}

class _ReaderSheetState extends State<_ReaderSheet> {
  late int _theme = widget.theme;
  late int _face = widget.face;
  late double _size = widget.size;

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final t = _readerThemes[_theme];
    final paper = t.paper ?? c.surface;
    final ink = t.ink ?? c.ink;
    final face = _readerFaces[_face];

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.lg, BxSpace.sm, BxSpace.lg, BxSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.lineStrong,
                    borderRadius: BorderRadius.circular(BxRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: BxSpace.md),
              const BxEyebrow('Reader'),
              const SizedBox(height: BxSpace.xxs),
              Text('How this reads', style: BxType.h2(c.ink)),
              const SizedBox(height: BxSpace.md),

              // Live preview — the settings answer for themselves.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(BxSpace.md),
                decoration: BoxDecoration(
                  color: paper,
                  borderRadius: BxRadius.card,
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  'Small daily reading beats midnight panic.',
                  style: BxType.body(ink).copyWith(
                    fontFamily: face.family,
                    fontFamilyFallback: face.fallback,
                    fontSize: _size,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: BxSpace.lg),
              const BxEyebrow('Background'),
              const SizedBox(height: BxSpace.sm),
              Wrap(
                spacing: BxSpace.xs,
                runSpacing: BxSpace.xs,
                children: [
                  for (var i = 0; i < _readerThemes.length; i++)
                    _swatch(context, i),
                ],
              ),

              const SizedBox(height: BxSpace.lg),
              const BxEyebrow('Font'),
              const SizedBox(height: BxSpace.sm),
              Wrap(
                spacing: BxSpace.xs,
                runSpacing: BxSpace.xs,
                children: [
                  for (var i = 0; i < _readerFaces.length; i++)
                    _faceChip(context, i),
                ],
              ),

              const SizedBox(height: BxSpace.lg),
              Row(
                children: [
                  const BxEyebrow('Text size'),
                  const Spacer(),
                  Text('${_size.round()} pt', style: BxType.mono(c.muted)),
                ],
              ),
              Row(
                children: [
                  Text('A', style: BxType.body(c.muted)),
                  Expanded(
                    child: Slider(
                      value: _size,
                      min: _minSize,
                      max: _maxSize,
                      divisions: (_maxSize - _minSize).round(),
                      label: '${_size.round()}',
                      onChanged: (v) {
                        setState(() => _size = v);
                        widget.onSize(v);
                      },
                    ),
                  ),
                  Text('A', style: BxType.h2(c.ink)),
                ],
              ),
              const SizedBox(height: BxSpace.xs),
              Text(
                'Your choice is remembered for every note you open.',
                style: BxType.tiny(c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(BuildContext context, int i) {
    final c = context.bx;
    final t = _readerThemes[i];
    final selected = i == _theme;
    final paper = t.paper ?? c.surface;
    final ink = t.ink ?? c.ink;

    return BxScaleTap(
      scale: 0.94,
      onTap: () {
        setState(() => _theme = i);
        widget.onTheme(i);
      },
      child: Container(
        width: 66,
        padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(
            color: selected ? c.gold : c.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: paper,
                shape: BoxShape.circle,
                border: Border.all(color: c.lineStrong),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 15, color: ink)
                  : Text('Aa', style: BxType.tiny(ink)),
            ),
            const SizedBox(height: 5),
            Text(
              t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BxType.tiny(selected ? c.goldDeep : c.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faceChip(BuildContext context, int i) {
    final c = context.bx;
    final f = _readerFaces[i];
    final selected = i == _face;

    return BxScaleTap(
      scale: 0.94,
      onTap: () {
        setState(() => _face = i);
        widget.onFace(i);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.sm, vertical: BxSpace.xs),
        decoration: BoxDecoration(
          color: selected ? c.goldTint : c.surfaceAlt,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(
              color: selected ? c.gold.withValues(alpha: 0.55) : c.line),
        ),
        child: Text(
          f.name,
          style: BxType.bodyStrong(selected ? c.goldDeep : c.inkSoft).copyWith(
            fontFamily: f.family,
            fontFamilyFallback: f.fallback,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Audio attachment
// ============================================================

/// A compact player for an audio clip clipped to a note. Audio is polish,
/// not the lesson, so every call is guarded: if the platform refuses, the
/// row quietly becomes a link that opens elsewhere.

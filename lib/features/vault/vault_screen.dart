import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE OFFLINE VAULT
///
/// The website kept saved material in the browser's Cache API, which
/// the browser is free to evict under storage pressure — the index
/// survived, the files did not, and "Open" led nowhere. Here the files
/// are real files in the app's private directory, the index is
/// reconciled against them on every visit, and nothing but the student
/// removes them.
/// ============================================================

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  /// Null while we are still asking the platform whether it can hold
  /// files at all — web cannot.
  bool? _supported;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final ok = await ref.read(localStoreProvider).vaultSupported;
      if (!mounted) return;
      setState(() {
        _supported = ok;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _refresh() async {
    ref.read(vaultProvider.notifier).refresh();
    await _check();
  }

  void _open(VaultEntry e) {
    context.push(
      e.kind == 'note' ? Routes.note(e.materialId) : Routes.view(e.materialId),
    );
  }

  Future<void> _remove(VaultEntry e) async {
    final sure = await bxConfirm(
      context,
      title: 'Remove from your vault?',
      message:
          '"${e.title}" leaves this phone and frees ${e.sizeLabel.isEmpty ? 'its space' : e.sizeLabel}. '
          'You can save it again any time you have data.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!sure || !mounted) return;
    await ref.read(vaultProvider.notifier).remove(e.materialId);
    if (!mounted) return;
    bxToast(context, 'Removed. That space is yours again.');
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BxAppBar(
        title: 'Offline Vault',
        subtitle: 'Zero-data reading',
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(child: _body()),
      ),
    );
  }

  Widget _body() {
    final entries = ref.watch(vaultProvider);

    if (_failed && _supported == null) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: BxSpace.xs),
        child: BxErrorState(
          title: 'Your shelf did not open',
          message:
              'We could not read what is stored on this phone just now. Try '
              'again in a moment.',
          onRetry: _check,
        ),
      );
    }

    if (_supported == null) {
      return const Column(
        key: ValueKey('loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxSkeleton(height: 76, radius: BxRadius.md),
          SizedBox(height: BxSpace.md),
          BxSkeletonList(count: 4, itemHeight: 78),
        ],
      );
    }

    final supported = _supported!;

    return Column(
      key: const ValueKey('content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!supported)
          const BxBanner(
            title: 'Offline saving needs the installed app',
            message:
                'A browser can clear its own storage without warning, so we '
                'do not pretend to hold your material here. Install the '
                'Belloxdydx app and everything you save stays put.',
            icon: Icons.phonelink_off_rounded,
            accent: BxAccent.warning,
          )
        else
          const BxBanner(
            title: 'Materials you saved open with your data off',
            message: 'Only you can remove them — nothing here expires on its own.',
            icon: Icons.wifi_off_rounded,
            accent: BxAccent.info,
          ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: BxSpace.sm),
          _totals(entries),
        ],
        const SizedBox(height: BxSpace.md),
        if (entries.isEmpty)
          BxEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Nothing saved yet',
            message:
                'Open any material and tap Save for offline — it will live '
                'here, readable anywhere, even with no signal.',
            actionLabel: 'Browse courses',
            onAction: () => context.go(Routes.courses),
          )
        else
          BxStagger(
            spacing: BxSpace.xs,
            children: [for (final e in entries) _row(e)],
          ),
      ],
    );
  }

  Widget _totals(List<VaultEntry> entries) {
    final c = context.bx;
    final bytes = entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
    return Row(
      children: [
        Icon(Icons.sd_storage_outlined, size: 15, color: c.muted),
        const SizedBox(width: BxSpace.xs),
        Expanded(
          child: Text(
            '${entries.length} item${entries.length == 1 ? '' : 's'} on this phone',
            style: BxType.tiny(c.muted),
          ),
        ),
        Text(_sizeLabel(bytes), style: BxType.mono(c.inkSoft, size: 12)),
      ],
    );
  }

  Widget _row(VaultEntry e) {
    final c = context.bx;
    final saved = DateFormat('d MMM').format(e.savedAt);
    final parts = <String>[
      if (e.courseCode.isNotEmpty) e.courseCode,
      'saved $saved',
      if (e.sizeLabel.isNotEmpty) e.sizeLabel,
    ];

    return BxListRow(
      title: e.title.isEmpty ? 'Saved material' : e.title,
      subtitle: parts.join(' · '),
      leading: _mark(e.kind),
      onTap: () => _open(e),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BxButton.secondary('Open', onPressed: () => _open(e)),
          IconButton(
            onPressed: () => _remove(e),
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.muted),
            tooltip: 'Remove from vault',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _mark(String kind) {
    final c = context.bx;
    final (icon, accent) = switch (kind) {
      'note' => (Icons.article_outlined, BxAccent.gold),
      'slide' => (Icons.slideshow_outlined, BxAccent.info),
      'video' => (Icons.play_circle_outline_rounded, BxAccent.danger),
      'series' => (Icons.playlist_play_rounded, BxAccent.violet),
      'pq' => (Icons.history_edu_outlined, BxAccent.success),
      _ => (Icons.insert_drive_file_outlined, BxAccent.neutral),
    };
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Icon(icon, size: 17, color: accent.ink(c)),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

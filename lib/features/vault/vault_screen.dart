import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/offline/offline_store.dart';
import '../../data/offline/sync_engine.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE OFFLINE VAULT
///
/// This screen used to be almost always empty, and the reason was
/// structural rather than cosmetic: the only thing that could ever put
/// something in it was a student remembering to open a material and tap
/// "Save for offline". Nothing arrived by itself. Notes were not kept.
/// Questions were not kept anywhere at all — not the text, not the
/// options, not the pictures — so "works offline" meant a cached
/// dashboard and nothing else.
///
/// Now the app fills it while the student uses it, and this screen shows
/// what is actually there: the notes, the pictures and voice notes, the
/// questions, and the documents. It also owns the one decision that
/// cannot be made for the student — whether to spend their data bundle
/// on whole PDFs — and it is off until they say so.
/// ============================================================

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  Future<void> _refresh() async {
    ref.read(vaultProvider.notifier).refresh();
    ref.invalidate(offlineSummaryProvider);
  }

  Future<void> _syncNow() async {
    final level = ref.read(sessionProvider).profile?.currentLevel;
    await ref.read(syncStatusProvider.notifier).start(now: true, level: level);
    if (!mounted) return;
    await _refresh();
  }

  void _open(OfflineItem e) {
    context.push(e.kind == 'note' ? Routes.note(e.id) : Routes.view(e.id));
  }

  Future<void> _remove(OfflineItem e) async {
    final sure = await bxConfirm(
      context,
      title: 'Remove from your vault?',
      message: '"${e.title}" leaves this phone and frees ${e.sizeLabel}. '
          'The next sync will bring it back unless you turned syncing off.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!sure || !mounted) return;
    await ref.read(vaultProvider.notifier).remove(e.id);
    if (!mounted) return;
    ref.invalidate(offlineSummaryProvider);
    bxToast(context, 'Removed. That space is yours again.');
  }

  Future<void> _setAutoDocs(bool on) async {
    await ref.read(localStoreProvider).setBool(BxKeys.autoDownloadDocs, on);
    ref.read(syncStatusProvider.notifier).autoDocuments = on;
    if (!mounted) return;
    setState(() {});
    if (on) {
      bxToast(context, 'PDFs will come down on Wi-Fi from the next sync.');
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);
    return Scaffold(
      appBar: BxAppBar(
        title: 'Offline Vault',
        subtitle: 'Zero-data reading',
        actions: [
          IconButton(
            onPressed: status.isRunning ? null : _syncNow,
            tooltip: 'Sync now',
            icon: status.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 20),
          ),
        ],
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(child: _body(status)),
      ),
    );
  }

  Widget _body(SyncStatus status) {
    final entries = ref.watch(vaultProvider);
    final summary = ref.watch(offlineSummaryProvider);
    final supported = ref.watch(offlineStoreProvider) != null;

    return Column(
      key: const ValueKey('content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!supported)
          BxBanner(
            title: kIsWeb
                ? 'Offline saving needs the installed app'
                : 'This phone will not let us keep offline copies',
            message: kIsWeb
                ? 'A browser can clear its own storage without warning, so we '
                    'do not pretend to hold your material here. Install the '
                    'Belloxdydx app and everything you save stays put.'
                : 'We could not open a place to store them. Everything still '
                    'works with data on. Restart the app and it usually '
                    'sorts itself; if it does not, chat Tutor Bello.',
            icon: Icons.phonelink_off_rounded,
            accent: BxAccent.warning,
          )
        else
          _SyncCard(status: status, onSync: _syncNow),
        const SizedBox(height: BxSpace.md),
        if (supported) ...[
          summary.when(
            loading: () => const BxSkeleton(height: 86, radius: BxRadius.md),
            error: (_, __) => const SizedBox.shrink(),
            data: _counts,
          ),
          const SizedBox(height: BxSpace.md),
          _autoDocsSwitch(),
          const SizedBox(height: BxSpace.md),
        ],
        if (entries.isEmpty)
          BxEmptyState(
            icon: Icons.inventory_2_outlined,
            title: status.isRunning ? 'Filling your vault…' : 'Nothing saved yet',
            message: status.isRunning
                ? 'Your notes are coming down now. You can keep using the app '
                    '— this finishes in the background.'
                : 'Tap sync above and every note on your shelf saves itself. '
                    'Open a material and tap Save to keep the big documents too.',
            actionLabel: status.isRunning ? null : 'Sync now',
            onAction: status.isRunning ? null : _syncNow,
          )
        else
          BxStagger(
            spacing: BxSpace.xs,
            children: [for (final e in entries) _row(e)],
          ),
      ],
    );
  }

  Widget _counts(OfflineSummary s) {
    final c = context.bx;
    return Container(
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BxRadius.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Stat(label: 'Materials', value: '${s.items}'),
              _Stat(label: 'Questions', value: '${s.questions}'),
              _Stat(label: 'Pictures', value: '${s.pictures}'),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Divider(height: 1, color: c.line),
          const SizedBox(height: BxSpace.xs),
          Row(
            children: [
              Icon(Icons.sd_storage_outlined, size: 15, color: c.muted),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text(
                  s.syncedAt == null
                      ? 'Not synced yet'
                      : 'Last synced ${DateFormat('d MMM, h:mm a').format(s.syncedAt!)}',
                  style: BxType.tiny(c.muted),
                ),
              ),
              Text(formatBytes(s.bytes), style: BxType.mono(c.inkSoft, size: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _autoDocsSwitch() {
    final c = context.bx;
    final on = ref.watch(localStoreProvider).getBool(BxKeys.autoDownloadDocs);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.sm, vertical: BxSpace.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BxRadius.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_rounded, size: 18, color: c.goldDeep),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Also download PDFs on Wi-Fi', style: BxType.smallStrong(c.ink)),
                Text(
                  'Notes, pictures and questions always save themselves. '
                  'Whole documents are big, so they only come down when you '
                  'ask and only on Wi-Fi.',
                  style: BxType.tiny(c.muted),
                ),
              ],
            ),
          ),
          Switch(value: on, onChanged: _setAutoDocs),
        ],
      ),
    );
  }

  Widget _row(OfflineItem e) {
    final c = context.bx;
    // TUTOR BELLO'S date where it is knowable, the student's only where
    // it is not.
    //
    // "subject last updated from Bello o not the download" — every row
    // here said "saved 12 Aug", which answers when the student pressed
    // a button. What they actually want to know about a note is how
    // fresh it is, and only Tutor Bello moves that.
    final bello = e.updatedAt;
    final parts = <String>[
      if (e.courseCode.isNotEmpty) e.courseCode,
      bello != null
          ? 'updated ${DateFormat('d MMM').format(bello)}'
          : 'saved ${DateFormat('d MMM').format(e.savedAt)}',
      if (e.bytes > 0) e.sizeLabel,
      if (e.pinned) 'kept',
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
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: BxType.h2(c.ink)),
          Text(label, style: BxType.tiny(c.muted)),
        ],
      ),
    );
  }
}

/// What the sync is doing, in words. A progress bar that says nothing is
/// how "background downloading" turns into a rumour.
class _SyncCard extends StatelessWidget {
  final SyncStatus status;
  final Future<void> Function() onSync;

  const _SyncCard({required this.status, required this.onSync});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    final (icon, accent, title, message) = switch (status.phase) {
      SyncPhase.running => (
          Icons.cloud_download_outlined,
          BxAccent.info,
          status.total > 0
              ? '${status.label} · ${status.done} of ${status.total}'
              : status.label,
          'Keep using the app. This finishes on its own.',
        ),
      SyncPhase.failed => (
          Icons.cloud_off_rounded,
          BxAccent.warning,
          'Sync stopped',
          status.message ?? 'Try again when you have a steadier connection.',
        ),
      SyncPhase.unsupported => (
          Icons.phonelink_off_rounded,
          BxAccent.warning,
          'This device cannot keep offline copies',
          'Everything still works online.',
        ),
      SyncPhase.done => (
          Icons.offline_pin_rounded,
          BxAccent.success,
          'Your material is on this phone',
          'Notes, pictures and questions open with your data off.',
        ),
      SyncPhase.idle => (
          Icons.wifi_off_rounded,
          BxAccent.gold,
          'Ready to save your material',
          'Tap sync and your notes come down in the background.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.md),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent.ink(c)),
              const SizedBox(width: BxSpace.xs),
              Expanded(child: Text(title, style: BxType.smallStrong(c.ink))),
            ],
          ),
          const SizedBox(height: 2),
          Text(message, style: BxType.tiny(c.inkSoft)),
          if (status.isRunning) ...[
            const SizedBox(height: BxSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(BxRadius.pill),
              child: LinearProgressIndicator(
                value: status.total > 0 ? status.progress : null,
                minHeight: 4,
                backgroundColor: c.line,
                valueColor: AlwaysStoppedAnimation(c.gold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

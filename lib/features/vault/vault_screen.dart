import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../data/offline/offline_store.dart';
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
    if (!mounted) return;
    setState(() {});
    if (on) {
      bxToast(context, 'PDFs will come down on Wi-Fi from the next sync.');
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // No "Sync now" here any more. One way onto the phone: the Download
    // button on each course.
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
          const _VaultHeadCard(),
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
            title: 'Nothing saved yet',
            message: 'Open a course and tap Download. It pulls every note, '
                'slide, past question, picture and question for that course '
                'in one go, and you watch it happen.',
            actionLabel: 'Go to my courses',
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
          // The date that matters is TUTOR BELLO'S.
          //
          // This card used to lead with "Last synced 3:14 PM", which
          // answers a question nobody asked — the student knows when
          // they pressed the button. What they cannot see is how fresh
          // the material itself is, and only Tutor Bello moves that.
          // So his date leads, and the phone's own clock is demoted to
          // the second line where it belongs.
          Row(
            children: [
              Icon(Icons.edit_calendar_outlined, size: 15, color: c.goldDeep),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text(
                  _belloLine(),
                  style: BxType.tiny(c.inkSoft),
                ),
              ),
              Text(formatBytes(s.bytes), style: BxType.mono(c.inkSoft, size: 12)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.sd_storage_outlined, size: 14, color: c.muted),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text(
                  _lastDownloadLine(),
                  style: BxType.tiny(c.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// When this phone last pulled a course down.
  ///
  /// Was "Last synced", from a background sync that no longer exists.
  /// The honest answer now is the newest download record on the disk —
  /// and it stays the SECOND line, under Tutor Bello's date, because
  /// his is the one that says how fresh the material is.
  String _lastDownloadLine() {
    final store = ref.watch(offlineStoreProvider);
    ref.watch(offlineRecordTick);
    if (store == null) return 'This phone cannot keep offline copies';
    DateTime? newest;
    for (final id in store.downloadedCourses) {
      final at = (store.courseRecord(id)?['at'] as num?)?.toInt() ?? 0;
      if (at <= 0) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(at);
      if (newest == null || d.isAfter(newest)) newest = d;
    }
    if (newest == null) return 'No course downloaded on this phone yet';
    return 'You last downloaded ${bxBelloDate(newest)}';
  }

  /// "Tutor Bello last updated …" across every course on the shelf.
  ///
  /// Falls back to saying nothing is known rather than borrowing the
  /// phone's clock — a made-up date here is worse than an absent one.
  String _belloLine() {
    final stamps = ref.watch(courseStampsProvider);
    final pending = ref.watch(coursesWithUpdatesProvider);
    DateTime? newest;
    for (final st in stamps.values) {
      final d = st.updatedAt;
      if (d == null) continue;
      if (newest == null || d.isAfter(newest)) newest = d;
    }
    if (pending > 0) {
      return newest == null
          ? '$pending ${pending == 1 ? 'course has' : 'courses have'} new '
              'material — tap sync'
          : 'Tutor Bello last updated ${bxBelloDate(newest)} · '
              '$pending ${pending == 1 ? 'course' : 'courses'} to pull';
    }
    if (newest == null) return 'Sync to see when Tutor Bello last updated';
    return 'Tutor Bello last updated ${bxBelloDate(newest)}';
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
                Text('Include whole PDFs on Wi-Fi',
                    style: BxType.smallStrong(c.ink)),
                Text(
                  'A course Download always brings its notes, pictures, '
                  'voice notes and questions. Whole documents are big, so '
                  'they only come down when this is on and you are on '
                  'Wi-Fi.',
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
          ? 'updated ${bxBelloDate(bello)}'
          : 'saved ${bxBelloDate(e.savedAt)}',
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

/// WHERE MATERIAL COMES FROM NOW.
///
/// There used to be a "Sync now" button here that promised to fill the
/// vault by itself. It did not, and having two ways to get material
/// onto a phone meant neither was ever clearly the answer — a student
/// who tapped sync and saw nothing arrive had no idea whether to wait
/// or to go and press something else.
///
/// One way now: the Download button on each course. This card says what
/// is here and sends them to the right place for more.
class _VaultHeadCard extends ConsumerWidget {
  const _VaultHeadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final held = ref.watch(vaultProvider).isNotEmpty;
    final pending = ref.watch(coursesWithUpdatesProvider);

    final (icon, accent, title, message) = pending > 0
        ? (
            Icons.sync_problem_rounded,
            BxAccent.warning,
            pending == 1
                ? 'One course has a change'
                : '$pending courses have a change',
            'Tutor Bello has added or changed something. Open the course '
                'and tap Update.',
          )
        : held
            ? (
                Icons.offline_pin_rounded,
                BxAccent.success,
                'Your material is on this phone',
                'Notes, pictures and questions open with your data off.',
              )
            : (
                Icons.download_for_offline_outlined,
                BxAccent.gold,
                'Nothing downloaded yet',
                'Open a course and tap Download. It pulls every note, '
                    'file, picture and question for that course in one go.',
              );

    return Container(
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.md),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent.ink(c)),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BxType.smallStrong(accent.ink(c))),
                const SizedBox(height: 2),
                Text(message, style: BxType.tiny(c.inkSoft)),
                const SizedBox(height: BxSpace.xs),
                BxButton.secondary(
                  held && pending == 0 ? 'My courses' : 'Go to my courses',
                  icon: Icons.menu_book_rounded,
                  onPressed: () => context.go(Routes.courses),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

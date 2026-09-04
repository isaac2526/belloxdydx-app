import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// ANNOUNCEMENTS — THE NOTICEBOARD
///
/// Everything Tutor Bello has ever posted, newest first. Unread notices
/// wear gold and a filled dot until they are read; nothing is ever
/// deleted, so a student who missed a week can scroll back and catch up.
/// ============================================================

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  /// Ids acknowledged during this visit. The server has been told, but
  /// the list in hand still carries the old flag until it is refetched.
  final _readHere = <String>{};
  bool _clearing = false;

  static String _friendly(Object e) => e is BxError
      ? e.message
      : 'The noticeboard did not load. Check your connection and pull to '
          'refresh.';

  bool _isUnread(Announcement a) => a.unread && !_readHere.contains(a.id);

  Future<void> _refresh() async {
    ref.invalidate(announcementsProvider);
    try {
      await ref.read(announcementsProvider.future);
    } catch (_) {
      // The error surface below already explains it; the pull just ends.
    }
  }

  Future<void> _open(Announcement a) async {
    if (!_isUnread(a)) return;
    setState(() => _readHere.add(a.id));
    await ref.read(engageRepoProvider).acknowledge(a.id);
  }

  Future<void> _clearAll(List<Announcement> all) async {
    if (_clearing) return;
    setState(() => _clearing = true);
    await ref.read(engageRepoProvider).acknowledgeAll();
    if (!mounted) return;
    setState(() {
      _readHere.addAll(all.map((a) => a.id));
      _clearing = false;
    });
    ref.invalidate(announcementsProvider);
    bxToast(context, 'Noticeboard cleared. The archive stays.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BxAppBar(
        title: 'Announcements',
        subtitle: 'The noticeboard',
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(child: _body(context)),
      ),
    );
  }

  // ---------------------------------------------------------- states

  Widget _body(BuildContext context) {
    final feed = ref.watch(announcementsProvider);

    if (feed.hasError && !feed.hasValue) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: BxSpace.xs),
        child: BxErrorState(
          title: 'The noticeboard did not load',
          message: _friendly(feed.error ?? 'Something went wrong.'),
          onRetry: _refresh,
        ),
      );
    }

    if (feed.isLoading && !feed.hasValue) {
      return const Column(
        key: ValueKey('loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxSkeleton(width: 210, height: 12),
          SizedBox(height: BxSpace.md),
          BxSkeletonList(count: 5, itemHeight: 104),
        ],
      );
    }

    final items = feed.value!;
    if (items.isEmpty) {
      return const Padding(
        key: ValueKey('empty'),
        padding: EdgeInsets.only(top: BxSpace.xs),
        child: BxEmptyState(
          icon: Icons.campaign_outlined,
          title: 'Nothing posted yet',
          message: 'Announcements from Tutor Bello land here.',
        ),
      );
    }

    final unread = items.where(_isUnread).length;

    return Column(
      key: ValueKey('feed-${items.length}-$unread'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderLine(
          unread: unread,
          clearing: _clearing,
          onClearAll: unread == 0 ? null : () => _clearAll(items),
        ),
        const SizedBox(height: BxSpace.md),
        BxStagger(
          spacing: BxSpace.sm,
          children: [
            for (final a in items)
              _AnnouncementCard(
                announcement: a,
                unread: _isUnread(a),
                onTap: () => _open(a),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================ header

class _HeaderLine extends StatelessWidget {
  final int unread;
  final bool clearing;
  final VoidCallback? onClearAll;

  const _HeaderLine({
    required this.unread,
    required this.clearing,
    this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final line = unread > 0
        ? '$unread unread · older ones live here forever'
        : 'All caught up · the archive stays here';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            line,
            style: unread > 0
                ? BxType.smallStrong(c.goldDeep)
                : BxType.small(c.muted),
          ),
        ),
        if (onClearAll != null) ...[
          const SizedBox(width: BxSpace.xs),
          BxButton.ghost(
            'Clear all',
            icon: Icons.done_all_rounded,
            loading: clearing,
            loadingLabel: 'Clearing…',
            onPressed: onClearAll,
          ),
        ],
      ],
    );
  }
}

// ============================================================ card

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool unread;
  final VoidCallback onTap;

  const _AnnouncementCard({
    required this.announcement,
    required this.unread,
    required this.onTap,
  });

  static String _stamp(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final sameYear = local.year == DateTime.now().year;
    return DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final a = announcement;
    final stamp = _stamp(a.createdAt);
    // Say when he CHANGED it, not only when he first posted it. A
    // student seeing a notice they had already dismissed needs to know
    // why it is back.
    final edited = a.wasEdited ? 'edited ${_stamp(a.updatedAt)}' : '';
    final meta = [
      if (stamp.isNotEmpty) stamp,
      if (edited.isNotEmpty) edited,
      if (!a.isActive) 'past',
    ].join(' · ');

    return BxCard(
      accent: unread ? BxAccent.gold : BxAccent.neutral,
      onTap: unread ? onTap : null,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (unread) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: BxSpace.xs),
                    ],
                    Expanded(
                      child: Text(
                        a.title.isEmpty ? 'Notice' : a.title,
                        style: BxType.bodyStrong(unread ? c.goldDeep : c.ink),
                      ),
                    ),
                  ],
                ),
                if (a.body.trim().isNotEmpty) ...[
                  const SizedBox(height: BxSpace.xxs),
                  Text(
                    a.body.trim(),
                    style: BxType.body(c.inkSoft),
                    softWrap: true,
                  ),
                ],
                if (unread) ...[
                  const SizedBox(height: BxSpace.xs),
                  Text('Tap to mark as read', style: BxType.tiny(c.muted)),
                ],
              ],
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: BxSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                meta,
                style: BxType.tiny(c.muted),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

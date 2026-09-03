import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_drawer.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// LEADERBOARD — THE RANKS TAB
///
/// Every point on this board was earned by showing up: a note opened,
/// a question answered right, a test finished, a streak kept alive.
/// The student sees their own standing first, then the room, then the
/// two rooms next door — the weekly League and the Millionaire seat.
/// ============================================================

const _medals = <int, String>{1: '🥇', 2: '🥈', 3: '🥉'};

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  static String _friendly(Object e) => e is BxError
      ? e.message
      : 'The board did not load. Check your connection and pull to refresh.';

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(leaderboardProvider);
    try {
      await ref.read(leaderboardProvider.future);
    } catch (_) {
      // The error surface below already says what happened; the pull ends.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;

    return Scaffold(
      appBar: AppBar(
        leading: const BxDrawerButton(),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Leaderboard', style: BxType.h3(c.ink)),
            const SizedBox(height: 2),
            const BxEyebrow('Rankings'),
          ],
        ),
      ),
      body: BxPage(
        onRefresh: () => _refresh(ref),
        child: BxSwitcher(child: _body(context, ref)),
      ),
    );
  }

  // ---------------------------------------------------------- states

  Widget _body(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider);

    if (board.hasError && !board.hasValue) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: BxSpace.xs),
        child: BxErrorState(
          title: 'The board did not load',
          message: _friendly(board.error ?? 'Something went wrong.'),
          onRetry: () => _refresh(ref),
        ),
      );
    }

    if (board.isLoading && !board.hasValue) {
      return const Column(
        key: ValueKey('loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxSkeletonList(count: 1, itemHeight: 148),
          SizedBox(height: BxSpace.xs),
          BxSkeletonList(count: 6, itemHeight: 62),
        ],
      );
    }

    final data = board.value!;
    final top = data.top;
    final me = data.me;
    final activated = ref.watch(profileProvider).isActivated;

    // The backend flags the student's own row, but a legacy payload can
    // arrive without an id to compare, so fall back to the username.
    final myHandle = me.username.trim().toLowerCase().isNotEmpty
        ? me.username.trim().toLowerCase()
        : ref.watch(profileProvider).username.trim().toLowerCase();
    bool mine(LeaderRow r) =>
        r.isMe ||
        (myHandle.isNotEmpty && r.username.trim().toLowerCase() == myHandle);

    final inTop = top.any(mine);
    final showPinned = !inTop && me.total > 0 && myHandle.isNotEmpty;

    final rows = <Widget>[];
    for (var i = 0; i < top.length; i++) {
      if (i > 0) rows.add(const BxDivider(height: 1));
      final r = top[i];
      rows.add(_BoardRow(
        rank: r.rank > 0 ? r.rank : i + 1,
        username: r.username,
        fullName: r.fullName,
        total: r.total,
        isMe: mine(r),
      ));
    }

    return BxStagger(
      key: ValueKey('board-${top.length}-$showPinned-$activated'),
      children: [
        if (!activated)
          BxBanner(
            title: 'Preview mode',
            message: 'Your name joins this board the day you activate. '
                'Small daily reading beats midnight panic — and it scores.',
            icon: Icons.lock_outline_rounded,
            actionLabel: 'Activate',
            onAction: () => context.push(Routes.activate),
          ),
        _StandingCard(me),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxSectionHeader(
              title: 'Top 100 · study points',
              padding: EdgeInsets.only(bottom: BxSpace.sm),
            ),
            if (rows.isEmpty)
              BxEmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'The board is empty',
                message: 'First person to study takes the crown.',
                actionLabel: 'Open a course',
                onAction: () => context.go(Routes.courses),
              )
            else
              BxCard(
                padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
          ],
        ),
        if (showPinned)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: BxSpace.xs),
                child: Text(
                  'Outside the hundred for now — here is where you sit.',
                  style: BxType.tiny(context.bx.muted),
                ),
              ),
              BxCard(
                accent: BxAccent.gold,
                padding: const EdgeInsets.symmetric(vertical: BxSpace.xxs),
                child: _BoardRow(
                  rank: me.rank,
                  username: me.username,
                  fullName: me.fullName,
                  total: me.total,
                  isMe: true,
                  tint: false,
                ),
              ),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxSectionHeader(
              title: 'Other rooms',
              padding: EdgeInsets.only(bottom: BxSpace.sm),
            ),
            BxListRow(
              title: 'The League',
              subtitle: 'Weekly points table. Everything resets in 7 days.',
              leading: _Mark(Icons.local_fire_department_rounded, BxAccent.gold),
              onTap: () => context.push(Routes.league),
            ),
            const SizedBox(height: BxSpace.sm),
            BxListRow(
              title: 'Millionaire',
              subtitle: activated
                  ? 'One hot seat, fifteen questions, ₦1,000,000 on the wall.'
                  : 'Activate to take the hot seat.',
              leading: _Mark(Icons.workspace_premium_rounded, BxAccent.violet),
              locked: !activated,
              onTap: () {
                if (!activated) {
                  showActivationGate(
                      context, () => context.push(Routes.activate));
                  return;
                }
                context.push(Routes.millionaire);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ pieces

/// The hero: where the student stands, and exactly how the points are
/// earned so the number never feels like a black box.
class _StandingCard extends StatelessWidget {
  final LeaderRow me;
  const _StandingCard(this.me);

  @override
  Widget build(BuildContext context) {
    return BxCard(
      accent: BxAccent.gold,
      child: LayoutBuilder(
        builder: (context, box) {
          // Two columns only when the rules can hold a readable measure.
          if (box.maxWidth >= 420) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _standing(context)),
                const SizedBox(width: BxSpace.md),
                Expanded(flex: 6, child: _rules(context)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _standing(context),
              const SizedBox(height: BxSpace.sm),
              const BxDivider(height: 1),
              const SizedBox(height: BxSpace.sm),
              _rules(context),
            ],
          );
        },
      ),
    );
  }

  Widget _standing(BuildContext context) {
    final c = context.bx;
    final ranked = me.rank > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BxEyebrow('Your standing'),
        const SizedBox(height: BxSpace.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  ranked ? '#${me.rank}' : '—',
                  style: BxType.hero(c.goldDeep),
                ),
              ),
            ),
            const SizedBox(width: BxSpace.xs),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '${me.total} pts',
                style: BxType.mono(c.goldDeep, size: 14, weight: 600),
              ),
            ),
          ],
        ),
        const SizedBox(height: BxSpace.xxs),
        Text(
          ranked
              ? 'Keep showing up and this number keeps climbing.'
              : 'No points yet. One note opened today starts the count.',
          style: BxType.tiny(c.muted),
        ),
      ],
    );
  }

  Widget _rules(BuildContext context) {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BxEyebrow('How you earn', color: c.muted),
        const SizedBox(height: BxSpace.xs),
        for (final rule in BxPoints.rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(rule, style: BxType.tiny(c.muted)),
          ),
      ],
    );
  }
}

/// One row of the board. Medal for the podium, plain number after that.
class _BoardRow extends StatelessWidget {
  final int rank;
  final String username;
  final String fullName;
  final int total;
  final bool isMe;
  final bool tint;

  const _BoardRow({
    required this.rank,
    required this.username,
    required this.fullName,
    required this.total,
    this.isMe = false,
    this.tint = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final handle = username.trim();
    final name = fullName.trim();
    final title = name.isNotEmpty ? name : '@$handle';
    final medal = _medals[rank];

    return Container(
      color: isMe && tint ? c.goldTint : null,
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: medal != null
                ? Text(medal,
                    style: BxType.bodyLg(c.ink), textAlign: TextAlign.center)
                : Text(
                    rank > 0 ? '$rank' : '–',
                    style: BxType.mono(c.muted, size: 13, weight: 600),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(width: BxSpace.sm),
          BxAvatar(handle.isEmpty ? '?' : handle, size: 34),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: BxType.bodyStrong(c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: BxSpace.xxs),
                        child: Text('· you',
                            style: BxType.smallStrong(c.goldDeep)),
                      ),
                  ],
                ),
                if (name.isNotEmpty)
                  Text(
                    '@$handle',
                    style: BxType.tiny(c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          Text('$total', style: BxType.mono(c.goldDeep, size: 14, weight: 600)),
        ],
      ),
    );
  }
}

/// The small square mark that leads a navigation row.
class _Mark extends StatelessWidget {
  final IconData icon;
  final BxAccent accent;
  const _Mark(this.icon, this.accent);

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Icon(icon, size: 18, color: accent.ink(c)),
    );
  }
}

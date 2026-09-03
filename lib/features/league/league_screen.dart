import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE LEAGUE — THE SEVEN-DAY TABLE
///
/// The all-time board rewards the students who started early. This one
/// resets every week, so a fresh throne is always up for grabs and the
/// person at the top can never relax on it.
/// ============================================================

const _medals = <int, String>{1: '🥇', 2: '🥈', 3: '🥉'};

class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  static String _friendly(Object e) => e is BxError
      ? e.message
      : 'The table did not load. Check your connection and pull to refresh.';

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(leagueProvider);
    try {
      await ref.read(leagueProvider.future);
    } catch (_) {
      // The error surface below already says what happened; the pull ends.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const BxAppBar(
        title: 'The League',
        subtitle: 'Weekly competition',
      ),
      body: BxPage(
        onRefresh: () => _refresh(ref),
        child: BxSwitcher(child: _body(context, ref)),
      ),
    );
  }

  // ---------------------------------------------------------- states

  Widget _body(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final league = ref.watch(leagueProvider);

    if (league.hasError && !league.hasValue) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: BxSpace.xs),
        child: BxErrorState(
          title: 'The table did not load',
          message: _friendly(league.error ?? 'Something went wrong.'),
          onRetry: () => _refresh(ref),
        ),
      );
    }

    if (league.isLoading && !league.hasValue) {
      return const Column(
        key: ValueKey('loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxSkeleton(width: 260, height: 12),
          SizedBox(height: BxSpace.md),
          BxSkeletonList(count: 1, itemHeight: 84),
          SizedBox(height: BxSpace.xs),
          BxSkeletonList(count: 6, itemHeight: 62),
        ],
      );
    }

    final data = league.value!;
    final table = data.table;
    final winners = data.winners;
    final activated = ref.watch(profileProvider).isActivated;

    // The backend flags the student's own row; a legacy payload without an
    // id to compare still resolves through the username.
    final myHandle =
        ref.watch(profileProvider).username.trim().toLowerCase();
    bool mine(LeagueRow r) =>
        r.isMe ||
        (myHandle.isNotEmpty && r.username.trim().toLowerCase() == myHandle);

    LeagueRow? seat;
    for (final r in table) {
      if (mine(r)) {
        seat = r;
        break;
      }
    }

    final rows = <Widget>[];
    for (var i = 0; i < table.length; i++) {
      if (i > 0) rows.add(const BxDivider(height: 1));
      final r = table[i];
      rows.add(_LeagueRowTile(
        rank: r.rank > 0 ? r.rank : i + 1,
        username: r.username,
        points: r.points,
        attempts: r.attempts,
        isMe: mine(r),
      ));
    }

    return BxStagger(
      key: ValueKey('league-${table.length}-${winners.length}'),
      children: [
        Text(
          'Every submitted attempt this week scores points. Resets every '
          '7 days, so nobody sleeps on a throne.',
          style: BxType.body(c.inkSoft),
        ),
        if (seat != null) _SeatCard(seat),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxSectionHeader(
              title: "This week's table",
              padding: EdgeInsets.only(bottom: BxSpace.sm),
            ),
            if (rows.isEmpty)
              BxEmptyState(
                icon: Icons.military_tech_outlined,
                title: 'Silence on the battlefield',
                message:
                    'Submit any practice or test and claim the empty throne.',
                actionLabel: 'Pick a drill',
                onAction: () => context.go(Routes.revision),
              )
            else
              BxCard(
                padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
                // Rows cascade in so the table reads as a standing being
                // counted, not a block of text dropped on screen.
                child: BxStagger(
                  spacing: 0,
                  step: const Duration(milliseconds: 26),
                  children: rows,
                ),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxSectionHeader(
              title: 'Hall of Winners · Millionaire',
              padding: EdgeInsets.only(bottom: BxSpace.sm),
            ),
            if (winners.isEmpty)
              BxCard(
                child: Text(
                  'The hot seat is still cold. Be the first name on this wall.',
                  style: BxType.small(c.muted),
                ),
              )
            else
              BxCard(
                padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < winners.length; i++) ...[
                      if (i > 0) const BxDivider(height: 1),
                      _WinnerTile(winners[i], position: i + 1),
                    ],
                  ],
                ),
              ),
          ],
        ),
        BxButton(
          'Enter the hot seat',
          icon: Icons.workspace_premium_rounded,
          expand: true,
          large: true,
          onPressed: () {
            if (!activated) {
              showActivationGate(context, () => context.push(Routes.activate));
              return;
            }
            context.push(Routes.millionaire);
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ pieces

/// Thousands separators, written here so the prize reads like money.
String _grouped(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

/// Where the student sits in the seven-day table.
class _SeatCard extends StatelessWidget {
  final LeagueRow row;
  const _SeatCard(this.row);

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final attempts = row.attempts;
    return BxCard(
      accent: BxAccent.gold,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(BxRadius.sm),
              border: Border.all(color: BxAccent.gold.stroke(c)),
            ),
            child: Icon(Icons.event_seat_rounded, size: 19, color: c.goldDeep),
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BxEyebrow('Your seat this week'),
                const SizedBox(height: BxSpace.xxs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('#${row.rank}', style: BxType.h1(c.goldDeep)),
                    const SizedBox(width: BxSpace.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· ${row.points} points',
                        style: BxType.mono(c.goldDeep, size: 14, weight: 600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'From $attempts attempt${attempts == 1 ? '' : 's'} since '
                  'the reset. Another one moves you up.',
                  style: BxType.tiny(c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the weekly table.
class _LeagueRowTile extends StatelessWidget {
  final int rank;
  final String username;
  final int points;
  final int attempts;
  final bool isMe;

  const _LeagueRowTile({
    required this.rank,
    required this.username,
    required this.points,
    required this.attempts,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final handle = username.trim();
    final medal = _medals[rank];

    return Container(
      color: isMe ? c.goldTint : null,
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
                        '@$handle',
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
                Text(
                  '$attempts attempt${attempts == 1 ? '' : 's'} this week',
                  style: BxType.tiny(c.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          Text('$points', style: BxType.mono(c.goldDeep, size: 14, weight: 600)),
        ],
      ),
    );
  }
}

/// One name on the Millionaire wall.
class _WinnerTile extends StatelessWidget {
  final MillionaireWinner winner;
  final int position;
  const _WinnerTile(this.winner, {required this.position});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final mark = winner.crowned ? '👑' : (_medals[position] ?? '');
    final handle = winner.username.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: mark.isNotEmpty
                ? Text(mark,
                    style: BxType.bodyLg(c.ink), textAlign: TextAlign.center)
                : Text(
                    '$position',
                    style: BxType.mono(c.muted, size: 13, weight: 600),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  handle.isEmpty ? 'A quiet legend' : '@$handle',
                  style: BxType.bodyStrong(c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (winner.crowned)
                  Text('Crowned in the hot seat',
                      style: BxType.tiny(c.muted), maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          Text(
            '₦${_grouped(winner.won)}',
            style: BxType.mono(c.goldDeep, size: 14, weight: 600),
          ),
        ],
      ),
    );
  }
}

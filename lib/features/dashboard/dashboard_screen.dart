import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE DASHBOARD
///
/// The first screen of the day. Everything here answers one of three
/// questions a student actually has when they open the app: where did I
/// stop, how am I doing, and what should I touch next.
///
/// Flat fills, hairline borders, one figure per card. No gradients.
/// ============================================================

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Showing up is worth points. Fire and forget — the streak must never
    // hold up the first frame, and the repository already swallows errors.
    unawaited(ref.read(engageRepoProvider).touchStreak());
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(dailyProvider);
    await ref.read(dashboardProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final dash = ref.watch(dashboardProvider);
    final profile = ref.watch(profileProvider);
    final data = dash.valueOrNull;

    final firstName = (data?.firstName.isNotEmpty ?? false)
        ? data!.firstName
        : profile.firstName;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: BxSpace.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BxEyebrow('Dashboard'),
            const SizedBox(height: 2),
            Text(
              firstName.isEmpty
                  ? _greeting(DateTime.now())
                  : '${_greeting(DateTime.now())}, $firstName',
              style: BxType.h3(c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: BxSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data != null && data.rank > 0) ...[
                  // On a phone the full "#2 · 1,840 pts" crowds the
                  // greeting until it truncates to "Good afternoon, Ku…".
                  // The rank is the part that matters at a glance; the
                  // points ride along only when there is room for them.
                  BxChip(
                    MediaQuery.sizeOf(context).width < 420
                        ? '#${data.rank}'
                        : '#${data.rank} · ${_thousands(data.points)}',
                    accent: BxAccent.gold,
                    dense: true,
                    onTap: () => context.go(Routes.ranks),
                  ),
                  const SizedBox(width: BxSpace.xxs),
                ],
                if (data != null && data.streakCurrent > 0) ...[
                  BxChip(
                    '${data.streakCurrent}',
                    accent: BxAccent.warning,
                    icon: Icons.local_fire_department_rounded,
                    dense: true,
                    onTap: () => context.go(Routes.ranks),
                  ),
                  const SizedBox(width: BxSpace.xxs),
                ],
                _BellButton(unread: data?.unreadAnnouncements ?? 0),
                IconButton(
                  onPressed: () => ref
                      .read(themeProvider.notifier)
                      .toggle(Theme.of(context).brightness),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                      width: 40, height: 40),
                  tooltip: context.isDark ? 'Light mode' : 'Dark mode',
                  icon: Icon(
                    context.isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: dash.when(
          loading: () => const BxSkeletonDashboard(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.only(top: BxSpace.lg),
            child: BxErrorState(
              title: 'Your dashboard did not load',
              message: _friendlyError(e),
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
          ),
          data: (d) => _DashboardBody(d),
        ),
      ),
    );
  }
}

/// 1840 -> "1,840". Keeps the rank chip readable without pulling in a
/// formatter just for one number.
String _thousands(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Greeting from the clock on the student's phone.
String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Nothing technical ever reaches a student. [BxError] messages are
/// already written for them; anything else gets a plain sentence.
String _friendlyError(Object e) => e is BxError
    ? e.message
    : 'Check your data or Wi-Fi and pull down to try again.';

class _BellButton extends StatelessWidget {
  final int unread;
  const _BellButton({required this.unread});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () => context.push(Routes.announcements),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          tooltip: 'Announcements',
          icon: const Icon(Icons.notifications_none_rounded, size: 21),
        ),
        if (unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c.danger,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------
// Body
// ------------------------------------------------------------

class _DashboardBody extends ConsumerWidget {
  final DashboardData d;
  const _DashboardBody(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final activated = ref.watch(profileProvider).isActivated;
    final answered = d.correctCount + d.wrongCount;

    return BxStagger(
      spacing: BxSpace.md,
      children: [
        if (!activated)
          BxBanner(
            title: 'Preview mode',
            message: 'You are looking at the real thing. One activation key '
                'opens every note, question and test on it.',
            icon: Icons.visibility_outlined,
            actionLabel: 'Activate now',
            onAction: () => context.push(Routes.activate),
          ),

        if (d.resume != null) _ResumeCard(d.resume!, activated: activated),

        // ---- the three figures that matter ----
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BxStatTile(
                  label: 'Attempts submitted',
                  value: d.attemptsSubmitted,
                  icon: Icons.task_alt_rounded,
                ),
              ),
              const SizedBox(width: BxSpace.sm),
              Expanded(
                child: BxStatTile(
                  label: 'Average score',
                  value: d.averagePercent,
                  suffix: '%',
                  accent: BxAccent.info,
                  icon: Icons.insights_rounded,
                ),
              ),
              const SizedBox(width: BxSpace.sm),
              Expanded(
                child: BxStatTile(
                  label: 'Questions answered',
                  value: d.questionsAnswered,
                  accent: BxAccent.success,
                  icon: Icons.done_all_rounded,
                ),
              ),
            ],
          ),
        ),

        if (answered > 0)
          BxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Head(
                  eyebrow: 'All time',
                  title: 'Your accuracy',
                ),
                const SizedBox(height: BxSpace.md),
                BxDonut(
                  size: 116,
                  centerValue: '${(d.correctCount / answered * 100).round()}%',
                  centerLabel: 'correct',
                  data: [
                    BxSlice('Correct', d.correctCount.toDouble(), c.success),
                    BxSlice('Missed', d.wrongCount.toDouble(), c.danger),
                  ],
                ),
              ],
            ),
          ),

        if (d.courseAverages.isNotEmpty)
          BxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Head(
                  eyebrow: 'Where you stand',
                  title: 'Average score by course',
                ),
                const SizedBox(height: BxSpace.md),
                BxBars(
                  suffix: '%',
                  data: [
                    for (final a in d.courseAverages)
                      BxBar(a.code, a.average.toDouble()),
                  ],
                ),
              ],
            ),
          ),

        const _DailyCard(),

        BxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BxEyebrow('Fuel for today'),
              const SizedBox(height: BxSpace.sm),
              Text(
                '“${d.quote.content}”',
                style: BxType.h3(c.ink).copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: BxSpace.xs),
              Text('— ${d.quote.author}', style: BxType.small(c.muted)),
            ],
          ),
        ),

        if (d.wallOfFame.isNotEmpty) _WallOfFame(d.wallOfFame),

        if (d.marathonAt != null) _MarathonCard(d.marathonAt!),

        _RecentResults(d.recent),

        _ShortcutGrid(activated: activated),

        const _ReferralCard(),
      ],
    );
  }
}

/// Eyebrow over a title, with an optional trailing mark. Every card head
/// on this screen is built from it so they line up exactly.
class _Head extends StatelessWidget {
  final String eyebrow;
  final String title;
  final Widget? trailing;

  const _Head({required this.eyebrow, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              BxEyebrow(eyebrow),
              const SizedBox(height: 3),
              Text(title, style: BxType.h3(c.ink)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: BxSpace.xs), trailing!],
      ],
    );
  }
}

// ------------------------------------------------------------
// Resume
// ------------------------------------------------------------

class _ResumeCard extends StatelessWidget {
  final ResumeCard resume;
  final bool activated;

  const _ResumeCard(this.resume, {required this.activated});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: BxAccent.gold,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BxEyebrow('Unfinished'),
                const SizedBox(height: 3),
                Text('Continue where you stopped', style: BxType.h3(c.ink)),
                const SizedBox(height: 2),
                Text(
                  resume.courseCode.isEmpty
                      ? 'Your progress is saved'
                      : '${resume.courseCode} · your progress is saved',
                  style: BxType.small(c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          BxButton(
            'Resume',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _guard(context, activated, () {
              context.push(resume.isTimed
                  ? Routes.cbt(resume.attemptId)
                  : Routes.practice(resume.attemptId));
            }),
          ),
        ],
      ),
    );
  }
}

/// Locked content explains itself instead of failing silently.
void _guard(BuildContext context, bool activated, VoidCallback open) {
  if (activated) {
    open();
    return;
  }
  unawaited(
    showActivationGate(context, () => context.push(Routes.activate)),
  );
}

// ------------------------------------------------------------
// Daily challenge
// ------------------------------------------------------------

class _DailyCard extends ConsumerStatefulWidget {
  const _DailyCard();

  @override
  ConsumerState<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends ConsumerState<_DailyCard> {
  /// Held in memory so the card reacts the instant they tap; the same
  /// answer is written to the local store so it survives a restart.
  String? _picked;
  String? _pickedDay;

  static const _reveal = '*'; // short-answer questions have nothing to tap

  String? _answerFor(DailyChallenge d) => _pickedDay == d.day
      ? _picked
      : ref.read(engageRepoProvider).dailyAnswerFor(d.day);

  Future<void> _choose(DailyChallenge d, String key) async {
    if (!ref.read(profileProvider).isActivated) {
      unawaited(
        showActivationGate(context, () => context.push(Routes.activate)),
      );
      return;
    }
    setState(() {
      _picked = key;
      _pickedDay = d.day;
    });
    await ref.read(engageRepoProvider).rememberDailyAnswer(d.day, key);
  }

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyProvider);

    return daily.when(
      loading: () => const BxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BxSkeleton(width: 150, height: 11),
            SizedBox(height: BxSpace.md),
            BxSkeleton(height: 16),
            SizedBox(height: BxSpace.xs),
            BxSkeleton(width: 220, height: 16),
            SizedBox(height: BxSpace.md),
            BxSkeleton(height: 40, radius: BxRadius.sm),
            SizedBox(height: BxSpace.xs),
            BxSkeleton(height: 40, radius: BxRadius.sm),
          ],
        ),
      ),
      error: (e, _) => BxErrorState(
        title: "Today's challenge did not load",
        message: _friendlyError(e),
        onRetry: () => ref.invalidate(dailyProvider),
      ),
      data: (d) => d == null
          ? BxEmptyState(
              icon: Icons.today_rounded,
              title: 'No challenge today',
              message: 'A fresh one drops most mornings. Take a quick '
                  'practice while you wait — small daily reading beats '
                  'midnight panic.',
              actionLabel: 'Open a course',
              onAction: () => context.go(Routes.courses),
            )
          : _card(d),
    );
  }

  Widget _card(DailyChallenge d) {
    final c = context.bx;
    final q = d.question;
    final picked = _answerFor(d);
    final answered = picked != null;
    final key = q.correctKey?.toUpperCase();
    final graded = answered && key != null;
    final gotIt = graded && picked == key;
    final options = q.displayOptions;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(
            eyebrow: q.courseCode.isEmpty
                ? 'Daily challenge'
                : 'Daily challenge · ${q.courseCode}',
            title: 'One question, one shot',
            trailing: graded
                ? BxChip(
                    gotIt ? 'Correct' : 'Missed',
                    accent: gotIt ? BxAccent.success : BxAccent.danger,
                    icon: gotIt
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                    dense: true,
                  )
                : null,
          ),
          const SizedBox(height: BxSpace.md),
          if (q.questionHtml.trim().isNotEmpty)
            BxHtml(q.questionHtml, textStyle: BxType.body(c.ink)),
          if ((q.questionImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: BxSpace.sm),
            _RemoteImage(q.questionImageUrl!),
          ],
          const SizedBox(height: BxSpace.md),
          if (options.isEmpty)
            _shortAnswer(d, answered)
          else
            for (final o in options) ...[
              _OptionRow(
                option: o,
                accent: _accentFor(o.key, picked, key, answered),
                mark: _markFor(o.key, picked, key, answered),
                onTap: answered ? null : () => _choose(d, o.key),
              ),
              const SizedBox(height: BxSpace.xs),
            ],
          if (answered) ...[
            const BxDivider(),
            Text(
              gotIt
                  ? 'Sharp. Come back tomorrow for another one.'
                  : graded
                      ? 'Now you will not forget it. That is the point.'
                      : 'Answer saved. Come back tomorrow for another one.',
              style: BxType.smallStrong(gotIt ? c.success : c.inkSoft),
            ),
            if (q.hasExplanation) ...[
              const SizedBox(height: BxSpace.sm),
              const BxEyebrow('Why'),
              const SizedBox(height: BxSpace.xs),
              if ((q.explanationHtml ?? '').trim().isNotEmpty)
                BxHtml(q.explanationHtml!,
                    textStyle: BxType.small(c.inkSoft)),
              if ((q.explanationImageUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: BxSpace.sm),
                _RemoteImage(q.explanationImageUrl!),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// Typed-answer questions have nothing to tap, so the one shot here is
  /// choosing to look — after that the answer stays revealed all day.
  Widget _shortAnswer(DailyChallenge d, bool answered) {
    final c = context.bx;
    final q = d.question;
    if (!answered) {
      return Align(
        alignment: Alignment.centerLeft,
        child: BxButton.secondary(
          'Show the answer',
          icon: Icons.visibility_rounded,
          onPressed: () => unawaited(_choose(d, _reveal)),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: BxAccent.success.stroke(c)),
      ),
      child: Text(
        q.acceptedAnswer.isEmpty ? 'Answer revealed below.' : q.acceptedAnswer,
        style: BxType.bodyStrong(c.success),
      ),
    );
  }

  BxAccent _accentFor(String k, String? picked, String? key, bool answered) {
    if (!answered) return BxAccent.neutral;
    if (key == null) return k == picked ? BxAccent.gold : BxAccent.neutral;
    if (k == key) return BxAccent.success;
    if (k == picked) return BxAccent.danger;
    return BxAccent.neutral;
  }

  IconData? _markFor(String k, String? picked, String? key, bool answered) {
    if (!answered || key == null) return null;
    if (k == key) return Icons.check_circle_rounded;
    if (k == picked) return Icons.cancel_rounded;
    return null;
  }
}

class _OptionRow extends StatelessWidget {
  final QuestionOption option;
  final BxAccent accent;
  final IconData? mark;
  final VoidCallback? onTap;

  const _OptionRow({
    required this.option,
    required this.accent,
    this.mark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.sm, vertical: BxSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent == BxAccent.neutral ? c.surfaceAlt : c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: accent.stroke(c)),
            ),
            child: Text(option.key,
                style: BxType.mono(accent.ink(c), size: 11.5, weight: 600)),
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.text.isNotEmpty)
                  // Options are stored as HTML like the question itself,
                  // so a unit written &middot; must not reach the screen
                  // spelled out.
                  BxHtml(option.text, textStyle: BxType.body(c.ink)),
                if ((option.imageUrl ?? '').isNotEmpty) ...[
                  if (option.text.isNotEmpty) const SizedBox(height: BxSpace.xs),
                  _RemoteImage(option.imageUrl!, height: 120),
                ],
              ],
            ),
          ),
          if (mark != null) ...[
            const SizedBox(width: BxSpace.xs),
            Icon(mark, size: 19, color: accent.ink(c)),
          ],
        ],
      ),
    );
  }
}

class _RemoteImage extends StatelessWidget {
  final String url;
  final double? height;

  const _RemoteImage(this.url, {this.height});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: BxImage(
        imageUrl: url,
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        placeholder: (_, __) =>
            BxSkeleton(height: height ?? 150, radius: BxRadius.sm),
        errorWidget: (_, __, ___) => Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: BxSpace.sm),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(BxRadius.sm),
            border: Border.all(color: c.line),
          ),
          child: Text('That image did not load.', style: BxType.tiny(c.muted)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Wall of fame
// ------------------------------------------------------------

class _WallOfFame extends StatelessWidget {
  final List<FameEntry> entries;
  const _WallOfFame(this.entries);

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final top = entries.take(3).toList();

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Head(eyebrow: 'This week', title: 'Wall of fame'),
          const SizedBox(height: BxSpace.md),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: BxSpace.sm),
            Row(
              children: [
                Text(_medals[i], style: BxType.h3(c.ink)),
                const SizedBox(width: BxSpace.sm),
                Expanded(
                  child: Text(
                    '@${top[i].username}',
                    style: BxType.bodyStrong(c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                BxPercentBadge(top[i].percent),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Marathon countdown
// ------------------------------------------------------------

class _MarathonCard extends StatefulWidget {
  final DateTime at;
  const _MarathonCard(this.at);

  @override
  State<_MarathonCard> createState() => _MarathonCardState();
}

class _MarathonCardState extends State<_MarathonCard> {
  Timer? _tick;
  late Duration _left = _remaining();

  Duration _remaining() {
    final gap = widget.at.difference(DateTime.now());
    return gap.isNegative ? Duration.zero : gap;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _left = _remaining());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final live = _left == Duration.zero;

    return BxCard(
      accent: BxAccent.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(
            eyebrow: 'Marathon countdown',
            title: 'December is for history!!!',
            trailing: Icon(Icons.timer_outlined, size: 20, color: c.violet),
          ),
          const SizedBox(height: BxSpace.xs),
          Text(
            live
                ? 'It has started. Get in there.'
                : DateFormat('EEEE d MMMM · h:mm a').format(widget.at.toLocal()),
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              _Unit(value: _left.inDays, label: 'Days'),
              const SizedBox(width: BxSpace.xs),
              _Unit(value: _left.inHours % 24, label: 'Hrs'),
              const SizedBox(width: BxSpace.xs),
              _Unit(value: _left.inMinutes % 60, label: 'Min'),
              const SizedBox(width: BxSpace.xs),
              _Unit(value: _left.inSeconds % 60, label: 'Sec'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Unit extends StatelessWidget {
  final int value;
  final String label;
  const _Unit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: BxSpace.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: BxType.mono(c.ink, size: 20, weight: 700),
            ),
            const SizedBox(height: 2),
            Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Recent results
// ------------------------------------------------------------

class _RecentResults extends StatelessWidget {
  final List<AttemptSummary> recent;
  const _RecentResults(this.recent);

  static String _when(DateTime? at) => at == null
      ? 'Recently'
      : DateFormat('d MMM · h:mm a').format(at.toLocal());

  @override
  Widget build(BuildContext context) {
    final rows = recent.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxSectionHeader(
          title: 'Recent results',
          eyebrow: 'Your last five',
          trailing: BxButton.ghost(
            'Go practice',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.go(Routes.courses),
          ),
        ),
        if (rows.isEmpty)
          BxEmptyState(
            icon: Icons.history_rounded,
            title: 'Nothing here yet',
            message: 'Your first result appears the moment you finish a '
                'practice or test.',
            actionLabel: 'Open a course',
            onAction: () => context.go(Routes.courses),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: BxSpace.sm),
            BxListRow(
              title: rows[i].courseCode.isEmpty
                  ? rows[i].displayTitle
                  : '${rows[i].courseCode} · ${rows[i].displayTitle}',
              subtitle: _when(rows[i].submittedAt),
              trailing: BxPercentBadge(rows[i].percent),
              onTap: () => context.push(Routes.result(rows[i].id)),
            ),
          ],
      ],
    );
  }
}

// ------------------------------------------------------------
// Shortcuts
// ------------------------------------------------------------

class _ShortcutGrid extends StatelessWidget {
  final bool activated;
  const _ShortcutGrid({required this.activated});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _Shortcut(
        icon: Icons.error_outline_rounded,
        title: 'My Mistakes',
        line: 'Every question you missed, waiting for a rematch.',
        accent: BxAccent.danger,
        onTap: () => _guard(
            context, activated, () => context.push(Routes.mistakes)),
      ),
      _Shortcut(
        icon: Icons.workspace_premium_outlined,
        title: 'The League',
        line: 'See exactly where you sit among your coursemates.',
        accent: BxAccent.success,
        onTap: () => context.push(Routes.league),
      ),
      _Shortcut(
        icon: Icons.diamond_outlined,
        title: 'Millionaire',
        line: 'Fifteen questions. One crown. No lifeline wasted.',
        accent: BxAccent.violet,
        onTap: () => _guard(
            context, activated, () => context.push(Routes.millionaire)),
      ),
      _Shortcut(
        icon: Icons.offline_pin_outlined,
        title: 'Offline Vault',
        line: 'Saved notes that open with zero data on you.',
        accent: BxAccent.info,
        onTap: () => context.push(Routes.vault),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: BxSpace.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: BxSpace.sm),
                Expanded(child: tiles[i + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String title;
  final String line;
  final BxAccent accent;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon,
    required this.title,
    required this.line,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: accent.ink(c)),
          const SizedBox(height: BxSpace.sm),
          Text(title, style: BxType.bodyStrong(c.ink)),
          const SizedBox(height: 2),
          Text(line, style: BxType.tiny(c.muted)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Referral
// ------------------------------------------------------------

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard();

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    bxToast(context, 'Code copied. Drop it in your course group chat.');
  }

  Future<void> _share(BuildContext context, String link) async {
    try {
      await Share.share(
        'Join me on Belloxdydx and smash 100 level. $link',
        subject: 'Belloxdydx',
      );
    } catch (_) {
      if (!context.mounted) return;
      bxToast(context, 'The share sheet did not open. Copy your code instead.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final code = ref.watch(profileProvider).referralCode.trim();
    final has = code.isNotEmpty;
    final link = '${BxConfig.siteUrl}/register?ref=$code';

    return BxCard(
      accent: BxAccent.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Head(
            eyebrow: 'Invite a coursemate',
            title: 'Your code pays you back',
          ),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Every coursemate who activates with your code puts '
            '₦${BxConfig.referralRewardNgn} in your pocket and '
            '+${BxPoints.referralActivated} points on your name.',
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: BxSpace.sm, vertical: BxSpace.sm),
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: BorderRadius.circular(BxRadius.sm),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    has ? code : 'Ready once your account finishes setting up',
                    style: has
                        ? BxType.mono(c.ink, size: 15, weight: 600)
                        : BxType.small(c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              IconButton(
                onPressed: has ? () => unawaited(_copy(context, code)) : null,
                tooltip: 'Copy code',
                icon: Icon(Icons.copy_rounded, size: 19, color: c.goldDeep),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          BxButton.secondary(
            'Share my invite link',
            icon: Icons.ios_share_rounded,
            expand: true,
            onPressed: has ? () => unawaited(_share(context, link)) : null,
          ),
        ],
      ),
    );
  }
}

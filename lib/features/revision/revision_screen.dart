import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// REVISION — THE TARGETED TAB
///
/// The rest of the app is where you read and practise. This tab is
/// where the app tells you, plainly, what you are worst at and then
/// builds the drill for you. Small daily reading beats midnight panic,
/// and a drill aimed at your own misses beats reading everything again.
/// ============================================================

class RevisionScreen extends ConsumerStatefulWidget {
  const RevisionScreen({super.key});

  @override
  ConsumerState<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends ConsumerState<RevisionScreen> {
  /// Which start button is in flight — the smart key, the saved key, or a
  /// course id. Only one attempt is ever built at a time.
  static const _smartKey = '#smart';
  static const _savedKey = '#saved';
  String? _busy;

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  Future<void> _refresh() async {
    ref.invalidate(weakSpotsProvider);
    ref.invalidate(bookmarkCountProvider);
    try {
      await ref.read(weakSpotsProvider.future);
      await ref.read(bookmarkCountProvider.future);
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  /// Builds an attempt and opens the practice runner on it.
  Future<void> _launch(String key, Future<String> Function() start) async {
    if (_busy != null) return;

    if (!ref.read(profileProvider).isActivated) {
      await showActivationGate(context, () => context.push(Routes.activate));
      return;
    }

    setState(() => _busy = key);
    try {
      final id = await start();
      if (!mounted) return;
      setState(() => _busy = null);
      context.push(Routes.practice(id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      bxToast(context, _friendly(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: BxSpace.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Revision', style: BxType.h3(c.ink)),
            const SizedBox(height: 2),
            const BxEyebrow('Targeted practice'),
          ],
        ),
      ),
      body: BxPage(
        onRefresh: _refresh,
        child: BxSwitcher(child: _body()),
      ),
    );
  }

  // ---------------------------------------------------------- states

  Widget _body() {
    final weak = ref.watch(weakSpotsProvider);
    final saved = ref.watch(bookmarkCountProvider);

    final failed = (weak.hasError && !weak.hasValue) ||
        (saved.hasError && !saved.hasValue);
    if (failed) {
      final e = weak.error ?? saved.error;
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: BxSpace.xs),
        child: BxErrorState(
          title: 'Your revision plan did not load',
          message: _friendly(e ?? 'Something went wrong.'),
          onRetry: _refresh,
        ),
      );
    }

    final waiting = (weak.isLoading && !weak.hasValue) ||
        (saved.isLoading && !saved.hasValue);
    if (waiting) {
      return const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.only(top: BxSpace.xs),
        child: BxSkeletonList(count: 4, itemHeight: 108),
      );
    }

    final spots = [...(weak.value ?? const <WeakSpot>[])]
      ..sort((a, b) => b.missed.compareTo(a.missed));
    final savedCount = saved.value ?? 0;
    final activated = ref.watch(profileProvider).isActivated;
    final bare = spots.isEmpty && savedCount == 0;

    return BxStagger(
      key: ValueKey('content-${spots.length}-$savedCount-$bare'),
      children: [
        if (!activated)
          BxBanner(
            title: 'Preview mode',
            message: 'Activate and every drill here is built from your own '
                'answers, not a generic list.',
            icon: Icons.lock_outline_rounded,
            actionLabel: 'Activate',
            onAction: () => context.push(Routes.activate),
          ),
        if (bare)
          BxEmptyState(
            icon: Icons.track_changes_rounded,
            title: 'No weak spots recorded yet',
            message: 'Do a few practice rounds first. Anything you miss lands '
                'here, anything you bookmark too.',
            actionLabel: 'Start practicing',
            onAction: () => context.go(Routes.courses),
          )
        else ...[
          _smartPanel(),
          _radar(spots),
          _savedQuestions(savedCount),
        ],
        _shortcuts(),
      ],
    );
  }

  // ---------------------------------------------------------- smart

  Widget _smartPanel() {
    final c = context.bx;
    return BxCard(
      accent: BxAccent.gold,
      raised: true,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 20, color: c.goldDeep),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text('Smart revision', style: BxType.h2(c.ink)),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(
            'One tap and the app builds a drill from your weakest course '
            'automatically.',
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          BxButton(
            'Revise my weakest course',
            icon: Icons.auto_fix_high_rounded,
            expand: true,
            large: true,
            loading: _busy == _smartKey,
            loadingLabel: 'Building your drill…',
            onPressed: _busy == null
                ? () => _launch(
                      _smartKey,
                      () => ref.read(assessmentRepoProvider).startSmart(),
                    )
                : null,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- radar

  Widget _radar(List<WeakSpot> spots) {
    final c = context.bx;
    final worst = spots.isEmpty ? 0 : spots.first.missed;

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxEyebrow('Your weak spots, by course'),
          const SizedBox(height: BxSpace.sm),
          if (spots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: BxSpace.xs),
              child: Text(
                'Nothing on the radar yet. Finish a round and whatever you '
                'miss shows up here by course.',
                style: BxType.small(c.muted),
              ),
            )
          else
            for (final w in spots)
              BxMeterRow(
                label: w.code.isEmpty ? 'Course' : w.code,
                sublabel: w.title,
                trailing: '${w.missed} missed',
                fraction: worst == 0 ? 0 : w.missed / worst,
                color: c.danger,
                action: BxButton.secondary(
                  'Revise',
                  loading: _busy == w.courseId,
                  loadingLabel: 'Building…',
                  onPressed: _busy == null
                      ? () => _launch(
                            w.courseId,
                            () => ref
                                .read(assessmentRepoProvider)
                                .startSmart(courseId: w.courseId),
                          )
                      : null,
                ),
              ),
          Text(
            'Answer a weak question correctly in revision and it quietly '
            'drops off this radar.',
            style: BxType.tiny(c.muted),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- saved

  Widget _savedQuestions(int count) {
    final c = context.bx;
    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('🔖 Saved questions', style: BxType.h3(c.ink)),
              ),
              const SizedBox(width: BxSpace.xs),
              Text(
                '$count',
                style: BxType.mono(c.goldDeep, size: 19, weight: 600),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          if (count == 0)
            Text(
              'Tap Save on any question during practice to build this pile.',
              style: BxType.small(c.muted),
            )
          else ...[
            Text(
              'The ones you flagged to meet again. Run them back whenever you '
              'have ten quiet minutes.',
              style: BxType.small(c.inkSoft),
            ),
            const SizedBox(height: BxSpace.md),
            BxButton(
              'Practice my saved questions',
              icon: Icons.bookmark_rounded,
              expand: true,
              loading: _busy == _savedKey,
              loadingLabel: 'Pulling them out…',
              onPressed: _busy == null
                  ? () => _launch(
                        _savedKey,
                        () => ref.read(assessmentRepoProvider).startBookmarks(),
                      )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- shortcuts

  Widget _shortcuts() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ShortcutCard(
              icon: Icons.error_outline_rounded,
              title: 'My Mistakes',
              line: 'The redemption deck. Swipe through what beat you.',
              accent: BxAccent.danger,
              onTap: () => context.push(Routes.mistakes),
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: _ShortcutCard(
              icon: Icons.history_rounded,
              title: 'Recent results',
              line: 'Your last rounds, scored and dated.',
              accent: BxAccent.info,
              onTap: () => context.go(Routes.home),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String line;
  final BxAccent accent;
  final VoidCallback onTap;

  const _ShortcutCard({
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
      onTap: onTap,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.fill(c),
              borderRadius: BorderRadius.circular(BxRadius.xs),
              border: Border.all(color: accent.stroke(c)),
            ),
            child: Icon(icon, size: 18, color: accent.ink(c)),
          ),
          const SizedBox(height: BxSpace.sm),
          Text(title, style: BxType.h3(c.ink)),
          const SizedBox(height: 2),
          Text(line, style: BxType.tiny(c.muted)),
        ],
      ),
    );
  }
}

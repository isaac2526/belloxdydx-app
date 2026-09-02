import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// WHO WANTS TO BE A BELLOXDYDX MILLIONAIRE
///
/// This is the one screen in the app that is allowed to be loud.
/// Everywhere else Belloxdydx is flat white and gold, because a
/// dashboard should get out of a student's way. A game show is not a
/// dashboard — it is a stage — so this screen deliberately wears the
/// deep night palette in every theme (see `bxDarkTheme` below), with
/// gold hexagons under a spotlight. Still no gradients: deep flat
/// fills, hairline gold edges, one glow on the hexagon you locked in.
/// ============================================================

/// The money. Fifteen rungs, exactly as the show plays it.
const _ladder = <int>[
  1000, 2000, 3000, 5000, 8000, //
  15000, 30000, 50000, 75000, 125000, //
  200000, 300000, 500000, 750000, 1000000,
];

/// Clear question 5 (₦8,000) or question 10 (₦125,000) and that money is
/// yours no matter what happens after.
const _safeHavens = <int>{4, 9};

/// The classic angled hexagon: a straight top and bottom with the left
/// and right corners cut back this far before they meet at a point.
const double _hexChamfer = 26;

/// Wide enough for the money ladder to stand beside the board.
const double _wideStage = 780;

enum _Phase { setup, dealing, play, over }

/// Where the current question is in its lock-in ritual.
enum _Step { asking, locked, revealing }

enum _Ending { won, fell, timedOut, walked }

class MillionaireScreen extends ConsumerWidget {
  const MillionaireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The stage always runs on the deep night palette, whatever theme the
    // student keeps the rest of the app in. It is wrapped here, above the
    // game's own state, so every `context.bx` inside reads the stage
    // colours — including the sheets and dialogs the game opens.
    return Theme(data: bxDarkTheme, child: const _HotSeat());
  }
}

class _HotSeat extends ConsumerStatefulWidget {
  const _HotSeat();

  @override
  ConsumerState<_HotSeat> createState() => _HotSeatState();
}

class _HotSeatState extends ConsumerState<_HotSeat>
    with SingleTickerProviderStateMixin {
  // ---- setup ----
  final Set<String> _selected = <String>{};
  String? _dealError;
  bool _shortPack = false;

  // ---- the pack ----
  List<Question> _qs = <Question>[];

  /// The next unused spare. The deal is 15 questions plus 3 spares, so
  /// the first spare sits right after the last rung.
  int _spareAt = _ladder.length;

  // ---- the game ----
  _Phase _phase = _Phase.setup;
  _Step _step = _Step.asking;
  int _index = 0;
  String? _picked;
  final Set<String> _eliminated = <String>{};

  // ---- lifelines ----
  bool _used5050 = false;
  bool _usedPoll = false;
  bool _usedSwitch = false;
  bool _pollLoading = false;
  ({int sample, Map<String, int> spread})? _poll;

  // ---- clock ----
  Timer? _ticker;
  Timer? _seq;
  int _limit = 15;
  int _left = 15;
  bool _paused = false;

  // ---- ending ----
  _Ending? _ending;
  int _amount = 0;
  String? _rightAnswer;

  /// The result is reported to the Hall of Winners exactly once a game.
  bool _reported = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  final _rng = math.Random();

  @override
  void dispose() {
    _ticker?.cancel();
    _seq?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- helpers

  Question get _current => _qs[_index];

  bool get _hasSpare => _qs.length > _spareAt;

  int _limitFor(int i) => i < 5 ? 15 : (i < 10 ? 30 : 45);

  /// The money already banked at a safe haven, which no wrong answer and
  /// no clock can take back.
  int _guaranteed() {
    var best = 0;
    for (final h in _safeHavens) {
      if (h < _index) best = math.max(best, _ladder[h]);
    }
    return best;
  }

  String _money(int n) {
    final s = n.toString();
    final b = StringBuffer('₦');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'The line dropped before the questions arrived. Check your '
          'connection and try again.';

  /// Option text is short and lives inside a fixed hexagon, so it is
  /// flattened to plain text rather than rendered as a document.
  String _plain(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();

  void _after(Duration d, VoidCallback fn) {
    _seq?.cancel();
    _seq = Timer(d, () {
      if (mounted) fn();
    });
  }

  // ---------------------------------------------------------- the game

  Future<void> _deal() async {
    setState(() {
      _phase = _Phase.dealing;
      _dealError = null;
      _shortPack = false;
    });
    try {
      final dealt = await ref
          .read(engageRepoProvider)
          .millionaireDeal(_selected.toList());
      if (!mounted) return;

      final playable =
          dealt.where((q) => q.displayOptions.length >= 2).toList();
      if (playable.length < _ladder.length) {
        setState(() {
          _phase = _Phase.setup;
          _shortPack = true;
        });
        return;
      }

      setState(() {
        _qs = playable;
        _spareAt = _ladder.length;
        _index = 0;
        _picked = null;
        _eliminated.clear();
        _used5050 = false;
        _usedPoll = false;
        _usedSwitch = false;
        _poll = null;
        _pollLoading = false;
        _ending = null;
        _amount = 0;
        _rightAnswer = null;
        _reported = false;
        _step = _Step.asking;
        _phase = _Phase.play;
      });
      _startClock();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.setup;
        _dealError = _friendly(e);
      });
    }
  }

  void _startClock() {
    _ticker?.cancel();
    _limit = _limitFor(_index);
    _left = _limit;
    _paused = false;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      setState(() => _left = _left - 1);
      if (_left <= 0) _timeUp();
    });
  }

  void _lockIn(String key) {
    if (_phase != _Phase.play || _step != _Step.asking) return;
    if (_eliminated.contains(key)) return;

    _ticker?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _picked = key;
      _step = _Step.locked;
    });
    if (!reduceMotion(context)) _pulse.repeat(reverse: true);

    // Two seconds of heartbeat, then the reveal, then the fall or the
    // next rung. The wait is the whole point of the format.
    _after(const Duration(milliseconds: 2000), () {
      _pulse.stop();
      _pulse.value = 0;
      HapticFeedback.heavyImpact();
      setState(() => _step = _Step.revealing);
      _after(const Duration(milliseconds: 1400), _settle);
    });
  }

  void _settle() {
    final q = _current;
    final key = (q.correctKey ?? '').toUpperCase();
    // A question that arrived without its answer is never held against a
    // student — it is waved through rather than ending the game unfairly.
    final right = key.isEmpty || key == _picked;

    if (!right) {
      _end(_Ending.fell);
      return;
    }
    if (_index >= _ladder.length - 1) {
      _end(_Ending.won);
      return;
    }
    setState(() {
      _index = _index + 1;
      _picked = null;
      _step = _Step.asking;
      _eliminated.clear();
      _poll = null;
    });
    _startClock();
  }

  void _timeUp() {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    setState(() {
      _picked = null;
      _step = _Step.revealing;
    });
    _after(const Duration(milliseconds: 1400), () => _end(_Ending.timedOut));
  }

  void _report(int amount, bool crowned) {
    if (_reported) return;
    _reported = true;
    ref.read(engageRepoProvider).millionaireReport(amount, crowned);
  }

  void _end(_Ending ending) {
    _ticker?.cancel();
    _seq?.cancel();
    _pulse.stop();
    _pulse.value = 0;

    final amount = switch (ending) {
      _Ending.won => _ladder.last,
      _Ending.walked => _index == 0 ? 0 : _ladder[_index - 1],
      _Ending.fell || _Ending.timedOut => _guaranteed(),
    };
    final crowned = ending == _Ending.won;

    String? answer;
    if (ending == _Ending.fell || ending == _Ending.timedOut) {
      final q = _current;
      final key = (q.correctKey ?? '').toUpperCase();
      if (key.isNotEmpty) {
        final opt = q.displayOptions.where((o) => o.key == key).firstOrNull;
        final text = opt == null ? '' : _plain(opt.text);
        answer = text.isEmpty ? key : '$key · $text';
      }
    }

    _report(amount, crowned);
    HapticFeedback.heavyImpact();
    setState(() {
      _phase = _Phase.over;
      _ending = ending;
      _amount = amount;
      _rightAnswer = answer;
    });
  }

  /// The clock stops while a question is put to the student, exactly as
  /// it does on the show — nobody loses a rung to a dialog box.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    setState(() => _paused = true);
    final ok = await bxConfirm(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (mounted && !ok && _phase == _Phase.play) {
      setState(() => _paused = false);
    }
    return ok;
  }

  Future<void> _walkAway() async {
    if (_phase != _Phase.play || _step != _Step.asking) return;
    final banked = _index == 0 ? 0 : _ladder[_index - 1];
    final ok = await _confirm(
      title: 'Walk away with ${_money(banked)}?',
      message: banked == 0
          ? 'You have not cleared a rung yet, so you would leave with '
              'nothing. One answer changes that.'
          : 'You keep ${_money(banked)} and the game ends here. No shame '
              'in taking the money — it still counts in the Hall of Winners.',
      confirmLabel: 'Walk away',
    );
    // The student may have been knocked off the board while deciding.
    if (!mounted || !ok || _phase != _Phase.play) return;
    _end(_Ending.walked);
  }

  Future<void> _confirmLeave() async {
    if (_phase != _Phase.play) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await _confirm(
      title: 'Leave the hot seat?',
      message: 'The game ends here and you keep only your safe-haven money. '
          'Walk away instead if you want the money on the board.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!mounted || !ok) return;
    _ticker?.cancel();
    _seq?.cancel();
    _report(_guaranteed(), false);
    if (mounted) Navigator.of(context).pop();
  }

  void _playAgain() {
    _ticker?.cancel();
    _seq?.cancel();
    setState(() {
      _phase = _Phase.setup;
      _step = _Step.asking;
      _qs = <Question>[];
      _spareAt = _ladder.length;
      _index = 0;
      _picked = null;
      _eliminated.clear();
      _used5050 = false;
      _usedPoll = false;
      _usedSwitch = false;
      _poll = null;
      _pollLoading = false;
      _ending = null;
      _amount = 0;
      _rightAnswer = null;
      _reported = false;
      _dealError = null;
      _shortPack = false;
    });
  }

  // ---------------------------------------------------------- lifelines

  bool get _canFifty =>
      !_used5050 &&
      _step == _Step.asking &&
      _current.displayOptions.length >= 3 &&
      (_current.correctKey ?? '').isNotEmpty;

  void _fiftyFifty() {
    if (!_canFifty) return;
    final q = _current;
    final key = (q.correctKey ?? '').toUpperCase();
    final wrong = q.displayOptions
        .map((o) => o.key)
        .where((k) => k != key)
        .toList()
      ..shuffle(_rng);
    HapticFeedback.selectionClick();
    setState(() {
      _eliminated
        ..clear()
        ..addAll(wrong.take(2));
      _used5050 = true;
    });
  }

  Future<void> _askTheClass() async {
    if (_usedPoll || _step != _Step.asking) return;
    HapticFeedback.selectionClick();
    // The clock waits while the class is polled — a slow network should
    // never be the thing that knocks a student off the ladder.
    final askedAt = _index;
    final askedId = _current.id;
    setState(() {
      _usedPoll = true;
      _pollLoading = true;
      _paused = true;
    });

    ({int sample, Map<String, int> spread}) r;
    try {
      r = await ref.read(engageRepoProvider).millionairePoll(askedId);
    } catch (_) {
      r = (sample: 0, spread: const <String, int>{});
    }
    if (!mounted) return;

    // If the student moved on, switched the question or ended the game
    // while the poll was in flight, the answer belongs to a question that
    // is no longer on the board — drop it rather than show it.
    final stale = _phase != _Phase.play ||
        _index != askedAt ||
        _current.id != askedId;
    setState(() {
      _pollLoading = false;
      _paused = false;
      if (!stale) _poll = r;
    });
  }

  void _switchQuestion() {
    if (_usedSwitch || _step != _Step.asking) return;
    // The website's version of this lifeline burns itself on the last
    // question and swaps in nothing. Here the spare is checked first, so
    // the student either gets a new question or keeps the lifeline.
    if (!_hasSpare) {
      bxToast(
        context,
        'No spare question left in the pack — this one is yours to answer.',
        error: true,
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _qs[_index] = _qs[_spareAt];
      _spareAt = _spareAt + 1;
      _usedSwitch = true;
      _picked = null;
      _eliminated.clear();
      _poll = null;
    });
    _startClock();
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final activated = ref.watch(profileProvider).isActivated;
    final playing = _phase == _Phase.play;

    return PopScope(
      canPop: !playing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave();
      },
      child: Scaffold(
        appBar: BxAppBar(
          title: playing ? 'The hot seat' : 'Millionaire',
          subtitle: switch (_phase) {
            _Phase.play =>
              'Question ${_index + 1} of 15 · playing for ${_money(_ladder[_index])}',
            _Phase.over => 'Game over',
            _ => 'Fifteen questions · three lifelines',
          },
          actions: [
            // Below the rail breakpoint the ladder has no room beside
            // the board, so it lives in a sheet behind this button.
            if (playing && !context.isWide)
              IconButton(
                tooltip: 'Money ladder',
                onPressed: _openLadderSheet,
                icon: const Icon(Icons.stairs_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: BxSwitcher(
            child: !activated
                ? _locked()
                : switch (_phase) {
                    _Phase.setup => _setup(),
                    _Phase.dealing => _dealing(),
                    _Phase.play => _play(),
                    _Phase.over => _over(),
                  },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- locked

  Widget _locked() {
    return BxPage(
      key: const ValueKey('locked'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: BxSpace.lg),
          BxEmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'The hot seat is locked',
            message: 'The million naira board opens with your activation '
                'key, along with every note, video and test on Belloxdydx. '
                'Activate once and the stage is yours.',
            actionLabel: 'Activate',
            onAction: () => showActivationGate(
              context,
              () => context.push(Routes.activate),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- setup

  Widget _dealing() => const Padding(
        key: ValueKey('dealing'),
        padding: EdgeInsets.all(BxSpace.xl),
        child: Center(child: BxThinking(message: 'Setting the stage…')),
      );

  Widget _setup() {
    final c = context.bx;
    final content = ref.watch(contentProvider);

    return BxPage(
      key: const ValueKey('setup'),
      onRefresh: () async {
        ref.invalidate(contentProvider);
        await ref.read(contentProvider.future);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BxEyebrow('The hot seat'),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Who Wants To Be A\nBelloxdydx Millionaire',
            style: BxType.h1(c.gold),
          ),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Fifteen questions from your own courses. Answer straight and '
            'the money climbs. Miss one and you drop to your last safe '
            'haven — so take the easy rungs seriously.',
            style: BxType.body(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.lg),
          if (_dealError != null) ...[
            BxErrorState(
              title: 'The pack did not arrive',
              message: _dealError!,
              retryLabel: 'Deal again',
              onRetry: _deal,
            ),
            const SizedBox(height: BxSpace.md),
          ],
          if (_shortPack) ...[
            const BxBanner(
              title: 'Not enough questions in that pick',
              message: 'A full board needs fifteen questions plus spares. '
                  'Add another course — or leave every course unpicked — '
                  'and we will deal again.',
              icon: Icons.style_outlined,
              accent: BxAccent.warning,
            ),
            const SizedBox(height: BxSpace.md),
          ],
          _rules(),
          const SizedBox(height: BxSpace.lg),
          const BxSectionHeader(
            title: 'Where should the questions come from?',
            eyebrow: 'Your pack',
            subtitle: 'Pick as many courses as you like. Leave them all '
                'unpicked and we deal from your whole shelf.',
          ),
          content.when(
            loading: () => const BxSkeletonList(count: 2, itemHeight: 92),
            error: (e, _) => BxErrorState(
              title: 'Your courses did not load',
              message: _friendly(e),
              onRetry: () => ref.invalidate(contentProvider),
            ),
            data: (repo) {
              final courses = repo.courses;
              if (courses.isEmpty) {
                return BxEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No courses on your shelf yet',
                  message: 'Once your level has courses we can deal you a '
                      'board. Take a look at what is there now.',
                  actionLabel: 'Open courses',
                  onAction: () => context.go(Routes.courses),
                );
              }
              return _coursePicker(courses);
            },
          ),
          const SizedBox(height: BxSpace.xl),
          BxButton(
            'Enter the hot seat',
            large: true,
            expand: true,
            icon: Icons.play_arrow_rounded,
            onPressed: _deal,
          ),
          const SizedBox(height: BxSpace.sm),
          Center(
            child: TextButton(
              onPressed: () => context.push(Routes.league),
              child: Text('See the Hall of Winners',
                  style: BxType.label(c.goldDeep)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rules() {
    final c = context.bx;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: BxSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: c.gold),
              const SizedBox(width: BxSpace.xs),
              Expanded(child: Text(text, style: BxType.small(c.inkSoft))),
            ],
          ),
        );

    return BxCard(
      fill: c.surfaceSunken,
      border: c.gold.withValues(alpha: 0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxEyebrow('House rules'),
          const SizedBox(height: BxSpace.sm),
          line(Icons.stairs_rounded,
              'Fifteen rungs, from ${_money(_ladder.first)} to ${_money(_ladder.last)}.'),
          line(Icons.shield_outlined,
              'Safe havens at ${_money(_ladder[4])} and ${_money(_ladder[9])} — clear them and that money is yours whatever happens next.'),
          line(Icons.timer_outlined,
              '15 seconds a question up to rung five, 30 up to rung ten, 45 after that. The clock running out costs you the same as a wrong answer.'),
          line(Icons.support_outlined,
              'Three lifelines, one use each: 50:50, Ask the Class, Switch the Question.'),
          line(Icons.emoji_events_outlined,
              'Walk away any time and keep the money already on the board.'),
        ],
      ),
    );
  }

  Widget _coursePicker(List<Course> courses) {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: BxSpace.xs,
          runSpacing: BxSpace.xs,
          children: [
            BxChip(
              'Everything',
              icon: Icons.all_inclusive_rounded,
              selected: _selected.isEmpty,
              onTap: () => setState(_selected.clear),
            ),
            for (final course in courses)
              BxChip(
                course.code,
                icon: _selected.contains(course.id)
                    ? Icons.check_rounded
                    : null,
                selected: _selected.contains(course.id),
                onTap: () => setState(() {
                  if (!_selected.remove(course.id)) _selected.add(course.id);
                }),
              ),
          ],
        ),
        const SizedBox(height: BxSpace.xs),
        Text(
          _selected.isEmpty
              ? 'Dealing from every course on your shelf.'
              : '${_selected.length} course${_selected.length == 1 ? '' : 's'} in the pack.',
          style: BxType.tiny(c.muted),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- play

  Widget _play() {
    return LayoutBuilder(
      key: const ValueKey('play'),
      builder: (context, box) {
        final wide = box.maxWidth >= _wideStage;
        final stage = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _clockStrip(),
                    const SizedBox(height: BxSpace.md),
                    _questionCard(),
                    if (_pollLoading || _poll != null) ...[
                      const SizedBox(height: BxSpace.sm),
                      _pollCard(),
                    ],
                    const SizedBox(height: BxSpace.md),
                    _optionGrid(wide ? box.maxWidth - 248 : box.maxWidth),
                  ],
                ),
              ),
            ),
            _controls(),
          ],
        );

        if (!wide) return stage;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: stage),
            VerticalDivider(width: 1, color: context.bx.line),
            SizedBox(
              width: 232,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BxSpace.md),
                child: _ladderPanel(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openLadderSheet() {
    final c = context.bx;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                BxSpace.md, 0, BxSpace.md, BxSpace.lg),
            child: _ladderPanel(),
          ),
        ),
      ),
    );
  }

  Widget _ladderPanel() {
    final c = context.bx;
    final rows = <Widget>[];
    for (var i = _ladder.length - 1; i >= 0; i--) {
      final current = i == _index;
      final cleared = i < _index;
      final safe = _safeHavens.contains(i);
      final fg = current
          ? BxColors.light.ink
          : (cleared ? c.muted : (safe ? c.goldBright : c.inkSoft));

      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.xs, vertical: BxSpace.xxs + 1),
        decoration: BoxDecoration(
          color: current
              ? c.gold
              : (safe ? c.goldTint : Colors.transparent),
          borderRadius: BorderRadius.circular(BxRadius.xs),
          border: Border.all(
            color: current
                ? c.goldBright
                : (safe ? c.gold.withValues(alpha: 0.35) : Colors.transparent),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text('${i + 1}',
                  style: BxType.mono(fg, size: 11), textAlign: TextAlign.right),
            ),
            const SizedBox(width: BxSpace.xs),
            Icon(
              safe ? Icons.shield_outlined : Icons.circle,
              size: safe ? 13 : 5,
              color: safe ? fg : fg.withValues(alpha: 0.45),
            ),
            const SizedBox(width: BxSpace.xs),
            Expanded(
              child: Text(
                _money(_ladder[i]),
                style: BxType.mono(fg,
                    size: 12.5, weight: current || safe ? 600 : 500),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BxEyebrow('The money'),
        const SizedBox(height: BxSpace.xs),
        ...rows,
        const SizedBox(height: BxSpace.xs),
        Text(
          'Shielded rungs are safe havens. Clear one and that money is '
          'yours for good.',
          style: BxType.tiny(c.muted),
        ),
      ],
    );
  }

  Widget _clockStrip() {
    final c = context.bx;
    final urgent = _left <= 5 && _step == _Step.asking;
    final tone = urgent ? c.danger : c.gold;
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Rung ${_index + 1} · ${_money(_ladder[_index])}',
                style: BxType.mono(c.goldBright, size: 13, weight: 600),
              ),
            ),
            Icon(
              _paused ? Icons.pause_circle_outline_rounded : Icons.timer_outlined,
              size: 15,
              color: tone,
            ),
            const SizedBox(width: 5),
            Text('$mm:$ss', style: BxType.clock(tone)),
          ],
        ),
        const SizedBox(height: 6),
        BxProgressBarRaw(
          fraction: _limit == 0 ? 0 : (_left / _limit).clamp(0.0, 1.0),
          color: tone,
          height: 5,
        ),
        if (_pollLoading) ...[
          const SizedBox(height: 5),
          Text('Clock held while the class answers.',
              style: BxType.tiny(c.muted)),
        ],
      ],
    );
  }

  Widget _questionCard() {
    final c = context.bx;
    final q = _current;
    final safeNext = _safeHavens.contains(_index);

    return BxCard(
      fill: c.surfaceSunken,
      border: c.gold.withValues(alpha: 0.32),
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: BxSpace.xs,
            runSpacing: BxSpace.xxs,
            children: [
              if (q.courseCode.isNotEmpty)
                BxChip(q.courseCode, accent: BxAccent.gold, dense: true),
              if (safeNext)
                const BxChip('Safe haven',
                    accent: BxAccent.success,
                    icon: Icons.shield_outlined,
                    dense: true),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          if (q.questionHtml.trim().isEmpty)
            Text(
              'This question arrived without its text. Switch it or answer '
              'on instinct — nothing here counts against you.',
              style: BxType.body(c.muted),
            )
          else
            HtmlWidget(q.questionHtml, textStyle: BxType.bodyLg(c.ink)),
          if ((q.questionImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: BxSpace.sm),
            _image(q.questionImageUrl!),
          ],
        ],
      ),
    );
  }

  Widget _image(String url) {
    final c = context.bx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(BxRadius.sm),
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const BxSkeleton(height: 160, radius: BxRadius.sm),
          errorWidget: (_, __, ___) => Padding(
            padding: const EdgeInsets.all(BxSpace.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_not_supported_outlined,
                    size: 17, color: c.muted),
                const SizedBox(width: BxSpace.xs),
                Flexible(
                  child: Text('That image would not load.',
                      style: BxType.small(c.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pollCard() {
    final c = context.bx;
    final poll = _poll;

    if (_pollLoading || poll == null) {
      return BxCard(
        fill: c.surfaceAlt,
        border: c.line,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.gold),
            ),
            const SizedBox(width: BxSpace.sm),
            Text('Asking the class…', style: BxType.small(c.inkSoft)),
          ],
        ),
      );
    }

    final options = _current.displayOptions;
    final total = options.fold<int>(0, (s, o) => s + (poll.spread[o.key] ?? 0));

    if (total == 0) {
      return BxCard(
        fill: c.surfaceAlt,
        border: c.line,
        child: Row(
          children: [
            Icon(Icons.groups_outlined, size: 18, color: c.muted),
            const SizedBox(width: BxSpace.sm),
            Expanded(
              child: Text(
                'The class went quiet — nobody has attempted this one yet. '
                'You are on your own here.',
                style: BxType.small(c.inkSoft),
              ),
            ),
          ],
        ),
      );
    }

    return BxCard(
      fill: c.surfaceAlt,
      border: c.gold.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 17, color: c.gold),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text('The class says', style: BxType.bodyStrong(c.ink)),
              ),
              Text('${poll.sample} answered', style: BxType.tiny(c.muted)),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: BxSpace.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Text(o.key,
                        style: BxType.mono(c.goldBright, size: 12, weight: 600)),
                  ),
                  Expanded(
                    child: BxProgressBarRaw(
                      fraction: (poll.spread[o.key] ?? 0) / total,
                      color: _eliminated.contains(o.key) ? c.muted : c.gold,
                      height: 7,
                    ),
                  ),
                  const SizedBox(width: BxSpace.xs),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(((poll.spread[o.key] ?? 0) / total) * 100).round()}%',
                      style: BxType.mono(c.inkSoft, size: 11.5),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionGrid(double width) {
    final options = _current.displayOptions;
    final twoUp = width >= 520 && options.length > 2;

    final tiles = <Widget>[
      for (final o in options) _hexFor(o),
    ];

    if (!twoUp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: BxSpace.sm),
            tiles[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: BxSpace.sm));
      // IntrinsicHeight so a pair of hexagons match each other even when
      // one answer runs to two lines — the row is inside a scroll view,
      // where a bare stretch would have no height to stretch to.
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: BxSpace.sm),
            Expanded(
              child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _hexFor(QuestionOption o) {
    final c = context.bx;
    final key = (_current.correctKey ?? '').toUpperCase();
    final gone = _eliminated.contains(o.key);
    final isPicked = _picked == o.key;
    final revealing = _step == _Step.revealing;
    final isRight = revealing && key.isNotEmpty && o.key == key;
    final isWrong = revealing && isPicked && !isRight;

    // Gold, green and amber are light surfaces, so their label ink comes
    // from the light palette — still a token, never a literal hex.
    const onBright = BxColors.light;

    Color fill = c.surfaceSunken;
    Color stroke = c.gold.withValues(alpha: 0.55);
    Color ink = c.ink;
    Color letter = c.goldBright;

    if (isRight) {
      fill = c.success;
      stroke = c.success;
      ink = onBright.ink;
      letter = onBright.ink;
    } else if (isWrong) {
      fill = c.danger;
      stroke = c.danger;
      ink = onBright.ink;
      letter = onBright.ink;
    } else if (isPicked) {
      fill = c.goldBright;
      stroke = c.goldBright;
      ink = onBright.ink;
      letter = onBright.ink;
    }

    _Hexagon hex({double glow = 0, VoidCallback? onTap}) => _Hexagon(
          letter: o.key,
          label: _plain(o.text),
          imageUrl: o.imageUrl,
          fill: fill,
          stroke: stroke,
          ink: ink,
          letterColor: letter,
          glow: glow,
          dim: gone,
          onTap: onTap,
        );

    // The heartbeat: only the locked-in hexagon pulses, and only while
    // the answer is being held back.
    if (isPicked && _step == _Step.locked) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Transform.scale(
          scale: 1 + 0.022 * _pulse.value,
          child: hex(glow: 0.35 + 0.65 * _pulse.value),
        ),
      );
    }

    return hex(
      glow: isRight ? 0.6 : 0,
      onTap: gone || _step != _Step.asking ? null : () => _lockIn(o.key),
    );
  }

  Widget _controls() {
    final c = context.bx;
    final banked = _index == 0 ? 0 : _ladder[_index - 1];

    return Container(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.sm, BxSpace.md, BxSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _lifeline(
                text: '50:50',
                label: 'Halve it',
                enabled: _canFifty,
                spent: _used5050,
                onTap: _fiftyFifty,
              ),
              const SizedBox(width: BxSpace.xs),
              _lifeline(
                icon: Icons.groups_rounded,
                label: 'Ask the class',
                enabled: !_usedPoll && _step == _Step.asking,
                spent: _usedPoll,
                busy: _pollLoading,
                onTap: _askTheClass,
              ),
              const SizedBox(width: BxSpace.xs),
              _lifeline(
                icon: Icons.swap_horiz_rounded,
                label: _hasSpare ? 'Switch it' : 'No spare',
                enabled: !_usedSwitch && _step == _Step.asking && _hasSpare,
                spent: _usedSwitch,
                onTap: _switchQuestion,
              ),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  banked == 0
                      ? 'Nothing banked yet.'
                      : 'Banked so far · ${_money(banked)}',
                  style: BxType.tiny(c.muted),
                ),
              ),
              BxButton.secondary(
                'Walk away',
                icon: Icons.logout_rounded,
                onPressed: _step == _Step.asking ? _walkAway : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lifeline({
    IconData? icon,
    String? text,
    required String label,
    required bool enabled,
    required bool spent,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    final c = context.bx;
    final live = enabled && !busy;
    final fg = live ? c.goldBright : c.muted;

    return Opacity(
      opacity: live ? 1 : 0.42,
      child: BxScaleTap(
        onTap: live ? onTap : null,
        scale: 0.92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: live ? c.surfaceSunken : c.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(
                  color: live ? c.gold.withValues(alpha: 0.6) : c.line,
                  width: 1.4,
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  : (text != null
                      ? Text(text, style: BxType.mono(fg, size: 13, weight: 600))
                      : Icon(icon, size: 22, color: fg)),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 78,
              child: Text(
                spent && !busy ? 'Used' : label,
                style: BxType.tiny(c.muted),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- game over

  Widget _over() {
    final c = context.bx;
    final ending = _ending ?? _Ending.walked;

    final (IconData icon, String headline, String line, BxAccent accent) =
        switch (ending) {
      _Ending.won => (
          Icons.workspace_premium_rounded,
          'Crowned.',
          'Fifteen from fifteen. You cleared the whole board and the '
              'crown is yours.',
          BxAccent.gold,
        ),
      _Ending.fell => (
          Icons.trending_down_rounded,
          'That one got you.',
          'You fell back to your safe haven. The questions that beat you '
              'are exactly the ones worth revising tonight.',
          BxAccent.danger,
        ),
      _Ending.timedOut => (
          Icons.timer_off_outlined,
          'The clock beat you.',
          'Time ran out on that rung, so you drop to your safe haven. '
              'Speed is a skill — it comes with the practice.',
          BxAccent.warning,
        ),
      _Ending.walked => (
          Icons.handshake_outlined,
          'You took the money.',
          'Nothing wrong with walking off the stage with money in hand. '
              'The board will still be here tomorrow.',
          BxAccent.success,
        ),
    };

    return BxPage(
      key: const ValueKey('over'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: BxSpace.lg),
          BxFadeIn(
            child: BxCard(
              fill: c.surfaceSunken,
              border: c.gold.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(
                  horizontal: BxSpace.lg, vertical: BxSpace.xxl),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.fill(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.stroke(c)),
                    ),
                    child: Icon(icon, size: 31, color: accent.ink(c)),
                  ),
                  const SizedBox(height: BxSpace.md),
                  Text(headline,
                      style: BxType.h2(c.ink), textAlign: TextAlign.center),
                  const SizedBox(height: BxSpace.lg),
                  FittedBox(
                    child: BxCountUp(
                      _amount,
                      prefix: '₦',
                      style: BxType.hero(c.gold),
                    ),
                  ),
                  const SizedBox(height: BxSpace.xs),
                  Text(
                    'bragging money · recorded in the Hall of Winners',
                    style: BxType.tiny(c.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: BxSpace.md),
                  Text(line,
                      style: BxType.body(c.inkSoft),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: BxSpace.md),
          BxCard(
            fill: c.surface,
            border: c.line,
            child: Column(
              children: [
                BxKeyValue('Reached', 'Question ${_index + 1} of 15'),
                BxKeyValue('Safe haven', _money(_guaranteed())),
                if (_rightAnswer != null)
                  BxKeyValue('The answer was', _rightAnswer!),
              ],
            ),
          ),
          const SizedBox(height: BxSpace.lg),
          BxButton(
            'Play again',
            large: true,
            expand: true,
            icon: Icons.replay_rounded,
            onPressed: _playAgain,
          ),
          const SizedBox(height: BxSpace.sm),
          BxButton.secondary(
            'Hall of Winners',
            large: true,
            expand: true,
            icon: Icons.emoji_events_outlined,
            onPressed: () => context.push(Routes.league),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// THE HEXAGON
// ============================================================

/// The classic angled hexagon: flat top and bottom, [_hexChamfer] of cut
/// on each side before the point. Inset a little so the glow drawn on
/// the picked answer has room to bloom inside the widget's box.
Path _hexPath(Size size, {double inset = 4}) {
  final r = Rect.fromLTWH(
    inset,
    inset,
    math.max(size.width - inset * 2, 1),
    math.max(size.height - inset * 2, 1),
  );
  final cut = math.min(_hexChamfer, r.width / 2);
  return Path()
    ..moveTo(r.left + cut, r.top)
    ..lineTo(r.right - cut, r.top)
    ..lineTo(r.right, r.center.dy)
    ..lineTo(r.right - cut, r.bottom)
    ..lineTo(r.left + cut, r.bottom)
    ..lineTo(r.left, r.center.dy)
    ..close();
}

class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) => _hexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Draws the gold edge, and the glow when an answer is locked in.
class _HexEdge extends CustomPainter {
  const _HexEdge({required this.color, this.glow = 0});

  final Color color;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hexPath(size);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.55 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 5 * glow),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HexEdge old) =>
      old.color != color || old.glow != glow;
}

class _Hexagon extends StatelessWidget {
  const _Hexagon({
    required this.letter,
    required this.label,
    required this.fill,
    required this.stroke,
    required this.ink,
    required this.letterColor,
    this.imageUrl,
    this.glow = 0,
    this.dim = false,
    this.onTap,
  });

  final String letter;
  final String label;
  final String? imageUrl;
  final Color fill;
  final Color stroke;
  final Color ink;
  final Color letterColor;
  final double glow;
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = (imageUrl ?? '').isNotEmpty;

    return Opacity(
      opacity: dim ? 0.22 : 1,
      child: BxScaleTap(
        onTap: onTap,
        scale: 0.97,
        child: CustomPaint(
          foregroundPainter: _HexEdge(color: stroke, glow: glow),
          child: ClipPath(
            clipper: const _HexClipper(),
            child: AnimatedContainer(
              duration: BxDuration.base,
              curve: BxCurves.smooth,
              constraints: const BoxConstraints(minHeight: 66),
              color: fill,
              padding: const EdgeInsets.symmetric(
                  horizontal: _hexChamfer + BxSpace.xs, vertical: BxSpace.sm),
              child: Row(
                children: [
                  Text(letter,
                      style: BxType.mono(letterColor, size: 15, weight: 600)),
                  const SizedBox(width: BxSpace.sm),
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BxRadius.xs),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl!,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const BxSkeleton(width: 38, height: 38),
                        errorWidget: (_, __, ___) =>
                            Icon(Icons.image_not_supported_outlined,
                                size: 18, color: ink),
                      ),
                    ),
                    if (label.isNotEmpty) const SizedBox(width: BxSpace.xs),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: BxType.bodyStrong(ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

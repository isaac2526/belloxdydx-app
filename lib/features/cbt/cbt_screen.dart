import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';
import 'calculator.dart';

/// ============================================================
/// CBT — THE SITTING
///
/// A real exam hall on a phone. Nothing is revealed while the clock
/// runs: no correctness, no explanation, no score. Every answer is kept
/// locally the instant it is tapped, so a shaky hostel network can never
/// take work away from a student, and pushed to the server behind the
/// scenes.
///
/// The timer belongs to the server. The device clock is only ever used
/// through the skew the server sent back, and it is cross-checked
/// against a monotonic stopwatch — so changing the phone's time buys
/// exactly nothing.
/// ============================================================

class CbtScreen extends ConsumerStatefulWidget {
  final String attemptId;
  const CbtScreen({super.key, required this.attemptId});

  @override
  ConsumerState<CbtScreen> createState() => _CbtScreenState();
}

class _CbtScreenState extends ConsumerState<CbtScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AttemptSession? _session;
  List<Question> _questions = const [];
  final Map<String, GivenAnswer> _answers = {};
  final Map<String, TextEditingController> _typed = {};

  /// Answers whose write did not land. They are safe on the phone and go
  /// up with the next successful save, or at the latest before submit.
  final Set<String> _unsaved = {};
  bool _flushing = false;

  int _index = 0;
  bool _loading = true;
  Object? _error;

  bool _started = false;
  bool _submitting = false;
  bool _autoSubmitted = false;
  bool _away = false; // already counted this trip out of the app
  int _violations = 0;

  Timer? _ticker;
  final Stopwatch _elapsed = Stopwatch();
  Duration _granted = Duration.zero;
  Duration _skew = Duration.zero;
  DateTime? _deadline;
  int _secondsLeft = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _pulse.dispose();
    for (final c in _typed.values) {
      c.dispose();
    }
    // The immersive lock belongs to the sitting, not to the app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------- loading

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session =
          await ref.read(assessmentRepoProvider).openAttempt(widget.attemptId);
      if (!mounted) return;

      if (session.isSubmitted) {
        context.pushReplacement(Routes.result(widget.attemptId));
        return;
      }

      final questions = List<Question>.of(session.questions);
      var start = questions
          .indexWhere((q) => !(session.answers[q.id]?.isAnswered ?? false));
      if (start < 0) start = questions.isEmpty ? 0 : questions.length - 1;

      for (final c in _typed.values) {
        c.dispose();
      }

      setState(() {
        _session = session;
        _questions = questions;
        _answers
          ..clear()
          ..addAll(session.answers);
        _typed.clear();
        _unsaved.clear();
        _violations = session.violations;
        _index = start;
        _loading = false;
        // Only an exam needs the hall rules; a class test starts running.
        _started = session.mode != AttemptMode.exam;
      });

      _applyDeadline(session.endsAt, session.serverNow);
      if (_started) _startClock();
    } catch (e) {
      if (!mounted) return;
      if (e is BxError && e.code == 'submitted') {
        context.pushReplacement(Routes.result(widget.attemptId));
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  // ---------------------------------------------------------- the clock

  /// The deadline arrives as server time. [AttemptSession.clockSkew] tells
  /// us how far the device clock sits from it, and the stopwatch gives a
  /// second, monotonic reading. Whichever says less time is the one used.
  void _applyDeadline(DateTime? endsAt, DateTime? serverNow) {
    if (endsAt == null) return;
    if (serverNow != null) _skew = serverNow.difference(DateTime.now());
    _deadline = endsAt;
    final left = endsAt.difference(DateTime.now().add(_skew));
    _granted = left.isNegative ? Duration.zero : left;
    _elapsed
      ..reset()
      ..start();
    if (mounted) setState(() => _secondsLeft = _granted.inSeconds);
  }

  int _remainingSeconds() {
    final deadline = _deadline;
    if (deadline == null) return -1; // untimed
    final byStopwatch = _granted - _elapsed.elapsed;
    final byClock = deadline.difference(DateTime.now().add(_skew));
    final left = byStopwatch < byClock ? byStopwatch : byClock;
    return left.isNegative ? 0 : left.inSeconds;
  }

  void _startClock() {
    _ticker?.cancel();
    if (_deadline == null) return;
    if (!_elapsed.isRunning) _elapsed.start();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final left = _remainingSeconds();
    if (left != _secondsLeft) setState(() => _secondsLeft = left);

    final urgent = left > 0 && left <= 60;
    if (urgent && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!urgent && _pulse.isAnimating) {
      _pulse.stop();
    }

    if (left == 0) {
      _ticker?.cancel();
      _autoSubmit();
    }
  }

  Future<void> _autoSubmit() async {
    if (_autoSubmitted) return;
    _autoSubmitted = true; // exactly once
    await _submit(auto: true);
  }

  // ---------------------------------------------------------- the hall

  void _begin() {
    // Stronger than the browser's requestFullscreen, which a student can
    // drop with one Escape key or a tab switch: immersiveSticky is held
    // by the operating system. A swipe only peeks at the system bars and
    // they slide straight back.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    HapticFeedback.mediumImpact();
    setState(() => _started = true);
    _startClock();
  }

  /// Lifecycle is the honest signal here. The website has to trust
  /// `visibilitychange`, which a student can suppress; the OS tells this
  /// app every single time the sitting leaves the screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = _session;
    if (session == null || session.mode != AttemptMode.exam) return;
    if (!_started || _submitting || _autoSubmitted) return;

    if (state == AppLifecycleState.resumed) {
      _away = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _tick(); // the clock kept running while they were away
      return;
    }

    final left = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;
    // paused usually follows inactive; one trip out is one violation.
    if (!left || _away) return;
    _away = true;
    ref.read(assessmentRepoProvider).reportViolation(widget.attemptId, 'left_app');
    if (mounted) setState(() => _violations++);
  }

  // ---------------------------------------------------------- counters

  int get _total => _questions.length;

  int get _answeredCount =>
      _questions.where((q) => _answers[q.id]?.isAnswered ?? false).length;

  // ---------------------------------------------------------- answering

  bool _ensureActivated() {
    if (ref.read(profileProvider).isActivated) return true;
    unawaited(showActivationGate(context, () => context.push(Routes.activate)));
    return false;
  }

  void _choose(Question q, String key) {
    if ((_answers[q.id]?.choice ?? '') == key) return;
    if (!_ensureActivated()) return;
    HapticFeedback.selectionClick();
    // Local first: the screen answers instantly and the answer is kept
    // even if the network is having a bad day.
    setState(() => _answers[q.id] = GivenAnswer(choice: key));
    unawaited(_save(q.id, choice: key));
  }

  void _saveTyped(Question q, String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (!_ensureActivated()) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _answers[q.id] = GivenAnswer(answerText: text));
    unawaited(_save(q.id, text: text));
  }

  Future<void> _save(String questionId, {String choice = '', String text = ''}) async {
    try {
      final verdict = await ref.read(assessmentRepoProvider).answerCbt(
            widget.attemptId,
            questionId,
            choice: choice,
            answerText: text,
          );
      if (!mounted) return;
      _unsaved.remove(questionId);

      // Tutor Bello can extend a live test while it runs; the answer
      // response is how that reaches every student mid sitting.
      if (verdict.endsAt != null) {
        _applyDeadline(verdict.endsAt, verdict.serverNow);
        if (_started) _startClock();
      }
      if (verdict.timeUp) {
        await _autoSubmit();
        return;
      }
      if (_unsaved.isNotEmpty) {
        unawaited(_flush());
      } else {
        setState(() {});
      }
    } catch (_) {
      // Swallowed on purpose. The answer already lives in local state, so
      // nothing is lost; the next successful write carries it up.
      if (!mounted) return;
      setState(() => _unsaved.add(questionId));
    }
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    for (final id in _unsaved.toList()) {
      final given = _answers[id];
      if (given == null) {
        _unsaved.remove(id);
        continue;
      }
      try {
        await ref.read(assessmentRepoProvider).answerCbt(
              widget.attemptId,
              id,
              choice: given.choice,
              answerText: given.answerText ?? '',
            );
        _unsaved.remove(id);
      } catch (_) {
        break; // still offline — keep the rest for the next chance
      }
      if (!mounted) break;
    }
    _flushing = false;
    if (mounted) setState(() {});
  }

  void _goTo(int i) {
    if (i < 0 || i >= _total || i == _index) return;
    FocusScope.of(context).unfocus();
    setState(() => _index = i);
  }

  // ---------------------------------------------------------- leaving

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;
    final answered = _answeredCount;
    final total = _total;

    if (!auto) {
      final ok = await bxConfirm(
        context,
        title: 'Submit now?',
        message: 'You answered $answered of $total questions.'
            '${answered < total ? ' Unanswered questions score zero.' : ''}',
        confirmLabel: 'Submit',
        cancelLabel: 'Keep working',
      );
      if (!ok) return;
      if (!mounted) return;
    }

    setState(() => _submitting = true);
    _ticker?.cancel();
    if (_pulse.isAnimating) _pulse.stop();
    if (_unsaved.isNotEmpty) await _flush();
    if (!mounted) return;

    try {
      await ref.read(assessmentRepoProvider).submit(widget.attemptId);
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(weakSpotsProvider);
      ref.invalidate(mistakesProvider);
      ref.invalidate(leaderboardProvider);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (auto) {
        bxToast(context, 'Time finished. Your work went in on its own.');
      }
      context.pushReplacement(Routes.result(widget.attemptId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (auto) {
        // Time is up but the network refused. Keep trying rather than
        // leaving the student staring at a dead screen.
        _autoSubmitted = false;
        bxToast(context, 'Time is up. Sending your work — hold on.', error: true);
        Future<void>.delayed(const Duration(seconds: 5), () {
          if (mounted) unawaited(_autoSubmit());
        });
      } else {
        bxToast(context, _friendly(e), error: true);
        _startClock();
      }
    }
  }

  Future<void> _confirmLeave() async {
    if (_submitting) return;
    final exam = _session?.mode == AttemptMode.exam;
    final ok = await bxConfirm(
      context,
      title: exam ? 'Leave this exam?' : 'Leave this test?',
      message: 'Your answers are saved, but the clock keeps running on the '
          'server. You can come back from the resume card on your dashboard.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (!ok) return;
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave();
      },
      child: Scaffold(
        appBar: _bar(),
        body: BxSwitcher(child: _body()),
      ),
    );
  }

  PreferredSizeWidget _bar() {
    final c = context.bx;
    final session = _session;
    final exam = session?.mode == AttemptMode.exam;
    final gated = exam && !_started;
    final ready = !_loading && _error == null && _total > 0 && !gated;

    final title = (session == null || session.title.isEmpty)
        ? (session != null && session.courseCode.isNotEmpty
            ? session.courseCode
            : 'Test')
        : session.title;

    final String subtitle;
    if (_loading) {
      subtitle = 'Opening your sitting…';
    } else if (gated) {
      subtitle = 'Read this before you begin';
    } else {
      subtitle =
          '${exam ? 'Exam' : 'Test'} mode · $_answeredCount/$_total answered';
    }

    return BxAppBar(
      title: title,
      subtitle: subtitle,
      // No casual way out of a running exam: leaving is Submit.
      showBack: !(exam && _started),
      actions: ready
          ? [
              if (_violations > 0)
                Center(
                  child: BxChip(
                    '$_violations',
                    accent: BxAccent.danger,
                    icon: Icons.gpp_maybe_rounded,
                    dense: true,
                  ),
                ),
              if (_deadline != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: BxSpace.xs),
                  child: Center(child: _clock(c)),
                ),
              IconButton(
                tooltip: 'Calculator',
                onPressed: () => showBxCalculator(context),
                icon: const Icon(Icons.calculate_outlined, size: 21),
                visualDensity: VisualDensity.compact,
              ),
              Center(
                child: BxButton(
                  'Submit',
                  loading: _submitting,
                  loadingLabel: 'Sending…',
                  onPressed: _submitting ? null : () => _submit(),
                ),
              ),
            ]
          : const [],
    );
  }

  Widget _clock(BxColors c) {
    final urgent = _secondsLeft <= 60;
    final text = Text(
      _clockLabel(_secondsLeft),
      style: BxType.clock(urgent ? c.danger : c.ink),
    );
    if (!urgent || reduceMotion(context)) return text;
    return AnimatedBuilder(
      animation: _pulse,
      child: text,
      builder: (_, child) => Opacity(opacity: 1 - 0.5 * _pulse.value, child: child),
    );
  }

  String _clockLabel(int seconds) {
    if (seconds < 0) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: BxThinking(message: 'Opening your sitting…'),
      );
    }

    if (_error != null) {
      return BxPage(
        key: const ValueKey('error'),
        child: BxErrorState(
          title: 'This sitting would not open',
          message: _friendly(_error!),
          onRetry: _load,
        ),
      );
    }

    if (_questions.isEmpty) {
      return BxPage(
        key: const ValueKey('empty'),
        child: BxEmptyState(
          icon: Icons.assignment_outlined,
          title: 'No questions in this paper',
          message: 'This one came through empty, so there is nothing to sit. '
              'Tell Tutor Bello and pick another test from your course page.',
          actionLabel: 'Back to courses',
          onAction: () => context.go(Routes.courses),
        ),
      );
    }

    final session = _session!;
    if (session.mode == AttemptMode.exam && !_started) return _gate();
    return _runner();
  }

  // ---------------------------------------------------------- exam gate

  Widget _gate() {
    final c = context.bx;
    final minutes = _granted.inMinutes;

    const rules = <(IconData, String)>[
      (
        Icons.lock_rounded,
        'The screen is locked to the app, exactly like the real CBT hall.'
      ),
      (
        Icons.exit_to_app_rounded,
        'Leaving the app or switching away is recorded as a violation.'
      ),
      (Icons.content_copy_rounded, 'Copy and paste are blocked.'),
      (
        Icons.schedule_rounded,
        'The timer lives on the server. Closing the app does not pause it.'
      ),
      (
        Icons.send_rounded,
        'When time finishes, your work submits itself.'
      ),
    ];

    return BxPage(
      key: const ValueKey('gate'),
      child: BxStagger(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BxEyebrow('Exam conditions'),
              const SizedBox(height: BxSpace.xxs),
              Text('Before you begin', style: BxType.h1(c.ink)),
              const SizedBox(height: BxSpace.xxs),
              Text(
                'Sit this one the way you will sit the real thing. '
                '$_total ${_total == 1 ? 'question' : 'questions'}'
                '${minutes > 0 ? ', $minutes ${minutes == 1 ? 'minute' : 'minutes'}' : ''}.',
                style: BxType.body(c.muted),
              ),
            ],
          ),
          BxCard(
            raised: true,
            padding: const EdgeInsets.all(BxSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rules.length; i++) ...[
                  if (i > 0) const SizedBox(height: BxSpace.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.goldTint,
                          borderRadius: BorderRadius.circular(BxRadius.xs),
                          border: Border.all(
                              color: c.gold.withValues(alpha: 0.42)),
                        ),
                        child: Icon(rules[i].$1, size: 16, color: c.goldDeep),
                      ),
                      const SizedBox(width: BxSpace.sm),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child:
                              Text(rules[i].$2, style: BxType.body(c.inkSoft)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          BxBanner(
            title: 'One sitting, one shot',
            message: 'Find a quiet corner and put the phone on silent. '
                'Once you begin, the clock does not wait for anybody.',
            icon: Icons.self_improvement_rounded,
          ),
          BxButton(
            'I understand, begin',
            icon: Icons.play_arrow_rounded,
            large: true,
            expand: true,
            onPressed: _begin,
          ),
          Center(
            child: BxButton.ghost(
              'Not now, take me back',
              onPressed: _confirmLeave,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- runner

  Widget _runner() {
    final c = context.bx;
    final wide = context.isWide;
    final activated = ref.watch(profileProvider).isActivated;

    final main = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.xs),
          child: Row(
            children: [
              Expanded(
                  child: BxProgressBar(_total == 0 ? 0 : _answeredCount / _total)),
              const SizedBox(width: BxSpace.sm),
              Text('Q${_index + 1} · $_answeredCount/$_total',
                  style: BxType.mono(c.muted, size: 11.5)),
            ],
          ),
        ),
        if (!activated)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(BxSpace.md, 0, BxSpace.md, BxSpace.xs),
            child: BxBanner(
              title: 'Preview mode',
              message: 'Activate to answer and keep your score.',
              icon: Icons.lock_outline_rounded,
              actionLabel: 'Activate',
              onAction: () => context.push(Routes.activate),
            ),
          ),
        if (_unsaved.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(BxSpace.md, 0, BxSpace.md, BxSpace.xs),
            child: BxBanner(
              title: '${_unsaved.length} answer'
                  '${_unsaved.length == 1 ? '' : 's'} still going up',
              message: 'They are safe on your phone and will go up on the next '
                  'save. Keep working.',
              icon: Icons.cloud_upload_outlined,
              accent: BxAccent.warning,
            ),
          ),
        Expanded(
          child: BxSwitcher(child: _questionPage(_questions[_index], _index)),
        ),
      ],
    );

    if (wide) {
      // Room for the real thing: the navigator lives beside the paper
      // instead of hiding behind a button.
      return Row(
        key: const ValueKey('runner-wide'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: main),
          VerticalDivider(width: 1, color: c.line),
          SizedBox(width: 272, child: _navigatorPanel()),
        ],
      );
    }

    return Stack(
      key: const ValueKey('runner'),
      children: [
        main,
        Positioned(
          left: BxSpace.md,
          bottom: BxSpace.md,
          child: SafeArea(child: _mapButton()),
        ),
      ],
    );
  }

  Widget _mapButton() {
    final c = context.bx;
    return BxCard(
      accent: BxAccent.gold,
      raised: true,
      radius: BxRadius.pill,
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.xs + 2),
      onTap: _openMap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_view_rounded, size: 17, color: c.goldDeep),
          const SizedBox(width: BxSpace.xs),
          Text('Map', style: BxType.smallStrong(c.goldDeep)),
        ],
      ),
    );
  }

  Future<void> _openMap() async {
    final c = context.bx;
    HapticFeedback.selectionClick();
    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.sheet),
      builder: (sheet) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                BxSpace.lg, BxSpace.md, BxSpace.lg, BxSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BxEyebrow('Question map'),
                const SizedBox(height: BxSpace.xxs),
                Text('Jump anywhere', style: BxType.h2(c.ink)),
                const SizedBox(height: BxSpace.xxs),
                Text('$_answeredCount of $_total answered.',
                    style: BxType.small(c.muted)),
                const SizedBox(height: BxSpace.md),
                _grid((i) => Navigator.of(sheet).pop(i)),
                const SizedBox(height: BxSpace.md),
                _legend(),
              ],
            ),
          ),
        ),
      ),
    );
    if (target != null) _goTo(target);
  }

  Widget _navigatorPanel() {
    final c = context.bx;
    return Container(
      color: c.ground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BxSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxEyebrow('Question map'),
            const SizedBox(height: BxSpace.xs),
            _grid(_goTo),
            const SizedBox(height: BxSpace.md),
            _legend(),
          ],
        ),
      ),
    );
  }

  Widget _grid(ValueChanged<int> onTap) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _total,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: BxSpace.xs,
        crossAxisSpacing: BxSpace.xs,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (_, i) => _cell(i, () => onTap(i)),
    );
  }

  Widget _cell(int i, VoidCallback onTap) {
    final c = context.bx;
    final answered = _answers[_questions[i].id]?.isAnswered ?? false;
    final current = i == _index;
    return BxScaleTap(
      onTap: onTap,
      scale: 0.92,
      borderRadius: BorderRadius.circular(BxRadius.xs),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: answered ? c.infoTint : c.surface,
          borderRadius: BorderRadius.circular(BxRadius.xs),
          border: Border.all(
            color: current
                ? c.gold
                : (answered ? c.info.withValues(alpha: 0.34) : c.line),
            width: current ? 2 : 1,
          ),
        ),
        child: Text(
          '${i + 1}',
          style: BxType.mono(answered ? c.info : c.inkSoft,
              size: 12.5, weight: 600),
        ),
      ),
    );
  }

  Widget _legend() {
    final c = context.bx;
    Widget item(Color fill, Color border, double width, String label) => Padding(
          padding: const EdgeInsets.only(bottom: BxSpace.xs),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(BxRadius.xs),
                  border: Border.all(color: border, width: width),
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              Expanded(child: Text(label, style: BxType.tiny(c.muted))),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(c.infoTint, c.info.withValues(alpha: 0.34), 1, 'Answered'),
        item(c.surface, c.gold, 2, 'Where you are now'),
        item(c.surface, c.line, 1, 'Not touched yet'),
      ],
    );
  }

  // ---------------------------------------------------------- one question

  Widget _questionPage(Question q, int i) {
    final c = context.bx;
    final given = _answers[q.id];
    final isLast = i == _total - 1;

    return BxPage(
      key: ValueKey(q.id),
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.huge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxCard(
            raised: true,
            padding: const EdgeInsets.all(BxSpace.md),
            // Copy and paste are blocked in the hall, so they are blocked
            // here: nothing in the paper can be selected or lifted out.
            child: SelectionContainer.disabled(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: BxEyebrow('Question ${i + 1} of $_total')),
                      BxChip(
                        '${q.marks} ${q.marks == 1 ? 'mark' : 'marks'}',
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: BxSpace.sm),
                  if (q.questionHtml.trim().isEmpty)
                    Text(
                      'This question arrived without its text. Answer what you '
                      'can and tell Tutor Bello after the sitting.',
                      style: BxType.body(c.muted),
                    )
                  else
                    HtmlWidget(q.questionHtml,
                        textStyle: BxType.bodyLg(c.ink)),
                  if ((q.questionImageUrl ?? '').isNotEmpty) ...[
                    const SizedBox(height: BxSpace.md),
                    _image(q.questionImageUrl!),
                  ],
                  if ((q.questionAudioUrl ?? '').isNotEmpty) ...[
                    const SizedBox(height: BxSpace.md),
                    _AudioRow(
                        url: q.questionAudioUrl!,
                        label: 'Listen to this question'),
                  ],
                  const SizedBox(height: BxSpace.md),
                  if (q.type == QuestionType.shortAnswer)
                    _shortAnswer(q, given)
                  else
                    _options(q),
                ],
              ),
            ),
          ),
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              Expanded(
                child: BxButton.secondary(
                  'Previous',
                  icon: Icons.arrow_back_rounded,
                  expand: true,
                  onPressed: i == 0 ? null : () => _goTo(i - 1),
                ),
              ),
              const SizedBox(width: BxSpace.sm),
              Expanded(
                child: isLast
                    ? BxButton(
                        'Finish & submit',
                        icon: Icons.flag_rounded,
                        expand: true,
                        loading: _submitting,
                        loadingLabel: 'Sending…',
                        onPressed: _submitting ? null : () => _submit(),
                      )
                    : BxButton(
                        'Next',
                        icon: Icons.arrow_forward_rounded,
                        expand: true,
                        onPressed: () => _goTo(i + 1),
                      ),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Center(
            child: Text(
              'You can change any answer until you submit.',
              style: BxType.tiny(c.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options(Question q) {
    final options = q.displayOptions;
    if (options.isEmpty) {
      return Text(
        'This question has no options loaded. Move on and mention it to '
        'Tutor Bello after the sitting.',
        style: BxType.small(context.bx.muted),
      );
    }

    if (q.type == QuestionType.trueFalse) {
      return Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: BxSpace.sm),
            Expanded(child: _optionTile(q, options[i])),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: BxSpace.xs),
          _optionTile(q, options[i]),
        ],
      ],
    );
  }

  /// Nothing is revealed while the clock runs — the tile only ever says
  /// which one this student picked, and it stays tappable so the answer
  /// can be changed right up to submit.
  Widget _optionTile(Question q, QuestionOption o) {
    final c = context.bx;
    final key = o.key.toUpperCase();
    final picked = (_answers[q.id]?.choice ?? '').toUpperCase() == key;

    final fill = picked ? c.goldTint : c.surfaceSunken;
    final stroke = picked ? c.gold : c.line;
    final ink = picked ? c.goldDeep : c.ink;

    return BxScaleTap(
      onTap: () => _choose(q, o.key),
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: AnimatedContainer(
        duration: BxDuration.fast,
        curve: BxCurves.smooth,
        padding: const EdgeInsets.all(BxSpace.sm),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: stroke, width: picked ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(BxRadius.xs),
                border: Border.all(color: stroke),
              ),
              child: Text(key, style: BxType.mono(ink, size: 13, weight: 600)),
            ),
            const SizedBox(width: BxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (o.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: HtmlWidget(o.text, textStyle: BxType.body(ink)),
                    ),
                  if ((o.imageUrl ?? '').isNotEmpty) ...[
                    if (o.text.trim().isNotEmpty)
                      const SizedBox(height: BxSpace.xs),
                    _image(o.imageUrl!, maxHeight: 160),
                  ],
                ],
              ),
            ),
            if (picked) ...[
              const SizedBox(width: BxSpace.xs),
              Icon(Icons.check_circle_rounded, size: 19, color: c.goldDeep),
            ],
          ],
        ),
      ),
    );
  }

  Widget _shortAnswer(Question q, GivenAnswer? given) {
    final c = context.bx;
    final stored = (given?.answerText ?? '').trim();
    final controller = _typed.putIfAbsent(
      q.id,
      () => TextEditingController(text: stored),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxField(
          label: 'Your answer',
          controller: controller,
          hint: 'Type your answer',
          helper: 'Spelling matters, capital letters and spaces do not.',
          capitalization: TextCapitalization.sentences,
          onSubmitted: (v) => _saveTyped(q, v),
        ),
        const SizedBox(height: BxSpace.sm),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) {
            final text = value.text.trim();
            return Align(
              alignment: Alignment.centerLeft,
              child: BxButton(
                text == stored && stored.isNotEmpty ? 'Saved' : 'Save',
                icon: Icons.save_outlined,
                onPressed: text.isEmpty || (text == stored && stored.isNotEmpty)
                    ? null
                    : () => _saveTyped(q, text),
              ),
            );
          },
        ),
        if (stored.isNotEmpty) ...[
          const SizedBox(height: BxSpace.xs),
          Text('Saved: "$stored" — you can still change it.',
              style: BxType.tiny(c.success)),
        ],
      ],
    );
  }

  // ---------------------------------------------------------- media

  Widget _image(String url, {double maxHeight = 300}) {
    final c = context.bx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceSunken,
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
}

/// ============================================================
/// A compact audio row for listening questions. Audio is polish: if the
/// platform refuses the file the row says so quietly instead of taking
/// the question down with it.
/// ============================================================

class _AudioRow extends StatefulWidget {
  final String url;
  final String label;
  const _AudioRow({required this.url, required this.label});

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _sub;
  bool _playing = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy || _failed) return;
    setState(() => _busy = true);
    try {
      var player = _player;
      if (player == null) {
        final created = AudioPlayer();
        _player = created;
        player = created;
        _sub = created.playerStateStream.listen((state) {
          if (!mounted) return;
          final done = state.processingState == ProcessingState.completed;
          setState(() => _playing = state.playing && !done);
          if (done) {
            unawaited(created.pause());
            unawaited(created.seek(Duration.zero));
          }
        });
        await created.setUrl(widget.url);
      }
      if (player.playing) {
        await player.pause();
      } else {
        // play() only completes when the clip ends, so it is not awaited.
        unawaited(player.play());
      }
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxScaleTap(
      onTap: _failed ? null : _toggle,
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.sm, vertical: BxSpace.xs),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: _busy
                  ? CircularProgressIndicator(strokeWidth: 2, color: c.gold)
                  : Icon(
                      _failed
                          ? Icons.volume_off_rounded
                          : (_playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded),
                      size: 22,
                      color: _failed ? c.muted : c.goldDeep,
                    ),
            ),
            const SizedBox(width: BxSpace.xs),
            Expanded(
              child: Text(
                _failed ? 'This audio would not play here.' : widget.label,
                style: BxType.smallStrong(_failed ? c.muted : c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

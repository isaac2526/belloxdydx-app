import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../data/net_speed.dart';
import '../../data/offline/offline_store.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// PRACTICE — THE INSTANT-CORRECTION RUNNER
///
/// One question per page, swipeable. You commit once, the server grades
/// it, and the answer opens with Tutor Bello's explanation right there.
/// Nothing is hidden until the end, because the point of practice is to
/// learn on the spot — small daily reading beats midnight panic.
/// ============================================================

class PracticeScreen extends ConsumerStatefulWidget {
  final String attemptId;
  const PracticeScreen({super.key, required this.attemptId});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  AttemptSession? _session;
  List<Question> _questions = const [];
  final Map<String, GivenAnswer> _answers = {};
  final Set<String> _bookmarks = {};
  final Map<String, TextEditingController> _typed = {};

  PageController? _pages;
  int _index = 0;
  bool _loading = true;
  Object? _error;

  /// Set while one answer is in flight, so a double tap cannot commit twice.
  String? _busyId;
  String? _busyChoice;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages?.dispose();
    for (final c in _typed.values) {
      c.dispose();
    }
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

      // Resume where the student stopped, not at the top — and not one
      // PAST it either, which is what guessing "the first unanswered
      // question" did. Somebody who answers and then stops to read the
      // explanation is sitting on an ANSWERED question; the guess moved
      // them on and took the explanation away. startIndexFor() prefers
      // the position the server actually recorded and falls back to the
      // guess only when there is none.
      final questions = List<Question>.of(session.questions);
      final start = session.startIndexFor();

      final old = _pages;
      for (final c in _typed.values) {
        c.dispose();
      }

      setState(() {
        _session = session;
        _questions = questions;
        _answers
          ..clear()
          ..addAll(session.answers);
        _bookmarks
          ..clear()
          ..addAll(session.bookmarks);
        _typed.clear();
        _index = start;
        _pages = PageController(initialPage: start);
        _loading = false;
      });
      old?.dispose();
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

  // ---------------------------------------------------------- counters

  int get _total => _questions.length;

  int get _answeredCount =>
      _questions.where((q) => _answers[q.id]?.isAnswered ?? false).length;

  int get _correctCount =>
      _questions.where((q) => _answers[q.id]?.isCorrect == true).length;

  bool get _allAnswered => _total > 0 && _answeredCount == _total;

  // ---------------------------------------------------------- actions

  Future<void> _answer(Question q, {String choice = '', String text = ''}) async {
    if (_busyId != null) return;
    if (_answers[q.id]?.isAnswered ?? false) return;

    if (!ref.read(profileProvider).isActivated) {
      await showActivationGate(context, () => context.push(Routes.activate));
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _busyId = q.id;
      _busyChoice = choice;
    });

    try {
      final verdict = await ref.read(assessmentRepoProvider).answerPractice(
            widget.attemptId,
            q.id,
            choice: choice,
            answerText: text,
          );
      if (!mounted) return;

      final at = _questions.indexWhere((x) => x.id == q.id);
      setState(() {
        // The verdict carries the answer key and explanation the question
        // was not allowed to hold before the student committed.
        if (at >= 0) _questions[at] = _questions[at].mergeAnswer(verdict);
        _answers[q.id] = GivenAnswer(
          choice: choice,
          answerText: text.isEmpty ? null : text,
          // Null, not false, when the line dropped and the phone does
          // not hold the key. Marking it wrong because nobody could
          // check it is the one answer this screen must never give.
          isCorrect: verdict.graded ? verdict.correct : null,
        );
        _busyId = null;
        _busyChoice = null;
      });
      if (!verdict.graded) {
        bxToast(context,
            'Kept. Your line dropped, so this one is marked when you are '
            'back.');
      }
      if (verdict.graded && verdict.correct) HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _busyChoice = null;
      });
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _toggleBookmark(Question q) async {
    final wasSaved = _bookmarks.contains(q.id);
    HapticFeedback.selectionClick();
    setState(() => wasSaved ? _bookmarks.remove(q.id) : _bookmarks.add(q.id));
    try {
      final saved = await ref.read(assessmentRepoProvider).toggleBookmark(q.id);
      if (!mounted) return;
      setState(() => saved ? _bookmarks.add(q.id) : _bookmarks.remove(q.id));
      ref.invalidate(bookmarkCountProvider);
      bxToast(
        context,
        saved
            ? 'Saved. You will meet this one again in Saved questions.'
            : 'Removed from your saved questions.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => wasSaved ? _bookmarks.add(q.id) : _bookmarks.remove(q.id));
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _report(Question q) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bx.surface,
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.sheet),
      builder: (_) => const _ReportSheet(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    if (!mounted) return;
    try {
      await ref.read(assessmentRepoProvider).reportQuestion(q.id, reason.trim());
      if (!mounted) return;
      bxToast(context, 'Sent. Tutor Bello will look at this question.');
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  void _goTo(int i) {
    final pages = _pages;
    if (pages == null || i < 0 || i >= _total) return;
    FocusScope.of(context).unfocus();
    if (reduceMotion(context)) {
      pages.jumpToPage(i);
    } else {
      pages.animateToPage(i, duration: BxDuration.base, curve: BxCurves.smooth);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final ok = await bxConfirm(
      context,
      title: 'End this practice?',
      message: '$_answeredCount of $_total answered. '
          'Questions you skipped count as wrong.',
      confirmLabel: 'End and see result',
      cancelLabel: 'Keep going',
    );
    if (!ok) return;
    if (!mounted) return;

    setState(() => _finishing = true);
    try {
      await ref.read(assessmentRepoProvider).finishPractice(widget.attemptId);
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(weakSpotsProvider);
      ref.invalidate(mistakesProvider);
      ref.invalidate(bookmarkCountProvider);
      context.pushReplacement(Routes.result(widget.attemptId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await bxConfirm(
      context,
      title: 'Leave this practice?',
      message: 'Your answers are saved. You can pick this round back up '
          'from the resume card on your dashboard.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (!leave) return;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final session = _session;
    final ready = !_loading && _error == null && _total > 0;

    final title = (session == null || session.courseCode.isEmpty)
        ? 'Practice'
        : (session.courseTitle.isEmpty
            ? session.courseCode
            : '${session.courseCode} · ${session.courseTitle}');
    final subtitle =
        '${(session?.mode ?? AttemptMode.practice).label} · instant corrections';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave();
      },
      child: Scaffold(
        appBar: BxAppBar(
          title: title,
          subtitle: subtitle,
          actions: [
            if (ready) ...[
              Center(
                child: BxChip(
                  '$_correctCount/$_answeredCount correct',
                  accent: _correctCount == _answeredCount && _answeredCount > 0
                      ? BxAccent.success
                      : BxAccent.neutral,
                  icon: Icons.task_alt_rounded,
                  dense: true,
                ),
              ),
              TextButton(
                onPressed: _finish,
                child: Text('End', style: BxType.label(c.danger)),
              ),
            ],
          ],
        ),
        body: BxSwitcher(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: BxThinking(message: 'Opening your practice…'),
      );
    }

    if (_error != null) {
      return BxPage(
        key: const ValueKey('error'),
        child: BxErrorState(
          title: 'This round would not open',
          message: _friendly(_error!),
          onRetry: _load,
        ),
      );
    }

    if (_questions.isEmpty) {
      return BxPage(
        key: const ValueKey('empty'),
        child: BxEmptyState(
          icon: Icons.quiz_outlined,
          title: 'No questions in this round',
          message: 'This one came through empty. Start a fresh round from '
              'your course page and you are back in business.',
          actionLabel: 'Pick a course',
          onAction: () => context.go(Routes.courses),
        ),
      );
    }

    final c = context.bx;
    final activated = ref.watch(profileProvider).isActivated;

    return Column(
      key: const ValueKey('content'),
      children: [
        // Progress sits directly under the bar so the finish line is
        // always in view.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.xs),
          child: Row(
            children: [
              Expanded(child: BxProgressBar(_answeredCount / _total)),
              const SizedBox(width: BxSpace.sm),
              Text('Q${_index + 1} · $_answeredCount/$_total',
                  style: BxType.mono(c.muted, size: 11.5)),
            ],
          ),
        ),
        if (!activated)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                BxSpace.md, 0, BxSpace.md, BxSpace.xs),
            child: BxBanner(
              title: 'Preview mode',
              message: 'Activate to answer and keep your score.',
              icon: Icons.lock_outline_rounded,
              actionLabel: 'Activate',
              onAction: () => context.push(Routes.activate),
            ),
          ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            // Swiping between questions is the native win the website
            // cannot offer.
            physics: const AlwaysScrollableScrollPhysics(),
            onPageChanged: (i) {
              FocusScope.of(context).unfocus();
              setState(() => _index = i);
              // Recorded so the round can be met again exactly here,
              // whether the app is killed, the phone dies, or the
              // student comes back on a different day.
              ref
                  .read(assessmentRepoProvider)
                  .reportPosition(widget.attemptId, i);
            },
            itemCount: _total,
            itemBuilder: (_, i) => _questionPage(_questions[i], i),
          ),
        ),
        if (_allAnswered) BxFadeIn(child: _summaryBar()),
      ],
    );
  }

  Widget _summaryBar() {
    final c = context.bx;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.sm, BxSpace.md, BxSpace.sm),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('All $_total answered. $_correctCount correct.',
                      style: BxType.bodyStrong(c.ink)),
                  Text('Finish to lock in your score.',
                      style: BxType.tiny(c.muted)),
                ],
              ),
            ),
            const SizedBox(width: BxSpace.sm),
            BxButton(
              'Finish',
              icon: Icons.flag_rounded,
              loading: _finishing,
              loadingLabel: 'Finishing…',
              onPressed: _finish,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- one question

  Widget _questionPage(Question q, int i) {
    final c = context.bx;
    final given = _answers[q.id];
    final answered = given?.isAnswered ?? false;
    final isLast = i == _total - 1;

    return BxPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxCard(
            raised: true,
            padding: const EdgeInsets.all(BxSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BxEyebrow(
                    'Question ${i + 1} of $_total · ${q.marks} ${q.marks == 1 ? 'mark' : 'marks'}'),
                const SizedBox(height: BxSpace.sm),
                if (q.questionHtml.trim().isEmpty)
                  Text(
                    'This question arrived without its text. Report it and '
                    'Tutor Bello will fix it.',
                    style: BxType.body(c.muted),
                  )
                else
                  BxHtml(q.questionHtml, textStyle: BxType.bodyLg(c.ink)),
                if ((q.questionImageUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: BxSpace.md),
                  _image(q.questionImageUrl!),
                ],
                if ((q.questionAudioUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: BxSpace.md),
                  BxAudio(
                      url: q.questionAudioUrl!, label: 'Listen to this question'),
                ],
                const SizedBox(height: BxSpace.md),
                if (q.type == QuestionType.shortAnswer)
                  _shortAnswer(q, answered)
                else
                  _options(q, answered),
              ],
            ),
          ),
          if (answered && given != null) ...[
            const SizedBox(height: BxSpace.md),
            BxFadeIn(child: _verdict(q, given)),
          ],
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
                        'See my result',
                        icon: Icons.flag_rounded,
                        expand: true,
                        loading: _finishing,
                        loadingLabel: 'Finishing…',
                        onPressed: _finish,
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
            child: Text('Swipe left or right to move between questions',
                style: BxType.tiny(c.muted)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- answering

  Widget _options(Question q, bool answered) {
    final options = q.displayOptions;
    if (options.isEmpty) {
      return Text(
        'This question has no options loaded yet. Report it so Tutor Bello '
        'can put it right.',
        style: BxType.small(context.bx.muted),
      );
    }

    if (q.type == QuestionType.trueFalse) {
      return Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: BxSpace.sm),
            Expanded(child: _optionTile(q, options[i], answered)),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: BxSpace.xs),
          _optionTile(q, options[i], answered),
        ],
      ],
    );
  }

  Widget _optionTile(Question q, QuestionOption o, bool answered) {
    final c = context.bx;
    final given = _answers[q.id];
    final key = o.key.toUpperCase();
    final picked = (given?.choice ?? '').toUpperCase();
    final correctKey = (q.correctKey ?? '').toUpperCase();

    // An answer nobody could mark yet — the line dropped and the phone
    // does not hold the key. The pick is SHOWN, so the student can see
    // what they chose, but it is not painted red: telling them they got
    // it wrong because nothing could check it is a lie in the one place
    // this app cannot afford one.
    final unmarked = answered && given?.isCorrect == null;

    final isCorrect =
        answered && !unmarked && correctKey.isNotEmpty && key == correctKey;
    final isPicked = answered && picked.isNotEmpty && key == picked;
    final isWrongPick = isPicked && !isCorrect && !unmarked;
    final faded = answered && !unmarked && !isCorrect && !isPicked;
    final waiting = _busyId == q.id && _busyChoice == o.key;

    final fill = isCorrect
        ? BxAccent.success.fill(c)
        : isWrongPick
            ? BxAccent.danger.fill(c)
            : (unmarked && isPicked ? BxAccent.info.fill(c) : c.surfaceSunken);
    final stroke = isCorrect
        ? c.success.withValues(alpha: 0.55)
        : isWrongPick
            ? c.danger.withValues(alpha: 0.55)
            : (unmarked && isPicked
                ? c.info.withValues(alpha: 0.55)
                : c.line);
    final ink = isCorrect
        ? c.success
        : isWrongPick
            ? c.danger
            : (unmarked && isPicked ? c.info : c.ink);

    return AnimatedOpacity(
      duration: BxDuration.base,
      curve: BxCurves.smooth,
      opacity: faded ? 0.55 : 1,
      child: BxScaleTap(
        onTap: answered ? null : () => _answer(q, choice: o.key),
        borderRadius: BorderRadius.circular(BxRadius.sm),
        child: AnimatedContainer(
          duration: BxDuration.base,
          curve: BxCurves.smooth,
          padding: const EdgeInsets.all(BxSpace.sm),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(BxRadius.sm),
            border: Border.all(
              color: stroke,
              width: isCorrect || isWrongPick || (unmarked && isPicked)
                  ? 1.5
                  : 1,
            ),
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
                        child:
                            BxHtml(o.text, textStyle: BxType.body(ink)),
                      ),
                    if ((o.imageUrl ?? '').isNotEmpty) ...[
                      if (o.text.trim().isNotEmpty)
                        const SizedBox(height: BxSpace.xs),
                      _image(o.imageUrl!, maxHeight: 160),
                    ],
                  ],
                ),
              ),
              if (waiting) ...[
                const SizedBox(width: BxSpace.xs),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.gold),
                  ),
                ),
              ] else if (isCorrect || isWrongPick) ...[
                const SizedBox(width: BxSpace.xs),
                Icon(
                  isCorrect ? Icons.check_rounded : Icons.close_rounded,
                  size: 19,
                  color: ink,
                ),
              ] else if (unmarked && isPicked) ...[
                // "This is what you chose", not "this is wrong".
                const SizedBox(width: BxSpace.xs),
                Icon(Icons.schedule_rounded, size: 19, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortAnswer(Question q, bool answered) {
    final c = context.bx;
    final given = _answers[q.id];
    final controller = _typed.putIfAbsent(
      q.id,
      () => TextEditingController(text: given?.answerText ?? ''),
    );
    final waiting = _busyId == q.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxField(
          label: 'Your answer',
          controller: controller,
          enabled: !answered,
          hint: 'Type your answer',
          helper: 'Spelling matters, capital letters and spaces do not.',
          capitalization: TextCapitalization.sentences,
          onSubmitted: answered
              ? null
              : (v) {
                  if (v.trim().isNotEmpty) _answer(q, text: v.trim());
                },
        ),
        const SizedBox(height: BxSpace.sm),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) => Align(
            alignment: Alignment.centerLeft,
            child: BxButton(
              answered ? 'Answered' : 'Check',
              icon: Icons.check_rounded,
              loading: waiting,
              loadingLabel: 'Checking…',
              onPressed: answered || value.text.trim().isEmpty
                  ? null
                  : () => _answer(q, text: value.text.trim()),
            ),
          ),
        ),
        if (answered && (given?.answerText ?? '').isNotEmpty) ...[
          const SizedBox(height: BxSpace.xs),
          Text('You typed: ${given!.answerText}', style: BxType.tiny(c.muted)),
        ],
      ],
    );
  }

  // ---------------------------------------------------------- verdict

  Widget _verdict(Question q, GivenAnswer given) {
    final c = context.bx;
    // An answer nobody could mark. It is kept, and it says so, rather
    // than being shown as wrong.
    if (given.isCorrect == null) {
      return BxCard(
        accent: BxAccent.info,
        padding: const EdgeInsets.all(BxSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, size: 20, color: c.info),
            const SizedBox(width: BxSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kept, not marked yet', style: BxType.h3(c.info)),
                  const SizedBox(height: BxSpace.xxs),
                  Text(
                    'Your line dropped before this one could be checked. '
                    'The answer is saved — keep going, and it is marked '
                    'the moment you are back. Download this course and '
                    'even that stops happening.',
                    style: BxType.small(c.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final ok = given.isCorrect == true;
    final accent = ok ? BxAccent.success : BxAccent.danger;
    final saved = _bookmarks.contains(q.id);

    final String headline;
    if (ok) {
      headline = 'Correct!';
    } else if (q.type == QuestionType.shortAnswer) {
      final accepted = q.acceptedAnswer;
      headline = accepted.isEmpty
          ? 'Not quite.'
          : 'Not quite. Accepted answer: $accepted';
    } else {
      final answerKey = (q.correctKey ?? '').toUpperCase();
      headline = answerKey.isEmpty
          ? 'Not this one.'
          : 'Not this one. Answer: $answerKey';
    }

    return BxCard(
      accent: accent,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 20,
                color: accent.ink(c),
              ),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                  child: Text(headline, style: BxType.h3(accent.ink(c)))),
            ],
          ),
          if (q.hasExplanation) ...[
            const SizedBox(height: BxSpace.sm),
            if ((q.explanationHtml ?? '').trim().isNotEmpty)
              BxHtml(q.explanationHtml!, textStyle: BxType.body(c.inkSoft)),
            if ((q.explanationImageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: BxSpace.sm),
              _image(q.explanationImageUrl!, maxHeight: 260),
            ],
            if ((q.explanationAudioUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: BxSpace.sm),
              BxAudio(
                  url: q.explanationAudioUrl!, label: 'Tutor Bello explains'),
            ],
          ] else ...[
            const SizedBox(height: BxSpace.xs),
            Text(
              ok
                  ? 'Clean work. Keep the pace.'
                  : 'No written explanation on this one yet. Save it and ask '
                      'Bello AI to break it down.',
              style: BxType.small(c.inkSoft),
            ),
          ],
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              BxChip(
                saved ? 'Saved' : 'Save this one',
                accent: saved ? BxAccent.gold : BxAccent.neutral,
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                onTap: () => _toggleBookmark(q),
              ),
              const SizedBox(width: BxSpace.xs),
              BxChip(
                'Report',
                icon: Icons.flag_outlined,
                onTap: () => _report(q),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- media

  /// What the box says when a picture cannot be drawn. With no line and
  /// no saved copy the honest sentence is the one the student can act
  /// on — "That image would not load" was read as a broken app.
  String _pictureExcuse(String url) {
    final offline = ref.read(netSpeedProvider).grade == BxNetGrade.offline;
    if (offline && !Offline.holds(url)) {
      return 'This picture is not on this phone yet. Tap Download on the '
          'course when you have data and it comes with the rest.';
    }
    return 'That image would not load.';
  }

  Widget _image(String url, {double maxHeight = 300}) {
    final c = context.bx;
    return BxScaleTap(
      onTap: () => _openImage(url),
      scale: 0.99,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BxRadius.sm),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(BxRadius.sm),
          ),
          child: BxImage(
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
                    child: Text(_pictureExcuse(url),
                        style: BxType.small(c.muted)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openImage(String url) {
    final c = context.bx;
    showDialog<void>(
      context: context,
      barrierColor: c.scrim,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(BxSpace.md),
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: BxRadius.card),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BxSpace.md, BxSpace.xs, BxSpace.xs, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Pinch to zoom', style: BxType.small(c.muted)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    BxSpace.sm, 0, BxSpace.sm, BxSpace.sm),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: BxImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const BxSkeleton(height: 260),
                    errorWidget: (_, __, ___) => Padding(
                      padding: const EdgeInsets.all(BxSpace.lg),
                      child: Text('That image would not load.',
                          style: BxType.small(c.muted)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// A compact audio row. Audio is polish: if the platform refuses the
/// file, the row says so quietly instead of breaking the question.
/// ============================================================


/// ============================================================
/// The report sheet. Pops with the reason; the screen sends it.
/// ============================================================

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BxSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BxEyebrow('Report a question'),
              const SizedBox(height: BxSpace.xxs),
              Text('What looks wrong?', style: BxType.h2(c.ink)),
              const SizedBox(height: BxSpace.xxs),
              Text(
                'A typo, a wrong answer key, a missing image — say it plainly '
                'and Tutor Bello will fix it.',
                style: BxType.small(c.muted),
              ),
              const SizedBox(height: BxSpace.md),
              BxField(
                label: 'Your reason',
                controller: _reason,
                maxLines: 4,
                autofocus: true,
                hint: 'The answer marked correct is not the right one…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: BxSpace.md),
              Row(
                children: [
                  Expanded(
                    child: BxButton.ghost(
                      'Cancel',
                      expand: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: BxSpace.sm),
                  Expanded(
                    child: BxButton(
                      'Send report',
                      icon: Icons.send_rounded,
                      expand: true,
                      onPressed: _reason.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(context, _reason.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

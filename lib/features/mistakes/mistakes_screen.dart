import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// MY MISTAKES — THE REDEMPTION DECK
///
/// Every question that has ever beaten this student, stacked into a
/// deck you swipe through one card at a time. You look at it, you try
/// to remember, then you turn the card. Nothing is scored here; the
/// scoring happens when you drill them properly at the end.
/// ============================================================

class MistakesScreen extends ConsumerStatefulWidget {
  const MistakesScreen({super.key});

  @override
  ConsumerState<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends ConsumerState<MistakesScreen> {
  // A hair under a full viewport so the next card peeks in — it reads as
  // a deck rather than a list of screens.
  final PageController _pages = PageController(viewportFraction: 0.94);

  final Set<String> _revealed = {};
  final Set<String> _saved = {};
  int _index = 0;
  bool _drilling = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  Future<void> _refresh() async {
    ref.invalidate(mistakesProvider);
    try {
      await ref.read(mistakesProvider.future);
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<bool> _gate() async {
    if (ref.read(profileProvider).isActivated) return true;
    await showActivationGate(context, () => context.push(Routes.activate));
    return false;
  }

  void _goTo(int i) {
    if (!_pages.hasClients) return;
    if (reduceMotion(context)) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i,
          duration: BxDuration.base, curve: BxCurves.smooth);
    }
  }

  Future<void> _reveal(Question q) async {
    if (_revealed.contains(q.id)) return;
    if (!await _gate()) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _revealed.add(q.id));
  }

  Future<void> _toggleBookmark(Question q) async {
    final wasSaved = _saved.contains(q.id);
    HapticFeedback.selectionClick();
    setState(() => wasSaved ? _saved.remove(q.id) : _saved.add(q.id));
    try {
      final saved = await ref.read(assessmentRepoProvider).toggleBookmark(q.id);
      if (!mounted) return;
      setState(() => saved ? _saved.add(q.id) : _saved.remove(q.id));
      ref.invalidate(bookmarkCountProvider);
      bxToast(
        context,
        saved
            ? 'Saved. It joins your saved questions in Revision.'
            : 'Removed from your saved questions.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => wasSaved ? _saved.add(q.id) : _saved.remove(q.id));
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

  Future<void> _drill() async {
    if (_drilling) return;
    if (!await _gate()) return;
    if (!mounted) return;

    setState(() => _drilling = true);
    try {
      final id = await ref.read(assessmentRepoProvider).startSmart();
      if (!mounted) return;
      setState(() => _drilling = false);
      context.push(Routes.practice(id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _drilling = false);
      bxToast(context, _friendly(e), error: true);
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mistakesProvider);

    return Scaffold(
      appBar: BxAppBar(
        title: 'My Mistakes',
        subtitle: 'Redemption',
        actions: [
          IconButton(
            tooltip: 'Refresh the deck',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
      body: BxSwitcher(
        child: async.when(
          loading: () => const Center(
            key: ValueKey('loading'),
            child: BxThinking(message: 'Pulling your deck together…'),
          ),
          error: (e, _) => BxPage(
            key: const ValueKey('error'),
            onRefresh: _refresh,
            child: BxErrorState(
              title: 'Your mistakes did not load',
              message: _friendly(e),
              onRetry: _refresh,
            ),
          ),
          data: (questions) => questions.isEmpty
              ? BxPage(
                  key: const ValueKey('empty'),
                  onRefresh: _refresh,
                  child: BxEmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'Nothing missed yet',
                    message: 'Every question you miss lands here so you can '
                        'beat it before the exam does.',
                    actionLabel: 'Start practicing',
                    onAction: () => context.go(Routes.courses),
                  ),
                )
              : _deck(questions),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- the deck

  Widget _deck(List<Question> questions) {
    final total = questions.length;

    return Column(
      key: ValueKey('deck-$total'),
      children: [
        _progress(total),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            physics: const AlwaysScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _index = i),
            // One extra page: the closing card at the bottom of the deck.
            itemCount: total + 1,
            itemBuilder: (_, i) => _lift(
              i,
              i == total
                  ? _closingCard(total)
                  : _card(questions[i], i, total),
            ),
          ),
        ),
      ],
    );
  }

  /// Cards behind the current one sit slightly back, so a swipe feels
  /// like dealing rather than paging.
  Widget _lift(int i, Widget child) {
    if (reduceMotion(context)) return child;
    return AnimatedBuilder(
      animation: _pages,
      child: child,
      builder: (_, built) {
        var page = _index.toDouble();
        if (_pages.hasClients && _pages.position.haveDimensions) {
          page = _pages.page ?? page;
        }
        final distance = (page - i).abs().clamp(0.0, 1.0);
        return Transform.scale(scale: 1 - distance * 0.05, child: built);
      },
    );
  }

  Widget _progress(int total) {
    final c = context.bx;
    final onClosing = _index >= total;
    final remaining = (total - _index - 1).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  onClosing
                      ? 'End of the deck'
                      : '${_index + 1} of $total',
                  style: BxType.mono(c.ink, size: 12.5, weight: 600),
                ),
                const SizedBox(height: 5),
                BxProgressBar(
                  ((_index + 1) / (total + 1)).clamp(0.0, 1.0),
                  color: c.danger,
                ),
              ],
            ),
          ),
          const SizedBox(width: BxSpace.sm),
          BxChip(
            onClosing ? 'Deck cleared' : '$remaining to beat',
            accent: onClosing || remaining == 0
                ? BxAccent.success
                : BxAccent.danger,
            icon: onClosing || remaining == 0
                ? Icons.check_rounded
                : Icons.local_fire_department_rounded,
            dense: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- one card

  Widget _card(Question q, int i, int total) {
    final c = context.bx;
    final open = _revealed.contains(q.id);
    final saved = _saved.contains(q.id);

    return BxPage(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.xs, BxSpace.xs, BxSpace.xs, BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxCard(
            raised: true,
            padding: const EdgeInsets.all(BxSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BxChip(
                      q.courseCode.isEmpty ? 'Missed' : q.courseCode,
                      accent: BxAccent.danger,
                      icon: Icons.close_rounded,
                      dense: true,
                    ),
                    const Spacer(),
                    Text('Card ${i + 1}/$total',
                        style: BxType.mono(c.muted, size: 11.5)),
                  ],
                ),
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
                const SizedBox(height: BxSpace.md),
                _options(q, open),
                const SizedBox(height: BxSpace.md),
                if (!open)
                  BxButton(
                    'Show answer',
                    icon: Icons.visibility_outlined,
                    expand: true,
                    onPressed: () => _reveal(q),
                  ),
                AnimatedSize(
                  duration: BxDuration.base,
                  curve: BxCurves.smooth,
                  alignment: Alignment.topCenter,
                  child: open
                      ? BxFadeIn(child: _answer(q))
                      : const SizedBox(width: double.infinity, height: 0),
                ),
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
          ),
          const SizedBox(height: BxSpace.sm),
          Center(
            child: Text(
              i == total - 1
                  ? 'Swipe left for the last word on this deck'
                  : 'Swipe to the next card',
              style: BxType.tiny(c.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options(Question q, bool open) {
    final c = context.bx;
    final options = q.displayOptions;

    if (options.isEmpty) {
      // Short answer, or a question whose options never arrived.
      return Text(
        q.type == QuestionType.shortAnswer
            ? 'This one is typed, not picked. Say the answer in your head '
                'before you turn the card.'
            : 'This question has no options loaded yet. Report it so Tutor '
                'Bello can put it right.',
        style: BxType.small(c.muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: BxSpace.xs),
          _optionTile(q, options[i], open),
        ],
      ],
    );
  }

  Widget _optionTile(Question q, QuestionOption o, bool open) {
    final c = context.bx;
    final key = o.key.toUpperCase();
    final correctKey = (q.correctKey ?? '').toUpperCase();
    final isCorrect = open && correctKey.isNotEmpty && key == correctKey;

    final fill = isCorrect ? BxAccent.success.fill(c) : c.surfaceSunken;
    final stroke =
        isCorrect ? c.success.withValues(alpha: 0.55) : c.line;
    final ink = isCorrect ? c.success : c.ink;

    return AnimatedOpacity(
      duration: BxDuration.base,
      curve: BxCurves.smooth,
      opacity: open && !isCorrect ? 0.55 : 1,
      child: AnimatedContainer(
        duration: BxDuration.base,
        curve: BxCurves.smooth,
        padding: const EdgeInsets.all(BxSpace.sm),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: stroke, width: isCorrect ? 1.5 : 1),
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
                      child: BxHtml(o.text, textStyle: BxType.body(ink)),
                    ),
                  if ((o.imageUrl ?? '').isNotEmpty) ...[
                    if (o.text.trim().isNotEmpty)
                      const SizedBox(height: BxSpace.xs),
                    _image(o.imageUrl!, maxHeight: 160),
                  ],
                ],
              ),
            ),
            if (isCorrect) ...[
              const SizedBox(width: BxSpace.xs),
              Icon(Icons.check_rounded, size: 19, color: ink),
            ],
          ],
        ),
      ),
    );
  }

  Widget _answer(Question q) {
    final c = context.bx;
    final answerKey = (q.correctKey ?? '').toUpperCase();
    final accepted = q.acceptedAnswer;

    final String headline;
    if (q.type == QuestionType.shortAnswer) {
      headline =
          accepted.isEmpty ? 'The answer' : 'The answer: $accepted';
    } else {
      headline = answerKey.isEmpty ? 'The answer' : 'The answer is $answerKey';
    }

    return Padding(
      padding: const EdgeInsets.only(top: BxSpace.md),
      child: BxCard(
        accent: BxAccent.success,
        padding: const EdgeInsets.all(BxSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, size: 20, color: c.success),
                const SizedBox(width: BxSpace.xs),
                Expanded(child: Text(headline, style: BxType.h3(c.success))),
              ],
            ),
            if (q.hasExplanation) ...[
              const SizedBox(height: BxSpace.sm),
              if ((q.explanationHtml ?? '').trim().isNotEmpty)
                BxHtml(q.explanationHtml!,
                    textStyle: BxType.body(c.inkSoft)),
              if ((q.explanationImageUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: BxSpace.sm),
                _image(q.explanationImageUrl!, maxHeight: 260),
              ],
            ] else ...[
              const SizedBox(height: BxSpace.xs),
              Text(
                'No written explanation on this one yet. Save it and ask '
                'Bello AI to break it down.',
                style: BxType.small(c.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- last card

  Widget _closingCard(int total) {
    final c = context.bx;
    final seen = _revealed.length;

    return BxPage(
      padding: const EdgeInsets.fromLTRB(
          BxSpace.xs, BxSpace.xs, BxSpace.xs, BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BxCard(
            accent: BxAccent.gold,
            raised: true,
            padding: const EdgeInsets.all(BxSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BxEyebrow('Bottom of the pile'),
                const SizedBox(height: BxSpace.xs),
                Text('That is the whole deck', style: BxType.h1(c.ink)),
                const SizedBox(height: BxSpace.xs),
                Text(
                  total == 1
                      ? 'One question has beaten you so far. Turning cards is '
                          'recognition; answering under pressure is what makes '
                          'it stick.'
                      : '$total questions have beaten you so far, and you '
                          'turned $seen of them over today. Turning cards is '
                          'recognition; answering under pressure is what makes '
                          'it stick.',
                  style: BxType.body(c.inkSoft),
                ),
                const SizedBox(height: BxSpace.lg),
                BxButton(
                  'Drill these properly',
                  icon: Icons.bolt_rounded,
                  expand: true,
                  large: true,
                  loading: _drilling,
                  loadingLabel: 'Building your drill…',
                  onPressed: _drill,
                ),
                const SizedBox(height: BxSpace.sm),
                BxButton.secondary(
                  'Back to the first card',
                  icon: Icons.restart_alt_rounded,
                  expand: true,
                  onPressed: () => _goTo(0),
                ),
              ],
            ),
          ),
          const SizedBox(height: BxSpace.md),
          Center(
            child: Text(
              'Beat a question in a real round and it leaves this deck.',
              style: BxType.tiny(c.muted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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

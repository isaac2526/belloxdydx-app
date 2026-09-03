import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE RESULT — SCORE FIRST, THEN THE FIX
///
/// The score card is the reward; the review under it is the work. Every
/// question comes back with what you picked, what was right, and Tutor
/// Bello's explanation, so the paper you just wrote becomes the lesson
/// you keep. Sixty questions stay smooth because the review is built
/// lazily, one card at a time, as you scroll.
/// ============================================================

class ResultScreen extends ConsumerStatefulWidget {
  final String attemptId;
  const ResultScreen({super.key, required this.attemptId});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  /// Bookmark state per question, seeded from the server but owned by the
  /// screen once the student taps — so the chip answers immediately.
  final Map<String, bool> _saved = {};
  final Set<String> _savingIds = {};
  bool _startingPractice = false;

  String _friendly(Object e) => e is BxError
      ? e.message
      : 'That did not go through. Check your connection and try again.';

  Future<void> _refresh() async {
    ref.invalidate(resultProvider(widget.attemptId));
    try {
      await ref.read(resultProvider(widget.attemptId).future);
    } catch (_) {
      // The error state below already says what happened; the pull just ends.
    }
  }

  // ---------------------------------------------------------- actions

  Future<void> _share(ResultReview r) async {
    final label = r.title.trim().isNotEmpty
        ? r.title.trim()
        : (r.courseCode.trim().isNotEmpty ? r.courseCode.trim() : r.mode.label);
    try {
      await Share.share(
        'I scored ${r.percent}% on $label — Belloxdydx. ${BxConfig.siteUrl}',
        subject: 'Belloxdydx',
      );
    } catch (_) {
      if (!mounted) return;
      bxToast(context, 'The share sheet did not open this time.', error: true);
    }
  }

  Future<void> _practiceMore(ResultReview r) async {
    if (_startingPractice) return;
    if (!ref.read(profileProvider).isActivated) {
      await showActivationGate(context, () => context.push(Routes.activate));
      return;
    }
    setState(() => _startingPractice = true);
    try {
      final id =
          await ref.read(assessmentRepoProvider).startPractice(r.courseId);
      if (!mounted) return;
      context.pushReplacement(Routes.practice(id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingPractice = false);
      bxToast(context, _friendly(e), error: true);
    }
  }

  Future<void> _toggleSave(ReviewItem item) async {
    final id = item.question.id;
    if (id.isEmpty || _savingIds.contains(id)) return;
    final was = _saved[id] ?? item.bookmarked;
    HapticFeedback.selectionClick();
    setState(() {
      _saved[id] = !was;
      _savingIds.add(id);
    });
    try {
      final saved = await ref.read(assessmentRepoProvider).toggleBookmark(id);
      if (!mounted) return;
      setState(() {
        _saved[id] = saved;
        _savingIds.remove(id);
      });
      ref.invalidate(bookmarkCountProvider);
      bxToast(
        context,
        saved
            ? 'Saved. You will meet this one again in Saved questions.'
            : 'Removed from your saved questions.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saved[id] = was;
        _savingIds.remove(id);
      });
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
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    try {
      await ref.read(assessmentRepoProvider).reportQuestion(q.id, reason.trim());
      if (!mounted) return;
      bxToast(context, 'Sent. Tutor Bello will look at this question.');
    } catch (e) {
      if (!mounted) return;
      bxToast(context, _friendly(e), error: true);
    }
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(resultProvider(widget.attemptId));
    final review = async.valueOrNull;

    return Scaffold(
      appBar: BxAppBar(
        title: 'Your result',
        subtitle: review == null ? null : _label(review),
        actions: [
          IconButton(
            tooltip: 'Share my score',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: review == null ? null : () => _share(review),
          ),
        ],
      ),
      body: async.when(
        loading: () => const BxPage(
          child: BxSkeletonList(count: 5, itemHeight: 96),
        ),
        error: (e, _) => BxPage(
          onRefresh: _refresh,
          child: BxErrorState(
            title: 'That result would not open',
            message: _friendly(e),
            onRetry: _refresh,
          ),
        ),
        data: _content,
      ),
    );
  }

  Widget _content(ResultReview r) {
    final items = r.items;
    final hasItems = items.isNotEmpty;

    return BxPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          // A builder, not a Column: a 60-question exam only ever builds
          // the handful of cards that are actually on screen.
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.xxxl),
            itemCount: 2 + (hasItems ? items.length : 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: BxSpace.xl),
                  child: BxFadeIn(child: _hero(r)),
                );
              }
              if (i == 1) {
                return BxSectionHeader(
                  eyebrow: 'The fix',
                  title: 'Question by question review',
                  trailing: hasItems
                      ? BxChip('${items.length} questions', dense: true)
                      : null,
                );
              }
              if (!hasItems) {
                return BxEmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Nothing to review here',
                  message:
                      'This attempt kept no questions to walk back through. '
                      'Run a fresh set and the review will be waiting.',
                  actionLabel:
                      r.courseId.isEmpty ? null : 'Practice ${r.courseCode}',
                  onAction: r.courseId.isEmpty ? null : () => _practiceMore(r),
                );
              }
              final item = items[i - 2];
              return Padding(
                padding: const EdgeInsets.only(bottom: BxSpace.sm),
                child: _ReviewCard(
                  item: item,
                  saved: _saved[item.question.id] ?? item.bookmarked,
                  busy: _savingIds.contains(item.question.id),
                  onToggleSave: () => _toggleSave(item),
                  onReport: () => _report(item.question),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- hero

  Widget _hero(ResultReview r) {
    final c = context.bx;
    final percent = r.percent;
    final accent = BxPercentBadge.accentFor(percent);
    final tone = BxPercentBadge.colorFor(context, percent);

    final card = BxCard(
      accent: accent,
      raised: true,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BxEyebrow(_label(r)),
          const SizedBox(height: BxSpace.sm),
          BxCountUp(percent, suffix: '%', style: BxType.hero(tone)),
          const SizedBox(height: BxSpace.xxs),
          Text('${r.score} of ${r.total} correct', style: BxType.mono(c.muted)),
          const SizedBox(height: BxSpace.sm),
          Text(r.verdict, style: BxType.h3(c.ink)),
          const SizedBox(height: BxSpace.md),
          Wrap(
            spacing: BxSpace.xs,
            runSpacing: BxSpace.xs,
            children: [
              BxChip(r.mode.label, icon: Icons.assignment_turned_in_outlined),
              if (r.timeUsed != null)
                BxChip(_clock(r.timeUsed!), icon: Icons.timer_outlined),
              if (r.beatPercent != null)
                BxChip(
                  'You beat ${r.beatPercent}% of takers',
                  accent: BxAccent.gold,
                  icon: Icons.trending_up_rounded,
                ),
              if (r.violations > 0)
                BxChip(
                  '${r.violations} violation${r.violations == 1 ? '' : 's'}',
                  accent: BxAccent.danger,
                  icon: Icons.gpp_maybe_outlined,
                ),
            ],
          ),
          const SizedBox(height: BxSpace.lg),
          Wrap(
            spacing: BxSpace.xs,
            runSpacing: BxSpace.xs,
            children: [
              if (r.courseCode.isNotEmpty)
                BxButton.secondary(
                  'Back to ${r.courseCode}',
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => context.go(Routes.course(r.courseCode)),
                ),
              if (r.courseId.isNotEmpty)
                BxButton(
                  'Practice more',
                  icon: Icons.bolt_rounded,
                  loading: _startingPractice,
                  loadingLabel: 'Building your set…',
                  onPressed: () => _practiceMore(r),
                ),
              BxButton.ghost(
                'Leaderboard',
                icon: Icons.emoji_events_outlined,
                onPressed: () => context.go(Routes.ranks),
              ),
            ],
          ),
        ],
      ),
    );

    if (percent < 80) return card;
    return Stack(
      children: [
        card,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BxRadius.card,
              child: const _Confetti(),
            ),
          ),
        ),
      ],
    );
  }

  String _label(ResultReview r) {
    final parts = [r.courseCode.trim(), r.title.trim()]
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? r.mode.label : parts.join(' · ');
  }
}

String _clock(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// ============================================================
/// ONE QUESTION, WALKED BACK
/// ============================================================

class _ReviewCard extends StatelessWidget {
  final ReviewItem item;
  final bool saved;
  final bool busy;
  final VoidCallback onToggleSave;
  final VoidCallback onReport;

  const _ReviewCard({
    required this.item,
    required this.saved,
    required this.busy,
    required this.onToggleSave,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final q = item.question;

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: BxEyebrow('Question ${item.n} · ${q.marks} mk'),
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              _statusChip(),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          if (q.questionHtml.trim().isNotEmpty)
            BxHtml(q.questionHtml, textStyle: BxType.bodyLg(c.ink)),
          if ((q.questionImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: BxSpace.sm),
            _Media(url: q.questionImageUrl!, maxHeight: 240),
          ],
          const SizedBox(height: BxSpace.md),
          if (q.type == QuestionType.shortAnswer)
            ..._typedAnswer(context)
          else
            ..._options(context),
          if (q.hasExplanation) ...[
            const SizedBox(height: BxSpace.md),
            _why(context),
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
                onTap: busy ? null : onToggleSave,
              ),
              const SizedBox(width: BxSpace.xs),
              BxChip('Report', icon: Icons.flag_outlined, onTap: onReport),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    if (!item.answered) {
      return const BxChip('Skipped', icon: Icons.remove_rounded, dense: true);
    }
    return item.isCorrect
        ? const BxChip('Correct',
            accent: BxAccent.success, icon: Icons.check_rounded, dense: true)
        : const BxChip('Wrong',
            accent: BxAccent.danger, icon: Icons.close_rounded, dense: true);
  }

  // ---- typed answers ----

  List<Widget> _typedAnswer(BuildContext context) {
    final q = item.question;
    final typed = (item.yourText ?? '').trim();
    final accepted = q.acceptedAnswer;

    return [
      _AnswerBox(
        label: 'You typed',
        body: typed.isEmpty ? 'You left this one blank.' : typed,
        accent: !item.answered
            ? BxAccent.neutral
            : (item.isCorrect ? BxAccent.success : BxAccent.danger),
      ),
      if (!item.isCorrect && accepted.isNotEmpty) ...[
        const SizedBox(height: BxSpace.xs),
        _AnswerBox(
          label: 'Accepted answer',
          body: accepted,
          accent: BxAccent.success,
        ),
      ],
    ];
  }

  // ---- option lists ----

  List<Widget> _options(BuildContext context) {
    final q = item.question;
    final options = q.displayOptions;
    if (options.isEmpty) {
      return [
        Text(
          'The options for this one were not kept with your attempt.',
          style: BxType.small(context.bx.muted),
        ),
      ];
    }
    final correctKey = (q.correctKey ?? '').trim().toUpperCase();
    final yourKey = (item.yourKey ?? '').trim().toUpperCase();

    return [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(height: BxSpace.xs),
        _optionRow(context, options[i], correctKey, yourKey),
      ],
    ];
  }

  Widget _optionRow(
    BuildContext context,
    QuestionOption o,
    String correctKey,
    String yourKey,
  ) {
    final c = context.bx;
    final key = o.key.toUpperCase();
    final isCorrect = correctKey.isNotEmpty && key == correctKey;
    final isYours = yourKey.isNotEmpty && key == yourKey;
    final isWrongPick = isYours && !isCorrect;
    final marked = isCorrect || isWrongPick;

    final fill = isCorrect
        ? BxAccent.success.fill(c)
        : (isWrongPick ? BxAccent.danger.fill(c) : c.surfaceSunken);
    final stroke = isCorrect
        ? c.success.withValues(alpha: 0.55)
        : (isWrongPick ? c.danger.withValues(alpha: 0.55) : c.line);
    final ink = isCorrect ? c.success : (isWrongPick ? c.danger : c.ink);

    final tags = <String>[
      if (isCorrect) 'correct answer',
      if (isYours) 'your pick',
    ];

    final row = Container(
      padding: const EdgeInsets.all(BxSpace.sm),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: stroke, width: marked ? 1.5 : 1),
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
                  _Media(url: o.imageUrl!, maxHeight: 160),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: BxSpace.xxs),
                  Text(
                    tags.join(' · ').toUpperCase(),
                    style: BxType.eyebrow(ink),
                  ),
                ],
              ],
            ),
          ),
          if (marked) ...[
            const SizedBox(width: BxSpace.xs),
            Icon(
              isCorrect ? Icons.check_rounded : Icons.close_rounded,
              size: 19,
              color: ink,
            ),
          ],
        ],
      ),
    );

    return marked ? row : Opacity(opacity: 0.7, child: row);
  }

  // ---- the explanation ----

  Widget _why(BuildContext context) {
    final c = context.bx;
    final q = item.question;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BxSpace.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxEyebrow('Why'),
          const SizedBox(height: BxSpace.xs),
          if ((q.explanationHtml ?? '').trim().isNotEmpty)
            BxHtml(q.explanationHtml!, textStyle: BxType.body(c.inkSoft)),
          if ((q.explanationImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: BxSpace.sm),
            _Media(url: q.explanationImageUrl!, maxHeight: 240),
          ],
          if ((q.explanationAudioUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: BxSpace.sm),
            BxAudio(
              url: q.explanationAudioUrl!,
              label: 'Tutor Bello explains',
            ),
          ],
        ],
      ),
    );
  }
}

/// A tinted box holding one typed answer.
class _AnswerBox extends StatelessWidget {
  final String label;
  final String body;
  final BxAccent accent;

  const _AnswerBox({
    required this.label,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      // A neutral box would vanish into the card behind it.
      fill: accent == BxAccent.neutral ? c.surfaceSunken : null,
      padding: const EdgeInsets.all(BxSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BxEyebrow(label, color: accent == BxAccent.neutral ? c.muted : null),
          const SizedBox(height: BxSpace.xxs),
          Text(body, style: BxType.bodyStrong(accent.ink(c))),
        ],
      ),
    );
  }
}

/// ============================================================
/// MEDIA
/// ============================================================

class _Media extends StatelessWidget {
  final String url;
  final double maxHeight;
  const _Media({required this.url, required this.maxHeight});

  void _zoom(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxScaleTap(
      onTap: () => _zoom(context),
      scale: 0.99,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BxRadius.sm),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(BxRadius.sm),
          ),
          child: BxImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) =>
                const BxSkeleton(height: 140, radius: BxRadius.sm),
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
      ),
    );
  }
}

/// A compact audio row. Audio is polish: when the platform refuses the
/// file the row says so quietly instead of breaking the review.

/// ============================================================
/// THE CONFETTI
/// Forty paper flecks fall across the score card for 2.8 seconds when a
/// student clears 80, then the widget removes itself so nothing keeps
/// painting behind the review. Reduce-motion gets a still card.
/// ============================================================

class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  static const _pieceCount = 40;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final List<_ConfettiPiece> _pieces;
  bool _spent = false;

  @override
  void initState() {
    super.initState();
    // A fixed seed so the burst is identical on every rebuild of the frame.
    final rnd = math.Random(8317);
    _pieces = List.generate(
      _pieceCount,
      (i) => _ConfettiPiece(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.3,
        drift: (rnd.nextDouble() - 0.5) * 0.4,
        spin: 1.2 + rnd.nextDouble() * 3,
        size: 5 + rnd.nextDouble() * 6,
        phase: rnd.nextDouble() * math.pi * 2,
        tone: i % 5,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || reduceMotion(context)) return;
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _spent = true);
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_spent || reduceMotion(context)) return const SizedBox.shrink();
    final c = context.bx;
    final palette = <Color>[c.gold, c.goldBright, c.success, c.info, c.violet];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            progress: _c.value,
            pieces: _pieces,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

@immutable
class _ConfettiPiece {
  final double x; // 0..1 across the card
  final double delay; // fraction of the run before it starts falling
  final double drift; // sideways travel over the run
  final double spin; // turns over the run
  final double size;
  final double phase; // wobble offset and starting angle
  final int tone;

  const _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.drift,
    required this.spin,
    required this.size,
    required this.phase,
    required this.tone,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiPiece> pieces;
  final List<Color> palette;

  const _ConfettiPainter({
    required this.progress,
    required this.pieces,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || palette.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in pieces) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      // Gravity: slow release, then a real drop.
      final dy = -0.2 + (t * 0.45 + t * t * 0.95) * 1.25;
      if (dy > 1.25) continue;
      final dx = p.x + p.drift * t + 0.025 * math.sin(p.phase + t * math.pi * 3);
      final fade = t > 0.75 ? ((1 - t) / 0.25).clamp(0.0, 1.0) : 1.0;

      paint.color =
          palette[p.tone % palette.length].withValues(alpha: fade * 0.9);
      canvas.save();
      canvas.translate(dx * size.width, dy * size.height);
      canvas.rotate(p.phase + t * p.spin * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.55),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
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

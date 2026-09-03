import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'inputs.dart';
import 'primitives.dart';

/// ============================================================
/// LOADING, EMPTY AND ERROR STATES
/// The audit found the website shows spinners or nothing. The app
/// shows skeletons that match the shape of what is coming, empty
/// states that offer the next action, and errors that say what to do.
/// ============================================================

/// A shimmering placeholder block.
class BxSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const BxSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = BxRadius.xs,
  });

  @override
  State<BxSkeleton> createState() => _BxSkeletonState();
}

class _BxSkeletonState extends State<BxSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(c.surfaceAlt, c.line, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton shaped like a card list — the default loading state for
/// courses, materials, results and leaderboards.
class BxSkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;

  const BxSkeletonList({super.key, this.count = 5, this.itemHeight = 68});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    // Draws only as many rows as it has room for.
    //
    // A skeleton is what a student looks at while they WAIT, so it is
    // the one thing in the app that must not be able to fail. Dropped
    // into a box too short for every row — the loading state of a
    // bottom sheet, a short card, a split view — a plain Column drew a
    // black-and-yellow overflow stripe across it, which is the app
    // telling the student it is broken while it loads.
    //
    // Clipping alone does not fix that: the flex still asserts, it just
    // hides the evidence. So the count is decided from the box instead.
    // Given room for four rows it draws four, and nobody can tell the
    // difference between four grey bars and six.
    return LayoutBuilder(builder: (context, box) {
      final rows = box.hasBoundedHeight
          ? ((box.maxHeight + BxSpace.sm) / (itemHeight + BxSpace.sm))
              .floor()
              .clamp(1, count)
          : count;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          rows,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: BxSpace.sm),
            child: Container(
              // A MINIMUM, not a fixed height. It was fixed, and a
              // caller asking for a shorter row than the two bars plus
              // the padding need overflowed by exactly the difference.
              constraints: BoxConstraints(minHeight: itemHeight),
              padding: const EdgeInsets.all(BxSpace.md),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BxRadius.card,
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BxSkeleton(width: 160 + (i % 3) * 40, height: 13),
                  const SizedBox(height: BxSpace.xs),
                  BxSkeleton(width: 100 + (i % 2) * 60, height: 10),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// A skeleton shaped like the dashboard.
class BxSkeletonDashboard extends StatelessWidget {
  const BxSkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    Widget box(double h) => Container(
          height: h,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BxRadius.card,
            border: Border.all(color: c.line),
          ),
          padding: const EdgeInsets.all(BxSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              BxSkeleton(width: 90, height: 10),
              SizedBox(height: BxSpace.sm),
              BxSkeleton(width: 140, height: 22),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BxSkeleton(width: 120, height: 11),
        const SizedBox(height: BxSpace.xs),
        const BxSkeleton(width: 230, height: 26),
        const SizedBox(height: BxSpace.lg),
        Row(children: [
          Expanded(child: box(92)),
          const SizedBox(width: BxSpace.sm),
          Expanded(child: box(92)),
          const SizedBox(width: BxSpace.sm),
          Expanded(child: box(92)),
        ]),
        const SizedBox(height: BxSpace.md),
        box(140),
        const SizedBox(height: BxSpace.md),
        box(180),
      ],
    );
  }
}

/// The empty state: a mark, a headline, one line of explanation, and the
/// single action that fixes it.
class BxEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final BxAccent accent;

  const BxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent = BxAccent.gold,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.lg, vertical: BxSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.fill(c),
              shape: BoxShape.circle,
              border: Border.all(color: accent.stroke(c)),
            ),
            child: Icon(icon, size: 25, color: accent.ink(c)),
          ),
          const SizedBox(height: BxSpace.md),
          Text(title, style: BxType.h3(c.ink), textAlign: TextAlign.center),
          const SizedBox(height: BxSpace.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BxSpace.sm),
            child: Text(message,
                style: BxType.small(c.muted), textAlign: TextAlign.center),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: BxSpace.lg),
            BxButton(actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// The error state. Says what went wrong and how to fix it — no
/// apologies, no stack traces, no host names.
class BxErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final String? title;

  const BxErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: BxAccent.danger,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 19, color: c.danger),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text(title ?? 'That did not load',
                    style: BxType.h3(c.danger)),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(message, style: BxType.small(c.inkSoft)),
          if (onRetry != null) ...[
            const SizedBox(height: BxSpace.md),
            BxButton.secondary(retryLabel,
                icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// An inline banner. Used for preview mode, offline notice, exam warnings.
class BxBanner extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final BxAccent accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const BxBanner({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.info_outline_rounded,
    this.accent = BxAccent.gold,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent.ink(c)),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: BxType.bodyStrong(accent.ink(c))),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: BxType.small(c.inkSoft)),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: BxSpace.sm),
                  BxButton(actionLabel!, onPressed: onAction),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 17, color: c.muted),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A full-screen thinking state used while an attempt is being built or
/// a document is opening. Honest about what it is doing.
class BxThinking extends StatelessWidget {
  final String message;
  const BxThinking({super.key, this.message = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: c.gold),
          ),
          const SizedBox(height: BxSpace.md),
          Text(message, style: BxType.small(c.muted)),
        ],
      ),
    );
  }
}

/// Toast helper so every screen reports the same way.
void bxToast(BuildContext context, String message, {bool error = false}) {
  final c = context.bx;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 17,
              color: error ? c.danger : c.success,
            ),
            const SizedBox(width: BxSpace.xs),
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

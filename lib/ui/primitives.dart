import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'motion.dart';

/// ============================================================
/// SURFACE & LABEL PRIMITIVES
/// Sharp white cards, hairline borders, one restrained shadow.
/// No gradients. Colour arrives as a flat tint or a single mark.
/// ============================================================

/// Accent roles a card or chip can take. Each maps to a flat tint plus a
/// matching border and text colour — never a gradient.
enum BxAccent { neutral, gold, success, danger, info, violet, warning }

extension BxAccentColors on BxAccent {
  Color fill(BxColors c) => switch (this) {
        BxAccent.neutral => c.surface,
        BxAccent.gold => c.goldTint,
        BxAccent.success => c.successTint,
        BxAccent.danger => c.dangerTint,
        BxAccent.info => c.infoTint,
        BxAccent.violet => c.violetTint,
        BxAccent.warning => c.warningTint,
      };

  Color stroke(BxColors c) => switch (this) {
        BxAccent.neutral => c.line,
        BxAccent.gold => c.gold.withValues(alpha: 0.42),
        BxAccent.success => c.success.withValues(alpha: 0.36),
        BxAccent.danger => c.danger.withValues(alpha: 0.36),
        BxAccent.info => c.info.withValues(alpha: 0.34),
        BxAccent.violet => c.violet.withValues(alpha: 0.34),
        BxAccent.warning => c.warning.withValues(alpha: 0.36),
      };

  Color ink(BxColors c) => switch (this) {
        BxAccent.neutral => c.ink,
        BxAccent.gold => c.goldDeep,
        BxAccent.success => c.success,
        BxAccent.danger => c.danger,
        BxAccent.info => c.info,
        BxAccent.violet => c.violet,
        BxAccent.warning => c.warning,
      };
}

/// The workhorse surface. Flat fill, 1px border, optional shadow.
class BxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BxAccent accent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool raised;
  final double? radius;
  final Color? fill;
  final Color? border;

  const BxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BxSpace.md),
    this.accent = BxAccent.neutral,
    this.onTap,
    this.onLongPress,
    this.raised = false,
    this.radius,
    this.fill,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final r = BorderRadius.circular(radius ?? BxRadius.md);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? accent.fill(c),
        borderRadius: r,
        border: Border.all(color: border ?? accent.stroke(c)),
        boxShadow: raised ? BxShadow.raised(c) : BxShadow.card(c),
      ),
      child: child,
    );
    if (onTap == null && onLongPress == null) return body;
    return BxScaleTap(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: r,
      child: body,
    );
  }
}

/// The signature label: monospace, uppercase, wide tracking, gold.
class BxEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const BxEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Text(
      text.toUpperCase(),
      style: BxType.eyebrow(color ?? c.goldDeep),
    );
  }
}

/// Page/section heading with an eyebrow above and optional trailing action.
class BxSectionHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const BxSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: BxSpace.md),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  BxEyebrow(eyebrow!),
                  const SizedBox(height: BxSpace.xxs),
                ],
                Text(title, style: BxType.h1(c.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: BxSpace.xxs),
                  Text(subtitle!, style: BxType.body(c.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: BxSpace.sm), trailing!],
        ],
      ),
    );
  }
}

/// Small rounded label. Used for modes, counts, states.
class BxChip extends StatelessWidget {
  final String label;
  final BxAccent accent;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool dense;

  const BxChip(
    this.label, {
    super.key,
    this.accent = BxAccent.neutral,
    this.icon,
    this.onTap,
    this.selected = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final fg = selected ? c.goldDeep : accent.ink(c);
    final bg = selected ? c.goldTint : (accent == BxAccent.neutral ? c.surfaceAlt : accent.fill(c));
    final bd = selected ? c.gold.withValues(alpha: 0.55) : accent.stroke(c);

    final body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? BxSpace.xs : BxSpace.sm,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BxRadius.pill),
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          // Flexible and clipped, because a chip lives in a row whose
          // width it does not control. On a 320dp phone at the largest
          // text size the app allows, an unconstrained label pushed the
          // chip 56 pixels past the edge of the screen — a yellow-and-
          // black overflow stripe across a course card.
          Flexible(
            child: Text(
              label,
              style: BxType.tiny(fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? body
        : BxScaleTap(onTap: onTap, scale: 0.94, child: body);
  }
}

/// The colour-graded score badge used on results, leaderboards and
/// recent-result rows. Green >= 70, gold >= 50, red below.
class BxPercentBadge extends StatelessWidget {
  final int percent;
  final bool large;

  const BxPercentBadge(this.percent, {super.key, this.large = false});

  static BxAccent accentFor(int p) =>
      p >= 70 ? BxAccent.success : (p >= 50 ? BxAccent.gold : BxAccent.danger);

  static Color colorFor(BuildContext ctx, int p) {
    final c = ctx.bx;
    return p >= 70 ? c.success : (p >= 50 ? c.goldDeep : c.danger);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final a = accentFor(percent);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? BxSpace.sm : BxSpace.xs,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: a.fill(c),
        borderRadius: BorderRadius.circular(BxRadius.xs),
        border: Border.all(color: a.stroke(c)),
      ),
      child: Text(
        '$percent%',
        style: BxType.mono(a.ink(c), size: large ? 15 : 12.5, weight: 600),
      ),
    );
  }
}

/// A stat tile: big figure, small label, flat accent tint. The figure
/// counts up when it first appears.
class BxStatTile extends StatelessWidget {
  final String label;
  final num value;
  final String suffix;
  final BxAccent accent;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool animate;

  const BxStatTile({
    super.key,
    required this.label,
    required this.value,
    this.suffix = '',
    this.accent = BxAccent.gold,
    this.icon,
    this.onTap,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: accent.ink(c)),
            const SizedBox(height: BxSpace.xs),
          ],
          animate
              ? BxCountUp(value,
                  suffix: suffix, style: BxType.figure(accent.ink(c)))
              : Text('$value$suffix', style: BxType.figure(accent.ink(c))),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
        ],
      ),
    );
  }
}

/// A tappable list row with title, subtitle, optional leading mark and
/// trailing widget. The backbone of every list in the app.
class BxListRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool locked;
  final BxAccent accent;

  const BxListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.locked = false,
    this.accent = BxAccent.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.sm + 2),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: BxSpace.sm)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: BxType.bodyStrong(c.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: BxType.tiny(c.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: BxSpace.xs),
          if (locked)
            Icon(Icons.lock_outline_rounded, size: 18, color: c.muted)
          else if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: 20, color: c.muted),
        ],
      ),
    );
  }
}

/// A circular avatar built from initials — no network image needed for
/// leaderboards and chat.
class BxAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final BxAccent accent;

  const BxAvatar(this.seed, {super.key, this.size = 36, this.accent = BxAccent.gold});

  String get _initials {
    final parts =
        seed.replaceAll('@', '').trim().split(RegExp(r'[\s_.\-]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.elementAt(1)[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.fill(c),
        shape: BoxShape.circle,
        border: Border.all(color: accent.stroke(c)),
      ),
      child: Text(_initials,
          style: BxType.mono(accent.ink(c), size: size * 0.32, weight: 600)),
    );
  }
}

/// A slim progress bar. Flat fill, no gradient.
class BxProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final double height;

  /// When true the bar sweeps instead of standing at zero.
  ///
  /// Work that has not yet been measured — reading a manifest, asking
  /// what a course contains — has no fraction to show, and a bar frozen
  /// at 0% for several seconds reads as "stuck", which is the one thing
  /// a student watching a download must not be told wrongly. A sweeping
  /// bar says "working" without claiming a number nobody has.
  final bool indeterminate;

  const BxProgressBar(
    this.value, {
    super.key,
    this.color,
    this.height = 6,
    this.indeterminate = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(BxRadius.pill),
      child: SizedBox(
        height: height,
        child: indeterminate
            ? LinearProgressIndicator(
                backgroundColor: c.surfaceAlt,
                color: color ?? c.gold,
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
                duration: BxDuration.slow,
                curve: BxCurves.enter,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  backgroundColor: c.surfaceAlt,
                  color: color ?? c.gold,
                ),
              ),
      ),
    );
  }
}

/// A hairline separator that respects the palette.
class BxDivider extends StatelessWidget {
  final double height;
  const BxDivider({super.key, this.height = BxSpace.md});

  @override
  Widget build(BuildContext context) =>
      Divider(color: context.bx.line, height: height, thickness: 1);
}

/// A labelled key/value row, used on profile and result summaries.
class BxKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueWidget;

  const BxKeyValue(this.label, this.value, {super.key, this.valueWidget});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BxSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
          ),
          const SizedBox(width: BxSpace.sm),
          Expanded(
            child: valueWidget ?? Text(value, style: BxType.body(c.ink)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// ============================================================
/// MOTION PRIMITIVES
/// Every animation in the app is one of these. Consistent timing is
/// what separates "animated" from "designed".
/// All of them respect the platform's reduce-motion setting.
/// ============================================================

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A number that earns its value on screen: counts up from zero with an
/// ease-out cubic the first time it is built.
class BxCountUp extends StatefulWidget {
  final num value;
  final String suffix;
  final String prefix;
  final TextStyle? style;
  final Duration duration;
  final bool separator;

  const BxCountUp(
    this.value, {
    super.key,
    this.suffix = '',
    this.prefix = '',
    this.style,
    this.duration = const Duration(milliseconds: 950),
    this.separator = true,
  });

  @override
  State<BxCountUp> createState() => _BxCountUpState();
}

class _BxCountUpState extends State<BxCountUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _a = Tween<double>(begin: 0, end: widget.value.toDouble())
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward();
    });
  }

  @override
  void didUpdateWidget(covariant BxCountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _a = Tween<double>(begin: _a.value, end: widget.value.toDouble())
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _fmt(int n) {
    if (!widget.separator) return '$n';
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return Text('${widget.prefix}${_fmt(widget.value.round())}${widget.suffix}',
          style: widget.style);
    }
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Text(
        '${widget.prefix}${_fmt(_a.value.round())}${widget.suffix}',
        style: widget.style,
      ),
    );
  }
}

/// Cascades children in on a short delay each. Used on dashboard grids
/// and list sections.
class BxStagger extends StatelessWidget {
  final List<Widget> children;
  final Axis direction;
  final double spacing;
  final Duration step;
  final CrossAxisAlignment crossAxisAlignment;

  const BxStagger({
    super.key,
    required this.children,
    this.direction = Axis.vertical,
    this.spacing = BxSpace.md,
    this.step = BxDuration.stagger,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(direction == Axis.vertical
            ? SizedBox(height: spacing)
            : SizedBox(width: spacing));
      }
      items.add(BxFadeIn(delay: step * i, child: children[i]));
    }
    return direction == Axis.vertical
        ? Column(crossAxisAlignment: crossAxisAlignment, children: items)
        : Row(children: items);
  }
}

/// Rises into place from a visible resting state. Never parks content
/// at zero opacity waiting for a scroll.
class BxFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;

  const BxFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 10,
  });

  @override
  State<BxFadeIn> createState() => _BxFadeInState();
}

class _BxFadeInState extends State<BxFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: BxDuration.slow);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.forward();
      });
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: BxCurves.enter);
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Press feedback: a small, quick scale-down. Applied to every tappable
/// card so touch feels physical.
class BxScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;

  const BxScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.975,
    this.borderRadius,
  });

  @override
  State<BxScaleTap> createState() => _BxScaleTapState();
}

class _BxScaleTapState extends State<BxScaleTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down && !reduceMotion(context) ? widget.scale : 1.0,
        duration: BxDuration.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Cross-fades between loading, empty, error and content without the
/// jarring jump a plain if/else produces.
class BxSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const BxSwitcher({super.key, required this.child, this.duration = BxDuration.base});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: BxCurves.enter,
      switchOutCurve: BxCurves.exit,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
              .animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

import 'dart:async';

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

  /// How many children get an entrance. Past this they are simply
  /// drawn.
  ///
  /// Two reasons, and both of them are about a cheap phone. Each
  /// animated child costs an AnimationController and a pending timer,
  /// so a shelf of twenty-two courses was twenty-two of each — on a
  /// screen where at most four are visible. And the stagger is
  /// cumulative: at 40 ms a step, the twenty-second card began its
  /// entrance almost a second after the first, which reads as the app
  /// being slow rather than as a flourish.
  static const int maxAnimated = 10;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(direction == Axis.vertical
            ? SizedBox(height: spacing)
            : SizedBox(width: spacing));
      }
      items.add(i < maxAnimated
          ? BxFadeIn(delay: step * i, child: children[i])
          : children[i]);
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

  /// Built ONCE and disposed.
  ///
  /// It used to be constructed inside build(), which means a fresh
  /// CurvedAnimation — and a fresh listener on the controller — on
  /// every rebuild, none of them ever disposed. On a list that rebuilds
  /// as it scrolls that is a leak that grows for as long as the screen
  /// is open, and Flutter now asserts about exactly this in debug.
  late final CurvedAnimation _curved =
      CurvedAnimation(parent: _c, curve: BxCurves.enter);

  /// Held so it can be cancelled. A bare Future.delayed keeps its
  /// closure — and this State — alive until it fires, however long ago
  /// the widget went away.
  Timer? _start;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.forward();
      });
    } else {
      _start = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _curved.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _curved,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Press feedback: a small, quick scale-down. Applied to every tappable
/// card so touch feels physical.
///
/// A bare GestureDetector gives a screen reader no way to know the thing
/// under the finger can be activated — TalkBack and VoiceOver read the
/// card's text and move on, so a blind student cannot find the control at
/// all. Every tappable in this app goes through here, so declaring the
/// button role once fixes the whole surface.
class BxScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;

  /// Read out instead of the child's own text. Leave it null when the
  /// child already says what the control does.
  final String? semanticLabel;

  /// Set on things that live in a group where one is active — segmented
  /// controls, filter chips, the question palette.
  final bool? selected;

  /// Clear when the child is decorative and the parent already carries
  /// the button role, so the tree does not grow a duplicate node.
  final bool button;

  const BxScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.975,
    this.borderRadius,
    this.semanticLabel,
    this.selected,
    this.button = true,
  });

  @override
  State<BxScaleTap> createState() => _BxScaleTapState();
}

class _BxScaleTapState extends State<BxScaleTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;

    final tappable = GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      // The Semantics wrapper below owns the announcement; letting the
      // detector add its own would put two nodes over one control.
      excludeFromSemantics: true,
      child: AnimatedScale(
        scale: _down && !reduceMotion(context) ? widget.scale : 1.0,
        duration: BxDuration.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );

    if (!widget.button && widget.semanticLabel == null) return tappable;

    return Semantics(
      container: true,
      button: widget.button,
      enabled: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      // With an explicit label the child's own text would only repeat it.
      excludeSemantics: widget.semanticLabel != null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: tappable,
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
      // AnimatedSwitcher's default layout is a LOOSE Stack, which lets a
      // scrolling child shrink to its content and then centres it. A
      // half-height page therefore floats in the middle of the screen
      // with dead bands above and below — visible on the exam paper, and
      // on every loading and empty state in the app. Passing our own
      // constraints straight through makes the child fill the space it
      // was given, exactly as it would without the switcher.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

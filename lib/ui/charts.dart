import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'motion.dart';

/// ============================================================
/// CHARTS
/// Native ports of the website's hand-drawn SVG charts. No chart
/// library: three CustomPainters, one scale each, labels that name
/// values the chart actually reaches, and colours from the theme so
/// they read in both light and dark.
/// ============================================================

class BxSlice {
  final String label;
  final double value;
  final Color color;
  const BxSlice(this.label, this.value, this.color);
}

/// Donut chart with a legend beside it. Used for all-time accuracy.
class BxDonut extends StatelessWidget {
  final List<BxSlice> data;
  final double size;
  final String? centerLabel;
  final String? centerValue;

  const BxDonut({
    super.key,
    required this.data,
    this.size = 128,
    this.centerLabel,
    this.centerValue,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final total = data.fold<double>(0, (s, d) => s + d.value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: BxDuration.xslow,
          curve: BxCurves.enter,
          builder: (_, t, __) => SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _DonutPainter(
                data: data,
                progress: reduceMotion(context) ? 1 : t,
                hole: c.surface,
                track: c.surfaceAlt,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (centerValue != null)
                      Text(centerValue!, style: BxType.h3(c.ink)),
                    if (centerLabel != null)
                      Text(centerLabel!, style: BxType.tiny(c.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: BxSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: data.map((d) {
              final pct = total == 0 ? 0 : (d.value / total * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: d.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: BxSpace.xs),
                    Expanded(
                      child: Text(d.label,
                          style: BxType.small(c.muted),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('${d.value.round()}',
                        style: BxType.mono(c.ink, size: 12.5, weight: 600)),
                    const SizedBox(width: 5),
                    Text('$pct%', style: BxType.tiny(c.muted)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<BxSlice> data;
  final double progress;
  final Color hole;
  final Color track;

  _DonutPainter({
    required this.data,
    required this.progress,
    required this.hole,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(0, (s, d) => s + d.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final ring = radius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius - ring / 2);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      ..color = track;
    canvas.drawCircle(center, radius - ring / 2, trackPaint);

    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final d in data) {
      if (d.value <= 0) continue;
      final sweep = (d.value / total) * math.pi * 2 * progress;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..strokeCap = StrokeCap.butt
        ..color = d.color;
      canvas.drawArc(rect, start, sweep, false, p);
      start += (d.value / total) * math.pi * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.data != data;
}

class BxBar {
  final String label;
  final double value;
  final Color? color;
  const BxBar(this.label, this.value, {this.color});
}

/// Vertical bar chart. Used for average score by course.
class BxBars extends StatelessWidget {
  final List<BxBar> data;
  final double height;
  final String suffix;

  const BxBars({
    super.key,
    required this.data,
    this.height = 150,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    if (data.isEmpty) return const SizedBox.shrink();
    final max = data.map((d) => d.value).reduce(math.max);
    final safeMax = max <= 0 ? 1.0 : max;
    const labelBlock = 40.0;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final frac = (d.value / safeMax).clamp(0.0, 1.0);
          final barMax = height - labelBlock;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${d.value.round()}$suffix',
                      style: BxType.mono(c.ink, size: 11, weight: 600),
                      maxLines: 1),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: BxDuration.xslow,
                    curve: BxCurves.enter,
                    builder: (_, t, __) => Container(
                      height: math.max(5, barMax * (reduceMotion(context) ? frac : t)),
                      decoration: BoxDecoration(
                        color: d.color ?? c.gold,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 14,
                    child: Text(
                      d.label,
                      style: BxType.tiny(c.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A sparkline for score trends over time.
class BxSparkline extends StatelessWidget {
  final List<double> points;
  final double height;
  final Color? color;

  const BxSparkline({
    super.key,
    required this.points,
    this.height = 56,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    if (points.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: BxDuration.xslow,
        curve: BxCurves.enter,
        builder: (_, t, __) => CustomPaint(
          painter: _SparkPainter(
            points: points,
            progress: reduceMotion(context) ? 1 : t,
            line: color ?? c.info,
            fill: (color ?? c.info).withValues(alpha: 0.10),
            dot: color ?? c.info,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> points;
  final double progress;
  final Color line;
  final Color fill;
  final Color dot;

  _SparkPainter({
    required this.points,
    required this.progress,
    required this.line,
    required this.fill,
    required this.dot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = points.reduce(math.max);
    final minV = points.reduce(math.min);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : maxV - minV;
    const pad = 6.0;
    final stepX = size.width / (points.length - 1);

    Offset at(int i) {
      final norm = (points[i] - minV) / range;
      return Offset(i * stepX, size.height - pad - norm * (size.height - pad * 2));
    }

    final count = (points.length * progress).ceil().clamp(2, points.length);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < count; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final area = Path.from(path)
      ..lineTo(at(count - 1).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill..style = PaintingStyle.fill);

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Emphasised endpoint.
    canvas.drawCircle(at(count - 1), 3.4, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.progress != progress || old.points != points;
}

/// A horizontal bar used by the weakness radar — label, count and a bar
/// scaled against the worst course.
class BxMeterRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final double fraction;
  final String trailing;
  final Color? color;
  final Widget? action;

  const BxMeterRow({
    super.key,
    required this.label,
    required this.sublabel,
    required this.fraction,
    required this.trailing,
    this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: const EdgeInsets.only(bottom: BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: BxType.mono(c.goldDeep, size: 13, weight: 600)),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text(sublabel,
                    style: BxType.small(c.muted),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(trailing, style: BxType.tiny(c.muted)),
              if (action != null) ...[
                const SizedBox(width: BxSpace.xs),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 6),
          BxProgressBarRaw(fraction: fraction, color: color ?? c.danger),
        ],
      ),
    );
  }
}

/// Bare animated meter used inside rows (no rounded container chrome).
class BxProgressBarRaw extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;

  const BxProgressBarRaw({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 7,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(BxRadius.pill),
      child: Container(
        height: height,
        color: c.surfaceAlt,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
            duration: BxDuration.xslow,
            curve: BxCurves.enter,
            builder: (_, t, __) => FractionallySizedBox(
              widthFactor: math.max(0.03, t),
              child: Container(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

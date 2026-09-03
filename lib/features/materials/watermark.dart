import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/ui.dart';

/// ============================================================
/// DOCUMENT PROTECTION
///
/// Two small pieces that ride on top of every protected reading
/// surface: the tiled identity flood, and the one-line strip that tells
/// the student the truth about what the app does with captures.
/// ============================================================

/// A dense diagonal flood of the reader's own identity, laid over the
/// page they are reading.
///
/// It is deliberately faint — you read straight through it — but it is
/// on every square inch, so a photograph of the screen carries the
/// username and matric number of whoever took it.
///
/// It returns a [Positioned.fill], so it must be dropped **directly
/// into a [Stack]**, last, above the content it protects:
///
/// ```dart
/// Stack(children: [ HtmlWidget(body), const Watermark() ])
/// ```
class Watermark extends ConsumerWidget {
  /// Overrides the mark. Defaults to the signed-in student's watermark.
  final String? text;

  /// Overrides the ink. Defaults to `context.bx.ink` — pass the reading
  /// surface's own ink when the surface is not the app's own paper.
  final Color? color;

  final double opacity;
  final double fontSize;

  const Watermark({
    super.key,
    this.text,
    this.color,
    this.opacity = 0.08,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = text ?? ref.watch(profileProvider).watermark;
    // A blank profile (preview mode, or a profile still loading) gets no
    // flood rather than a row of empty stamps.
    if (mark.trim().isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          isComplex: true,
          willChange: false,
          painter: _WatermarkPainter(
            text: mark,
            style: BxType.mono(
              (color ?? context.bx.ink).withValues(alpha: opacity),
              size: fontSize,
              weight: 600,
            ),
          ),
        ),
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter({required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const double _angle = -22 * math.pi / 180;
  static const double _gapX = 54;
  static const double _gapY = 44;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // One TextPainter, laid out once, then stamped across the whole
    // surface. Building a painter per tile is what makes naive
    // watermarks drop frames on a long note.
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final stepX = tp.width + _gapX;
    final stepY = tp.height + _gapY;
    if (stepX <= 0 || stepY <= 0) {
      tp.dispose();
      return;
    }

    // Rotating about the centre pulls the corners out of the tiled area,
    // so the loop runs over the half-diagonal instead of the half-size.
    final reach =
        math.sqrt(size.width * size.width + size.height * size.height) / 2 +
            math.max(stepX, stepY);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_angle);

    var row = 0;
    for (var y = -reach; y < reach; y += stepY) {
      // Brick-offset alternate rows so the flood reads as a texture
      // rather than a grid of columns.
      final stagger = row.isEven ? 0.0 : stepX / 2;
      for (var x = -reach; x < reach; x += stepX) {
        tp.paint(canvas, Offset(x + stagger, y));
      }
      row++;
    }

    canvas.restore();
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter old) =>
      old.text != text || old.style != style;
}

/// The one-liner above every protected document.
///
/// The website makes this promise and cannot keep it — a browser cannot
/// stop a screenshot. The Android build sets `FLAG_SECURE` on the whole
/// window, so on Android the claim is literally true: captures come out
/// black at the OS level. iOS has no equivalent, so on iOS the strip
/// drops that sentence instead of lying to the student.
class ThreatStrip extends StatelessWidget {
  const ThreatStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final captureBlocked = defaultTargetPlatform == TargetPlatform.android;

    return BxCard(
      accent: BxAccent.danger,
      padding: const EdgeInsets.symmetric(
        horizontal: BxSpace.sm,
        vertical: BxSpace.xs + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 15, color: c.danger),
          const SizedBox(width: BxSpace.xs),
          Expanded(
            child: Text(
              captureBlocked
                  ? 'Screenshots and screen recording are blocked on this '
                      'device. Every page carries your name and matric number.'
                  : 'Every page carries your name and matric number.',
              style: BxType.tiny(c.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

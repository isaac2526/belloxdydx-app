import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// ============================================================
/// THE MARK
///
/// One brand lockup, used by every screen a signed-out student can
/// reach. It exists because the logo had quietly disappeared from the
/// auth flow: the welcome screen showed it at 60px, the login screen
/// not at all, and Create Account not at all — so the first three
/// screens of the product carried no product.
///
/// The plate is drawn rather than baked into the image so it takes the
/// theme with it: a surface tile, a gold hairline, one soft shadow. The
/// logo asset is a photograph-like PNG, and a flat plate under it stops
/// it reading as a sticker dropped on the page.
/// ============================================================

class BxAuthBrand extends StatelessWidget {
  /// The plate's edge length. 72 is the default for a screen that leads
  /// with the brand; 56 suits a form that leads with its own heading.
  final double size;

  /// Shows the BELLOXDYDX wordmark under the mark. Off where a big
  /// headline sits directly beneath and would compete with it.
  final bool showWordmark;

  /// Shows the university line under the wordmark.
  final bool showPlace;

  final CrossAxisAlignment align;

  const BxAuthBrand({
    super.key,
    this.size = 72,
    this.showWordmark = true,
    this.showPlace = false,
    this.align = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(size * 0.28),
            border: Border.all(color: c.gold.withValues(alpha: 0.45)),
            boxShadow: BxShadow.card(c),
          ),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.cover,
            // A missing asset must still leave a brand-shaped object on
            // the page rather than a broken-image glyph.
            errorBuilder: (_, __, ___) => Container(
              color: c.goldTint,
              alignment: Alignment.center,
              child: Icon(
                Icons.school_rounded,
                size: size * 0.46,
                color: c.goldDeep,
              ),
            ),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.22),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('BELLO', style: BxType.h2(c.ink)),
                Text('XDYDX', style: BxType.h2(c.goldDeep)),
              ],
            ),
          ),
        ],
        if (showPlace) ...[
          const SizedBox(height: BxSpace.xxs),
          const BxEyebrow('University of Ibadan · 100 level'),
        ],
      ],
    );
  }
}

/// Three segments that fill as the student moves through Create Account.
///
/// It replaces three separate "Step N · …" eyebrows that used to sit
/// inside the form competing with the field labels. Progress belongs in
/// the chrome, once, not repeated down the page.
class BxStepBar extends StatelessWidget {
  final int step;
  final int total;

  const BxStepBar({super.key, required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Semantics(
      label: 'Step ${step + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: BxDuration.base,
                curve: BxCurves.enter,
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? c.gold : c.line,
                  borderRadius: BorderRadius.circular(BxRadius.pill),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

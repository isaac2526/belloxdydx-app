import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/router.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE DOOR
///
/// The first screen a signed-out student meets. It says what this is,
/// offers the two ways in, and points at the one tool that needs no
/// account. Nothing here is sold — the students arrive already knowing
/// why they came.
/// ============================================================

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;

    return Scaffold(
      body: SafeArea(
        child: BxPage(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.lg, BxSpace.xl, BxSpace.lg, BxSpace.xl),
          child: BxStagger(
            spacing: BxSpace.lg,
            children: [
              const _Wordmark(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Everything ${BxConfig.university} 100 level needs, '
                    'in one place.',
                    style: BxType.h2(c.ink),
                  ),
                  const SizedBox(height: BxSpace.xs),
                  Text(
                    'Notes and slides you can actually read, past questions '
                    'sorted by course, CBT practice that marks itself, and '
                    'exam simulations that feel like the hall. Small daily '
                    'reading beats midnight panic.',
                    style: BxType.body(c.inkSoft),
                  ),
                ],
              ),
              const BxCard(
                padding: EdgeInsets.symmetric(
                    horizontal: BxSpace.md, vertical: BxSpace.sm),
                child: Column(
                  children: [
                    _Feature(
                      icon: Icons.menu_book_rounded,
                      title: 'Notes, slides and past questions',
                      body: 'Every 100 level course, both semesters.',
                    ),
                    BxDivider(height: BxSpace.lg),
                    _Feature(
                      icon: Icons.fact_check_rounded,
                      title: 'CBT practice that explains itself',
                      body: 'Answer, see why, move on. No waiting.',
                    ),
                    BxDivider(height: BxSpace.lg),
                    _Feature(
                      icon: Icons.timer_rounded,
                      title: 'Real exam simulations',
                      body: 'A live clock and one shot, like the hall.',
                    ),
                    BxDivider(height: BxSpace.lg),
                    _Feature(
                      icon: Icons.emoji_events_rounded,
                      title: 'Rankings and the league',
                      body: 'See where you stand among your coursemates.',
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  BxButton(
                    'Create free account',
                    large: true,
                    expand: true,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.push(Routes.register),
                  ),
                  const SizedBox(height: BxSpace.sm),
                  BxButton.secondary(
                    'Log in',
                    large: true,
                    expand: true,
                    onPressed: () => context.push(Routes.login),
                  ),
                ],
              ),
              Column(
                children: [
                  const BxDivider(height: BxSpace.xs),
                  const SizedBox(height: BxSpace.sm),
                  TextButton.icon(
                    onPressed: () => context.push(Routes.cgpa),
                    icon: Icon(Icons.calculate_outlined,
                        size: 18, color: c.goldDeep),
                    label: const Text('CGPA calculator'),
                  ),
                  Text(
                    'Open it without an account. Your grades stay on your phone.',
                    textAlign: TextAlign.center,
                    style: BxType.tiny(c.muted),
                  ),
                  const SizedBox(height: BxSpace.lg),
                  Text(
                    BxConfig.brandFooter,
                    textAlign: TextAlign.center,
                    style: BxType.tiny(c.muted),
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

/// The wordmark: the logo, the name split in two weights of colour, and
/// the one line that says where this belongs.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(BxRadius.lg),
            border: Border.all(color: c.line),
            boxShadow: BxShadow.card(c),
          ),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.cover,
            // Decoded at the size it is drawn, not the 1254x1254 the
            // file happens to be.
            cacheWidth: 216,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.school_rounded, size: 28, color: c.goldDeep),
          ),
        ),
        const SizedBox(height: BxSpace.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BELLO', style: BxType.h1(c.ink)),
              Text('XDYDX', style: BxType.h1(c.goldDeep)),
            ],
          ),
        ),
        const SizedBox(height: BxSpace.xxs),
        const BxEyebrow('University of Ibadan · 100 level'),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Feature({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.goldTint,
            borderRadius: BorderRadius.circular(BxRadius.sm),
            border: Border.all(color: c.gold.withValues(alpha: 0.42)),
          ),
          child: Icon(icon, size: 17, color: c.goldDeep),
        ),
        const SizedBox(width: BxSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BxType.bodyStrong(c.ink)),
              const SizedBox(height: 1),
              Text(body, style: BxType.small(c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

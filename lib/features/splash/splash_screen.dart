import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../ui/ui.dart';

/// ============================================================
/// SPLASH
///
/// The half second while the router decides where this student
/// belongs. It never navigates — the redirect in core/router.dart
/// owns that — so this screen has exactly one job: hold the brand
/// still and make the wait feel measured instead of stuck.
/// ============================================================

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.xl,
            vertical: BxSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              BxFadeIn(
                offsetY: 6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(BxRadius.xl),
                        border: Border.all(color: c.line),
                        boxShadow: BxShadow.card(c),
                      ),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        semanticLabel: 'Belloxdydx',
                      ),
                    ),
                    const SizedBox(height: BxSpace.lg),
                    Text('Belloxdydx', style: BxType.h1(c.ink)),
                    const SizedBox(height: BxSpace.xxs),
                    Text(
                      'Smash your 100 level exams',
                      style: BxType.body(c.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BxSpace.xxl),
              const _BootBar(),
              const Spacer(flex: 4),
              Text(
                BxConfig.brandFooter,
                style: BxType.tiny(c.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hairline that fills once, over the length of a comfortable breath.
/// It is a pacing device, not a real percentage — so it never stalls at
/// 97% the way a fake download bar does.
class _BootBar extends StatelessWidget {
  const _BootBar();

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final still = reduceMotion(context);

    return SizedBox(
      width: 190,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BxRadius.pill),
        child: SizedBox(
          height: 3,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: BxCurves.smooth,
            builder: (_, t, __) => LinearProgressIndicator(
              value: still ? 1 : t,
              backgroundColor: c.surfaceAlt,
              color: c.gold,
            ),
          ),
        ),
      ),
    );
  }
}

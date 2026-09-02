import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/local_store.dart';
import '../../ui/ui.dart';

/// ============================================================
/// ONBOARDING
///
/// Five cards a student swipes before they ever meet a password field.
/// Shown once per install and then never again — the flag is read
/// synchronously in the router's redirect, so there is no frame where
/// a returning student sees this and is then pushed off it.
///
/// Skip sits in the same place on every card, from the first frame. A
/// student who already knows what Belloxdydx is should never have to
/// swipe four times to reach the login button.
/// ============================================================

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final BxAccent accent;
  const _Slide(this.eyebrow, this.title, this.body, this.icon, this.accent);
}

const _slides = <_Slide>[
  _Slide(
    'Your shelf',
    'Every course, both semesters',
    'Notes written simply, lecture slides, past questions and Tutor Bello '
        'on video — sorted by course, ready before you need them.',
    Icons.menu_book_rounded,
    BxAccent.gold,
  ),
  _Slide(
    'Practice',
    'Questions that explain themselves',
    'Answer, see straight away whether you got it, and read why. No waiting '
        'for a marking scheme, no guessing what you got wrong.',
    Icons.bolt_rounded,
    BxAccent.info,
  ),
  _Slide(
    'CBT',
    'The exam hall, before the exam hall',
    'A live clock, one shot, a question map and a calculator. Sit it the way '
        'you will sit the real one, so the real one holds no surprises.',
    Icons.timer_outlined,
    BxAccent.danger,
  ),
  _Slide(
    'Revision',
    'Your mistakes become your syllabus',
    'Every question you miss lands in one deck. Weak spots are named by '
        'course, and the daily challenge keeps the streak honest.',
    Icons.track_changes_rounded,
    BxAccent.success,
  ),
  _Slide(
    'Progress',
    'See exactly where you stand',
    'Your accuracy, your average by course, your streak — and where you sit '
        'among your coursemates on the league table.',
    Icons.emoji_events_outlined,
    BxAccent.violet,
  ),
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await ref.read(localStoreProvider).setBool(BxKeys.onboardingSeen, true);
    if (mounted) context.go(Routes.welcome);
  }

  void _goTo(int i) {
    if (i < 0 || i >= _slides.length) return;
    HapticFeedback.selectionClick();
    if (reduceMotion(context)) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(
        i,
        duration: BxDuration.base,
        curve: BxCurves.enter,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            // Skip is present on every card including the last, in the
            // same place, so it never moves under a reaching thumb.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BxSpace.md, BxSpace.xs, BxSpace.xs, 0),
              child: Row(
                children: [
                  const BxEyebrow('Belloxdydx'),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BxSpace.lg, 0, BxSpace.lg, BxSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dots(
                    count: _slides.length,
                    index: _index,
                    onTap: _goTo,
                  ),
                  const SizedBox(height: BxSpace.lg),
                  BxButton(
                    _isLast ? 'Create free account' : 'Next',
                    icon: _isLast
                        ? Icons.arrow_forward_rounded
                        : Icons.chevron_right_rounded,
                    large: true,
                    expand: true,
                    onPressed: () async {
                      if (!_isLast) {
                        _goTo(_index + 1);
                        return;
                      }
                      await ref
                          .read(localStoreProvider)
                          .setBool(BxKeys.onboardingSeen, true);
                      if (context.mounted) context.go(Routes.register);
                    },
                  ),
                  const SizedBox(height: BxSpace.xs),
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(localStoreProvider)
                          .setBool(BxKeys.onboardingSeen, true);
                      if (context.mounted) context.go(Routes.login);
                    },
                    child: Text('I already have an account',
                        style: BxType.label(c.goldDeep)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final palette = Theme.of(context).extension<BxColors>() ?? BxColors.light;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BxSpace.lg),
      // Biased above centre. Dead centre leaves a tall empty band over
      // the emblem on a phone, and the eye reads the card as having
      // slipped down the screen rather than as being composed.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          _Emblem(
            icon: slide.icon,
            fill: slide.accent.fill(palette),
            stroke: slide.accent.stroke(palette),
            ink: slide.accent.ink(palette),
          ),
          const SizedBox(height: BxSpace.xl),
          BxEyebrow(slide.eyebrow),
          const SizedBox(height: BxSpace.xs),
          Text(slide.title, style: BxType.h1(c.ink)),
          const SizedBox(height: BxSpace.sm),
          Text(slide.body, style: BxType.bodyLg(c.inkSoft)),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

/// A quiet piece of geometry rather than a stock illustration: one
/// rounded plate, a ring of the slide's accent, and the icon. It keeps
/// the five cards a family without five drawings to commission.
class _Emblem extends StatelessWidget {
  final IconData icon;
  final Color fill;
  final Color stroke;
  final Color ink;

  const _Emblem({
    required this.icon,
    required this.fill,
    required this.stroke,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -math.pi / 24,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(BxRadius.xl),
                border: Border.all(color: c.line),
              ),
            ),
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(BxRadius.xl),
              border: Border.all(color: stroke),
            ),
            child: Icon(icon, size: 46, color: ink),
          ),
        ],
      ),
    );
  }
}

/// Dots that are also controls — a student can jump to a card rather
/// than swipe to it.
class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  const _Dots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == index,
            label: 'Page ${i + 1} of $count',
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                // Padding, not margin: it keeps a 44px touch target
                // around a 7px dot.
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: BxSpace.md),
                child: AnimatedContainer(
                  duration: BxDuration.fast,
                  curve: BxCurves.enter,
                  width: i == index ? 26 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == index ? c.gold : c.line,
                    borderRadius: BorderRadius.circular(BxRadius.pill),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

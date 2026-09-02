import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/features/auth/intro_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 3D door is the most intricate custom paint in the app: a software
/// renderer with a hand-written spring integrator. A crash inside
/// CustomPainter.paint surfaces as a red screen on the login page, which
/// is the worst possible place for one — so pump it through its whole
/// timeline here and let CI catch any throw.
void main() {
  Widget host({bool play = true}) => MaterialApp(
        theme: bxLightTheme,
        home: Scaffold(
          body: Intro3D(
            play: play,
            child: const Center(child: Text('LOGIN FORM')),
          ),
        ),
      );

  testWidgets('renders every frame of the animation without throwing',
      (tester) async {
    await tester.pumpWidget(host());

    // Walk the full 7 second timeline in 100ms steps: walk-in, crouch,
    // set-down, latches, lid, panels, light, particles, rise, idle.
    for (var i = 0; i < 72; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the form is revealed once the case opens', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('LOGIN FORM'), findsOneWidget,
        reason: 'the child is always in the tree, just faded out');

    // Before the rise the form must not accept taps.
    final ignore =
        tester.widget<IgnorePointer>(find.byKey(introFormGateKey));
    expect(ignore.ignoring, isTrue);

    // Past the 4.3s rise mark it becomes interactive. Advance in steps:
    // a ticker sets its start time on its FIRST tick, so one large pump
    // would report zero elapsed and the animation would never move.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final after =
        tester.widget<IgnorePointer>(find.byKey(introFormGateKey));
    expect(after.ignoring, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip reveals the form immediately', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Skip intro'), findsOneWidget);
    await tester.tap(find.text('Skip intro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final ignore =
        tester.widget<IgnorePointer>(find.byKey(introFormGateKey));
    expect(ignore.ignoring, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('play:false skips the stage entirely', (tester) async {
    await tester.pumpWidget(host(play: false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Skip intro'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('honours reduce-motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // With animations disabled the stage never runs, so there is nothing
    // to skip and the form is live straight away.
    expect(find.text('Skip intro'), findsNothing);
    final ignore =
        tester.widget<IgnorePointer>(find.byKey(introFormGateKey));
    expect(ignore.ignoring, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a replay', (tester) async {
    await tester.pumpWidget(host());
    for (var i = 0; i < 72; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Replay intro'), findsOneWidget);
    await tester.tap(find.text('Replay intro'));
    await tester.pump();
    for (var i = 0; i < 72; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes cleanly mid-animation', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}

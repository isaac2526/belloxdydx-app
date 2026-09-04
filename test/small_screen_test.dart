import 'package:belloxdydx/core/providers.dart';
import 'package:belloxdydx/core/security.dart';
import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:belloxdydx/features/security/lock_screen.dart';
import 'package:belloxdydx/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// THE CHEAPEST PHONE, WITH THE BIGGEST TEXT
///
/// "the app should be friendly and be sharp to even a small device like
///  device with small RAM and ROM we don't want them to have issues"
///
/// The app clamps text scaling to 1.35, so that is the worst case a
/// student can actually produce — and 320dp is the narrowest Android
/// phone still in use. Everything must survive both at once.
///
/// These render the REAL widgets. A test that re-implements the widget
/// it is checking passes for ever while the widget drifts, which is
/// exactly how the two overflows below reached a build.
/// ============================================================

/// Every layout complaint Flutter raised while building the frame.
List<String> overflows(WidgetTester tester) => tester
    .takeException()
    .toString()
    .split('\n')
    .where((l) => l.contains('overflowed'))
    .toList();

Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double scale = 1.35,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: bxLightTheme,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalStore.resetForTest();
    await LocalStore.init();
  });

  group('a chip never pushes past the edge of the screen', () {
    // Measured before the fix: 56 pixels past the right edge at 320dp,
    // 16 at 360dp — a yellow-and-black overflow stripe across a course
    // card, on the phones most of these students are holding.
    for (final width in const [320.0, 360.0, 411.0]) {
      testWidgets('at ${width.round()}dp and the largest text allowed',
          (tester) async {
        await pumpAt(
          tester,
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('CHM 101'),
                    BxChip(
                      'Change waiting · download now',
                      accent: BxAccent.warning,
                      icon: Icons.sync_problem_rounded,
                      dense: true,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          size: Size(width, 640),
        );
        expect(overflows(tester), isEmpty,
            reason: 'a chip shares its row with a course code and title');
      });
    }

    testWidgets('a long label is cut, not spilled', (tester) async {
      await pumpAt(
        tester,
        const SizedBox(
          width: 90,
          child: BxChip('an unreasonably long chip label', dense: true),
        ),
        size: const Size(320, 640),
      );
      expect(overflows(tester), isEmpty);
      final text = tester.widget<Text>(
        find.text('an unreasonably long chip label'),
      );
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
    });
  });

  group('the lock screen is reachable on the smallest phone', () {
    // The one screen a student cannot navigate away from. An overflow
    // here is not cosmetic — it is the Unlock button pushed off the
    // bottom with no way to reach it. Measured before the fix: 40 pixels
    // past the bottom at 320x568 with the largest text.
    Widget lock() => const LockOverlay(child: SizedBox.expand());

    List<Override> locked() => [
          appLockProvider.overrideWith(
            (ref) => _StuckLock(BxLockState.enrolling),
          ),
        ];

    for (final size in const [
      Size(320, 568),
      Size(360, 568),
      Size(360, 640),
      Size(411, 915),
    ]) {
      testWidgets(
          'enrolling at ${size.width.round()}x${size.height.round()}',
          (tester) async {
        await pumpAt(tester, lock(), size: size, overrides: locked());
        expect(overflows(tester), isEmpty,
            reason: 'the button that opens the app must stay on screen');
      });
    }

    testWidgets('and it scrolls when it genuinely cannot fit',
        (tester) async {
      // A landscape sliver, far past anything the app supports, purely
      // to prove the failure mode is "scroll" and not "overflow".
      await pumpAt(tester, lock(),
          size: const Size(360, 300), overrides: locked());
      expect(overflows(tester), isEmpty);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('the locked wording fits too', (tester) async {
      await pumpAt(
        tester,
        lock(),
        size: const Size(320, 568),
        overrides: [
          appLockProvider.overrideWith((ref) => _StuckLock(BxLockState.locked)),
        ],
      );
      expect(overflows(tester), isEmpty);
    });
  });
}

/// A lock that stays in one state, so a face can be rendered without a
/// platform channel answering for the fingerprint sensor.
class _StuckLock extends AppLockNotifier {
  _StuckLock(this._fixed) : super(LocalStore.instance) {
    state = _fixed;
  }
  final BxLockState _fixed;

  @override
  Future<bool> unlock() async => false;
}

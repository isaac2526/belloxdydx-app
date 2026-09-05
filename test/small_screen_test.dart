import 'package:belloxdydx/core/providers.dart';
import 'package:belloxdydx/core/security.dart';
import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:belloxdydx/data/offline/course_downloader.dart';
import 'package:belloxdydx/features/security/lock_screen.dart';
import 'package:belloxdydx/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:belloxdydx/data/net_speed.dart';
import 'package:belloxdydx/features/shell/net_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A connection reading that never changes, so a layout test measures
/// the layout and not the network.
class _FixedSpeed extends NetSpeedNotifier {
  _FixedSpeed(BxNetSpeed fixed) : super(NetSpeedMeter()) {
    state = fixed;
  }
}

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
  theDownloadCardOnASmallPhone();

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

/// ============================================================
/// THE DOWNLOAD CARD ON A CHEAP PHONE
///
/// Three separate ways the new offline surfaces went wrong at 320dp,
/// all of them at the exact moment a student needed them most.
/// ============================================================
void theDownloadCardOnASmallPhone() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalStore.resetForTest();
    await LocalStore.init();
  });

  group('the download progress caption', () {
    // A fast Wi-Fi reading is the widest this line ever gets.
    const wide = BxNetSpeed(
      grade: BxNetGrade.good,
      unmetered: true,
      bytesPerSecond: 12.4 * 1024 * 1024,
    );

    testWidgets('keeps its own line rather than being squeezed at 320dp',
        (tester) async {
      // The old layout was Expanded(caption) + the reading in one Row,
      // so the reading took what it asked for and the caption took what
      // was left — about 56dp — and wrapped to four lines that jittered
      // under a running bar. In a Wrap the reading drops to its own run
      // instead and the caption keeps its full line.
      const caption = '3 of 47 · 1.2 MB · working through the pictures';
      await pumpAt(
        tester,
        const Wrap(
          spacing: BxSpace.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [Text(caption), BxNetLine()],
        ),
        size: const Size(320, 640),
        overrides: [
          netSpeedProvider.overrideWith((ref) => _FixedSpeed(wide)),
        ],
      );
      expect(overflows(tester), isEmpty);

      final captionBox = tester.renderObject<RenderBox>(find.text(caption));
      expect(captionBox.size.width, greaterThan(200),
          reason: 'the caption must get a real line, not a 56dp column '
              'left over after the connection reading');
    });

    testWidgets('the reading is cut, never spilled, in a narrow box',
        (tester) async {
      // Given a bounded box — which is what a Wrap run, a card column
      // or a fixed column hands it — the reading must give way rather
      // than paint the yellow-and-black stripe across a running
      // download.
      await pumpAt(
        tester,
        const SizedBox(width: 70, child: BxNetLine()),
        size: const Size(320, 640),
        overrides: [
          netSpeedProvider.overrideWith((ref) => _FixedSpeed(wide)),
        ],
      );
      expect(overflows(tester), isEmpty);
    });
  });

  group('the sentence naming what did not save', () {
    // "6 files did not save" told a student nothing they could act on,
    // so the card names them now — and a named list is long. On the
    // phones these students hold it must wrap rather than paint the
    // yellow-and-black stripe across the card.
    testWidgets('wraps at 320dp and the largest text allowed',
        (tester) async {
      final message = CourseDownloader.failureMessage(6, const [
        CourseDownloadFailure(
            title: 'PHY 102 Series, Episode II — Electric Fields',
            reason: 'not found on the server'),
        CourseDownloadFailure(
            title: 'Lecture 4 slides', reason: 'the connection dropped'),
        CourseDownloadFailure(
            title: 'a picture in Worked examples', reason: 'came down empty'),
      ]);
      await pumpAt(
        tester,
        Text(message, style: const TextStyle(fontSize: 11)),
        size: const Size(320, 640),
      );
      expect(overflows(tester), isEmpty);
      expect(find.textContaining('Episode II'), findsOneWidget,
          reason: 'the whole point is that it names them');
    });
  });

  group('a progress bar with nothing counted yet', () {
    testWidgets('sweeps rather than standing at zero', (tester) async {
      // "Checking what has changed" reads a manifest and a bundle before
      // a single file is counted. A bar frozen at 0% for several seconds
      // reads as "stuck", which is the one thing a student watching a
      // download must not be told wrongly.
      await pumpAt(
        tester,
        const BxProgressBar(0, indeterminate: true),
        size: const Size(320, 640),
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull, reason: 'null value is what sweeps');
    });

    testWidgets('shows the real fraction once there is one', (tester) async {
      await pumpAt(
        tester,
        const BxProgressBar(0.5),
        size: const Size(320, 640),
      );
      await tester.pump(const Duration(seconds: 2));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNotNull);
      expect(bar.value, closeTo(0.5, 0.01));
    });
  });

  group('a section with nothing to say', () {
    testWidgets('takes no space in a stagger', (tester) async {
      // The dashboard's updates banner returned an empty widget when
      // there was nothing to announce. It was still a child, so it
      // still took a gap on each side — a phantom band at the top of
      // every activated student's dashboard, every day.
      await pumpAt(
        tester,
        const BxStagger(
          spacing: 16,
          children: [
            SizedBox(key: ValueKey('A'), height: 20),
            SizedBox.shrink(),
            SizedBox(key: ValueKey('B'), height: 20),
          ],
        ),
        size: const Size(320, 640),
      );
      // BxFadeIn rises 10dp into place; measuring mid-flight would
      // read the entrance offset as spacing.
      await tester.pumpAndSettle();

      final a = tester.getRect(find.byKey(const ValueKey('A')));
      final b = tester.getRect(find.byKey(const ValueKey('B')));
      expect(b.top - a.bottom, closeTo(16, 1),
          reason: 'one gap, not two with a dead widget between them');
    });

    testWidgets('a real section still gets its gap', (tester) async {
      await pumpAt(
        tester,
        const BxStagger(
          spacing: 16,
          children: [
            SizedBox(key: ValueKey('A'), height: 20),
            SizedBox(key: ValueKey('B'), height: 20),
          ],
        ),
        size: const Size(320, 640),
      );
      await tester.pumpAndSettle();
      final a = tester.getRect(find.byKey(const ValueKey('A')));
      final b = tester.getRect(find.byKey(const ValueKey('B')));
      expect(b.top - a.bottom, closeTo(16, 1));
    });
  });
}

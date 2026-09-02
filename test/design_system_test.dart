import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every component, in both themes, at a narrow phone width. Catches the
/// two failures that actually bite in this app: a colour that only exists
/// in one theme (unreadable text) and a row that overflows on a small
/// screen (a yellow-and-black stripe over the UI).
void main() {
  Widget host(Widget child, {required bool dark, double width = 360}) {
    return MaterialApp(
      theme: dark ? bxDarkTheme : bxLightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BxSpace.md),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  final gallery = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const BxEyebrow('Section label'),
      const BxSectionHeader(
        title: 'Dashboard',
        eyebrow: 'Overview',
        subtitle: 'Small daily reading beats midnight panic.',
      ),
      const BxCard(child: Text('A plain card')),
      const SizedBox(height: BxSpace.sm),
      for (final a in BxAccent.values) ...[
        BxCard(accent: a, child: Text('Accent ${a.name}')),
        const SizedBox(height: BxSpace.xs),
      ],
      Row(
        children: const [
          Expanded(
            child: BxStatTile(
                label: 'Attempts', value: 12, accent: BxAccent.gold, animate: false),
          ),
          SizedBox(width: BxSpace.sm),
          Expanded(
            child: BxStatTile(
                label: 'Average', value: 71, suffix: '%', accent: BxAccent.info, animate: false),
          ),
          SizedBox(width: BxSpace.sm),
          Expanded(
            child: BxStatTile(
                label: 'Answered', value: 480, accent: BxAccent.success, animate: false),
          ),
        ],
      ),
      const SizedBox(height: BxSpace.sm),
      Wrap(
        spacing: BxSpace.xs,
        runSpacing: BxSpace.xs,
        children: const [
          BxChip('Neutral'),
          BxChip('Gold', accent: BxAccent.gold),
          BxChip('Exam', accent: BxAccent.danger, icon: Icons.school_rounded),
          BxPercentBadge(88),
          BxPercentBadge(61),
          BxPercentBadge(34),
        ],
      ),
      const SizedBox(height: BxSpace.sm),
      const BxListRow(
        title: 'PHY 101 · Introduction and key laws',
        subtitle: 'Foundations · 12 Jan 2026',
        leading: BxAvatar('PHY 101'),
      ),
      const SizedBox(height: BxSpace.sm),
      const BxProgressBar(0.62),
      const BxDivider(),
      const BxKeyValue('Device bound', '12 Jan 2026'),
      const SizedBox(height: BxSpace.sm),
      Row(
        children: const [
          Expanded(child: BxButton('Primary')),
          SizedBox(width: BxSpace.xs),
          Expanded(child: BxButton.secondary('Secondary')),
        ],
      ),
      const SizedBox(height: BxSpace.xs),
      Row(
        children: const [
          Expanded(child: BxButton.ghost('Ghost')),
          SizedBox(width: BxSpace.xs),
          Expanded(child: BxButton.danger('Delete')),
        ],
      ),
      const SizedBox(height: BxSpace.xs),
      const BxButton('Working', loading: true, loadingLabel: 'Saving…'),
      const SizedBox(height: BxSpace.sm),
      const BxField(label: 'Email', hint: 'you@example.com'),
      const SizedBox(height: BxSpace.sm),
      const BxField(label: 'Username', error: 'Taken already. Try another.'),
      const SizedBox(height: BxSpace.sm),
      const BxPasswordField(helper: 'At least 8 characters.'),
      const SizedBox(height: BxSpace.sm),
      const BxBanner(
        title: 'Preview mode',
        message: 'Activation unlocks every note, video and test.',
        actionLabel: 'Activate now',
      ),
      const SizedBox(height: BxSpace.sm),
      const BxErrorState(message: 'Check your connection and try again.'),
      const SizedBox(height: BxSpace.sm),
      const BxEmptyState(
        icon: Icons.inbox_rounded,
        title: 'Nothing here yet',
        message: 'Your first result appears the moment you finish a practice.',
        actionLabel: 'Open a course',
      ),
      const SizedBox(height: BxSpace.sm),
      const BxSkeletonList(count: 2),
      const SizedBox(height: BxSpace.sm),
      const BxSkeletonDashboard(),
    ],
  );

  for (final dark in [false, true]) {
    final label = dark ? 'dark' : 'light';

    testWidgets('the component gallery renders in $label with no overflow',
        (tester) async {
      await tester.pumpWidget(host(gallery, dark: dark));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('charts render in $label', (tester) async {
      await tester.pumpWidget(host(
        Column(children: [
          BxCard(
            child: BxDonut(
              data: [
                BxSlice('Correct', 56, dark ? BxColors.dark.success : BxColors.light.success),
                BxSlice('Missed', 24, dark ? BxColors.dark.danger : BxColors.light.danger),
              ],
              centerValue: '70%',
              centerLabel: 'accuracy',
            ),
          ),
          const SizedBox(height: BxSpace.sm),
          const BxCard(
            child: BxBars(
              data: [
                BxBar('PHY 101', 80),
                BxBar('MTH 101', 70),
                BxBar('CHM 101', 65),
                BxBar('BIO 101', 55),
              ],
              suffix: '%',
            ),
          ),
          const SizedBox(height: BxSpace.sm),
          const BxCard(child: BxSparkline(points: [40, 55, 48, 72, 66, 81, 90])),
          const SizedBox(height: BxSpace.sm),
          const BxCard(
            child: BxMeterRow(
              label: 'PHY 101',
              sublabel: 'General Physics I',
              fraction: 0.8,
              trailing: '12 missed',
            ),
          ),
        ]),
        dark: dark,
      ));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty chart does not divide by zero in $label',
        (tester) async {
      await tester.pumpWidget(host(
        Column(children: [
          BxCard(
            child: BxDonut(data: [
              BxSlice('Correct', 0, dark ? BxColors.dark.success : BxColors.light.success),
              BxSlice('Missed', 0, dark ? BxColors.dark.danger : BxColors.light.danger),
            ]),
          ),
          const BxCard(child: BxBars(data: [BxBar('NONE', 0)])),
          const BxCard(child: BxSparkline(points: [5, 5, 5])),
        ]),
        dark: dark,
      ));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a very narrow screen still lays out cleanly', (tester) async {
    await tester.pumpWidget(host(gallery, dark: false, width: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion primitives settle', (tester) async {
    await tester.pumpWidget(host(
      BxStagger(children: [
        const BxCountUp(1234, style: TextStyle(fontSize: 24)),
        const BxCountUp(97, suffix: '%'),
        BxScaleTap(onTap: () {}, child: const BxCard(child: Text('Tap me'))),
        const BxSwitcher(child: Text('Content')),
      ]),
      dark: false,
    ));
    // Step the clock: a ticker records its start time on the first tick,
    // so one large pump would leave the animation at zero.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('1,234'), findsOneWidget,
        reason: 'CountUp formats with thousands separators');
    await tester.tap(find.text('Tap me'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every accent resolves in both palettes', (tester) async {
    for (final a in BxAccent.values) {
      for (final palette in [BxColors.light, BxColors.dark]) {
        expect(a.fill(palette), isA<Color>());
        expect(a.stroke(palette), isA<Color>());
        expect(a.ink(palette), isA<Color>());
      }
    }
  });
}

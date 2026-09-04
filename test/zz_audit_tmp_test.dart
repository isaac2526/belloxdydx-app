import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/ui/ui.dart';
import 'package:belloxdydx/features/auth/auth_brand.dart';

Size gSize = const Size(320, 568);

Widget host(Widget child) => MediaQuery(
      data: MediaQueryData(size: gSize, textScaler: const TextScaler.linear(1.35)),
      child: MaterialApp(theme: bxLightTheme, home: Scaffold(body: child)),
    );

Widget lockFace() => SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BxAuthBrand(size: 72),
                const SizedBox(height: 20),
                Text('Lock this to you', style: BxType.h1(Colors.black)),
                const SizedBox(height: 8),
                Text(
                  'From now on Belloxdydx opens with your own '
                  'fingerprint, face or screen PIN — the same one '
                  'that opens this phone. Nobody who picks it up '
                  'gets into your account. Touch the sensor once '
                  'to set it.',
                  style: BxType.body(Colors.black),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                BxButton('Set it now',
                    icon: Icons.fingerprint_rounded,
                    expand: true,
                    large: true,
                    onPressed: () {}),
                const SizedBox(height: 12),
                TextButton(onPressed: () {}, child: const Text('Not now')),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> loadFonts() async {
  for (final f in ['Inter', 'SpaceGrotesk', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });
  testWidgets('shelf chip 320dp x1.35', (t) async {
    gSize = const Size(320, 568);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(Padding(
      padding: const EdgeInsets.all(16),
      child: BxCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('CHM 101'),
              BxChip('Change waiting · download now',
                  accent: BxAccent.warning,
                  icon: Icons.sync_problem_rounded,
                  dense: true),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ]),
      ),
    )));
    print('>>> CHIP320: ${t.takeException()}');
  });

  testWidgets('shelf chip 360dp x1.35', (t) async {
    gSize = const Size(360, 640);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(Padding(
      padding: const EdgeInsets.all(16),
      child: BxCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('CHM 101'),
              BxChip('Change waiting · download now',
                  accent: BxAccent.warning,
                  icon: Icons.sync_problem_rounded,
                  dense: true),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ]),
      ),
    )));
    print('>>> CHIP360: ${t.takeException()}');
  });

  testWidgets('lock face 320x568 x1.35', (t) async {
    gSize = const Size(320, 568);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(lockFace()));
    print('>>> LOCK320: ${t.takeException()}');
  });

  testWidgets('lock face 360x640 x1.35', (t) async {
    gSize = const Size(360, 640);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(lockFace()));
    print('>>> LOCK360: ${t.takeException()}');
  });

  testWidgets('lock face 412x915 x1.35 (modern phone)', (t) async {
    gSize = const Size(412, 915);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(lockFace()));
    print('>>> LOCK412: ${t.takeException()}');
  });

  testWidgets('download progress row 320dp x1.35', (t) async {
    gSize = const Size(320, 568);
    t.view.physicalSize = gSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(Padding(
      padding: const EdgeInsets.all(16),
      child: BxCard(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(
            child: Text('12 of 47 · 8.4 MB', style: BxType.tiny(Colors.grey)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.signal_cellular_alt_rounded, size: 13),
            const SizedBox(width: 4),
            Text('Mobile data · 245 KB/s', style: BxType.tiny(Colors.grey)),
          ]),
        ]),
      ),
    )));
    print('>>> PROGROW320: ${t.takeException()}');
  });
}

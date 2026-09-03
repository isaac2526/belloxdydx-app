import 'dart:io';

import 'package:belloxdydx/core/theme/app_theme.dart';
import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:belloxdydx/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Voice notes and pictures inside a note body.
///
/// Two things were broken here and both were invisible from the code:
///
///   · `flutter_widget_from_html_core` supports NO media elements at
///     all — no `<audio>`, no `<video>`, no `<iframe>`. A voice note
///     embedded in a lecture note was not failing to play. It was not
///     on the page. Nothing rendered, nothing errored, and the student
///     had no way to know a recording existed.
///
///   · Every picture went to the network even after a sync had put the
///     file on the phone, because the package knows nothing about the
///     offline root.
///
/// What these tests deliberately do NOT claim: that audio decodes.
/// just_audio has no Linux implementation, so real playback can only be
/// checked on a device. The part that WAS missing — choosing the saved
/// copy over the network, and putting a player on the page at all — is
/// exactly what is checked here.
/// No test here should ever open a socket. Without this the picture
/// tests sit waiting on a real request to a real host — which is both
/// slow and a lie, since what is being checked is which SOURCE the
/// widget chooses, not whether the internet works.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _DeadClient();
}

class _DeadClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('offline in tests'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late OfflineStore store;

  const storage = 'https://proj.supabase.co/storage/v1/object/public';
  const audioUrl = '$storage/materials/audio/tutor.mp3';
  const imageUrl = '$storage/materials/images/diagram.png';

  setUp(() async {
    HttpOverrides.global = _NoNetwork();
    docs = await Directory.systemTemp.createTemp('bx_media_test');
    PathProviderPlatform.instance = _FakePaths(docs.path);
    final opened = await OfflineStore.open();
    store = opened!;
    Offline.store = store;
  });

  tearDown(() async {
    HttpOverrides.global = null;
    Offline.store = null;
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Widget host(Widget child) => MaterialApp(
        theme: bxLightTheme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  // ------------------------------------------------------------
  group('a voice note plays from the phone when the phone has it', () {
    test('the saved copy wins', () async {
      await store.putAsset(audioUrl, List<int>.filled(64, 1));
      final src = await resolveAudioSource(audioUrl);
      expect(src.isLocal, isTrue);
      expect(src.url, isNull);
      expect(File(src.path!).existsSync(), isTrue);
    });

    test('the network answers when there is no saved copy', () async {
      final src = await resolveAudioSource(audioUrl);
      expect(src.isLocal, isFalse);
      expect(src.url, audioUrl);
    });

    test('a catalogue entry whose file has gone falls back, not over',
        () async {
      await store.putAsset(audioUrl, [1, 2, 3]);
      final path = store.assetPath(audioUrl)!;
      await File(path).delete();

      final src = await resolveAudioSource(audioUrl);
      expect(src.isLocal, isFalse,
          reason: 'a stale entry must not silence the clip');
      expect(src.url, audioUrl);
    });

    test('one saved copy serves both backend paths', () async {
      // The legacy path wraps storage URLs through the website; the
      // direct path does not. A student whose app flips between them
      // must not lose their downloads.
      await store.putAsset(audioUrl, [7, 7, 7]);
      const proxied = 'https://belloxdydx.org/api/file?u='
          'aHR0cHM6Ly9wcm9qLnN1cGFiYXNlLmNvL3N0b3JhZ2UvdjEvb2JqZWN0L3B1YmxpYy9t'
          'YXRlcmlhbHMvYXVkaW8vdHV0b3IubXAz';
      final src = await resolveAudioSource(proxied);
      expect(src.isLocal, isTrue);
    });

    test('nothing at all is reported as nothing, not as a failure',
        () async {
      final src = await resolveAudioSource('   ');
      expect(src.isMissing, isTrue);
    });
  });

  // ------------------------------------------------------------
  group('<audio> inside a note body becomes a player', () {
    testWidgets('it is on the page at all', (tester) async {
      await tester.pumpWidget(host(const BxHtml(
        '<p>Listen to this part.</p>'
        '<audio controls src="$audioUrl" title="Tutor Bello explains"></audio>',
      )));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BxAudio), findsOneWidget,
          reason: 'the core package renders <audio> as NOTHING');
      expect(find.text('Tutor Bello explains'), findsOneWidget,
          reason: 'the title is what a student reads before tapping');
      // findRichText, because HtmlWidget lays paragraphs out as
      // RichText rather than as Text widgets.
      expect(find.text('Listen to this part.', findRichText: true),
          findsOneWidget,
          reason: 'the surrounding text must survive');
    });

    testWidgets('a <source> child is found too', (tester) async {
      await tester.pumpWidget(host(const BxHtml(
        '<audio controls><source src="$audioUrl" type="audio/mpeg"></audio>',
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BxAudio), findsOneWidget);
    });

    testWidgets('several voice notes in one body all appear', (tester) async {
      await tester.pumpWidget(host(const BxHtml(
        '<audio src="$audioUrl" title="First"></audio>'
        '<p>then</p>'
        '<audio src="$audioUrl" title="Second"></audio>'
        '<audio src="$audioUrl" title="Third"></audio>',
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BxAudio), findsNWidgets(3),
          reason: 'a note with three recordings must show three players');
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget);
    });

    testWidgets('an <audio> with no source is dropped, not drawn broken',
        (tester) async {
      await tester.pumpWidget(host(const BxHtml('<audio controls></audio>')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BxAudio), findsNothing);
    });

    testWidgets('a video says so instead of leaving a silent hole',
        (tester) async {
      await tester.pumpWidget(host(const BxHtml(
        '<video src="https://x.test/a.mp4"></video>',
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Video'), findsOneWidget);
      expect(find.textContaining('Watch tab'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------
  group('pictures', () {
    testWidgets('a saved one is drawn from disk, not fetched', (tester) async {
      // A real 1x1 PNG, byte for byte. An invalid one leaves the
      // decoder waiting and the test never returns.
      final png = <int>[
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, //
        0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, //
        68, 65, 84, 120, 218, 99, 252, 207, 192, 80, 15, 0, 4, 133, 1, 128, //
        132, 169, 140, 33, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
      ];
      // runAsync, because testWidgets fakes the clock: an await on real
      // file I/O inside it never completes and the test simply stops.
      await tester.runAsync(() => store.putAsset(imageUrl, png));

      await tester.pumpWidget(host(const BxImage(imageUrl: imageUrl)));
      await tester.pump();

      // The PROVIDER is what is under test — where the bytes come from.
      // Waiting for a decode would only be testing the codec.
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
        findsOneWidget,
        reason: 'a synced picture must come off the disk, not the network',
      );
    });

    testWidgets('one that is not saved hands over to the network loader',
        (tester) async {
      await tester.pumpWidget(host(const BxImage(imageUrl: imageUrl)));
      await tester.pump(const Duration(milliseconds: 300));
      // No FileImage, because there is no file — the widget did not
      // invent one, and did not draw the URL either.
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
        findsNothing,
      );
    });

    testWidgets('a broken picture never shows a URL', (tester) async {
      await tester.pumpWidget(host(BxNetworkImage(
        imageUrl,
        empty: const Text('nothing here'),
      )));
      await tester.pump(const Duration(milliseconds: 300));

      // Whatever it draws, it must not be the address.
      for (final e in find.byType(Text).evaluate()) {
        final t = (e.widget as Text).data ?? '';
        expect(t.contains('http'), isFalse,
            reason: 'a raw URL on screen is the bug this replaced: "$t"');
        expect(t.contains('/api/file'), isFalse);
      }
    });

    testWidgets('no picture at all draws the caller\'s own empty state',
        (tester) async {
      await tester.pumpWidget(host(const BxNetworkImage(
        '',
        empty: Text('No diagram'),
      )));
      await tester.pump();
      expect(find.text('No diagram'), findsOneWidget);
    });
  });
}

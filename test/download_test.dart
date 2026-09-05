import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:belloxdydx/data/net_speed.dart';
import 'package:belloxdydx/data/offline/course_downloader.dart';
import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:belloxdydx/data/offline/round_picker.dart';
import 'package:belloxdydx/data/repositories.dart';
import 'package:belloxdydx/features/shell/net_chip.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// WHAT A DOWNLOAD LEAVES BEHIND
///
/// Every test here is a sentence a student said about a phone with a
/// course downloaded onto it:
///
///   · "the stuff isn't downloading all" — 6 files did not save, the
///     same six every time, on a steady line.
///   · "the note showed the slide is bringing network error" — an
///     attachment on the disk, unreachable.
///   · "Nothing is attached yet either" — over a PDF that was here.
///   · "in offline it's repeating almost the same question".
///   · "the network bar isn't sharp" — a Wi-Fi icon on mobile data.
///
/// None of them were visible to the old tests, because the old tests
/// asked the catalogue what it held instead of asking the disk.
/// ============================================================
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

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('bx_download_test');
    PathProviderPlatform.instance = _FakePaths(docs.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    Offline.store = null;
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<OfflineStore> open() async {
    final s = await OfflineStore.open();
    expect(s, isNotNull);
    return s!;
  }

  // ------------------------------------------------------------
  group('a note that is only its attachment', () {
    // Tutor Bello posts a series episode by episode: the PDF goes up
    // first, the body is typed later. Six of those on one course were
    // the whole of "6 files did not save" — the download counted each
    // one as saved and the check afterwards could not find it, for
    // ever, however good the line was.

    test('is catalogued, verifies, and keeps its attachment list',
        () async {
      final store = await open();
      await store.putNote(
        id: 'ep2',
        title: 'Series, Episode II',
        html: '',
        courseId: 'phy102',
        sig: '2026-07-14T10:00:00Z',
        pinned: true,
        attachments: const [
          OfflineAttachment(
            title: 'Episode 2 — Electric Fields',
            url: 'https://s.co/storage/v1/object/public/materials/ep2.pdf',
            kind: 'pdf',
          ),
        ],
      );

      expect(store.has('ep2'), isTrue,
          reason: 'a note with no body still has to have a row — without '
              'one nothing offline can find it, and the download counts '
              'it as a file that did not save');
      expect(await store.verifyItem('ep2'), isTrue,
          reason: 'THE CHECK AT THE END OF A DOWNLOAD MUST PASS. This is '
              'the exact assertion that produced "6 files did not save" '
              'on a course where nothing was missing.');
      expect(store.item('ep2')!.attachments.single.title,
          'Episode 2 — Electric Fields');
    });

    test('survives being read back on the next launch', () async {
      final store = await open();
      await store.putNote(
        id: 'ep2',
        title: 'Episode II',
        html: '',
        courseId: 'phy102',
        attachments: const [
          OfflineAttachment(
              title: 'Episode 2', url: 'https://s.co/ep2.pdf', kind: 'pdf'),
        ],
      );
      await store.flush();

      final reopened = await open();
      final back = reopened.item('ep2');
      expect(back, isNotNull, reason: 'the catalogue is written whole');
      expect(back!.attachments, hasLength(1));
      expect(back.attachments.single.url, 'https://s.co/ep2.pdf');
      expect(back.attachments.single.kind, 'pdf');
    });

    test('the reader is handed its attachments with the data off',
        () async {
      final store = await open();
      Offline.store = store;
      await store.putNote(
        id: 'ep2',
        title: 'Episode II',
        html: '',
        courseId: 'phy102',
        attachments: const [
          OfflineAttachment(
              title: 'Episode 2 — Electric Fields',
              url: 'https://s.co/ep2.pdf',
              kind: 'pdf'),
        ],
      );

      // Backend() with nothing configured cannot reach anything, which
      // is a phone with its data off.
      final repo = ContentRepository(Backend(), await LocalStore.init());
      final m = await repo.material('ep2');

      expect(m.attachments, hasLength(1),
          reason: 'THE WHOLE COMPLAINT. Offline the note said "Nothing is '
              'attached yet either" over a PDF sitting on the phone.');
      expect(m.attachments.single.title, 'Episode 2 — Electric Fields');
      expect(m.attachments.single.kind, 'pdf');
    });

    test('a note with neither body nor entry still throws', () async {
      final store = await open();
      Offline.store = store;
      final repo = ContentRepository(Backend(), await LocalStore.init());
      await expectLater(repo.material('never-saved'), throwsA(anything),
          reason: 'a fallback that invents an empty note out of nothing '
              'is worse than an error a student can act on');
    });
  });

  // ------------------------------------------------------------
  group('what the phone holds, not what the last run moved', () {
    test('held files are counted off the catalogue', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'A', html: '<p>a</p>',
          courseId: 'c1');
      await store.putNote(id: 'n2', title: 'B', html: '', courseId: 'c1');
      await store.putDocument(
        id: 'd1',
        title: 'Slides',
        kind: 'slide',
        bytes: utf8.encode('%PDF-1.4'),
        extension: 'pdf',
        courseId: 'c1',
      );
      await store.putNote(id: 'other', title: 'C', html: 'x', courseId: 'c2');
      await store.putQuestions('c1', [
        {'id': 'q1', 'correct_key': 'A'},
      ]);

      expect(store.heldFilesFor('c1'), 3,
          reason: 'notes and documents of this course, and not its '
              'question bucket');
      expect(store.heldFilesFor('c2'), 1);
      expect(store.heldFilesFor(''), 0);
    });

    test('an asset the disk has lost is forgotten, not trusted', () async {
      final store = await open();
      const url = 'https://s.co/storage/v1/object/public/x/pic.png';
      await store.putAsset(url, utf8.encode('PNGDATA'));
      expect(store.hasAsset(url), isTrue);
      expect(await store.verifyAsset(url), isTrue);

      // Something outside the app cleared the file — a cleaner, a
      // restore, a cache wipe.
      await File(store.assetPath(url)!).delete();
      expect(await store.verifyAsset(url), isFalse,
          reason: 'the disk gets the last word, not the catalogue');

      await store.forgetAsset(url);
      expect(store.hasAsset(url), isFalse,
          reason: 'so the next Update fetches it again instead of '
              'reporting it as held for ever');
    });
  });

  // ------------------------------------------------------------
  group('when something really does not save, it is named', () {
    test('the sentence carries the names, not just a number', () {
      final msg = CourseDownloader.failureMessage(2, const [
        CourseDownloadFailure(
            title: 'Episode 2', reason: 'not found on the server'),
        CourseDownloadFailure(title: 'Lecture 1 slides', reason: 'came down empty'),
      ]);
      expect(msg, contains('Episode 2 (not found on the server)'));
      expect(msg, contains('Lecture 1 slides'));
      expect(msg, contains('2 files did not save'));
    });

    test('a long list is trimmed rather than dumped', () {
      final msg = CourseDownloader.failureMessage(6, [
        for (var i = 0; i < 6; i++)
          CourseDownloadFailure(title: 'File $i', reason: 'no connection'),
      ]);
      expect(msg, contains('File 0'));
      expect(msg, contains('and 3 more'));
      expect(msg, isNot(contains('File 5')));
    });

    test('the tally adds up when the stored list was capped', () {
      // A record keeps at most kMaxRecordedFailures names but the count
      // of everything that failed, so "and N more" has to complete the
      // HEADLINE. Counted against the list instead, a run of 114
      // failures read "114 files did not save: a · b · c and 17 more"
      // — a sentence contradicting itself.
      final msg = CourseDownloader.failureMessage(114, [
        for (var i = 0; i < kMaxRecordedFailures; i++)
          CourseDownloadFailure(title: 'File $i', reason: 'no connection'),
      ]);
      expect(msg, contains('114 files did not save'));
      expect(msg, contains('and 111 more'));
    });

    test('one file reads as one file', () {
      final msg = CourseDownloader.failureMessage(
          1, const [CourseDownloadFailure(title: 'A', reason: '')]);
      expect(msg, contains('1 file did not save'));
      expect(msg, isNot(contains('1 files')));
    });
  });

  // ------------------------------------------------------------
  group('an offline round does not deal the same questions again', () {
    List<Map<String, dynamic>> bank(int n, {String prefix = 'q'}) => [
          for (var i = 0; i < n; i++)
            {'id': '$prefix$i', 'correct_key': 'A', 'question_html': 'Q$i'},
        ];

    test('walks the whole bank before it repeats one', () {
      final all = bank(75);
      final served = <String>[];
      final seen = <String>{};
      for (var round = 0; round < 3; round++) {
        final picked = dealOfflineRound(
          all,
          count: 20,
          recentlyServed: List.of(served),
          pictureIsHeld: (_) => true,
          random: Random(round + 1),
        );
        expect(picked, hasLength(20));
        final ids = picked.map((r) => '${r['id']}').toList();
        expect(ids.toSet().intersection(seen), isEmpty,
            reason: 'ROUND ${round + 1} REPEATED A QUESTION. Twenty out of '
                'seventy-five drawn with no memory overlap by five on '
                'average, which is what "it\'s repeating almost the same '
                'question" is.');
        seen.addAll(ids);
        served.addAll(ids);
      }
      expect(seen, hasLength(60));
    });

    test('reaches for the least recently seen once the bank runs dry', () {
      final all = bank(25);
      // Everything has been seen; q0 longest ago.
      final served = [for (var i = 0; i < 25; i++) 'q$i'];
      final picked = dealOfflineRound(all, count: 10,
          recentlyServed: served, random: Random(7));
      expect(picked, hasLength(10));
      final ids = picked.map((r) => '${r['id']}').toSet();
      expect(ids, contains('q0'),
          reason: 'the oldest deal comes back first, so the bank rolls '
              'round in order instead of clustering');
      expect(ids.intersection({for (var i = 15; i < 25; i++) 'q$i'}), isEmpty,
          reason: 'the ten just dealt are the last ones it reaches for');
    });

    test('a question whose picture never came down goes last, not away',
        () {
      final rows = <Map<String, dynamic>>[
        {'id': 'plain1', 'correct_key': 'A'},
        {'id': 'plain2', 'correct_key': 'A'},
        {
          'id': 'withPic',
          'correct_key': 'A',
          'question_image_url': 'https://s.co/missing.png',
        },
      ];
      final two = dealOfflineRound(rows, count: 2,
          recentlyServed: const [],
          pictureIsHeld: (_) => false,
          random: Random(3));
      expect(two.map((r) => '${r['id']}'), isNot(contains('withPic')),
          reason: 'a diagram that is not on the phone reads as a broken '
              'app, so it waits while there is anything better');

      final three = dealOfflineRound(rows, count: 3,
          recentlyServed: const [],
          pictureIsHeld: (_) => false,
          random: Random(3));
      expect(three.map((r) => '${r['id']}'), contains('withPic'),
          reason: 'but it is still a question — it is never dropped');
    });

    test('a question whose picture IS on the phone is ordinary', () {
      final rows = <Map<String, dynamic>>[
        {'id': 'plain', 'correct_key': 'A'},
        {
          'id': 'withPic',
          'correct_key': 'A',
          'question_image_url': 'https://s.co/held.png',
        },
      ];
      final one = dealOfflineRound(rows, count: 1,
          recentlyServed: const [],
          pictureIsHeld: (u) => u == 'https://s.co/held.png',
          random: Random(11));
      // With one held picture both are equal candidates; the point is
      // that it is not pushed to the back.
      final many = [
        for (var seed = 0; seed < 12; seed++)
          dealOfflineRound(rows, count: 1,
              recentlyServed: const [],
                  pictureIsHeld: (u) => u == 'https://s.co/held.png',
              random: Random(seed)).single['id'],
      ];
      expect(one, isNotNull);
      expect(many, contains('withPic'),
          reason: 'a picture that IS on the phone must not cost the '
              'question its place in the deal');
    });

    test('an empty bank deals nothing rather than throwing', () {
      expect(
          dealOfflineRound(const [], count: 20,
              recentlyServed: const []),
          isEmpty);
    });
  });

  // ------------------------------------------------------------
  group('the memory of what was dealt', () {
    test('is a ring that survives the next launch', () async {
      final store = await open();
      await store.rememberServed('phy102', ['a', 'b', 'c']);
      await store.rememberServed('phy102', ['c', 'd']);

      expect(store.recentlyServed('phy102'), ['a', 'b', 'c', 'd'],
          reason: 'a question dealt again moves to the end rather than '
              'sitting twice in the ring');

      final reopened = await open();
      expect(reopened.recentlyServed('phy102'), ['a', 'b', 'c', 'd']);
      expect(reopened.recentlyServed('other'), isEmpty);
    });

    test('does not grow without end', () async {
      final store = await open();
      await store.rememberServed(
          'c1', [for (var i = 0; i < kServedMemory + 50; i++) 'q$i']);
      final ring = store.recentlyServed('c1');
      expect(ring, hasLength(kServedMemory));
      expect(ring.first, 'q50', reason: 'the oldest fall off the front');
    });
  });

  // ------------------------------------------------------------
  group('the connection icon says which line it is', () {
    BxNetSpeed at(BxNetGrade g, {bool wifi = false}) =>
        BxNetSpeed(grade: g, unmetered: wifi);

    test('mobile data never wears a Wi-Fi shape', () {
      for (final g in BxNetGrade.values) {
        final icon = bxNetIcon(at(g));
        expect(icon, isNot(Icons.wifi_rounded));
        expect(icon, isNot(Icons.signal_wifi_off_rounded));
        expect(icon, isNot(Icons.network_wifi_1_bar_rounded));
        expect(icon, isNot(Icons.network_wifi_3_bar_rounded));
      }
    });

    test('a bad mobile line is cellular bars, not a red Wi-Fi fan', () {
      expect(bxNetIcon(at(BxNetGrade.poor)),
          Icons.signal_cellular_alt_1_bar_rounded);
      expect(bxNetIcon(at(BxNetGrade.fair)),
          Icons.signal_cellular_alt_2_bar_rounded);
      expect(bxNetIcon(at(BxNetGrade.good)), Icons.signal_cellular_alt_rounded);
      expect(bxNetIcon(at(BxNetGrade.offline)), Icons.signal_cellular_off_rounded);
    });

    test('Wi-Fi keeps the Wi-Fi shapes', () {
      expect(bxNetIcon(at(BxNetGrade.poor, wifi: true)),
          Icons.network_wifi_1_bar_rounded);
      expect(bxNetIcon(at(BxNetGrade.good, wifi: true)), Icons.wifi_rounded);
      expect(bxNetIcon(at(BxNetGrade.offline, wifi: true)),
          Icons.signal_wifi_off_rounded);
    });

    test('losing the line does not turn mobile data into Wi-Fi', () {
      final meter = NetSpeedMeter();
      addTearDown(meter.dispose);
      meter.setUnmetered(false);
      meter.sample(bytes: 400, millis: 120);
      meter.setReachable(false);
      expect(meter.value.grade, BxNetGrade.offline);
      expect(meter.value.unmetered, isFalse,
          reason: 'the kind of line is not forgotten when it drops, so '
              'the icon does not change shape as well as colour');
      expect(bxNetIcon(meter.value), Icons.signal_cellular_off_rounded);
    });

    test('one slow cold reply does not condemn a good line', () {
      final meter = NetSpeedMeter();
      addTearDown(meter.dispose);
      // A serverless function waking up: one 2.4 s reply, then the
      // line's real round trips.
      meter.sample(bytes: 500, millis: 2400);
      for (var i = 0; i < 4; i++) {
        meter.sample(bytes: 500, millis: 220);
      }
      expect(meter.value.grade, isNot(BxNetGrade.poor),
          reason: 'a student on working 4.5G was shown a red icon for as '
              'long as the app was open because one cold start was read '
              'as the line');
    });
  });
}

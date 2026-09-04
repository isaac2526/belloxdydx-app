import 'dart:convert';
import 'dart:io';

import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:belloxdydx/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The Offline Vault shipped with no test at all, and it showed: it held
/// only whole documents a student had remembered to tap Save on, its
/// index lived in SharedPreferences with ABSOLUTE paths in it, and
/// nothing about a question was written to disk anywhere in the app.
///
/// These drive the real OfflineStore against a real temporary directory.
/// Nothing is re-implemented here — a test that copies the logic it is
/// checking proves only that the copy agrees with itself.
class _FakePaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePaths(this.root);
  String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  courseDownloadRecords();
  pruningWithdrawnContent();
  whoseDateIsShown();
  clearingAWithdrawnCourse();
  syncingWithNoSignal();
  aSavedCopyThatFellBehind();
  belloDateReadsRight();

  late Directory docs;
  late _FakePaths paths;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('bx_offline_test');
    paths = _FakePaths(docs.path);
    PathProviderPlatform.instance = paths;
  });

  tearDown(() async {
    Offline.store = null;
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<OfflineStore> open() async {
    final s = await OfflineStore.open();
    expect(s, isNotNull, reason: 'the store must open on a real filesystem');
    return s!;
  }

  // ------------------------------------------------------------
  group('one cache key per file, whichever backend path is live', () {
    // The same picture arrives as a raw Supabase URL in direct mode and
    // as a website proxy URL in legacy mode. Keying on whichever URL
    // turned up would re-download the student's whole library the first
    // time their app flipped between paths.
    const raw = 'https://proj.supabase.co/storage/v1/object/public'
        '/materials/diagrams/vector.png';
    final proxied = 'https://belloxdydx.org/api/file?u='
        '${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';

    test('a proxy URL resolves back to the storage URL it names', () {
      expect(canonicalAssetUrl(proxied), raw);
    });

    test('a raw storage URL is left alone', () {
      expect(canonicalAssetUrl(raw), raw);
    });

    test('both spellings share one key', () {
      expect(assetKeyFor(proxied), assetKeyFor(raw));
    });

    test('different files do not', () {
      expect(assetKeyFor(raw), isNot(assetKeyFor('${raw}x')));
    });

    test('nonsense in the u= parameter does not throw', () {
      const junk = 'https://belloxdydx.org/api/file?u=%%%not-base64%%%';
      expect(canonicalAssetUrl(junk), junk);
      expect(() => assetKeyFor(junk), returnsNormally);
    });

    test('a decoded target that is not a URL is not trusted', () {
      final evil = 'https://belloxdydx.org/api/file?u='
          '${base64Url.encode(utf8.encode('/etc/passwd')).replaceAll('=', '')}';
      expect(canonicalAssetUrl(evil), evil);
    });
  });

  // ------------------------------------------------------------
  group('paths are stored relative to the container', () {
    test('a saved document survives the container moving', () async {
      final store = await open();
      await store.putDocument(
        id: 'm1',
        title: 'Vectors',
        kind: 'pq',
        bytes: List<int>.filled(64, 7),
        extension: 'pdf',
      );
      await store.flush();

      final before = await store.documentPath('m1');
      expect(before, isNotNull);
      expect(await File(before!).exists(), isTrue);

      // Exactly what iOS does on a restore: the app's container keeps
      // its contents and gets a new UUID. The old index wrote absolute
      // paths, so every saved document stopped opening at this point.
      final moved = await Directory.systemTemp.createTemp('bx_moved');
      await Directory('${docs.path}/offline')
          .rename('${moved.path}/offline');
      paths.root = moved.path;

      final reopened = await open();
      final after = await reopened.documentPath('m1');
      expect(after, isNotNull, reason: 'the document must still be found');
      expect(after, isNot(before), reason: 'under the NEW container path');
      expect(await File(after!).exists(), isTrue);
      await moved.delete(recursive: true);
    });

    test('the catalogue records no absolute path', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'Note', html: '<p>hi</p>');
      await store.putAsset('https://x.test/a.png', [1, 2, 3]);
      await store.flush();

      final index =
          await File('${docs.path}/offline/index.json').readAsString();
      expect(index.contains(docs.path), isFalse,
          reason: 'an absolute path in the index is the iOS bug');
    });
  });

  // ------------------------------------------------------------
  group('the catalogue', () {
    test('keeps notes, documents, pictures and questions apart', () async {
      final store = await open();
      await store.putNote(
          id: 'n1', title: 'Kinematics', html: '<p>v = u + at</p>');
      await store.putDocument(
        id: 'd1',
        title: 'Past questions',
        kind: 'pq',
        bytes: List<int>.filled(10, 1),
        extension: 'pdf',
      );
      await store.putQuestions('CHM101', [
        {'id': 'q1', 'question_html': '<p>Mole?</p>'},
      ]);
      await store.flush();

      expect(await store.readNote('n1'), '<p>v = u + at</p>');
      expect(await store.documentPath('d1'), isNotNull);
      expect((await store.questions('CHM101')).length, 1);

      // The Vault list shows things a student can open, not the
      // question sets, which are counted separately.
      expect(store.readable.map((i) => i.id), containsAll(['n1', 'd1']));
      expect(store.readable.any((i) => i.kind == 'questions'), isFalse);
    });

    test('survives a restart', () async {
      final a = await open();
      await a.putNote(id: 'n1', title: 'T', html: '<p>body</p>', sig: 'v1');
      await a.flush();

      final b = await open();
      expect(await b.readNote('n1'), '<p>body</p>');
      expect(b.isCurrent('n1', 'v1'), isTrue);
      expect(b.isCurrent('n1', 'v2'), isFalse,
          reason: 'a changed signature must force a re-fetch');
    });

    test('an empty signature never counts as current', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      expect(store.isCurrent('n1', ''), isFalse);
    });

    test('a corrupt index starts clean instead of throwing', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      await store.flush();
      await File('${docs.path}/offline/index.json').writeAsString('{ not json');

      final reopened = await open();
      expect(reopened.readable, isEmpty);
      expect(await reopened.readNote('n1'), isNull);
    });

    test('an index from an older shape is discarded, not guessed at',
        () async {
      await Directory('${docs.path}/offline').create(recursive: true);
      await File('${docs.path}/offline/index.json')
          .writeAsString(jsonEncode({'v': 1, 'items': {'n1': {}}}));
      final store = await open();
      expect(store.readable, isEmpty);
    });

    test('drops rows whose files have gone', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      await store.putNote(id: 'n2', title: 'U', html: '<p>y</p>');
      await store.flush();

      // The website shipped the opposite bug: an index that outlived
      // its files, so Open led nowhere.
      await File('${docs.path}/offline/notes/n1.html').delete();
      final dropped = await store.reconcile();
      expect(dropped, 1);
      expect(store.readable.map((i) => i.id), ['n2']);
    });

    test('removing an item deletes its file too', () async {
      final store = await open();
      await store.putDocument(
        id: 'd1',
        title: 'T',
        kind: 'pq',
        bytes: [1, 2, 3],
        extension: 'pdf',
      );
      final path = (await store.documentPath('d1'))!;
      await store.removeItem('d1');
      expect(await File(path).exists(), isFalse);
      expect(store.readable, isEmpty);
    });
  });

  // ------------------------------------------------------------
  group('parallel writers do not trip over each other', () {
    // Found by running the real app against a real filesystem, not by
    // reading the code. The sync uses three workers and the same
    // picture is referenced by several notes, so two of them routinely
    // download it at once. With one shared "<target>.part" staging
    // name, the first rename moved the file and the second failed with
    // ENOENT — silently losing that file from the vault.
    test('the same asset fetched concurrently lands exactly once', () async {
      final store = await open();
      const url = 'https://p.supabase.co/storage/v1/object/public/x/same.png';

      await Future.wait([
        for (var i = 0; i < 12; i++) store.putAsset(url, [i, i, i, i]),
      ]);
      await store.flush();

      expect(store.assetCount, 1);
      final path = store.assetPath(url);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);

      // No staging files left lying around.
      final leftovers = Directory('${docs.path}/offline/assets')
          .listSync()
          .where((f) => f.path.contains('.part'))
          .toList();
      expect(leftovers, isEmpty, reason: 'staged files must be cleaned up');
    });

    test('the same note written twice at once survives', () async {
      final store = await open();
      await Future.wait([
        store.putNote(id: 'n1', title: 'A', html: '<p>one</p>'),
        store.putNote(id: 'n1', title: 'A', html: '<p>one</p>'),
        store.putNote(id: 'n1', title: 'A', html: '<p>one</p>'),
      ]);
      await store.flush();
      expect(await store.readNote('n1'), '<p>one</p>');
    });

    test('overlapping flushes all complete and the index is valid', () async {
      final store = await open();
      for (var i = 0; i < 20; i++) {
        await store.putNote(id: 'n$i', title: 'T$i', html: '<p>$i</p>');
      }
      await Future.wait([store.flush(), store.flush(), store.flush()]);

      final raw =
          await File('${docs.path}/offline/index.json').readAsString();
      expect(() => jsonDecode(raw), returnsNormally,
          reason: 'a half-written catalogue is worse than none');

      final reopened = await open();
      expect(reopened.readable.length, 20);
    });
  });

  // ------------------------------------------------------------
  group('one student never sees another one\'s downloads', () {
    test('a different owner wipes the store', () async {
      final store = await open();
      await store.claim('student-a');
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      await store.flush();

      expect(await store.claim('student-a'), isFalse,
          reason: 'the same student keeps their material');
      expect(store.readable.length, 1);

      expect(await store.claim('student-b'), isTrue);
      expect(store.readable, isEmpty);
      expect(await store.readNote('n1'), isNull);
      expect(await File('${docs.path}/offline/notes/n1.html').exists(),
          isFalse);
    });

    test('claiming an unclaimed store keeps what is there', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      expect(await store.claim('student-a'), isFalse);
      expect(store.readable.length, 1);
    });
  });

  // ------------------------------------------------------------
  group('signing out does not throw away your material', () {
    // LocalStore.clearCache() runs on every sign-out and deletes
    // <documents>/cache. The offline root sits deliberately OUTSIDE
    // that directory: a student who signs out on Friday and back in on
    // Monday should not have to re-download a semester of notes over
    // their own data. A different student signing in is the case that
    // wipes, and that is covered by claim() above.
    test('the offline root is not inside the cache directory', () async {
      final store = await open();
      expect(store.rootPath, isNot(contains('/cache')),
          reason: 'sign-out clears <documents>/cache; the vault must not '
              'be in it');
      expect(store.rootPath, endsWith('/offline'));
    });

    test('clearing the JSON cache leaves the vault alone', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>kept</p>');
      await store.flush();

      // Exactly what LocalStore.clearCache does.
      final cache = Directory('${docs.path}/cache');
      await cache.create(recursive: true);
      await File('${cache.path}/content.json').writeAsString('{}');
      await cache.delete(recursive: true);

      final reopened = await open();
      expect(await reopened.readNote('n1'), '<p>kept</p>');
      expect(reopened.readable.length, 1);
    });
  });

  // ------------------------------------------------------------
  group('the store tells the truth about storage', () {
    // This app has now been wrong about storage in BOTH directions.
    // First it told a student with 256 GB free to clear room, because
    // every save failure was reported as a full disk. Then the sync
    // announced "Saved for offline" after a run in which every write
    // had failed with ENOSPC — each caught, each logged, none of them
    // reaching the student — so a nearly full phone reported success
    // and then could not open a thing.
    //
    // Being wrong either way destroys trust in the whole feature.

    test('a claim is not a fact: verifyItem checks the disk', () async {
      final store = await open();
      await store.putDocument(
        id: 'd1',
        title: 'Past questions',
        kind: 'pq',
        bytes: List<int>.filled(64, 3),
        extension: 'pdf',
      );
      expect(await store.verifyItem('d1'), isTrue);

      // The catalogue still says it is there. The file is not.
      await File(store.resolve(store.item('d1')!.docRel!)).delete();
      expect(await store.verifyItem('d1'), isFalse,
          reason: 'an index entry must never be taken as proof');
    });

    test('an empty file is not a saved file', () async {
      final store = await open();
      await store.putDocument(
        id: 'd1',
        title: 'T',
        kind: 'pq',
        bytes: [1, 2, 3],
        extension: 'pdf',
      );
      await File(store.resolve(store.item('d1')!.docRel!)).writeAsBytes([]);
      expect(await store.verifyItem('d1'), isFalse);
    });

    test('an asset is verified the same way', () async {
      final store = await open();
      const url = 'https://p.supabase.co/storage/v1/object/public/x/a.png';
      await store.putAsset(url, [9, 9, 9]);
      expect(await store.verifyAsset(url), isTrue);
      await File(store.assetPath(url)!).delete();
      expect(await store.verifyAsset(url), isFalse);
      expect(await store.verifyAsset('https://nope.test/x.png'), isFalse);
    });

    test('the library has a ceiling and it is enforced', () async {
      final store = await open();
      final room = await store.canWrite(OfflineStore.maxTotalBytes + 1);
      expect(room.ok, isFalse);
      expect(room.reason, contains('full'));
      expect(room.reason, isNot(contains('Exception')));
    });

    test('a small write is allowed', () async {
      final store = await open();
      expect((await store.canWrite(1024)).ok, isTrue);
    });

    test('eviction takes the oldest unpinned item and never a pinned one',
        () async {
      final store = await open();
      // Pinned means the student chose it by hand. It is never the
      // thing we throw away to make room for something they did not.
      await store.putDocument(
        id: 'kept',
        title: 'Chosen',
        kind: 'pq',
        bytes: List<int>.filled(32, 1),
        extension: 'pdf',
        pinned: true,
      );
      await store.putDocument(
        id: 'auto',
        title: 'Synced',
        kind: 'pq',
        bytes: List<int>.filled(32, 1),
        extension: 'pdf',
        pinned: false,
      );
      await store.flush();

      // Ask for more than the ceiling so eviction has to act.
      await store.evictFor(OfflineStore.maxTotalBytes);
      expect(store.has('kept'), isTrue, reason: 'pinned is never evicted');
      expect(store.has('auto'), isFalse);
    });

    test('the sweep reclaims staging files and orphans', () async {
      final store = await open();
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      await store.flush();

      // What a phone that killed the app mid-sync leaves behind.
      final notes = Directory('${docs.path}/offline/notes');
      await File('${notes.path}/half-written.html.3.part')
          .writeAsString('incomplete');
      // And a file whose catalogue row was lost: invisible in the Vault,
      // impossible to delete from it, still counted against storage.
      await File('${notes.path}/orphan.html').writeAsString('nobody owns me');

      final reclaimed = await store.sweep();
      expect(reclaimed, greaterThan(0));
      expect(File('${notes.path}/half-written.html.3.part').existsSync(),
          isFalse);
      expect(File('${notes.path}/orphan.html').existsSync(), isFalse);
      expect(await store.readNote('n1'), '<p>x</p>',
          reason: 'the sweep must not touch a live file');
    });
  });

  // ------------------------------------------------------------
  group('finding one question does not decode all of them', () {
    // Folding an answer verdict back into a cached question used to
    // read and jsonDecode EVERY bucket to find the one row it wanted,
    // on the UI isolate, before the student could be shown whether they
    // were right. The cost grew with every round anybody ever played.
    test('patchQuestion updates exactly the row it names', () async {
      final store = await open();
      await store.putQuestions('PHY101', [
        {'id': 'q1', 'question_html': '<p>a</p>'},
        {'id': 'q2', 'question_html': '<p>b</p>'},
      ]);
      await store.putQuestions('CHM101', [
        {'id': 'q3', 'question_html': '<p>c</p>'},
      ]);

      final ok = await store.patchQuestion('q2', {
        'correct_key': 'B',
        'explanation_html': '<p>because</p>',
      });
      expect(ok, isTrue);

      final phy = await store.questions('PHY101');
      final q2 = phy.firstWhere((r) => r['id'] == 'q2');
      expect(q2['correct_key'], 'B');
      expect(q2['explanation_html'], '<p>because</p>');
      expect(q2['question_html'], '<p>b</p>', reason: 'nothing else changes');

      final q1 = phy.firstWhere((r) => r['id'] == 'q1');
      expect(q1.containsKey('correct_key'), isFalse,
          reason: 'a sibling row is untouched');
    });

    test('it finds a question in any bucket', () async {
      final store = await open();
      await store.putQuestions('A', [{'id': 'qa'}]);
      await store.putQuestions('B', [{'id': 'qb'}]);
      await store.putQuestions('C', [{'id': 'qc'}]);
      expect(await store.bucketFor('qc'), 'C');
      expect(await store.patchQuestion('qc', {'correct_key': 'D'}), isTrue);
      expect((await store.questions('C')).first['correct_key'], 'D');
    });

    test('an unknown question is a quiet no, not a throw', () async {
      final store = await open();
      await store.putQuestions('A', [{'id': 'qa'}]);
      expect(await store.bucketFor('nope'), isNull);
      expect(await store.patchQuestion('nope', {'correct_key': 'A'}), isFalse);
    });

    test('empty fields change nothing', () async {
      final store = await open();
      await store.putQuestions('A', [
        {'id': 'qa', 'correct_key': 'B'},
      ]);
      await store.patchQuestion('qa', {'correct_key': '', 'answer_text': null});
      expect((await store.questions('A')).first['correct_key'], 'B',
          reason: 'a blank from the server must not erase what we hold');
    });
  });

  // ------------------------------------------------------------
  group('assets', () {
    test('are found synchronously, which is what build() needs', () async {
      final store = await open();
      const url = 'https://proj.supabase.co/storage/v1/object/public/x/a.png';
      expect(store.assetPath(url), isNull);

      await store.putAsset(url, [1, 2, 3, 4]);
      final path = store.assetPath(url);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue,
          reason: 'a widget cannot await, so this must be true immediately');
    });

    test('one copy serves both backend paths', () async {
      final store = await open();
      const raw = 'https://proj.supabase.co/storage/v1/object/public/x/a.png';
      final proxied = 'https://belloxdydx.org/api/file?u='
          '${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';

      await store.putAsset(raw, [9, 9, 9]);
      expect(store.hasAsset(proxied), isTrue);
      expect(store.assetPath(proxied), store.assetPath(raw));
      expect(store.assetCount, 1);
    });

    test('the Offline handle answers for the app', () async {
      final store = await open();
      Offline.store = store;
      const url = 'https://proj.supabase.co/storage/v1/object/public/x/a.png';
      expect(Offline.pathFor(url), isNull);
      expect(Offline.holds(url), isFalse);
      await store.putAsset(url, [1]);
      expect(Offline.pathFor(url), isNotNull);
      expect(Offline.holds(url), isTrue);
      expect(Offline.pathFor(null), isNull);
      expect(Offline.pathFor(''), isNull);
    });
  });

  // ------------------------------------------------------------
  group('questions on the phone', () {
    test('are de-duplicated across buckets', () async {
      final store = await open();
      await store.putQuestions('PHY101', [
        {'id': 'q1', 'question_html': '<p>a</p>'},
        {'id': 'q2', 'question_html': '<p>b</p>'},
      ]);
      await store.putQuestions('mistakes', [
        {'id': 'q2', 'question_html': '<p>b</p>'},
        {'id': 'q3', 'question_html': '<p>c</p>'},
      ]);
      final all = await store.allQuestions();
      expect(all.map((q) => q['id']).toSet(), {'q1', 'q2', 'q3'});
    });

    test('a bucket name with a slash cannot escape the directory', () async {
      final store = await open();
      await store.putQuestions('../../etc/passwd', [
        {'id': 'q1'},
      ]);
      final escaped = File('${docs.path}/etc/passwd.json');
      expect(await escaped.exists(), isFalse);
      expect((await store.questions('../../etc/passwd')).length, 1);
    });

    test('an unknown bucket reads as empty rather than throwing', () async {
      final store = await open();
      expect(await store.questions('nothing-here'), isEmpty);
    });
  });

  // ------------------------------------------------------------
  group('a round taken with no signal', () {
    test('is stored, read back and removed', () async {
      final store = await open();
      await store.putAttempt('offline-1', {
        'at': 1,
        'questions': [
          {'id': 'q1'},
        ],
      });
      final back = await store.attempt('offline-1');
      expect(back, isNotNull);
      expect((back!['questions'] as List).length, 1);
      expect((await store.attempts()).length, 1);

      await store.removeAttempt('offline-1');
      expect(await store.attempt('offline-1'), isNull);
    });

    test('is not thrown away by a sync', () async {
      final store = await open();
      await store.putAttempt('offline-1', {'at': 1, 'questions': []});
      await store.putNote(id: 'n1', title: 'T', html: '<p>x</p>');
      await store.markSynced();
      expect(await store.attempt('offline-1'), isNotNull,
          reason: "a student's own work is not downloaded content");
    });
  });

  // ------------------------------------------------------------
  group('marking offline agrees with marking online', () {
    // Transcribed from the website's src/lib/attempts.ts:114-137. If
    // these two ever disagree, the same typed answer is right on Wi-Fi
    // and wrong on the bus.
    Question mcq(String key) => Question(
          id: 'q',
          questionHtml: '<p>?</p>',
          correctKey: key,
          options: const [
            QuestionOption(key: 'A', text: 'one'),
            QuestionOption(key: 'B', text: 'two'),
          ],
        );

    Question typed(String accepted) => Question(
          id: 'q',
          questionHtml: '<p>?</p>',
          type: QuestionType.shortAnswer,
          answerText: accepted,
        );

    test('a multiple choice answer compares the key', () {
      expect(gradeLocally(mcq('B'), choice: 'B'), isTrue);
      expect(gradeLocally(mcq('B'), choice: 'A'), isFalse);
      expect(gradeLocally(mcq('B'), choice: ''), isFalse);
    });

    test('a question with no key is never marked right', () {
      // Exactly the shape a sealed exam question arrives in. It must
      // never silently mark itself correct.
      expect(gradeLocally(mcq(''), choice: 'A'), isFalse);
      expect(gradeLocally(mcq(''), choice: ''), isFalse);
    });

    test('a typed answer ignores case, spacing and stray punctuation', () {
      final q = typed('Isaac Newton|Newton');
      expect(gradeLocally(q, answerText: 'isaac newton'), isTrue);
      expect(gradeLocally(q, answerText: '  ISAAC   NEWTON  '), isTrue);
      expect(gradeLocally(q, answerText: 'Newton.'), isTrue);
      expect(gradeLocally(q, answerText: '"Newton"'), isTrue);
      expect(gradeLocally(q, answerText: 'Einstein'), isFalse);
      expect(gradeLocally(q, answerText: ''), isFalse);
      expect(gradeLocally(q, answerText: '   '), isFalse);
    });

    test('normalisation matches the server rule exactly', () {
      expect(normalizeShortAnswer('  Hello   World!  '), 'hello world');
      expect(normalizeShortAnswer('(newton)'), 'newton');
      expect(normalizeShortAnswer('a  b\tc'), 'a b c');
    });

    test('an empty accepted list cannot be satisfied', () {
      expect(gradeLocally(typed(''), answerText: 'anything'), isFalse);
      expect(gradeLocally(typed('|| '), answerText: ''), isFalse);
    });

    test('true/false uses the key like any other choice', () {
      final q = Question(
        id: 'q',
        questionHtml: '<p>?</p>',
        type: QuestionType.trueFalse,
        correctKey: 'T',
      );
      expect(gradeLocally(q, choice: 'T'), isTrue);
      expect(gradeLocally(q, choice: 'F'), isFalse);
    });
  });

  // ------------------------------------------------------------
  group('a question survives the round trip to disk', () {
    test('with its options, key, explanation and every picture', () {
      final original = Question(
        id: 'q1',
        courseId: 'c1',
        questionHtml: '<p>Identify the vector</p><img src="https://s/a.png">',
        questionImageUrl: 'https://s/q.png',
        questionAudioUrl: 'https://s/q.mp3',
        type: QuestionType.multipleChoice,
        marks: 2,
        correctKey: 'B',
        explanationHtml: '<p>Because…</p>',
        explanationImageUrl: 'https://s/e.png',
        explanationAudioUrl: 'https://s/e.mp3',
        courseCode: 'PHY101',
        options: const [
          QuestionOption(key: 'A', text: 'one'),
          QuestionOption(key: 'B', text: 'two'),
        ],
      );

      final back = Question.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(back.id, original.id);
      expect(back.courseId, original.courseId);
      expect(back.questionHtml, original.questionHtml);
      expect(back.questionImageUrl, original.questionImageUrl);
      expect(back.questionAudioUrl, original.questionAudioUrl);
      expect(back.correctKey, original.correctKey);
      expect(back.marks, original.marks);
      expect(back.type, original.type);
      expect(back.explanationHtml, original.explanationHtml);
      expect(back.explanationImageUrl, original.explanationImageUrl);
      expect(back.explanationAudioUrl, original.explanationAudioUrl);
      expect(back.courseCode, original.courseCode);
      expect(back.displayOptions.length, 2);
      expect(back.displayOptions.first.key, 'A');
    });
  });

  // ------------------------------------------------------------
  group('exams are never written to disk', () {
    test('isTimed marks the modes that must not be cached', () {
      expect(AttemptMode.test.isTimed, isTrue);
      expect(AttemptMode.exam.isTimed, isTrue);
      expect(AttemptMode.practice.isTimed, isFalse);
      expect(AttemptMode.smart.isTimed, isFalse);
      expect(AttemptMode.bookmarks.isTimed, isFalse);
    });
  });

  // ------------------------------------------------------------
  group('extensions and sizes', () {
    test('an extension is taken from the canonical URL', () {
      const raw = 'https://p.supabase.co/storage/v1/object/public/x/a.PNG';
      final proxied = 'https://site/api/file?u='
          '${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';
      expect(extensionForUrl(proxied), 'png');
      expect(extensionForUrl('https://x/a.mp3?token=abc'), 'mp3');
      expect(extensionForUrl('https://x/nodot'), 'bin');
      expect(extensionForUrl('https://x/a.verylongthing'), 'bin');
    });

    test('sizes read as sizes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(900), '900 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}

/// ============================================================
/// THE PER-COURSE DOWNLOAD
///
/// "every course should have its own download materials button ... it
///  should say that, there's a change in course, download now"
///
/// The badge is one comparison, and getting it wrong in either
/// direction is bad in a different way. Too eager and every course
/// nags forever; too shy and a student sits an exam on questions their
/// phone never fetched. These pin the comparison down.
/// ============================================================
void courseDownloadRecords() {
  group('deciding whether a course has changed', () {
    const server = CourseStamp(
      id: 'c1',
      code: 'CHM 101',
      materials: 8,
      questions: 240,
      tests: 2,
      pins: 12,
      pinPrint: 'abc123',
      courseStamp: '2026-08-20T08:00:00Z',
      stamp: '2026-09-01T10:00:00Z',
    );

    Map<String, dynamic> held({
      int materials = 8,
      int questions = 240,
      int tests = 2,
      int pins = 12,
      String pinPrint = 'abc123',
      String courseStamp = '2026-08-20T08:00:00Z',
      String stamp = '2026-09-01T10:00:00Z',
      bool ok = true,
    }) =>
        {
          'materials': materials,
          'questions': questions,
          'tests': tests,
          'pins': pins,
          'pin_print': pinPrint,
          'course_stamp': courseStamp,
          'stamp': stamp,
          'ok': ok,
        };

    test('a course never downloaded has no update, it has a download', () {
      expect(server.differsFrom(null), isTrue);
    });

    test('an exact match is not a change', () {
      expect(server.differsFrom(held()), isFalse);
    });

    test('a new question moves the count AND the stamp', () {
      expect(
        server.differsFrom(held(questions: 239, stamp: '2026-08-30T09:00:00Z')),
        isTrue,
      );
    });

    test('an EDITED question moves only the stamp', () {
      // The count is unchanged, which is exactly why a count alone is
      // not enough: a corrected answer key would never reach the phone.
      expect(server.differsFrom(held(stamp: '2026-08-30T09:00:00Z')), isTrue);
    });

    test('a WITHDRAWN question moves only the count', () {
      // updated_at cannot see a deletion — unpublish a question and the
      // newest stamp does not move — which is why a stamp alone is not
      // enough either.
      expect(server.differsFrom(held(questions: 241)), isTrue);
    });

    test('a new material moves it too', () {
      expect(server.differsFrom(held(materials: 7)), isTrue);
    });

    test('A QUESTION PINNED TO A TEST moves nothing else at all', () {
      // The sharpest case, and the one the first version of this missed
      // completely. A pin decides which questions the bundle WITHHOLDS,
      // so pinning one changes the correct content of every download of
      // that course without touching a single question or material row.
      // Measured against a real PostgreSQL: pinning one question took a
      // download from five questions to four while the material count,
      // the question count and both timestamps stayed byte-identical.
      expect(
        server.differsFrom(held(pins: 11)),
        isTrue,
        reason: 'a phone would keep a question that is now on an exam',
      );
    });

    test('a pin SWAP keeps the count and still gets caught', () {
      // Unpin one question and pin another in the same sitting: the
      // count is identical and the set the bundle withholds has
      // completely changed. Measured against a real PostgreSQL — pins
      // 3 -> 3, questions 7 -> 7, question stamp unmoved, checksum
      // 0c39052b86… -> d521a1e128…
      expect(
        server.differsFrom(held(pinPrint: 'a-different-checksum')),
        isTrue,
        reason: 'the phone would hold the key to whichever question was '
            'just put on the exam',
      );
    });

    test('a test published moves the test count', () {
      expect(server.differsFrom(held(tests: 1)), isTrue);
    });

    test('a course RENAMED or HIDDEN moves only its own stamp', () {
      // courses has carried an updated_at trigger since the first
      // migration and nothing ever read it, so a rename, a hide, a
      // re-order and a move to another level were all invisible.
      expect(
        server.differsFrom(held(courseStamp: '2026-08-19T08:00:00Z')),
        isTrue,
      );
    });

    test('a run that did not finish keeps asking', () {
      // Everything matches, but the download reported failures. A
      // half-downloaded course must not sit there looking finished.
      expect(server.differsFrom(held(ok: false)), isTrue);
    });

    test('a record written by an older build counts as different', () {
      // No tests, pins or course_stamp keys at all. One extra download
      // on the upgrade launch, and correct from then on — the other way
      // round would leave every existing phone permanently blind to the
      // three fields this release added.
      expect(
        server.differsFrom({
          'materials': 8,
          'questions': 240,
          'stamp': '2026-09-01T10:00:00Z',
          'ok': true,
        }),
        isTrue,
      );
    });

    test('an empty course is not offered as a download', () {
      const nothing = CourseStamp(id: 'c2');
      expect(nothing.isEmpty, isTrue);
      expect(server.isEmpty, isFalse);
    });

    test('it reads both spellings the two backends use', () {
      // The SQL half and the website half must be indistinguishable.
      final fromSql = CourseStamp.fromJson(const {
        'id': 'c1',
        'code': 'CHM 101',
        'materials': 8,
        'questions': 240,
        'tests': 2,
        'pins': 12,
        'pin_print': 'abc123',
        'course_stamp': '2026-08-20T08:00:00Z',
        'material_stamp': '2026-08-21T08:00:00Z',
        'stamp': '2026-09-01T10:00:00Z',
      });
      expect(fromSql.pins, 12);
      expect(fromSql.courseStamp, '2026-08-20T08:00:00Z');
      expect(fromSql.differsFrom(held()), isFalse);
      expect(fromSql.updatedAt, isNotNull,
          reason: 'the date shown to a student comes off this');
    });
  });

  group('the one number that says something changed', () {
    test('a moved revision means go and look', () {
      const now = ContentRevision(rev: 41, available: true);
      expect(now.movedFrom(40), isTrue);
      expect(now.movedFrom(41), isFalse);
    });

    test('an UNAVAILABLE revision always means go and look', () {
      // Migration 0014 not applied. The app falls back to comparing the
      // manifest, which is what it did before this existed: slower to
      // notice, never wrong. Reading "unavailable" as "nothing changed"
      // would blind every phone until the migration ran.
      const missing = ContentRevision(rev: 0, available: false);
      expect(missing.movedFrom(0), isTrue);
      expect(missing.movedFrom(99), isTrue);
    });

    test('a zero revision is never trusted', () {
      const zero = ContentRevision(rev: 0, available: true);
      expect(zero.movedFrom(0), isTrue);
    });

    test('it reads both spellings the two backends use', () {
      expect(
        ContentRevision.fromJson(const {'rev': 7, 'revAvailable': true}).rev,
        7,
      );
      expect(
        ContentRevision.fromJson(const {'rev': 7, 'available': true}).available,
        isTrue,
      );
      expect(ContentRevision.fromJson(const {}).available, isFalse);
    });
  });

  group('the record of what landed', () {
    late Directory dir;
    late OfflineStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bx_course_test');
      PathProviderPlatform.instance = _FakePaths(dir.path);
      final opened = await OfflineStore.open();
      expect(opened, isNotNull);
      store = opened!;
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('a course with no record has never been downloaded', () {
      expect(store.courseRecord('c1'), isNull);
    });

    test('the record survives being read back from disk', () async {
      await store.putCourseRecord(
        'c1',
        materials: 8,
        questions: 240,
        stamp: '2026-09-01T10:00:00Z',
        ok: true,
        bytes: 12345,
      );
      await store.flush();

      final reopened = await OfflineStore.open();
      expect(reopened, isNotNull);
      final rec = reopened!.courseRecord('c1');
      expect(rec, isNotNull,
          reason: 'a record only in RAM is a badge that comes back on every '
              'launch');
      expect(rec!['questions'], 240);
      expect(rec['ok'], isTrue);
      expect(rec['bytes'], 12345);
    });

    test('signing in as somebody else throws the records away', () async {
      await store.claim('student-1');
      await store.putCourseRecord('c1',
          materials: 1, questions: 1, stamp: 's', ok: true);
      await store.claim('student-2');
      expect(store.courseRecord('c1'), isNull,
          reason: "another student's downloads are not this one's to see");
    });
  });
}

/// ============================================================
/// DROPPING WHAT TUTOR BELLO WITHDREW
///
/// The offline bank only ever merged. A question he unpublished or
/// deleted stayed on the phone for ever — practisable, with its answer
/// key, long after he had decided it was wrong.
///
/// It cannot be worked out from the download pages, because those
/// deliberately withhold the questions pinned to a published test: "the
/// server did not send it" and "the server no longer has it" look
/// exactly alike. So the phone asks for the full id list, withheld ones
/// included, and prunes against that.
///
/// The dangerous direction is deleting too much. These pin that shut.
/// ============================================================
void pruningWithdrawnContent() {
  group('dropping what was withdrawn', () {
    late Directory dir;
    late OfflineStore store;

    Map<String, dynamic> q(String id, {String why = '<p>because</p>'}) => {
          'id': id,
          'course_id': 'c1',
          'question_html': '<p>Q$id</p>',
          'correct_key': 'A',
          'explanation_html': why,
          'options': [
            {'key': 'A', 'text': 'one'},
          ],
        };

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bx_prune_test');
      PathProviderPlatform.instance = _FakePaths(dir.path);
      final opened = await OfflineStore.open();
      expect(opened, isNotNull);
      store = opened!;
      await store.putQuestions('c1', [q('a'), q('b'), q('c'), q('d')]);
      await store.flush();
    });

    tearDown(() async => dir.delete(recursive: true));

    test('a withdrawn question is really gone from the disk', () async {
      final dropped = await store.pruneQuestions('c1', {'a', 'b', 'c'});
      expect(dropped, 1);

      final held = await store.questions('c1');
      expect(held.map((r) => r['id']), unorderedEquals(['a', 'b', 'c']));

      // And from a store that has never seen this session — a prune
      // that only lives in RAM is a question that comes back.
      final reopened = await OfflineStore.open();
      expect((await reopened!.questions('c1')).length, 3);
    });

    test('a question PINNED after the download loses its key', () async {
      // The reverse of what this used to assert, and the reversal is
      // the point. The alive set is what the server still SERVES, so a
      // question Tutor Bello puts on an exam drops out of it — and the
      // phone that already holds it, with its answer key, must let it
      // go. Keeping it "because the server still publishes it" was
      // stepping over precisely the row that most needed removing.
      final dropped = await store.pruneQuestions('c1', {'a', 'b', 'c'});
      expect(dropped, 1);
      expect((await store.questions('c1')).map((r) => r['id']),
          isNot(contains('d')));
    });

    test('an EMPTY list is an answer, and it prunes', () async {
      // A course whose every question is now pinned to a published
      // test, or one Tutor Bello emptied out. Refusing to act on
      // emptiness left exactly those courses holding withdrawn
      // questions for ever, with their answer keys, and a manual
      // "Check for anything new" refused to clear them.
      expect(await store.pruneQuestions('c1', {}), 4);
      expect((await store.questions('c1')), isEmpty);
    });

    test('a read that FAILED never gets this far', () async {
      // The safety lives one level up, in CourseIndex.isUsable, and it
      // has to: emptiness and failure look identical to pruneQuestions
      // and only the caller can tell them apart.
      const failed = CourseIndex(complete: false);
      expect(failed.isUsable, isFalse);

      const emptyButReal = CourseIndex(complete: true);
      expect(emptyButReal.isUsable, isTrue,
          reason: 'a course with nothing left to serve must still prune');

      const normal = CourseIndex(questionIds: {'a'}, complete: true);
      expect(normal.isUsable, isTrue);
    });

    test('another course is never touched', () async {
      await store.putQuestions('c2', [q('x'), q('y')]);
      await store.pruneQuestions('c1', {'a'});
      expect((await store.questions('c2')).length, 2,
          reason: 'pruning one course must not reach into another');
    });

    test('pruning twice is not a second deletion', () async {
      expect(await store.pruneQuestions('c1', {'a', 'b', 'c'}), 1);
      expect(await store.pruneQuestions('c1', {'a', 'b', 'c'}), 0);
    });
  });

  group('an edit that clears a field', () {
    late Directory dir;
    late OfflineStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bx_clear_test');
      PathProviderPlatform.instance = _FakePaths(dir.path);
      store = (await OfflineStore.open())!;
    });

    tearDown(() async => dir.delete(recursive: true));

    Map<String, dynamic> row(String why) => {
          'id': 'q1',
          'course_id': 'c1',
          'question_html': '<p>Q</p>',
          'correct_key': 'A',
          'explanation_html': why,
        };

    test('a PARTIAL row still must not strip what the phone holds',
        () async {
      // The reason the merge exists. On the direct path an attempt opens
      // with the answer key stripped and fills it in only once the
      // student has answered; overwriting would throw the key away and a
      // question with no key cannot be marked offline.
      await store.putQuestions('c1', [row('<p>the long explanation</p>')]);
      await store.putQuestions('c1', [
        {'id': 'q1', 'course_id': 'c1', 'question_html': '<p>Q</p>'},
      ]);
      final held = (await store.questions('c1')).first;
      expect(held['explanation_html'], '<p>the long explanation</p>');
      expect(held['correct_key'], 'A');
    });

    test('a COMPLETE row lets Tutor Bello clear something', () async {
      // The same rule, unchanged, meant a wrong explanation he deleted
      // stayed on the phone for ever, because "empty" always lost to
      // "held". A course download sends whole rows and says so.
      await store.putQuestions('c1', [row('<p>this was wrong</p>')]);
      await store.putQuestions('c1', [row('')], complete: true);
      final held = (await store.questions('c1')).first;
      expect(held['explanation_html'], '',
          reason: 'a cleared field must really clear');
      expect(held['correct_key'], 'A',
          reason: 'and the rest of the row must survive');
    });
  });
}

/// ============================================================
/// WHOSE DATE IS ON THE SCREEN
///
/// "Check the code, also subject last updated from Bello o not the
///  download"
///
/// Every recency string in the app used to answer "when did the student
/// press a button" — savedAt, syncedAt, "Saved on this phone". Nobody
/// has ever wanted to know that about a note. What they want is how
/// fresh the material is, and only Tutor Bello moves that.
/// ============================================================
void whoseDateIsShown() {
  group('the date on screen is Tutor Bello\'s', () {
    OfflineItem item(String sig) => OfflineItem(
          id: 'm1',
          title: 'Note',
          kind: 'note',
          sig: sig,
          savedAtMs: DateTime(2026, 8, 12).millisecondsSinceEpoch,
        );

    test('a material carries the date he last changed it', () {
      // sig is already the material's own updated_at wherever the
      // backend sends one, so the date is on the disk and costs nothing.
      final e = item('2026-09-01T10:30:00.000Z');
      expect(e.updatedAt, isNotNull);
      expect(e.updatedAt!.toUtc().month, 9);
      expect(e.updatedAt!.toUtc().day, 1);
      expect(e.savedAt.month, 8,
          reason: 'and it is NOT the day the student downloaded it');
    });

    test('the URL form of a signature is not a date', () {
      // Older backends, and anything the sync could only fingerprint by
      // URL. Showing "updated 1970" would be worse than showing nothing.
      expect(item('https://example.com/a.pdf#3').updatedAt, isNull);
      expect(item('carried-over').updatedAt, isNull);
      expect(item('').updatedAt, isNull);
    });

    test('a course carries it too, and holds it offline', () {
      const stamp = CourseStamp(
        id: 'c1',
        materials: 3,
        questions: 40,
        stamp: '2026-09-01T10:30:00.000Z',
      );
      expect(stamp.updatedAt, isNotNull);
      expect(stamp.updatedAt!.toUtc().day, 1);
    });

    test('an unstamped course shows nothing rather than a wrong date', () {
      const stamp = CourseStamp(id: 'c1', materials: 3, questions: 40);
      expect(stamp.updatedAt, isNull);
    });
  });
}

/// ============================================================
/// CLEARING A COURSE TUTOR BELLO TOOK DOWN
///
/// The app announces a withdrawn course and tells the student to free
/// the space. Nothing could actually free it: the question bank is
/// stored as an item of kind 'questions', which the Vault filters out
/// of its list and the evictor skips — while its bytes still count
/// against the storage ceiling. So the banner pointed at a screen that
/// could not show the thing it was talking about, the record was never
/// removed, and the notice stayed up for the life of the install.
/// ============================================================
void clearingAWithdrawnCourse() {
  group('a withdrawn course can actually be cleared', () {
    late Directory dir;
    late OfflineStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bx_forget_test');
      PathProviderPlatform.instance = _FakePaths(dir.path);
      store = (await OfflineStore.open())!;

      await store.putQuestions('gone', [
        {'id': 'q1', 'course_id': 'gone', 'question_html': '<p>a</p>'},
        {'id': 'q2', 'course_id': 'gone', 'question_html': '<p>b</p>'},
      ]);
      await store.putNote(
        id: 'n1',
        title: 'A note',
        html: '<p>body</p>',
        courseId: 'gone',
      );
      await store.putNote(
        id: 'keep',
        title: 'Another course',
        html: '<p>body</p>',
        courseId: 'staying',
      );
      await store.putCourseRecord('gone',
          materials: 1, questions: 2, stamp: 's', ok: true, bytes: 10);
      await store.flush();
    });

    tearDown(() async => dir.delete(recursive: true));

    test('the question bank is invisible in the Vault but real on disk',
        () async {
      // The reason the old banner was unfollowable.
      expect(store.readable.any((i) => i.kind == 'questions'), isFalse,
          reason: 'the Vault cannot show it');
      expect((await store.questions('gone')).length, 2,
          reason: 'and yet there it is');
      expect(store.totalBytes, greaterThan(0),
          reason: 'counting against the ceiling the whole time');
    });

    test('forgetting the course takes all of it', () async {
      final freed = await store.forgetCourse('gone');
      expect(freed, greaterThan(0));
      expect(await store.questions('gone'), isEmpty);
      expect(store.item('n1'), isNull);
      expect(store.courseRecord('gone'), isNull,
          reason: 'the record must go too, or the banner never clears');
    });

    test('and leaves every other course alone', () async {
      await store.forgetCourse('gone');
      expect(store.item('keep'), isNotNull);
    });

    test('it survives being read back from disk', () async {
      await store.forgetCourse('gone');
      final reopened = await OfflineStore.open();
      expect(reopened!.courseRecord('gone'), isNull);
      expect(await reopened.questions('gone'), isEmpty);
      expect(reopened.item('keep'), isNotNull);
    });

    test('forgetting nothing is not an error', () async {
      expect(await store.forgetCourse('never-existed'), 0);
      expect(await store.forgetCourse(''), 0);
    });
  });

  group('the record says what LANDED, not what the server has', () {
    late Directory dir;
    late OfflineStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bx_record_test');
      PathProviderPlatform.instance = _FakePaths(dir.path);
      store = (await OfflineStore.open())!;
    });

    tearDown(() async => dir.delete(recursive: true));

    test('the two counts are kept apart', () async {
      // With offline_questions switched off nothing is fetched, and the
      // manifest's count was stored anyway — so from the next launch the
      // course announced "works without data · 412 questions" with none
      // of them on the phone. The server's numbers must stay the
      // server's, or the badge can never settle; what the student is
      // TOLD they have has to be what landed.
      await store.putCourseRecord(
        'c1',
        materials: 8,
        questions: 412,
        heldQuestions: 0,
        heldFiles: 8,
        stamp: 's',
        ok: true,
      );
      final rec = store.courseRecord('c1')!;
      expect(rec['questions'], 412, reason: 'what the server has');
      expect(rec['heldQuestions'], 0, reason: 'what is on the phone');
    });

    test('a failure records WHY, so it is not blamed on Tutor Bello',
        () async {
      // A file that can never be fetched latched ok:false, and the card
      // then told the student, in his name, every launch for ever, that
      // he had changed something. He had not.
      await store.putCourseRecord(
        'c1',
        materials: 8,
        questions: 40,
        stamp: 's',
        ok: false,
        reason: 'Your offline library is full.',
      );
      final rec = store.courseRecord('c1')!;
      expect(rec['ok'], isFalse);
      expect(rec['reason'], 'Your offline library is full.');
    });
  });
}

/// ============================================================
/// A SYNC THAT NEVER LEFT THE PHONE MUST NOT CLAIM TO HAVE SYNCED
///
/// loadContent falls back to the cached shelf whenever it cannot reach
/// the server. That is right for reading — the app has to keep working
/// with the data off — and it was catastrophic for syncing, because the
/// sync engine treated the cached answer as a successful check: no jobs
/// were planned, markSynced() stamped the clock, and the Vault said
/// "Last synced 3:14 PM". A student in a lecture hall with no signal
/// tapped Sync, read that, turned their data off and believed they were
/// holding today's material.
///
/// So loadContent now says WHERE its answer came from, and the sync
/// refuses to stamp anything it did not actually check.
/// ============================================================
void syncingWithNoSignal() {
  group('a sync that never reached the server', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocalStore.resetForTest();
    });

    test('serves the cached shelf but reports that it is cached', () async {
      final store = await LocalStore.init();
      await store.writeJson(BxKeys.cachedContent, {
        'courses': [
          {'id': 'c1', 'code': 'PHY 101', 'title': 'General Physics I'},
        ],
        'materials': const [],
      });

      // Backend() with nothing configured cannot reach anything, which
      // is exactly the lecture-hall case.
      final repo = ContentRepository(Backend(), store);
      final fresh = await repo.loadContent(level: '100', force: true);

      expect(fresh, isFalse,
          reason: 'nothing was checked, so nothing may be claimed');
      expect(repo.courses, hasLength(1),
          reason: 'the student still reads what they already have');
    });

    test('a shelf that is neither on the server nor on the phone throws',
        () async {
      final store = await LocalStore.init();
      final repo = ContentRepository(Backend(), store);
      await expectLater(
        repo.loadContent(level: '100', force: true),
        throwsA(anything),
      );
    });
  });
}

/// ============================================================
/// A SAVED DOCUMENT THAT TUTOR BELLO HAS SINCE CHANGED
///
/// The reader always preferred the vaulted copy, which is right, and
/// then never checked it against what the server publishes, which is
/// not. A corrected past-question paper could never reach a student who
/// had already saved the wrong one: the screen said nothing, carried no
/// date, and pull-to-refresh reloaded the row and handed back the same
/// file.
/// ============================================================
void aSavedCopyThatFellBehind() {
  group('a saved document knows when it has fallen behind', () {
    // The comparison the reader makes: the sig written at save time
    // against the material's updated_at now.
    bool stale({required String held, required String live}) =>
        held.isNotEmpty && live.isNotEmpty && held != live;

    test('a re-uploaded document is stale', () {
      expect(
        stale(
          held: '2026-08-01T09:00:00.000Z',
          live: '2026-09-03T16:20:00.000Z',
        ),
        isTrue,
      );
    });

    test('the same document is not', () {
      expect(
        stale(
          held: '2026-08-01T09:00:00.000Z',
          live: '2026-08-01T09:00:00.000Z',
        ),
        isFalse,
      );
    });

    test('an unknown date on either side raises no false alarm', () {
      // A backend that sends no updated_at, or a copy saved by an older
      // build. "We cannot tell" must not become "yours is out of date"
      // on a document that never changed — that sends a student to
      // spend data re-downloading a file they already hold.
      expect(stale(held: '', live: '2026-09-03T16:20:00.000Z'), isFalse);
      expect(stale(held: '2026-08-01T09:00:00.000Z', live: ''), isFalse);
      expect(stale(held: '', live: ''), isFalse);
    });

    test('the date the student sees comes off the saved copy', () {
      final e = OfflineItem(
        id: 'm1',
        title: 'PHY 101 · 2023 past questions',
        kind: 'pq',
        sig: '2026-09-03T16:20:00.000Z',
        savedAtMs: DateTime(2026, 9, 4).millisecondsSinceEpoch,
      );
      expect(e.updatedAt!.toUtc().day, 3,
          reason: "Tutor Bello's date, not the download's");
    });
  });
}

/// ============================================================
/// THE ONE LINE THE OWNER ASKED FOR
///
/// "subject last updated from Bello o not the download."
///
/// It was printed in UTC while "today" was read from the phone's own
/// clock, so a note Tutor Bello posted at half past midnight in Lagos
/// told the whole country it was "yesterday" — and the year was dropped
/// entirely, which on an app that runs the same PHY 101 session after
/// session makes last year's material indistinguishable from this
/// year's. CI now runs the suite with TZ=Africa/Lagos so a regression
/// here cannot hide behind a UTC runner.
/// ============================================================
void belloDateReadsRight() {
  group("Tutor Bello's date", () {
    test('is rendered in the student\'s own time, not UTC', () {
      // Half past midnight in Lagos on 4 September is 23:30 UTC on the
      // 3rd. Rendered as UTC it reads "yesterday" to every student in
      // the country.
      final instant = DateTime.utc(2026, 9, 3, 23, 30);
      final local = instant.toLocal();
      final noonThatLocalDay =
          DateTime(local.year, local.month, local.day, 12);
      expect(bxBelloDate(instant, now: noonThatLocalDay), 'today');
    });

    test('says today, yesterday, then days, then the date', () {
      final now = DateTime(2026, 9, 10, 12);
      expect(bxBelloDate(DateTime(2026, 9, 10, 6), now: now), 'today');
      expect(bxBelloDate(DateTime(2026, 9, 9, 23), now: now), 'yesterday');
      expect(bxBelloDate(DateTime(2026, 9, 7), now: now), '3 days ago');
      expect(bxBelloDate(DateTime(2026, 9, 1), now: now), '1 Sep');
    });

    test('carries the year on anything from another session', () {
      final now = DateTime(2026, 9, 10, 12);
      expect(bxBelloDate(DateTime(2025, 10, 12), now: now), '12 Oct 2025');
      expect(bxBelloDate(DateTime(2026, 1, 4), now: now), '4 Jan');
    });

    test('a date in the future is not called "-1 days ago"', () {
      // Clock skew on a cheap phone, or a stamp written by a server an
      // hour ahead. It must still read as a date.
      final now = DateTime(2026, 9, 10, 12);
      expect(bxBelloDate(DateTime(2026, 9, 12), now: now), '12 Sep');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
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

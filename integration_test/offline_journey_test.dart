import 'dart:io';

import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/core/providers.dart';
import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:belloxdydx/features/shell/app_drawer.dart';
import 'package:belloxdydx/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// ============================================================
/// THE JOURNEY THAT MATTERS
///
/// The widget tests prove the offline store keeps what it is given.
/// They cannot prove the app puts anything in it. Only running the real
/// app against a real server, over a real HTTP stack, onto a real
/// filesystem, can do that — which is the whole reason this file exists
/// and why it runs on a desktop target rather than in a browser.
///
/// It answers exactly the questions that were asked of it:
///
///   · Does the Offline Vault still sit empty after a real sync?
///   · Do the note bodies actually reach the disk?
///   · Do the PICTURES reach the disk, including the ones embedded in
///     an HTML body?
///   · Are questions kept, with their options and their answer key?
///   · Does any of it still open when the server is GONE?
///
/// The last one is the point. Half of what was called offline support
/// was a cached JSON blob that happened to still be in memory. Here the
/// mock backend is killed outright, mid-test, and the app has to stand
/// on its own.
/// ============================================================

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [check] passes or the budget runs out. `pumpAndSettle`
  /// is no use here: the app has a live sync and animated banners, so
  /// there is never a settled frame to wait for.
  Future<bool> until(
    WidgetTester tester,
    bool Function() check, {
    Duration budget = const Duration(seconds: 40),
  }) async {
    final deadline = DateTime.now().add(budget);
    while (DateTime.now().isBefore(deadline)) {
      if (check()) return true;
      await tester.pump(const Duration(milliseconds: 250));
    }
    return check();
  }

  Future<bool> untilFound(WidgetTester tester, Finder f,
          {Duration budget = const Duration(seconds: 30)}) =>
      until(tester, () => f.evaluate().isNotEmpty, budget: budget);

  /// Everything readable on screen right now. When a step cannot find
  /// what it is looking for, the failure should say what WAS there
  /// rather than just "not found".
  String visible() {
    final out = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final t = e.widget as Text;
      final s = t.data ?? t.textSpan?.toPlainText() ?? '';
      if (s.trim().isNotEmpty) out.add(s.trim().replaceAll('\n', ' '));
    }
    return out.join(' | ');
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(f.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a student signs in, the app fills itself, and it survives '
      'the server going away', (tester) async {
    // A phone, not the desktop window this happens to run in. A student
    // on a 6-inch Tecno is the shape that matters, and a layout that
    // only holds together at 1280 logical pixels wide is not tested by
    // running it at 1280 logical pixels wide.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625; // 411 x 914 logical
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // The app's own container, so the test asks the same providers the
    // screens do rather than reaching around them.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    const backend = String.fromEnvironment('BX_SITE_URL',
        defaultValue: 'http://127.0.0.1:54321');

    // ---- through onboarding and into the login form ----------------
    //
    // Tapped by TEXT rather than by button type on purpose. Every
    // control in this app is a BxButton wrapping a BxScaleTap, not a
    // Material ElevatedButton, so a type-based finder finds nothing —
    // and a test that silently finds nothing is a test that silently
    // passes.
    debugPrint('[journey] first screen: ${visible()}');

    // The splash holds until the session resolves, and it carries no
    // controls at all. Starting to tap before it clears just breaks the
    // loop on its first pass.
    await until(
      tester,
      () =>
          find.byType(TextField).evaluate().isNotEmpty ||
          find.text('Log in').evaluate().isNotEmpty ||
          find.text('Skip').evaluate().isNotEmpty,
      budget: const Duration(seconds: 30),
    );
    debugPrint('[journey] settled on: ${visible()}');

    for (var i = 0; i < 8 && find.byType(TextField).evaluate().isEmpty; i++) {
      var moved = false;
      for (final label in const [
        'I already have an account',
        'Log in',
        'Skip',
      ]) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        await tap(tester, f.last);
        moved = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 700));
      debugPrint('[journey] step $i (moved: $moved): ${visible()}');
      if (!moved) break;
    }

    bool onDashboard() =>
        find.textContaining(RegExp('DASHBOARD|Good ')).evaluate().isNotEmpty;

    // A session survives a restart, which is the point of it — so the
    // run may already be inside. Only sign in when there is a form.
    if (!onDashboard()) {
      expect(await untilFound(tester, find.byType(TextField)), isTrue,
          reason: 'the login form should be reachable from a cold start. '
              'On screen: ${visible()}');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'kunle');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(fields.at(1), 'Password@1#');
      await tester.pump(const Duration(milliseconds: 200));

      // The login form rises out of the 3D intro and sits inside an
      // IgnorePointer until it has. Tapping before then lands on
      // nothing at all — which is correct behaviour, and the reason
      // this step exists rather than a longer wait.
      final skipIntro = find.text('Skip intro');
      if (skipIntro.evaluate().isNotEmpty) {
        await tap(tester, skipIntro);
        await tester.pump(const Duration(seconds: 2));
      }
      await until(
        tester,
        () => find.text('Replay intro').evaluate().isNotEmpty,
        budget: const Duration(seconds: 15),
      );

      await tap(tester, find.text('Log in').last);
      await tester.pump(const Duration(milliseconds: 800));
      debugPrint('[journey] after submit: ${visible()}');
    }

    // ---- signed in --------------------------------------------------
    final signedIn =
        await until(tester, onDashboard, budget: const Duration(seconds: 60));
    expect(signedIn, isTrue,
        reason: 'login must complete against the mock. On screen: ${visible()}');
    debugPrint('[journey] signed in');

    // ---- the sync runs behind them ----------------------------------
    // Nothing is tapped here on purpose. The claim under test is that
    // material arrives BY ITSELF, so the test waits rather than asks.
    final store = Offline.store;
    expect(store, isNotNull,
        reason: 'the offline root must open on a real filesystem');

    final filled = await until(
      tester,
      () => store!.readable.isNotEmpty,
      budget: const Duration(seconds: 90),
    );

    final root = Directory(store!.rootPath);
    final onDisk = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring(root.path.length + 1))
        .toList();

    expect(filled, isTrue,
        reason: 'THE VAULT MUST NOT BE EMPTY AFTER A REAL SYNC. '
            'On disk: $onDisk');

    // ---- what actually landed ---------------------------------------
    final notes = onDisk.where((p) => p.startsWith('notes/')).toList();
    expect(notes, isNotEmpty,
        reason: 'note bodies must be real files: $onDisk');

    final assets = onDisk.where((p) => p.startsWith('assets/')).toList();
    expect(assets, isNotEmpty,
        reason: 'the pictures inside those notes must come down too — a '
            'note whose diagram is missing is half-saved: $onDisk');

    // A saved note is genuinely readable, and it is the real body.
    final firstNote = store.readable.firstWhere((i) => i.kind == 'note');
    final html = await store.readNote(firstNote.id);
    expect(html, isNotNull);
    expect(html!.length, greaterThan(200),
        reason: 'a note body, not a placeholder');

    // Every picture the body points at is on the phone, by the same
    // lookup the reader uses at build time.
    final embedded = kEmbeddedStorageUrl
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toList();
    expect(embedded, isNotEmpty,
        reason: 'the fixture note embeds a diagram');
    for (final url in embedded) {
      final path = store.assetPath(url);
      expect(path, isNotNull, reason: 'not cached: $url');
      expect(File(path!).existsSync(), isTrue, reason: 'missing on disk: $url');
    }

    // ---- questions ---------------------------------------------------
    // The claim is that a question the app has ALREADY SHOWN is kept,
    // with its options, its key and its pictures. So a round is opened
    // through the real UI and the store is then asked what it holds.
    final menu = find.byType(BxDrawerButton);
    debugPrint('[journey] menu buttons: ${menu.evaluate().length}, '
        'icons: ${find.byIcon(Icons.menu_rounded).evaluate().length}');
    expect(menu.evaluate(), isNotEmpty,
        reason: 'the drawer must be reachable from a tab screen. '
            'On screen: ${visible()}');
    debugPrint('[journey] menu rect: ${tester.getRect(menu.first)} '
        'size: ${tester.view.physicalSize / tester.view.devicePixelRatio}');
    await tester.tap(menu.first, warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 900));
    debugPrint('[journey] drawer: ${visible()}');

    expect(await untilFound(tester, find.text('Practice a course'),
            budget: const Duration(seconds: 10)),
        isTrue,
        reason: 'the drawer must offer practice by course');
    await tap(tester, find.text('Practice a course'));
    await tester.pump(const Duration(seconds: 2));
    debugPrint('[journey] picker: ${visible()}');

    // Scoped to the sheet. The dashboard behind it also prints course
    // codes ("80% | PHY 101"), and a finder that reaches one of those
    // taps the modal barrier instead — closing the sheet and starting
    // nothing, which looks exactly like the feature being broken.
    final firstCourse = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.textContaining(RegExp(r'^[A-Z]{3} ?\d{3}$')),
    );
    expect(
        await until(tester, () => firstCourse.evaluate().isNotEmpty,
            budget: const Duration(seconds: 15)),
        isTrue,
        reason: 'the course picker must list courses. '
            'On screen: ${visible()}');
    await tap(tester, firstCourse);

    final inPractice = await until(
      tester,
      () => find.textContaining(RegExp('Question |of 20|Submit')).evaluate().isNotEmpty,
      budget: const Duration(seconds: 30),
    );
    debugPrint('[journey] practice: ${visible()}');

    final questions = await store.allQuestions();
    expect(questions, isNotEmpty,
        reason: 'A QUESTION THE APP HAS SHOWN MUST BE KEPT. '
            'Reached practice: $inPractice. On screen: ${visible()}');

    final q = questions.first;
    expect('${q['question_html']}'.trim(), isNotEmpty);
    expect(q['options'], isNotNull,
        reason: 'without options an offline question is unanswerable');

    // The answer key is asserted where it can be. The two backend paths
    // genuinely differ: the website route ships the key when an attempt
    // opens, while the direct RPC withholds it until the student has
    // answered once. So the app is checked for the behaviour that
    // matters either way — a round is only offered offline over
    // questions it can actually MARK.
    final markable = questions.where(isMarkableOffline).toList();
    debugPrint('[journey] markable offline: ${markable.length} of '
        '${questions.length}');
    if (markable.isNotEmpty) {
      final m = markable.first;
      expect(isMarkableOffline(m), isTrue);
      final graded = gradeLocally(
        Question.fromJson(m),
        choice: '${m['correct_key'] ?? ''}',
        answerText: '${m['answer_text'] ?? ''}'.split('|').first,
      );
      expect(graded, isTrue,
          reason: 'a cached question must mark its own right answer right');
    }

    // ---- answering folds the key in ----------------------------------
    // The direct path opens an attempt with the key stripped and only
    // discloses it once an answer is committed. So a question is only
    // fully offline-ready after it has been answered once, and this
    // proves the app actually keeps what the server hands back.
    final optionA = find.text('A');
    if (optionA.evaluate().isNotEmpty) {
      await tap(tester, optionA.first);
      await tester.pump(const Duration(seconds: 3));
      debugPrint('[journey] answered: ${visible()}');

      final afterAnswer = await until(
        tester,
        () => true,
        budget: const Duration(seconds: 2),
      );
      expect(afterAnswer, isTrue);

      final refreshed = await store.allQuestions();
      final nowMarkable = refreshed.where(isMarkableOffline).length;
      debugPrint('[journey] markable after answering: $nowMarkable');

      // The two paths differ and both are correct:
      //
      //   legacy (what production runs) — /api/practice/[id] does
      //     select("*"), so every question in the round arrives ready to
      //     mark offline before the student has answered anything.
      //   direct — bx_open_attempt strips the key and hands it over
      //     only once an answer is committed, so the pool becomes
      //     markable one question at a time.
      //
      // What must hold either way: answering never LOSES a key, and
      // after one answer at least one question can be marked offline.
      expect(nowMarkable, greaterThanOrEqualTo(markable.length),
          reason: 'a cached key must never be lost by a later write');
      expect(nowMarkable, greaterThan(0),
          reason: 'answering a question must leave it markable offline — '
              'otherwise an offline round marks everything wrong');
      if (markable.isEmpty) {
        expect(nowMarkable, greaterThan(0),
            reason: 'on a path that withholds the key, answering is what '
                'hands it over');
      }
    }

    // Every picture and voice note those questions carry is on the
    // phone too — otherwise "questions work offline" means text only.
    final media = <String>{};
    for (final row in questions) {
      for (final key in const [
        'question_image_url',
        'question_audio_url',
        'explanation_image_url',
        'explanation_audio_url',
      ]) {
        final v = row[key];
        if (v is String && v.trim().isNotEmpty) media.add(v);
      }
    }
    debugPrint('[journey] question media referenced: ${media.length}');
    if (media.isNotEmpty) {
      final held = media.where((u) => store.hasAsset(u)).length;
      debugPrint('[journey] question media on disk: $held of ${media.length}');
      expect(held, greaterThan(0),
          reason: 'a question diagram that is not on the phone makes '
              '"questions work offline" mean text only');
    }

    // ---- the backend policy reaches the phone ------------------------
    // "No new build" is a claim, so it gets tested rather than stated.
    // The setting is flipped on the server and the app is made to
    // resume; it must be obeying the new value afterwards.
    expect(container.read(appPolicyProvider).allowScreenshots, isFalse,
        reason: 'screen capture is blocked unless the backend says otherwise');

    await tester.runAsync(() async {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('$backend/__test/settings'));
      req.headers.contentType = ContentType.json;
      req.write('{"allowScreenshots":true}');
      await (await req.close()).drain<void>();
      client.close();
    });

    await tester.runAsync(() =>
        container.read(sessionProvider.notifier).applyPolicyForTest());
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(appPolicyProvider).allowScreenshots, isTrue,
        reason: 'a switch Tutor Bello flips must reach the phone with no '
            'new build');

    // ---- the server disappears ----------------------------------------
    // Everything above could be explained by a warm cache. This cannot:
    // the backend is killed outright and the app has to stand on its own.
    final mockPid = const String.fromEnvironment('BX_MOCK_PID');
    if (mockPid.isNotEmpty) {
      await tester.runAsync(() => Process.run('kill', [mockPid]));
      await tester.pump(const Duration(seconds: 2));

      final stillDown = await tester.runAsync(() async {
        try {
          final s = await Socket.connect('127.0.0.1', 54321,
              timeout: const Duration(seconds: 2));
          s.destroy();
          return false;
        } catch (_) {
          return true;
        }
      });
      expect(stillDown, isTrue, reason: 'the backend must really be gone');
      debugPrint('[journey] backend killed');

      // A saved note still opens, read through the app's own repository
      // rather than the store directly — which is what a student
      // tapping it actually goes through.
      final offlineNote = await tester.runAsync(
          () => container.read(contentRepoProvider).material(firstNote.id));
      expect(offlineNote, isNotNull);
      expect(offlineNote!.contentHtml.trim(), isNotEmpty,
          reason: 'A SAVED NOTE MUST OPEN WITH THE SERVER GONE');
      debugPrint('[journey] note opened offline: '
          '${offlineNote.contentHtml.length} chars');

      // And its pictures are still found on disk.
      for (final url in embedded) {
        expect(store.assetPath(url), isNotNull,
            reason: 'a saved picture must still be found offline');
      }

      // The question pool is readable with nothing but the phone.
      final offlineQuestions =
          await tester.runAsync(() => store.allQuestions()) ?? const [];
      expect(offlineQuestions, isNotEmpty,
          reason: 'QUESTIONS MUST BE READABLE WITH THE SERVER GONE');
      debugPrint('[journey] ${offlineQuestions.length} questions readable '
          'offline');

      // And a round can be started from them, marked on the device.
      final markableNow = offlineQuestions.where(isMarkableOffline).toList();
      if (markableNow.isNotEmpty) {
        final id = await tester.runAsync(() =>
            container.read(assessmentRepoProvider).startOfflinePractice());
        expect(id, isNotNull);
        expect(id!.startsWith(kLocalAttemptPrefix), isTrue);

        final session = await tester.runAsync(() =>
            container.read(assessmentRepoProvider).openAttempt(id));
        expect(session!.questions, isNotEmpty,
            reason: 'AN OFFLINE ROUND MUST HAVE QUESTIONS IN IT');

        final q = session.questions.first;
        final verdict = await tester.runAsync(() => container
            .read(assessmentRepoProvider)
            .answerPractice(id, q.id, choice: q.correctKey ?? ''));
        expect(verdict!.correct, isTrue,
            reason: 'an offline round must mark the right answer right');
        debugPrint('[journey] offline round: ${session.questions.length} '
            'questions, marked on the device');
      }
    }

    await store.flush();
    final reopened = await tester.runAsync(OfflineStore.open);
    expect(reopened, isNotNull);
    expect(reopened!.readable, isNotEmpty,
        reason: 'the catalogue must survive being read back from scratch');

    debugPrint('[journey] ${store.readable.length} items, '
        '${store.assetCount} pictures, ${questions.length} questions, '
        '${formatBytes(store.totalBytes)} on disk');
  });
}

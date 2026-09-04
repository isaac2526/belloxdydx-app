import 'dart:convert' show Utf8Decoder;
import 'dart:io';

import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/core/providers.dart';
import 'package:belloxdydx/features/auth/auth_brand.dart';
import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/data/offline/course_downloader.dart';
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

  testWidgets('the signed-out screens still work, and carry the brand',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // This test may be the one that meets the onboarding carousel, so
    // it walks it rather than assuming a particular starting screen.
    await until(
      tester,
      () =>
          find.text('Log in').evaluate().isNotEmpty ||
          find.text('Skip').evaluate().isNotEmpty,
      budget: const Duration(seconds: 30),
    );
    final createFinder =
        find.textContaining(RegExp('Create free account|Create your account'));
    for (var i = 0; i < 6 && createFinder.evaluate().isEmpty; i++) {
      for (final label in const ['I already have an account', 'Skip']) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        await tap(tester, f.last);
        break;
      }
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Reached the way a student reaches it — not by pushing a route a
    // phone has no address bar for.
    final create = createFinder;
    expect(create.evaluate(), isNotEmpty,
        reason: 'Create Account must be reachable. On screen: ${visible()}');

    // If the login screen is the way through, its form sits inside the
    // 3D intro's IgnorePointer until the case has opened — a tap before
    // then lands on nothing at all.
    final skipIntro = find.text('Skip intro');
    if (skipIntro.evaluate().isNotEmpty) {
      await tap(tester, skipIntro);
      await until(
        tester,
        () => find.text('Replay intro').evaluate().isNotEmpty,
        budget: const Duration(seconds: 15),
      );
    }

    await tap(tester, create.first);
    await until(
      tester,
      () => find.textContaining('Step 1 of 3').evaluate().isNotEmpty,
      budget: const Duration(seconds: 15),
    );
    debugPrint('[auth] create account: ${visible()}');

    // The redesign's shape: the mark is on the page, progress is in the
    // chrome, and only the first step's fields are asked for. This is
    // the screen the complaint was about — "too many words competing
    // for attention and I can barely see our logo".
    expect(find.byType(BxAuthBrand), findsOneWidget,
        reason: 'the logo must be on the first screen of the product');
    expect(find.byType(BxStepBar), findsOneWidget,
        reason: 'progress belongs in the chrome, once');
    expect(find.textContaining('Step 1 of 3'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields.evaluate().length, lessThanOrEqualTo(3),
        reason: 'a step asks for two or three fields, not eight');

    // It advances, and it validates the step it is on rather than
    // reporting a mistake eight fields further down.
    await tester.enterText(fields.at(0), 'Bello');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(fields.at(1), 'Ayomide');
    await tester.pump(const Duration(milliseconds: 200));
    final next = find.text('Continue');
    if (next.evaluate().isNotEmpty) {
      await tap(tester, next.first);
      await tester.pump(const Duration(seconds: 1));
      debugPrint('[auth] step two: ${visible()}');
      expect(find.textContaining('Step 2 of 3'), findsOneWidget,
          reason: 'the wizard must advance');
    }

    // And back out to the login screen, which also carries the mark now.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    debugPrint('[auth] back: ${visible()}');
  });

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

    // ---- a first install opens LIGHT ---------------------------------
    // Whatever the phone is set to. Belloxdydx is a white-and-gold
    // product and the first thing a student sees should be the product,
    // not their own night setting. "System" stays available and is
    // honoured the moment it is chosen; it is simply not the starting
    // position.
    expect(container.read(themeProvider), ThemeMode.light,
        reason: 'a brand new install must open light');

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

    // ---- the Download button, one whole course ------------------------
    //
    // "every course should have its own download materials button and it
    //  must download all the materials ... Even questions oo, it should
    //  pull everything ... it must be sure that everything was
    //  downloaded"
    //
    // The background sync above is careful with a student's data bundle
    // because they did not ask for it. This one they asked for by name,
    // so it must bring down EVERYTHING, and it must be able to say
    // whether it did.
    final course = container.read(contentRepoProvider).courses.first;

    await tester.runAsync(
        () => container.read(courseStampsProvider.notifier).refresh(force: true));
    await tester.pump(const Duration(seconds: 1));
    final stamp = container.read(courseStampsProvider)[course.id];
    expect(stamp, isNotNull,
        reason: 'the manifest must know this course');
    expect(stamp!.questions, greaterThan(0),
        reason: 'a manifest that reports no questions cannot raise a badge');
    debugPrint('[journey] manifest ${course.code}: '
        '${stamp.materials} materials, ${stamp.questions} questions');

    // The answer-key trade, checked at the wire rather than inferred:
    // questions pinned to a published test must NOT come down, however
    // offline the phone is.
    final firstPage = await tester.runAsync(() => container
        .read(contentRepoProvider)
        .courseBundle(course.id, part: 'questions', limit: 400));
    expect(firstPage, isNotNull);
    expect(firstPage!.withheld, greaterThan(0),
        reason: 'the mock pins two questions to a published test; a bundle '
            'that hands them over is the one version of this feature that '
            'costs Tutor Bello something');
    expect(firstPage.questions.length, lessThan(firstPage.questionTotal),
        reason: 'the pinned ones must actually be missing from the payload, '
            'not merely counted');
    expect(firstPage.questionsIncluded, isTrue);
    debugPrint('[journey] bundle: ${firstPage.questions.length} of '
        '${firstPage.questionTotal} questions, '
        '${firstPage.withheld} withheld');

    final before = await tester.runAsync(() => store.questions(course.id)) ??
        const <Map<String, dynamic>>[];
    final markableBefore = before.where(isMarkableOffline).length;

    await tester.runAsync(() =>
        container.read(courseDownloadProvider(course.id).notifier).start());
    await tester.pump(const Duration(seconds: 2));

    final download = container.read(courseDownloadProvider(course.id));
    debugPrint('[journey] download: ${download.phase.name} · '
        '${download.label} · ${download.questions} questions · '
        '${download.materials} files · ${download.assets} pictures · '
        '${formatBytes(download.bytes)} · ${download.failed} failed');
    expect(download.phase, CourseDownloadPhase.done,
        reason: 'A COURSE DOWNLOAD MUST REPORT HONESTLY. '
            'It said: ${download.label} / ${download.message}');
    expect(download.held, isTrue);
    expect(download.updateAvailable, isFalse,
        reason: 'a course that has just been downloaded whole cannot also '
            'have an update waiting');
    expect(download.failed, 0,
        reason: 'every file it went for must be on the disk — that is what '
            '"it must be sure that everything was downloaded" means');

    // What is actually on the phone, read off the disk.
    final after = await tester.runAsync(() => store.questions(course.id)) ??
        const <Map<String, dynamic>>[];
    expect(after.length, greaterThanOrEqualTo(firstPage.questions.length),
        reason: 'THE WHOLE BANK MUST BE ON THE PHONE');
    final markableAfter = after.where(isMarkableOffline).length;
    expect(markableAfter, greaterThanOrEqualTo(markableBefore),
        reason: 'a download must never lose a key it already held');
    expect(markableAfter, greaterThanOrEqualTo(20),
        reason: 'a bank the phone cannot MARK is not an offline bank');
    debugPrint('[journey] on the phone: ${after.length} questions, '
        '$markableAfter markable (was $markableBefore)');

    // And it survives being read back from a fresh catalogue, which is
    // what the next launch does.
    final record = store.courseRecord(course.id);
    expect(record, isNotNull);
    expect(record!['ok'], isTrue);
    expect(record['questions'], stamp.questions,
        reason: 'the record holds the MANIFEST count, not what was saved — '
            'they differ by the withheld ones, and storing what was saved '
            'would leave the badge lit forever');

    // ---- "there's a change in course, download now" -------------------
    //
    // Tutor Bello adds a question. Nothing about the phone changes. The
    // badge has to appear on its own.
    final published = await tester.runAsync(() async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('$backend/__test/publish'));
        req.headers.contentType = ContentType.json;
        req.write('{"courseId":"${course.id}"}');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        client.close();
      }
    });
    expect(published, 200, reason: 'the test hook must have fired');

    await tester.runAsync(
        () => container.read(courseStampsProvider.notifier).refresh(force: true));
    await tester.pump(const Duration(seconds: 1));
    final stale = container.read(courseDownloadProvider(course.id));
    expect(stale.updateAvailable, isTrue,
        reason: 'A QUESTION TUTOR BELLO ADDS MUST RAISE THE BADGE. '
            'Manifest now: ${container.read(courseStampsProvider)[course.id]?.questions}');
    expect(stale.held, isTrue,
        reason: 'an update is a different sentence from a first download');
    debugPrint('[journey] badge raised: "there is a change in '
        '${course.code}"');

    // Updating clears it, and only fetches what is missing.
    await tester.runAsync(() =>
        container.read(courseDownloadProvider(course.id).notifier).start());
    await tester.pump(const Duration(seconds: 2));
    final updated = container.read(courseDownloadProvider(course.id));
    expect(updated.phase, CourseDownloadPhase.done,
        reason: 'the update said: ${updated.label} / ${updated.message}');
    expect(updated.updateAvailable, isFalse,
        reason: 'a badge that survives the update it asked for is a badge '
            'nobody will trust twice');
    debugPrint('[journey] badge cleared after update');

    // ---- ANYTHING Tutor Bello changes reaches a RUNNING app ----------
    //
    // "if we change anything in the website in the backend like courses,
    //  Level or we freeze account any fucking thing that I didn't even
    //  say ... there's a lot of things I can't say"
    //
    // Three changes that the per-course manifest, as first built, could
    // not see AT ALL. Each is made while the app is open, and each must
    // move the one counter the database keeps.
    Future<Map<String, dynamic>> hit(String path, [String body = '{}']) async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('$backend$path'));
        req.headers.contentType = ContentType.json;
        req.write(body);
        final res = await req.close();
        final text = await res.transform(const Utf8Decoder()).join();
        return {'status': res.statusCode, 'body': text};
      } finally {
        client.close();
      }
    }

    Future<int> revNow() async {
      final r = await tester
          .runAsync(() => container.read(contentRepoProvider).revision());
      return r?.rev ?? 0;
    }

    final revBefore = await revNow();
    expect(revBefore, greaterThan(0),
        reason: 'the backend must be keeping a content revision at all');
    debugPrint('[journey] revision starts at $revBefore');

    // 1 · a course RENAMED. No material, no question, no timestamp on
    //     either of them moves. The original design was blind to this.
    var res = await tester.runAsync(
        () => hit('/__test/rename-course', '{"courseId":"${course.id}"}'));
    expect(res!['status'], 200);
    final revAfterRename = await revNow();
    expect(revAfterRename, greaterThan(revBefore),
        reason: 'RENAMING A COURSE MUST MOVE THE SIGNAL');
    debugPrint('[journey] course renamed -> revision $revBefore '
        '-> $revAfterRename');

    // 2 · a question PINNED to a published test. This changes which
    //     questions the bundle withholds — so it changes the correct
    //     content of a download — while every count and every stamp
    //     stays exactly where it was.
    final beforePin = container.read(courseStampsProvider)[course.id];
    res = await tester
        .runAsync(() => hit('/__test/pin', '{"courseId":"${course.id}"}'));
    expect(res!['status'], 200);
    await tester.runAsync(() =>
        container.read(courseStampsProvider.notifier).refresh(force: true));
    await tester.pump(const Duration(seconds: 1));
    final afterPin = container.read(courseStampsProvider)[course.id];
    expect(afterPin, isNotNull);
    expect(afterPin!.questions, beforePin!.questions,
        reason: 'the point of this case is that the count does NOT move');
    expect(afterPin.questionStamp, beforePin.questionStamp,
        reason: 'nor does the question timestamp');
    expect(afterPin.pinPrint, isNot(beforePin.pinPrint),
        reason: 'A PIN SWAP MUST STILL BE CAUGHT — otherwise the phone '
            'keeps the key to a question that is now on an exam');
    expect(afterPin.differsFrom(store.courseRecord(course.id)), isTrue,
        reason: 'and it must raise the badge');
    debugPrint('[journey] question pinned -> pins '
        '${beforePin.pins} -> ${afterPin.pins}, checksum changed, '
        'counts unmoved');

    // 3 · a question WITHDRAWN. It must leave the phone, and pruning
    //     must not touch the ones merely withheld.
    await tester.runAsync(() =>
        container.read(courseDownloadProvider(course.id).notifier).start());
    await tester.pump(const Duration(seconds: 1));
    final heldBefore =
        (await tester.runAsync(() => store.questions(course.id)))!.length;

    res = await tester
        .runAsync(() => hit('/__test/withdraw', '{"courseId":"${course.id}"}'));
    expect(res!['status'], 200);
    await tester.runAsync(() =>
        container.read(courseDownloadProvider(course.id).notifier).start());
    await tester.pump(const Duration(seconds: 1));
    final heldAfter =
        (await tester.runAsync(() => store.questions(course.id)))!.length;

    expect(heldAfter, lessThan(heldBefore),
        reason: 'A QUESTION TUTOR BELLO WITHDREW MUST LEAVE THE PHONE — '
            'it used to stay for ever, practisable, with its answer key');
    final index = await tester
        .runAsync(() => container.read(contentRepoProvider).courseIndex(course.id));
    expect(heldAfter, lessThanOrEqualTo(index!.questionIds.length),
        reason: 'and nothing the server still publishes may be dropped');
    debugPrint('[journey] question withdrawn -> on the phone '
        '$heldBefore -> $heldAfter (server still publishes '
        '${index.questionIds.length})');

    // ---- Tutor Bello closes the level the student is standing on -----
    //
    // Deactivating a level on the website unpublishes it. Every student
    // on it then asked for a shelf that no longer exists, got an empty
    // one, and — because the level switcher only appeared when there
    // were two or more levels to choose from — lost the one control
    // that could have moved them off it. On the path production runs
    // it was worse still: /api/mobile/content never sent `levels` at
    // all, so the switcher had nothing to draw and opening a new level
    // on the website reached nobody.
    res = await tester
        .runAsync(() => hit('/__test/close-level', '{"level":"100"}'));
    expect(res!['status'], 200);

    await tester.runAsync(() => container
        .read(contentRepoProvider)
        .loadContent(level: '100', force: true));
    final repo = container.read(contentRepoProvider);
    expect(repo.levels, isNotEmpty,
        reason: 'THE APP MUST BE TOLD WHICH LEVELS EXIST. Without this '
            'the switcher is blank on the path production runs, and a '
            'student whose level Bello closed can never leave it.');
    expect(repo.levels.map((l) => l.code), isNot(contains('100')),
        reason: 'a closed level is not offered');
    debugPrint('[journey] level closed -> the app is offered '
        '${repo.levels.map((l) => l.code).join(', ')} instead');

    // ---- a revocation reaches a RUNNING app --------------------------
    //
    // Tutor Bello presses "Force logout" (or resets the device). The
    // panel says "Session killed ✓" either way. On the direct path the
    // app is not polling — it watches its own active_sessions row over
    // Realtime, and that watcher maps an empty result to "still mine"
    // ON PURPOSE, because an empty result is also what a race looks
    // like and treating it as theft logged students out at random the
    // first time this ran. The cost was that a deliberate revocation
    // looked exactly like a race, so the student stayed signed in for
    // ever.
    //
    // Checked at the repository, because driving a three-minute timer
    // in a widget test proves nothing about the mechanism.
    res = await tester.runAsync(() => hit('/__test/force-logout'));
    expect(res!['status'], 200);

    final pulse = await tester
        .runAsync(() => container.read(authRepoProvider).standingNow());
    expect(pulse, isNotNull);
    expect(pulse!.alive, isFalse,
        reason: 'A FORCE LOGOUT MUST REACH A RUNNING APP. The panel says '
            '"Session killed" and on this path nothing ever happened.');
    debugPrint('[journey] force logout -> the app is told its session '
        'ended');

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

      // TUTOR BELLO'S DATE SURVIVES THE SERVER BEING GONE.
      //
      // The manifest lived in memory only, so the one line the owner
      // asked for — "Tutor Bello last updated this" — existed only
      // while the phone had a connection. Open the app on the bus with
      // the data off and every course on the shelf went back to saying
      // nothing, on the app whose whole point is working offline.
      //
      // A fresh notifier is built here deliberately: that is what a
      // cold start does, and it must find the answer on the disk.
      final cold = ProviderContainer();
      addTearDown(cold.dispose);
      final restored = cold.read(courseStampsProvider);
      expect(restored, isNotEmpty,
          reason: 'THE SHELF MUST STILL KNOW WHEN BELLO LAST UPDATED '
              'EACH COURSE WITH THE SERVER GONE');
      expect(restored[course.id]?.updatedAt, isNotNull,
          reason: 'and it must be a real date, not an empty stamp');
      debugPrint('[journey] Bello date after a cold start with no server: '
          '${restored[course.id]!.updatedAt}');

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

      // A DOWNLOADED PDF OPENS WITH THE SERVER GONE.
      //
      // "when I downloaded some pdf, it showed in the offline vault
      //  that it's downloaded, when I put off my internet connection it
      //  was saying that internet connection issues"
      //
      // The reader asks for the material before it asks for the file,
      // and that lookup's offline fallback only ever recognised a saved
      // NOTE — so a slide sitting complete on the disk threw a network
      // error before anything got as far as looking at the disk.
      final savedDoc = store.readable
          .where((i) => i.hasDoc && i.courseId == course.id)
          .firstOrNull;
      expect(savedDoc, isNotNull,
          reason: 'the course download must have put a document on the '
              'disk. Held: ${store.readable.map((i) => i.kind).toSet()}');
      final docMaterial = await tester.runAsync(
          () => container.read(contentRepoProvider).material(savedDoc!.id));
      expect(docMaterial, isNotNull,
          reason: 'A SAVED PDF MUST NOT REPORT A CONNECTION PROBLEM');
      final docPath =
          await tester.runAsync(() => store.documentPath(savedDoc!.id));
      expect(docPath, isNotNull);
      final onDisk =
          await tester.runAsync(() => File(docPath!).readAsBytes());
      expect(onDisk!.length, greaterThan(4));
      expect(String.fromCharCodes(onDisk.take(4)), '%PDF',
          reason: 'the vaulted copy must be the real document, not a '
              'placeholder the reader will refuse to draw');
      debugPrint('[journey] saved PDF opened offline: '
          '${docMaterial!.title} · ${onDisk.length} bytes');

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

        // Answered the way the question actually asks. The pool is
        // shuffled and contains short-answer questions, which have no
        // key at all — sending a choice to one of those is wrong and
        // was making this assertion pass or fail on the shuffle.
        final q = session.questions.first;
        final isTyped = q.type == QuestionType.shortAnswer;
        final verdict = await tester.runAsync(() =>
            container.read(assessmentRepoProvider).answerPractice(
                  id,
                  q.id,
                  choice: isTyped ? '' : (q.correctKey ?? ''),
                  answerText: isTyped ? q.acceptedAnswer : '',
                ));
        expect(verdict!.correct, isTrue,
            reason: 'an offline round must mark the right answer right, '
                'whatever kind of question it is (this one is '
                '${q.type.name})');

        // And a wrong one wrong, which is the half that proves it is
        // marking rather than agreeing.
        final second = session.questions.length > 1
            ? session.questions[1]
            : session.questions.first;
        final wrongTyped = second.type == QuestionType.shortAnswer;
        final wrong = await tester.runAsync(() =>
            container.read(assessmentRepoProvider).answerPractice(
                  id,
                  second.id,
                  choice: wrongTyped ? '' : 'ZZ',
                  answerText: wrongTyped ? 'definitely not the answer' : '',
                ));
        expect(wrong!.correct, isFalse,
            reason: 'an offline round that marks everything right is not '
                'marking');
        debugPrint('[journey] offline round: ${session.questions.length} '
            'questions, marked on the device');
      }

      // And the course a student DOWNLOADED opens a round of its own,
      // by course, with the server gone. This is the sentence the
      // complaint was about: "the practice questions like it can't work
      // offline even there's no place to download them".
      final downloadedRound = await tester.runAsync(() => container
          .read(assessmentRepoProvider)
          .startPracticeOrOffline(course.id));
      expect(downloadedRound, isNotNull,
          reason: 'A DOWNLOADED COURSE MUST PRACTISE WITH NO SERVER');
      final downloadedSession = await tester.runAsync(() =>
          container.read(assessmentRepoProvider).openAttempt(downloadedRound!));
      expect(downloadedSession, isNotNull);
      expect(downloadedSession!.questions, isNotEmpty);
      debugPrint('[journey] downloaded course practised offline: '
          '${downloadedSession.questions.length} questions');
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

import 'dart:io';

import 'package:belloxdydx/data/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    docs = await Directory.systemTemp.createTemp('bx_probe');
    PathProviderPlatform.instance = _FakePaths(docs.path);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    Offline.store = null;
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<OfflineStore> open() async => (await OfflineStore.open())!;

  test('PROBE 1: bodyless note that already has a doc row fails verifyItem',
      () async {
    final store = await open();
    // What the OLD build wrote when the student tapped Save on a note
    // whose only content was a clipped PDF: putDocument under the
    // NOTE's own id, kind 'note', no html.
    await store.putDocument(
      id: 'm1',
      title: 'Episode 2',
      kind: 'note',
      bytes: List<int>.filled(4096, 7),
      extension: 'pdf',
      courseId: 'phy102',
      sig: 'v1',
    );
    expect(await store.verifyItem('m1'), isTrue, reason: 'doc alone verifies');

    // The new build downloads the course. _saveNote saves the empty body.
    await store.putNote(
      id: 'm1',
      title: 'Episode 2',
      html: '',
      courseId: 'phy102',
      sig: 'v1',
      pinned: true,
      attachments: const [OfflineAttachment(title: 'Slide', url: 'u', kind: 'pdf')],
    );
    final i = store.item('m1')!;
    print('  docRel=${i.docRel} htmlRel=${i.htmlRel} bytes=${i.bytes} hasDoc=${i.hasDoc}');
    print('  PDF still on disk: ${await File(store.resolve(i.docRel!)).length()} bytes');
    print('  verifyItem => ${await store.verifyItem('m1')}');
    expect(await store.verifyItem('m1'), isTrue,
        reason: 'the PDF is right there on the disk');
  });

  test('PROBE 2: forgetCourse leaves the served ring behind', () async {
    final store = await open();
    await store.putQuestions('phy102', [
      {'id': 'q1'},
      {'id': 'q2'},
    ], complete: true);
    await store.rememberServed('phy102', ['q1', 'q2']);
    await store.putCourseRecord('phy102',
        materials: 0, questions: 2, stamp: 's', ok: true);
    await store.forgetCourse('phy102');
    await store.flush();
    print('  after forgetCourse: recentlyServed=${store.recentlyServed('phy102')}');
    final raw = await File('${store.rootPath}/index.json').readAsString();
    print('  index.json contains q1: ${raw.contains('"q1"')}');
    final reopened = (await OfflineStore.open())!;
    print('  after reopen:  recentlyServed=${reopened.recentlyServed('phy102')}');
    expect(store.recentlyServed('phy102'), isEmpty,
        reason: 'the course was removed from the phone entirely');
  });

  test('PROBE 3: forgetAsset does not flush', () async {
    final store = await open();
    await store.putAsset('https://x/y.png', List<int>.filled(10, 1));
    await store.flush();
    await store.forgetAsset('https://x/y.png');
    final raw = await File('${store.rootPath}/index.json').readAsString();
    print('  index.json still lists the asset after forgetAsset: '
        '${raw.contains(assetKeyFor('https://x/y.png'))}');
    // Simulate the process dying before the 2.5s timer.
    final reopened = (await OfflineStore.open())!;
    print('  reopened.hasAsset => ${reopened.hasAsset('https://x/y.png')}');
    print('  reopened.assetPath exists => '
        '${reopened.assetPath('https://x/y.png') != null ? await File(reopened.assetPath('https://x/y.png')!).exists() : null}');
  });
}

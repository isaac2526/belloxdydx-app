import 'package:belloxdydx/core/security.dart';
import 'package:belloxdydx/data/backend.dart';
import 'package:belloxdydx/data/local_store.dart';
import 'package:belloxdydx/data/models.dart';
import 'package:belloxdydx/data/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// OPENING THE APP
///
/// Two complaints, one cause.
///
///   "after I signed in, when I went back it's telling me to sign-in
///    again, instead of it should open the dashboard"
///   "the app sometimes takes long to load"
///
/// Boot used to await a capability probe (up to eight seconds on a bad
/// line) and then a profile read (two more requests) before the router
/// was allowed off the splash — and if either failed, which offline it
/// always does, it published `signedOut` and the student was shown a
/// login screen for an account they had never left.
///
/// The fix is that the phone remembers, synchronously, and the network
/// only ever gets to make things better. These tests pin the remembering
/// down: if any of them goes red, the login screen is back.
/// ============================================================

Future<LocalStore> storeWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  LocalStore.resetForTest();
  return LocalStore.init();
}

Map<String, dynamic> profileJson({
  String id = 'stu-1',
  bool frozen = false,
}) =>
    {
      'id': id,
      'surname': 'Bello',
      'first_name': 'Ayomide',
      'username': 'ayo',
      'email': 'ayo@example.com',
      'current_level': '100',
      'is_activated': true,
      'is_frozen': frozen,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the phone remembers who is signed in, with no await', () {
    test('an empty install remembers nobody', () async {
      final store = await storeWith({});
      expect(store.readJsonSync(BxKeys.cachedProfile), isNull);
      expect(AuthRepository(Backend(), store).rememberedProfile(), isNull);
    });

    test('a mirrored write comes back synchronously', () async {
      final store = await storeWith({});
      await store.writeJson(BxKeys.cachedProfile, profileJson(), mirror: true);

      // No await between the launch and the answer. This is the whole
      // point: a Future here is a frame of splash screen, and a frame of
      // splash screen is where the login screen used to appear.
      final raw = store.readJsonSync(BxKeys.cachedProfile);
      expect(raw, isNotNull);
      expect(raw!['username'], 'ayo');
    });

    test('the remembered student is a real profile, not a husk', () async {
      final store = await storeWith({});
      await store.writeJson(BxKeys.cachedProfile, profileJson(), mirror: true);

      final p = AuthRepository(Backend(), store).rememberedProfile();
      expect(p, isNotNull);
      expect(p!.id, 'stu-1');
      expect(p.firstName, 'Ayomide');
      expect(p.currentLevel, '100');
    });

    test('a row with no id is not somebody', () async {
      // Half-written cache, an interrupted sign-in, a cleared account:
      // opening a dashboard on this would be showing a student somebody
      // else's app, or nobody's.
      final store = await storeWith({});
      await store.writeJson(
        BxKeys.cachedProfile,
        {'username': 'ghost'},
        mirror: true,
      );
      expect(AuthRepository(Backend(), store).rememberedProfile(), isNull);
    });

    test('a platform with no documents directory still boots fast', () async {
      // Web, and this test runner, have nowhere to put a cache file, so
      // everything falls back to preferences. The fast path must keep
      // working there rather than quietly returning null and sending the
      // student to a login screen.
      final store = await storeWith({});
      await store.writeJson(BxKeys.cachedProfile, profileJson());
      expect(AuthRepository(Backend(), store).rememberedProfile()?.id,
          'stu-1');
    });

    test('a frozen student is still remembered', () async {
      // Frozen is a state of the account, not of the session. Booting a
      // frozen student to the login screen would tell them the wrong
      // thing about why they cannot get in.
      final store = await storeWith({});
      await store.writeJson(
        BxKeys.cachedProfile,
        profileJson(frozen: true),
        mirror: true,
      );
      final p = AuthRepository(Backend(), store).rememberedProfile();
      expect(p, isNotNull);
      expect(p!.isFrozen, isTrue);
    });

    test('garbage in the mirror is not a crash on launch', () async {
      final store = await storeWith({'cache:${BxKeys.cachedProfile}': '{{{'});
      expect(store.readJsonSync(BxKeys.cachedProfile), isNull);
      expect(AuthRepository(Backend(), store).rememberedProfile(), isNull);
    });

    test('adopt seeds the repository without overwriting a live read',
        () async {
      final store = await storeWith({});
      final repo = AuthRepository(Backend(), store);
      final remembered = Profile.fromJson(profileJson());
      repo.adopt(remembered);
      expect(repo.cachedProfile?.id, 'stu-1');

      // A second adopt must not undo a fresher profile.
      repo.adopt(Profile.fromJson(profileJson(id: 'stu-2')));
      expect(repo.cachedProfile?.id, 'stu-1');
    });
  });

  group('the app starts on the path it used last time', () {
    test('nothing stored means legacy, which is what production runs', () {
      final b = Backend();
      b.restoreMode(null);
      expect(b.mode, BackendMode.legacy);
    });

    test('a stored direct mode is honoured before the probe answers', () {
      final b = Backend();
      b.restoreMode('direct');
      expect(b.isDirect, isTrue);
    });

    test('anything unrecognised is legacy', () {
      for (final v in ['', 'DIRECT', 'supabase', 'legacy']) {
        final b = Backend();
        b.restoreMode(v);
        expect(b.mode, BackendMode.legacy, reason: 'stored value "$v"');
      }
    });
  });

  group('the lock is on before the first frame', () {
    // "Also the device lock isn't working."
    //
    // It came up open, always. Every timer and idle stamp lived in RAM,
    // so a phone reclaiming memory — which is what a phone does to a
    // backgrounded app within minutes — reset all of it. The lock only
    // guarded a session that was never interrupted, which is the one
    // case that does not need guarding.
    int agoMs(Duration d) =>
        DateTime.now().subtract(d).millisecondsSinceEpoch;

    test('a signed-out app never comes up locked', () async {
      final store = await storeWith({BxKeys.lockAfterMs: agoMs(const Duration(days: 3))});
      expect(
        AppLockNotifier.startStateForTest(store, false),
        BxLockState.open,
        reason: 'a lock screen over a login form is a dead end',
      );
    });

    test('a session with no recorded activity comes up locked', () async {
      final store = await storeWith({});
      expect(AppLockNotifier.startStateForTest(store, true),
          BxLockState.locked);
    });

    test('yesterday means locked', () async {
      final store =
          await storeWith({BxKeys.lockAfterMs: agoMs(const Duration(hours: 14))});
      expect(AppLockNotifier.startStateForTest(store, true),
          BxLockState.locked);
    });

    test('a relaunch seconds after a kill does not nag', () async {
      // The exact case the student complains about: the phone killed the
      // app to reclaim RAM and they reopened it straight away. Asking
      // for a fingerprint here would be punishing them for their phone.
      final store =
          await storeWith({BxKeys.lockAfterMs: agoMs(const Duration(seconds: 20))});
      expect(
          AppLockNotifier.startStateForTest(store, true), BxLockState.open);
    });

    test('five minutes is the line', () async {
      final justUnder =
          await storeWith({BxKeys.lockAfterMs: agoMs(const Duration(minutes: 4, seconds: 30))});
      expect(AppLockNotifier.startStateForTest(justUnder, true),
          BxLockState.open);

      final justOver =
          await storeWith({BxKeys.lockAfterMs: agoMs(const Duration(minutes: 5, seconds: 30))});
      expect(AppLockNotifier.startStateForTest(justOver, true),
          BxLockState.locked);
    });

    test('a student who turned the lock off is not locked out', () async {
      final store = await storeWith({
        BxKeys.biometricOn: false,
        BxKeys.lockAfterMs: agoMs(const Duration(days: 2)),
      });
      expect(
          AppLockNotifier.startStateForTest(store, true), BxLockState.open);
    });

    test('the lock is on by default — it is not opt-in', () async {
      final store = await storeWith({
        BxKeys.lockAfterMs: agoMs(const Duration(days: 2)),
      });
      expect(AppLockNotifier.startStateForTest(store, true),
          BxLockState.locked);
    });
  });
}

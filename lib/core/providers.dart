import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_bridge.dart';
import 'security.dart';
import '../data/backend.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../data/offline/offline_store.dart';
import '../data/offline/sync_engine.dart';
import '../data/repositories.dart';

/// ============================================================
/// PROVIDERS
/// One place where the app's services and shared state are wired.
/// ============================================================

final localStoreProvider = Provider<LocalStore>(
  (_) => LocalStore.instance,
);

final backendProvider = Provider<Backend>((ref) {
  final b = Backend();
  ref.onDispose(b.dispose);
  return b;
});

final authRepoProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(backendProvider), ref.watch(localStoreProvider)),
);

final contentRepoProvider = Provider<ContentRepository>(
  (ref) =>
      ContentRepository(ref.watch(backendProvider), ref.watch(localStoreProvider)),
);

final assessmentRepoProvider = Provider<AssessmentRepository>(
  (ref) => AssessmentRepository(ref.watch(backendProvider), Offline.store),
);

/// The lock. One per app, and it watches the lifecycle itself.
final appLockProvider = StateNotifierProvider<AppLockNotifier, BxLockState>(
  (ref) => AppLockNotifier(ref.watch(localStoreProvider)),
);

/// What Tutor Bello has switched on for every phone. Read from the
/// content bootstrap, so it costs no extra call.
final appPolicyProvider = StateProvider<AppPolicy>((_) => const AppPolicy());

/// What the platform underneath can actually enforce — which is not the
/// same question, and answering them as if they were is how a settings
/// toggle ends up lying to a student.
final screenshotPolicyProvider =
    FutureProvider.autoDispose<ScreenshotPolicy>((ref) {
  ref.watch(appPolicyProvider);
  return ScreenCapture.describe();
});

/// The offline root. Opened once in main() before runApp, so a widget
/// can ask it a question during build without awaiting anything.
final offlineStoreProvider = Provider<OfflineStore?>((_) => Offline.store);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    backend: ref.watch(backendProvider),
    content: ref.watch(contentRepoProvider),
    store: Offline.store,
  );
  engine.autoDocuments =
      ref.watch(localStoreProvider).getBool(BxKeys.autoDownloadDocs);
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

/// What the Vault screen and the dashboard banner watch.
final syncStatusProvider = StateNotifierProvider<SyncStatusNotifier, SyncStatus>(
  (ref) => SyncStatusNotifier(ref.watch(syncEngineProvider)),
);

class SyncStatusNotifier extends StateNotifier<SyncStatus> {
  SyncStatusNotifier(this._engine) : super(_engine.status) {
    _sub = _engine.updates.listen((s) {
      if (mounted) state = s;
    });
  }

  final SyncEngine _engine;
  StreamSubscription<SyncStatus>? _sub;

  Future<void> start({bool now = false, String? level}) => _engine.run(
        minInterval: now ? Duration.zero : const Duration(hours: 6),
        level: level,
      );

  void cancel() => _engine.cancel();

  set autoDocuments(bool v) => _engine.autoDocuments = v;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final engageRepoProvider = Provider<EngageRepository>(
  (ref) =>
      EngageRepository(ref.watch(backendProvider), ref.watch(localStoreProvider)),
);

// ------------------------------------------------------------
// Session
// ------------------------------------------------------------

/// The signed-in student's profile, or null when signed out. This is the
/// single source of truth the router reads to decide what to show.
class SessionNotifier extends StateNotifier<SessionState>
    with WidgetsBindingObserver {
  SessionNotifier(this._ref) : super(const SessionState.unknown()) {
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  final Ref _ref;
  StreamSubscription<bool>? _sessionWatch;
  DateTime _lastResumeWork = DateTime.fromMillisecondsSinceEpoch(0);

  /// Coming back to the app is when the backend's switches are re-read
  /// and the offline sync is nudged. This is what makes "no new build"
  /// literally true: a policy Tutor Bello changes this morning is being
  /// obeyed by lunchtime, and new material a student did not have keeps
  /// arriving without them asking.
  ///
  /// Throttled, because Android delivers `resumed` for things as small
  /// as dismissing a notification shade.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    if (!state.isSignedIn) return;
    final now = DateTime.now();
    if (now.difference(_lastResumeWork) < const Duration(minutes: 2)) return;
    _lastResumeWork = now;
    unawaited(() async {
      try {
        await _ref
            .read(syncStatusProvider.notifier)
            .start(level: state.profile?.currentLevel);
        await applyPolicy();
      } catch (e) {
        debugPrint('[resume] refresh skipped: $e');
      }
    }());
  }

  AuthRepository get _auth => _ref.read(authRepoProvider);
  Backend get _backend => _ref.read(backendProvider);

  Future<void> _boot() async {
    // Starts the radio watch before anything can fail, so the first
    // error a student sees already knows whether their phone has a
    // connection at all.
    _backend.watchConnectivity();
    await _backend.probeCapabilities();
    if (!_backend.signedIn) {
      state = const SessionState.signedOut();
      return;
    }
    await refreshProfile();
  }

  Future<void> refreshProfile() async {
    final Profile p;
    try {
      p = await _auth.loadProfile(force: true);
    } catch (e) {
      // Signed in but the profile could not be read — treat as signed out
      // rather than trapping the student on a blank screen. ONLY the
      // profile read may reach this: a fault anywhere else must not be
      // reported to the student as a failed login.
      state = SessionState.signedOut(
          message: e is BxError ? e.message : null);
      return;
    }

    state = p.isFrozen ? SessionState.frozen(p) : SessionState.active(p);
    _listenForSupersede();
    unawaited(_prepareOffline(p));
    unawaited(_checkDevice(p));
  }

  /// Stops a phone this account has never been opened on, once.
  ///
  /// Runs AFTER the state is already active, deliberately: a check that
  /// cannot reach the server must never be the thing that keeps a
  /// paying student out of the app. It fails open, and the
  /// single-live-session rule still stands behind it.
  Future<void> _checkDevice(Profile p) async {
    if (p.isFrozen) return;
    try {
      final standing = await _auth.deviceStanding();
      if (!mounted) return;
      if (standing.mustVerify &&
          _ref.read(contentRepoProvider).policy.deviceVerification &&
          state.status == SessionStatus.active) {
        state = SessionState.deviceCheck(p);
      }
    } catch (e) {
      debugPrint('[device] check skipped: $e');
    }
  }

  /// Called by the device-check screen once the code has been proved.
  Future<void> markDeviceTrusted() async {
    final p = state.profile;
    if (p == null) return;
    state = SessionState.active(p);
    await _ref.read(localStoreProvider).setBool(BxKeys.deviceTrusted, true);
  }

  /// Ties the offline root to this student and starts filling it.
  ///
  /// Deliberately not awaited and deliberately after the state write:
  /// the student is already inside the app while their notes come down
  /// behind them. Nothing here can fail a sign-in.
  Future<void> _prepareOffline(Profile p) async {
    try {
      final store = Offline.store;
      if (store == null) return;
      // Somebody else's downloads are not this student's to see.
      await store.claim(p.id);
      if (p.isFrozen) return;
      await _ref
          .read(syncStatusProvider.notifier)
          .start(level: p.currentLevel);
      await applyPolicy();
    } catch (e) {
      debugPrint('[offline] first sync skipped: $e');
    }
  }

  /// Watches for another device taking the session.
  ///
  /// Deliberately cannot fail the sign-in. This used to be attached
  /// inside the same try as the profile read, so when the watcher threw,
  /// the student was told their profile could not be read and the
  /// session they had just established was thrown away — silently,
  /// because both state writes happened in one synchronous block and the
  /// router only ever saw the last one. Losing the watcher costs the
  /// single-session rule until the next launch. Losing the session costs
  /// the student the app.
  void _listenForSupersede() {
    _sessionWatch?.cancel();
    _sessionWatch = null;
    try {
      _sessionWatch = _auth.watchSession().listen(
        (stillMine) {
          if (!stillMine) {
            signOut(
              reason:
                  'Signed in on another device. Only one login can be alive.',
            );
          }
        },
        onError: (_) {},
      );
    } catch (e) {
      debugPrint('[session] device watch unavailable: $e');
    }
  }

  /// Pushes the backend's switches onto the phone.
  ///
  /// Runs after the content bootstrap because that is what carries
  /// them, and again on every resume — which is what makes "no new
  /// build" true: a policy Tutor Bello changes this morning is being
  /// obeyed by lunchtime without anybody downloading anything.
  Future<void> applyPolicy() async {
    try {
      final policy = _ref.read(contentRepoProvider).policy;
      _ref.read(appPolicyProvider.notifier).state = policy;
      _ref.read(appLockProvider.notifier).policy = policy;
      await ScreenCapture.apply(policy);
    } catch (e) {
      debugPrint('[policy] not applied: $e');
    }
  }

  Future<void> onSignedIn() => refreshProfile();

  Future<void> signOut({String? reason}) async {
    _sessionWatch?.cancel();
    _sessionWatch = null;
    await _auth.signOut();
    state = SessionState.signedOut(message: reason);
  }

  /// Called after a successful activation so gates reopen immediately.
  void markActivated() {
    final p = state.profile;
    if (p != null) state = SessionState.active(p.copyWith(isActivated: true));
  }

  void setLevel(String level) {
    final p = state.profile;
    if (p != null) {
      state = SessionState.active(p.copyWith(currentLevel: level));
    }
  }

  @override
  void dispose() {
    _sessionWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

enum SessionStatus {
  unknown,
  signedOut,

  /// Signed in, but on a phone this account has never been opened on.
  /// Nothing inside is reachable until the student proves they hold the
  /// account's email — a shared password does not come with a shared
  /// inbox, which is the whole point.
  deviceCheck,

  active,
  frozen,
}

@immutable
class SessionState {
  final SessionStatus status;
  final Profile? profile;
  final String? message;

  const SessionState._(this.status, this.profile, this.message);
  const SessionState.unknown() : this._(SessionStatus.unknown, null, null);
  const SessionState.signedOut({String? message})
      : this._(SessionStatus.signedOut, null, message);
  const SessionState.active(Profile p) : this._(SessionStatus.active, p, null);
  const SessionState.deviceCheck(Profile p)
      : this._(SessionStatus.deviceCheck, p, null);
  const SessionState.frozen(Profile p) : this._(SessionStatus.frozen, p, null);

  bool get isSignedIn =>
      status == SessionStatus.active ||
      status == SessionStatus.frozen ||
      status == SessionStatus.deviceCheck;
  bool get isActivated => profile?.isActivated ?? false;
  bool get isReady => status != SessionStatus.unknown;
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Convenience: the profile, or an empty one so widgets never null-check.
final profileProvider = Provider<Profile>(
  (ref) => ref.watch(sessionProvider).profile ?? Profile.empty,
);

// ------------------------------------------------------------
// Theme
// ------------------------------------------------------------

/// Light, dark or follow-the-phone — and which one a brand new install
/// opens in.
///
/// A first install is LIGHT, whatever the phone is set to. Belloxdydx is
/// a white-and-gold product and the first thing a student sees should be
/// the product, not their own night setting. "System" remains available
/// and is honoured the moment it is chosen; it is simply not the
/// starting position.
///
/// The stored value is read synchronously in the constructor so the very
/// first frame is already correct — there is no light-to-dark swap after
/// launch.
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(this._store) : super(_read(_store)) {
    // Keep the native launch window in step from the very first run,
    // including the case where a student chose dark on a previous
    // install and the preference survived.
    NativeBridge.rememberLaunchTheme(_isDark(state, _store));
  }

  final LocalStore _store;

  static ThemeMode _read(LocalStore s) => switch (s.getString(BxKeys.themeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        // Nothing stored: this install has never been through the
        // Appearance control, so it opens light.
        _ => ThemeMode.light,
      };

  /// What the launch window should paint next time. "System" has to be
  /// resolved against the platform here, because Android needs a
  /// concrete colour before Flutter exists to ask.
  static bool _isDark(ThemeMode m, LocalStore s) => switch (m) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          PlatformDispatcher.instance.platformBrightness == Brightness.dark,
      };

  Future<void> set(ThemeMode m) async {
    state = m;
    await _store.setString(BxKeys.themeMode, m.name);
    await NativeBridge.rememberLaunchTheme(_isDark(m, _store));
  }

  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(ref.watch(localStoreProvider)),
);

// ------------------------------------------------------------
// Content
// ------------------------------------------------------------

/// Loads the course shelf and material index for the student's level.
final contentProvider = FutureProvider.autoDispose<ContentRepository>((ref) async {
  final repo = ref.watch(contentRepoProvider);
  final level = ref.watch(profileProvider).currentLevel;
  await repo.loadContent(level: level);
  ref.keepAlive();
  return repo;
});

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  // Rebuilds when the student activates or switches level.
  ref.watch(profileProvider);
  return ref.watch(engageRepoProvider).dashboard();
});

final announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) async {
  return ref.watch(engageRepoProvider).announcements();
});

final leaderboardProvider = FutureProvider.autoDispose<
    ({List<LeaderRow> top, LeaderRow me})>((ref) async {
  return ref.watch(engageRepoProvider).leaderboard();
});

final leagueProvider = FutureProvider.autoDispose<
    ({List<LeagueRow> table, List<MillionaireWinner> winners})>((ref) async {
  return ref.watch(engageRepoProvider).league();
});

final weakSpotsProvider =
    FutureProvider.autoDispose<List<WeakSpot>>((ref) async {
  return ref.watch(assessmentRepoProvider).weakSpots();
});

final bookmarkCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(assessmentRepoProvider).bookmarkCount();
});

final mistakesProvider =
    FutureProvider.autoDispose<List<Question>>((ref) async {
  return ref.watch(assessmentRepoProvider).mistakes();
});

final dailyProvider = FutureProvider.autoDispose<DailyChallenge?>((ref) async {
  return ref.watch(engageRepoProvider).daily();
});

final testsForCourseProvider = FutureProvider.autoDispose
    .family<List<StudyTest>, String>((ref, courseId) async {
  return ref.watch(assessmentRepoProvider).testsFor(courseId);
});

final materialProvider = FutureProvider.autoDispose
    .family<StudyMaterial, String>((ref, id) async {
  return ref.watch(contentRepoProvider).material(id);
});

final resultProvider =
    FutureProvider.autoDispose.family<ResultReview, String>((ref, id) async {
  return ref.watch(assessmentRepoProvider).result(id);
});

/// Which backend path is live — surfaced in Profile so the architecture
/// is visible rather than mysterious.
final backendModeProvider = Provider<BackendMode>(
  (ref) => ref.watch(backendProvider).mode,
);

// ------------------------------------------------------------
// Vault
// ------------------------------------------------------------

/// The Offline Vault's contents.
///
/// It reads the offline root rather than the old SharedPreferences blob.
/// The blob held absolute paths, which is a real defect on iOS — the app
/// container is a UUID that changes on restore — and it was also the
/// reason the vault could only ever contain whole documents a student
/// had remembered to tap Save on. It now contains everything the sync
/// put there too.
class VaultNotifier extends StateNotifier<List<OfflineItem>> {
  VaultNotifier(this._store) : super(_store?.readable ?? const []) {
    _reconcile();
  }

  final OfflineStore? _store;

  Future<void> _reconcile() async {
    final store = _store;
    if (store == null) return;
    await store.reconcile();
    if (mounted) state = store.readable;
  }

  void refresh() {
    final store = _store;
    if (store != null && mounted) state = store.readable;
  }

  bool isSaved(String materialId) => state.any((v) => v.id == materialId);

  Future<void> remove(String materialId) async {
    await _store?.removeItem(materialId);
    refresh();
  }
}

final vaultProvider = StateNotifierProvider<VaultNotifier, List<OfflineItem>>(
  (ref) => VaultNotifier(ref.watch(offlineStoreProvider)),
);

/// How much is on the phone, in one line for the Vault header.
final offlineSummaryProvider = FutureProvider.autoDispose<OfflineSummary>(
  (ref) async {
    // Recomputed whenever the catalogue or a sync changes.
    ref.watch(vaultProvider);
    ref.watch(syncStatusProvider);
    final store = ref.watch(offlineStoreProvider);
    if (store == null) return const OfflineSummary();
    final questions = await store.allQuestions();
    return OfflineSummary(
      items: store.readable.length,
      questions: questions.length,
      pictures: store.assetCount,
      bytes: store.totalBytes,
      syncedAtMs: store.syncedAtMs,
    );
  },
);

@immutable
class OfflineSummary {
  final int items;
  final int questions;
  final int pictures;
  final int bytes;
  final int syncedAtMs;

  const OfflineSummary({
    this.items = 0,
    this.questions = 0,
    this.pictures = 0,
    this.bytes = 0,
    this.syncedAtMs = 0,
  });

  bool get isEmpty => items == 0 && questions == 0;

  DateTime? get syncedAt => syncedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(syncedAtMs);
}

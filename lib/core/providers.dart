import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_bridge.dart';
import 'security.dart';
import '../data/backend.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../data/net_speed.dart';
import '../data/offline/course_downloader.dart';
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
  (ref) {
    final store = ref.watch(localStoreProvider);
    return AppLockNotifier(
      store,
      // Read synchronously, from the same mirrored profile boot uses, so
      // the very first frame is already either locked or not. Deciding
      // this a frame late means showing the dashboard to whoever picked
      // the phone up, which is the whole thing the lock exists to stop.
      hasSession: store.readJsonSync(BxKeys.cachedProfile) != null,
    );
  },
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

/// How fast the connection is right now, measured from the traffic the
/// app is already making. Never a synthetic speed test: spending a
/// student's airtime to tell them their airtime is slow is not a
/// feature.
final netSpeedProvider = StateNotifierProvider<NetSpeedNotifier, BxNetSpeed>(
  (ref) => NetSpeedNotifier(ref.watch(backendProvider).speed),
);

class NetSpeedNotifier extends StateNotifier<BxNetSpeed> {
  NetSpeedNotifier(this._meter) : super(_meter.value) {
    _meter.addListener(_onChange);
  }

  final NetSpeedMeter _meter;

  void _onChange() {
    if (mounted) state = _meter.value;
  }

  @override
  void dispose() {
    _meter.removeListener(_onChange);
    super.dispose();
  }
}

// ------------------------------------------------------------
// Downloading a course
// ------------------------------------------------------------

/// What the server is publishing right now, per course.
///
/// One cheap call, shared by every Download button on screen, refreshed
/// on a resume and after a download. This is the whole of the "there's
/// a change in this course, download now" badge.
class CourseStampsNotifier extends StateNotifier<Map<String, CourseStamp>> {
  CourseStampsNotifier(this._ref) : super(const {}) {
    _restore();
  }

  final Ref _ref;

  /// The manifest the last successful read produced, straight off the
  /// disk with nothing awaited.
  ///
  /// Without this the one line the owner asked for — "Tutor Bello last
  /// updated this" — existed only while the phone had a connection.
  /// Open the app on the bus with the data off and every course on the
  /// shelf went back to saying nothing, on the app whose whole point is
  /// working offline.
  void _restore() {
    try {
      final raw = _ref
          .read(localStoreProvider)
          .readJsonSync(BxKeys.cachedManifest);
      if (raw == null) return;
      final rows = raw['rows'];
      if (rows is! List) return;
      final restored = <String, CourseStamp>{};
      for (final r in rows) {
        if (r is! Map) continue;
        final stamp = CourseStamp.fromJson(Map<String, dynamic>.from(r));
        if (stamp.id.isNotEmpty) restored[stamp.id] = stamp;
      }
      if (restored.isEmpty) return;
      state = restored;
      // The revision this answer was read at, so a launch where nothing
      // has changed skips the manifest entirely rather than spending
      // forty-eight queries to discover that.
      _readAtRev = (raw['rev'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[course] held manifest unreadable: $e');
    }
  }
  DateTime _lastRead = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _inFlight;

  /// The revision the current answer was read at. When the backend has
  /// not moved past this, the per-course manifest is pure cost — on the
  /// website path it is three counts and three newest-row reads PER
  /// COURSE, so a shelf of eight courses is forty-eight queries to
  /// discover that nothing happened.
  int _readAtRev = 0;

  /// Throttled, because every course tile asks for it as it scrolls
  /// into view. Pass [force] after a download, when the answer has
  /// certainly changed.
  Future<void> refresh({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    if (!force &&
        DateTime.now().difference(_lastRead) < const Duration(minutes: 5)) {
      return Future.value();
    }
    final f = _read().whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  Future<void> _read() async {
    final repo = _ref.read(contentRepoProvider);
    try {
      // One tiny read first. If the backend has not moved since the
      // answer we are already holding, there is nothing to find and the
      // manifest is skipped entirely.
      if (state.isNotEmpty && _readAtRev > 0) {
        final rev = await repo.revision();
        if (rev.available && rev.rev == _readAtRev) {
          _lastRead = DateTime.now();
          return;
        }
      }

      final rows = await repo.manifest();
      if (!mounted) return;
      _lastRead = DateTime.now();
      _readAtRev = repo.lastManifestRev;
      state = {for (final r in rows) r.id: r};
      unawaited(_ref.read(localStoreProvider).writeJson(
            BxKeys.cachedManifest,
            {
              'rev': _readAtRev,
              'rows': [for (final r in rows) r.toJson()],
            },
            mirror: true,
          ));
    } catch (e) {
      // A manifest the app could not read is not an error a student
      // needs to see. The badge simply does not appear this time.
      debugPrint('[course] manifest skipped: $e');
    }
  }

}

final courseStampsProvider =
    StateNotifierProvider<CourseStampsNotifier, Map<String, CourseStamp>>(
  CourseStampsNotifier.new,
);

/// One Download button's state, per course.
///
/// A family rather than one notifier with a map, so a course hub can
/// watch its own course and rebuild for nothing else — and so two
/// downloads can never share a progress counter.
class CourseDownloadNotifier extends StateNotifier<CourseDownloadState> {
  CourseDownloadNotifier(this._ref, this.courseId)
      : _engine = CourseDownloader(
          backend: _ref.read(backendProvider),
          content: _ref.read(contentRepoProvider),
          store: Offline.store,
          courseId: courseId,
        ),
        super(_seed(courseId)) {
    state = _engine.state;
    _sub = _engine.updates.listen((s) {
      if (mounted) state = s;
    });
    // Whatever the manifest already says, applied without a call.
    _engine.applyStamp(_ref.read(courseStampsProvider)[courseId]);
    state = _engine.state;
    _ref.listen<Map<String, CourseStamp>>(courseStampsProvider, (_, next) {
      _engine.applyStamp(next[courseId]);
      if (mounted) state = _engine.state;
    });
  }

  final Ref _ref;
  final String courseId;
  final CourseDownloader _engine;
  StreamSubscription<CourseDownloadState>? _sub;

  static CourseDownloadState _seed(String courseId) =>
      CourseDownloadState(courseId: courseId);

  Future<void> start() async {
    await _engine.run();
    // The catalogue changed underneath anything watching it.
    _ref.read(offlineRecordTick.notifier).state++;
    // The badge is re-read from the server rather than assumed: a
    // question added while the download was running must still show up
    // as a change.
    await _ref.read(courseStampsProvider.notifier).refresh(force: true);
    if (mounted) {
      _engine.applyStamp(_ref.read(courseStampsProvider)[courseId]);
      state = _engine.state;
    }
  }

  void cancel() => _engine.cancel();

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_engine.dispose());
    super.dispose();
  }
}

final courseDownloadProvider = StateNotifierProvider.family<
    CourseDownloadNotifier, CourseDownloadState, String>(
  (ref, courseId) => CourseDownloadNotifier(ref, courseId),
);

/// How many courses on this shelf have something new waiting. Read by
/// the dashboard so the badge is visible before a student opens the
/// course list.
/// Courses this phone still holds that the backend no longer publishes.
///
/// Tutor Bello deleting a course, hiding it, or moving it to another
/// level leaves every note, PDF, picture and question of it sitting on
/// the phone — openable, practisable, indistinguishable from material
/// he still stands behind. Nothing ever told the student.
///
/// "Missing from the manifest" is NOT enough to conclude this: the
/// manifest is filtered to the student's current level, so a course
/// they simply are not standing on right now looks exactly like a
/// deleted one. Deleting a student's downloaded material because they
/// switched level would be unforgivable, so each candidate is asked
/// about directly and only a positive answer counts.
class WithdrawnCoursesNotifier extends StateNotifier<Set<String>> {
  WithdrawnCoursesNotifier(this._ref) : super(const {}) {
    _ref.listen<Map<String, CourseStamp>>(
      courseStampsProvider,
      (_, next) => unawaited(_check(next)),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  bool _busy = false;

  Future<void> _check(Map<String, CourseStamp> shelf) async {
    if (_busy || shelf.isEmpty) return;
    final store = _ref.read(offlineStoreProvider);
    if (store == null) return;

    final candidates = store.downloadedCourses
        .where((id) => !shelf.containsKey(id))
        .toList(growable: false);
    if (candidates.isEmpty) {
      if (mounted && state.isNotEmpty) state = const {};
      return;
    }

    _busy = true;
    try {
      final repo = _ref.read(contentRepoProvider);
      final gone = <String>{};
      for (final id in candidates) {
        final verdict = await repo.isCourseWithdrawn(id);
        // null means the question could not be asked. Silence is not a
        // yes.
        if (verdict == true) gone.add(id);
      }
      if (mounted) state = gone;
    } catch (e) {
      debugPrint('[course] withdrawal check skipped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Clears them off the phone and stops asking.
  ///
  /// Without this the banner was permanent: nothing anywhere called
  /// forgetCourseRecord, so `downloadedCourses` kept yielding the dead
  /// course, the check kept saying "withdrawn", and the banner stayed
  /// up for the life of the install — telling the student to open the
  /// Vault and clear something the Vault cannot show them, because the
  /// question bank is filtered out of it.
  Future<int> clear() async {
    final store = _ref.read(offlineStoreProvider);
    if (store == null || state.isEmpty) return 0;
    var freed = 0;
    for (final id in state.toList()) {
      try {
        freed += await store.forgetCourse(id);
      } catch (e) {
        debugPrint('[course] could not clear $id: $e');
      }
    }
    if (mounted) state = const {};
    _ref.read(offlineRecordTick.notifier).state++;
    return freed;
  }
}

final withdrawnCoursesProvider =
    StateNotifierProvider<WithdrawnCoursesNotifier, Set<String>>(
  WithdrawnCoursesNotifier.new,
);

/// Bumped whenever a course download writes its record.
///
/// The banner below reads the offline catalogue, which is one long-lived
/// object — so watching the store gives it nothing to rebuild on, and
/// the banner stayed lit after the student had already downloaded the
/// very course it was pointing at.
final offlineRecordTick = StateProvider<int>((_) => 0);

final coursesWithUpdatesProvider = Provider<int>((ref) {
  final stamps = ref.watch(courseStampsProvider);
  final store = ref.watch(offlineStoreProvider);
  ref.watch(offlineRecordTick);
  if (store == null) return 0;
  var n = 0;
  for (final s in stamps.values) {
    if (s.isEmpty) continue;
    final rec = store.courseRecord(s.id);
    // Only a course this phone has ALREADY downloaded can have an
    // update. Everything else is simply not downloaded yet, which is a
    // different sentence and a different button.
    if (rec == null) continue;
    if (s.differsFrom(rec)) n++;
  }
  return n;
});

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
  StreamSubscription<void>? _authWatch;
  StreamSubscription<SessionPulse>? _standingWatch;

  /// The content revision this phone last acted on.
  int _rev = 0;
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
        // Ask about the student's OWN standing first. A freeze, an
        // unfreeze, a level change or three weeks of silence all land
        // here, before any content work — which is what makes picking
        // the phone up obey Tutor Bello rather than waiting out the
        // three-minute pulse.
        await checkInNow();
        await _ref
            .read(syncStatusProvider.notifier)
            .start(level: state.profile?.currentLevel);
        await applyPolicy();
        // What Tutor Bello published while the student was away. This
        // is what makes "there's a change in this course" arrive on its
        // own rather than only when somebody opens the course.
        await _ref.read(courseStampsProvider.notifier).refresh();
      } catch (e) {
        debugPrint('[resume] refresh skipped: $e');
      } finally {
        // Even a failed refresh has to re-apply the gate: the failure
        // may be exactly the silence the gate exists to catch.
        applySilenceGate();
      }
    }());
  }

  AuthRepository get _auth => _ref.read(authRepoProvider);
  Backend get _backend => _ref.read(backendProvider);

  /// True once a session has been put on screen, so a later refresh
  /// that fails knows it must not undo it.
  bool _live = false;

  Future<void> _boot() async {
    try {
      await _bootOrThrow();
    } catch (e) {
      // The router holds on the splash while the session is `unknown`,
      // so an exception escaping boot is a student staring at a loading
      // screen with no way forward. Whatever went wrong, they get a
      // screen they can act on.
      debugPrint('[boot] failed: $e');
      if (mounted && !state.isReady) {
        state = const SessionState.signedOut();
      }
    }
  }

  Future<void> _bootOrThrow() async {
    // Starts the radio watch before anything can fail, so the first
    // error a student sees already knows whether their phone has a
    // connection at all.
    _backend.watchConnectivity();

    final store = _ref.read(localStoreProvider);

    // FIRST, before anything can poll. The website's heartbeat treats a
    // missing session header exactly like a stolen session, and the app
    // treats that answer as grounds to sign the student out. Restoring
    // this after the first poll would be too late; not restoring it at
    // all — which is what happened — signed everybody out three minutes
    // into every launch.
    _backend.restoreMobileSession(store.getString(BxKeys.mobileSession));
    _backend.restoreMode(store.getString(BxKeys.backendMode));
    _rev = store.getInt(BxKeys.contentRev);
    _watchForSessionEnd();

    // The whole point of this branch: a phone that remembers a signed-in
    // student opens ON that student, in the first frame, with no network
    // call in front of it.
    //
    // What it replaces awaited a capability probe (up to eight seconds
    // on a bad line) and then a profile read (two more requests) before
    // the router was allowed off the splash — and if either one failed,
    // which offline it always does, it published `signedOut` and the
    // student was shown a login screen for an account they had never
    // left. That is the bug: not a lost session, an impatient boot.
    final remembered = _auth.rememberedProfile();
    // The remembered student must be the one the session belongs to.
    // Signing out clears both, so they can only disagree if a crash
    // landed between the two writes — and opening one student's app on
    // another student's name is not a mistake worth risking to save a
    // comparison.
    final mine = remembered != null &&
        (_backend.userId == null || _backend.userId == remembered.id);
    if (mine && _backend.signedIn) {
      _auth.adopt(remembered);
      _publish(remembered);
      unawaited(_catchUp());
      return;
    }

    await _backend.probeCapabilities();
    unawaited(_rememberMode());
    if (!_backend.signedIn) {
      state = const SessionState.signedOut();
      return;
    }
    await refreshProfile();
  }

  /// Everything the old boot did in front of the student, moved behind
  /// them. Nothing in here may take the app away.
  Future<void> _catchUp() async {
    try {
      await _backend.probeCapabilities();
      await _rememberMode();
    } catch (e) {
      debugPrint('[boot] probe skipped: $e');
    }
    await refreshProfile();
  }

  Future<void> _rememberMode() async {
    try {
      await _ref
          .read(localStoreProvider)
          .setString(BxKeys.backendMode, _backend.modeName);
    } catch (_) {}
  }

  Future<void> refreshProfile() async {
    final Profile p;
    try {
      p = await _auth.loadProfile(force: true);
    } catch (e) {
      // A student who is already inside the app is NEVER thrown out of
      // it by a failed read. The profile is a detail; the session is
      // not, and only the session decides this.
      if (_live && state.isSignedIn) {
        debugPrint('[session] profile refresh skipped: $e');
        return;
      }
      final fallback = _auth.cachedProfile ?? _auth.rememberedProfile();
      if (fallback != null && _backend.signedIn) {
        _publish(fallback);
        return;
      }
      // Signed in but the profile could not be read — treat as signed out
      // rather than trapping the student on a blank screen. ONLY the
      // profile read may reach this: a fault anywhere else must not be
      // reported to the student as a failed login.
      state = SessionState.signedOut(
          message: e is BxError ? e.message : null);
      return;
    }

    _publish(p);
  }

  /// Puts a profile on screen and starts everything that hangs off it.
  /// Safe to call twice: the second call refreshes the state without
  /// starting a second sync or a second supersede watcher.
  void _publish(Profile p) {
    final first = !_live;
    _live = true;
    // A phone still proving itself stays on the door. A background
    // refresh landing a second later must not open it.
    if (!first && state.status == SessionStatus.deviceCheck && !p.isFrozen) {
      state = SessionState.deviceCheck(p);
      return;
    }
    state = p.isFrozen ? SessionState.frozen(p) : SessionState.active(p);
    // A paid account the server has not confirmed in three weeks stops
    // at the reconnect wall. Checked here so it applies on a cold start
    // too, not only on a resume — going offline and killing the app is
    // the obvious way round a resume-only check.
    applySilenceGate();
    if (!first) return;
    _ref.read(appLockProvider.notifier).hasSession = true;
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

      // A frozen account still SEES the app — the chairman's rule is
      // that the ice stands in the way of using it, not of opening it —
      // so it still has to obey the screenshot policy. What it does not
      // get is a sync: there is no point spending a bundle filling a
      // vault for material the account cannot open.
      if (p.isFrozen) {
        await applyPolicy();
        return;
      }
      unawaited(_ref.read(courseStampsProvider.notifier).refresh());
      await _ref
          .read(syncStatusProvider.notifier)
          .start(level: p.currentLevel);
      await applyPolicy();
    } catch (e) {
      debugPrint('[offline] first sync skipped: $e');
    }
  }

  /// The counterweight to a boot that trusts the phone.
  ///
  /// Because nothing else is allowed to end a live session any more —
  /// not a timeout, not a failed profile read — something has to end
  /// one that genuinely IS over. This is it: Supabase telling us the
  /// refresh token is dead. Without it a student whose account was
  /// revoked would sit inside a cached dashboard where every button
  /// returns an error and no button signs them out.
  void _watchForSessionEnd() {
    _authWatch?.cancel();
    try {
      _authWatch = _auth.sessionEnded.listen(
        (_) {
          // Our own signOut() clears this first, so this only fires for
          // an ending the app did not ask for.
          if (!_live) return;
          unawaited(signOut(
            reason: 'Your session has ended. Please sign in again.',
          ));
        },
        onError: (_) {},
      );
    } catch (e) {
      debugPrint('[session] auth watch unavailable: $e');
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
      // Note: the pulse below carries the same answer on the direct
      // path, where the Realtime watcher cannot tell a revocation from
      // a race. Both end in signOut; whichever arrives first wins and
      // the second is a no-op because _live is already false.
    } catch (e) {
      debugPrint('[session] device watch unavailable: $e');
    }
    _listenForStanding();
  }

  /// Acts on what the check-in says about the backend and about this
  /// student — every three minutes, on the request the app was already
  /// making.
  ///
  /// Before this, all of it waited for a cold start. Tutor Bello could
  /// freeze an account and the phone would carry on serving it until the
  /// app was next KILLED and reopened, which on a phone that is never
  /// closed is never. An activation granted by hand landed just as
  /// slowly, which is worse: a student who has paid is sitting behind a
  /// gate that has already been opened for them.
  void _listenForStanding() {
    _standingWatch?.cancel();
    _standingWatch = null;
    try {
      _standingWatch = _auth.watchStanding().listen(
        _onPulse,
        onError: (_) {},
      );
    } catch (e) {
      debugPrint('[session] standing watch unavailable: $e');
    }
  }

  void _onPulse(SessionPulse pulse) {
    if (!mounted) return;

    // ---- the session itself ----------------------------------------
    //
    // On the direct path the Realtime watcher cannot tell a revocation
    // from a race and deliberately errs towards staying signed in, so
    // this is where a force-logout or a device reset actually lands.
    // The server said so positively; unknown never reaches here.
    if (!pulse.alive && _live) {
      unawaited(signOut(
        reason: 'Your session was ended. Please sign in again.',
      ));
      return;
    }

    // ---- what Tutor Bello changed, anywhere ------------------------
    //
    // One number, moved by a database trigger on every write to every
    // content table. When it moves, the shelf and the per-course badges
    // are re-read — and NOT the courses themselves. A student's bundle
    // is not spent re-downloading a course because an announcement was
    // edited; the badge simply appears and they choose.
    if (pulse.revAvailable && pulse.rev > 0 && pulse.rev != _rev) {
      final first = _rev == 0;
      if (first) {
        // Nothing to follow up on the first pulse of a launch: this is
        // simply where the number is now.
        _rev = pulse.rev;
        unawaited(
          _ref.read(localStoreProvider).setInt(BxKeys.contentRev, _rev),
        );
      } else {
        // COMMITTED ONLY IF THE FOLLOW-UP SUCCEEDS.
        //
        // Recording the number first and then failing to re-read — one
        // flaky moment, a lost signal in a lecture hall — would mean the
        // app believes it has already dealt with that revision. The
        // change would then never be picked up again, because the next
        // pulse carries the same number and matches. A change missed
        // for good, from one dropped request.
        final target = pulse.rev;
        unawaited(() async {
          final ok = await _backendChanged();
          if (!ok || !mounted) return;
          _rev = target;
          await _ref.read(localStoreProvider).setInt(BxKeys.contentRev, target);
        }());
      }
    }

    // ---- what changed about this student ---------------------------
    final p = state.profile;
    if (p == null || !pulse.knowsStanding) return;

    // The server has just answered a question about this student, so
    // the silence clock resets. See [_staleFor] for why one exists.
    _markCheckedIn();

    final frozen = pulse.frozen;
    if (frozen != null && frozen != p.isFrozen) {
      // Both directions. Unfreezing has to land as fast as freezing, or
      // a student Tutor Bello has forgiven stays locked out until they
      // think to reinstall.
      _adopt(p.copyWith(
        isFrozen: frozen,
        frozenReason: frozen ? pulse.frozenReason : '',
      ));
      return;
    }

    final activated = pulse.activated;
    if (activated != null && activated != p.isActivated) {
      _adopt(p.copyWith(isActivated: activated));
      unawaited(
        _ref.read(localStoreProvider).setBool(BxKeys.activated, activated),
      );
      return;
    }

    final level = pulse.level;
    if (level != null && level.isNotEmpty && level != p.currentLevel) {
      // The shelf they are looking at is the wrong one.
      _adopt(p.copyWith(currentLevel: level));
      unawaited(_backendChanged());
    }
  }

  /// Freezing an account is Tutor Bello's only sanction, and it was
  /// trivially defeated: turn the data off and keep the whole paid app
  /// for ever. Nothing on the phone and nothing on the server could
  /// detect it, because the phone never had to come back.
  ///
  /// The window in [bxNeedsReconnect] is deliberately long. A student
  /// who genuinely cannot buy data for three weeks is the student this
  /// app exists for, and what the gate asks for is one moment of
  /// connection — not a download, not a sync, one call — so nobody is
  /// locked out of material they already hold for want of a bundle.
  void _markCheckedIn() {
    unawaited(_ref.read(localStoreProvider).setInt(
          BxKeys.lastCheckIn,
          DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// True when this account has been out of contact long enough that
  /// the app must hear from the server before going any further.
  ///
  /// Only ever applies to an ACTIVATED account: a student who has not
  /// paid has nothing worth gating, and locking them out would be
  /// punishing the wrong person.
  bool _tooLongSilent() {
    final p = state.profile;
    if (p == null) return false;
    final at = _ref.read(localStoreProvider).getInt(BxKeys.lastCheckIn);
    // Never recorded: this install has not seen the new build yet.
    // Start the clock rather than locking them out on the first launch
    // after an update.
    if (at == 0 && p.isActivated) {
      _markCheckedIn();
      return false;
    }
    return bxNeedsReconnect(
      activated: p.isActivated,
      lastCheckInMs: at,
      now: DateTime.now(),
    );
  }

  /// Puts the app behind the reconnect wall, or takes it back down.
  ///
  /// Called on resume and after each pulse, so a student who reconnects
  /// is let straight back in without restarting anything.
  void applySilenceGate() {
    if (!mounted) return;
    final p = state.profile;
    if (p == null) return;
    if (state.status == SessionStatus.active && _tooLongSilent()) {
      state = SessionState.mustReconnect(p);
    } else if (state.status == SessionStatus.mustReconnect &&
        !_tooLongSilent()) {
      state = SessionState.active(p);
    }
  }

  /// Asks the server, once, on behalf of the reconnect screen.
  ///
  /// Returns true when the backend answered — whatever it said. A
  /// frozen answer lands through the normal path and moves the student
  /// to the cold room, which is the right destination.
  Future<bool> checkInNow() async {
    try {
      final pulse = await _ref.read(authRepoProvider).standingNow();
      if (!pulse.knowsStanding) return false;
      _onPulse(pulse);
      if (!mounted) return true;
      applySilenceGate();
      return true;
    } catch (e) {
      debugPrint('[standing] check-in failed: $e');
      return false;
    }
  }

  /// Publishes a changed profile AND writes it where the next launch
  /// will find it.
  ///
  /// Publishing alone is not enough. Boot opens on the profile mirrored
  /// to disk, so a freeze that arrived on the heartbeat and was only
  /// ever held in memory is UNDONE by killing the app — which is what
  /// these phones do to a backgrounded app within minutes. The student
  /// would land back in a working dashboard until the next heartbeat
  /// froze them again, over and over.
  void _adopt(Profile p) {
    _publish(p);
    unawaited(() async {
      try {
        await _ref
            .read(localStoreProvider)
            .writeJson(BxKeys.cachedProfile, p.toJson(), mirror: true);
      } catch (e) {
        debugPrint('[session] could not keep the change: $e');
      }
    }());
  }

  /// Re-reads what is cheap and leaves alone what is not.
  ///
  /// The shelf, the switches and the per-course badges. NOT the courses
  /// themselves: a student's data bundle is not spent re-downloading a
  /// course because an announcement was edited. The badge appears and
  /// they choose.
  ///
  /// Returns false when it could not finish, so the caller knows not to
  /// record the revision as handled.
  Future<bool> _backendChanged() async {
    try {
      await _ref
          .read(contentRepoProvider)
          .loadContent(level: state.profile?.currentLevel ?? '100', force: true);
      _ref.invalidate(contentProvider);

      // The other surfaces that hang off backend content, and used to
      // sit stale until the student happened to leave the screen and
      // come back:
      //
      //   the bell    a new announcement neither rang it nor, once
      //               withdrawn, stopped it ringing
      //   the tests   a test published, opened or closed never appeared
      //               on a course hub the student was already standing
      //               on
      //   the numbers the dashboard's own counts
      //
      // All three are autoDispose futures, so invalidating costs
      // nothing for the ones nobody is looking at.
      _ref.invalidate(announcementsProvider);
      _ref.invalidate(dashboardProvider);
      for (final c in _ref.read(contentRepoProvider).courses) {
        _ref.invalidate(testsForCourseProvider(c.id));
      }

      await applyPolicy();
      await _ref.read(courseStampsProvider.notifier).refresh(force: true);
      return true;
    } catch (e) {
      debugPrint('[session] could not follow the change: $e');
      return false;
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
      // So a graded attempt cannot be started against a closed
      // platform. Offline practice is untouched.
      _ref.read(assessmentRepoProvider).policyForStart = policy;
      await ScreenCapture.apply(policy);
    } catch (e) {
      debugPrint('[policy] not applied: $e');
    }
  }

  /// Re-reads the backend's switches without waiting for a resume.
  /// Used by the journey test to prove a policy change reaches the
  /// phone; the app itself calls [applyPolicy] on resume.
  @visibleForTesting
  Future<void> applyPolicyForTest() async {
    await _ref
        .read(contentRepoProvider)
        .loadContent(level: state.profile?.currentLevel ?? '100', force: true);
    await applyPolicy();
  }

  /// The one place both "sign in" and "create account" land.
  ///
  /// The phone's own lock is shown here, once, while the student is
  /// still paying attention — which is what "force passkey after
  /// creating an account or signing in" means in practice. It cannot be
  /// forced on a phone that has no screen lock at all; there it does
  /// nothing and Profile says why.
  Future<void> onSignedIn() async {
    await refreshProfile();
    if (!state.isSignedIn) return;
    unawaited(_ref.read(appLockProvider.notifier).enrolNow());
  }

  Future<void> signOut({String? reason}) async {
    _live = false;
    _sessionWatch?.cancel();
    _sessionWatch = null;
    _standingWatch?.cancel();
    _standingWatch = null;
    _rev = 0;
    _ref.read(appLockProvider.notifier).hasSession = false;
    // The shelf, the levels and the screenshot policy of the student who
    // just left. All of it lived in a long-lived repository and would
    // have been shown to whoever signed in next on this phone.
    _ref.read(contentRepoProvider).forget();
    _ref.invalidate(contentProvider);
    // The silence clock belongs to the student who just left. Carrying
    // it over would put the next student on this phone behind the
    // reconnect wall for something they had nothing to do with.
    unawaited(_ref.read(localStoreProvider).setInt(BxKeys.lastCheckIn, 0));
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
    _standingWatch?.cancel();
    _authWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// The whole of the reconnect rule, with nothing around it.
///
/// Kept as a plain function so it can be pinned down exactly: this
/// decides whether a student is shut out of material they have already
/// paid for and already downloaded, and getting it wrong in either
/// direction is expensive. Too loose and a frozen account keeps the app
/// for ever by staying offline; too tight and a student with no data
/// bundle loses what they paid for.
bool bxNeedsReconnect({
  required bool activated,
  required int lastCheckInMs,
  required DateTime now,
  Duration allowed = const Duration(days: 21),
}) {
  // Nothing to gate. A student who has not paid has nothing worth
  // withholding, and locking them out punishes the wrong person.
  if (!activated) return false;
  // No clock yet — an install that predates this rule. The caller
  // starts the clock; it must never be read as three weeks of silence.
  if (lastCheckInMs <= 0) return false;
  final last = DateTime.fromMillisecondsSinceEpoch(lastCheckInMs);
  // A stamp from the future is a phone with a wrong clock, not a
  // student in good standing and not one in bad. Let them through.
  if (last.isAfter(now)) return false;
  return now.difference(last) > allowed;
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

  /// Signed in and paid, but the backend has not confirmed this
  /// account's standing in three weeks. One connection clears it.
  mustReconnect,
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
  const SessionState.mustReconnect(Profile p)
      : this._(SessionStatus.mustReconnect, p, null);

  bool get isSignedIn =>
      status == SessionStatus.active ||
      status == SessionStatus.frozen ||
      status == SessionStatus.mustReconnect ||
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
/// Bumped to make the next content read go to the SERVER.
///
/// Invalidating [contentProvider] on its own does nothing, and that is
/// worth being precise about because it made every pull-to-refresh in
/// the app a decoration. loadContent() begins with
///
///     if (!force && _courses.isNotEmpty) return;
///
/// and the repository is long-lived, so its courses are already
/// populated. Invalidating re-ran the future, which returned on that
/// first line without touching the network. A student pulling down to
/// fetch the note Tutor Bello had just added got a spinner and their
/// own cache, for ever.
final contentRefreshTick = StateProvider<int>((_) => 0);

final contentProvider = FutureProvider.autoDispose<ContentRepository>((ref) async {
  final repo = ref.watch(contentRepoProvider);
  final level = ref.watch(profileProvider).currentLevel;
  final tick = ref.watch(contentRefreshTick);
  await repo.loadContent(level: level, force: tick > 0);
  ref.keepAlive();
  return repo;
});

/// What every pull-to-refresh should call.
///
/// Asks the server, then rebuilds whatever is watching. Falls back to
/// the cache inside loadContent when there is no signal, so pulling
/// down with the data off is a no-op rather than an error.
Future<void> refreshContent(WidgetRef ref) async {
  ref.read(contentRefreshTick.notifier).state++;
  ref.invalidate(contentProvider);
  await ref.read(contentProvider.future);
  // The badges hang off the same content, so they are re-read with it.
  unawaited(ref.read(courseStampsProvider.notifier).refresh(force: true));
}

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

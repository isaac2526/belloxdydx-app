import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_bridge.dart';
import '../data/backend.dart';
import '../data/local_store.dart';
import '../data/models.dart';
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
  (ref) => AssessmentRepository(ref.watch(backendProvider)),
);

final engageRepoProvider = Provider<EngageRepository>(
  (ref) =>
      EngageRepository(ref.watch(backendProvider), ref.watch(localStoreProvider)),
);

// ------------------------------------------------------------
// Session
// ------------------------------------------------------------

/// The signed-in student's profile, or null when signed out. This is the
/// single source of truth the router reads to decide what to show.
class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this._ref) : super(const SessionState.unknown()) {
    _boot();
  }

  final Ref _ref;
  StreamSubscription<bool>? _sessionWatch;

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
    super.dispose();
  }
}

enum SessionStatus { unknown, signedOut, active, frozen }

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
  const SessionState.frozen(Profile p) : this._(SessionStatus.frozen, p, null);

  bool get isSignedIn =>
      status == SessionStatus.active || status == SessionStatus.frozen;
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

class VaultNotifier extends StateNotifier<List<VaultEntry>> {
  VaultNotifier(this._store) : super(_store.vaultItems()) {
    _reconcile();
  }

  final LocalStore _store;

  Future<void> _reconcile() async {
    await _store.reconcileVault();
    if (mounted) state = _store.vaultItems();
  }

  void refresh() => state = _store.vaultItems();

  bool isSaved(String materialId) =>
      state.any((v) => v.materialId == materialId);

  Future<void> remove(String materialId) async {
    await _store.removeFromVault(materialId);
    refresh();
  }
}

final vaultProvider =
    StateNotifierProvider<VaultNotifier, List<VaultEntry>>(
  (ref) => VaultNotifier(ref.watch(localStoreProvider)),
);

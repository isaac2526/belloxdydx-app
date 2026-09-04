import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/ai_screen.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/auth/activate_screen.dart';
import '../features/auth/forgot_screen.dart';
import '../features/auth/frozen_screen.dart';
import '../features/auth/reconnect_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/security/device_check_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/reset_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/cbt/cbt_screen.dart';
import '../features/cgpa/cgpa_screen.dart';
import '../features/courses/course_hub_screen.dart';
import '../features/courses/courses_screen.dart';
import '../features/courses/section_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/league/league_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/materials/note_screen.dart';
import '../features/materials/viewer_screen.dart';
import '../features/materials/watch_screen.dart';
import '../features/millionaire/millionaire_screen.dart';
import '../features/mistakes/mistakes_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/results/result_screen.dart';
import '../features/revision/revision_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import '../features/vault/vault_screen.dart';
import '../data/local_store.dart';
import 'providers.dart';

/// ============================================================
/// ROUTING
///
/// A declarative router whose redirect reads one thing — the session
/// state — so there is never a screen a signed-out student can reach
/// and never a blank frame between states.
///
/// Deep links land here too: belloxdydx.org/t/<code> opens a live class
/// test straight in the app.
/// ============================================================

abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const forgot = '/forgot-password';
  static const reset = '/reset-password';
  static const activate = '/activate';
  static const frozen = '/frozen';
  static const reconnect = '/reconnect';
  static const deviceCheck = '/new-device';

  static const home = '/';
  static const courses = '/courses';
  static const revision = '/revision';
  static const ai = '/ai';
  static const ranks = '/ranks';
  static const you = '/you';

  static const league = '/league';
  static const millionaire = '/millionaire';
  static const mistakes = '/mistakes';
  static const announcements = '/announcements';
  static const vault = '/vault';
  static const cgpa = '/cgpa';

  static String course(String code) => '/courses/$code';
  static String section(String code, String section) =>
      '/courses/$code/$section';
  static String note(String id) => '/notes/$id';
  static String view(String id) => '/view/$id';
  static String watch(String id) => '/watch/$id';
  static String practice(String id) => '/practice/$id';
  static String cbt(String id) => '/cbt/$id';
  static String result(String id) => '/results/$id';
  static String liveTest(String code) => '/t/$code';
}

/// Rebuilds the router's redirect whenever the session changes.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(this._ref) {
    _ref.listen<SessionState>(sessionProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

/// Screens worth coming back to after the phone killed the app.
///
/// A tab root is not one of them: a student who was on the dashboard is
/// not in the middle of anything, and reopening the app on a screen
/// they merely passed through would be surprising rather than helpful.
const bxResumableRoutes = <String>[
  '/practice/',
  '/cbt/',
  '/notes/',
  '/view/',
  '/watch/',
  '/results/',
];

/// After this long it is a new session, not an interruption. Coming
/// back the next morning should open the app, not last night's
/// question.
const bxRouteMemoryLifetime = Duration(hours: 12);

bool bxIsResumableRoute(String location) =>
    bxResumableRoutes.any(location.startsWith);

/// ============================================================
/// COMING BACK TO WHERE YOU WERE
///
/// "if I'm offline or online and I left a practice questions I suppose
///  to meet it back, if just for a second for 16 GB RAM phone the app
///  has already refreshed"
///
/// A phone reclaims memory by killing whatever is in the background,
/// and the phones this app runs on do it within minutes. Flutter's own
/// state does not survive that — the process is gone — so "meet it
/// back" has to be rebuilt from something on disk.
///
/// Three pieces do it together, and this is the third:
///
///   1. The ANSWERS are written to the offline store as they are
///      committed, so the round itself survives (repositories.dart).
///   2. The POSITION is recorded, so it comes back to the question the
///      student was looking at rather than the next unanswered one
///      (models.dart, startIndexFor).
///   3. The SCREEN is remembered here, so the app reopens on it.
///
/// Deliberately narrow. Only screens a student can be interrupted in
/// the middle of are remembered — a round, a note, a document, a
/// result. Reopening on a tab they merely visited would be surprising,
/// and reopening on a login screen would be a bug.
class _RouteMemory {
  _RouteMemory(this._ref, this._router) {
    // Read FIRST, before anything can overwrite it.
    //
    // The router settles on the splash and then on the dashboard within
    // the first frames, and _remember() clears the memory the moment it
    // sees a screen that is not resumable. So the stored value has to be
    // taken now, into a local, or the app would erase the thing it is
    // about to restore.
    _target = _readTarget();
    _router.routerDelegate.addListener(_remember);
    _ref.listen<SessionState>(
      sessionProvider,
      (_, next) {
        if (next.status == SessionStatus.active) _restore();
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final GoRouter _router;
  String? _target;
  bool _done = false;

  void dispose() => _router.routerDelegate.removeListener(_remember);

  void _remember() {
    try {
      final loc = _router.state.matchedLocation;
      final uri = _router.state.uri.toString();
      final store = _ref.read(localStoreProvider);
      if (bxIsResumableRoute(loc)) {
        store.setString(BxKeys.lastRoute, uri);
        store.setInt(
          BxKeys.lastRouteAt,
          DateTime.now().millisecondsSinceEpoch,
        );
      } else if (store.getString(BxKeys.lastRoute) != null) {
        // Leaving the round is the student closing it. Forgetting here
        // is what stops the app reopening on a screen they walked away
        // from on purpose.
        store.remove(BxKeys.lastRoute);
      }
    } catch (_) {
      // Remembering is a convenience. It may never be the reason a
      // navigation fails.
    }
  }

  String? _readTarget() {
    try {
      final store = _ref.read(localStoreProvider);
      final target = store.getString(BxKeys.lastRoute);
      if (target == null || target.isEmpty) return null;

      final at = store.getInt(BxKeys.lastRouteAt);
      if (at <= 0 ||
          DateTime.now().millisecondsSinceEpoch - at >
              bxRouteMemoryLifetime.inMilliseconds) {
        store.remove(BxKeys.lastRoute);
        return null;
      }
      if (!bxIsResumableRoute(Uri.tryParse(target)?.path ?? '')) return null;
      return target;
    } catch (_) {
      return null;
    }
  }

  void _restore() {
    if (_done) return;
    final target = _target;
    if (target == null) {
      _done = true;
      return;
    }
    _push(target, 0);
  }

  /// Waits for the router to settle on the dashboard, then pushes on
  /// top of it — rather than instead of it, so Back goes where a
  /// student expects instead of out of the app.
  ///
  /// Retried rather than fired once: the session can go active in the
  /// same frame the app starts now, and at that moment the router is
  /// still on the splash. A single post-frame callback would look, find
  /// the splash, and give up on a round the student was in the middle
  /// of.
  void _push(String target, int attempt) {
    if (_done || attempt > 20) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_done) return;
      String loc;
      try {
        loc = _router.state.matchedLocation;
      } catch (_) {
        loc = '';
      }
      if (loc == Routes.home) {
        _done = true;
        try {
          _router.push(target);
        } catch (_) {}
        return;
      }
      // Signed out, frozen, or a device check in the way: nothing to
      // come back to.
      if (loc == Routes.welcome ||
          loc == Routes.frozen ||
          loc == Routes.reconnect ||
          loc == Routes.deviceCheck) {
        _done = true;
        return;
      }
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _push(target, attempt + 1),
      );
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  late final GoRouter router;
  _RouteMemory? memory;
  ref.onDispose(() => memory?.dispose());

  router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      const publicRoutes = {
        Routes.splash,
        Routes.onboarding,
        Routes.welcome,
        Routes.login,
        Routes.register,
        Routes.forgot,
        Routes.reset,
        Routes.cgpa,
      };
      final isPublic = publicRoutes.contains(loc);

      // Still deciding — hold on the splash.
      if (!session.isReady) return loc == Routes.splash ? null : Routes.splash;

      if (!session.isSignedIn) {
        // First run on this install goes through onboarding. The flag is
        // read synchronously from local storage, so a returning student
        // is never shown a card that is then snatched away.
        final firstRun =
            !ref.read(localStoreProvider).getBool(BxKeys.onboardingSeen);

        // The splash has done its job the moment the session resolves.
        // It is a "public" route so an unauthenticated visitor may sit
        // on it while we decide — but once we have decided, staying
        // there strands the student on a loading screen forever.
        if (loc == Routes.splash) {
          return firstRun ? Routes.onboarding : Routes.welcome;
        }
        if (loc == Routes.onboarding) return firstRun ? null : Routes.welcome;
        return isPublic ? null : Routes.welcome;
      }

      // A phone this account has never been opened on proves itself
      // before anything else is reachable.
      if (session.status == SessionStatus.deviceCheck) {
        return loc == Routes.deviceCheck ? null : Routes.deviceCheck;
      }

      // A frozen account sees only the cold room.
      if (session.status == SessionStatus.frozen) {
        return loc == Routes.frozen ? null : Routes.frozen;
      }

      // A paid account the server has not confirmed in three weeks asks
      // for one moment of connection. Below the cold room deliberately:
      // a student who IS frozen belongs in the cold room, where the
      // reason Tutor Bello wrote is waiting for them.
      if (session.status == SessionStatus.mustReconnect) {
        return loc == Routes.reconnect ? null : Routes.reconnect;
      }

      // Signed in: the auth doors are closed behind them.
      if (loc == Routes.splash ||
          loc == Routes.onboarding ||
          loc == Routes.welcome ||
          loc == Routes.login ||
          loc == Routes.register ||
          loc == Routes.deviceCheck ||
          loc == Routes.reconnect ||
          loc == Routes.frozen) {
        return Routes.home;
      }

      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: Routes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: Routes.onboarding,
          builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: Routes.forgot, builder: (_, __) => const ForgotScreen()),
      GoRoute(path: Routes.reset, builder: (_, __) => const ResetScreen()),
      GoRoute(path: Routes.frozen, builder: (_, __) => const FrozenScreen()),
      GoRoute(
          path: Routes.reconnect,
          builder: (_, __) => const ReconnectScreen()),
      GoRoute(
          path: Routes.deviceCheck,
          builder: (_, __) => const DeviceCheckScreen()),
      GoRoute(path: Routes.activate, builder: (_, __) => const ActivateScreen()),
      GoRoute(path: Routes.cgpa, builder: (_, __) => const CgpaScreen()),

      // ---- the tabbed shell ----
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, __) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.courses,
              builder: (_, __) => const CoursesScreen(),
              routes: [
                GoRoute(
                  path: ':code',
                  builder: (_, s) =>
                      CourseHubScreen(code: s.pathParameters['code']!),
                  routes: [
                    GoRoute(
                      path: ':section',
                      builder: (_, s) => SectionScreen(
                        code: s.pathParameters['code']!,
                        section: s.pathParameters['section']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.revision,
              builder: (_, __) => const RevisionScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.ai, builder: (_, __) => const AiScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.ranks,
              builder: (_, __) => const LeaderboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.you, builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),

      // ---- full-screen routes outside the shell ----
      GoRoute(
        path: '/notes/:id',
        builder: (_, s) => NoteScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/view/:id',
        builder: (_, s) => ViewerScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/watch/:id',
        builder: (_, s) => WatchScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/practice/:id',
        builder: (_, s) => PracticeScreen(attemptId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cbt/:id',
        builder: (_, s) => CbtScreen(attemptId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/results/:id',
        builder: (_, s) => ResultScreen(attemptId: s.pathParameters['id']!),
      ),
      GoRoute(path: Routes.mistakes, builder: (_, __) => const MistakesScreen()),
      GoRoute(path: Routes.league, builder: (_, __) => const LeagueScreen()),
      GoRoute(
          path: Routes.millionaire,
          builder: (_, __) => const MillionaireScreen()),
      GoRoute(
        path: Routes.announcements,
        builder: (_, __) => const AnnouncementsScreen(),
      ),
      GoRoute(path: Routes.vault, builder: (_, __) => const VaultScreen()),

      // A live class test link shared in WhatsApp opens here.
      GoRoute(
        path: '/t/:code',
        builder: (_, s) => LiveTestEntry(code: s.pathParameters['code']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('That page went missing.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Attached after the router exists, because it listens to it.
  memory = _RouteMemory(ref, router);
  return router;
});

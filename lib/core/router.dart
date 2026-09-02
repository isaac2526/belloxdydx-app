import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/ai_screen.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/auth/activate_screen.dart';
import '../features/auth/forgot_screen.dart';
import '../features/auth/frozen_screen.dart';
import '../features/auth/login_screen.dart';
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
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const forgot = '/forgot-password';
  static const reset = '/reset-password';
  static const activate = '/activate';
  static const frozen = '/frozen';

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

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      const publicRoutes = {
        Routes.splash,
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
        // The splash has done its job the moment the session resolves.
        // It is a "public" route so an unauthenticated visitor may sit
        // on it while we decide — but once we have decided, staying
        // there strands the student on a loading screen forever.
        if (loc == Routes.splash) return Routes.welcome;
        return isPublic ? null : Routes.welcome;
      }

      // A frozen account sees only the cold room.
      if (session.status == SessionStatus.frozen) {
        return loc == Routes.frozen ? null : Routes.frozen;
      }

      // Signed in: the auth doors are closed behind them.
      if (loc == Routes.splash ||
          loc == Routes.welcome ||
          loc == Routes.login ||
          loc == Routes.register ||
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
      GoRoute(path: Routes.forgot, builder: (_, __) => const ForgotScreen()),
      GoRoute(path: Routes.reset, builder: (_, __) => const ResetScreen()),
      GoRoute(path: Routes.frozen, builder: (_, __) => const FrozenScreen()),
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
});

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/local_store.dart';

/// ============================================================
/// BELLOXDYDX
///
/// A real Flutter application. There is no WebView here, no PWA
/// wrapper and no embedded website — every screen is built natively
/// against the same backend the website uses.
///
/// The previous release shipped a WebView pointed at belloxdydx.org
/// while 24 finished native screens sat unreachable in this repo. That
/// shell is gone; the native app is the app.
/// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await LocalStore.init();

  try {
    await Supabase.initialize(
      url: BxConfig.supabaseUrl,
      anonKey: BxConfig.supabaseAnonKey, // ignore: deprecated_member_use
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (e) {
    debugPrint('[boot] Supabase init failed: $e');
  }

  runApp(const ProviderScope(child: BelloxdydxApp()));
}

class BelloxdydxApp extends ConsumerWidget {
  const BelloxdydxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Belloxdydx',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: bxLightTheme,
      darkTheme: bxDarkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        // Text never scales past a readable ceiling — an exam timer and
        // a question navigator must not be pushed off screen by a
        // system font setting.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.35,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

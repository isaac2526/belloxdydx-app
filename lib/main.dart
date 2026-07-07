import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/splash.dart';
import 'screens/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await Api.init();
  final theme = ThemeController();
  await theme.load();
  runApp(
    ChangeNotifierProvider.value(value: theme, child: const BelloxdydxApp()),
  );
}

class BelloxdydxApp extends StatelessWidget {
  const BelloxdydxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: "Belloxdydx",
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: theme.mode,
      routes: {
        "/login": (_) => const LoginScreen(),
      },
      home: const SplashScreen(),
    );
  }
}

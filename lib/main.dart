import 'package:flutter/material.dart';
import 'clone_shell.dart';

// Belloxdydx v4 — the exact-clone era. The website is the app; this
// shell adds the native powers (secure screen, persistent session,
// branded offline, deep links) and nothing else stands between the
// student and the real platform.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BelloxdydxApp());
}

class BelloxdydxApp extends StatelessWidget {
  const BelloxdydxApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: "Belloxdydx",
      debugShowCheckedModeBanner: false,
      home: CloneShell(),
    );
  }
}

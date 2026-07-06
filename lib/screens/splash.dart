import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../config.dart';
import 'login.dart';
import 'shell.dart';

// The game-style loader: a real 0 to 100 tied to real work, so
// students always know the app is alive and how far along it is.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double shown = 0;
  double target = 0;
  Timer? _smooth;

  @override
  void initState() {
    super.initState();
    _smooth = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      setState(() {
        if (shown < target) shown = (shown + 2).clamp(0, target);
      });
    });
    _boot();
  }

  Future<void> _boot() async {
    setState(() => target = 25);
    await Api.installPingOnce();

    setState(() => target = 55);
    if (!Api.signedIn) {
      setState(() => target = 100);
      await Future.delayed(const Duration(milliseconds: 700));
      _go(const LoginScreen());
      return;
    }

    setState(() => target = 80);
    try {
      await Api.fetchContent();
      unawaited(Api.streakTouch());
      setState(() => target = 100);
      await Future.delayed(const Duration(milliseconds: 500));
      _go(const ShellScreen());
    } catch (_) {
      setState(() => target = 100);
      await Future.delayed(const Duration(milliseconds: 500));
      _go(const ShellScreen()); // shell shows its own retry if content is null
    }
  }

  void _go(Widget w) {
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => w));
  }

  @override
  void dispose() {
    _smooth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset("assets/logo.png", width: 110, height: 110),
            ),
            const SizedBox(height: 18),
            const Text("Belloxdydx",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text("Smash your 100 level exams",
                style: TextStyle(color: Colors.white54)),
            const Spacer(),
            Text("${shown.toInt()}%",
                style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF5B301))),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: shown / 100,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFFF5B301),
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.only(bottom: 18, left: 24, right: 24),
              child: Text(brandFooter,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

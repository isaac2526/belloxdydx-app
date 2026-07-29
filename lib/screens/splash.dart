import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api.dart';
import '../config.dart';
import '../security.dart';
import '../biometric.dart';
import 'login.dart';
import 'landing.dart';
import 'shell.dart';

// The game-style 0 to 100 loader tied to real startup work.
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
    Security.lockDown();
    _smooth = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (!mounted) return;
      setState(() {
        if (shown < target) shown = (shown + 2).clamp(0, target);
      });
    });
    _boot();
  }

  Future<void> _boot() async {
    setState(() => target = 20);
    await Api.installPingOnce();

    if (!Api.signedIn) {
      setState(() => target = 100);
      await Future.delayed(const Duration(milliseconds: 650));
      _go(const LandingScreen());
      return;
    }

    // Biometric gate on relaunch, if the student turned it on.
    setState(() => target = 45);
    if (await Biometric.isEnabled()) {
      final ok = await Biometric.prompt("Unlock Belloxdydx");
      if (!ok) {
        setState(() => target = 100);
        await Future.delayed(const Duration(milliseconds: 400));
        _go(const LandingScreen());
        return;
      }
    }

    setState(() => target = 75);
    // Load whatever we saved last so the app can open with NO network.
    await Api.loadCachedContent();
    try {
      await Api.fetchContent(); // refreshes + re-caches; falls back internally
      unawaited(Api.streakTouch());
    } catch (_) {
      // offline with no cache is handled inside Home with a retry.
    }
    setState(() => target = 100);
    await Future.delayed(const Duration(milliseconds: 400));
    _go(const ShellScreen());
  }

  void _go(Widget w) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => w));
  }

  @override
  void dispose() {
    _smooth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFF5B301);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset("assets/logo.png", width: 116, height: 116),
            ),
            const SizedBox(height: 18),
            Text("Belloxdydx",
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text("Smash your 100 level exams",
                style: TextStyle(color: Theme.of(context).hintColor)),
            const Spacer(),
            Text("${shown.toInt()}%",
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 44, fontWeight: FontWeight.w800, color: gold)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: shown / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey.withOpacity(0.2),
                  color: gold,
                ),
              ),
            ),
            const SizedBox(height: 44),
            Padding(
              padding: const EdgeInsets.only(bottom: 18, left: 24, right: 24),
              child: Text(brandFooter,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

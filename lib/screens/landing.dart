import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import 'login.dart';
import 'register.dart';
import 'cgpa.dart';

// The front door. Light by default, gradient hero, the promise of the
// platform in one screen — then Log in or Create account.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8E7), Color(0xFFEAF3FF), Color(0xFFF3ECFF)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                Image.asset("assets/logo.png", height: 34,
                    errorBuilder: (_, __, ___) => const SizedBox()),
                const SizedBox(width: 8),
                const Text("Belloxdydx",
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const Spacer(),
                IconButton(
                  tooltip: "CGPA Calculator",
                  icon: const Icon(Icons.calculate_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CgpaScreen())),
                ),
                IconButton(
                  tooltip: theme.isDark ? "Light mode" : "Dark mode",
                  icon: Icon(theme.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  onPressed: () => theme.toggle(),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                children: [
                  const SizedBox(height: 22),
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(colors: [
                      Color(0xFFF5B301),
                      Color(0xFFFF7A00),
                      Color(0xFF3EA0EE)
                    ]).createShader(r),
                    child: const Text(
                      "Your 100 Level,\nconquered.",
                      style: TextStyle(
                          fontSize: 40,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Past questions, CBT practice, lecture materials, Bello AI, the Millionaire hot seat and the weekly League — the complete University of Ibadan first-year arsenal, in your pocket.",
                    style: TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _Chip("📚 Materials vault", Color(0xFF3EA0EE)),
                      _Chip("🧠 CBT & practice", Color(0xFF3ECF8E)),
                      _Chip("🤖 Bello AI", Color(0xFF8B5CF6)),
                      _Chip("🎰 Millionaire", Color(0xFFF5B301)),
                      _Chip("⚔️ Weekly League", Color(0xFFE5484D)),
                      _Chip("📊 Your charts", Color(0xFF1D74C4)),
                    ],
                  ),
                  const SizedBox(height: 30),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF5B301),
                      foregroundColor: const Color(0xFF0B1220),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text("Create your account"),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => Navigator.of(context)
                        .pushNamed("/login"),
                    child: const Text("I already have an account — Log in"),
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      "Designed with excellence for academic distinction\n— Isaac Arinola Tech",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

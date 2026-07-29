import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import 'register.dart';
import 'cgpa.dart';

// ============================================================
// THE FRONT DOOR — rebuilt for real.
// Theme-aware (no invisible text, ever), generous spacing, layered
// gradient orbs and glassy feature tiles instead of bare emoji, a
// bold multi-colour hero. Works in light AND dark.
// ============================================================
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final dark = theme.isDark;

    // Every colour derives from the mode, so text is always legible.
    final bg1 = dark ? const Color(0xFF070B1E) : const Color(0xFFF6F9FF);
    final bg2 = dark ? const Color(0xFF0E1533) : const Color(0xFFFFFFFF);
    final ink = dark ? Colors.white : const Color(0xFF0B1220);
    final sub = dark ? const Color(0xFF9FB0CC) : const Color(0xFF54617A);
    final tileBg = dark ? Colors.white.withOpacity(0.05) : Colors.white;
    final tileBorder =
        dark ? Colors.white.withOpacity(0.10) : const Color(0x14000000);

    return Scaffold(
      body: Stack(children: [
        // base wash
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bg1, bg2],
            ),
          ),
        ),
        // floating colour orbs (soft, blurred, the "design")
        Positioned(top: -80, right: -60, child: _orb(220, const Color(0xFFF5B301), dark ? 0.22 : 0.30)),
        Positioned(top: 120, left: -70, child: _orb(200, const Color(0xFF3EA0EE), dark ? 0.20 : 0.26)),
        Positioned(bottom: -60, right: -40, child: _orb(240, const Color(0xFF8B5CF6), dark ? 0.18 : 0.22)),
        SafeArea(
          child: Column(children: [
            // top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    gradient: const LinearGradient(
                        colors: [Color(0xFFF5B301), Color(0xFFFF7A00)]),
                  ),
                  alignment: Alignment.center,
                  child: const Text("B",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Text("Belloxdydx",
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: ink)),
                const Spacer(),
                IconButton(
                  tooltip: "CGPA Calculator",
                  color: ink,
                  icon: const Icon(Icons.calculate_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CgpaScreen())),
                ),
                IconButton(
                  tooltip: dark ? "Light mode" : "Dark mode",
                  color: ink,
                  icon: Icon(dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  onPressed: () => theme.toggle(),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  const SizedBox(height: 26),
                  // eyebrow
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5B301).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text("UNIVERSITY OF IBADAN · 100 LEVEL",
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB8860B))),
                  ),
                  const SizedBox(height: 18),
                  // hero — gradient words that read on any background
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 42,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          color: ink),
                      children: [
                        const TextSpan(text: "Your first year,\n"),
                        WidgetSpan(
                          child: ShaderMask(
                            shaderCallback: (r) => const LinearGradient(colors: [
                              Color(0xFFF5B301),
                              Color(0xFFFF7A00),
                              Color(0xFF3EA0EE),
                            ]).createShader(r),
                            child: const Text("conquered.",
                                style: TextStyle(
                                    fontSize: 42,
                                    height: 1.08,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Every past question, CBT practice, lecture material, and Bello AI — plus the Millionaire hot seat and a weekly League that turns your class into a leaderboard. The complete University of Ibadan first-year arsenal, in one app.",
                    style: TextStyle(fontSize: 15, height: 1.55, color: sub),
                  ),
                  const SizedBox(height: 26),
                  // feature tiles — glassy, coloured, not bare emoji
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                    children: [
                      _tile(tileBg, tileBorder, ink, sub, Icons.menu_book_rounded,
                          const Color(0xFF3EA0EE), "Materials", "Notes, PDFs & slides"),
                      _tile(tileBg, tileBorder, ink, sub, Icons.psychology_rounded,
                          const Color(0xFF3ECF8E), "CBT & Practice", "Real exam engine"),
                      _tile(tileBg, tileBorder, ink, sub, Icons.auto_awesome_rounded,
                          const Color(0xFF8B5CF6), "Bello AI", "Your study partner"),
                      _tile(tileBg, tileBorder, ink, sub, Icons.emoji_events_rounded,
                          const Color(0xFFF5B301), "Millionaire", "Win bragging money"),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // primary actions
                  _gradientButton(
                    "Create your account",
                    () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RegisterScreen())),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        side: BorderSide(
                            color: dark
                                ? Colors.white24
                                : const Color(0x22000000)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pushNamed("/login"),
                      child: const Text("I already have an account — Log in",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      "Designed with excellence for academic distinction\n— Isaac Arinola Tech",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: sub, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _orb(double size, Color color, double opacity) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withOpacity(opacity),
              color.withOpacity(0),
            ]),
          ),
        ),
      );

  Widget _tile(Color bg, Color border, Color ink, Color sub, IconData icon,
      Color accent, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
              color: accent.withOpacity(0.10),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: ink)),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 11, color: sub)),
          ]),
        ],
      ),
    );
  }

  Widget _gradientButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
              colors: [Color(0xFFF5B301), Color(0xFFFF7A00)]),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFF5B301).withOpacity(0.4),
                blurRadius: 22,
                offset: const Offset(0, 8)),
          ],
        ),
        child: const Text("Create your account",
            style: TextStyle(
                color: Color(0xFF0B1220),
                fontSize: 16,
                fontWeight: FontWeight.w900)),
      ),
    );
  }
}

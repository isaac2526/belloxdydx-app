import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Brand palette shared with the website: deep navy, glass surfaces, gold.
const gold = Color(0xFFF5B301);
const goldDeep = Color(0xFFD99E00);

const navyBg = Color(0xFF0B1220);
const navySurface = Color(0xFF141E33);
const navyBorder = Color(0x1AFFFFFF);

const lightBg = Color(0xFFEDF2FC);
const lightSurface = Color(0xFFFFFFFF);
const lightBorder = Color(0x14000000);

// A tiny theme controller the whole app listens to, so dark/light flips
// instantly and remembers the choice.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString("bx_theme");
    if (v == "light") {
      _mode = ThemeMode.light;
    } else if (v == "dark") {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system; // follow the phone's own setting
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    // If following the system, first tap flips to the opposite of what
    // is currently shown; after that it toggles explicitly.
    final showingDark = isDarkIn(_lastBrightness);
    _mode = showingDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString("bx_theme", _mode == ThemeMode.light ? "light" : "dark");
  }

  Future<void> useSystem() async {
    _mode = ThemeMode.system;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove("bx_theme");
  }

  Brightness _lastBrightness = Brightness.dark;
  void noteBrightness(Brightness b) => _lastBrightness = b;
  bool isDarkIn(Brightness sys) =>
      _mode == ThemeMode.dark ||
      (_mode == ThemeMode.system && sys == Brightness.dark);

  bool get isDark => _mode == ThemeMode.dark ||
      (_mode == ThemeMode.system && _lastBrightness == Brightness.dark);
  bool get isSystem => _mode == ThemeMode.system;
}

ThemeData _base(Brightness b, Color bg, Color surface, Color border) {
  final scheme = ColorScheme.fromSeed(
    seedColor: gold,
    brightness: b,
    primary: gold,
    surface: surface,
  );
  final onBg = b == Brightness.dark ? Colors.white : const Color(0xFF0B1220);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bg,
    colorScheme: scheme,
    textTheme: GoogleFonts.interTextTheme(
      b == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        color: onBg,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: onBg),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: const Color(0xFF0B1220),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: gold, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: gold.withOpacity(0.18),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

final darkTheme = _base(Brightness.dark, navyBg, navySurface, navyBorder);
final lightTheme = _base(Brightness.light, lightBg, lightSurface, lightBorder);

// A soft glass panel used across the app to echo the website's look.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? tint;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? (dark ? Colors.white.withOpacity(0.05) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: child,
    );
  }
}

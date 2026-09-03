import 'package:flutter/material.dart';

/// ============================================================
/// BELLOXDYDX DESIGN TOKENS
///
/// White and gold. Sharp, flat, premium. The dashboard carries NO
/// gradients — colour arrives through a tinted fill, a hairline
/// border or a single figure, never a wash.
///
/// Every colour in the app comes from here. No literal hex values
/// anywhere else in the codebase.
/// ============================================================

@immutable
class BxColors extends ThemeExtension<BxColors> {
  // ---- grounds & surfaces ----
  final Color ground; // page background
  final Color surface; // card background
  final Color surfaceAlt; // subtle inset / secondary panel
  final Color surfaceSunken; // input wells, code blocks

  // ---- ink ----
  final Color ink; // primary text
  final Color inkSoft; // secondary text
  final Color muted; // tertiary text, labels

  // ---- lines ----
  final Color line; // hairline border
  final Color lineStrong; // emphasised border

  // ---- brand ----
  final Color gold; // the accent
  final Color goldBright; // highlights, active marks
  final Color goldDeep; // gold text on light (legible)
  final Color goldTint; // flat tinted card fill

  // ---- semantic ----
  final Color success;
  final Color successTint;
  final Color warning;
  final Color warningTint;
  final Color danger;
  final Color dangerTint;
  final Color info;
  final Color infoTint;
  final Color violet;
  final Color violetTint;

  // ---- misc ----
  final Color scrim; // modal backdrop
  final Color shadow;

  const BxColors({
    required this.ground,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.gold,
    required this.goldBright,
    required this.goldDeep,
    required this.goldTint,
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.danger,
    required this.dangerTint,
    required this.info,
    required this.infoTint,
    required this.violet,
    required this.violetTint,
    required this.scrim,
    required this.shadow,
  });

  static const light = BxColors(
    ground: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F3F7),
    surfaceSunken: Color(0xFFF4F6F9),
    ink: Color(0xFF0F1729),
    inkSoft: Color(0xFF2A3648),
    muted: Color(0xFF697586),
    line: Color(0xFFE3E7ED),
    lineStrong: Color(0xFFCED5DF),
    gold: Color(0xFFD4A017),
    goldBright: Color(0xFFF0B429),
    goldDeep: Color(0xFF8A6500),
    goldTint: Color(0xFFFDF7E8),
    success: Color(0xFF0E8A54),
    successTint: Color(0xFFE7F5EE),
    warning: Color(0xFFB26A00),
    warningTint: Color(0xFFFCF2E3),
    danger: Color(0xFFC42B1C),
    dangerTint: Color(0xFFFCEDEB),
    info: Color(0xFF2563EB),
    infoTint: Color(0xFFEDF2FE),
    violet: Color(0xFF6D4AC4),
    violetTint: Color(0xFFF1EDFB),
    scrim: Color(0x800F1729),
    shadow: Color(0x140F1729),
  );

  static const dark = BxColors(
    ground: Color(0xFF0A1120),
    surface: Color(0xFF111B2E),
    surfaceAlt: Color(0xFF17223A),
    surfaceSunken: Color(0xFF0D1626),
    ink: Color(0xFFE9EEF9),
    inkSoft: Color(0xFFC5D0E4),
    muted: Color(0xFF8D9CBA),
    line: Color(0xFF223050),
    lineStrong: Color(0xFF32436B),
    gold: Color(0xFFF5C542),
    goldBright: Color(0xFFFFD666),
    goldDeep: Color(0xFFF5C542),
    goldTint: Color(0xFF241D08),
    success: Color(0xFF3ECF8E),
    successTint: Color(0xFF0B2419),
    warning: Color(0xFFF0A500),
    warningTint: Color(0xFF241A08),
    danger: Color(0xFFF07167),
    dangerTint: Color(0xFF2A1310),
    info: Color(0xFF6BA0FF),
    infoTint: Color(0xFF0E1B36),
    violet: Color(0xFFA594F0),
    violetTint: Color(0xFF1A1633),
    scrim: Color(0xB3050A14),
    shadow: Color(0x66000000),
  );

  /// Convenience accessor used everywhere: `context.bx.gold`
  @override
  BxColors copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunken,
    Color? ink,
    Color? inkSoft,
    Color? muted,
    Color? line,
    Color? lineStrong,
    Color? gold,
    Color? goldBright,
    Color? goldDeep,
    Color? goldTint,
    Color? success,
    Color? successTint,
    Color? warning,
    Color? warningTint,
    Color? danger,
    Color? dangerTint,
    Color? info,
    Color? infoTint,
    Color? violet,
    Color? violetTint,
    Color? scrim,
    Color? shadow,
  }) {
    return BxColors(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      gold: gold ?? this.gold,
      goldBright: goldBright ?? this.goldBright,
      goldDeep: goldDeep ?? this.goldDeep,
      goldTint: goldTint ?? this.goldTint,
      success: success ?? this.success,
      successTint: successTint ?? this.successTint,
      warning: warning ?? this.warning,
      warningTint: warningTint ?? this.warningTint,
      danger: danger ?? this.danger,
      dangerTint: dangerTint ?? this.dangerTint,
      info: info ?? this.info,
      infoTint: infoTint ?? this.infoTint,
      violet: violet ?? this.violet,
      violetTint: violetTint ?? this.violetTint,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  BxColors lerp(ThemeExtension<BxColors>? other, double t) {
    if (other is! BxColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return BxColors(
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      muted: c(muted, other.muted),
      line: c(line, other.line),
      lineStrong: c(lineStrong, other.lineStrong),
      gold: c(gold, other.gold),
      goldBright: c(goldBright, other.goldBright),
      goldDeep: c(goldDeep, other.goldDeep),
      goldTint: c(goldTint, other.goldTint),
      success: c(success, other.success),
      successTint: c(successTint, other.successTint),
      warning: c(warning, other.warning),
      warningTint: c(warningTint, other.warningTint),
      danger: c(danger, other.danger),
      dangerTint: c(dangerTint, other.dangerTint),
      info: c(info, other.info),
      infoTint: c(infoTint, other.infoTint),
      violet: c(violet, other.violet),
      violetTint: c(violetTint, other.violetTint),
      scrim: c(scrim, other.scrim),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Spacing scale. Every gap and pad in the app is one of these.
abstract final class BxSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 56;
}

/// Corner radii. Sharp, not pillowy — 14 is the card default.
abstract final class BxRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius control = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Motion. Consistent timing makes the whole app feel designed.
abstract final class BxDuration {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
  static const xslow = Duration(milliseconds: 620);
  static const stagger = Duration(milliseconds: 55);
}

abstract final class BxCurves {
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const spring = Cubic(0.2, 0.9, 0.3, 1.15);
  static const smooth = Curves.easeInOutCubic;
}

/// One restrained shadow, spent by role. Not every surface gets one.
abstract final class BxShadow {
  static List<BoxShadow> card(BxColors c) => [
        BoxShadow(color: c.shadow, blurRadius: 2, offset: const Offset(0, 1)),
      ];

  static List<BoxShadow> raised(BxColors c) => [
        BoxShadow(color: c.shadow, blurRadius: 3, offset: const Offset(0, 1)),
        BoxShadow(
          color: c.shadow,
          blurRadius: 24,
          spreadRadius: -8,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> overlay(BxColors c) => [
        BoxShadow(
          color: c.shadow,
          blurRadius: 40,
          spreadRadius: -12,
          offset: const Offset(0, 16),
        ),
      ];
}

/// `context.bx` — the one-liner every widget uses to reach the palette.
extension BxThemeAccess on BuildContext {
  BxColors get bx =>
      Theme.of(this).extension<BxColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? BxColors.dark
          : BxColors.light);

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// True when the viewport is wide enough for the rail + content layout.
  ///
  /// Deliberately reads zero as "not wide". A window can report no size
  /// at all on the very first frame, before the platform has measured
  /// it, and a breakpoint that answers from that measurement lays the
  /// app out once for the wrong width and again a frame later — which a
  /// student sees as the interface sliding sideways as the navigation
  /// rail appears and then leaves.
  bool get isWide {
    final w = MediaQuery.sizeOf(this).width;
    return w >= 900;
  }

  /// True on tablets and small laptops — two-column grids.
  bool get isMedium {
    final w = MediaQuery.sizeOf(this).width;
    return w >= 600;
  }

  /// True while the platform has not told us how big the window is.
  /// Layouts that change shape across a breakpoint should hold their
  /// narrow form until this is false rather than guess.
  bool get sizeUnknown {
    final s = MediaQuery.sizeOf(this);
    return s.width <= 0 || s.height <= 0;
  }
}

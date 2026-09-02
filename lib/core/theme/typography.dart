import 'package:flutter/material.dart';

/// ============================================================
/// TYPE SYSTEM
///
/// Three roles, three families, one scale:
///   display — Space Grotesk, for headings and figures
///   body    — Inter, for reading
///   data    — JetBrains Mono, for numbers, codes and eyebrows
///
/// All three are bundled VARIABLE fonts, so weight is selected with
/// a FontVariation on the `wght` axis. Setting fontWeight alone would
/// make the engine synthesise a faux bold; these helpers set both, so
/// the real weight is drawn.
/// ============================================================

abstract final class BxFont {
  static const display = 'SpaceGrotesk';
  static const body = 'Inter';
  static const data = 'JetBrainsMono';

  static const fallback = <String>[
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];
  static const monoFallback = <String>['Menlo', 'Consolas', 'monospace'];
}

/// Builds a TextStyle that carries a real variable-font weight.
TextStyle _v(
  String family, {
  required double size,
  required int weight,
  double? height,
  double? letterSpacing,
  Color? color,
  FontStyle? fontStyle,
  List<String>? fallback,
}) {
  return TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback ??
        (family == BxFont.data ? BxFont.monoFallback : BxFont.fallback),
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    fontStyle: fontStyle,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );
}

/// The app's type scale. Screens compose these; nothing hand-rolls a
/// TextStyle from scratch.
abstract final class BxType {
  // ---- display (Space Grotesk) ----
  /// Score heroes, the Millionaire prize, the CGPA figure.
  static TextStyle hero(Color c) =>
      _v(BxFont.display, size: 52, weight: 700, height: 1.0, letterSpacing: -1.4, color: c);

  /// Page titles.
  static TextStyle h1(Color c) =>
      _v(BxFont.display, size: 27, weight: 700, height: 1.12, letterSpacing: -0.6, color: c);

  /// Section titles, card headlines.
  static TextStyle h2(Color c) =>
      _v(BxFont.display, size: 21, weight: 700, height: 1.18, letterSpacing: -0.35, color: c);

  /// Sub-headings, list-row titles that need weight.
  static TextStyle h3(Color c) =>
      _v(BxFont.display, size: 17, weight: 600, height: 1.24, letterSpacing: -0.2, color: c);

  /// Big numbers on stat tiles.
  static TextStyle figure(Color c) =>
      _v(BxFont.display, size: 30, weight: 700, height: 1.05, letterSpacing: -0.8, color: c);

  // ---- body (Inter) ----
  static TextStyle bodyLg(Color c) =>
      _v(BxFont.body, size: 16, weight: 400, height: 1.55, color: c);

  static TextStyle body(Color c) =>
      _v(BxFont.body, size: 14.5, weight: 400, height: 1.52, color: c);

  static TextStyle bodyStrong(Color c) =>
      _v(BxFont.body, size: 14.5, weight: 600, height: 1.45, color: c);

  static TextStyle small(Color c) =>
      _v(BxFont.body, size: 13, weight: 400, height: 1.45, color: c);

  static TextStyle smallStrong(Color c) =>
      _v(BxFont.body, size: 13, weight: 600, height: 1.4, color: c);

  static TextStyle tiny(Color c) =>
      _v(BxFont.body, size: 11.5, weight: 500, height: 1.4, color: c);

  /// Button and tab labels.
  static TextStyle label(Color c) =>
      _v(BxFont.body, size: 14, weight: 600, height: 1.2, letterSpacing: 0.1, color: c);

  // ---- data (JetBrains Mono) ----
  /// The signature eyebrow: uppercase, wide tracking, gold.
  static TextStyle eyebrow(Color c) => _v(BxFont.data,
      size: 10.5, weight: 600, height: 1.3, letterSpacing: 1.7, color: c);

  /// Tabular figures: scores, timers, counters, codes.
  static TextStyle mono(Color c, {double size = 13, int weight = 500}) =>
      _v(BxFont.data, size: size, weight: weight, height: 1.3, color: c);

  /// The exam clock and other big monospace readouts.
  static TextStyle clock(Color c) =>
      _v(BxFont.data, size: 17, weight: 600, height: 1.1, letterSpacing: 0.4, color: c);
}

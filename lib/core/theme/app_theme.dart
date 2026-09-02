import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds the ThemeData for a given palette. Everything visual routes
/// through BxColors, so light and dark stay in lockstep by construction.
ThemeData _build(Brightness brightness, BxColors c) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.gold,
    onPrimary: brightness == Brightness.dark
        ? const Color(0xFF1A1400)
        : const Color(0xFF241A00),
    secondary: c.info,
    onSecondary: Colors.white,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surfaceAlt,
    outline: c.line,
    outlineVariant: c.lineStrong,
    shadow: c.shadow,
    scrim: c.scrim,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    dividerColor: c.line,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],

    fontFamily: BxFont.body,
    fontFamilyFallback: BxFont.fallback,

    textTheme: TextTheme(
      displayLarge: BxType.hero(c.ink),
      headlineLarge: BxType.h1(c.ink),
      headlineMedium: BxType.h2(c.ink),
      titleLarge: BxType.h3(c.ink),
      bodyLarge: BxType.bodyLg(c.ink),
      bodyMedium: BxType.body(c.ink),
      bodySmall: BxType.small(c.muted),
      labelLarge: BxType.label(c.ink),
      labelSmall: BxType.eyebrow(c.goldDeep),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: BxType.h2(c.ink),
      iconTheme: IconThemeData(color: c.ink, size: 22),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),

    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BxRadius.card,
        side: BorderSide(color: c.line),
      ),
    ),

    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),

    iconTheme: IconThemeData(color: c.inkSoft, size: 22),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: const Color(0xFF241A00),
        disabledBackgroundColor: c.surfaceAlt,
        disabledForegroundColor: c.muted,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.xl, vertical: BxSpace.md),
        textStyle: BxType.label(const Color(0xFF241A00)),
        shape: const RoundedRectangleBorder(borderRadius: BxRadius.control),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.lineStrong),
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.lg, vertical: BxSpace.md),
        textStyle: BxType.label(c.ink),
        shape: const RoundedRectangleBorder(borderRadius: BxRadius.control),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.goldDeep,
        textStyle: BxType.label(c.goldDeep),
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.sm, vertical: BxSpace.xs),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceSunken,
      hintStyle: BxType.body(c.muted),
      labelStyle: BxType.small(c.muted),
      errorStyle: BxType.tiny(c.danger),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: BxSpace.md, vertical: BxSpace.md),
      border: OutlineInputBorder(
        borderRadius: BxRadius.control,
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BxRadius.control,
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BxRadius.control,
        borderSide: BorderSide(color: c.gold, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BxRadius.control,
        borderSide: BorderSide(color: c.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BxRadius.control,
        borderSide: BorderSide(color: c.danger, width: 1.6),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.goldTint,
      elevation: 0,
      height: 66,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(BxType.tiny(c.muted)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 23,
          color: s.contains(WidgetState.selected) ? c.goldDeep : c.muted,
        ),
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.goldTint,
      selectedLabelTextStyle: BxType.smallStrong(c.ink),
      unselectedLabelTextStyle: BxType.small(c.muted),
      selectedIconTheme: IconThemeData(color: c.goldDeep, size: 22),
      unselectedIconTheme: IconThemeData(color: c.muted, size: 22),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.sheet),
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BxRadius.lg),
        side: BorderSide(color: c.line),
      ),
      titleTextStyle: BxType.h2(c.ink),
      contentTextStyle: BxType.body(c.inkSoft),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: BxType.small(c.ground),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.control),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceAlt,
      side: BorderSide(color: c.line),
      labelStyle: BxType.tiny(c.inkSoft),
      padding: const EdgeInsets.symmetric(horizontal: BxSpace.xs),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(BxRadius.pill))),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(BxRadius.xs),
      ),
      textStyle: BxType.tiny(c.ground),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.gold,
      linearTrackColor: c.surfaceAlt,
      circularTrackColor: c.surfaceAlt,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: c.gold,
      inactiveTrackColor: c.surfaceAlt,
      thumbColor: c.gold,
      overlayColor: c.gold.withValues(alpha: 0.12),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.gold : c.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.goldTint : c.surfaceAlt),
      trackOutlineColor: WidgetStatePropertyAll(c.line),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BxRadius.sm),
        side: BorderSide(color: c.line),
      ),
      textStyle: BxType.body(c.ink),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      textColor: c.ink,
      titleTextStyle: BxType.bodyStrong(c.ink),
      subtitleTextStyle: BxType.small(c.muted),
      shape: const RoundedRectangleBorder(borderRadius: BxRadius.control),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _BxPageTransition(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: _BxPageTransition(),
      TargetPlatform.windows: _BxPageTransition(),
    }),
  );
}

/// A restrained slide-and-fade. Sharper than Material's default zoom,
/// and it reads as premium rather than playful.
class _BxPageTransition extends PageTransitionsBuilder {
  const _BxPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: BxCurves.enter, reverseCurve: BxCurves.exit);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.022),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

final ThemeData bxLightTheme = _build(Brightness.light, BxColors.light);
final ThemeData bxDarkTheme = _build(Brightness.dark, BxColors.dark);

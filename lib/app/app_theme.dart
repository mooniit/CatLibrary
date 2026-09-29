import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeKey = 'appearance_theme';

Future<ThemeMode> loadAppTheme() async {
  try {
    return (await SharedPreferences.getInstance()).getString(_themeKey) ==
            'night'
        ? ThemeMode.dark
        : ThemeMode.light;
  } catch (_) {
    return ThemeMode.light;
  }
}

Future<void> saveAppTheme(ThemeMode mode) async {
  await (await SharedPreferences.getInstance()).setString(
    _themeKey,
    mode == ThemeMode.dark ? 'night' : 'light',
  );
}

SystemUiOverlayStyle appSystemBars(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: dark ? const Color(0xff151a24) : Colors.white,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? const Color(0xff9cb2cd) : const Color(0xff7186a0);
  final surface = dark ? const Color(0xff151a24) : Colors.white;
  final ink = dark ? const Color(0xfff1f3f7) : const Color(0xff242832);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? const Color(0xff151a24) : Colors.white,
        surface: surface,
        onSurface: ink,
        surfaceContainerLow: dark
            ? const Color(0xff202634)
            : const Color(0xfff6f7f9),
        surfaceContainer: dark
            ? const Color(0xff252d3c)
            : const Color(0xffeef1f4),
        outline: dark ? const Color(0xff657185) : const Color(0xffa9b2bf),
        outlineVariant: dark
            ? const Color(0xff384252)
            : const Color(0xffdce0e6),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: appSystemBars(brightness),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withValues(alpha: dark ? 0.22 : 0.16),
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
  );
}

import 'package:flutter/material.dart';

/// One selectable brand palette - just the identity colors (primary/accent),
/// not the semantic status colors (success/warning/danger/neutral), which
/// stay fixed across every theme since they're a UX convention (red means
/// trouble, green means done) rather than a branding choice.
class ThemePreset {
  const ThemePreset({
    required this.key,
    required this.label,
    required this.primary,
    required this.primaryLight,
    required this.accent,
    required this.accentLight,
  });

  final String key;
  final String label;
  final Color primary;
  final Color primaryLight;
  final Color accent;
  final Color accentLight;
}

/// Every theme a super admin can pick from Console > Settings. The first
/// entry is the original SuperD brand look and doubles as the fallback for
/// an unrecognized/missing `app_settings.theme` value.
const List<ThemePreset> kThemePresets = [
  ThemePreset(
    key: 'navy_gold',
    label: 'Navy & Gold',
    primary: Color(0xFF16213E),
    primaryLight: Color(0xFFE7EAF2),
    accent: Color(0xFFF5A623),
    accentLight: Color(0xFFFFF3DC),
  ),
  ThemePreset(
    key: 'ocean_blue',
    label: 'Ocean Blue',
    primary: Color(0xFF0B3D91),
    primaryLight: Color(0xFFE3ECFA),
    accent: Color(0xFF00B8D9),
    accentLight: Color(0xFFDFF7FB),
  ),
  ThemePreset(
    key: 'forest_green',
    label: 'Forest Green',
    primary: Color(0xFF1B4332),
    primaryLight: Color(0xFFE3EFE8),
    accent: Color(0xFFE9C46A),
    accentLight: Color(0xFFFBF1DA),
  ),
  ThemePreset(
    key: 'sunset_orange',
    label: 'Sunset Orange',
    primary: Color(0xFF6B3226),
    primaryLight: Color(0xFFF7E6E0),
    accent: Color(0xFFFF7F50),
    accentLight: Color(0xFFFFE8DA),
  ),
  ThemePreset(
    key: 'royal_purple',
    label: 'Royal Purple',
    primary: Color(0xFF3B1F63),
    primaryLight: Color(0xFFEDE3F5),
    accent: Color(0xFFC084FC),
    accentLight: Color(0xFFF5EBFF),
  ),
  ThemePreset(
    key: 'charcoal_dark',
    label: 'Charcoal',
    primary: Color(0xFF1C1C1E),
    primaryLight: Color(0xFFE4E4E7),
    accent: Color(0xFF2EC4B6),
    accentLight: Color(0xFFDFF7F4),
  ),
];

ThemePreset themePresetFor(String key) => kThemePresets.firstWhere(
  (p) => p.key == key,
  orElse: () => kThemePresets.first,
);

/// SuperD's theme. The identity colors below default to the original
/// navy/gold brand look but aren't `const` - [apply] swaps them for a
/// different [ThemePreset] when a super admin changes it in Settings.
/// They're deliberately still plain static fields (not threaded through
/// `Theme.of(context)`) to match how the rest of the app already reads
/// them; swapping them only takes visual effect once the app is
/// rebuilt from the root - see the `KeyedSubtree` in `app.dart`.
class AppTheme {
  AppTheme._();

  static Color primary = kThemePresets.first.primary;
  static Color primaryLight = kThemePresets.first.primaryLight;
  static Color accent = kThemePresets.first.accent;
  static Color accentLight = kThemePresets.first.accentLight;

  // Semantic status colors - intentionally fixed, not part of any preset.
  static const Color danger = Color(0xFFD64545);
  static const Color warning = Color(0xFFE0A800);
  static const Color success = Color(0xFF2E9E5B);
  static const Color neutral = Color(0xFF5B6B85);

  static void apply(String presetKey) {
    final preset = themePresetFor(presetKey);
    primary = preset.primary;
    primaryLight = preset.primaryLight;
    accent = preset.accent;
    accentLight = preset.accentLight;
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      secondary: accent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      splashColor: accent.withValues(alpha: 0.15),
      highlightColor: accent.withValues(alpha: 0.08),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE7EAEE)),
        ),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: primary,
        elevation: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: Color(0xFFCBD3DC)),
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD3DC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD3DC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

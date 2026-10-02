import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The Admin Console's own design layer - surfaces, spacing, radii and
/// type, read directly by Console widgets the same way the rest of the
/// app already reads `AppTheme.primary` as a static field rather than
/// through `Theme.of(context)`.
///
/// Deliberately separate from [AppTheme]/`AppTheme.light`: that `ThemeData`
/// is the whole app's theme (driver app, login, the two public forms
/// included), so changing it there would reskin screens nobody asked to
/// touch. This file only affects what lives under `/admin` -
/// [AdminShellScreen] and the Console tabs - while still deriving its one
/// brand color from [AppTheme.primary]/[AppTheme.accent], so a super
/// admin's theme-preset choice in Settings still carries through.
///
/// The shift from the old per-tab look: shadow-heavy floating white cards
/// become flatter panels separated by a hairline border, closer to
/// control-room software than a marketing dashboard template; spacing and
/// radii are tighter and more consistent; numbers get tabular figures so
/// columns of them actually line up.
class ConsoleColors {
  ConsoleColors._();

  /// Page background - cooler and a shade darker than the app-wide
  /// scaffold color, so a white [ConsoleCard] actually separates from the
  /// page instead of needing a shadow to prove it's there.
  static const canvas = Color(0xFFEFF2F6);

  static const surface = Color(0xFFFFFFFF);

  /// An inset surface one step down from [surface] - a table's header
  /// row, a stat tile inside a card, anything that reads as "beneath" the
  /// panel it sits in rather than beside it.
  static const surfaceSunken = Color(0xFFF6F7FA);

  static const border = Color(0xFFE1E5EB);
  static const borderStrong = Color(0xFFCDD3DD);

  /// Near-black navy rather than pure black - warmer under the cool
  /// canvas, and close in hue to the Navy & Gold preset's own primary so
  /// body text never looks like an unrelated system bolted on, whichever
  /// preset is active.
  static const ink = Color(0xFF13192B);
  static const inkMuted = Color(0xFF5B6478);
  static const inkFaint = Color(0xFF9AA2B1);

  static Color get accent => AppTheme.accent;
  static Color get primary => AppTheme.primary;

  // Pass-throughs so Console code reads one namespace for every color it
  // needs rather than switching between ConsoleColors and AppTheme mid
  // file - these three stay fixed across every theme preset, same as on
  // AppTheme itself.
  static const Color success = AppTheme.success;
  static const Color warning = AppTheme.warning;
  static const Color danger = AppTheme.danger;
}

class ConsoleSpace {
  ConsoleSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class ConsoleRadius {
  ConsoleRadius._();

  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 14.0;
}

/// A console-wide type scale. Every numeric display style carries
/// [FontFeature.tabularFigures] so a column of KPI values or a ranked
/// list's counts sit flush rather than drifting with each digit's own
/// width - the one typographic refinement that matters most on a screen
/// that is mostly numbers, without pulling in a webfont dependency a
/// blind edit pass can't verify actually loads.
class ConsoleText {
  ConsoleText._();

  static const _tabular = [FontFeature.tabularFigures()];

  /// A page/section's own name - "Dashboard", "Deliveries".
  static const pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: ConsoleColors.ink,
  );

  /// A card's heading.
  static const cardTitle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    color: ConsoleColors.ink,
  );

  static const cardSubtitle = TextStyle(
    fontSize: 12,
    color: ConsoleColors.inkMuted,
  );

  /// A short uppercase label over a value or a section of rows - e.g. a
  /// stat tile's caption. Letter-spaced the way a label reads as a label
  /// rather than a sentence.
  static const eyebrow = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: ConsoleColors.inkMuted,
  );

  /// A KPI tile's headline number.
  static const statValue = TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.1,
    fontFeatures: _tabular,
  );

  static const body = TextStyle(fontSize: 13.5, color: ConsoleColors.ink);
  static const bodyMuted = TextStyle(
    fontSize: 12.5,
    color: ConsoleColors.inkMuted,
  );

  /// Any other figure set in running text or a table cell that should
  /// still line up in a column - a currency amount, a count.
  static const number = TextStyle(fontFeatures: _tabular);
}

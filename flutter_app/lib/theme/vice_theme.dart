// Colors and sizing lifted directly from the Android app
// (LauncherLayoutHelper.java, ViceMenuPanel.java, MainActivity.java) so the
// Flutter workbench reads as the same app, not a reskin.
//
// Flutter's logical pixels are the same concept as Android's dp (both are
// density-independent units the platform scales to physical pixels), so
// every `dp(n)` value from the Java source is used here unconverted as a
// plain double.
import 'package:flutter/material.dart';

class ViceColors {
  ViceColors._();

  // Root background (LauncherLayoutHelper.createLauncher: rootStack bg).
  static const Color rootBackground = Color(0xFF050607);

  // Sidebar / content panel background (LauncherLayoutHelper.contentBackground).
  static const Color panelFill = Color(0xCC0B0D10);
  static const Color panelStroke = Color(0x44FFFFFF);

  // Selected sidebar button (LauncherLayoutHelper.selectedBackground).
  static const Color selectedFill = Color(0xFF24292E);
  static const Color selectedStroke = Color(0xFF444D56);

  // Sidebar label colors.
  static const Color sidebarLabelIdle = Color(0xFF8C939D);
  static const Color sidebarLabelSelected = Colors.white;

  // Shared accent colors used throughout (music EQ, status text, etc).
  static const Color accentTeal = Color(0xFF00FFCC);
  static const Color accentBlue = Color(0xFF2D8CFF);

  // Media / SID card chrome (MainActivity.createMediaCard / createSidCard).
  static const Color cardFill = Color(0xFF191D22);
  static const Color cardStroke = Color(0xFF353B44);
  static const Color coverFill = Color(0xFF262C34);
  static const Color coverStroke = Color(0xFF404853);
  static const Color sidCardFill = Color(0xFF242A31);
  static const Color sidCardStroke = Color(0xFF46505C);

  static const Color textMuted = Color(0xFF9AA3AF);
  static const Color textMuted2 = Color(0xFFBAC2CC);
}

class ViceMetrics {
  ViceMetrics._();

  // Sidebar rail width is MEASURED from the widest label (see sidebar.dart)
  // rather than pinned to a flat 160dp: the flat value came from a
  // UI-layout note, but the live Android source
  // (LauncherLayoutHelper.createLauncher) also measures -- min(measured,
  // dp(150) / a quarter of the screen), floor dp(88) -- and on a real
  // 853dp-wide device the fixed value left a wide dead strip beside every
  // label. These are the clamp bounds for that measurement.
  static const double sidebarMinWidth = 118.0;
  static double sidebarMaxWidth(double screenWidth) {
    final quarter = screenWidth * 0.25;
    return quarter < 190.0 ? quarter : 190.0;
  }

  // LauncherLayoutHelper.createMenuButton: dp(36) height, 12sp text, 10dp
  // left padding. Height is a FLOOR here, not a fixed value -- the row
  // grows when the platform text scale does (the Retroid runs at 1.35x),
  // which is what stops the labels looking cramped on device.
  static const double sidebarButtonHeight = 36.0;
  static const double sidebarButtonTextSize = 13.0;
  static const double sidebarButtonBottomMargin = 4.0;
  static const double sidebarButtonSidePadding = 10.0;
  static const double sidebarButtonVerticalPadding = 8.0;

  // mainRootPadding / sideNav padding.
  static const double rootPadding = 12.0;
  static const double sideNavPadding = 6.0;
  static const double contentLeftMargin = 12.0;

  // MainActivity.createMediaCard (grid mode).
  static const double mediaCardWidth = 120.0;
  static const double mediaCardHeight = 178.0;
  static const double mediaCoverHeight = 120.0;
  static const double mediaCardCell = 126.0; // card + margins, for column math

  // ViceMenuPanel.panelWidth: min(dp(340), 45% of screen width).
  static double quickSettingsPanelWidth(double screenWidth) {
    final pct = screenWidth * 0.45;
    return pct < 340.0 ? pct : 340.0;
  }
}

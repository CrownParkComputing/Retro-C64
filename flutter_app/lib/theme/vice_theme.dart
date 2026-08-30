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

  // ---------------------------------------------------------------------
  // The VIC-II's own sixteen colours.
  //
  // These are Pepto's measurements of the real chip's composite output --
  // the same values VICE itself uses -- not an artist's impression of
  // "retro". A C64 could display these and nothing else, so an interface
  // built from them is the machine's own palette rather than a theme laid
  // over a generic shell.
  //
  // Kept as the complete set, including the colours nothing currently
  // draws with, because the point is the palette, not a selection from it.
  // ---------------------------------------------------------------------
  static const Color c64Black = Color(0xFF000000);
  static const Color c64White = Color(0xFFFFFFFF);
  static const Color c64Red = Color(0xFF68372B);
  static const Color c64Cyan = Color(0xFF70A4B2);
  static const Color c64Purple = Color(0xFF6F3D86);
  static const Color c64Green = Color(0xFF588D43);
  static const Color c64Blue = Color(0xFF352879);
  static const Color c64Yellow = Color(0xFFB8C76F);
  static const Color c64Orange = Color(0xFF6F4F25);
  static const Color c64Brown = Color(0xFF433900);
  static const Color c64LightRed = Color(0xFF9A6759);
  static const Color c64DarkGrey = Color(0xFF444444);
  static const Color c64Grey = Color(0xFF6C6C6C);
  static const Color c64LightGreen = Color(0xFF9AD284);
  static const Color c64LightBlue = Color(0xFF6C5EB5);
  static const Color c64LightGrey = Color(0xFF959595);

  // ---------------------------------------------------------------------
  // Roles, mapped onto the palette above.
  //
  // The arrangement is the machine's own boot screen: blue screen, lighter
  // blue border and cursor. Panels sit DARKER than the root rather than
  // lighter, which is what keeps body text legible -- light grey on the
  // root blue is only 4.0:1, and on the panel fill it is 4.7:1.
  // ---------------------------------------------------------------------

  /// The screen itself.
  static const Color rootBackground = c64Blue;

  /// Panels sit inside the screen, so they are the same hue driven down.
  static const Color panelFill = Color(0xE6251C55);
  static const Color panelStroke = Color(0x806C5EB5);

  /// The selected rail entry is the C64's cursor: a solid light-blue block.
  static const Color selectedFill = c64LightBlue;
  static const Color selectedStroke = Color(0xFF8B7FD0);

  static const Color sidebarLabelIdle = c64LightGrey;
  static const Color sidebarLabelSelected = c64White;

  /// The accent throughout. Cyan is the C64's, and it is the one colour in
  /// this palette that carries at small sizes against the blue.
  static const Color accentCyan = c64Cyan;

  // Media / SID card chrome.
  static const Color cardFill = Color(0xFF251C55);
  static const Color cardStroke = Color(0x666C5EB5);
  static const Color coverFill = Color(0xFF2E2465);
  static const Color coverStroke = Color(0x806C5EB5);
  static const Color sidCardFill = Color(0xFF2A2060);
  static const Color sidCardStroke = Color(0x666C5EB5);

  static const Color textMuted = c64LightGrey;
  static const Color textMuted2 = Color(0xD9FFFFFF);
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
  /// 128, not 118: the floor has to clear the widest label the rail actually
  /// carries. "Compliance" needs about 122pt once the icon column and side
  /// padding are counted, so at 118 the longest entry rendered as "Com..." on
  /// every screen of every phone -- and so in every store screenshot -- while
  /// looking like a deliberate width rather than a fault.
  static const double sidebarMinWidth = 128.0;

  /// Upper bound for the measured rail, never below [sidebarMinWidth].
  ///
  /// The floor matters: a quarter of the screen is under 118 on any display
  /// narrower than 472pt, which is every iPhone in portrait. Returning the
  /// bare quarter then handed sidebar.dart a clamp whose lower bound was above
  /// its upper one, and `double.clamp` throws on that -- "Invalid argument(s):
  /// 118.0". The build failed, the rail never laid out, and what a tester saw
  /// was a white screen in portrait that came right in landscape, where the
  /// quarter finally exceeds the floor.
  ///
  /// A quarter is a preference, not a constraint. On a narrow screen the rail
  /// takes its minimum and gives up a little more of the width, which is the
  /// intended trade: the labels stay readable either way.
  static double sidebarMaxWidth(double screenWidth) {
    // A third, not a quarter. The rail sizes itself to its widest label, and a
    // quarter of any iPhone is below what "Compliance" needs, so the cap was
    // binding on all of them. A third still leaves two thirds for content, and
    // the ceiling keeps a wide tablet from growing a needlessly fat rail.
    final share = screenWidth / 3;
    final capped = share < 190.0 ? share : 190.0;
    return capped < sidebarMinWidth ? sidebarMinWidth : capped;
  }

  // LauncherLayoutHelper.createMenuButton: dp(36) height, 12sp text, 10dp
  // left padding. Height is a FLOOR here, not a fixed value -- the row
  // grows when the platform text scale does (the Retroid runs at 1.35x),
  // which is what stops the labels looking cramped on device.
  static const double sidebarButtonHeight = 36.0;
  static const double sidebarButtonTextSize = 13.0;
  /// Gap under each rail button. Tight on purpose: the rail has to show
  /// every destination at once on a 456dp-tall screen, and gaps are the
  /// cheapest height to give back -- far cheaper than shrinking the text.
  static const double sidebarButtonBottomMargin = 2.0;
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

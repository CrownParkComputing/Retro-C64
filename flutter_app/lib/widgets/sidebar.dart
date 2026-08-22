import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The side nav shared by every Retro-* front end.
///
/// This file is deliberately IDENTICAL in all of the apps. Nothing in it
/// imports a per-app theme: the colours and metrics arrive as a
/// [SidebarStyle], which each app builds from its own theme file. Before
/// this, four front ends had four rails -- one decoupled, one that imported
/// its category enum from workbench_screen.dart (and so could not be reused
/// or unit-tested), one private class inlined in a screen, and one with a
/// different name and API again. Any fix had to be made four times and
/// usually was not.
///
/// Sizing is measured, not hardcoded. LauncherLayoutHelper.createLauncher in
/// the Android original also sized this rail from its content (widest
/// measured label, floored at dp(88), capped at dp(150)/a quarter of the
/// screen); an earlier pass pinned it at a flat 160dp instead, which left a
/// wide dead strip to the right of every label on a 853dp-wide device -- and,
/// worse, ignored the platform text scale entirely, so at the Retroid's 1.35x
/// font scale the labels were far too big for the fixed 36dp rows. Both are
/// computed here:
///   - width  = icon column + widest measured title + paddings, clamped
///   - height = text height + vertical padding, floored at a touch target
class Sidebar extends StatelessWidget {
  final List<SidebarDestination> destinations;

  /// Index into [destinations]. Out-of-range simply means "nothing
  /// highlighted", which is the right behaviour while a screen is still
  /// deciding what it is showing rather than an error worth asserting on.
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// Optional content pinned to the bottom of the rail, below the scrolling
  /// destination list -- a music status line, a mount/cycles readout. Null
  /// means the rail ends after the last button.
  final Widget? footer;

  /// Pins the highest-numbered [SidebarDestination.group] to the bottom of
  /// the rail instead of letting it scroll with the rest. The reference-y
  /// destinations (Music, History, About) belong at the far end of the rail
  /// the way About always does -- and a band that drifts up the rail as the
  /// list above it grows or shrinks stops being a landmark.
  final bool pinLastGroupToBottom;

  final SidebarStyle style;

  const Sidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.style,
    this.footer,
    this.pinLastGroupToBottom = false,
  });

  static const double _iconColumnWidth = 22.0;
  static const double _iconGap = 10.0;

  /// Destinations [from, to), with a hairline wherever the group changes.
  List<Widget> _buttons({
    required int from,
    required int to,
    required double rowHeight,
    required TextStyle textStyle,
    required bool hasIcons,
  }) {
    final out = <Widget>[];
    for (var i = from; i < to; i++) {
      if (i > from && destinations[i].group != destinations[i - 1].group) {
        out.add(_GroupRule(color: style.panelStroke));
      }
      out.add(_SidebarButton(
        destination: destinations[i],
        selected: i == selectedIndex,
        onTap: () => onSelected(i),
        height: rowHeight,
        titleStyle: textStyle,
        style: style,
        iconWidth: hasIcons ? _iconColumnWidth : 0,
        iconGap: hasIcons ? _iconGap : 0,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = scaler.scale(style.buttonTextSize);
    final textStyle = TextStyle(
      fontSize: titleSize,
      height: 1.15,
      color: style.labelIdle,
    );

    // Widest title decides the rail width, so no label is ever clipped and
    // there is no dead space beyond one consistent right margin.
    //
    // Measured in the SELECTED weight, which is the widest a row ever gets.
    // Measuring the regular weight and painting the selected one semi-bold is
    // what turned "Settings" into "Settin..." the moment it was picked -- and
    // only for the longer labels, which reads as a random clip rather than as
    // a width that is one weight too small.
    final measureStyle = textStyle.copyWith(fontWeight: FontWeight.w600);
    double widest = 0;
    for (final dest in destinations) {
      final painter = TextPainter(
        text: TextSpan(text: dest.title, style: measureStyle),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }

    // Only reserve the icon column if something actually has an icon --
    // otherwise a rail of plain labels carries a permanent empty gutter.
    final hasIcons = destinations.any((d) => d.hasIcon);
    final iconAllowance = hasIcons ? _iconColumnWidth + _iconGap : 0.0;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final railWidth =
        (widest + iconAllowance + style.buttonSidePadding * 2 + style.navPadding * 2)
            .clamp(style.minWidth, style.maxWidth(screenWidth));

    // Rows grow with the text rather than clipping it, but never get smaller
    // than a comfortable touch target.
    final rowHeight = (titleSize * 1.15 + style.buttonVerticalPadding * 2)
        .clamp(style.buttonHeight, 72.0);

    // Where the scrolling part of the list ends. With no pinned band that is
    // simply "all of them".
    final lastGroup =
        destinations.isEmpty ? 0 : destinations.last.group;
    final pinnedFrom = pinLastGroupToBottom
        ? destinations.indexWhere((d) => d.group == lastGroup)
        : -1;
    final scrollingCount =
        pinnedFrom >= 0 ? pinnedFrom : destinations.length;

    // Everything on one page: the rail is NEVER scrolled.
    //
    // It used to be, because a fixed 12-entry column overran the Retroid
    // Flip2's 456dp landscape height by 32px. Scrolling solved the overflow
    // and created a worse problem: an entry you cannot see is an entry that
    // does not exist, which is how the Compliance page went missing on the
    // one device it most needed to be visible on. So the rows shrink to fit
    // the height available instead, down to a floor that is still a usable
    // touch target, and only a rail that cannot fit even then falls back to
    // scrolling.
    const double rowFloor = 30.0;
    // 3px padding either side of a 1px line -- see _GroupRule.
    const double ruleHeight = 7.0;
    // EVERY group boundary draws one, not just the pinned band's. Counting
    // only the pinned rule is what pushed the last entry out through the
    // bottom of the panel: the budget was short by one rule plus the
    // per-button margins, which together came to about one row's worth.
    var ruleCount = 0;
    for (var i = 1; i < destinations.length; i++) {
      if (destinations[i].group != destinations[i - 1].group) ruleCount++;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowCount = destinations.length;
        var fittedRow = rowHeight;
        if (rowCount > 0 && constraints.maxHeight.isFinite) {
          final available = constraints.maxHeight -
              style.navPadding * 2 -
              ruleCount * ruleHeight -
              (footer != null ? 26.0 : 0.0);
          if (available > 0) {
            // Each row costs its height PLUS the gap beneath it.
            final perRow = available / rowCount - style.buttonBottomMargin;
            fittedRow = math.min(rowHeight, perRow).clamp(rowFloor, rowHeight);
          }
        }

        // Shrink the label with the row, or tall text in a short button
        // clips. Only ever downwards, and never past legibility.
        final shrink = (fittedRow / rowHeight).clamp(0.0, 1.0);
        final fittedText = shrink < 1.0
            ? textStyle.copyWith(
                fontSize: math.max(titleSize * shrink, titleSize * 0.72))
            : textStyle;

        final everythingFits = !constraints.maxHeight.isFinite ||
            rowCount * (rowFloor + style.buttonBottomMargin) +
                    ruleCount * ruleHeight +
                    style.navPadding * 2 +
                    (footer != null ? 26.0 : 0.0) <=
                constraints.maxHeight;

        final topRows = _buttons(
          from: 0,
          to: scrollingCount,
          rowHeight: fittedRow,
          textStyle: fittedText,
          hasIcons: hasIcons,
        );
        final pinnedRows = (pinnedFrom >= 0 && pinnedFrom < destinations.length)
            ? _buttons(
                from: pinnedFrom,
                to: destinations.length,
                rowHeight: fittedRow,
                textStyle: fittedText,
                hasIcons: hasIcons,
              )
            : const <Widget>[];

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (everythingFits) ...[
              ...topRows,
              // Keeps the last band against the bottom when there is room to
              // spare, and collapses to nothing when there is not.
              const Spacer(),
            ] else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: topRows,
                  ),
                ),
              ),
            if (pinnedRows.isNotEmpty) ...[
              _GroupRule(color: style.panelStroke),
              ...pinnedRows,
            ],
            if (footer != null)
              Padding(
                padding: EdgeInsets.only(
                  left: style.buttonSidePadding,
                  top: 6,
                  bottom: 2,
                ),
                child: footer,
              ),
          ],
        );

        return Container(
          width: railWidth,
          padding: EdgeInsets.all(style.navPadding),
          decoration: BoxDecoration(
            color: style.panelFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.panelStroke),
          ),
          child: body,
        );
      },
    );
  }

}

/// One entry in the side nav. [icon] is an optional emoji shown in a fixed
/// column to the left of the title; [iconData] is the same column drawn as a
/// Material icon instead. The apps differ here on purpose -- the C64 rail's
/// emoji are part of that machine's look, the Amiga's line icons are part of
/// its -- and one rail supporting both is what keeps this file identical
/// everywhere.
///
/// [group] sorts the rail into bands. Entries keep the order they are given
/// in; the rail draws a hairline wherever the group changes, so the bands
/// read as "where you go", "how it is set up" and "everything else" rather
/// than as one undifferentiated list of nine. Leave it at 0 and the rail
/// behaves exactly as it did before groups existed.
class SidebarDestination {
  final String title;
  final String? icon;
  final IconData? iconData;
  final int group;

  const SidebarDestination(
    this.title, {
    this.icon,
    this.iconData,
    this.group = 0,
  });

  bool get hasIcon => icon != null || iconData != null;
}

/// The per-app colours and metrics the rail needs. Each front end builds one
/// of these from its own theme, which is the only thing that differs between
/// apps -- the widget above stays identical.
class SidebarStyle {
  final Color panelFill;
  final Color panelStroke;
  final Color selectedFill;
  final Color selectedStroke;
  final Color labelIdle;
  final Color labelSelected;

  final double minWidth;
  final double buttonHeight;
  final double buttonTextSize;
  final double buttonBottomMargin;
  final double buttonSidePadding;
  final double buttonVerticalPadding;
  final double navPadding;

  /// Cap on the rail width, as a function of the screen width. The Android
  /// original capped at a quarter of the screen; keeping it a function rather
  /// than a constant is what stops a long label eating a small display.
  final double Function(double screenWidth) maxWidth;

  const SidebarStyle({
    required this.panelFill,
    required this.panelStroke,
    required this.selectedFill,
    required this.selectedStroke,
    required this.labelIdle,
    required this.labelSelected,
    required this.minWidth,
    required this.buttonHeight,
    required this.buttonTextSize,
    required this.buttonBottomMargin,
    required this.buttonSidePadding,
    required this.buttonVerticalPadding,
    required this.navPadding,
    required this.maxWidth,
  });
}

/// The band separator: a hairline with air either side. Deliberately not a
/// Divider -- Divider's own inset and 16px default height are tuned for
/// lists, and both are wrong inside a 456dp-tall rail.
class _GroupRule extends StatelessWidget {
  final Color color;

  const _GroupRule({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(height: 1, color: color),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final SidebarDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final TextStyle titleStyle;
  final SidebarStyle style;
  final double iconWidth;
  final double iconGap;

  const _SidebarButton({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.titleStyle,
    required this.style,
    required this.iconWidth,
    required this.iconGap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: style.buttonBottomMargin),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: style.buttonSidePadding),
            decoration: selected
                ? BoxDecoration(
                    color: style.selectedFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: style.selectedStroke),
                  )
                : null,
            child: Row(
              children: [
                if (iconWidth > 0) ...[
                  SizedBox(
                    width: iconWidth,
                    child: destination.iconData != null
                        ? Icon(
                            destination.iconData,
                            size: (titleStyle.fontSize ?? 14) + 2,
                            color: selected
                                ? style.labelSelected
                                : style.labelIdle,
                          )
                        : Text(
                            destination.icon ?? '',
                            // See the note on the title below: this size has
                            // already been scaled.
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(fontSize: titleStyle.fontSize),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  SizedBox(width: iconGap),
                ],
                Expanded(
                  child: Text(
                    destination.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The size in titleStyle has ALREADY been through the
                    // platform text scaler (see build()), and the rail's
                    // width and row heights were measured from it. Letting
                    // Text scale it a second time squares the factor -- on a
                    // device set to 1.35x that is 1.8x -- so labels came out
                    // far larger than the rows measured for them and the
                    // shrink-to-fit above was silently undone.
                    textScaler: TextScaler.noScaling,
                    style: titleStyle.copyWith(
                      color: selected ? style.labelSelected : style.labelIdle,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

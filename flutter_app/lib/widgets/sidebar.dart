import 'package:flutter/material.dart';

import '../data/category.dart';
import '../theme/vice_theme.dart';

/// The side nav: a vertical rail of destination buttons and a music-status
/// line pinned to the bottom.
///
/// Sizing is measured, not hardcoded. LauncherLayoutHelper.createLauncher in
/// the Android original also sizes this rail from its content (widest
/// measured label, floored at dp(88), capped at dp(150)/a quarter of the
/// screen); an earlier pass of this port pinned it at a flat 160dp instead,
/// which left a wide dead strip to the right of every label on a 853dp-wide
/// device -- and, worse, ignored the platform text scale entirely, so at the
/// Retroid's 1.35x font scale the labels were far too big for the fixed
/// 36dp rows. Both are computed here now:
///   - width  = icon column + widest measured title + paddings, clamped
///   - height = text height + vertical padding, floored at a touch target
class Sidebar extends StatelessWidget {
  final WorkbenchCategory selected;
  final ValueChanged<WorkbenchCategory> onSelect;
  final String musicStatus;

  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.musicStatus = 'MUSIC: IDLE',
  });

  static const double _iconColumnWidth = 22.0;
  static const double _iconGap = 10.0;

  TextStyle _titleStyle(double scaledSize) => TextStyle(
        fontSize: scaledSize,
        height: 1.15,
        color: ViceColors.sidebarLabelIdle,
      );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = scaler.scale(ViceMetrics.sidebarButtonTextSize);
    final style = _titleStyle(titleSize);

    // Widest title decides the rail width, so no label is ever clipped and
    // there's no dead space beyond one consistent right margin.
    double widest = 0;
    for (final cat in WorkbenchCategory.values) {
      final painter = TextPainter(
        text: TextSpan(text: cat.title, style: style),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }

    final horizontalPadding = ViceMetrics.sidebarButtonSidePadding * 2;
    final rowContentWidth = _iconColumnWidth + _iconGap + widest;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final railWidth = (rowContentWidth +
            horizontalPadding +
            ViceMetrics.sideNavPadding * 2)
        .clamp(ViceMetrics.sidebarMinWidth,
            ViceMetrics.sidebarMaxWidth(screenWidth));

    // Rows grow with the text rather than clipping it, but never get
    // smaller than a comfortable touch target.
    final rowHeight = (titleSize * 1.15 + ViceMetrics.sidebarButtonVerticalPadding * 2)
        .clamp(ViceMetrics.sidebarButtonHeight, 72.0);

    return Container(
      width: railWidth,
      padding: const EdgeInsets.all(ViceMetrics.sideNavPadding),
      decoration: BoxDecoration(
        color: ViceColors.panelFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ViceColors.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail must never overflow, however short the window is (the
          // Retroid Flip2 is only 456dp tall in landscape, which the old
          // fixed 12-entry Column overran by 32px). Expanded + a scroll
          // view gives the buttons all the room there is and scrolls any
          // remainder; Expanded (not Flexible) also keeps the music status
          // line pinned to the bottom of the rail.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final cat in WorkbenchCategory.values)
                    _SidebarButton(
                      category: cat,
                      selected: cat == selected,
                      onTap: () => onSelect(cat),
                      height: rowHeight,
                      titleStyle: style,
                      iconWidth: _iconColumnWidth,
                      iconGap: _iconGap,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: ViceMetrics.sidebarButtonSidePadding,
              top: 6,
              bottom: 2,
            ),
            child: Text(
              musicStatus,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                color: ViceColors.accentTeal,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final WorkbenchCategory category;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final TextStyle titleStyle;
  final double iconWidth;
  final double iconGap;

  const _SidebarButton({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.titleStyle,
    required this.iconWidth,
    required this.iconGap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: ViceMetrics.sidebarButtonBottomMargin),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(
                horizontal: ViceMetrics.sidebarButtonSidePadding),
            decoration: selected
                ? BoxDecoration(
                    color: ViceColors.selectedFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ViceColors.selectedStroke),
                  )
                : null,
            child: Row(
              children: [
                // Fixed-width icon cell: emoji advance widths differ, so
                // this is what actually keeps the titles left-aligned with
                // each other.
                SizedBox(
                  width: iconWidth,
                  child: Text(
                    category.icon,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: titleStyle.fontSize! * 0.95),
                  ),
                ),
                SizedBox(width: iconGap),
                Expanded(
                  child: Text(
                    category.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle.copyWith(
                      color: selected
                          ? ViceColors.sidebarLabelSelected
                          : ViceColors.sidebarLabelIdle,
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

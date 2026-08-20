import 'sidebar.dart';
import '../theme/vice_theme.dart';

/// The C64 front end's rail palette. This adapter is the only per-app part of
/// the side nav -- widgets/sidebar.dart itself is identical in every Retro-*
/// app, so a fix there lands everywhere instead of once.
const SidebarStyle viceSidebarStyle = SidebarStyle(
  panelFill: ViceColors.panelFill,
  panelStroke: ViceColors.panelStroke,
  selectedFill: ViceColors.selectedFill,
  selectedStroke: ViceColors.selectedStroke,
  labelIdle: ViceColors.sidebarLabelIdle,
  labelSelected: ViceColors.sidebarLabelSelected,
  minWidth: ViceMetrics.sidebarMinWidth,
  buttonHeight: ViceMetrics.sidebarButtonHeight,
  buttonTextSize: ViceMetrics.sidebarButtonTextSize,
  buttonBottomMargin: ViceMetrics.sidebarButtonBottomMargin,
  buttonSidePadding: ViceMetrics.sidebarButtonSidePadding,
  buttonVerticalPadding: ViceMetrics.sidebarButtonVerticalPadding,
  navPadding: ViceMetrics.sideNavPadding,
  maxWidth: ViceMetrics.sidebarMaxWidth,
);

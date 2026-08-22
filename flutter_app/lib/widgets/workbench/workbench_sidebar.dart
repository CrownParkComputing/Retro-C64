import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retro_c64/theme/vice_theme.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';
import 'package:retro_c64/widgets/sidebar.dart';
import 'package:retro_c64/widgets/sidebar_style.dart';

class WorkbenchSidebar extends StatelessWidget {
  final double screenWidth;

  const WorkbenchSidebar({super.key, required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkbenchViewModel>();

    if (vm.sidebarHidden || vm.hideChrome) return const SizedBox.shrink();

    return Row(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ViceMetrics.sidebarMaxWidth(screenWidth),
          ),
          child: Sidebar(
            // The rail offers what this mode can actually do. In free-ROM
            // mode the user's media folder is not the one in use, so Games
            // and Music would be destinations onto an empty room.
            destinations: [
              for (final c in vm.visibleCategories)
                SidebarDestination(c.title, icon: c.icon, group: c.group),
            ],
            selectedIndex: vm.visibleCategories.indexOf(vm.category),
            onSelected: (i) => vm.setCategory(vm.visibleCategories[i]),
            style: viceSidebarStyle,
            pinLastGroupToBottom: true,
          ),
        ),
        const SizedBox(width: ViceMetrics.contentLeftMargin),
      ],
    );
  }
}

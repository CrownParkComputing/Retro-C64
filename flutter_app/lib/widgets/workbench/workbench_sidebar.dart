import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/category.dart';
import '../../theme/vice_theme.dart';
import '../../view_models/workbench_view_model.dart';
import '../sidebar.dart';
import '../sidebar_style.dart';

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
            destinations: [
              for (final c in WorkbenchCategory.values)
                SidebarDestination(c.title, icon: c.icon, group: c.group),
            ],
            selectedIndex: vm.category.index,
            onSelected: (i) => vm.setCategory(WorkbenchCategory.values[i]),
            style: viceSidebarStyle,
            pinLastGroupToBottom: true,
          ),
        ),
        const SizedBox(width: ViceMetrics.contentLeftMargin),
      ],
    );
  }
}

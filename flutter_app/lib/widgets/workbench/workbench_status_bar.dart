import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/theme/vice_theme.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';

class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkbenchViewModel>();

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Row(
        children: [
          IconButton(
            onPressed: vm.toggleSidebar,
            icon: Icon(
              vm.sidebarHidden ? Icons.menu : Icons.menu_open,
              size: 18,
            ),
            color: ViceColors.sidebarLabelIdle,
            tooltip: vm.sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 6),
          // Says which machine this is, whenever it is not the ordinary
          // one. Free-ROM mode changes what the app boots from and hides
          // the library, and a mode you can forget you are in is a mode
          // that gets reported as a fault -- "where have my games gone".
          if (vm.demoMode) ...[
            InkWell(
              onTap: () => vm.setCategory(WorkbenchCategory.compliance),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x3300FFCC),
                  border: Border.all(color: ViceColors.accentTeal),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'COMPLIANCE MODE — FREE ROMS',
                  style: TextStyle(
                    color: ViceColors.accentTeal,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              vm.lastMediaName.isEmpty ? 'No media loaded' : vm.lastMediaName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ViceColors.sidebarLabelIdle,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

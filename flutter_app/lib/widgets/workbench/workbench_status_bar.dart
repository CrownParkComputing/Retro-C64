import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/vice_theme.dart';
import '../../view_models/workbench_view_model.dart';
import '../emulator_control_strip.dart';

class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkbenchViewModel>();

    if (vm.hideChrome) return const SizedBox.shrink();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (vm.inEmulator) vm.wakeChrome();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            IconButton(
              onPressed: vm.toggleSidebar,
              icon: Icon(vm.sidebarHidden ? Icons.menu : Icons.menu_open, size: 18),
              color: ViceColors.sidebarLabelIdle,
              tooltip: vm.sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 6),
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
            if (vm.inEmulator)
              EmulatorControlStrip(
                ui: vm.emulatorUi,
                onPause: vm.backToLibrary,
                padMode: vm.padMode,
                onPadModeChanged: vm.setPadMode,
                joystickPort: vm.joystickPort,
                onJoystickPortChanged: vm.setJoystickPort,
              ),
          ],
        ),
      ),
    );
  }
}

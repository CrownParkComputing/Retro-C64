import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retro_c64/theme/vice_theme.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';
import 'package:retro_c64/widgets/c64_background.dart';
import 'workbench_content.dart';
import 'workbench_sidebar.dart';
import 'workbench_status_bar.dart';

class WorkbenchShell extends StatelessWidget {
  final VoidCallback? onRerunSetup;

  const WorkbenchShell({super.key, this.onRerunSetup});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkbenchViewModel>();
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: ViceColors.rootBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => vm.scheduleIdle(),
              onPointerSignal: (_) => vm.scheduleIdle(),
              onPointerHover: (_) => vm.scheduleIdle(),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(ViceMetrics.rootPadding),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            WorkbenchSidebar(screenWidth: screenWidth),
                            Expanded(child: WorkbenchContent(onRerunSetup: onRerunSetup)),
                          ],
                        ),
                      ),
                      const WorkbenchStatusBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (vm.screensaverActive)
            Positioned.fill(
              child: C64Background(
                active: true,
                infoText: vm.backdropInfoText(),
                audioLevel: () => vm.core.isRunning ? vm.core.audioLevel : 0,
                onWake: vm.scheduleIdle,
              ),
            ),
        ],
      ),
    );
  }
}

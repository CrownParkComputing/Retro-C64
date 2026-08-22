import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/category.dart';
import '../../screens/about_screen.dart';
import '../../screens/core_settings_screen.dart';
import '../../screens/emulator_screen.dart';
import '../../screens/history_screen.dart';
import '../../screens/input_settings_screen.dart';
import '../../screens/compliance_screen.dart';
import '../../screens/library_grid.dart';
import '../../screens/music_screen.dart';
import '../../screens/paths_settings_screen.dart';
import '../../screens/resume_screen.dart';
import '../../screens/video_settings_screen.dart';
import '../../theme/vice_theme.dart';
import '../../view_models/workbench_view_model.dart';

class WorkbenchContent extends StatelessWidget {
  final VoidCallback? onRerunSetup;

  const WorkbenchContent({super.key, this.onRerunSetup});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkbenchViewModel>();

    return Container(
      padding: EdgeInsets.all(vm.hideChrome ? 0 : 10),
      decoration: vm.hideChrome
          ? const BoxDecoration(color: ViceColors.panelFill)
          : BoxDecoration(
              color: ViceColors.panelFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ViceColors.panelStroke),
            ),
      clipBehavior: Clip.antiAlias,
      child: _buildBody(context, vm),
    );
  }

  Widget _buildBody(BuildContext context, WorkbenchViewModel vm) {
    if (isLibraryCategory(vm.category)) {
      final grid = LibraryGrid(
        allEntries: vm.library,
        onLaunch: (entry) => vm.launch(entry, context),
      );

      if (vm.isLibraryLoading) {
        return const Center(child: CircularProgressIndicator());
      }

      if (vm.unreadableCount == 0) return grid;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UnreadableBanner(
            count: vm.unreadableCount,
            onGrant: vm.requestStorageAccess,
          ),
          Expanded(child: grid),
        ],
      );
    }

    return switch (vm.category) {
      WorkbenchCategory.games => const SizedBox.shrink(), // Handled above
      WorkbenchCategory.resume => vm.inEmulator
          ? EmulatorScreen(
              core: vm.core,
              mediaLabel: vm.emulatorLabel,
              onScreenTouched: vm.wakeChrome,
              onBackToLibrary: vm.backToLibrary,
              leftHanded: vm.leftHanded,
              gamepad: vm.gamepad,
              padMode: vm.padMode,
              onPadModeChanged: vm.setPadMode,
              customButtons: vm.customButtons,
              onCustomButtonsChanged: vm.setCustomButtons,
              joystickPort: vm.joystickPort,
              onJoystickPortChanged: vm.setJoystickPort,
              ui: vm.emulatorUi,
            )
          : ResumeScreen(
              currentTitle: vm.currentEntry?.displayName,
              onResumeCurrent: vm.resumeCurrent,
              onResumeSaved: (entry) => vm.resumeSaved(entry, context),
            ),
      WorkbenchCategory.music => const MusicScreen(),
      WorkbenchCategory.paths => PathsSettingsScreen(
          onLibraryShouldRescan: vm.scanLibrary,
          onRerunSetup: onRerunSetup,
        ),
      WorkbenchCategory.history => const HistoryScreen(),
      WorkbenchCategory.compliance => const ComplianceScreen(),
      WorkbenchCategory.video => const VideoSettingsScreen(),
      WorkbenchCategory.input => InputSettingsScreen(
          leftHanded: vm.leftHanded,
          onLeftHandedChanged: vm.setLeftHanded,
          padMode: vm.padMode,
          onPadModeChanged: vm.setPadMode,
          customButtons: vm.customButtons,
          onCustomButtonsChanged: vm.setCustomButtons,
          joystickPort: vm.joystickPort,
          onJoystickPortChanged: vm.setJoystickPort,
          gamepadConnected: vm.gamepad.connected,
        ),
      WorkbenchCategory.core => CoreSettingsScreen(core: vm.core),
      WorkbenchCategory.about => AboutScreen(
          onOpenCompliance: () =>
              vm.setCategory(WorkbenchCategory.compliance),
        ),
    };
  }
}

class _UnreadableBanner extends StatelessWidget {
  final int count;
  final VoidCallback onGrant;

  const _UnreadableBanner({required this.count, required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2E12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8A6D2F)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count file${count == 1 ? '' : 's'} hidden: the app can list '
              'them but not read them. Grant "All files access" to use them.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onGrant,
            child: const Text('GRANT', style: TextStyle(color: ViceColors.accentTeal)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:retro_c64/data/emulator_ui_state.dart';
import 'package:retro_c64/services/app_prefs.dart';
import 'package:retro_c64/theme/vice_theme.dart';

/// The in-game tool rail, down the right edge of the session screen where
/// the thumb already is: keyboard, on-screen pad mode, joystick port and
/// layout editing, as labelled buttons -- an unlabelled circle two rooms
/// from its effect was the single most common review complaint across the
/// Retro-* family.
///
/// Extracted from the session screen so the widget tests can drive it next
/// to an EmulatorScreen with plain callbacks, the way the old control strip
/// was tested.
class SessionToolRail extends StatelessWidget {
  final EmulatorUiState ui;

  final OnScreenPadMode padMode;
  final ValueChanged<OnScreenPadMode>? onPadModeChanged;

  final int joystickPort;
  final ValueChanged<int>? onJoystickPortChanged;

  /// Restarts the auto-hide countdown on the chrome this rail is part of.
  final VoidCallback? onWake;

  /// Whatever [padMode] and [joystickPort] are read from, so the rail
  /// repaints when they change. The session screen passes its view model.
  final Listenable? listenable;

  const SessionToolRail({
    super.key,
    required this.ui,
    required this.padMode,
    this.onPadModeChanged,
    required this.joystickPort,
    this.onJoystickPortChanged,
    this.onWake,
    this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable == null ? ui : Listenable.merge([listenable, ui]),
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailTool(
            icon: Icons.keyboard,
            label: 'Keys',
            lit: ui.keyboardVisible,
            tooltip: ui.keyboardVisible ? 'Hide keyboard' : 'Show keyboard',
            onTap: () {
              onWake?.call();
              ui.toggleKeyboard();
            },
          ),
          _RailTool(
            icon: Icons.videogame_asset,
            label: 'Pad',
            tooltip: '${padMode.label} -- ${padMode.description}',
            onTap: () {
              onWake?.call();
              onPadModeChanged?.call(padMode.next);
            },
          ),
          // Port swap, showing the port it is on. First thing to try when a
          // game ignores the stick entirely, and "nothing moves" is not a
          // moment to go hunting through menus.
          _RailTool(
            text: 'P$joystickPort',
            label: 'Port',
            tooltip: 'Joystick in port $joystickPort -- tap to swap',
            onTap: () {
              onWake?.call();
              onJoystickPortChanged?.call(joystickPort == 1 ? 2 : 1);
            },
          ),
          // Layout editing lives out here rather than in Input Settings:
          // you can only judge where a control should go while looking at
          // the game it has to sit on top of.
          _RailTool(
            icon: ui.editingLayout ? Icons.check : Icons.open_with,
            label: 'Layout',
            lit: ui.editingLayout,
            tooltip: ui.editingLayout
                ? 'Finish moving controls'
                : 'Move or add on-screen controls',
            onTap: () {
              onWake?.call();
              ui.toggleLayoutEditing();
            },
          ),
        ],
      ),
    );
  }
}

/// One labelled tool on the session rail: a 34px circle with its name under
/// it, matching the Amiga and Saturn rails.
class _RailTool extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final String label;
  final String tooltip;
  final bool lit;
  final VoidCallback onTap;

  const _RailTool({
    this.icon,
    this.text,
    required this.label,
    required this.tooltip,
    this.lit = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: lit ? ViceColors.accentTeal : const Color(0x66000000),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: tooltip,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: icon != null
                          ? Icon(icon,
                              color: lit ? Colors.black : Colors.white,
                              size: 18)
                          : Text(
                              text!,
                              style: TextStyle(
                                color: lit ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

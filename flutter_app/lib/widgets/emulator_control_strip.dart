import 'package:flutter/material.dart';

import '../data/emulator_ui_state.dart';
import '../services/app_prefs.dart';

/// The in-game control strip: pause, keyboard, on-screen pad, joystick port
/// and layout editing, in one row along the bottom of the workbench.
///
/// It sits OUTSIDE the content panel, on the right-hand end of the status
/// row that already carries the rail toggle and the loaded title. The border
/// is the edge of the emulated machine; chrome drawn inside it reads as part
/// of the picture, and drawn ON the picture it covers the bottom-right of a
/// 4:3 frame, which is where games put their status panels.
///
/// Sharing the status row rather than taking a band of its own is the point:
/// that row is already on screen, and a second band would come straight out
/// of the picture's height -- which is the one thing a 4:3 machine on a wide
/// handheld has none of to spare.
///
/// Laid out right-to-left, so the first child is the rightmost button and the
/// strip grows leftwards from the edge nearest the hand already holding the
/// device.
class EmulatorControlStrip extends StatelessWidget {
  final EmulatorUiState ui;

  /// Pause is the only way out of a session, and it keeps your place: it
  /// returns to the workbench having snapshotted. There is deliberately no
  /// close button -- the rolling save states keep the last five sessions
  /// either way, so a second button whose only difference was throwing one
  /// of them away was a trap, not a choice. Starting a different title is
  /// what ends this one.
  final VoidCallback onPause;

  final OnScreenPadMode padMode;
  final ValueChanged<OnScreenPadMode>? onPadModeChanged;

  final int joystickPort;
  final ValueChanged<int>? onJoystickPortChanged;

  const EmulatorControlStrip({
    super.key,
    required this.ui,
    required this.onPause,
    required this.padMode,
    this.onPadModeChanged,
    required this.joystickPort,
    this.onJoystickPortChanged,
  });

  static const Color _idle = Color(0xFF24292E);
  static const Color _keyboardLit = Color(0xFF4040E0);
  static const Color _editingLit = Color(0xFF008080);

  /// Compact, not FAB-sized: the strip shares the status row under the
  /// picture, and a row of 40px buttons was costing the machine a border's
  /// worth of height. 32px is still a comfortable target with the row's own
  /// padding around it. Same treatment as Retro-Amiga's strip.
  ///
  /// The gap between them is 16, not 8. At 8 the buttons read as one blurred
  /// bar on a handheld rather than as separate targets, and the two that
  /// matter mid-game -- pause and the port swap -- are the ones you least
  /// want to hit by accident.
  Widget _tool({
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(width: 32, height: 32, child: Center(child: child)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) => Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: [
          _tool(
            color: _idle,
            tooltip: 'Pause and return to the workbench',
            onPressed: onPause,
            child: const Icon(Icons.pause, color: Colors.white, size: 18),
          ),
          _tool(
            // Lit while the keyboard is up, so the button doubles as the
            // indicator of its own state.
            color: ui.keyboardVisible ? _keyboardLit : _idle,
            tooltip: ui.keyboardVisible ? 'Keyboard shown' : 'Keyboard hidden',
            onPressed: ui.toggleKeyboard,
            child: const Icon(Icons.keyboard, color: Colors.white, size: 18),
          ),
          _tool(
            color: _idle,
            tooltip: '${padMode.label} -- ${padMode.description}',
            onPressed: () => onPadModeChanged?.call(padMode.next),
            child: const Icon(Icons.videogame_asset,
                color: Colors.white, size: 18),
          ),
          // Port swap, as a button that shows the port it is on. This is
          // the first thing to try when a game ignores the stick entirely,
          // and "nothing moves" is not a moment to go hunting through
          // menus. The number IS the label.
          _tool(
            color: _idle,
            tooltip: 'Joystick port $joystickPort',
            onPressed: () =>
                onJoystickPortChanged?.call(joystickPort == 1 ? 2 : 1),
            child: Text(
              'P$joystickPort',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Layout editing lives out here rather than in Input Settings:
          // you can only judge where a control should go while looking at
          // the game it has to sit on top of.
          _tool(
            color: ui.editingLayout ? _editingLit : _idle,
            tooltip: ui.editingLayout
                ? 'Finish moving controls'
                : 'Move or add on-screen controls',
            onPressed: ui.toggleLayoutEditing,
            child: Icon(
              ui.editingLayout ? Icons.check : Icons.open_with,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

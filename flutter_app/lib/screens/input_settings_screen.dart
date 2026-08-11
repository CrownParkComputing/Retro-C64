import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/c64_keys.dart';
import '../services/app_prefs.dart';
import '../theme/vice_theme.dart';
import '../widgets/custom_key_button.dart';

/// Input Settings tab: the left-handed on-screen-joystick position toggle,
/// live external-gamepad connection status (see services/gamepad_service.dart),
/// and a pointer to where the A/B fire-button remap UI actually lives
/// (long-press the button in-game -- see widgets/assignable_action_button.dart).
class InputSettingsScreen extends StatelessWidget {
  final bool leftHanded;
  final ValueChanged<bool> onLeftHandedChanged;
  final OnScreenPadMode padMode;
  final ValueChanged<OnScreenPadMode> onPadModeChanged;
  final int joystickPort;
  final ValueChanged<int> onJoystickPortChanged;
  final List<C64Key> customButtons;
  final ValueChanged<List<C64Key>> onCustomButtonsChanged;
  final ValueListenable<bool> gamepadConnected;

  const InputSettingsScreen({
    super.key,
    required this.leftHanded,
    required this.onLeftHandedChanged,
    required this.padMode,
    required this.onPadModeChanged,
    required this.joystickPort,
    required this.onJoystickPortChanged,
    required this.customButtons,
    required this.onCustomButtonsChanged,
    required this.gamepadConnected,
  });

  Widget _card({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF191D22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF353B44)),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Input Settings',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        // Joystick port first: it is the setting that decides whether the
        // controls work AT ALL on a given game.
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Joystick port',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                'The C64 has two joystick ports and games disagree about which '
                'one they read. Most use port 2; if a game ignores your input '
                'entirely, switch to port 1. Applies to the on-screen stick, '
                'the A/B buttons and any external controller.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Port 1')),
                  ButtonSegment(value: 2, label: Text('Port 2')),
                ],
                selected: {joystickPort},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onJoystickPortChanged(s.first),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('On-screen pad',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                'Auto hides the touch joystick and A/B buttons while a '
                'controller is connected. Always keeps them on screen anyway, '
                'which is what you want on a handheld whose built-in pad '
                'always counts as connected. Never hides them outright.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              SegmentedButton<OnScreenPadMode>(
                segments: [
                  for (final mode in OnScreenPadMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {padMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onPadModeChanged(s.first),
              ),
            ],
          ),
        ),
        _card(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Left-handed mode',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    SizedBox(height: 4),
                    Text(
                      'Moves the on-screen joystick to the bottom-right and the '
                      'A/B buttons to the bottom-left. Direction mapping is unchanged.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: leftHanded,
                activeThumbColor: ViceColors.accentTeal,
                onChanged: onLeftHandedChanged,
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Extra on-screen buttons',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                'A and B are the joystick fire buttons and stay that way. Add '
                'your own buttons here for games that want a keyboard key -- '
                'SPACE to start, RUN/STOP to abort, and so on. Any C64 key can '
                'be assigned; the new button appears next to A and B in-game.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (customButtons.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No extra buttons yet.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < customButtons.length; i++)
                      InputChip(
                        label: Text(customButtons[i].label),
                        backgroundColor: const Color(0xFF22272E),
                        labelStyle: const TextStyle(color: Colors.white),
                        deleteIconColor: Colors.white54,
                        onDeleted: () {
                          final next = [...customButtons]..removeAt(i);
                          onCustomButtonsChanged(next);
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ViceColors.accentTeal,
                    side: const BorderSide(color: ViceColors.accentTeal),
                  ),
                  onPressed: () async {
                    final key = await showC64KeyPicker(context);
                    if (key == null) return;
                    onCustomButtonsChanged([...customButtons, key]);
                  },
                ),
              ),
            ],
          ),
        ),
        _card(
          child: ValueListenableBuilder<bool>(
            valueListenable: gamepadConnected,
            builder: (context, isConnected, _) {
              return Row(
                children: [
                  Icon(
                    isConnected ? Icons.sports_esports : Icons.sports_esports_outlined,
                    color: isConnected ? ViceColors.accentTeal : Colors.white38,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('External gamepad',
                            style: TextStyle(color: Colors.white, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          isConnected
                              ? 'Connected -- D-pad/left stick and A/B map to the '
                                  'C64 joystick automatically. On-screen controls '
                                  'follow the "On-screen pad" setting above.'
                              : 'None detected. Plug one in at any time -- no restart needed.',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Full remap-any-key UI and per-device configuration deferred to a later milestone.',
              style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}

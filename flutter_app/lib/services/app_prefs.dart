// Thin wrapper around shared_preferences for the handful of persisted
// settings the setup wizard needs: whether it's been completed once (so it
// only shows on first run, mirroring SetupWizardActivity's
// PREF_SETUP_COMPLETED), and the chosen app/games folder paths on the
// folder-scan platforms (PREF_APP_FOLDER_URI / PREF_GAMES_FOLDER_URI in the
// Android original -- here a plain filesystem path rather than a SAF URI,
// since file_picker hands back a real path on both Linux and Android).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/c64_keys.dart';

/// When the on-screen joypad is shown. See [AppPrefs.getOnScreenPadMode].
enum OnScreenPadMode {
  auto('Auto', 'Hidden while a controller is connected'),
  always('Always', 'Always shown, even with a controller'),
  never('Never', 'Never shown');

  final String label;
  final String description;
  const OnScreenPadMode(this.label, this.description);

  /// Whether the pad should be on screen right now.
  bool visibleWith({required bool controllerConnected}) => switch (this) {
        OnScreenPadMode.always => true,
        OnScreenPadMode.never => false,
        OnScreenPadMode.auto => !controllerConnected,
      };

  /// Next mode when the user taps the single Quick Settings row.
  OnScreenPadMode get next =>
      OnScreenPadMode.values[(index + 1) % OnScreenPadMode.values.length];
}

class AppPrefs {
  AppPrefs._();

  static const _keySetupCompleted = 'setup_completed';
  static const _keyAppFolderPath = 'app_folder_path';
  static const _keyGamesFolderPath = 'games_folder_path';
  static const _keyLeftHandedInput = 'left_handed_input';
  static const _keyActionButtonAKey = 'action_button_a_key';
  static const _keyActionButtonBKey = 'action_button_b_key';
  // Distinct key from the short-lived boolean 'force_on_screen_pad' this
  // replaced: reading an int out of a key that holds a bool is a type error
  // on some shared_preferences platforms, so the old key is abandoned rather
  // than reused. Worst case an early tester's setting resets to Auto once.
  static const _keyOnScreenPadMode = 'on_screen_pad_mode';
  static const _keyJoystickPort = 'joystick_port';
  static const _keyCustomButtons = 'custom_on_screen_buttons';

  /// Sentinel stored in prefs for "use the joystick fire default" (no
  /// explicit key remap), mirroring Android's KEY_MAPPING_DEFAULT. Kept
  /// private -- callers see this as `null`.
  static const int _mappingDefault = -1;

  static Future<bool> isSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySetupCompleted) ?? false;
  }

  static Future<void> setSetupCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySetupCompleted, value);
  }

  static Future<String?> getAppFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAppFolderPath);
  }

  static Future<void> setAppFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppFolderPath, path);
  }

  static Future<String?> getGamesFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGamesFolderPath);
  }

  static Future<void> setGamesFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGamesFolderPath, path);
  }

  /// Mirrors the on-screen joystick's position from bottom-left to
  /// bottom-right of the emulator screen (position only -- direction
  /// mapping is unchanged). Set from the Input Settings tab.
  static Future<bool> getLeftHandedInput() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLeftHandedInput) ?? false;
  }

  static Future<void> setLeftHandedInput(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLeftHandedInput, value);
  }

  /// When the on-screen joypad is shown.
  ///
  /// This is ONE setting rather than the two overlapping controls the UI
  /// briefly had (a local show/hide toggle plus a separate "force visible"
  /// override, which showed up as duplicate joypad rows in Quick Settings).
  /// The three modes cover every case between them:
  ///
  ///  - [OnScreenPadMode.auto]: hide while a controller is connected. The
  ///    sensible default, and what the app always used to do.
  ///  - [OnScreenPadMode.always]: keep the touch controls up regardless --
  ///    the case auto-hide alone made impossible on a handheld like the
  ///    Retroid Flip2, whose built-in gamepad is permanently "connected".
  ///  - [OnScreenPadMode.never]: no touch controls, even with no controller.
  static Future<OnScreenPadMode> getOnScreenPadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyOnScreenPadMode) ?? 0;
    return (index >= 0 && index < OnScreenPadMode.values.length)
        ? OnScreenPadMode.values[index]
        : OnScreenPadMode.auto;
  }

  static Future<void> setOnScreenPadMode(OnScreenPadMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOnScreenPadMode, mode.index);
  }

  /// Which of the C64's two joystick ports the player's input drives.
  ///
  /// Port 2 is the default because it's what most commercial C64 games
  /// read, but plenty of titles use port 1 instead and there is no way to
  /// detect which from the outside -- you find out by starting the game and
  /// discovering nothing moves. Hence a user-visible setting, changeable
  /// mid-game from Quick Settings.
  static Future<int> getJoystickPort() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyJoystickPort) ?? 2;
    return (value == 1 || value == 2) ? value : 2;
  }

  static Future<void> setJoystickPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyJoystickPort, port == 1 ? 1 : 2);
  }

  /// Extra on-screen buttons the user has added, in the order they were
  /// added (which is the order they appear on screen).
  ///
  /// These are ADDITIONAL to the A/B fire buttons, which stay fire buttons.
  /// Each one sends a real C64 keyboard-matrix key via
  /// `vice_core_matrix_key_event`, so any key in [C64KeyCatalogue] can be
  /// assigned -- not just the seven ordinals `vice_core_key_event` knows.
  static Future<List<C64Key>> getCustomButtons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCustomButtons);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((entry) {
            final row = entry['row'];
            final column = entry['column'];
            if (row is! int || column is! int) return null;
            return C64KeyCatalogue.find(row, column) ??
                C64Key(entry['label'] as String? ?? '?', row, column);
          })
          .whereType<C64Key>()
          .toList();
    } catch (_) {
      // A corrupt list costs the user their extra buttons, not the app.
      return const [];
    }
  }

  static Future<void> setCustomButtons(List<C64Key> buttons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCustomButtons,
      jsonEncode([
        for (final b in buttons)
          {'label': b.label, 'row': b.row, 'column': b.column},
      ]),
    );
  }

  /// Assignable A/B action-button key mapping, port of
  /// MainActivity.makeAssignableVirtualButton's PREF_VIRTUAL_BUTTON_*_KEY:
  /// null means "joystick fire" (the button's default), a non-null value is
  /// a `vice_core_key_event` ordinal (0=Space, 1=Run/Stop, 2=Return,
  /// 3=F1, 4=F3, 5=F5, 6=F7 -- see vice_bridge.c's c64_matrix_key()).
  static Future<int?> getActionButtonKey(String button) async {
    final prefs = await SharedPreferences.getInstance();
    final key = button == 'a' ? _keyActionButtonAKey : _keyActionButtonBKey;
    final value = prefs.getInt(key) ?? _mappingDefault;
    return value == _mappingDefault ? null : value;
  }

  static Future<void> setActionButtonKey(String button, int? ordinal) async {
    final prefs = await SharedPreferences.getInstance();
    final key = button == 'a' ? _keyActionButtonAKey : _keyActionButtonBKey;
    await prefs.setInt(key, ordinal ?? _mappingDefault);
  }
}

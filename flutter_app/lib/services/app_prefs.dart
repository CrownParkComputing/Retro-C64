// Thin wrapper around shared_preferences for the handful of persisted
// settings the setup wizard needs: whether it's been completed once (so it
// only shows on first run, mirroring SetupWizardActivity's
// PREF_SETUP_COMPLETED), and the chosen app/games folder paths on the
// folder-scan platforms (PREF_APP_FOLDER_URI / PREF_GAMES_FOLDER_URI in the
// Android original -- here a plain filesystem path rather than a SAF URI,
// since file_picker hands back a real path on both Linux and Android).
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/c64_keys.dart';
import '../data/custom_button.dart';

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

/// Which directional control the on-screen pad draws. Both emit the same
/// digital 8-way output; this is purely which one your thumb prefers.
enum JoystickStyle {
  wobble('Wobble stick', 'Analog-style stick that springs back to centre'),
  dpad('D-pad buttons', 'Four-way cross; corners press two directions');

  final String label;
  final String description;
  const JoystickStyle(this.label, this.description);
}

/// Identifies the movable on-screen controls in [AppPrefs.getControlPositions].
/// Two clusters, not two widgets: the fire/custom buttons move together, the
/// way they are stacked together on screen.
const String kControlIdStick = 'stick';
const String kControlIdButtons = 'buttons';

class AppPrefs {
  AppPrefs._();

  static const _keySetupCompleted = 'setup_completed';

  /// A BASIC listing for the workbench to type in on the next boot, set when
  /// the wizard's "See it working" demo is chosen. CLEARED once taken: it is a
  /// one-shot instruction, not a setting, and a demo that replayed itself on
  /// every launch would be a bug rather than a feature.
  static const _keyDemoProgram = 'demo_program';
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
  static const _keyArtworkBaseUrl = 'artwork_base_url';
  static const _keyJoystickStyle = 'joystick_style';
  static const _keyWorkbenchMusic = 'workbench_music';
  static const _keyControlPositions = 'on_screen_control_positions';

  /// Sentinel stored in prefs for "use the joystick fire default" (no
  /// explicit key remap), mirroring Android's KEY_MAPPING_DEFAULT. Kept
  /// private -- callers see this as `null`.
  static const int _mappingDefault = -1;

  static Future<bool> isSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySetupCompleted) ?? false;
  }

  static Future<String?> takeDemoProgram() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyDemoProgram);
    if (value != null) await prefs.remove(_keyDemoProgram);
    return value;
  }

  static Future<void> setDemoProgram(String listing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDemoProgram, listing);
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
  /// assigned -- not just the seven ordinals `vice_core_key_event` knows --
  /// or a joystick direction, for games that want UP-to-jump under a thumb.
  /// Entries saved before directions existed still load (see
  /// CustomButton.fromJson).
  /// Where per-game artwork packs are served from, as `<base>/<slug>.zip`.
  ///
  /// Empty until a host is configured, which is not an error: the games grid
  /// simply keeps its format-label placeholders.
  static Future<String> getArtworkBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyArtworkBaseUrl) ?? '';
  }

  static Future<void> setArtworkBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyArtworkBaseUrl, url.trim());
  }

  /// Whether a SID tune plays while you are browsing the workbench.
  ///
  /// Defaults to ON: a C64 front end in silence is the wrong first
  /// impression, and the demo backdrop's equaliser has nothing to show
  /// without it. Music always stops when a game launches regardless -- the
  /// game's own audio wins -- so this only governs the workbench.
  static Future<bool> getWorkbenchMusic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWorkbenchMusic) ?? true;
  }

  static Future<void> setWorkbenchMusic(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWorkbenchMusic, value);
  }

  /// Which directional control the on-screen pad draws.
  static Future<JoystickStyle> getJoystickStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyJoystickStyle) ?? 0;
    return (index >= 0 && index < JoystickStyle.values.length)
        ? JoystickStyle.values[index]
        : JoystickStyle.wobble;
  }

  static Future<void> setJoystickStyle(JoystickStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyJoystickStyle, style.index);
  }

  /// Where the user has dragged each on-screen control, keyed by
  /// [kControlIdStick] / [kControlIdButtons].
  ///
  /// Stored as a FRACTION of the screen (0..1 from the top-left of the
  /// control), not pixels. The same setting has to survive rotation, the
  /// keyboard overlay appearing, and -- on iOS especially -- the identical
  /// build running on a phone and an iPad. A control parked 40px from the
  /// bottom of a phone in pixels lands mid-screen on a tablet; as a fraction
  /// it stays where it looks like it belongs.
  ///
  /// An absent entry means "never moved", which is deliberately different
  /// from a stored 0,0: the defaults follow the left-handed setting, and a
  /// control the user has never touched should keep doing that.
  static Future<Map<String, Offset>> getControlPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyControlPositions);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, Offset>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! List || value.length != 2) return;
        final dx = (value[0] as num).toDouble();
        final dy = (value[1] as num).toDouble();
        if (dx.isNaN || dy.isNaN) return;
        out[key] = Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
      });
      return out;
    } catch (_) {
      // A corrupt layout costs the user their custom positions, not the app:
      // returning empty puts every control back at its default corner.
      return const {};
    }
  }

  static Future<void> setControlPosition(String id, Offset fraction) async {
    final prefs = await SharedPreferences.getInstance();
    final current = Map<String, Offset>.from(await getControlPositions());
    current[id] = Offset(
      fraction.dx.clamp(0.0, 1.0),
      fraction.dy.clamp(0.0, 1.0),
    );
    await prefs.setString(
      _keyControlPositions,
      jsonEncode({
        for (final e in current.entries) e.key: [e.value.dx, e.value.dy],
      }),
    );
  }

  /// Puts every control back to its default corner.
  static Future<void> clearControlPositions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyControlPositions);
  }

  static Future<List<CustomButton>> getCustomButtons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCustomButtons);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CustomButton.fromJson)
          .whereType<CustomButton>()
          .toList();
    } catch (_) {
      // A corrupt list costs the user their extra buttons, not the app.
      return const [];
    }
  }

  static Future<void> setCustomButtons(List<CustomButton> buttons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCustomButtons,
      jsonEncode([for (final b in buttons) b.toJson()]),
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

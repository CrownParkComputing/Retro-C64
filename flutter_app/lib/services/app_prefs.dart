import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/data/custom_button.dart';

/// When the on-screen joypad is shown.
enum OnScreenPadMode {
  auto('Auto', 'Hidden while a controller is connected'),
  always('Always', 'Always shown, even with a controller'),
  never('Never', 'Never shown');

  final String label;
  final String description;
  const OnScreenPadMode(this.label, this.description);

  bool visibleWith({required bool controllerConnected}) => switch (this) {
        OnScreenPadMode.always => true,
        OnScreenPadMode.never => false,
        OnScreenPadMode.auto => !controllerConnected,
      };

  OnScreenPadMode get next =>
      OnScreenPadMode.values[(index + 1) % OnScreenPadMode.values.length];
}

/// Which directional control the on-screen pad draws.
enum JoystickStyle {
  wobble('Wobble stick', 'Analog-style stick that springs back to centre'),
  dpad('D-pad buttons', 'Four-way cross; corners press two directions');

  final String label;
  final String description;
  const JoystickStyle(this.label, this.description);
}

const String kControlIdStick = 'stick';
const String kControlIdButtons = 'buttons';

/// Interface for application preferences.
abstract class AppPrefs {
  Future<bool> isSetupCompleted();
  Future<void> setSetupCompleted(bool value);
  Future<bool> getDemoRomMode();
  Future<void> setDemoRomMode(bool value);
  Future<bool> setupCompletedFor(String version);
  Future<void> setSetupCompletedFor(String version);
  Future<String?> getAppFolderPath();
  Future<void> setAppFolderPath(String path);
  Future<String?> getGamesFolderPath();
  Future<void> setGamesFolderPath(String path);
  Future<bool> getLeftHandedInput();
  Future<void> setLeftHandedInput(bool value);
  Future<OnScreenPadMode> getOnScreenPadMode();
  Future<void> setOnScreenPadMode(OnScreenPadMode mode);
  Future<int> getJoystickPort();
  Future<void> setJoystickPort(int port);
  Future<String> getArtworkBaseUrl();
  Future<void> setArtworkBaseUrl(String url);
  Future<bool> getWorkbenchMusic();
  Future<void> setWorkbenchMusic(bool value);
  Future<JoystickStyle> getJoystickStyle();
  Future<void> setJoystickStyle(JoystickStyle style);
  Future<bool> getConfirmDelete();
  Future<void> setConfirmDelete(bool value);
  Future<Map<String, Offset>> getControlPositions();
  Future<void> setControlPosition(String id, Offset fraction);
  Future<void> clearControlPositions();
  Future<List<CustomButton>> getCustomButtons();
  Future<void> setCustomButtons(List<CustomButton> buttons);
  Future<int?> getActionButtonKey(String button);
  Future<void> setActionButtonKey(String button, int? ordinal);
}

/// Concrete implementation using [SharedPreferences].
class SharedPrefsImpl implements AppPrefs {
  static const _keySetupCompleted = 'setup_completed';
  static const _keyDemoRomMode = 'demo_rom_mode';
  static const _keySetupVersion = 'setup_completed_version';
  static const _keyAppFolderPath = 'app_folder_path';
  static const _keyGamesFolderPath = 'games_folder_path';
  static const _keyLeftHandedInput = 'left_handed_input';
  static const _keyActionButtonAKey = 'action_button_a_key';
  static const _keyActionButtonBKey = 'action_button_b_key';
  static const _keyOnScreenPadMode = 'on_screen_pad_mode';
  static const _keyJoystickPort = 'joystick_port';
  static const _keyCustomButtons = 'custom_on_screen_buttons';
  static const _keyArtworkBaseUrl = 'artwork_base_url';
  static const _keyJoystickStyle = 'joystick_style';
  static const _keyWorkbenchMusic = 'workbench_music';
  static const _keyControlPositions = 'on_screen_control_positions';
  static const _keyConfirmDelete = 'confirm_delete';

  static const int _mappingDefault = -1;

  final SharedPreferences _prefs;

  SharedPrefsImpl(this._prefs);

  @override
  Future<bool> isSetupCompleted() async => _prefs.getBool(_keySetupCompleted) ?? false;

  @override
  Future<void> setSetupCompleted(bool value) async => await _prefs.setBool(_keySetupCompleted, value);

  @override
  Future<bool> getDemoRomMode() async => _prefs.getBool(_keyDemoRomMode) ?? false;

  @override
  Future<void> setDemoRomMode(bool value) async => await _prefs.setBool(_keyDemoRomMode, value);

  @override
  Future<bool> setupCompletedFor(String version) async {
    if (!(_prefs.getBool(_keySetupCompleted) ?? false)) return false;
    final seen = _prefs.getString(_keySetupVersion);
    if (seen == null) {
      await _prefs.setString(_keySetupVersion, version);
      return true;
    }
    return seen == version;
  }

  @override
  Future<void> setSetupCompletedFor(String version) async {
    await _prefs.setBool(_keySetupCompleted, true);
    await _prefs.setString(_keySetupVersion, version);
  }

  @override
  Future<String?> getAppFolderPath() async => _prefs.getString(_keyAppFolderPath);

  @override
  Future<void> setAppFolderPath(String path) async => await _prefs.setString(_keyAppFolderPath, path);

  @override
  Future<String?> getGamesFolderPath() async => _prefs.getString(_keyGamesFolderPath);

  @override
  Future<void> setGamesFolderPath(String path) async => await _prefs.setString(_keyGamesFolderPath, path);

  @override
  Future<bool> getLeftHandedInput() async => _prefs.getBool(_keyLeftHandedInput) ?? false;

  @override
  Future<void> setLeftHandedInput(bool value) async => await _prefs.setBool(_keyLeftHandedInput, value);

  @override
  Future<OnScreenPadMode> getOnScreenPadMode() async {
    final index = _prefs.getInt(_keyOnScreenPadMode) ?? 0;
    return (index >= 0 && index < OnScreenPadMode.values.length)
        ? OnScreenPadMode.values[index]
        : OnScreenPadMode.auto;
  }

  @override
  Future<void> setOnScreenPadMode(OnScreenPadMode mode) async => await _prefs.setInt(_keyOnScreenPadMode, mode.index);

  @override
  Future<int> getJoystickPort() async {
    final value = _prefs.getInt(_keyJoystickPort) ?? 2;
    return (value == 1 || value == 2) ? value : 2;
  }

  @override
  Future<void> setJoystickPort(int port) async => await _prefs.setInt(_keyJoystickPort, port == 1 ? 1 : 2);

  @override
  Future<String> getArtworkBaseUrl() async => _prefs.getString(_keyArtworkBaseUrl) ?? '';

  @override
  Future<void> setArtworkBaseUrl(String url) async => await _prefs.setString(_keyArtworkBaseUrl, url.trim());

  @override
  Future<bool> getWorkbenchMusic() async => _prefs.getBool(_keyWorkbenchMusic) ?? true;

  @override
  Future<void> setWorkbenchMusic(bool value) async => await _prefs.setBool(_keyWorkbenchMusic, value);

  @override
  Future<JoystickStyle> getJoystickStyle() async {
    final index = _prefs.getInt(_keyJoystickStyle) ?? 0;
    return (index >= 0 && index < JoystickStyle.values.length)
        ? JoystickStyle.values[index]
        : JoystickStyle.wobble;
  }

  @override
  Future<void> setJoystickStyle(JoystickStyle style) async => await _prefs.setInt(_keyJoystickStyle, style.index);

  @override
  Future<bool> getConfirmDelete() async =>
      _prefs.getBool(_keyConfirmDelete) ?? true;

  @override
  Future<void> setConfirmDelete(bool value) async =>
      await _prefs.setBool(_keyConfirmDelete, value);

  @override
  Future<Map<String, Offset>> getControlPositions() async {
    final raw = _prefs.getString(_keyControlPositions);
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
      return const {};
    }
  }

  @override
  Future<void> setControlPosition(String id, Offset fraction) async {
    final current = Map<String, Offset>.from(await getControlPositions());
    current[id] = Offset(
      fraction.dx.clamp(0.0, 1.0),
      fraction.dy.clamp(0.0, 1.0),
    );
    await _prefs.setString(
      _keyControlPositions,
      jsonEncode({
        for (final e in current.entries) e.key: [e.value.dx, e.value.dy],
      }),
    );
  }

  @override
  Future<void> clearControlPositions() async => await _prefs.remove(_keyControlPositions);

  @override
  Future<List<CustomButton>> getCustomButtons() async {
    final raw = _prefs.getString(_keyCustomButtons);
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
      return const [];
    }
  }

  @override
  Future<void> setCustomButtons(List<CustomButton> buttons) async {
    await _prefs.setString(
      _keyCustomButtons,
      jsonEncode([for (final b in buttons) b.toJson()]),
    );
  }

  @override
  Future<int?> getActionButtonKey(String button) async {
    final key = button == 'a' ? _keyActionButtonAKey : _keyActionButtonBKey;
    final value = _prefs.getInt(key) ?? _mappingDefault;
    return value == _mappingDefault ? null : value;
  }

  @override
  Future<void> setActionButtonKey(String button, int? ordinal) async {
    final key = button == 'a' ? _keyActionButtonAKey : _keyActionButtonBKey;
    await _prefs.setInt(key, ordinal ?? _mappingDefault);
  }
}

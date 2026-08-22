// Shared, persisted video settings.
//
// One source of truth for both the Video settings tab and the in-game Quick
// Settings panel -- before this existed the panel's CRT and Bezel toggles
// were dead state: they flipped a bool on the emulator screen and changed
// the label, but nothing in the render path ever read them. Everything
// exposed here is applied for real by FramebufferView.
//
// Deliberately NOT here: VICE core resources such as the VIC-II border mode
// and the C64 palette. Those live inside the emulator core, and the plain-C
// bridge (native/vice_core/bridge/vice_bridge.h) exposes no resource
// setters at all -- there is no vice_core_set_* function to call. Adding
// them means new bridge entry points and a rebuild of the native libs for
// both Linux and Android, so they're left out of the UI rather than shipped
// as switches that do nothing.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the C64 picture is fitted into the window.
enum AspectMode {
  /// 4:3, the shape a real C64 monitor produced. Letterboxed as needed.
  authentic('4:3 authentic'),

  /// Fill the window's width at 16:9, cropping nothing but distorting the
  /// pixels horizontally.
  wide('16:9 fill'),

  /// Largest whole-number multiple of the emulator's own pixel grid that
  /// fits -- no resampling at all, so no shimmer on scrolling.
  integer('Integer scale'),

  /// Stretch to the whole window, ignoring aspect entirely.
  stretch('Stretch to fill');

  final String label;
  const AspectMode(this.label);
}

class VideoSettings extends ChangeNotifier {
  VideoSettings._();
  factory VideoSettings() => VideoSettings._();

  static const _keyCrt = 'video_crt';
  static const _keyBezel = 'video_bezel';
  static const _keyAspect = 'video_aspect_mode';
  static const _keySmooth = 'video_smooth_filter';
  static const _keyRotation = 'video_rotation_quarter_turns';
  static const _keyScanline = 'video_scanline_intensity';

  bool _crt = false;
  bool _bezel = false;
  AspectMode _aspect = AspectMode.authentic;
  bool _smooth = false;
  int _rotationQuarterTurns = 0;
  double _scanlineIntensity = 0.35;
  bool _loaded = false;

  bool get crt => _crt;
  bool get bezel => _bezel;
  AspectMode get aspect => _aspect;
  bool get smooth => _smooth;
  int get rotationQuarterTurns => _rotationQuarterTurns;

  /// 0..1, how dark the CRT scanlines are drawn. Only has an effect while
  /// [crt] is on.
  double get scanlineIntensity => _scanlineIntensity;

  /// Loads persisted values once. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _crt = prefs.getBool(_keyCrt) ?? false;
    _bezel = prefs.getBool(_keyBezel) ?? false;
    final aspectIndex = prefs.getInt(_keyAspect) ?? AspectMode.authentic.index;
    _aspect = AspectMode
        .values[aspectIndex.clamp(0, AspectMode.values.length - 1)];
    _smooth = prefs.getBool(_keySmooth) ?? false;
    _rotationQuarterTurns = (prefs.getInt(_keyRotation) ?? 0) % 4;
    _scanlineIntensity = prefs.getDouble(_keyScanline) ?? 0.35;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save(void Function(SharedPreferences p) write) async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    write(prefs);
  }

  void setCrt(bool value) {
    _crt = value;
    _save((p) => p.setBool(_keyCrt, value));
  }

  void setBezel(bool value) {
    _bezel = value;
    _save((p) => p.setBool(_keyBezel, value));
  }

  void setAspect(AspectMode mode) {
    _aspect = mode;
    _save((p) => p.setInt(_keyAspect, mode.index));
  }

  void setSmooth(bool value) {
    _smooth = value;
    _save((p) => p.setBool(_keySmooth, value));
  }

  void setRotationQuarterTurns(int turns) {
    _rotationQuarterTurns = turns % 4;
    _save((p) => p.setInt(_keyRotation, _rotationQuarterTurns));
  }

  void setScanlineIntensity(double value) {
    _scanlineIntensity = value.clamp(0.0, 1.0);
    _save((p) => p.setDouble(_keyScanline, _scanlineIntensity));
  }

  /// Drops every value back to its default and forgets that [load] ran, so
  /// each test starts from a clean singleton. Not used by the app.
  @visibleForTesting
  void resetForTests() {
    _crt = false;
    _bezel = false;
    _aspect = AspectMode.authentic;
    _smooth = false;
    _rotationQuarterTurns = 0;
    _scanlineIntensity = 0.35;
    _loaded = false;
  }

  /// Label used by the Quick Settings panel rows so the two UIs describe the
  /// same state in the same words.
  String get aspectLabel => _aspect.label;
}

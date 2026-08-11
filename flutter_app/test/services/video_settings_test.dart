// Video settings: defaults AND persistence.
//
// Persistence is asserted here because it was silently broken -- load() was
// written but nothing ever called it, so every setting reverted on restart
// while the setters kept dutifully writing values nobody read back.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/services/video_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = VideoSettings.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.resetForTests();
  });

  test('defaults are a plain 4:3 picture with no effects', () async {
    await settings.load();
    expect(settings.crt, isFalse);
    expect(settings.bezel, isFalse);
    expect(settings.smooth, isFalse);
    expect(settings.aspect, AspectMode.authentic);
    expect(settings.aspectLabel, AspectMode.authentic.label);
    expect(settings.rotationQuarterTurns, 0);
    expect(settings.scanlineIntensity, 0.35);
  });

  test('every setting survives a restart', () async {
    await settings.load();
    settings.setCrt(true);
    settings.setBezel(true);
    settings.setSmooth(true);
    settings.setAspect(AspectMode.integer);
    settings.setRotationQuarterTurns(3);
    settings.setScanlineIntensity(0.6);
    // Let the async writes land before pretending to restart.
    await Future<void>.delayed(Duration.zero);

    // A "restart": same persisted store, a settings object that has not
    // loaded yet. Without main() calling load(), this is where every value
    // used to snap back to its default.
    settings.resetForTests();
    expect(settings.crt, isFalse, reason: 'pre-load state is the default');
    await settings.load();

    expect(settings.crt, isTrue);
    expect(settings.bezel, isTrue);
    expect(settings.smooth, isTrue);
    expect(settings.aspect, AspectMode.integer);
    expect(settings.rotationQuarterTurns, 3);
    expect(settings.scanlineIntensity, closeTo(0.6, 1e-9));
  });

  test('load() is idempotent and does not clobber a later change', () async {
    await settings.load();
    settings.setCrt(true);
    await settings.load(); // e.g. a second screen calling it defensively
    expect(settings.crt, isTrue);
  });

  test('notifies listeners so the live picture updates', () async {
    await settings.load();
    var notifications = 0;
    void listener() => notifications++;
    settings.addListener(listener);
    addTearDown(() => settings.removeListener(listener));

    settings.setCrt(true);
    settings.setAspect(AspectMode.wide);
    expect(notifications, 2);
  });

  test('rotation wraps into quarter turns and intensity is clamped 0..1',
      () async {
    await settings.load();
    settings.setRotationQuarterTurns(4);
    expect(settings.rotationQuarterTurns, 0);
    settings.setRotationQuarterTurns(5);
    expect(settings.rotationQuarterTurns, 1);

    settings.setScanlineIntensity(2.5);
    expect(settings.scanlineIntensity, 1.0);
    settings.setScanlineIntensity(-1);
    expect(settings.scanlineIntensity, 0.0);
  });

  test('an out-of-range stored aspect index does not crash the app',
      () async {
    // Enum indexes are persisted, so a downgrade can meet a value this
    // build has no mode for.
    SharedPreferences.setMockInitialValues({'video_aspect_mode': 99});
    settings.resetForTests();
    await settings.load();
    expect(AspectMode.values, contains(settings.aspect));
  });

  test('every aspect mode has a label for the Quick Settings row', () {
    for (final mode in AspectMode.values) {
      expect(mode.label, isNotEmpty);
    }
  });
}

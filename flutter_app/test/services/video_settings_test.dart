// Video settings: defaults AND persistence.
//
// Persistence is asserted here because it was silently broken -- load() was
// written but nothing ever called it, so every setting reverted on restart
// while the setters kept dutifully writing values nobody read back.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_c64/services/service_locator.dart';
import 'package:get_it/get_it.dart';
import 'package:retro_c64/services/video_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    await setupServiceLocator();
  });

  test('defaults are a plain 4:3 picture with no effects', () async {
    await GetIt.instance<VideoSettings>().load();
    expect(GetIt.instance<VideoSettings>().crt, isFalse);
    expect(GetIt.instance<VideoSettings>().bezel, isFalse);
    expect(GetIt.instance<VideoSettings>().smooth, isFalse);
    expect(GetIt.instance<VideoSettings>().aspect, AspectMode.authentic);
    expect(GetIt.instance<VideoSettings>().aspectLabel, AspectMode.authentic.label);
    expect(GetIt.instance<VideoSettings>().rotationQuarterTurns, 0);
    expect(GetIt.instance<VideoSettings>().scanlineIntensity, 0.35);
  });

  test('every setting survives a restart', () async {
    await GetIt.instance<VideoSettings>().load();
    GetIt.instance<VideoSettings>().setCrt(true);
    GetIt.instance<VideoSettings>().setBezel(true);
    GetIt.instance<VideoSettings>().setSmooth(true);
    GetIt.instance<VideoSettings>().setAspect(AspectMode.integer);
    GetIt.instance<VideoSettings>().setRotationQuarterTurns(3);
    GetIt.instance<VideoSettings>().setScanlineIntensity(0.6);
    // Let the async writes land before pretending to restart.
    await Future<void>.delayed(Duration.zero);

    // A "restart": same persisted store, a settings object that has not
    // loaded yet. Without main() calling load(), this is where every value
    // used to snap back to its default.
    GetIt.instance<VideoSettings>().resetForTests();
    expect(GetIt.instance<VideoSettings>().crt, isFalse, reason: 'pre-load state is the default');
    await GetIt.instance<VideoSettings>().load();

    expect(GetIt.instance<VideoSettings>().crt, isTrue);
    expect(GetIt.instance<VideoSettings>().bezel, isTrue);
    expect(GetIt.instance<VideoSettings>().smooth, isTrue);
    expect(GetIt.instance<VideoSettings>().aspect, AspectMode.integer);
    expect(GetIt.instance<VideoSettings>().rotationQuarterTurns, 3);
    expect(GetIt.instance<VideoSettings>().scanlineIntensity, closeTo(0.6, 1e-9));
  });

  test('load() is idempotent and does not clobber a later change', () async {
    await GetIt.instance<VideoSettings>().load();
    GetIt.instance<VideoSettings>().setCrt(true);
    await GetIt.instance<VideoSettings>().load(); // e.g. a second screen calling it defensively
    expect(GetIt.instance<VideoSettings>().crt, isTrue);
  });

  test('notifies listeners so the live picture updates', () async {
    await GetIt.instance<VideoSettings>().load();
    var notifications = 0;
    void listener() => notifications++;
    GetIt.instance<VideoSettings>().addListener(listener);
    addTearDown(() => GetIt.instance<VideoSettings>().removeListener(listener));

    GetIt.instance<VideoSettings>().setCrt(true);
    GetIt.instance<VideoSettings>().setAspect(AspectMode.wide);
    expect(notifications, 2);
  });

  test('rotation wraps into quarter turns and intensity is clamped 0..1',
      () async {
    await GetIt.instance<VideoSettings>().load();
    GetIt.instance<VideoSettings>().setRotationQuarterTurns(4);
    expect(GetIt.instance<VideoSettings>().rotationQuarterTurns, 0);
    GetIt.instance<VideoSettings>().setRotationQuarterTurns(5);
    expect(GetIt.instance<VideoSettings>().rotationQuarterTurns, 1);

    GetIt.instance<VideoSettings>().setScanlineIntensity(2.5);
    expect(GetIt.instance<VideoSettings>().scanlineIntensity, 1.0);
    GetIt.instance<VideoSettings>().setScanlineIntensity(-1);
    expect(GetIt.instance<VideoSettings>().scanlineIntensity, 0.0);
  });

  test('an out-of-range stored aspect index does not crash the app',
      () async {
    // Enum indexes are persisted, so a downgrade can meet a value this
    // build has no mode for.
    SharedPreferences.setMockInitialValues({'video_aspect_mode': 99});
    GetIt.instance<VideoSettings>().resetForTests();
    await GetIt.instance<VideoSettings>().load();
    expect(AspectMode.values, contains(GetIt.instance<VideoSettings>().aspect));
  });

  test('every aspect mode has a label for the Quick Settings row', () {
    for (final mode in AspectMode.values) {
      expect(mode.label, isNotEmpty);
    }
  });
}

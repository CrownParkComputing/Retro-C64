// The workbench screensaver's scroller. It shipped with a hardcoded "VICE
// ANDROID" that survived the rename and was still claiming Android on a
// Linux desktop, and it reports live state (what's loaded, how many titles,
// FPS) that must not be able to lie.
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/view_models/workbench_view_model.dart';
import 'package:retro_c64/services/platform_info.dart';

void main() {
  test('names the running platform rather than a baked-in one', () {
    final text = buildBackdropInfoText(
        platform: 'Linux', loadedMediaName: '', libraryCount: 0);
    expect(text, startsWith('VICE ON LINUX'));
    expect(text, isNot(contains('ANDROID')));

    expect(
      buildBackdropInfoText(
          platform: 'Android', loadedMediaName: '', libraryCount: 0),
      startsWith('VICE ON ANDROID'),
    );
  });

  test('is fed by platformName(), not a literal', () {
    expect(
      buildBackdropInfoText(
          platform: platformName(), loadedMediaName: '', libraryCount: 3),
      contains('VICE ON ${platformName().toUpperCase()}'),
    );
  });

  test('says NO MEDIA LOADED when nothing is loaded', () {
    final text = buildBackdropInfoText(
        platform: 'Linux', loadedMediaName: '', libraryCount: 12);
    expect(text, contains('NO MEDIA LOADED'));
    expect(text, isNot(contains('*   LOADED ')));
    expect(text, contains('12 TITLES IN LIBRARY'));
  });

  test('names the loaded title once one is running', () {
    final text = buildBackdropInfoText(
        platform: 'Linux',
        loadedMediaName: 'Boulder Dash.d64',
        libraryCount: 12,
        fps: 50);
    expect(text, contains('LOADED BOULDER DASH.D64'));
    expect(text, isNot(contains('NO MEDIA LOADED')));
    expect(text, contains('50 FPS'));
  });

  test('omits FPS entirely when the core is not producing frames', () {
    // "0 FPS" on the backdrop reads as a fault rather than as "not running".
    final text = buildBackdropInfoText(
        platform: 'Linux', loadedMediaName: '', libraryCount: 0, fps: 0);
    expect(text, isNot(contains('FPS')));
  });
}

// The picture itself: that a frame from the core reaches the screen, and
// that the video settings shared with the Video tab really are applied to
// the render path (they were once local booleans that only relabelled a
// Quick Settings row).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/services/video_settings.dart';
import 'package:vice_multiplatform/widgets/framebuffer_view.dart';

import '../fakes/fake_vice_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VideoSettings.instance.resetForTests();
  });

  /// Pumps the view and gives the core's frame time to decode.
  Future<void> pumpFrames(WidgetTester tester, FakeViceCore core) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 480,
          child: FramebufferView(
            core: core,
            pollInterval: const Duration(milliseconds: 16),
          ),
        ),
      ),
    ));
    // One poll tick, then a real-time slice for decodeImageFromPixels'
    // callback, then a frame to paint the result.
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('says so, rather than showing nothing, before the first frame',
      (tester) async {
    // A core that has not drawn yet is the normal state for the first
    // moments of every launch.
    await pumpFrames(tester, FakeViceCore(withFrame: false));
    expect(find.text('Waiting for first frame...'), findsOneWidget);
  });

  testWidgets('paints the frame once the core produces one', (tester) async {
    await pumpFrames(tester, FakeViceCore(withFrame: true));
    expect(find.text('Waiting for first frame...'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('the aspect setting reaches the render path', (tester) async {
    await VideoSettings.instance.load();
    await pumpFrames(tester, FakeViceCore(withFrame: true));

    // Default: 4:3, the shape a real C64 monitor produced.
    AspectRatio ratio() => tester.widget<AspectRatio>(find
        .descendant(of: find.byType(FramebufferView), matching: find.byType(AspectRatio))
        .first);
    expect(ratio().aspectRatio, closeTo(4 / 3, 1e-9));

    VideoSettings.instance.setAspect(AspectMode.wide);
    await tester.pump();
    expect(ratio().aspectRatio, closeTo(16 / 9, 1e-9));

    // Stretch drops the AspectRatio box entirely.
    VideoSettings.instance.setAspect(AspectMode.stretch);
    await tester.pump();
    expect(
      find.descendant(
          of: find.byType(FramebufferView), matching: find.byType(AspectRatio)),
      findsNothing,
    );
  });

  testWidgets('rotation is applied to the picture', (tester) async {
    await VideoSettings.instance.load();
    await pumpFrames(tester, FakeViceCore(withFrame: true));
    expect(find.byType(RotatedBox), findsNothing);

    VideoSettings.instance.setRotationQuarterTurns(1);
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
  });
}

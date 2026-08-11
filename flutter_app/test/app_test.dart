// Root-widget smoke test.
//
// The app is a Flutter shell over a native core, and whether that core is
// present depends on the machine: a developer checkout has one built under
// native/, a CI runner and a fresh Linux bundle do not. Either way the
// shell must come up and land on one of its three legitimate states rather
// than throwing -- including the "no libvicecore" state, where saying so is
// a diagnosis and a blank window is not.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vice_multiplatform/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('builds and settles into a real state, core or no core',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ViceMultiplatformApp());
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull);

    final failedToLoad = find.textContaining('Failed to load libvicecore');
    final stillLoading = find.byType(CircularProgressIndicator);
    // With setup never completed, a core that DID load lands on the wizard.
    final wizard = find.textContaining('Next');
    expect(
      failedToLoad.evaluate().isNotEmpty ||
          stillLoading.evaluate().isNotEmpty ||
          wizard.evaluate().isNotEmpty,
      isTrue,
      reason: 'the app must reach the error, loading or setup screen',
    );

    // Unmount cleanly: the app registers a lifecycle observer and the
    // wizard animates on a timer.
    await tester.pumpWidget(const SizedBox());
  });
}

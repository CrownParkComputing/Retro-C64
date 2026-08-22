// The rail must show every destination at once, on the shortest screen the
// app runs on.
//
// This exists because it failed in exactly that way: the rail scrolled when
// it ran out of room, the Compliance entry ended up below the fold on a
// Retroid Flip2, and the page was reported as "not on the device" when it
// was there all along. An entry you cannot see is an entry that does not
// exist.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_c64/data/category.dart';
import 'package:retro_c64/widgets/sidebar.dart';
import 'package:retro_c64/widgets/sidebar_style.dart';

void main() {
  // The Flip2 in landscape, which is the short one.
  const shortLandscape = Size(853, 456);

  testWidgets('every destination is visible without scrolling',
      (tester) async {
    tester.view.physicalSize = shortLandscape;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Sidebar(
              destinations: [
                for (final c in WorkbenchCategory.values)
                  SidebarDestination(c.title, icon: c.icon, group: c.group),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
              style: viceSidebarStyle,
              pinLastGroupToBottom: true,
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    for (final c in WorkbenchCategory.values) {
      final finder = find.text(c.title);
      expect(finder, findsOneWidget, reason: '${c.title} is missing entirely');

      // Present in the tree is not the same as on the screen: a scrolled-away
      // row still exists. Check it is inside the window.
      final box = tester.getRect(finder);
      expect(box.top, greaterThanOrEqualTo(0.0),
          reason: '${c.title} is off the top of the rail');
      expect(box.bottom, lessThanOrEqualTo(shortLandscape.height),
          reason: '${c.title} is below the fold -- the rail scrolled again');
    }
  });
}

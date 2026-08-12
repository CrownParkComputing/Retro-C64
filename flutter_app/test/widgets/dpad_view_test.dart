// The D-pad's whole reason to exist is that it does diagonals. Four
// independent buttons would report one direction per touch, which loses the
// forward-jump that most of the C64 library needs, so these tests pin the
// corner and slide behaviour rather than just "a tap sends left".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vice_multiplatform/widgets/dpad_view.dart';

void main() {
  const size = 140.0;
  const centre = Offset(size / 2, size / 2);

  late List<List<bool>> events;

  Future<void> pumpPad(WidgetTester tester) async {
    events = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DpadView(
              size: size,
              onDirections: (u, d, l, r) => events.add([u, d, l, r]),
            ),
          ),
        ),
      ),
    );
  }

  /// Local offset within the pad -> a global one the gesture layer can use.
  Offset at(WidgetTester tester, Offset local) =>
      tester.getTopLeft(find.byType(DpadView)) + local;

  testWidgets('pressing an arm sends exactly that direction', (tester) async {
    await pumpPad(tester);

    final g = await tester.startGesture(at(tester, const Offset(size / 2, 8)));
    await tester.pump();

    expect(events.last, [true, false, false, false]); // up only
    await g.up();
  });

  testWidgets('a corner presses two directions at once', (tester) async {
    await pumpPad(tester);

    // Up-and-right: the diagonal a platformer needs to jump forward.
    final g = await tester.startGesture(at(tester, const Offset(size - 12, 12)));
    await tester.pump();

    expect(events.last, [true, false, false, true]);
    await g.up();
  });

  testWidgets('the centre is a dead zone', (tester) async {
    await pumpPad(tester);

    final g = await tester.startGesture(at(tester, centre));
    await tester.pump();

    // Nothing was ever emitted: neutral in, neutral out.
    expect(events, isEmpty);
    await g.up();
  });

  testWidgets('sliding from one arm to the next changes direction without '
      'lifting off', (tester) async {
    await pumpPad(tester);

    final g = await tester.startGesture(at(tester, const Offset(8, size / 2)));
    await tester.pump();
    expect(events.last, [false, false, true, false]); // left

    await g.moveTo(at(tester, const Offset(size - 8, size / 2)));
    await tester.pump();
    expect(events.last, [false, false, false, true]); // right

    await g.up();
  });

  testWidgets('releasing returns to neutral', (tester) async {
    await pumpPad(tester);

    final g = await tester.startGesture(at(tester, const Offset(size / 2, 8)));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(events.last, [false, false, false, false]);
  });

  testWidgets('a second finger does not cancel the first', (tester) async {
    await pumpPad(tester);

    // Thumb holds right; a second finger taps down. Both must be live -- this
    // is the case a single-pointer implementation gets wrong.
    final thumb = await tester.startGesture(
        at(tester, const Offset(size - 8, size / 2)),
        pointer: 1);
    await tester.pump();
    final finger = await tester.startGesture(
        at(tester, const Offset(size / 2, size - 8)),
        pointer: 2);
    await tester.pump();

    expect(events.last, [false, true, false, true]); // down + right

    await finger.up();
    await tester.pump();
    expect(events.last, [false, false, false, true]); // right survives

    await thumb.up();
  });

  testWidgets('being disposed mid-press releases the direction',
      (tester) async {
    await pumpPad(tester);

    await tester.startGesture(at(tester, const Offset(8, size / 2)));
    await tester.pump();
    expect(events.last, [false, false, true, false]);

    // Hiding the controls (or leaving the game) while a direction is held
    // would otherwise leave the bit latched and the character walking into
    // a wall forever.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(events.last, [false, false, false, false]);
    // Deliberately no g.up(): the finger is still down in real life, and
    // that is the point -- the release has to come from dispose(), not from
    // a pointer event the vanished widget will never receive.
  });
}

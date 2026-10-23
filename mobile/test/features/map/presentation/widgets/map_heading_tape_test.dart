import 'package:blueway/features/map/presentation/widgets/map_heading_tape.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cap affiché sur trois chiffres, 360 revient à 000', () {
    expect(MapHeadingTape.readout(161.4), '161');
    expect(MapHeadingTape.readout(5), '005');
    expect(MapHeadingTape.readout(359.6), '000');
    expect(MapHeadingTape.readout(null), '---');
  });

  test('lettres sur les multiples de 45°, chiffres sinon', () {
    expect(MapHeadingTape.label(0), 'N');
    expect(MapHeadingTape.label(135), 'SE');
    expect(MapHeadingTape.label(315), 'NW');
    expect(MapHeadingTape.label(360), 'N');
    expect(MapHeadingTape.label(-15), '345');
    expect(MapHeadingTape.label(195), '195');
  });

  testWidgets('position GPS centrée sous le cap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: MapHeadingTape(
              heading: 161,
              position: '43°26′48″N   006°47′16″E',
            ),
          ),
        ),
      ),
    );
    expect(find.text('161'), findsOneWidget);
    final readout = tester.getCenter(find.text('161'));
    final position = tester.getCenter(find.byKey(MapHeadingTape.positionKey));
    expect(position.dx, closeTo(readout.dx, 0.5));
    expect(position.dy, greaterThan(readout.dy));
    expect(
      tester.getSize(find.byType(MapHeadingTape)).width,
      MapHeadingTape.maxWidth,
    );
  });

  testWidgets('le cap glisse vers la mesure suivante en passant par le nord', (
    tester,
  ) async {
    Widget tape(double heading) => MaterialApp(
      home: MapHeadingTape(heading: heading, position: ''),
    );
    await tester.pumpWidget(tape(355));
    await tester.pumpWidget(tape(365));
    await tester.pump(MapHeadingTape.glide ~/ 2);
    final shown = int.parse(
      tester.widget<Text>(find.textContaining(RegExp(r'^\d{3}$'))).data!,
    );
    expect(shown == 0 || shown > 355 || shown < 5, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('005'), findsOneWidget);
  });
}

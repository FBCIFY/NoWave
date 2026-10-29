import 'package:blueway/features/auth/presentation/widgets/flow_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget screen(int step) => MaterialApp(
    home: FlowTransition(
      step: step,
      child: ColoredBox(
        key: ValueKey('screen-$step'),
        color: step == 0 ? Colors.blue : Colors.green,
      ),
    ),
  );

  testWidgets('the next screen enters right and the old screen exits left', (
    tester,
  ) async {
    await tester.pumpWidget(screen(0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(screen(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final oldX = tester.getTopLeft(find.byKey(const ValueKey('screen-0'))).dx;
    final newX = tester.getTopLeft(find.byKey(const ValueKey('screen-1'))).dx;

    expect(oldX, lessThan(0));
    expect(newX, greaterThan(0));
  });

  testWidgets('going back reverses the direction', (tester) async {
    await tester.pumpWidget(screen(1));
    await tester.pumpAndSettle();

    await tester.pumpWidget(screen(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final oldX = tester.getTopLeft(find.byKey(const ValueKey('screen-1'))).dx;
    final newX = tester.getTopLeft(find.byKey(const ValueKey('screen-0'))).dx;

    expect(oldX, greaterThan(0));
    expect(newX, lessThan(0));
  });
}

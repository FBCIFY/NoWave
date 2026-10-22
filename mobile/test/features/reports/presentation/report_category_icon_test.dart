import 'dart:ui' as ui;

import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/presentation/report_category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('suit la taille de l’IconTheme, sauf taille donnée', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IconTheme(
          data: IconThemeData(size: 30),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReportCategoryIcon(
                ReportCategory.marineAnimal,
                key: ValueKey('theme'),
              ),
              ReportCategoryIcon(
                ReportCategory.pollution,
                key: ValueKey('given'),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('theme'))),
      const Size.square(30),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('given'))),
      const Size.square(18),
    );
  });

  test('dauphin : corps plein, coins vides, œil découpé', () async {
    const side = 96;
    final recorder = ui.PictureRecorder();
    ReportCategory.marineAnimal.paintIcon(
      Canvas(recorder),
      const Offset(side / 2, side / 2),
      side.toDouble(),
      Colors.white,
    );
    final image = await recorder.endRecording().toImage(side, side);
    final bytes = (await image.toByteData())!;
    image.dispose();
    int alpha(int x, int y) => bytes.getUint8((y * side + x) * 4 + 3);

    expect(alpha(side ~/ 2, side ~/ 2), 255);
    expect(alpha(1, 1), 0);
    expect(alpha(side - 2, side - 2), 0);
    // Œil : des pixels vides qu'on n'atteint pas depuis le bord.
    final outside = <int>{};
    final queue = <int>[
      for (var i = 0; i < side; i++) ...[i, side * (side - 1) + i],
    ];
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      if (alpha(i % side, i ~/ side) != 0 || !outside.add(i)) continue;
      final x = i % side, y = i ~/ side;
      if (x > 0) queue.add(i - 1);
      if (x < side - 1) queue.add(i + 1);
      if (y > 0) queue.add(i - side);
      if (y < side - 1) queue.add(i + side);
    }
    final eyeHole = [for (var i = 0; i < side * side; i++) i]
        .any((i) => alpha(i % side, i ~/ side) == 0 && !outside.contains(i));
    expect(eyeHole, true);
  });
}

import 'dart:ui' as ui;

import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dessine le badge en PNG, ombre comprise', (tester) async {
    final png = await tester.runAsync(
      () => ReportMarker.paint(icon: Icons.pets_outlined, color: Colors.cyan),
    );

    final codec = await tester.runAsync(() => ui.instantiateImageCodec(png!));
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
    expect(frame!.image.width, side);
    expect(frame.image.height, side);
    frame.image.dispose();
  });
}

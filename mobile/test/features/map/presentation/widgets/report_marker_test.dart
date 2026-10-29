import 'package:blueway/features/map/presentation/widgets/report_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('se soulève sans déplacer la boîte qui sert aux coordonnées', (
    tester,
  ) async {
    Future<void> pumpMarker({required bool lifted}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: ReportMarker(lifted: lifted)),
        ),
      );
      await tester.pumpAndSettle();
    }

    double groundShadowOpacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    await pumpMarker(lifted: false);
    final box = tester.getRect(find.byType(ReportMarker));
    final icon = tester.getRect(find.byIcon(Icons.place));
    expect(icon, box);
    expect(groundShadowOpacity(), 0);

    await pumpMarker(lifted: true);
    expect(tester.getRect(find.byType(ReportMarker)), box);
    expect(
      tester.getRect(find.byIcon(Icons.place)),
      icon.shift(const Offset(0, -11)),
    );
    expect(groundShadowOpacity(), 1);

    await pumpMarker(lifted: false);
    expect(tester.getRect(find.byIcon(Icons.place)), icon);
  });
}

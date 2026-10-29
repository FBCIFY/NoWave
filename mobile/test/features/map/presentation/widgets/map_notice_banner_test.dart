import 'package:blueway/features/map/presentation/widgets/map_notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester,
    MapNotice notice, {
    VoidCallback? onDismiss,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapNoticeBanner(notice: notice, onDismiss: onDismiss ?? () {}),
        ),
      ),
    );
  }

  testWidgets('affiche le message avec l’icône de son type', (tester) async {
    await pumpBanner(
      tester,
      const MapNotice('Signalement publié.', MapNoticeKind.success),
    );
    expect(find.text('Signalement publié.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await pumpBanner(
      tester,
      const MapNotice('Signalement publié sans photo.', MapNoticeKind.warning),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await pumpBanner(
      tester,
      const MapNotice('Cap du téléphone indisponible.', MapNoticeKind.error),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('se ferme à l’appui', (tester) async {
    var dismissals = 0;
    await pumpBanner(
      tester,
      const MapNotice('Signalement publié.', MapNoticeKind.success),
      onDismiss: () => dismissals++,
    );

    await tester.tap(find.text('Signalement publié.'));
    expect(dismissals, 1);
  });

  testWidgets('est annoncé par le lecteur d’écran', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBanner(
      tester,
      const MapNotice('Signalement publié.', MapNoticeKind.success),
    );

    expect(
      tester.getSemantics(find.byType(MapNoticeBanner)),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });
}

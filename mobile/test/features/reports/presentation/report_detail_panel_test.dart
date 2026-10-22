import 'dart:async';

import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _photo = img.encodePng(img.Image(width: 40, height: 30));
final _report = ReportDetail(
  id: 'photo-report',
  category: ReportCategory.pollution,
  description: List.filled(12, 'Nappe visible près du port.').join(' '),
  latitude: 43.29,
  longitude: 5.37,
  observedAt: DateTime(2026, 10, 22, 10),
  expiresAt: DateTime(2026, 10, 22, 18),
  author: const ReportAuthor(username: 'Brice', deleted: false),
  boat: null,
  photo: const ReportPhoto(
    status: ReportPhotoStatus.uploaded,
    url: 'https://photo.test/a',
  ),
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    var closed = 0;
    var mapTaps = 0;
    var dismiss = false;
    late StateSetter update;

    Future<void> mount(
      WidgetTester tester, {
      Future<ReportDetail>? loading,
      ReportDetail? report,
      bool reduceMotion = false,
      bool settle = true,
    }) async {
      closed = 0;
      mapTaps = 0;
      dismiss = false;
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(430, 932),
                padding: const EdgeInsets.only(top: 44, bottom: 24),
                disableAnimations: reduceMotion,
              ),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => mapTaps++,
                          child: const ColoredBox(color: Colors.blue),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ReportDetailPanel(
                          reportId: 'photo-report',
                          dismissRequested: dismiss,
                          loadReport: (_) =>
                              loading ?? Future.value(report ?? _report),
                          loadPhoto: (_) async => _photo,
                          onClose: () => closed++,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (!settle) return;
      if (loading == null) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    final surface = find.byKey(const ValueKey('map-panel-surface'));
    Offset contentStart(WidgetTester tester) =>
        Offset(210, tester.getTopLeft(surface).dy + 180);

    testWidgets('$platform : la hauteur provisoire n’est jamais affichée', (
      tester,
    ) async {
      final loading = Completer<ReportDetail>();
      await mount(tester, loading: loading.future, settle: false);
      final opacity = find
          .ancestor(of: surface, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      expect(surface.hitTestable(), findsNothing);
      await tester.pump();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(tester.getSize(surface).height, lessThan(300));
      loading.complete(_report);
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(closed, 0);
    });

    for (final hasPhoto in [false, true]) {
      testWidgets(
        '$platform : ${hasPhoto ? 'photo' : 'manuel'} sans blanc après le contenu',
        (tester) async {
          final shortReport = ReportDetail(
            id: _report.id,
            category: _report.category,
            description: 'Nappe près du port.',
            latitude: _report.latitude,
            longitude: _report.longitude,
            observedAt: _report.observedAt,
            expiresAt: _report.expiresAt,
            author: _report.author,
            boat: null,
            photo: hasPhoto ? _report.photo : null,
          );
          await mount(tester, report: shortReport);
          final content = find.descendant(
            of: find.byType(ReportDetailSheet),
            matching: find.byType(SizeChangedLayoutNotifier),
          );
          final naturalHeight =
              tester.getSize(content).height +
              32 +
              (platform == TargetPlatform.android ? 24 : 0);
          if (!hasPhoto) {
            expect(tester.getSize(surface).height, closeTo(naturalHeight, 1));
            expect(naturalHeight, lessThan(400));
          }
          // Même en insistant vers le haut, le panneau s'arrête à son contenu.
          await tester.dragFrom(contentStart(tester), const Offset(0, -600));
          await tester.pumpAndSettle();
          expect(tester.getSize(surface).height, closeTo(naturalHeight, 1));
          final scroll = tester
              .widget<ReportDetailSheet>(find.byType(ReportDetailSheet))
              .scrollController!;
          expect(scroll.position.maxScrollExtent, closeTo(0, 1));
          await tester.dragFrom(contentStart(tester), const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.getSize(surface).height, closeTo(naturalHeight, 1));
          expect(scroll.offset, closeTo(0, 1));
          expect(closed, 0);
          await tester.dragFrom(contentStart(tester), const Offset(0, 720));
          await tester.pumpAndSettle();
          expect(closed, 1);
        },
      );
    }

    testWidgets(
      '$platform : le contenu agrandit la fiche avec photo puis défile',
      (tester) async {
        await mount(tester);
        final initialHeight = tester.getSize(surface).height;
        expect(
          tester.getSize(find.byType(ReportDetailPanel)).height,
          closeTo(initialHeight + (platform == TargetPlatform.iOS ? 24 : 0), 1),
        );
        // La boîte visible du panneau ne masque pas les interactions de la carte.
        await tester.tapAt(const Offset(210, 100));
        expect(mapTaps, 1);
        final gesture = await tester.startGesture(contentStart(tester));
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -160));
        await tester.pump();
        expect(
          tester.getSize(surface).height,
          greaterThan(initialHeight + 100),
        );
        final sheet = tester.widget<ReportDetailSheet>(
          find.byType(ReportDetailSheet),
        );
        expect(sheet.scrollController!.offset, 0);
        await gesture.moveBy(const Offset(0, -400));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getSize(surface).height, greaterThan(750));
        await tester.dragFrom(const Offset(210, 550), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(sheet.scrollController!.offset, greaterThan(60));
        await tester.dragFrom(const Offset(210, 550), const Offset(0, 40));
        await tester.pumpAndSettle();
        expect(tester.getSize(surface).height, greaterThan(750));
        expect(closed, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$platform : un petit glissement revient en place, un grand ferme',
      (tester) async {
        await mount(tester);
        final initialHeight = tester.getSize(surface).height;
        final gesture = await tester.startGesture(contentStart(tester));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 24));
        await tester.pump(const Duration(milliseconds: 500));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getSize(surface).height, closeTo(initialHeight, 1));
        expect(closed, 0);
        await tester.dragFrom(contentStart(tester), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(closed, 1);
      },
    );

    testWidgets('$platform : la poignée agrandit et referme aussi le panneau', (
      tester,
    ) async {
      await mount(tester);
      final initialHeight = tester.getSize(surface).height;
      final handle = find.byKey(const ValueKey('map-panel-drag-handle'));
      await tester.drag(handle, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(tester.getSize(surface).height, greaterThan(initialHeight + 200));
      await tester.drag(handle, const Offset(0, 720));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets(
      '$platform : la carte ferme en douceur même une fiche agrandie',
      (tester) async {
        await mount(tester);
        await tester.dragFrom(contentStart(tester), const Offset(0, -360));
        await tester.pumpAndSettle();
        update(() => dismiss = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(closed, 0);
        expect(find.byType(ReportDetailSheet), findsOneWidget);
        await tester.pumpAndSettle();
        expect(closed, 1);
      },
    );

    testWidgets(
      '$platform : fermeture possible pendant le chargement, animations réduites',
      (tester) async {
        final loading = Completer<ReportDetail>();
        await mount(tester, loading: loading.future, reduceMotion: true);
        await tester.dragFrom(
          Offset(210, tester.getTopLeft(surface).dy + 80),
          const Offset(0, 400),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(closed, 1);
        loading.complete(_report);
        await tester.pumpAndSettle();
        expect(closed, 1);
      },
    );
  }
}

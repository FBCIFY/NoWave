import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blueway/features/map/presentation/report_marker.dart' as badges;
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:image/image.dart' as img;

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/home/presentation/home_screen.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:geolocator/geolocator.dart' as geo;

import '../../map/support/focus_fakes.dart';
import '../support/alert_fixtures.dart';

class _Reports extends Fake implements ReportDetailService {
  final calls = <String>[];
  final photoCalls = <String>[];
  @override
  Future<Uint8List> fetchPhoto(String url) async {
    photoCalls.add(url);
    return img.encodePng(img.Image(width: 2, height: 2));
  }

  Future<ReportDetail> Function(String)? load;
  @override
  Future<ReportDetail> fetchReport(String id) {
    calls.add(id);
    return load?.call(id) ??
        Future.value(focusReport(id: id, longitude: 6, latitude: 44));
  }
}

class _UnavailableGps extends geo.GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

void focusTestWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(
    description,
    body,
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}

void main() {
  late geo.GeolocatorPlatform previousGps;
  late FakeAlertPushSource source;
  late AlertPushController push;
  late _Reports reports;
  late FocusMap map;
  setUp(() {
    previousGps = geo.GeolocatorPlatform.instance;
    geo.GeolocatorPlatform.instance = _UnavailableGps();
    source = FakeAlertPushSource();
    push = AlertPushController(source: source, now: () => testNow);
    reports = _Reports();
    map = FocusMap();
  });
  tearDown(() async {
    geo.GeolocatorPlatform.instance = previousGps;
    push.dispose();
    await source.close();
  });

  MapFocusController selection(WidgetTester tester) =>
      tester.widget<MapScreen>(find.byType(MapScreen)).focusController!;

  Future<void> mount(WidgetTester tester) async {
    await prepareFocusMarkers(tester);
    push.setSession('user-a');
    push.setReady(true);
    await push.start();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(pushController: push, reportDetailService: reports),
      ),
    );
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onMapCreated!(map);
    tester
        .widget<mb.MapWidget>(find.byType(mb.MapWidget))
        .onStyleLoadedListener!(
      mb.StyleLoadedEventData.fromJson({
        'timeInterval': {'begin': 0, 'end': 1},
      }),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  for (final photo in [false, true]) {
    for (final category in ReportCategory.values) {
      for (final delivery in ['foreground', 'background', 'terminated']) {
        focusTestWidgets(
          'NW-210 ${photo ? 'photo' : 'manuel'} ${category.apiValue} $delivery : carte directe et fiche au tap',
          (tester) async {
            final apiClient = MockClient((request) async {
              expectSync(request.method, 'GET');
              expectSync(request.headers['authorization'], 'Bearer test-token');
              final id = request.url.pathSegments.last;
              return http.Response(
                jsonEncode({
                  'id': id,
                  'category': category.apiValue,
                  'description': 'Backend position',
                  'positioning_mode': photo ? 'photo' : 'manual',
                  'final_position': {
                    'type': 'Point',
                    'coordinates': [6.0, 44.0],
                  },
                  'observed_at': DateTime.now().toUtc().toIso8601String(),
                  'expires_at': DateTime.now()
                      .add(const Duration(hours: 1))
                      .toUtc()
                      .toIso8601String(),
                  'author': null,
                  'boat': null,
                  'photo': photo
                      ? {
                          'status': 'uploaded',
                          'url': 'https://storage.test/$id.png',
                        }
                      : null,
                }),
                200,
              );
            });
            addTearDown(apiClient.close);
            final apiReports = ReportDetailService(
              apiService: ApiService(
                client: apiClient,
                baseUrl: 'https://nowave.test/',
              ),
              getIdToken: () async => 'test-token',
              photoClient: apiClient,
            );
            final loads = <Future<ReportDetail>>[];
            reports.load = (id) {
              final pending = apiReports.fetchReport(id);
              loads.add(pending);
              return pending;
            };
            Future<void> settle() async {
              await tester.pump();
              await tester.runAsync(() => Future.wait(loads));
              await tester.pumpAndSettle();
            }

            if (delivery == 'terminated') source.initial = pushMessage();
            await mount(tester);
            final original = tester.state(find.byType(MapScreen));
            if (delivery == 'foreground') {
              source.messages.add(pushMessage());
              await settle();
              expect(reports.calls, isEmpty);
              expect(find.text('Ouvrir'), findsOneWidget);
              await tester.tap(find.text('Ouvrir'));
            } else if (delivery == 'background') {
              source.taps.add(pushMessage());
            }
            await settle();
            expect(reports.calls, ['report-a']);
            expect(selection(tester).report!.longitude, 6);
            expect(selection(tester).report!.latitude, 44);
            expect(map.cameras.single.center!.coordinates.lng, 6);
            expect(map.cameras.single.center!.coordinates.lat, 44);
            expect(selection(tester).report!.category, category);
            // The push fixture always says pollution: the API category must win.
            final data = jsonDecode(
              map.style.sources['alert-selected']!['data'] as String,
            );
            expect(data['properties']['category'], category.apiValue);
            expect(map.style.layers['alert-selected-point']!['type'], 'symbol');
            expect(
              map.style.images,
              contains(badges.ReportMarker.imageId(category)),
            );
            expect(selection(tester).report!.photo != null, photo);
            expect(reports.photoCalls, isEmpty);

            expect(
              find.byType(ReportDetailSheet, skipOffstage: false),
              findsNothing,
            );
            expect(tester.state(find.byType(MapScreen)), same(original));
            source.taps.add(pushMessage());
            await settle();
            expect(reports.calls, hasLength(1));
            source.taps.add(pushMessage(id: 'b', reportId: 'report-b'));
            await settle();
            expect(reports.calls, ['report-a', 'report-b']);
            expect(selection(tester).report!.id, 'report-b');
            expect(find.byType(MapScreen, skipOffstage: false), findsOneWidget);
            expect(
              Navigator.of(tester.element(find.byType(MapScreen))).canPop(),
              false,
            );
            map.interactions.single.action(
              mb.TypedFeaturesetFeature(
                mb.FeaturesetDescriptor(layerId: 'alert-selected-point'),
                {
                  'type': 'Point',
                  'coordinates': [6.0, 44.0],
                },
                {'report_id': 'report-b'},
                {},
              ),
              mb.MapContentGestureContext(
                touchPosition: mb.ScreenCoordinate(x: 200, y: 300),
                point: mb.Point(coordinates: mb.Position(6, 44)),
                gestureState: mb.GestureState.ended,
              ),
            );
            await settle();
            expect(
              tester
                  .widget<ReportDetailSheet>(find.byType(ReportDetailSheet))
                  .reportId,
              'report-b',
            );
            expect(reports.calls, ['report-a', 'report-b', 'report-b']);
            expect(
              reports.photoCalls,
              photo ? ['https://storage.test/report-b.png'] : isEmpty,
            );
            if (photo) {
              expect(
                find.bySemanticsLabel('Agrandir la photo'),
                findsOneWidget,
              );
            }
          },
        );
      }
    }
  }

  focusTestWidgets(
    'panne HTTP puis Réessayer : aucun cadrage inventé, nouvelle lecture API',
    (tester) async {
      reports.load = (_) async => throw TimeoutException('offline');
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de charger'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(selection(tester).report, isNull);
      expect(map.cameras, isEmpty);
      reports.load = null;
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(reports.calls, hasLength(1));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a', 'report-a']);
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets(
    'échec de cadrage puis Réessayer : nouvelle lecture et même carte',
    (tester) async {
      map.style.failSelection = true;
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de cadrer'), findsOneWidget);
      expect(map.cameras, isEmpty);
      map.style.failSelection = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a', 'report-a']);
      expect(map.cameras, hasLength(1));
    },
  );

  for (final photo in [false, true]) {
    for (final failure in ['404', 'expired', 'forbidden', 'network']) {
      focusTestWidgets(
        'NW-210 ${photo ? 'photo' : 'manuel'} $failure après sélection : aucun repère résiduel',
        (tester) async {
          reports.load = (id) async => focusReport(
            id: id,
            photo: photo
                ? const ReportPhoto(
                    status: ReportPhotoStatus.pending,
                    url: null,
                  )
                : null,
          );
          await mount(tester);
          source.taps.add(pushMessage(id: 'previous', reportId: 'previous'));
          await tester.pumpAndSettle();
          expect(selection(tester).report!.id, 'previous');
          expect(map.style.layers, contains('alert-selected-point'));
          reports.load = (id) async {
            if (failure == '404') throw const ReportNotFoundException();
            if (failure == 'forbidden') {
              throw const ApiException(statusCode: 403, body: '');
            }
            if (failure == 'network') throw TimeoutException('offline');
            return focusReport(
              id: id,
              expires: DateTime.now().subtract(const Duration(seconds: 1)),
            );
          };
          source.taps.add(pushMessage());
          await tester.pumpAndSettle();
          expect(push.canRetry, failure == 'network');
          expect(selection(tester).report, isNull);
          expect(map.cameras, hasLength(1));
          expect(map.style.layers, isNot(contains('alert-selected-point')));
          expect(map.style.sources, isNot(contains('alert-selected')));
          expect(reports.photoCalls, isEmpty);
          expect(find.byType(ReportDetailSheet), findsNothing);
        },
      );
    }
  }

  focusTestWidgets(
    'brouillon ouvert : diffère la lecture et le cadrage jusqu’à sa fermeture',
    (tester) async {
      await mount(tester);
      final focus = selection(tester);
      focus.setBlocked(true);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Terminez ou annulez'), findsOneWidget);
      expect(focus.isBlocked, true);
      expect(reports.calls, isEmpty);
      expect(map.cameras, isEmpty);
      focus.setBlocked(false);
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a']);
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets(
    'réponse HTTP ancienne après nouvel événement : conserve la dernière sélection',
    (tester) async {
      final old = Completer<ReportDetail>();
      reports.load = (id) => id == 'report-a'
          ? old.future
          : Future.value(focusReport(id: id, longitude: 7));
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      source.taps.add(pushMessage(id: 'b', reportId: 'report-b'));
      await tester.pumpAndSettle();
      old.complete(focusReport());
      await tester.pumpAndSettle();
      expect(selection(tester).report!.id, 'report-b');
      expect(map.cameras, hasLength(1));
      expect(map.cameras.single.center!.coordinates.lng, 7);
    },
  );

  focusTestWidgets(
    'session suspendue pendant HTTP : abandonne la réponse et la caméra',
    (tester) async {
      final pending = Completer<ReportDetail>();
      reports.load = (_) => pending.future;
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      push.setReady(false);
      pending.complete(focusReport());
      await tester.pumpAndSettle();
      expect(selection(tester).report, isNull);
      expect(map.cameras, isEmpty);
      expect(push.canRetry, false);
    },
  );
}

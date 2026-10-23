import 'dart:convert';

import 'package:blueway/core/api/api_config.dart';
import 'package:blueway/core/map/marine/marine_map_controller.dart';
import 'package:blueway/features/map/data/buoy_layer.dart';
import 'package:blueway/features/map/data/fixed_aid_layer.dart';
import 'package:blueway/features/map/data/hydrography_layer.dart';
import 'package:blueway/features/map/data/marine_tiles.dart';
import 'package:blueway/features/map/data/port_layer.dart';
import 'package:blueway/features/map/data/harbour_layer.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/map/marine/marine_map_controller_test.dart'
    show MarineMap;

class ScopedHttp extends Fake implements MapboxHttpService {
  final hosts = <String>[];
  final headers = <Map<String, String>>[];
  @override
  Future<void> setCustomHeadersForHost(
    String host,
    Map<String, String> value,
  ) async {
    hosts.add(host);
    headers.add(value);
  }
}

class SourcesMap extends MarineMap {
  final ScopedHttp scopedHttp = ScopedHttp();
  @override
  ScopedHttp get httpService => scopedHttp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = 'https://api.example.com/proxy?tenant=eu';

  testWidgets('toutes les sources partagent la base, versions et reload', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final map = SourcesMap();
      final raster = MarineMapController(apiBaseUrl: base);
      final hydro = HydrographyLayer(apiBaseUrl: base);
      final buoys = BuoyLayer(apiBaseUrl: base);
      final fixed = FixedAidLayer();
      final reports = ReportTiles(
        apiBaseUrl: base,
        getIdToken: () async => 'unit-token',
      );
      Future<void> install() async {
        await raster.install(map);
        await hydro.addTo(map);
        await PortLayer.addTo(map, apiBaseUrl: base);
        await HarbourLayer.addTo(map, apiBaseUrl: base);
        await buoys.addTo(map);
        await fixed.addTo(map);
        await reports.addTo(map);
      }

      await install();
      await install();
      final expected = {
        'nowave-global-seafloor':
            'seafloor/gebco-2026-v1/{z}/{x}/{y}.webp?tenant=eu',
        'nowave-bathymetry':
            'bathymetry/{z}/{x}/{y}.png?tenant=eu&v=marine-visual-7',
        'nowave-depth-contours': 'depth-contours/{z}/{x}/{y}.pbf?tenant=eu&v=3',
        'nowave-soundings': 'soundings/{z}/{x}/{y}.pbf?tenant=eu&v=depths-4',
        'nowave-underwater-hazards':
            'underwater-hazards/{z}/{x}/{y}.pbf?tenant=eu&v=3',
        'nowave-osm-ports':
            'port-infrastructure/{z}/{x}/{y}.pbf?tenant=eu&v=quays-2',
        'nowave-harbours': 'harbours/{z}/{x}/{y}.pbf?tenant=eu',
        'nowave-buoys': 'seamarks/{z}/{x}/{y}.pbf?tenant=eu',
        'nowave-reports': 'tiles/{z}/{x}/{y}.mvt?tenant=eu',
      };
      void verify() {
        expect(map.style.sources.keys.toSet(), expected.keys.toSet());
        for (final entry in expected.entries) {
          if (map.style.sources[entry.key]!['type'] == 'geojson') {
            expect(
              map.style.sources[entry.key]!['attribution'],
              contains('api.example.com/proxy'),
            );
            continue;
          }
          expect(map.style.sources[entry.key]!['tiles'], [
            'https://api.example.com/proxy/api/v1/map/${entry.value}',
          ]);
        }
        expect(map.httpService.hosts.toSet(), {'api.example.com'});
        expect(
          map.httpService.headers.every(
            (h) => h['Authorization'] == 'Bearer unit-token',
          ),
          isTrue,
        );
        expect(map.style.sources['nowave-soundings']!['type'], 'geojson');
      }

      verify();
      final layerCount = map.style.layers.length;
      map.style.sources.clear();
      map.style.layers.clear();
      map.style.images.clear();
      await install();
      verify();
      expect(map.style.layers.length, layerCount);
    });
  });

  test(
    'base invalide refusée avant demande du token ou en-tête Mapbox',
    () async {
      final map = SourcesMap();
      var tokenCalls = 0;
      final reports = ReportTiles(
        apiBaseUrl: '',
        getIdToken: () async {
          tokenCalls++;
          return 'unit-token';
        },
      );
      await expectLater(reports.authorize(map), throwsStateError);
      expect(tokenCalls, 0);
      expect(map.httpService.hosts, isEmpty);
    },
  );

  testWidgets(
    'environnement : seules les sources publiques utilisent la base marine',
    (tester) async {
      if (ApiConfig.baseUrl.isEmpty) {
        expect(() => ApiConfig.resolve('api/v1/users/me'), throwsStateError);
        return;
      }
      await tester.runAsync(() async {
        final map = SourcesMap();
        await MarineMapController().install(map);
        await HydrographyLayer().addTo(map);
        await PortLayer.addTo(map);
        await HarbourLayer.addTo(map);
        await BuoyLayer().addTo(map);
        await ReportTiles(getIdToken: () async => 'unit-token').addTo(map);
        final routes = {
          'nowave-global-seafloor': 'seafloor/gebco-2026-v1/{z}/{x}/{y}.webp',
          'nowave-bathymetry': 'bathymetry/{z}/{x}/{y}.png?v=marine-visual-7',
          'nowave-depth-contours': 'depth-contours/{z}/{x}/{y}.pbf?v=3',
          'nowave-soundings': 'soundings/{z}/{x}/{y}.pbf?v=depths-4',
          'nowave-underwater-hazards': 'underwater-hazards/{z}/{x}/{y}.pbf?v=3',
          'nowave-osm-ports': 'port-infrastructure/{z}/{x}/{y}.pbf?v=quays-2',
          'nowave-harbours': 'harbours/{z}/{x}/{y}.pbf',
          'nowave-buoys': 'seamarks/{z}/{x}/{y}.pbf',
          'nowave-reports': 'tiles/{z}/{x}/{y}.mvt',
        };
        expect(map.style.sources.keys.toSet(), routes.keys.toSet());
        for (final entry in routes.entries) {
          final source = map.style.sources[entry.key]!;
          if (source['type'] == 'geojson') continue;
          final url = (source['tiles'] as List).single as String;
          final expectedBase = entry.key == 'nowave-reports'
              ? ApiConfig.baseUrl
              : ApiConfig.marineBaseUrl;
          expect(
            url,
            ApiConfig.endpoint(
              'api/v1/map/${entry.value}',
              baseUrl: expectedBase,
            ),
          );
          expect(url, contains('{z}/{x}/{y}'));
        }
        final metadata = ApiConfig.endpoint(
          'api/v1/map/marine-sources',
          baseUrl: ApiConfig.marineBaseUrl,
        );
        final metadataLink =
            'href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(metadata)}"';
        expect(MarineTiles.attribution(), contains(metadataLink));
        for (final source in map.style.sources.values) {
          if (source['attribution'] != null) {
            expect(source['attribution'], contains(metadataLink));
          }
        }
        expect(map.httpService.hosts, [Uri.parse(ApiConfig.baseUrl).host]);
        expect(map.httpService.headers, [
          {'Authorization': 'Bearer unit-token'},
        ]);
      });
    },
  );
}

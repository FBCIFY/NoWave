import 'package:blueway/app/app.dart';
import 'package:blueway/core/map/marine/marine_map_controller.dart';
import 'package:blueway/core/map/marine/water_texture_layer.dart';
import 'package:blueway/features/map/data/buoy_layer.dart';
import 'package:blueway/features/map/data/port_layer.dart';
import 'package:blueway/features/map/data/hydrography_layer.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  testWidgets(
    'une panne des bouées laisse la carte et ses commandes accessibles',
    (tester) async {
      await tester.pumpWidget(const MyApp(home: MapScreen()));
      final widget = tester.widget<MapWidget>(find.byType(MapWidget));
      for (final (type, source) in [
        (MapLoadErrorType.SOURCE, BuoyLayer.sourceId),
        (MapLoadErrorType.TILE, BuoyLayer.sourceId),
        (MapLoadErrorType.TILE, PortLayer.sourceId),
        (MapLoadErrorType.TILE, MarineMapController.bathymetrySourceId),
        (MapLoadErrorType.SOURCE, WaterTextureLayer.sourceId),
        (MapLoadErrorType.TILE, WaterTextureLayer.sourceId),
        for (final source in HydrographyLayer.sourceIds) ...[
          (MapLoadErrorType.TILE, source),
          (MapLoadErrorType.SOURCE, source),
        ],
      ]) {
        widget.onMapLoadErrorListener!(
          MapLoadingErrorEventData.fromJson({
            'type': type.index,
            'message': 'Failed to load tile: HTTP status code 503',
            'sourceId': source,
            'timestamp': 0,
          }),
        );
        await tester.pump();
        expect(
          find.textContaining('Impossible de charger la carte'),
          findsNothing,
        );
        expect(find.byType(MapWidget), findsOneWidget);
        expect(find.byTooltip('Créer un signalement'), findsOneWidget);
        expect(find.byTooltip('Recentrer sur ma position'), findsOneWidget);
      }
      // Une vraie panne du fond de carte garde le comportement existant.
      widget.onMapLoadErrorListener!(
        MapLoadingErrorEventData.fromJson({
          'type': MapLoadErrorType.STYLE.index,
          'message': 'Style unavailable',
          'timestamp': 0,
        }),
      );
      await tester.pump();
      expect(
        find.textContaining('Impossible de charger la carte'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

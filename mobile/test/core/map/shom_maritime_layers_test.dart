import 'package:blueway/core/map/shom_maritime_layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShomMaritimeLayers', () {
    test('uses the public SHOM HTTPS endpoints only', () {
      expect(ShomMaritimeLayers.wmtsEndpoint, startsWith('https://'));
      expect(ShomMaritimeLayers.wfsEndpoint, startsWith('https://'));
      expect(
        Uri.parse(ShomMaritimeLayers.wmtsEndpoint).host,
        'services.data.shom.fr',
      );
      expect(
        Uri.parse(ShomMaritimeLayers.wfsEndpoint).host,
        'services.data.shom.fr',
      );
      expect(ShomMaritimeLayers.wmtsEndpoint, isNot(contains('localhost')));
      expect(ShomMaritimeLayers.wmtsEndpoint, isNot(contains('openseamap')));
    });

    test('builds Web Mercator WMTS GetTile URLs', () {
      final url = ShomMaritimeLayers.tileUrl(
        ShomMaritimeLayers.buoyageWmtsLayerId,
      );

      expect(url, contains('service=WMTS'));
      expect(url, contains('request=GetTile'));
      expect(url, contains('version=1.0.0'));
      expect(url, contains('tilematrixset=3857'));
      expect(url, contains('TileMatrix={z}'));
      expect(url, contains('TileCol={x}'));
      expect(url, contains('TileRow={y}'));
      expect(url, contains('layer=${ShomMaritimeLayers.buoyageWmtsLayerId}'));
    });

    test('keeps the validated SHOM products', () {
      expect(
        ShomMaritimeLayers.activeWmtsLayerIds,
        containsAll(<String>[
          'MNT_MED100m_GDL_CA_HOMONIM_PBMA_3857_WMTS',
          'REGLEMENTATION_NAVIGATION_PYR_PNG_3857_WMTS',
          'INFORMATIONS_PORTUAIRES_PYR_PNG_3857_WMTS',
          'TOPONYMIE_PYR_PNG_3857_WMTS',
          'BALISAGE_PYR_PNG_3857_WMTS',
        ]),
      );
    });

    test('wrecks are prepared but disabled by default', () {
      expect(ShomMaritimeLayers.wrecksEnabledByDefault, isFalse);
      expect(
        ShomMaritimeLayers.activeWmtsLayerIds,
        isNot(contains(ShomMaritimeLayers.wrecksWmtsLayerId)),
      );
      expect(
        ShomMaritimeLayers.allWmtsLayerIds,
        contains(ShomMaritimeLayers.wrecksWmtsLayerId),
      );
    });

    test('country and city zoom ranges preserve the z6 switch', () {
      expect(ShomMaritimeLayers.countryMaxZoom, 6.01);
      expect(ShomMaritimeLayers.cityMinZoom, 6.01);
      expect(ShomMaritimeLayers.cityMaxZoom, 12.0);
      expect(ShomMaritimeLayers.countryMaxZoom, ShomMaritimeLayers.cityMinZoom);
    });

    test('recognizes only SHOM source ids', () {
      expect(
        ShomMaritimeLayers.isSourceId(ShomMaritimeLayers.buoyageSourceId),
        isTrue,
      );
      expect(ShomMaritimeLayers.isSourceId('nowave-reports'), isFalse);
      expect(ShomMaritimeLayers.isSourceId(null), isFalse);
    });
  });
}

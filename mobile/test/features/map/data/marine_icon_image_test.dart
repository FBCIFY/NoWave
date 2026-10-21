import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/buoy_layer.dart';
import 'package:blueway/features/map/data/fixed_aid_layer.dart';
import 'package:blueway/features/map/data/harbour_layer.dart';
import 'package:blueway/features/map/data/marine_icon_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'les références nautiques couvrent les 43 assets et leur alias neutre',
    () async {
      Set<String> references(Object? value) {
        if (value is String && value.startsWith('nowave-')) {
          return {value};
        }
        if (value is List) {
          return {for (final item in value) ...references(item)};
        }
        return {};
      }

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      Set<String> assetIds(String directory, String prefix) => {
        for (final path in manifest.listAssets())
          if (path.startsWith('assets/icons/$directory/') &&
              path.endsWith('.png'))
            '$prefix${path.split('/').last.replaceAll('.png', '')}',
      };
      final buoys = references(BuoyLayer.imageExpression());
      final fixed = references(FixedAidLayer.imageExpression());
      final harbours = references(HarbourLayer.layer().iconImageExpression);
      expect(buoys, assetIds('buoys', 'nowave-buoy-'));
      expect(buoys, hasLength(12));
      expect(fixed, {
        ...assetIds('fixed-aids', 'nowave-'),
        'nowave-beacon-neutral',
      });
      expect(fixed, hasLength(30));
      expect(harbours, {'nowave-harbour', 'nowave-marina'});
      expect(assetIds('harbours', ''), {'port', 'marina'});
      expect({...buoys, ...fixed, ...harbours}, hasLength(44));
    },
  );

  testWidgets('les 43 assets déclarés restent des PNG natifs transparents', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets =
          manifest
              .listAssets()
              .where(
                (path) => RegExp(
                  r'^assets/icons/(buoys|fixed-aids|harbours)/[^/]+\.png$',
                ).hasMatch(path),
              )
              .toList()
            ..sort();
      expect(assets, hasLength(43));
      expect(assets.where((p) => p.contains('/buoys/')), hasLength(12));
      expect(
        assets.where((p) => p.contains('/fixed-aids/beacon-')),
        hasLength(19),
      );
      expect(
        assets.where((p) => p.contains('/fixed-aids/lighthouse-')),
        hasLength(5),
      );
      expect(
        assets.where((p) => p.contains('/fixed-aids/light-')),
        hasLength(5),
      );
      expect(assets.where((p) => p.contains('/harbours/')), hasLength(2));
      for (final asset in assets) {
        final source = await rootBundle.load(asset);
        final image = await MarineIconImage.load(asset);
        expect(image.width, 72, reason: asset);
        expect(image.height, 72, reason: asset);
        expect(
          image.data,
          orderedEquals(
            source.buffer.asUint8List(
              source.offsetInBytes,
              source.lengthInBytes,
            ),
          ),
          reason: asset,
        );
        expect(image.data.take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ], reason: asset);
        // Exerce un vrai décodeur d'image encodée, comme les deux ponts natifs.
        final codec = await ui.instantiateImageCodec(image.data);
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, image.width, reason: asset);
            expect(frame.image.height, image.height, reason: asset);
            final rgba = (await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            expect(rgba, hasLength(72 * 72 * 4), reason: asset);
            final alpha = [for (var i = 3; i < rgba.length; i += 4) rgba[i]];
            expect(alpha, containsAll([0, 255]), reason: asset);
            expect(alpha.any((a) => a > 0 && a < 255), true, reason: asset);
            for (final corner in [0, 71, 72 * 71, 72 * 72 - 1]) {
              expect(rgba[corner * 4 + 3], 0, reason: asset);
            }
            for (var i = 0; i < rgba.length; i += 4) {
              // Le décodage natif produit bien les composantes prémultipliées.
              if (rgba[i] > rgba[i + 3] ||
                  rgba[i + 1] > rgba[i + 3] ||
                  rgba[i + 2] > rgba[i + 3]) {
                fail('Pixel non prémultiplié dans $asset à ${i ~/ 4}');
              }
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    });
  });

  testWidgets('ByteData décalé et alpha partiel conservent le PNG encodé', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = img.Image(width: 1, height: 1, numChannels: 4)
        ..setPixelRgba(0, 0, 200, 100, 50, 128);
      final png = Uint8List.fromList(img.encodePng(source));
      final padded = Uint8List(png.length + 31)
        ..setRange(17, 17 + png.length, png);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        expect(
          utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          ),
          'fixture-offset.png',
        );
        return ByteData.sublistView(padded, 17, 17 + png.length);
      });
      try {
        final result = await MarineIconImage.load('fixture-offset.png');
        expect(result.width, 1);
        expect(result.height, 1);
        expect(result.data, orderedEquals(png));
        final codec = await ui.instantiateImageCodec(result.data);
        try {
          final frame = await codec.getNextFrame();
          try {
            final rgba = (await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            expect(
              rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
              [100, 50, 25, 128],
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        messenger.setMockMessageHandler('flutter/assets', null);
      }
    });
  });

  testWidgets(
    'image corrompue et asset absent échouent, puis sont retentables',
    (tester) async {
      await tester.runAsync(() async {
        final valid = await rootBundle.load('assets/icons/harbours/port.png');
        var missing = true;
        var corrupt = false;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler('flutter/assets', (_) async {
          if (missing) return null;
          if (corrupt) {
            return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
          }
          return valid;
        });
        try {
          await expectLater(
            MarineIconImage.load('fixture-retry.png'),
            throwsFlutterError,
          );
          missing = false;
          corrupt = true;
          await expectLater(
            MarineIconImage.load('fixture-retry.png'),
            throwsA(isA<Exception>()),
          );
          corrupt = false;
          final image = await MarineIconImage.load('fixture-retry.png');
          expect(image.width, 72);
          expect(image.height, 72);
          expect(image.data.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        } finally {
          messenger.setMockMessageHandler('flutter/assets', null);
        }
      });
    },
  );
}

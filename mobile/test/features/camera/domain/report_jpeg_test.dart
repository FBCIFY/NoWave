import 'dart:math' as math;
import 'dart:typed_data';

import 'package:blueway/features/camera/domain/report_jpeg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Photo couchée comme celles du téléphone : EXIF avec rotation de 90° et
/// une marque d'appareil.
Uint8List _phoneJpeg({required int width, required int height, int seed = 1}) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);

  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }

  image.exif.imageIfd.orientation = 6;
  image.exif.imageIfd['Make'] = 'Test phone';

  return img.encodeJpg(image, quality: 95);
}

bool _containsExif(Uint8List jpeg) {
  const signature = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"

  for (var i = 0; i <= jpeg.length - signature.length; i++) {
    var matches = true;

    for (var j = 0; j < signature.length; j++) {
      if (jpeg[i + j] != signature[j]) {
        matches = false;
        break;
      }
    }

    if (matches) return true;
  }

  return false;
}

void main() {
  test('la photo d’origine contient bien des EXIF', () {
    expect(_containsExif(_phoneJpeg(width: 40, height: 30)), isTrue);
  });

  test('redresse la photo et retire les EXIF', () {
    final result = prepareReportJpeg(_phoneJpeg(width: 40, height: 30));
    final decoded = img.decodeJpg(result)!;

    expect(_containsExif(result), isFalse);
    expect(decoded.width, 30);
    expect(decoded.height, 40);
  });

  test('réduit une grande photo à 1600 px au plus grand côté', () {
    final result = prepareReportJpeg(
      _phoneJpeg(width: 1920, height: 1080),
      maxBytes: 10000000,
    );
    final decoded = img.decodeJpg(result)!;

    expect(decoded.width, 900);
    expect(decoded.height, 1600);
  });

  test('ne dépasse jamais 500 000 octets', () {
    final original = _phoneJpeg(width: 1920, height: 1080);
    expect(original.length, greaterThan(maxReportPhotoBytes));

    final result = prepareReportJpeg(original);

    expect(result.length, lessThanOrEqualTo(maxReportPhotoBytes));
    expect(img.decodeJpg(result), isNotNull);
  });

  test('refuse une photo impossible à alléger assez', () {
    expect(
      () => prepareReportJpeg(_phoneJpeg(width: 40, height: 30), maxBytes: 10),
      throwsFormatException,
    );
  });

  test('refuse des octets qui ne sont pas une image', () {
    expect(
      () => prepareReportJpeg(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}

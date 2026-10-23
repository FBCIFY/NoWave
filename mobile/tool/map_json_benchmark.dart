// Host-only decode/transfer experiment. No Flutter frame or device FPS claims.
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

List<Map<String, dynamic>> decodeFeatures(Uint8List bytes) {
  final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  return (data['features'] as List)
      .map((f) => Map<String, dynamic>.from(f as Map))
      .toList();
}

Future<void> main() async {
  for (final count in [100, 1000, 5000]) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            for (var i = 0; i < count; i++)
              {
                'type': 'Feature',
                'id': 'line-$i',
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (var j = 0; j < 20; j++)
                      [5.92 + j * .001, 43.08 + i * .000001],
                  ],
                },
                'properties': {'value_m': i + 1},
              },
          ],
        }),
      ),
    );
    // Warm both execution paths before the three paired observations.
    decodeFeatures(bytes);
    await Isolate.run(() => decodeFeatures(bytes));
    final sync = <int>[], isolated = <int>[];
    for (var trial = 0; trial < 3; trial++) {
      final watch = Stopwatch()..start();
      final a = decodeFeatures(bytes);
      sync.add(watch.elapsedMicroseconds);
      watch.reset();
      final b = await Isolate.run(() => decodeFeatures(bytes));
      isolated.add(watch.elapsedMicroseconds);
      if (a.length != count || jsonEncode(a) != jsonEncode(b)) {
        throw StateError('Decode result differs');
      }
    }
    // ignore: avoid_print
    print(
      jsonEncode({
        'features': count,
        'bytes': bytes.length,
        'sync_us': sync,
        'isolate_total_us': isolated,
        'scope': 'host Dart VM; includes isolate transfer; no device frame measurement',
      }),
    );
  }
}

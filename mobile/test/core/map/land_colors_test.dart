import 'dart:math' as math;

import 'package:blueway/core/map/globe_style.dart';
import 'package:blueway/core/map/land_colors.dart';
import 'package:blueway/core/map/marine/marine_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Evaluate the emitted paint expression in sRGB, independently of the palette
// helpers. Native parsing/rendering is also checked on Android.
Color evaluate(Object expression, double zoom, {String category = ''}) {
  if (expression is String) {
    if (expression == 'rgba(0,0,0,0)') return const Color(0x00000000);
    return Color(int.parse('FF${expression.substring(1)}', radix: 16));
  }
  final e = expression as List;
  switch (e.first) {
    case 'hsl':
      final h = (e[1] as num) / 60;
      final s = (e[2] as num) / 100;
      final l = (e[3] as num) / 100;
      final c = (1 - (2 * l - 1).abs()) * s;
      final x = c * (1 - (h % 2 - 1).abs());
      final m = l - c / 2;
      final channels = switch (h.floor() % 6) {
        0 => [c, x, 0.0],
        1 => [x, c, 0.0],
        2 => [0.0, c, x],
        3 => [0.0, x, c],
        4 => [x, 0.0, c],
        _ => [c, 0.0, x],
      };
      return Color.from(
        alpha: 1,
        red: channels[0] + m,
        green: channels[1] + m,
        blue: channels[2] + m,
      );
    case 'match':
      for (var i = 2; i < e.length - 1; i += 2) {
        if (e[i] == category) return evaluate(e[i + 1], zoom);
      }
      return evaluate(e.last, zoom);
    case 'interpolate':
      final from = (e[3] as num).toDouble();
      final to = (e[5] as num).toDouble();
      final t = ((zoom - from) / (to - from)).clamp(0.0, 1.0);
      final a = evaluate(e[4], zoom, category: category);
      final b = evaluate(e[6], zoom, category: category);
      return Color.from(
        alpha: a.a + (b.a - a.a) * t,
        red: a.r + (b.r - a.r) * t,
        green: a.g + (b.g - a.g) * t,
        blue: a.b + (b.b - a.b) * t,
      );
    default:
      throw StateError('Unexpected expression: $expression');
  }
}

// HSLColor.fromColor quantizes its input to 8-bit; Mapbox expressions operate
// on floats, so inspect the unquantized sRGB channels for this numeric check.
HSLColor hsl(Color color) {
  final hi = math.max(color.r, math.max(color.g, color.b));
  final lo = math.min(color.r, math.min(color.g, color.b));
  final delta = hi - lo;
  final lightness = (hi + lo) / 2;
  final hue = delta == 0
      ? 0.0
      : 60 *
            (hi == color.r
                ? ((color.g - color.b) / delta) % 6
                : hi == color.g
                ? (color.b - color.r) / delta + 2
                : (color.r - color.g) / delta + 4);
  return HSLColor.fromAHSL(
    color.a,
    hue,
    delta == 0 ? 0 : delta / (1 - (2 * lightness - 1).abs()),
    lightness,
  );
}

void verify(Object expression) {
  final original = hsl(evaluate(expression, 4));
  for (final entry in <double, double>{
    0.65: 1,
    4: 1,
    4.5: .9375,
    5: .875,
    5.5: .8125,
    6: .75,
    8: .75,
    16: .75,
    5.99: .75125,
    4.01: .99875,
  }.entries) {
    final actual = hsl(evaluate(expression, entry.key));
    expect(actual.saturation, closeTo(original.saturation * entry.value, 1e-6));
    expect(actual.hue, closeTo(original.hue, 1e-4));
    expect(actual.lightness, closeTo(original.lightness, 1e-6));
  }
}

void main() {
  test('60% saturation becomes 45%, with fractional continuous zooms', () {
    final expression = LandColors.color('#33CC33');
    expect(hsl(evaluate(expression, 4)).saturation, closeTo(.6, 1e-6));
    expect(hsl(evaluate(expression, 6)).saturation, closeTo(.45, 1e-6));
    verify(expression);
    for (var i = 0; i <= 200; i++) {
      final zoom = 4 + i / 100;
      final saturation = hsl(evaluate(expression, zoom)).saturation;
      expect(saturation, closeTo(.6 * (1 - .25 * (zoom - 4) / 2), 1e-6));
    }
  });

  test(
    'all Standard land surfaces use relative correction, neutral stays neutral',
    () {
      for (final key in MarinePalette.land.keys) {
        verify(MarinePalette.basemapConfig[key]!);
      }
      verify(LandColors.color('#888888'));
      expect(MarinePalette.basemapConfig['colorWater'], '#002D51');
      expect(MarinePalette.basemapConfig['colorPlaceLabels'], '#3A4843');
      expect(MarinePalette.basemapConfig['colorAdminBoundaries'], '#CED1C8');
    },
  );

  test('landcover and relief preserve classification, opacity and native zoom fade', () {
    final layers =
        GlobeStyle.document(Uri.parse('file:///unused/'))['layers'] as List;
    for (final id in ['nowave-landcover', 'nowave-land-relief']) {
      final layer = layers.singleWhere((l) => l['id'] == id) as Map;
      final expression = layer['paint']['fill-color'] as List;
      final original = expression[4] as List;
      for (var i = 2; i < original.length - 1; i += 2) {
        final category = original[i] as String;
        // Keep the actual emitted class match at both zoom stops.
        final before = hsl(evaluate(expression, 4, category: category));
        for (final z in [4.0, 4.5, 5.0, 5.5, 6.0, 8.0]) {
          final after = hsl(evaluate(expression, z, category: category));
          final factor = 1 - .25 * ((z - 4) / 2).clamp(0, 1);
          expect(after.saturation, closeTo(before.saturation * factor, 1e-6));
          expect(after.lightness, closeTo(before.lightness, 1e-6));
        }
      }
      expect(evaluate(expression, 8, category: 'unknown').a, 0);
      expect(layer['slot'], 'bottom');
      expect(layer['paint']['fill-emissive-strength'], 1);
    }
    final relief = layers.singleWhere((l) => l['id'] == 'nowave-land-relief');
    expect(relief['paint']['fill-opacity'], [
      'interpolate',
      ['linear'],
      ['zoom'],
      0,
      .22,
      12,
      .22,
      16,
      0.0,
    ]);
    final ocean = layers.singleWhere((l) => l['id'] == 'nowave-earth-ocean');
    expect(ocean['paint']['fill-color'], '#002D51');
    expect(ocean['paint']['fill-opacity'], 1);
  });
}

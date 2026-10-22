import 'package:blueway/core/map/location_mast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pavillon chargé par code ISO, sans tenir compte de la casse', () async {
    for (final code in ['FR', ' es ', 'gb', 'CH']) {
      final flag = await LocationMast.loadFlag(code);
      expect(flag, isNotNull, reason: code);
      // flagcdn w80 : 80 pixels de large, la hauteur suit le pays.
      expect(flag!.width, 80, reason: code);
      flag.dispose();
    }
  });

  test('code absent ou inconnu : pas de pavillon, donc bleu uni', () async {
    for (final code in [null, '', 'zz', 'fra', '../fr', '12']) {
      expect(await LocationMast.loadFlag(code), isNull, reason: '$code');
    }
  });

  test('images à la densité de l’écran', () async {
    final mast = await LocationMast.mast(2, null);
    expect((mast.width, mast.height), (120, 124));
    final flag = await LocationMast.loadFlag('FR');
    final flagged = await LocationMast.mast(3, flag);
    flag!.dispose();
    expect((flagged.width, flagged.height), (180, 186));
    expect(flagged.data, isNotEmpty);
    final chevron = await LocationMast.chevron(3, scale: .75);
    expect((chevron.width, chevron.height), (144, 144));
    final dot = await LocationMast.dot(2);
    expect((dot.width, dot.height), (96, 96));
  });
}

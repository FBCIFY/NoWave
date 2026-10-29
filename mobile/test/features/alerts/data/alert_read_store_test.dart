import 'package:blueway/features/alerts/data/alert_read_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'la consultation persiste au redémarrage et reste propre au compte',
    () async {
      final date = DateTime.utc(2026, 10, 22, 12);
      await AlertReadStore(accountId: 'a').markOpened('report', date);
      expect(await AlertReadStore(accountId: 'a').read(), {'report': date});
      expect(await AlertReadStore(accountId: 'b').read(), isEmpty);
    },
  );

  test(
    'les écritures simultanées conservent la consultation la plus récente',
    () async {
      final store = AlertReadStore(accountId: 'a');
      final date = DateTime.utc(2026, 10, 22, 12);
      await Future.wait([
        store.markOpened('one', date),
        store.markOpened('two', date),
        store.markOpened('one', date.subtract(const Duration(hours: 1))),
      ]);
      expect(await store.read(), {'one': date, 'two': date});
    },
  );
}

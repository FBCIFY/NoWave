import 'dart:async';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/features/profile/data/account_deletion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_deletion_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountFixture f;
  setUp(() {
    f = AccountFixture();
  });
  tearDown(() => f.dispose());

  test(
    'échec du journal avant envoi : aucune suppression ni nettoyage',
    () async {
      final deletion = AccountDeletion(
        profileService: f.profiles,
        authService: f.auth,
        registration: f.registration,
        reporter: f.reporter,
        preferences: () async => throw StateError('Stockage indisponible'),
      );
      await expectLater(deletion.run(), throwsStateError);
      expect(deletion.pending, isFalse);
      expect(f.requests, isEmpty);
      expect(f.auth.signOutCalls, 0);
      expect(await f.ids.read(), 'installation-old');
    },
  );

  test(
    'attend l’enregistrement en cours avant DELETE et bloque les suivants',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      f.respondDevice = (_) {
        started.complete();
        return response.future;
      };
      final registering = f.registration.start();
      await started.future;
      final deleting = f.deletion.run();
      await Future<void>.delayed(Duration.zero);
      expect(f.requests.map((r) => r.method), ['PUT']);
      response.complete(http.Response('{}', 200));
      await registering;
      await deleting;
      expect(f.requests.map((r) => r.method), ['PUT', 'DELETE']);
      expect(f.auth.currentUser, isNull);
    },
  );

  test(
    '204 nettoie FCM, installation et session sans DELETE appareil',
    () async {
      await f.registration.start();
      await f.deletion.run();
      expect(f.auth.currentUser, isNull);
      expect(f.push.deletions, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('installation_id'), isNull);
      expect(prefs.getStringList('account_deletion'), isNull);
      expect(
        f.requests.where((r) => r.method == 'DELETE').map((r) => r.url.path),
        ['/api/v1/users/me'],
      );
      f.auth.currentUser = TestUser('account-b');
      await f.registration.start();
      expect(await f.ids.read(), 'installation-next');
    },
  );

  for (final status in [401, 403, 404, 422, 503]) {
    test(
      'HTTP $status ne ferme jamais la session ni ne nettoie les données',
      () async {
        f.respond = (_) async => http.Response('{}', status);
        await expectLater(f.deletion.run(), throwsA(isA<ApiException>()));
        expect(f.auth.signOutCalls, 0);
        expect(await f.ids.read(), 'installation-old');
        expect(f.push.deletions, 0);
        expect(f.deletion.confirmed, isFalse);
        expect(f.registration.isSigningOut, isTrue);
        await f.registration.start();
        await f.registration.register();
        await f.reporter.start();
        expect(f.requests, hasLength(1));
      },
    );
  }

  for (final error in [
    TimeoutException('réponse perdue'),
    http.ClientException('offline'),
  ]) {
    test('$error conserve la reprise puis accepte un DELETE 204', () async {
      f.respond = (_) async => throw error;
      await expectLater(f.deletion.run(), throwsA(same(error)));
      expect(f.auth.signOutCalls, 0);
      final resumed = f.newDeletion();
      expect(await resumed.restore(), isTrue);
      expect(resumed.confirmed, isFalse);
      f.respond = (_) async => http.Response('', 204);
      await resumed.run();
      expect(f.auth.signOutCalls, 1);
      expect(f.requests, hasLength(2));
    });
  }

  test(
    'réponse perdue après suppression serveur puis 401 reste indéterminée',
    () async {
      var serverDeleted = false;
      f.respond = (_) async {
        if (serverDeleted) return http.Response('{}', 401);
        serverDeleted = true;
        throw TimeoutException('réponse perdue après commit serveur');
      };
      await expectLater(f.deletion.run(), throwsA(isA<TimeoutException>()));
      await expectLater(f.deletion.run(), throwsA(isA<ApiException>()));
      expect(serverDeleted, isTrue);
      expect(f.deletion.confirmed, isFalse);
      expect(f.auth.signOutCalls, 0);
      expect(await f.ids.read(), 'installation-old');
    },
  );

  test(
    'réponse perdue puis compte Firebase introuvable : suppression terminée',
    () async {
      var serverDeleted = false;
      f.respond = (_) async {
        if (serverDeleted) return http.Response('{}', 401);
        serverDeleted = true;
        throw TimeoutException('réponse perdue après commit serveur');
      };
      await expectLater(f.deletion.run(), throwsA(isA<TimeoutException>()));
      f.auth.identityDeleted = true;
      await f.deletion.run();
      expect(f.deletion.confirmed, isTrue);
      expect(f.auth.signOutCalls, 1);
      expect(f.push.deletions, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('account_deletion'), isNull);
    },
  );

  test(
    'sortie sans confirmation : session fermée, reprise gardée pour ce compte',
    () async {
      f.respond = (_) async => http.Response('{}', 503);
      await expectLater(f.deletion.run(), throwsA(isA<ApiException>()));
      await f.deletion.leave();
      expect(f.auth.currentUser, isNull);
      expect(f.requests, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('account_deletion'), ['account-a', 'pending']);

      f.auth.currentUser = TestUser('account-a');
      expect(await f.newDeletion().restore(), isTrue);
    },
  );

  test('deux appels partagent une seule suppression', () async {
    final response = Completer<http.Response>();
    f.respond = (_) => response.future;
    final first = f.deletion.run();
    final second = f.deletion.run();
    expect(identical(first, second), isTrue);
    response.complete(http.Response('', 204));
    await Future.wait([first, second]);
    expect(f.requests, hasLength(1));
  });

  test(
    'stockage indisponible après 204 : reprise confirmée sans nouveau DELETE',
    () async {
      f.ids.failReset = true;
      await expectLater(f.deletion.run(), throwsStateError);
      expect(f.auth.signOutCalls, 0);
      expect(await f.ids.read(), 'installation-old');
      final resumed = f.newDeletion();
      expect(await resumed.restore(), isTrue);
      expect(resumed.confirmed, isTrue);
      f.ids.failReset = false;
      await resumed.run();
      expect(f.requests, hasLength(1));
      expect(f.auth.currentUser, isNull);
    },
  );

  test('échec Firebase local après 204 ne répète pas le DELETE', () async {
    f.auth.failSignOut = true;
    await expectLater(f.deletion.run(), throwsStateError);
    expect(f.deletion.confirmed, isTrue);
    await f.registration.start();
    expect(f.requests, hasLength(1));
    f.auth.failSignOut = false;
    await f.deletion.run();
    expect(f.requests, hasLength(1));
    expect(f.auth.signOutCalls, 2);
  });

  test('FCM indisponible ne bloque pas après confirmation serveur', () async {
    f.push.fail = true;
    await f.deletion.run();
    expect(f.auth.currentUser, isNull);
  });

  test('journal ne supprime jamais un autre compte', () async {
    f.respond = (_) async => http.Response('', 503);
    await expectLater(f.deletion.run(), throwsA(isA<ApiException>()));
    f.auth.currentUser = TestUser('account-b');
    expect(await f.newDeletion().restore(), isFalse);
    expect(f.requests, hasLength(1));
  });
}

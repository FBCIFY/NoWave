import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/boat_profile_loader.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/domain/boat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'boat_service_test.dart' show boatJson;

void main() {
  late int requests;
  late BoatProfileLoader loader;
  late Future<http.Response> Function() respond;

  setUp(() {
    requests = 0;
    respond = () async => http.Response(jsonEncode(boatJson), 200);
    final client = MockClient((request) {
      requests++;
      return respond();
    });
    addTearDown(client.close);
    loader = BoatProfileLoader(
      ProfileService(
        apiService: ApiService(client: client, baseUrl: 'https://nowave.test/'),
        getIdToken: () async => 'test-token',
      ),
    );
  });

  test('le préchargement et le clic partagent une seule requête', () async {
    final response = Completer<http.Response>();
    respond = () => response.future;
    final prefetch = loader.load();
    final click = loader.load();
    expect(identical(prefetch, click), isTrue);
    response.complete(http.Response(jsonEncode(boatJson), 200));
    final boat = await click;
    expect(requests, 1);
    expect(loader.boat, same(boat));
    expect(await loader.load(), same(boat));
    expect(requests, 1);
  });

  test('l’absence de bateau est aussi conservée en mémoire', () async {
    respond = () async =>
        http.Response('{"error":{"code":"boat_not_found"}}', 404);
    expect(await loader.load(), isNull);
    expect(loader.loaded, isTrue);
    expect(await loader.load(), isNull);
    expect(requests, 1);
  });

  test('une erreur ne bloque pas une nouvelle tentative', () async {
    respond = () async => http.Response('{}', 503);
    await expectLater(loader.load(), throwsA(anything));
    expect(loader.loaded, isFalse);
    respond = () async => http.Response(jsonEncode(boatJson), 200);
    expect(await loader.load(), isNotNull);
    expect(requests, 2);
  });

  test('modification et suppression remplacent le bateau préchargé', () async {
    await loader.load();
    final changed = Boat.fromJson({...boatJson, 'name': 'Nouveau nom'});
    loader.update(changed);
    expect(await loader.load(), same(changed));
    loader.update(null);
    expect(await loader.load(), isNull);
    expect(requests, 1);
  });

  test(
    'une mutation incertaine impose une relecture à la réouverture',
    () async {
      await loader.load();
      loader.invalidate();
      expect(loader.loaded, isFalse);
      await loader.load();
      expect(requests, 2);
    },
  );

  test('une relecture explicite contourne le cache', () async {
    await loader.load();
    await loader.load(refresh: true);
    expect(requests, 2);
  });
}

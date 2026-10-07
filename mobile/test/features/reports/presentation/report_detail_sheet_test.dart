import 'dart:async';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:blueway/features/reports/presentation/report_photo_viewer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Signalement à 2,4 NM au nord de [_user], observé ce matin.
ReportDetail _report({
  ReportAuthor? author = const ReportAuthor(username: 'marin', deleted: false),
  ReportBoat? boat = const ReportBoat(name: 'Albatros', type: BoatType.rib),
  ReportPhoto? photo = const ReportPhoto(
    status: ReportPhotoStatus.pending,
    url: null,
  ),
}) => ReportDetail(
  id: 'report-id',
  category: ReportCategory.marineAnimal,
  description: 'Dauphins',
  latitude: 43.04,
  longitude: 5,
  observedAt: DateTime(2026, 10, 5, 9, 30),
  expiresAt: DateTime(2026, 10, 5, 15, 30),
  author: author,
  boat: boat,
  photo: photo,
);

const _user = (latitude: 43.0, longitude: 5.0);

/// Photo publiée, servie par une URL signée.
ReportPhoto _uploaded(String? url) =>
    ReportPhoto(status: ReportPhotoStatus.uploaded, url: url);

final _png = img.encodePng(img.Image(width: 4, height: 3));

ApiException _storage(int statusCode) =>
    ApiException(statusCode: statusCode, body: '<Error/>');

/// Fiche seule dans un écran, avec une heure fixe.
Widget _sheet(
  Future<ReportDetail> Function(String id) load, {
  Future<Uint8List> Function(String url)? loadPhoto,
}) => MaterialApp(
  home: Scaffold(
    body: ReportDetailSheet(
      reportId: 'report-id',
      loadReport: load,
      loadPhoto: loadPhoto ?? (_) async => _png,
      userPosition: _user,
      now: () => DateTime(2026, 10, 5, 14),
    ),
  ),
);

void main() {
  testWidgets('affiche la fiche complète', (tester) async {
    await tester.pumpWidget(_sheet((_) async => _report()));
    await tester.pumpAndSettle();

    expect(find.text('Animal marin'), findsOneWidget);
    expect(find.text('Observé aujourd’hui à 09:30'), findsOneWidget);
    expect(find.text('Dauphins'), findsOneWidget);
    expect(find.text('43° 2′ 24″ N\n5° 0′ 0″ E'), findsOneWidget);
    expect(find.text('2,4 NM au N'), findsOneWidget);
    expect(find.text('marin'), findsOneWidget);
    expect(find.text('Albatros · Semi-rigide'), findsOneWidget);
    expect(find.text('Envoi en cours'), findsOneWidget);
    expect(find.text('aujourd’hui à 15:30'), findsOneWidget);
  });

  testWidgets('indique un auteur supprimé et cache le reste', (tester) async {
    await tester.pumpWidget(
      _sheet(
        (_) async => _report(
          author: const ReportAuthor(username: null, deleted: true),
          boat: null,
          photo: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Utilisateur supprimé'), findsOneWidget);
    expect(find.text('Bateau'), findsNothing);
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('dit qu’un signalement disparu n’est plus disponible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheet((_) => Future.error(const ReportNotFoundException())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('n’est plus disponible'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('réessaie après une erreur réseau', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _sheet((_) {
        calls++;
        return calls == 1
            ? Future.error(TimeoutException('lent'))
            : Future.value(_report());
      }),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Vérifiez votre connexion'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Animal marin'), findsOneWidget);
  });

  testWidgets('demande de se reconnecter sur un 401', (tester) async {
    await tester.pumpWidget(
      _sheet(
        (_) => Future.error(const ApiException(statusCode: 401, body: '')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Reconnectez-vous'), findsOneWidget);
  });

  group('photo publiée (NW-151)', () {
    testWidgets('affiche la photo d’un autre compte et l’agrandit', (
      tester,
    ) async {
      final urls = <String>[];
      await tester.pumpWidget(
        _sheet(
          (_) async => _report(photo: _uploaded('https://s3.test/a?sig=1')),
          loadPhoto: (url) async {
            urls.add(url);
            return _png;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(urls, ['https://s3.test/a?sig=1']);
      expect(find.text('Envoyée'), findsNothing);
      final photo = find.bySemanticsLabel('Agrandir la photo');
      expect(photo, findsOneWidget);

      await tester.ensureVisible(photo);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.byType(ReportPhotoViewer), findsOneWidget);
    });

    testWidgets('chargement lent : indicateur à la place de la photo', (
      tester,
    ) async {
      final download = Completer<Uint8List>();
      await tester.pumpWidget(
        _sheet(
          (_) async => _report(photo: _uploaded('https://s3.test/a')),
          loadPhoto: (_) => download.future,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Chargement de la photo'), findsOneWidget);
      expect(find.text('Animal marin'), findsOneWidget);

      download.complete(_png);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Chargement de la photo'), findsNothing);
      expect(find.bySemanticsLabel('Agrandir la photo'), findsOneWidget);
    });

    testWidgets('erreur réseau puis « Réessayer » avec une URL neuve', (
      tester,
    ) async {
      var loads = 0;
      final urls = <String>[];
      await tester.pumpWidget(
        _sheet(
          (_) async {
            loads++;
            return _report(photo: _uploaded('https://s3.test/a?v=$loads'));
          },
          loadPhoto: (url) async {
            urls.add(url);
            if (urls.length == 1) throw http.ClientException('hors ligne');
            return _png;
          },
        ),
      );
      await tester.pumpAndSettle();

      const message = 'Photo indisponible. Vérifiez votre connexion.';
      expect(find.text(message), findsOneWidget);

      await tester.ensureVisible(find.text('Réessayer'));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(urls, ['https://s3.test/a?v=1', 'https://s3.test/a?v=2']);
      expect(find.text(message), findsNothing);
      expect(find.bySemanticsLabel('Agrandir la photo'), findsOneWidget);
    });

    testWidgets('URL expirée : relit la fiche puis affiche la photo', (
      tester,
    ) async {
      var loads = 0;
      final urls = <String>[];
      await tester.pumpWidget(
        _sheet(
          (_) async {
            loads++;
            return _report(photo: _uploaded('https://s3.test/a?v=$loads'));
          },
          loadPhoto: (url) async {
            urls.add(url);
            if (url.endsWith('v=1')) throw _storage(403);
            return _png;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(urls, ['https://s3.test/a?v=1', 'https://s3.test/a?v=2']);
      expect(find.text('Accès à la photo refusé.'), findsNothing);
      expect(find.bySemanticsLabel('Agrandir la photo'), findsOneWidget);
    });

    testWidgets('refus avec une URL neuve : affiché, sans boucle', (
      tester,
    ) async {
      var downloads = 0;
      await tester.pumpWidget(
        _sheet(
          (_) async => _report(photo: _uploaded('https://s3.test/a')),
          loadPhoto: (_) async {
            downloads++;
            throw _storage(403);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(downloads, 2);
      expect(find.text('Accès à la photo refusé.'), findsOneWidget);
      expect(find.bySemanticsLabel('Agrandir la photo'), findsNothing);
    });

    testWidgets('photo masquée entre-temps : pas de « Réessayer »', (
      tester,
    ) async {
      var loads = 0;
      await tester.pumpWidget(
        _sheet((_) async {
          loads++;
          return _report(
            photo: _uploaded(loads == 1 ? 'https://s3.test/a' : null),
          );
        }, loadPhoto: (_) async => throw _storage(403)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cette photo n’est plus disponible.'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('session expirée en relisant la fiche', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        _sheet((_) async {
          loads++;
          if (loads > 1) throw const ApiException(statusCode: 401, body: '');
          return _report(photo: _uploaded('https://s3.test/a'));
        }, loadPhoto: (_) async => throw _storage(403)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Votre session a expiré. Reconnectez-vous.'),
        findsOneWidget,
      );
    });

    testWidgets('photo envoyée mais plus servie', (tester) async {
      await tester.pumpWidget(
        _sheet((_) async => _report(photo: _uploaded(null))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.bySemanticsLabel('Chargement de la photo'), findsNothing);
    });
  });
}

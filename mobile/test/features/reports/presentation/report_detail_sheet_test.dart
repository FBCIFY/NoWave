import 'dart:async';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Fiche seule dans un écran, avec une heure fixe.
Widget _sheet(Future<ReportDetail> Function(String id) load) => MaterialApp(
  home: Scaffold(
    body: ReportDetailSheet(
      reportId: 'report-id',
      loadReport: load,
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
}

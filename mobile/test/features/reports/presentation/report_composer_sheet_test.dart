import 'dart:async';

import 'package:blueway/features/reports/presentation/report_composer_sheet.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/core/api/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('garde le texte et le focus quand le clavier masque le repère', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget sheetWithInsets(double keyboardHeight) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              if (keyboardHeight == 0)
                const Positioned(top: 0, child: SizedBox(width: 1, height: 1)),
              const Positioned(
                key: ValueKey('report-composer'),
                left: 0,
                right: 0,
                bottom: 0,
                child: ReportComposerSheet(onClose: _noop),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(sheetWithInsets(0));
    expect(find.byTooltip('Animal marin'), findsOneWidget);
    expect(find.byTooltip('Obstacle'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      ReportComposerSheet.heightFor(const MediaQueryData(size: Size(390, 844))),
      300,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      'Un commentaire sur deux lignes\navec une précision',
    );
    await tester.pumpWidget(sheetWithInsets(300));
    expect(
      find.text('Un commentaire sur deux lignes\navec une précision'),
      findsOneWidget,
    );

    expect(find.byTooltip('Animal marin'), findsOneWidget);
    expect(find.byTooltip('Obstacle'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Le clavier reste actif');
    expect(find.text('Le clavier reste actif'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    final button = find.widgetWithText(FilledButton, 'Publier le signalement');
    expect(button, findsOneWidget);
    expect(tester.getBottomLeft(button).dy, lessThan(844 - 300));
    expect(
      ReportComposerSheet.heightFor(
        const MediaQueryData(
          size: Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
      ),
      300,
    );

    await tester.pumpWidget(sheetWithInsets(0));
    expect(find.byTooltip('Animal marin'), findsOneWidget);
  });

  testWidgets('publie la catégorie et le commentaire, puis permet un réessai', (
    tester,
  ) async {
    var attempts = 0;
    ReportCategory? submittedCategory;
    String? submittedDescription;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportComposerSheet(
            onClose: _noop,
            onPublish: (category, description) async {
              attempts++;
              submittedCategory = category;
              submittedDescription = description;
              if (attempts == 1) {
                throw const ApiException(statusCode: 409, body: 'conflit');
              }
            },
          ),
        ),
      ),
    );

    final publish = find.text('Publier le signalement');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Pollution'));
    await tester.enterText(find.byType(TextField), '  Pollution visible  ');
    await tester.tap(publish);
    await tester.pump();
    expect(attempts, 1);
    expect(submittedCategory, ReportCategory.pollution);
    expect(submittedDescription, 'Pollution visible');
    expect(
      find.text('Ce signalement a changé depuis le premier envoi.'),
      findsOneWidget,
    );

    await tester.tap(publish);
    await tester.pump();
    expect(attempts, 2);
    expect(
      find.text('Ce signalement a changé depuis le premier envoi.'),
      findsNothing,
    );
  });

  testWidgets('affiche la photo et l’estimation dans l’en-tête', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReportComposerSheet(
              onClose: _noop,
              photo: img.encodeJpg(img.Image(width: 4, height: 4)),
              subtitle: 'Estimé à 120 m · ajustez si besoin',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Nouveau signalement'), findsOneWidget);
    expect(find.text('Estimé à 120 m · ajustez si besoin'), findsOneWidget);
  });

  testWidgets('envoie la photo après la publication, puis réessaie', (
    tester,
  ) async {
    var publishes = 0;
    var uploads = 0;
    var closes = 0;
    Completer<void>? firstUpload;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportComposerSheet(
            onClose: () => closes++,
            onPublish: (_, _) async => publishes++,
            onUploadPhoto: () {
              uploads++;
              if (uploads == 1) {
                firstUpload = Completer<void>();
                return firstUpload!.future;
              }
              return Future.value();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Pollution'));
    await tester.pump();
    await tester.tap(find.text('Publier le signalement'));
    await tester.pump();
    expect(publishes, 1);
    expect(uploads, 1);
    expect(find.text('Signalement publié'), findsOneWidget);
    expect(find.text('Envoi de la photo…'), findsOneWidget);
    // Publié : plus de croix, qui laissait croire à une annulation.
    expect(find.byTooltip('Fermer'), findsNothing);

    firstUpload!.completeError(
      const ApiException(statusCode: 404, body: 'Not Found'),
    );
    await tester.pump();
    expect(find.text('Signalement publié'), findsOneWidget);
    expect(
      find.text('Photo non envoyée : envoi indisponible sur ce serveur.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Fermer'), findsNothing);
    expect(find.text('Publier le signalement'), findsNothing);

    await tester.tap(find.text('Réessayer l’envoi'));
    await tester.pump();
    expect(publishes, 1);
    expect(uploads, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportComposerSheet(
            key: const ValueKey('second'),
            onClose: () => closes++,
            onPublish: (_, _) async {},
            onUploadPhoto: () async =>
                throw const ApiException(statusCode: 503, body: ''),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Obstacle'));
    await tester.pump();
    await tester.tap(find.text('Publier le signalement'));
    await tester.pump();
    expect(find.text('Photo non envoyée. Réessayez.'), findsOneWidget);
    await tester.tap(find.text('Terminer sans photo'));
    expect(closes, 1);
  });
}

void _noop() {}

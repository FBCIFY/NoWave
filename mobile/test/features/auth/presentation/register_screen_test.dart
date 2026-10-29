import 'dart:async';

import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/auth/presentation/register_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFirebaseAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(firebaseAuth: _FakeFirebaseAuth());

  final signUps = <(String, String)>[];
  int verificationEmails = 0;
  Object? error;
  Completer<void>? pending;

  @override
  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    signUps.add((email, password));
    await pending?.future;
    if (error != null) throw error!;
    return _FakeCredential();
  }

  @override
  Future<void> sendEmailVerification() async => verificationEmails++;
}

Finder _field(String label) => find.ancestor(
  of: find.text(label.toUpperCase()),
  matching: find.byType(Column),
);

Finder _input(String label) =>
    find.descendant(of: _field(label).first, matching: find.byType(TextField));

bool _hasFocus(WidgetTester tester, String label) =>
    tester.widget<TextField>(_input(label)).focusNode?.hasFocus ?? false;

Future<void> _pumpRegister(
  WidgetTester tester,
  _FakeAuthService auth, {
  VoidCallback? onBack,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RegisterScreen(authService: auth, onBack: onBack ?? () {}),
    ),
  );
}

Future<void> _enterEmail(WidgetTester tester, String email) async {
  await tester.enterText(_input('E-mail'), email);
  await tester.tap(find.text('Suivant'));
  await tester.pumpAndSettle();
}

Future<void> _enterPasswords(
  WidgetTester tester,
  String password,
  String confirmation,
) async {
  await tester.enterText(_input('Mot de passe'), password);
  await tester.enterText(_input('Confirmer le mot de passe'), confirmation);
  await tester.tap(find.text('Créer mon compte'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('e-mail, puis les deux mots de passe, puis création du compte', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await _pumpRegister(tester, auth);
    expect(find.text('ÉTAPE 1 SUR 3'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);

    await _enterEmail(tester, 'marin@example.com');
    expect(find.text('ÉTAPE 2 SUR 3'), findsOneWidget);
    expect(find.textContaining('marin@example.com'), findsOneWidget);
    expect(_hasFocus(tester, 'Mot de passe'), isTrue);

    await _enterPasswords(tester, '12345', '12345');
    expect(find.text('Au moins 6 caractères.'), findsOneWidget);

    await _enterPasswords(tester, 'secret1', 'secret2');
    expect(
      find.text('Les mots de passe ne correspondent pas.'),
      findsOneWidget,
    );
    expect(auth.signUps, isEmpty);

    final pending = auth.pending = Completer<void>();
    await tester.enterText(_input('Confirmer le mot de passe'), 'secret1');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    // Retour bloqué pendant la réponse de Firebase.
    await tester.tap(find.byTooltip('Retour'));
    await tester.pump();
    expect(find.text('ÉTAPE 2 SUR 3'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(auth.signUps, [('marin@example.com', 'secret1')]);
    expect(auth.verificationEmails, 1);
  });

  testWidgets(
    'validé au clavier, le clavier reste ouvert sur le mot de passe',
    (tester) async {
      await _pumpRegister(tester, _FakeAuthService());

      await tester.showKeyboard(_input('E-mail'));
      await tester.enterText(_input('E-mail'), 'marin@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(find.text('ÉTAPE 2 SUR 3'), findsOneWidget);
      expect(_hasFocus(tester, 'Mot de passe'), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets('adresse déjà utilisée : retour à la page de l’e-mail', (
    tester,
  ) async {
    final auth = _FakeAuthService()
      ..error = FirebaseAuthException(code: 'email-already-in-use');
    await _pumpRegister(tester, auth);

    await _enterEmail(tester, 'marin@example.com');
    await _enterPasswords(tester, 'secret1', 'secret1');

    expect(find.text('ÉTAPE 1 SUR 3'), findsOneWidget);
    expect(
      find.text('Un compte utilise déjà cette adresse e-mail.'),
      findsOneWidget,
    );

    // Corriger l'adresse efface le message ; les mots de passe sont gardés.
    await tester.enterText(_input('E-mail'), 'autre@example.com');
    await tester.pump();
    expect(
      find.text('Un compte utilise déjà cette adresse e-mail.'),
      findsNothing,
    );
    auth.error = null;
    await _enterEmail(tester, 'autre@example.com');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(auth.signUps.last, ('autre@example.com', 'secret1'));
  });

  testWidgets('autre refus de Firebase : on reste sur les mots de passe', (
    tester,
  ) async {
    final auth = _FakeAuthService()
      ..error = FirebaseAuthException(code: 'network-request-failed');
    await _pumpRegister(tester, auth);

    await _enterEmail(tester, 'marin@example.com');
    await _enterPasswords(tester, 'secret1', 'secret1');

    expect(find.text('ÉTAPE 2 SUR 3'), findsOneWidget);
    expect(find.text('Connexion réseau indisponible.'), findsOneWidget);
  });

  testWidgets('retour : page de l’e-mail, puis connexion', (tester) async {
    var backs = 0;
    await _pumpRegister(tester, _FakeAuthService(), onBack: () => backs++);

    await _enterEmail(tester, 'marin@example.com');
    expect(find.text('ÉTAPE 2 SUR 3'), findsOneWidget);

    // Bouton retour du téléphone.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 1 SUR 3'), findsOneWidget);
    expect(backs, 0);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(backs, 1);

    await tester.tap(find.text('Se connecter'));
    expect(backs, 2);
  });
}

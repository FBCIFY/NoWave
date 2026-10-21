import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/auth/presentation/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFirebaseAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(firebaseAuth: _FakeFirebaseAuth());

  String? sentEmail;
  Object? error;

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    sentEmail = email;
    if (error != null) throw error!;
  }
}

void main() {
  testWidgets('préremplit l’adresse et revient à la connexion', (tester) async {
    final authService = _FakeAuthService();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(emailField.controller?.text, 'test@example.com');

    await tester.tap(find.text('Envoyer le lien'));
    await tester.pumpAndSettle();

    expect(authService.sentEmail, 'test@example.com');
    expect(find.textContaining('Si un compte existe'), findsOneWidget);

    await tester.tap(find.text('Retour à la connexion'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
  });

  testWidgets('refuse une adresse invalide sans appeler Firebase', (
    tester,
  ) async {
    final authService = _FakeAuthService();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'adresse-invalide');
    await tester.tap(find.text('Envoyer le lien'));
    await tester.pump();

    expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
    expect(authService.sentEmail, isNull);
  });

  testWidgets('affiche une erreur réseau et permet de réessayer', (
    tester,
  ) async {
    final authService = _FakeAuthService()
      ..error = FirebaseAuthException(code: 'network-request-failed');

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'test@example.com');
    await tester.tap(find.text('Envoyer le lien'));
    await tester.pump();

    expect(find.text('Connexion réseau indisponible.'), findsOneWidget);

    authService.error = null;
    await tester.tap(find.text('Envoyer le lien'));
    await tester.pump();

    expect(find.textContaining('Si un compte existe'), findsOneWidget);
  });

  testWidgets('titre à la même hauteur que « Bienvenue », avant et après '
      'l’envoi', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authService = _FakeAuthService();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );
    final signInTitle = tester.getTopLeft(find.text('Bienvenue')).dy;

    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Mot de passe oublié')).dy, signInTitle);

    await tester.enterText(find.byType(TextFormField), 'test@example.com');
    await tester.tap(find.text('Envoyer le lien'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Mot de passe oublié')).dy, signInTitle);
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import 'widgets/auth_layout.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

/// Création du compte Firebase, puis envoi de l'e-mail de vérification.
///
/// Une fois le compte créé, `AuthGate` affiche l'écran de vérification.
class RegisterScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onBack;

  const RegisterScreen({super.key, required this.authService, this.onBack});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmation = _confirmationController.text;

    if (email.isEmpty || password.isEmpty || confirmation.isEmpty) {
      setState(() {
        _errorMessage = 'Tous les champs sont obligatoires.';
      });
      return;
    }

    if (password != confirmation) {
      setState(() {
        _errorMessage = 'Les mots de passe ne correspondent pas.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.signUp(email: email, password: password);

      await widget.authService.sendEmailVerification();

      if (!mounted) return;

      if (widget.onBack == null) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _messageForFirebaseError(error.code);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Impossible de créer le compte pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _messageForFirebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Un compte utilise déjà cette adresse e-mail.';
      case 'invalid-email':
        return 'L’adresse e-mail est invalide.';
      case 'weak-password':
        return 'Le mot de passe n’est pas assez sécurisé.';
      case 'operation-not-allowed':
        return 'L’inscription par e-mail est indisponible.';
      case 'network-request-failed':
        return 'Connexion réseau indisponible.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      default:
        return 'Impossible de créer le compte pour le moment.';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Créer un compte',
      subtitle: 'Rejoindre la communauté NoWave',
      showBackButton: true,
      onBack: widget.onBack,
      centerContent: false,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              controller: _emailController,
              label: 'E-mail',
              hintText: 'votre@email.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _passwordController,
              label: 'Mot de passe',
              hintText: '••••••••',
              icon: Icons.lock_outline,
              obscureText: true,
              enableInteractiveSelection: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _confirmationController,
              label: 'Confirmer le mot de passe',
              hintText: '••••••••',
              icon: Icons.lock_outline,
              obscureText: true,
              enableInteractiveSelection: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) {
                if (!_isLoading) {
                  _register();
                }
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFFCA5A5),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFFECACA),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            AuthPrimaryButton(
              label: 'Créer mon compte',
              onPressed: _isLoading ? null : _register,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Déjà un compte ? ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30),
                    fontSize: 12,
                  ),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (widget.onBack case final onBack?) {
                            onBack();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF22D3EE)
                        .withValues(alpha: 0.70),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Se connecter',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

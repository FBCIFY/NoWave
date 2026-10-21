import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import 'widgets/auth_layout.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

/// Demande d'un lien de réinitialisation du mot de passe (envoyé par Firebase).
///
/// Le message de confirmation est le même que le compte existe ou non, pour
/// ne pas révéler quelles adresses sont inscrites.
class ResetPasswordScreen extends StatefulWidget {
  final AuthService authService;
  final String initialEmail;

  const ResetPasswordScreen({
    super.key,
    required this.authService,
    this.initialEmail = '',
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _isSent = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail.trim());
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.sendPasswordResetEmail(_emailController.text);

      if (!mounted) return;
      setState(() => _isSent = true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      if (error.code == 'user-not-found') {
        setState(() => _isSent = true);
        return;
      }

      setState(() {
        _errorMessage = switch (error.code) {
          'invalid-email' => 'L’adresse e-mail est invalide.',
          'too-many-requests' => 'Trop de tentatives. Réessayez plus tard.',
          'network-request-failed' => 'Connexion réseau indisponible.',
          _ => 'Impossible d’envoyer le courriel pour le moment.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible d’envoyer le courriel pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Mot de passe oublié',
      subtitle: 'Réinitialiser votre accès NoWave',
      showBackButton: true,
      child: _isSent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  color: Color(0xFF22D3EE),
                  size: 48,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Si un compte existe pour cette adresse, '
                  'vous recevrez un lien de réinitialisation. '
                  'Vérifiez également vos courriers indésirables.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 28),
                AuthPrimaryButton(
                  label: 'Retour à la connexion',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Saisissez l’adresse e-mail de votre compte. '
                    'Nous vous enverrons un lien pour choisir '
                    'un nouveau mot de passe.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  AuthTextField(
                    controller: _emailController,
                    label: 'E-mail',
                    hintText: 'votre@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Saisissez votre adresse e-mail.';
                      }
                      if (!value.contains('@')) {
                        return 'Saisissez une adresse e-mail valide.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _sendResetEmail();
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  AuthPrimaryButton(
                    label: 'Envoyer le lien',
                    onPressed: _isLoading ? null : _sendResetEmail,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
    );
  }
}

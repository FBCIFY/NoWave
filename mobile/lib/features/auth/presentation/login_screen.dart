import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import 'widgets/auth_layout.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

/// Connexion par e-mail et mot de passe.
///
/// En cas de succès, rien à faire ici : `AuthGate` détecte la session et
/// change d'écran. Donne aussi accès à l'inscription et au mot de passe oublié.
class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onRegister;

  const LoginScreen({super.key, required this.authService, this.onRegister});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _messageForFirebaseError(error.code);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Impossible de vous connecter pour le moment.';
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
      case 'invalid-email':
        return 'L’adresse e-mail est invalide.';
      case 'invalid-credential' || 'user-not-found' || 'wrong-password':
        return 'L’adresse e-mail ou le mot de passe est incorrect.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'network-request-failed':
        return 'Connexion réseau indisponible.';
      default:
        return 'Impossible de vous connecter pour le moment.';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'nowave',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
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
              ),
              const SizedBox(height: 20),
              AuthTextField(
                controller: _passwordController,
                label: 'Mot de passe',
                hintText: '••••••••',
                icon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Saisissez votre mot de passe.';
                  }

                  return null;
                },
                onFieldSubmitted: (_) {
                  if (!_isLoading) {
                    _signIn();
                  }
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => ResetPasswordScreen(
                                authService: widget.authService,
                                initialEmail: _emailController.text,
                              ),
                            ),
                          );
                        },
                  child: const Text('Mot de passe oublié ?'),
                ),
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
              const SizedBox(height: 28),
              AuthPrimaryButton(
                label: 'Connexion',
                onPressed: _isLoading ? null : _signIn,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Pas encore de compte ? ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 12,
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            if (widget.onRegister case final onRegister?) {
                              onRegister();
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => RegisterScreen(
                                    authService: widget.authService,
                                  ),
                                ),
                              );
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
                      'S’inscrire',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

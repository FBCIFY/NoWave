import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../profile/presentation/widgets/onboarding_progress.dart';
import '../data/auth_service.dart';
import 'widgets/auth_photo_layout.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

/// Une page par étape de l'inscription, dans l'ordre. La dernière étape, la
/// vérification de l'e-mail, est l'écran suivant.
enum _Page { email, password }

/// Inscription en plusieurs pages, comme le premier passage du profil :
/// l'e-mail, puis le mot de passe et sa confirmation. La photo, le logo et la
/// progression restent fixes : seules les pages glissent.
///
/// Le compte Firebase est créé à la fin, puis l'e-mail de vérification est
/// envoyé. `AuthGate` affiche alors l'écran de vérification, dernière étape.
/// Si Firebase refuse l'adresse (déjà utilisée ou invalide), l'inscription
/// revient à la page de l'e-mail avec le message.
class RegisterScreen extends StatefulWidget {
  /// Étapes de l'inscription : e-mail, mot de passe, vérification de
  /// l'e-mail.
  static const stepCount = 3;

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

  _Page _page = _Page.email;
  bool _isLoading = false;
  String? _errorMessage;

  void _goTo(_Page page, {String? errorMessage}) {
    setState(() {
      _page = page;
      _errorMessage = errorMessage;
    });
  }

  void _back() {
    if (_isLoading) return;

    if (_page == _Page.password) {
      FocusManager.instance.primaryFocus?.unfocus();
      _goTo(_Page.email);
    } else if (widget.onBack case final onBack?) {
      onBack();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _submitEmail(FormState form) {
    if (!form.validate()) return;
    // Le champ du mot de passe prend le focus en arrivant : le clavier reste
    // ouvert.
    _goTo(_Page.password);
  }

  Future<void> _register(FormState form) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!form.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await widget.authService.sendEmailVerification();

      if (!mounted) return;

      if (widget.onBack == null) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      final message = _messageForFirebaseError(error.code);
      switch (error.code) {
        case 'email-already-in-use' || 'invalid-email':
          _goTo(_Page.email, errorMessage: message);
        default:
          setState(() => _errorMessage = message);
      }
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
    final (title, subtitle, child) = switch (_page) {
      _Page.email => (
        'Créer un compte',
        'Rejoignez la communauté NoWave.',
        _buildEmail(),
      ),
      _Page.password => (
        'Choisissez un mot de passe',
        'Pour le compte ${_emailController.text.trim()}. Au moins 6 '
            'caractères.',
        _buildPassword(),
      ),
    };

    // Le bouton retour du téléphone revient à la page précédente, puis à la
    // connexion.
    return PopScope(
      canPop: _page == _Page.email && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthPhotoLayout(
        header: OnboardingProgress(
          step: _page.index + 1,
          stepCount: RegisterScreen.stepCount,
        ),
        page: _page.index,
        title: title,
        subtitle: subtitle,
        showBackButton: true,
        onBack: _back,
        child: AutofillGroup(child: child),
      ),
    );
  }

  Widget _buildEmail() {
    // Pas de GlobalKey pour le formulaire : pendant le glissement, la page qui
    // part et celle qui arrive peuvent être affichées en même temps.
    return Form(
      child: Builder(
        builder: (context) {
          void submit() {
            if (!_isLoading) _submitEmail(Form.of(context));
          }

          return Column(
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
                onChanged: (_) => _clearError(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Saisissez votre adresse e-mail.';
                  }

                  if (!value.contains('@')) {
                    return 'Saisissez une adresse e-mail valide.';
                  }

                  return null;
                },
                // Le champ garde le focus jusqu'à la page suivante : le
                // clavier ne se ferme pas entre les deux.
                onEditingComplete: submit,
              ),
              ..._buildError(),
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: 'Suivant',
                onPressed: _isLoading ? null : submit,
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Déjà un compte ? ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _back,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF22D3EE),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Se connecter',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPassword() {
    return Form(
      child: Builder(
        builder: (context) {
          void submit() {
            if (!_isLoading) _register(Form.of(context));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _passwordController,
                label: 'Mot de passe',
                hintText: '••••••••',
                icon: Icons.lock_outline,
                obscureText: true,
                enableInteractiveSelection: false,
                autofocus: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => _clearError(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Choisissez un mot de passe.';
                  }

                  // Minimum imposé par Firebase.
                  if (value.length < 6) {
                    return 'Au moins 6 caractères.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _confirmationController,
                label: 'Confirmer le mot de passe',
                hintText: '••••••••',
                icon: Icons.lock_outline,
                obscureText: true,
                enableInteractiveSelection: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => _clearError(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirmez le mot de passe.';
                  }

                  if (value != _passwordController.text) {
                    return 'Les mots de passe ne correspondent pas.';
                  }

                  return null;
                },
                onFieldSubmitted: (_) => submit(),
              ),
              ..._buildError(),
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: 'Créer mon compte',
                onPressed: _isLoading ? null : submit,
                isLoading: _isLoading,
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildError() => [
    if (_errorMessage case final message?) ...[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFCA5A5), size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFFFECACA), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ],
  ];
}

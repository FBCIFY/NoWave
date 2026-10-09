import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_exception.dart';
import '../data/profile_service.dart';
import '../domain/user_profile.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../../auth/presentation/widgets/auth_primary_button.dart';
import '../../auth/presentation/widgets/auth_text_field.dart';

/// Création du profil NoWave (nom d'utilisateur) au premier passage.
///
/// Le backend répond 409 si le nom est pris et 403 si l'e-mail n'est pas
/// vérifié. Il répond aussi 409 si ce compte a déjà un profil : une première
/// création a abouti sans que sa réponse arrive (NW-153). L'écran relit alors
/// le profil du compte et continue avec lui, sans en créer d'autre.
/// Un 409 `email_already_registered` signifie que l'e-mail appartient au
/// profil d'un autre compte : pas de relecture, un message suffit (NW-155).
class ProfileSetupScreen extends StatefulWidget {
  final ProfileService profileService;
  final VoidCallback onProfileCreated;
  final Future<void> Function() onSignOut;

  const ProfileSetupScreen({
    super.key,
    required this.profileService,
    required this.onProfileCreated,
    required this.onSignOut,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _createProfile() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.profileService.createProfile(
        username: _usernameController.text,
      );

      if (!mounted) return;

      widget.onProfileCreated();
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == 'user_already_exists') {
        await _continueWithExistingProfile();
        return;
      }

      setState(() {
        _errorMessage = switch (error.code) {
          'username_already_exists' => 'Ce nom d’utilisateur est déjà utilisé.',
          'email_already_registered' =>
            'Cette adresse e-mail est déjà liée à un autre compte NoWave. '
                'Connectez-vous avec ce compte.',
          'email_not_verified' => 'Votre adresse e-mail doit être vérifiée.',
          'request_validation_error' => 'Vérifiez le nom d’utilisateur.',
          _ when error.statusCode == 409 => 'Impossible de créer ce profil.',
          _ when error.statusCode == 403 =>
            'Votre compte ne permet pas cette opération.',
          _ => 'Impossible de créer votre profil.',
        };
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Impossible de contacter le serveur. Réessayez plus tard.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Le profil existe déjà côté serveur : on le relit et on continue avec
  /// lui, quel que soit le nom saisi cette fois-ci. Une seule lecture par
  /// appui sur le bouton.
  Future<void> _continueWithExistingProfile() async {
    final UserProfile? profile;
    try {
      profile = await widget.profileService.getCurrentProfile();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Votre profil existe déjà mais n’a pas pu être chargé. Réessayez.';
      });
      return;
    }

    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _errorMessage = 'Impossible de créer votre profil. Réessayez.';
      });
      return;
    }

    widget.onProfileCreated();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.vertical -
        mediaQuery.viewInsets.bottom;

    final useCompactLayout = availableHeight < 600;

    return AuthLayout(
      title: 'Votre profil',
      centerContent: !useCompactLayout,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!useCompactLayout) ...[
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'Choisissez votre nom d’utilisateur',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: useCompactLayout ? 18 : 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!useCompactLayout) ...[
              const SizedBox(height: 8),
              Text(
                'Ce nom sera associé à votre profil NoWave.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
            ],
            SizedBox(height: useCompactLayout ? 16 : 28),
            AuthTextField(
              controller: _usernameController,
              label: 'Nom d’utilisateur',
              hintText: 'Votre nom public',
              icon: Icons.person_outline,
              maxLength: 100,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
              validator: (value) {
                final username = value?.trim() ?? '';

                if (username.isEmpty) {
                  return 'Choisissez un nom d’utilisateur.';
                }

                if (username.length > 100) {
                  return 'Le nom ne peut pas dépasser 100 caractères.';
                }

                if (RegExp(r'\s').hasMatch(username)) {
                  return 'Le nom d’utilisateur ne peut pas contenir d’espace.';
                }

                return null;
              },
              onFieldSubmitted: (_) {
                if (!_isLoading) {
                  _createProfile();
                }
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
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
              label: 'Créer mon profil',
              onPressed: _isLoading ? null : _createProfile,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading ? null : widget.onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.45),
              ),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}

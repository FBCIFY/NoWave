import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/text/capitalize_first_letter_formatter.dart';
import '../../auth/presentation/widgets/auth_photo_layout.dart';
import '../../auth/presentation/widgets/auth_primary_button.dart';
import '../../auth/presentation/widgets/auth_text_field.dart';
import '../data/profile_service.dart';
import '../domain/boat.dart';
import '../domain/user_profile.dart';
import 'profile_screen.dart' show UpdatePreferences;
import 'widgets/onboarding_progress.dart';

/// Une page par étape de [OnboardingProgress], dans l'ordre.
enum _Page { username, boatType, boatDetails, visibility, alerts }

/// Premier passage, sur un seul écran : nom d'utilisateur (création du
/// profil), bateau (type, puis nom et pavillon), ce qui s'affiche sur les
/// signalements, puis les alertes. La photo, le logo et la progression restent
/// fixes : seules les pages glissent, et chacune peut revenir à la précédente.
///
/// Seul le nom d'utilisateur est obligatoire ; le reste se passe et reste
/// modifiable depuis le profil.
///
/// Création du profil : le backend répond 409 si le nom est pris et 403 si
/// l'e-mail n'est pas vérifié. Il répond aussi 409 si ce compte a déjà un
/// profil : une première création a abouti sans que sa réponse arrive
/// (NW-153). L'écran relit alors le profil du compte et continue avec lui,
/// sans en créer d'autre. Un 409 `email_already_registered` signifie que
/// l'e-mail appartient au profil d'un autre compte : pas de relecture, un
/// message suffit (NW-155). En revenant au nom une fois le profil créé, un nom
/// changé est enregistré par un PATCH.
///
/// Aucun type de bateau n'est choisi d'avance : sans choix, aucun bateau n'est
/// créé. Le bateau est enregistré en quittant la page du nom et du pavillon ;
/// après un échec, la page peut être passée.
///
/// Les alertes sont expliquées avant d'afficher la demande d'autorisation du
/// téléphone.
class ProfileOnboardingScreen extends StatefulWidget {
  /// `null` tant que le profil n'existe pas : le parcours commence alors au
  /// nom d'utilisateur, sinon au bateau.
  final UserProfile? profile;
  final ProfileService profileService;

  /// Profil créé, ou nom changé en revenant en arrière.
  final ValueChanged<UserProfile> onProfileSaved;
  final UpdatePreferences onUpdatePreferences;
  final NotificationPermissionService notificationPermissions;
  final Future<void> Function() onSignOut;
  final VoidCallback onDone;

  const ProfileOnboardingScreen({
    super.key,
    required this.profile,
    required this.profileService,
    required this.onProfileSaved,
    required this.onUpdatePreferences,
    required this.notificationPermissions,
    required this.onSignOut,
    required this.onDone,
  });

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  late final _usernameController = TextEditingController(
    text: widget.profile?.username,
  );
  final _nameController = TextEditingController();
  final _flagController = TextEditingController();

  late _Page _page = widget.profile == null ? _Page.username : _Page.boatType;

  /// Dernier profil renvoyé par le backend : sert à n'envoyer que ce qui
  /// change.
  late UserProfile? _profile = widget.profile;
  BoatType? _type;
  Boat? _boat;
  late bool _showUserName = widget.profile?.showUserName ?? false;
  late bool _showBoatInfo = widget.profile?.showBoatInfo ?? false;

  bool _isLoading = false;
  String? _errorMessage;

  /// Un enregistrement a échoué : la page peut être passée.
  bool _failed = false;

  /// Parcours terminé : la carte prend le relais, plus rien ne se touche
  /// jusqu'à la fin du fondu.
  bool _done = false;

  void _goTo(_Page page) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _page = page;
      _errorMessage = null;
      _failed = false;
    });
  }

  void _back() {
    if (_isLoading || _done) return;
    _goTo(switch (_page) {
      _Page.username || _Page.boatType => _Page.username,
      _Page.boatDetails => _Page.boatType,
      _Page.visibility when _type != null => _Page.boatDetails,
      _Page.visibility => _Page.boatType,
      _Page.alerts => _Page.visibility,
    });
  }

  Future<void> _saveUsername(FormState form) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!form.validate()) {
      return;
    }

    final profile = _profile;
    // Retour sur la page sans changer le nom : rien à enregistrer.
    if (profile != null &&
        _usernameController.text.trim() == profile.username) {
      _goTo(_Page.boatType);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final saved = profile == null
          ? await widget.profileService.createProfile(
              username: _usernameController.text,
            )
          : await widget.profileService.updateUsername(
              _usernameController.text,
            );

      if (!mounted) return;

      _continueWith(saved);
    } on ApiException catch (error) {
      if (!mounted) return;

      if (profile == null && error.code == 'user_already_exists') {
        await _continueWithExistingProfile();
        return;
      }

      setState(() {
        _errorMessage = switch (error.code) {
          'username_already_exists' => 'Ce nom d’utilisateur est déjà utilisé.',
          'email_already_registered' =>
            'Cette adresse e-mail est déjà liée à un autre profil NoWave. '
                'Contactez le support.',
          'email_not_verified' => 'Votre adresse e-mail doit être vérifiée.',
          'request_validation_error' => 'Vérifiez le nom d’utilisateur.',
          _ when profile != null =>
            'Impossible d’enregistrer votre nom d’utilisateur.',
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

    _continueWith(profile);
  }

  void _continueWith(UserProfile profile) {
    if (_profile == null) {
      _showUserName = profile.showUserName;
      _showBoatInfo = profile.showBoatInfo;
    }
    _profile = profile;
    // Le nom enregistré, qui peut différer du nom saisi (profil relu).
    _usernameController.text = profile.username;
    widget.onProfileSaved(profile);
    _goTo(_Page.boatType);
  }

  void _skipBoat() {
    _type = null;
    _goTo(_Page.visibility);
  }

  Future<void> _saveBoat() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final flag = _flagController.text.trim();
    if (flag.isNotEmpty && flag.length != 2) {
      setState(() {
        _errorMessage =
            'Le pavillon est un code pays de deux lettres, par exemple FR.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final boat = await _sendBoat(create: _boat == null);
      if (!mounted) return;

      _boat = boat;
      _goTo(_Page.visibility);
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _failed = true;
        _errorMessage = error.code == 'request_validation_error'
            ? 'Vérifiez le nom et le pavillon du bateau.'
            : _boatErrorMessage;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _failed = true;
        _errorMessage = _boatErrorMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static const _boatErrorMessage =
      'Le bateau n’a pas pu être enregistré. Réessayez, ou passez : vous '
      'pourrez l’ajouter depuis votre profil.';

  Future<Boat> _sendBoat({required bool create}) async {
    try {
      return await widget.profileService.saveBoat(
        create: create,
        type: _type!,
        name: _nameController.text,
        flagCountry: _flagController.text,
      );
    } on ApiException catch (error) {
      // Une première création a abouti sans que sa réponse arrive : le
      // bateau existe déjà, on le met à jour.
      if (create && error.code == 'boat_already_exists') {
        return _sendBoat(create: false);
      }
      rethrow;
    }
  }

  /// N'envoie que les choix qui changent le profil. Sans bateau, la
  /// préférence du bateau n'est pas touchée.
  Future<void> _savePreferences() async {
    // Le profil existe : cette page vient après sa création.
    final profile = _profile!;
    final showUserName = _showUserName != profile.showUserName
        ? _showUserName
        : null;
    final showBoatInfo = _boat != null && _showBoatInfo != profile.showBoatInfo
        ? _showBoatInfo
        : null;

    if (showUserName == null && showBoatInfo == null) {
      _goTo(_Page.alerts);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _profile = await widget.onUpdatePreferences(
        showUserName: showUserName,
        showBoatInfo: showBoatInfo,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _failed = true;
        _errorMessage =
            'Vos choix n’ont pas pu être enregistrés. Réessayez, ou passez : '
            'vous pourrez les modifier depuis votre profil.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    _goTo(_Page.alerts);
  }

  Future<void> _enableAlerts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onUpdatePreferences(notificationsEnabled: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible d’activer les alertes. Réessayez.';
      });
      return;
    }

    try {
      await widget.notificationPermissions.request();
    } catch (_) {
      // La préférence est enregistrée : l'autorisation reste modifiable
      // depuis le profil.
    }

    // Le chargement continue jusqu'au changement d'écran.
    if (!mounted) return;
    _finish();
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    widget.onDone();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _flagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, child) = switch (_page) {
      _Page.username => ('Votre profil', null, _buildUsername()),
      _Page.boatType => (
        'Votre bateau',
        'Vous pourrez le modifier depuis votre profil.',
        _buildBoatType(),
      ),
      _Page.boatDetails => ('Nom et pavillon', null, _buildBoatDetails()),
      _Page.visibility => (
        'Sur vos signalements',
        'Choisissez ce que les autres marins voient quand vous signalez un '
            'danger. Par défaut, rien n’est affiché.',
        _buildVisibility(),
      ),
      _Page.alerts => (
        'Alertes à proximité',
        'NoWave vous prévient quand un danger est signalé près de vous en '
            'mer. Pour cela, l’app a besoin de vous envoyer des notifications.',
        _buildAlerts(),
      ),
    };

    return PopScope(
      canPop: _page == _Page.username,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthPhotoLayout(
        header: OnboardingProgress(
          step: _page.index + 1,
          stepCount: _Page.values.length,
        ),
        page: _page.index,
        title: title,
        subtitle: subtitle,
        showBackButton: _page != _Page.username,
        onBack: _back,
        child: child,
      ),
    );
  }

  Widget _buildUsername() {
    // Pas de GlobalKey pour le formulaire : pendant le glissement, la page qui
    // part et celle qui arrive peuvent être affichées en même temps.
    return Form(
      child: Builder(
        builder: (context) {
          void submit() {
            if (!_isLoading) _saveUsername(Form.of(context));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _usernameController,
                label: 'Nom d’utilisateur',
                hintText: 'Votre nom public',
                icon: Icons.person_outline,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [CapitalizeFirstLetterFormatter()],
                textInputAction: TextInputAction.done,
                onChanged: (_) => _clearError(),
                validator: (value) {
                  final username = value?.trim() ?? '';

                  if (username.isEmpty) {
                    return 'Choisissez un nom d’utilisateur.';
                  }

                  if (username.length > 100) {
                    return 'Le nom ne peut pas dépasser 100 caractères.';
                  }

                  return null;
                },
                onFieldSubmitted: (_) => submit(),
              ),
              ..._buildError(),
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: _profile == null ? 'Créer mon profil' : 'Suivant',
                onPressed: _isLoading ? null : submit,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 4),
              _SecondaryButton(
                label: 'Se déconnecter',
                onPressed: _isLoading ? null : widget.onSignOut,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoatType() {
    const types = BoatType.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < types.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          // Deux tuiles de même hauteur, même si un libellé passe sur deux
          // lignes.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final type in types.skip(i).take(2)) ...[
                  if (type != types[i]) const SizedBox(width: 8),
                  Expanded(
                    child: _BoatTypeTile(
                      type: type,
                      selected: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        AuthPrimaryButton(
          label: 'Suivant',
          onPressed: _type == null ? null : () => _goTo(_Page.boatDetails),
        ),
        // Un bateau déjà enregistré se supprime depuis le profil.
        if (_boat == null) ...[
          const SizedBox(height: 4),
          _SecondaryButton(
            label: 'Je n’ai pas de bateau',
            onPressed: _skipBoat,
          ),
        ],
      ],
    );
  }

  Widget _buildBoatDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthTextField(
          controller: _nameController,
          label: 'Nom du bateau (facultatif)',
          hintText: 'Ex. Belle Île',
          icon: Icons.directions_boat_outlined,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [CapitalizeFirstLetterFormatter()],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 8),
        AuthTextField(
          controller: _flagController,
          label: 'Pavillon (facultatif)',
          hintText: 'Code pays, ex. FR',
          icon: Icons.flag_outlined,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
            LengthLimitingTextInputFormatter(2),
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  newValue.copyWith(text: newValue.text.toUpperCase()),
            ),
          ],
          textInputAction: TextInputAction.done,
          onChanged: (_) => _clearError(),
          onFieldSubmitted: (_) {
            if (!_isLoading) _saveBoat();
          },
        ),
        ..._buildError(),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          label: 'Suivant',
          onPressed: _isLoading ? null : _saveBoat,
          isLoading: _isLoading,
        ),
        if (_failed) ...[
          const SizedBox(height: 4),
          _SecondaryButton(
            label: 'Passer',
            onPressed: _isLoading ? null : () => _goTo(_Page.visibility),
          ),
        ],
      ],
    );
  }

  Widget _buildVisibility() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VisibilitySwitch(
          label: 'Afficher mon nom d’utilisateur',
          description: 'Sinon, vos signalements restent anonymes.',
          value: _showUserName,
          onChanged: _isLoading
              ? null
              : (value) => setState(() => _showUserName = value),
        ),
        if (_boat != null) ...[
          const SizedBox(height: 8),
          _VisibilitySwitch(
            label: 'Afficher mon bateau',
            description:
                'Son nom et son type apparaissent avec vos '
                'signalements.',
            value: _showBoatInfo,
            onChanged: _isLoading
                ? null
                : (value) => setState(() => _showBoatInfo = value),
          ),
        ],
        ..._buildError(),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          label: 'Continuer',
          onPressed: _isLoading ? null : _savePreferences,
          isLoading: _isLoading,
        ),
        if (_failed) ...[
          const SizedBox(height: 4),
          _SecondaryButton(
            label: 'Passer',
            onPressed: _isLoading ? null : () => _goTo(_Page.alerts),
          ),
        ],
      ],
    );
  }

  Widget _buildAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vous pourrez changer d’avis à tout moment dans votre profil.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 11,
          ),
        ),
        ..._buildError(),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          label: 'Activer les alertes',
          onPressed: _isLoading || _done ? null : _enableAlerts,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 4),
        _SecondaryButton(
          label: 'Plus tard',
          onPressed: _isLoading || _done ? null : _finish,
        ),
      ],
    );
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  List<Widget> _buildError() => [
    if (_errorMessage case final message?) ...[
      const SizedBox(height: 12),
      _ErrorMessage(message),
    ],
  ];
}

class _BoatTypeTile extends StatelessWidget {
  final BoatType type;
  final bool selected;
  final VoidCallback onTap;

  const _BoatTypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? AppColors.cyan500.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? const BorderSide(color: AppColors.cyan500, width: 1.5)
              : BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: selected
                        ? AppColors.cyan500
                        : Colors.white.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      type.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisibilitySwitch extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _VisibilitySwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        // Toute la carte bascule l'interrupteur.
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: AppColors.cyan500,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  inactiveThumbColor: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.70),
        minimumSize: const Size(0, 36),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

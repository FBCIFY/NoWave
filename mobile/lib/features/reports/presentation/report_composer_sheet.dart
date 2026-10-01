import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/haptics/app_haptics.dart';
import '../domain/manual_report.dart';
import 'report_photo_viewer.dart';

/// Panneau du bas en mode signalement : catégorie, commentaire facultatif
/// (250 caractères max) et bouton Publier. L'envoi est fait par `MapScreen`.
/// [subtitle] guide le placement du point dans l'en-tête et disparaît une fois
/// le signalement publié. En mode photo, la miniature s'y ajoute, et
/// [onUploadPhoto] envoie le JPEG une fois le signalement publié. En cas
/// d'échec, l'utilisateur peut réessayer ou terminer sans photo. Une fois
/// publié, le bouton Fermer disparaît : il laissait croire à une annulation.
class ReportComposerSheet extends StatefulWidget {
  const ReportComposerSheet({
    super.key,
    required this.onClose,
    this.onPublish,
    this.onUploadPhoto,
    this.photo,
    this.subtitle,
  });

  final VoidCallback onClose;
  final Future<void> Function(ReportCategory category, String? description)?
  onPublish;
  final Future<void> Function()? onUploadPhoto;
  final Uint8List? photo;
  final String? subtitle;

  /// Hauteur réservée au panneau par la carte pour placer le marqueur : celle
  /// du formulaire sans message. Un message d'erreur ou d'envoi agrandit le
  /// panneau vers le haut sans déplacer le marqueur.
  static double heightFor(MediaQueryData mediaQuery) =>
      math.min(_formHeight, _maxHeightFor(mediaQuery));

  // En-tête 12 + 48, catégories 12 + 64, commentaire 12 + 48,
  // bouton 12 + 48 + 16.
  static const _formHeight = 272.0;

  static double _maxHeightFor(MediaQueryData mediaQuery) => math.max(
    0,
    mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.viewInsets.bottom -
        24,
  );

  @override
  State<ReportComposerSheet> createState() => _ReportComposerSheetState();
}

class _ReportComposerSheetState extends State<ReportComposerSheet> {
  final _commentController = TextEditingController();
  ReportCategory? _category;
  bool _isSubmitting = false;
  bool _isPublished = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;

  bool get _isBusy => _isSubmitting || _isUploadingPhoto;

  Future<void> _publish() async {
    final category = _category;
    final onPublish = widget.onPublish;
    if (_isSubmitting || category == null || onPublish == null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final description = _commentController.text.trim();
      await onPublish(category, description.isEmpty ? null : description);
      // En mode photo, le succès attend l'envoi de la photo.
      if (widget.onUploadPhoto == null) AppHaptics.success();
    } on ApiException catch (error) {
      AppHaptics.failure();
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForApiError(error);
      });
      return;
    } catch (_) {
      AppHaptics.failure();
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de publier. Vérifiez votre connexion.';
      });
      return;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    if (!mounted || widget.onUploadPhoto == null) return;
    setState(() => _isPublished = true);
    await _uploadPhoto();
  }

  Future<void> _uploadPhoto() async {
    final onUploadPhoto = widget.onUploadPhoto;
    if (_isUploadingPhoto || onUploadPhoto == null) return;

    setState(() {
      _isUploadingPhoto = true;
      _errorMessage = null;
    });
    try {
      await onUploadPhoto();
      AppHaptics.success();
    } on ApiException catch (error) {
      AppHaptics.failure();
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForPhotoError(error);
      });
    } catch (_) {
      AppHaptics.failure();
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Photo non envoyée : vérifiez votre connexion.';
      });
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  String _messageForApiError(ApiException error) {
    if (error.statusCode == 404) {
      if (error.code == 'user_not_found') {
        return 'Votre profil NoWave est introuvable.';
      }

      return 'Publication indisponible sur ce serveur.';
    }
    return switch (error.statusCode) {
      400 || 422 => 'Vérifiez les données du signalement.',
      401 => 'Votre session a expiré. Reconnectez-vous.',
      403 => 'Votre compte ne peut pas publier de signalement.',
      409 => 'Ce signalement a changé depuis le premier envoi.',
      _ => 'Impossible de publier. Réessayez.',
    };
  }

  // Le signalement est déjà publié : seul l'envoi de la photo a échoué.
  String _messageForPhotoError(ApiException error) {
    return switch (error.statusCode) {
      401 => 'Photo non envoyée : session expirée. Reconnectez-vous.',
      403 => 'Photo non envoyée : votre compte ne peut pas en envoyer.',
      404 => 'Photo non envoyée : envoi indisponible sur ce serveur.',
      413 || 415 || 422 => 'Photo non envoyée : refusée par le serveur.',
      _ => 'Photo non envoyée. Réessayez.',
    };
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    // Espacements : 16 contre les bords du panneau, 12 entre deux blocs.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        mediaQuery.viewInsets.bottom + 12,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: ReportComposerSheet._maxHeightFor(mediaQuery),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x290D2238),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _categoryPicker(),
                      const SizedBox(height: 12),
                      _commentField(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isPublished) ...[
                      _publishedStatus(),
                      const SizedBox(height: 12),
                    ] else if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _errorColor),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_isPublished && _errorMessage != null)
                      _photoRetryActions()
                    else
                      FilledButton(
                        onPressed:
                            _category == null ||
                                _isLocked ||
                                widget.onPublish == null
                            ? null
                            : _publish,
                        style: _primaryButtonStyle,
                        // Grisé sans explication, le bouton laissait chercher
                        // ce qui manquait : son libellé dit quoi faire.
                        child: _isBusy
                            ? const _ButtonSpinner()
                            : Text(
                                _category == null
                                    ? 'Choisissez une catégorie'
                                    : 'Publier le signalement',
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isLocked => _isBusy || _isPublished;

  static const _textColor = Color(0xFF243243);
  static const _mutedColor = Color(0xFF687789);
  static const _borderColor = Color(0xFFDDE3EA);
  static const _accentColor = Color(0xFF0DB8D5);
  static const _errorColor = Color(0xFFAF3942);

  // Même arrondi que les champs et boutons du thème.
  static const _controlRadius = BorderRadius.all(Radius.circular(14));

  static final _primaryButtonStyle = FilledButton.styleFrom(
    minimumSize: const ui.Size.fromHeight(48),
    backgroundColor: _accentColor,
    disabledBackgroundColor: const Color(0xFFD5E4EC),
    disabledForegroundColor: const Color(0xFF637888),
  );

  static const _categories = [
    (ReportCategory.marineAnimal, Icons.pets_outlined, 'Animal marin'),
    (ReportCategory.obstruction, Icons.warning_amber_rounded, 'Obstacle'),
    (ReportCategory.pollution, Icons.water_drop_outlined, 'Pollution'),
  ];

  // Le compteur n'apparaît qu'à l'approche de la limite de 250 caractères.
  static const _commentMaxLength = 250;
  static const _counterThreshold = 200;

  Widget _header() {
    final photo = widget.photo;
    // Une fois publié, le point est envoyé : le guide de placement n'a plus
    // lieu d'être.
    final subtitle = _isPublished ? null : widget.subtitle;
    // La croix (40 px dans une zone de 48) tombe à 16 du coin.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (photo != null) ...[
              _photoThumbnail(photo),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nouveau signalement',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _mutedColor, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (!_isPublished)
              IconButton(
                tooltip: 'Fermer',
                onPressed: _isBusy ? null : widget.onClose,
                color: _textColor,
                style: IconButton.styleFrom(backgroundColor: Colors.white),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  // Le badge montre que la miniature s'ouvre : sans lui, rien ne l'indique.
  Widget _photoThumbnail(Uint8List photo) {
    return Semantics(
      button: true,
      label: 'Agrandir la photo',
      child: GestureDetector(
        onTap: () => ReportPhotoViewer.show(context, photo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Image.memory(
                photo,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black54,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.open_in_full,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryPicker() {
    return Row(
      children: [
        for (final (index, (category, icon, label)) in _categories.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(child: _categoryTile(category, icon, label)),
        ],
      ],
    );
  }

  // Icône et nom visibles : une infobulle demande un appui long, que
  // personne ne fait sur l'eau.
  Widget _categoryTile(ReportCategory category, IconData icon, String label) {
    final selected = _category == category;
    final foreground = selected ? Colors.white : _textColor;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Opacity(
        // Une fois verrouillé, seule la catégorie choisie reste en avant.
        opacity: _isLocked && !selected ? 0.5 : 1,
        child: Material(
          color: selected ? _accentColor : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: _controlRadius,
            side: BorderSide(color: selected ? _accentColor : _borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isLocked
                ? null
                : () {
                    AppHaptics.selection();
                    setState(() {
                      _category = category;
                      _errorMessage = null;
                    });
                  },
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _commentField() {
    const border = OutlineInputBorder(
      borderRadius: _controlRadius,
      borderSide: BorderSide(color: _borderColor),
    );
    return TextField(
      controller: _commentController,
      enabled: !_isLocked,
      maxLength: _commentMaxLength,
      maxLines: 2,
      minLines: 1,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      // Sur mobile, Flutter garde le clavier ouvert par défaut quand on touche
      // ailleurs : un appui sur la carte ou le panneau le referme.
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              currentLength < _counterThreshold
              ? null
              : Text(
                  '$currentLength/$maxLength',
                  style: const TextStyle(color: _mutedColor, fontSize: 12),
                ),
      style: const TextStyle(color: _textColor),
      decoration: const InputDecoration(
        hintText: 'Ajouter un commentaire (facultatif)',
        hintMaxLines: 1,
        hintStyle: TextStyle(color: _mutedColor),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: border,
        enabledBorder: border,
      ),
    );
  }

  // Le signalement est en ligne quoi qu'il arrive à la photo : on le dit
  // d'abord, puis l'état de l'envoi.
  Widget _publishedStatus() {
    final photoMessage = _errorMessage ?? 'Envoi de la photo…';
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF1E8E5A), size: 18),
            SizedBox(width: 6),
            Text(
              'Signalement publié',
              style: TextStyle(
                color: Color(0xFF1E8E5A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          photoMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _errorMessage != null ? _errorColor : _mutedColor,
          ),
        ),
      ],
    );
  }

  // Signalement publié mais photo non envoyée : réessayer, ou terminer en
  // abandonnant la photo. L'un sous l'autre, les libellés tiennent sur une
  // ligne.
  Widget _photoRetryActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: _uploadPhoto,
          style: _primaryButtonStyle,
          child: const Text('Réessayer l’envoi'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onClose,
          style: TextButton.styleFrom(
            minimumSize: const ui.Size.fromHeight(40),
            foregroundColor: _textColor,
          ),
          child: const Text('Terminer sans photo'),
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    // Le bouton est désactivé pendant l'envoi : un spinner blanc y serait
    // presque invisible.
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF637888),
      ),
    );
  }
}

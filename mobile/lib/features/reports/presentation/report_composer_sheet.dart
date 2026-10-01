import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../domain/manual_report.dart';

/// Panneau du bas en mode signalement : catégorie, commentaire facultatif
/// (250 caractères max) et bouton Publier. L'envoi est fait par `MapScreen`.
/// En mode photo, la miniature et [subtitle] s'affichent dans l'en-tête, et
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

  /// Hauteur du panneau, utilisée par la carte pour placer le marqueur.
  static double heightFor(MediaQueryData mediaQuery) {
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.viewInsets.bottom -
        24;
    const preferredHeight = 300.0;
    return math.min(preferredHeight, math.max(0, availableHeight));
  }

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
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForApiError(error);
      });
      return;
    } catch (_) {
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
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForPhotoError(error);
      });
    } catch (_) {
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
    final photo = widget.photo;
    final subtitle = widget.subtitle;
    final isLocked = _isBusy || _isPublished;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        mediaQuery.viewInsets.bottom + 12,
      ),
      child: SizedBox(
        height: ReportComposerSheet.heightFor(mediaQuery),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDDE3EA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x290D2238),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                  child: Row(
                    children: [
                      if (photo != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photo,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
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
                                color: Color(0xFF243243),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF687789),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!_isPublished)
                        IconButton(
                          tooltip: 'Fermer',
                          onPressed: _isBusy ? null : widget.onClose,
                          color: const Color(0xFF243243),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _categoryButton(
                            ReportCategory.marineAnimal,
                            Icons.pets_outlined,
                            'Animal marin',
                          ),
                          _categoryButton(
                            ReportCategory.obstruction,
                            Icons.warning_amber_rounded,
                            'Obstacle',
                          ),
                          _categoryButton(
                            ReportCategory.pollution,
                            Icons.water_drop_outlined,
                            'Pollution',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        enabled: !isLocked,
                        maxLength: 250,
                        maxLines: 2,
                        minLines: 1,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        style: const TextStyle(color: Color(0xFF243243)),
                        decoration: InputDecoration(
                          hintText: 'Ajouter un commentaire…',
                          hintStyle: const TextStyle(color: Color(0xFF687789)),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDDE3EA),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDDE3EA),
                            ),
                          ),
                          counterStyle: const TextStyle(
                            color: Color(0xFF687789),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isPublished)
                _publishedStatus()
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _errorColor),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _isPublished && _errorMessage != null
                    ? _photoRetryActions()
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              _category == null ||
                                  isLocked ||
                                  widget.onPublish == null
                              ? null
                              : _publish,
                          style: _primaryButtonStyle,
                          child: _isBusy
                              ? const _ButtonSpinner()
                              : const Text('Publier le signalement'),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _primaryButtonStyle = FilledButton.styleFrom(
    minimumSize: const ui.Size.fromHeight(48),
    backgroundColor: const Color(0xFF0DB8D5),
    disabledBackgroundColor: const Color(0xFFD5E4EC),
    disabledForegroundColor: const Color(0xFF637888),
  );

  static const _errorColor = Color(0xFFAF3942);

  // Le signalement est en ligne quoi qu'il arrive à la photo : on le dit
  // d'abord, puis l'état de l'envoi.
  Widget _publishedStatus() {
    final photoMessage = _errorMessage ?? 'Envoi de la photo…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
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
              color: _errorMessage != null
                  ? _errorColor
                  : const Color(0xFF687789),
            ),
          ),
        ],
      ),
    );
  }

  // Signalement publié mais photo non envoyée : réessayer, ou terminer en
  // abandonnant la photo.
  Widget _photoRetryActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.onClose,
            style: OutlinedButton.styleFrom(
              minimumSize: const ui.Size.fromHeight(48),
              foregroundColor: const Color(0xFF243243),
              side: const BorderSide(color: Color(0xFFDDE3EA)),
            ),
            child: const Text('Terminer sans photo'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _uploadPhoto,
            style: _primaryButtonStyle,
            child: const Text('Réessayer l’envoi'),
          ),
        ),
      ],
    );
  }

  Widget _categoryButton(ReportCategory category, IconData icon, String label) {
    final selected = _category == category;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          onPressed: _isBusy || _isPublished
              ? null
              : () => setState(() {
                  _category = category;
                  _errorMessage = null;
                }),
          style: IconButton.styleFrom(
            minimumSize: const ui.Size(54, 54),
            backgroundColor: selected ? const Color(0xFF0DB8D5) : Colors.white,
            foregroundColor: selected ? Colors.white : const Color(0xFF243243),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF0DB8D5)
                  : const Color(0xFFDDE3EA),
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

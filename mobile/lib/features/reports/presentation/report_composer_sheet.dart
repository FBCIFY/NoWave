import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../domain/manual_report.dart';

/// Panneau du bas en mode signalement : catégorie, commentaire facultatif
/// (250 caractères max) et bouton Publier. L'envoi est fait par `MapScreen`.
class ReportComposerSheet extends StatefulWidget {
  const ReportComposerSheet({super.key, required this.onClose, this.onPublish});

  final VoidCallback onClose;
  final Future<void> Function(ReportCategory category, String? description)?
  onPublish;

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
  String? _errorMessage;

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de publier. Vérifiez votre connexion.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _messageForApiError(ApiException error) {
    if (error.statusCode == 404) {
      try {
        final body = jsonDecode(error.body);
        if (body is Map && body['error']?['code'] == 'USER_NOT_FOUND') {
          return 'Votre profil NoWave est introuvable.';
        }
      } catch (_) {
        // A missing route can return a different response format.
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

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

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
                      const Expanded(
                        child: Text(
                          'Nouveau signalement',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF243243),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: _isSubmitting ? null : widget.onClose,
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
                        enabled: !_isSubmitting,
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
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFAF3942)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _category == null ||
                            _isSubmitting ||
                            widget.onPublish == null
                        ? null
                        : _publish,
                    style: FilledButton.styleFrom(
                      minimumSize: const ui.Size.fromHeight(48),
                      backgroundColor: const Color(0xFF0DB8D5),
                      disabledBackgroundColor: const Color(0xFFD5E4EC),
                      disabledForegroundColor: const Color(0xFF637888),
                    ),
                    child: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
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

  Widget _categoryButton(ReportCategory category, IconData icon, String label) {
    final selected = _category == category;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          onPressed: _isSubmitting
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

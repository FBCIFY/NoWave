import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../core/api/api_exception.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../data/report_detail_service.dart';
import '../domain/report_detail.dart';
import 'report_category_style.dart';
import 'report_detail_format.dart';
import 'report_photo_viewer.dart';

/// Fiche d'un signalement touché sur la carte (US-11) : catégorie, date,
/// position, distance, auteur, bateau et photo.
class ReportDetailSheet extends StatefulWidget {
  const ReportDetailSheet({
    super.key,
    required this.reportId,
    required this.loadReport,
    required this.loadPhoto,
    this.userPosition,
    this.now = DateTime.now,
  });

  final String reportId;

  /// Charge la fiche, en général `ReportDetailService.fetchReport`.
  final Future<ReportDetail> Function(String reportId) loadReport;

  /// Télécharge la photo, en général `ReportDetailService.fetchPhoto`.
  final Future<Uint8List> Function(String url) loadPhoto;

  /// Position de l'utilisateur pour la distance ; null si elle est inconnue.
  final ({double latitude, double longitude})? userPosition;

  /// Heure actuelle, remplaçable dans les tests.
  final DateTime Function() now;

  /// Ouvre la fiche en bas de l'écran, par-dessus la carte.
  static Future<void> show(
    BuildContext context, {
    required String reportId,
    required Future<ReportDetail> Function(String reportId) loadReport,
    required Future<Uint8List> Function(String url) loadPhoto,
    ({double latitude, double longitude})? userPosition,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ReportDetailSheet(
      reportId: reportId,
      loadReport: loadReport,
      loadPhoto: loadPhoto,
      userPosition: userPosition,
    ),
  );

  @override
  State<ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<ReportDetailSheet> {
  /// Chargement en cours ou terminé ; remplacé à chaque nouvel essai.
  late Future<ReportDetail> _report = widget.loadReport(widget.reportId);

  void _retry() {
    final report = widget.loadReport(widget.reportId);
    setState(() {
      _report = report;
    });
  }

  /// Relit la fiche pour une URL de photo neuve : l'URL signée ne vaut que
  /// cinq minutes. Null si la photo n'est plus servie (masquée).
  Future<String?> _refreshPhotoUrl() async =>
      (await widget.loadReport(widget.reportId)).photo?.url;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: FutureBuilder<ReportDetail>(
          future: _report,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return _ReportDetailContent(
                report: snapshot.requireData,
                userPosition: widget.userPosition,
                now: widget.now(),
                loadPhoto: widget.loadPhoto,
                refreshPhotoUrl: _refreshPhotoUrl,
              );
            }
            if (snapshot.hasError) {
              return _ReportDetailError(
                error: snapshot.error!,
                onRetry: _retry,
              );
            }
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
    );
  }
}

/// Fiche chargée.
class _ReportDetailContent extends StatelessWidget {
  const _ReportDetailContent({
    required this.report,
    required this.userPosition,
    required this.now,
    required this.loadPhoto,
    required this.refreshPhotoUrl,
  });

  final ReportDetail report;
  final ({double latitude, double longitude})? userPosition;
  final DateTime now;
  final Future<Uint8List> Function(String url) loadPhoto;
  final Future<String?> Function() refreshPhotoUrl;

  /// Distance et direction depuis l'utilisateur, ex. `2,4 NM au NE`.
  String get _distance {
    final from = userPosition;
    if (from == null) return 'Votre position est inconnue';
    final meters = geo.Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      report.latitude,
      report.longitude,
    );
    final bearing = geo.Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      report.latitude,
      report.longitude,
    );
    return '${formatNauticalMiles(meters)} au ${compassPoint(bearing)}';
  }

  /// Nom de l'auteur, ou pourquoi il n'est pas affiché.
  String get _author {
    final author = report.author;
    if (author == null) return 'Anonyme';
    if (author.deleted) return 'Utilisateur supprimé';
    return author.username ?? 'Anonyme';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = report.category;
    final description = report.description;
    final boat = report.boat;
    final photo = report.photo;
    final photoUrl = photo?.url;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: category.color,
                foregroundColor: Colors.white,
                child: Icon(category.icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.label, style: theme.textTheme.titleLarge),
                    Text(
                      'Observé ${formatDayTime(report.observedAt, now: now)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.place_outlined,
            label: 'Position',
            value:
                '${formatDms(report.latitude, isLatitude: true)}\n'
                '${formatDms(report.longitude, isLatitude: false)}',
          ),
          _DetailRow(
            icon: Icons.near_me_outlined,
            label: 'Distance',
            value: _distance,
          ),
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Auteur',
            value: _author,
          ),
          if (boat != null)
            _DetailRow(
              icon: Icons.sailing_outlined,
              label: 'Bateau',
              value: boat.name == null
                  ? boat.type.label
                  : '${boat.name} · ${boat.type.label}',
            ),
          if (photo != null)
            _DetailRow(
              icon: Icons.photo_camera_outlined,
              label: 'Photo',
              value: switch (photo.status) {
                ReportPhotoStatus.pending => 'Envoi en cours',
                // Sans URL, le backend ne la sert plus (masquée).
                ReportPhotoStatus.uploaded when photoUrl == null =>
                  'Indisponible',
                ReportPhotoStatus.uploaded => null,
                ReportPhotoStatus.failed => 'Envoi échoué',
              },
              child: photoUrl == null
                  ? null
                  : _ReportPhoto(
                      url: photoUrl,
                      loadPhoto: loadPhoto,
                      refreshUrl: refreshPhotoUrl,
                    ),
            ),
          _DetailRow(
            icon: Icons.schedule,
            label: 'Fin du signalement',
            value: formatDayTime(report.expiresAt, now: now),
          ),
        ],
      ),
    );
  }
}

/// Une information de la fiche : icône, intitulé et valeur (texte, ou
/// [child] comme la photo).
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.child,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (value case final value?)
                  Text(value, style: theme.textTheme.bodyLarge),
                if (child case final child?) ...[
                  const SizedBox(height: 8),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La photo n'est plus servie : masquée depuis l'ouverture de la fiche.
class _PhotoHiddenException implements Exception {
  const _PhotoHiddenException();
}

/// Photo publiée, téléchargée depuis son URL signée ; un appui l'ouvre en
/// plein écran.
///
/// L'URL expire au bout de cinq minutes et le stockage répond alors 403,
/// comme pour un refus d'accès. Sur un 403, on relit donc la fiche une fois
/// pour une URL neuve ; si elle est refusée à son tour, c'est un vrai refus.
class _ReportPhoto extends StatefulWidget {
  const _ReportPhoto({
    required this.url,
    required this.loadPhoto,
    required this.refreshUrl,
  });

  final String url;
  final Future<Uint8List> Function(String url) loadPhoto;
  final Future<String?> Function() refreshUrl;

  @override
  State<_ReportPhoto> createState() => _ReportPhotoState();
}

class _ReportPhotoState extends State<_ReportPhoto> {
  late Future<Uint8List> _photo = _load();

  Future<Uint8List> _load() async {
    try {
      return await widget.loadPhoto(widget.url);
    } on ApiException catch (error) {
      if (error.statusCode != 403) rethrow;
      return _loadFromFreshUrl();
    }
  }

  /// Une URL neuve : un 403 n'est plus une expiration.
  Future<Uint8List> _loadFromFreshUrl() async {
    final url = await widget.refreshUrl();
    if (url == null) throw const _PhotoHiddenException();
    return widget.loadPhoto(url);
  }

  /// L'URL a pu expirer depuis l'ouverture : on repart d'une URL neuve.
  void _retry() {
    final photo = _loadFromFreshUrl();
    setState(() {
      _photo = photo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: FutureBuilder<Uint8List>(
            future: _photo,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final bytes = snapshot.requireData;
                return Semantics(
                  button: true,
                  label: 'Agrandir la photo',
                  child: GestureDetector(
                    onTap: () => ReportPhotoViewer.show(context, bytes),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const _PhotoError(message: 'Photo illisible.'),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _photoError(snapshot.error!);
              }
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Chargement de la photo',
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _photoError(Object error) {
    return switch (error) {
      _PhotoHiddenException() => const _PhotoError(
        message: 'Cette photo n’est plus disponible.',
      ),
      ReportNotFoundException() => const _PhotoError(
        message: 'Ce signalement n’est plus disponible.',
      ),
      ApiException(statusCode: 401) => _PhotoError(
        message: 'Votre session a expiré. Reconnectez-vous.',
        onRetry: _retry,
      ),
      ApiException(statusCode: 403) => _PhotoError(
        message: 'Accès à la photo refusé.',
        onRetry: _retry,
      ),
      ApiException() => _PhotoError(
        message: 'Photo indisponible. Réessayez.',
        onRetry: _retry,
      ),
      // Délai dépassé, pas de réseau.
      _ => _PhotoError(
        message: 'Photo indisponible. Vérifiez votre connexion.',
        onRetry: _retry,
      ),
    };
  }
}

/// Message à la place de la photo, avec « Réessayer » si cela peut aider.
class _PhotoError extends StatelessWidget {
  const _PhotoError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, size: 32),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }
}

/// Échec du chargement : le signalement a disparu, ou on peut réessayer.
class _ReportDetailError extends StatelessWidget {
  const _ReportDetailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final gone = error is ReportNotFoundException;
    final message = switch (error) {
      ReportNotFoundException() =>
        'Ce signalement n’est plus disponible : il a expiré ou a été retiré.',
      ApiException(statusCode: 401) =>
        'Votre session a expiré. Reconnectez-vous puis réessayez.',
      ApiException() => 'Le serveur ne répond pas correctement. Réessayez.',
      // Délai dépassé, pas de réseau ou réponse illisible.
      _ => 'Impossible de charger le signalement. Vérifiez votre connexion.',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          gone ? Icons.event_busy_outlined : Icons.cloud_off_outlined,
          size: 40,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (gone)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          )
        else
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../core/api/api_exception.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../data/report_detail_service.dart';
import '../domain/report_detail.dart';
import 'report_category_style.dart';
import 'report_detail_format.dart';

/// Fiche d'un signalement touché sur la carte (US-11) : catégorie, date,
/// position, distance, auteur, bateau et état de la photo.
class ReportDetailSheet extends StatefulWidget {
  const ReportDetailSheet({
    super.key,
    required this.reportId,
    required this.loadReport,
    this.userPosition,
    this.now = DateTime.now,
  });

  final String reportId;

  /// Charge la fiche, en général `ReportDetailService.fetchReport`.
  final Future<ReportDetail> Function(String reportId) loadReport;

  /// Position de l'utilisateur pour la distance ; null si elle est inconnue.
  final ({double latitude, double longitude})? userPosition;

  /// Heure actuelle, remplaçable dans les tests.
  final DateTime Function() now;

  /// Ouvre la fiche en bas de l'écran, par-dessus la carte.
  static Future<void> show(
    BuildContext context, {
    required String reportId,
    required Future<ReportDetail> Function(String reportId) loadReport,
    ({double latitude, double longitude})? userPosition,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ReportDetailSheet(
      reportId: reportId,
      loadReport: loadReport,
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
  });

  final ReportDetail report;
  final ({double latitude, double longitude})? userPosition;
  final DateTime now;

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
                ReportPhotoStatus.uploaded => 'Envoyée',
                ReportPhotoStatus.failed => 'Envoi échoué',
              },
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

/// Une information de la fiche : icône, intitulé et valeur.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
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

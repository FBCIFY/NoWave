import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../map/presentation/widgets/map_panel.dart';
import '../data/report_detail_service.dart';
import '../domain/report_detail.dart';
import 'report_category_style.dart';
import 'report_category_badge.dart';
import 'report_detail_format.dart';
import 'report_photo_viewer.dart';

/// Fiche d'un signalement touché sur la carte (US-11) : catégorie, date,
/// distance, fin, photo, commentaire, auteur et bateau.
class ReportDetailSheet extends StatefulWidget {
  const ReportDetailSheet({
    super.key,
    required this.reportId,
    required this.loadReport,
    required this.loadPhoto,
    this.userPosition,
    this.now = DateTime.now,
    this.onShowOnMap,
  });

  final String reportId;
  final Future<void> Function(ReportDetail)? onShowOnMap;

  /// Charge la fiche, en général `ReportDetailService.fetchReport`.
  final Future<ReportDetail> Function(String reportId) loadReport;

  /// Télécharge la photo, en général `ReportDetailService.fetchPhoto`.
  final Future<Uint8List> Function(String url) loadPhoto;

  /// Position de l'utilisateur pour la distance ; null si elle est inconnue.
  final ({double latitude, double longitude})? userPosition;

  /// Heure actuelle, remplaçable dans les tests.
  final DateTime Function() now;

  @override
  State<ReportDetailSheet> createState() => _ReportDetailSheetState();
}

/// Même fiche en bas de la carte depuis un badge ou Mes alertes ; dans ce
/// dernier cas, une flèche permet de retrouver la liste.
class ReportDetailPanel extends StatelessWidget {
  const ReportDetailPanel({
    super.key,
    required this.reportId,
    required this.loadReport,
    required this.loadPhoto,
    required this.onClose,
    this.side = MapPanelSide.bottom,
    this.onBack,
    this.userPosition,
    this.dismissRequested = false,
  });

  final String reportId;
  final Future<ReportDetail> Function(String reportId) loadReport;
  final Future<Uint8List> Function(String url) loadPhoto;
  final ({double latitude, double longitude})? userPosition;
  final VoidCallback onClose;
  final MapPanelSide side;
  final VoidCallback? onBack;
  final bool dismissRequested;

  @override
  Widget build(BuildContext context) => MapPanel(
    side: side,
    onClose: onClose,
    onBack: onBack,
    showCloseButton: false,
    backgroundColor: Colors.white,
    extendToBottom: Theme.of(context).platform == TargetPlatform.android,
    dismissRequested: dismissRequested,
    child: ReportDetailSheet(
      reportId: reportId,
      loadReport: loadReport,
      loadPhoto: loadPhoto,
      userPosition: userPosition,
    ),
  );
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
                onShowOnMap: widget.onShowOnMap,
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

/// Fiche chargée : en-tête, distance et fin, photo, commentaire, auteur, puis
/// « Voir sur la carte » depuis l'historique.
class _ReportDetailContent extends StatelessWidget {
  const _ReportDetailContent({
    required this.report,
    this.onShowOnMap,
    required this.userPosition,
    required this.now,
    required this.loadPhoto,
    required this.refreshPhotoUrl,
  });

  final ReportDetail report;
  final Future<void> Function(ReportDetail)? onShowOnMap;
  final ({double latitude, double longitude})? userPosition;
  final DateTime now;
  final Future<Uint8List> Function(String url) loadPhoto;
  final Future<String?> Function() refreshPhotoUrl;

  /// Distance et direction depuis l'utilisateur, ex. `2,4 NM au NE`.
  String get _distance {
    final from = userPosition;
    if (from == null) return 'Distance inconnue';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = report.category;
    final description = report.description;
    final photo = report.photo;
    final photoUrl = photo?.url;
    final onShowOnMap = this.onShowOnMap;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ReportCategoryBadge(category: category),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Observé ${formatDayTime(report.observedAt, now: now)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.near_me_outlined, label: _distance),
              _InfoChip(
                icon: Icons.schedule,
                label: 'Expire ${formatDayTime(report.expiresAt, now: now)}',
              ),
            ],
          ),
          if (photo != null) ...[
            const SizedBox(height: 16),
            if (photoUrl != null)
              _ReportPhoto(
                url: photoUrl,
                loadPhoto: loadPhoto,
                refreshUrl: refreshPhotoUrl,
              )
            else
              _PhotoStatus(photo.status),
          ],
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: 16),
          _AuthorRow(author: report.author, boat: report.boat),
          if (onShowOnMap != null) ...[
            const SizedBox(height: 20),
            _ShowOnMapButton(onPressed: () => onShowOnMap(report)),
          ],
        ],
      ),
    );
  }
}

/// Petite information en pastille : distance, fin du signalement.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo pas encore servie : en cours d'envoi, échouée ou masquée.
class _PhotoStatus extends StatelessWidget {
  const _PhotoStatus(this.status);

  final ReportPhotoStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (status) {
      ReportPhotoStatus.pending => 'Photo en cours d’envoi',
      ReportPhotoStatus.failed => 'Envoi de la photo échoué',
      // Sans URL, le backend ne la sert plus (masquée).
      ReportPhotoStatus.uploaded => 'Photo indisponible',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_camera_outlined, color: const Color(0xFF475569)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Auteur et bateau, selon ce que l'auteur accepte de montrer.
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.author, required this.boat});

  final ReportAuthor? author;
  final ReportBoat? boat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = this.author;
    final boat = this.boat;
    final username = author == null || author.deleted ? null : author.username;
    final name = switch (author) {
      ReportAuthor(deleted: true) => 'Utilisateur supprimé',
      _ => username ?? 'Anonyme',
    };

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.blue600,
          child: username == null || username.isEmpty
              ? const Icon(Icons.person_outline, size: 20)
              : Text(
                  username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              if (boat != null)
                Text(
                  boat.name == null
                      ? boat.type.label
                      : '${boat.name} · ${boat.type.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
            ],
          ),
        ),
      ],
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
      ApiException(statusCode: 403) =>
        'Vous n’avez pas accès à ce signalement.',
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

/// Une seule navigation carte à la fois, même après un double appui.
class _ShowOnMapButton extends StatefulWidget {
  const _ShowOnMapButton({required this.onPressed});
  final Future<void> Function() onPressed;
  @override
  State<_ShowOnMapButton> createState() => _ShowOnMapButtonState();
}

class _ShowOnMapButtonState extends State<_ShowOnMapButton> {
  bool _busy = false;
  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’ouvrir la carte. Réessayez.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: _busy ? null : _open,
    icon: const Icon(Icons.map_outlined),
    label: const Text('Voir sur la carte'),
  );
}

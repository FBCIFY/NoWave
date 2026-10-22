import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../map/presentation/widgets/map_panel.dart';
import '../../reports/presentation/report_category_badge.dart';
import '../../reports/presentation/report_category_style.dart';
import '../../reports/presentation/report_detail_format.dart';
import '../data/alert_history_controller.dart';
import '../domain/alert.dart';

/// Mes alertes, posé en bas de la carte : les plus récentes d'abord. Une
/// alerte touchée ouvre sa fiche à la même place.
class AlertsPanel extends StatelessWidget {
  const AlertsPanel({
    super.key,
    required this.history,
    required this.onOpen,
    required this.onClose,
    this.userPosition,
    this.now = DateTime.now,
    this.dismissRequested = false,
  });

  /// Gardé par la carte : revenir de la fiche ne recharge pas la liste.
  final AlertHistoryController history;
  final void Function(Alert) onOpen;
  final VoidCallback onClose;

  /// Position actuelle pour la distance ; sinon celle au moment de l'alerte.
  final ({double latitude, double longitude})? userPosition;
  final DateTime Function() now;
  final bool dismissRequested;

  String _error(Object error) => switch (error) {
    ApiException(statusCode: 401) =>
      'Votre session a expiré. Reconnectez-vous puis réessayez.',
    ApiException(statusCode: 403) => 'L’accès aux alertes est refusé.',
    ApiException(statusCode: 404) =>
      'L’historique des alertes est indisponible sur ce serveur.',
    _ => 'Impossible de charger les alertes. Vérifiez votre connexion. L’historique n’est pas disponible hors ligne.',
  };

  String _distance(Alert alert) {
    final from = userPosition;
    if (from == null) {
      return '${formatNauticalMiles(alert.distanceM)} lors de l’alerte';
    }
    return formatNauticalMiles(
      geo.Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        alert.latitude,
        alert.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MapPanel(
    side: MapPanelSide.bottom,
    title: 'Mes alertes',
    backgroundColor: Colors.white,
    onClose: onClose,
    dismissRequested: dismissRequested,
    actions: [
      ListenableBuilder(
        listenable: history,
        builder: (_, _) => IconButton(
          tooltip: 'Actualiser les alertes',
          onPressed: history.loading ? null : () => history.load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ),
    ],
    child: ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final error = history.error;
        final items = history.items;
        return ListView(
          // Retour depuis une fiche : la liste reprend où elle était.
          key: const PageStorageKey('alerts-list'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          children: [
            if (error != null)
              _ErrorRow(
                message: items.isEmpty
                    ? _error(error)
                    : '${_error(error)} Les alertes affichées peuvent ne plus être à jour.',
                onRetry: history.loading ? null : history.retry,
              ),
            if (history.loaded && items.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune alerte pour le moment.'),
              ),
            for (final (index, alert) in items.indexed) ...[
              if (index > 0)
                const Divider(
                  height: 1,
                  indent: 64,
                  endIndent: 12,
                  color: Color(0xFFD7E0EB),
                ),
              ListTile(
                key: ValueKey(alert.id),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                titleAlignment: ListTileTitleAlignment.center,
                minLeadingWidth: 40,
                horizontalTitleGap: 12,
                leading: ReportCategoryBadge(
                  category: alert.category,
                  size: 40,
                ),
                title: Text(
                  alert.category.label,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                isThreeLine: true,
                subtitle: Text.rich(
                  TextSpan(
                    text: '${formatDayTime(alert.alertedAt!, now: now())}\n',
                    children: [
                      TextSpan(
                        text: _distance(alert),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.slate900,
                ),
                onTap: () => onOpen(alert),
              ),
            ],
            if (history.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (history.hasMore && error == null)
              // Bas de liste atteint : la page suivante arrive seule.
              _LoadMore(onVisible: history.load),
          ],
        );
      },
    ),
  );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

/// Construit seulement près du bas de la liste : demande la page suivante.
class _LoadMore extends StatefulWidget {
  const _LoadMore({required this.onVisible});

  final Future<void> Function() onVisible;

  @override
  State<_LoadMore> createState() => _LoadMoreState();
}

class _LoadMoreState extends State<_LoadMore> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 48);
}

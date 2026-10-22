import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../map/presentation/widgets/map_panel.dart';
import '../../reports/presentation/report_category_icon.dart';
import '../../reports/presentation/report_category_style.dart';
import '../../reports/presentation/report_category_badge.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Les plus récentes en premier',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF475569)),
                ),
              ),
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
            for (final alert in items)
              _AlertCard(
                key: ValueKey(alert.id),
                alert: alert,
                receivedAt: formatDayTime(alert.alertedAt!, now: now()),
                distance: _distance(alert),
                currentDistance: userPosition != null,
                onTap: () => onOpen(alert),
              ),
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    super.key,
    required this.alert,
    required this.receivedAt,
    required this.distance,
    required this.currentDistance,
    required this.onTap,
  });

  final Alert alert;
  final String receivedAt;
  final String distance;
  final bool currentDistance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD7E0EB)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ReportCategoryBadge(category: alert.category),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.category.label,
                            style: text.titleMedium?.copyWith(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reçue $receivedAt',
                            style: text.bodySmall?.copyWith(
                              color: const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: AppColors.slate900),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Color(0xFFD7E0EB)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.near_me_outlined,
                      size: 18,
                      color: AppColors.blue950,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: currentDistance
                              ? 'Distance actuelle\n'
                              : 'Distance\n',
                          style: text.bodySmall?.copyWith(
                            color: const Color(0xFF475569),
                          ),
                          children: [
                            TextSpan(
                              text: distance,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

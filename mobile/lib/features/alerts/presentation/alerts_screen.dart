import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../reports/presentation/report_category_style.dart';
import '../../reports/presentation/report_detail_format.dart';
import '../data/alert_history_controller.dart';
import '../data/alert_service.dart';
import '../domain/alert.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.service, required this.onOpen});
  final AlertService service;
  final Future<void> Function(Alert) onOpen;
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final _history = AlertHistoryController(widget.service)..load();
  bool _opening = false;
  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  Future<void> _open(Alert alert) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen(alert);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’ouvrir le signalement. Réessayez.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _error(Object error) => switch (error) {
    ApiException(statusCode: 401) =>
      'Votre session a expiré. Reconnectez-vous puis réessayez.',
    ApiException(statusCode: 403) => 'L’accès aux alertes est refusé.',
    ApiException(statusCode: 404) =>
      'L’historique des alertes est indisponible sur ce serveur.',
    _ => 'Impossible de charger les alertes. Vérifiez votre connexion puis réessayez. L’historique n’est pas disponible hors ligne.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mes alertes'),
      actions: [
        ListenableBuilder(
          listenable: _history,
          builder: (_, _) => IconButton(
            tooltip: 'Actualiser les alertes',
            onPressed: _history.loading
                ? null
                : () => _history.load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: _history,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Historique des alertes de votre compte, même si la notification n’a pas été reçue.',
          ),
          if (_history.error case final error?) ...[
            const SizedBox(height: 16),
            Text(_error(error)),
            if (_history.items.isNotEmpty)
              const Text(
                'Les alertes déjà affichées peuvent ne plus être à jour.',
              ),
            TextButton(
              onPressed: _history.loading ? null : _history.retry,
              child: const Text('Réessayer'),
            ),
          ],
          if (_history.loaded &&
              _history.items.isEmpty &&
              _history.error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune alerte pour le moment.'),
            ),
          for (final alert in _history.items)
            Card(
              child: ListTile(
                key: ValueKey(alert.id),
                leading: Icon(alert.category.icon, color: alert.category.color),
                title: Text(alert.category.label),
                subtitle: Text(
                  '${formatNauticalMiles(alert.distanceM)} lors de l’alerte\n${alert.positionDms}\n${formatDayTime(alert.alertedAt!, now: DateTime.now())}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _opening ? null : () => _open(alert),
              ),
            ),
          if (_history.loading)
            const Center(child: CircularProgressIndicator())
          else if (_history.hasMore && _history.error == null)
            TextButton(
              onPressed: _history.load,
              child: const Text('Charger la suite'),
            ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../features/alerts/domain/alert.dart';
import '../../features/reports/presentation/report_category_style.dart';
import '../../features/reports/presentation/report_detail_format.dart';
import 'alert_push_controller.dart';

/// UI attachée uniquement à l'accueil autorisé. Le contrôleur capture les taps
/// plus tôt (AuthGate), puis attend cet écran pour naviguer.
class PushNotificationListener extends StatefulWidget {
  const PushNotificationListener({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.child,
    this.onOpenHistory,
  });
  final AlertPushController controller;
  final Future<void> Function(AlertPush) onOpen;
  final Widget child;
  final VoidCallback? onOpenHistory;
  @override
  State<PushNotificationListener> createState() =>
      _PushNotificationListenerState();
}

class _PushNotificationListenerState extends State<PushNotificationListener> {
  Future<void> _open(AlertPush push) => widget.onOpen(push);
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.attach(_open);
      _changed();
    });
  }

  void _changed() {
    if (!mounted) return;
    final controller = widget.controller;
    final push = controller.foreground;
    final notice = controller.notice;
    final session = controller.sessionEpoch;
    controller.foreground = null;
    controller.notice = null;
    if (push == null && notice == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            notice ??
                '${push!.alert.category.label} · ${formatNauticalMiles(push.alert.distanceM)}\n${push.alert.positionDms}',
          ),
          action: notice != null
              ? controller.canRetry
                    ? SnackBarAction(
                        label: 'Réessayer',
                        onPressed: () {
                          if (controller.sessionEpoch == session &&
                              controller.ready) {
                            controller.retry();
                          }
                        },
                      )
                    : widget.onOpenHistory == null
                    ? null
                    : SnackBarAction(
                        label: 'Historique',
                        onPressed: () {
                          if (controller.sessionEpoch == session &&
                              controller.ready) {
                            widget.onOpenHistory?.call();
                          }
                        },
                      )
              : push == null
              ? null
              : SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () {
                    if (controller.sessionEpoch == session &&
                        controller.ready) {
                      controller.open(push);
                    }
                  },
                ),
        ),
      );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.detach(_open);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

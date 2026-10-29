import 'dart:async';

import 'package:flutter/widgets.dart';

import 'device_position_reporter.dart';

/// Envoie la position du téléphone tant que [child] est affiché et que l'app
/// est visible. En arrière-plan, le suivi s'arrête, sauf avec
/// [runInBackground].
///
/// À placer sous `DeviceRegistrar` : le backend n'accepte la position que d'un
/// téléphone enregistré.
class DevicePositionTracker extends StatefulWidget {
  final DevicePositionReporter reporter;

  /// Continuer l'envoi quand l'app passe en arrière-plan. Vrai quand
  /// l'utilisateur a activé les alertes : le backend ne choisit les
  /// destinataires que parmi eux.
  final bool runInBackground;

  /// Faux tant que la carte se charge sous l'onboarding : le suivi démarre à
  /// son arrivée.
  final bool active;
  final Widget child;

  const DevicePositionTracker({
    super.key,
    required this.reporter,
    this.runInBackground = false,
    this.active = true,
    required this.child,
  });

  @override
  State<DevicePositionTracker> createState() => _DevicePositionTrackerState();
}

class _DevicePositionTrackerState extends State<DevicePositionTracker> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    unawaited(widget.reporter.setBackground(widget.runInBackground));
    if (widget.active) unawaited(widget.reporter.start());
    // `hide` et pas `pause` : une fenêtre système (autorisation de
    // notifications) ne doit pas couper le suivi. `resume` : la localisation
    // vient peut-être d'être autorisée dans une de ces fenêtres, le suivi
    // s'abonne alors sans attendre le prochain envoi.
    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        if (widget.active) unawaited(widget.reporter.appHidden());
      },
      onShow: () {
        if (widget.active) unawaited(widget.reporter.start());
      },
      onResume: () {
        if (widget.active) unawaited(widget.reporter.start());
      },
    );
  }

  @override
  void didUpdateWidget(covariant DevicePositionTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runInBackground != widget.runInBackground) {
      unawaited(widget.reporter.setBackground(widget.runInBackground));
    }
    if (widget.active && !oldWidget.active) {
      unawaited(widget.reporter.start());
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(widget.reporter.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

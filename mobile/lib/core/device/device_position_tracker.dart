import 'dart:async';

import 'package:flutter/widgets.dart';

import 'device_position_reporter.dart';

/// Envoie la position du téléphone tant que [child] est affiché et que l'app
/// est visible. En arrière-plan, le suivi s'arrête.
///
/// À placer sous `DeviceRegistrar` : le backend n'accepte la position que d'un
/// téléphone enregistré.
class DevicePositionTracker extends StatefulWidget {
  final DevicePositionReporter reporter;
  final Widget child;

  const DevicePositionTracker({
    super.key,
    required this.reporter,
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
    unawaited(widget.reporter.start());
    // `hide` et pas `pause` : une fenêtre système (autorisation de
    // notifications) ne doit pas couper le suivi.
    _lifecycleListener = AppLifecycleListener(
      onHide: () => unawaited(widget.reporter.stop()),
      onShow: () => unawaited(widget.reporter.start()),
    );
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

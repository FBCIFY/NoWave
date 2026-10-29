import 'dart:async';

import 'package:flutter/widgets.dart';

import 'device_registration.dart';

/// Garde ce téléphone enregistré auprès du backend tant que [child] est
/// affiché : à l'ouverture, à chaque retour dans l'app et à chaque nouveau
/// token FCM.
///
/// À placer sous `ProfileGate`, une fois le profil créé : avant, le backend
/// refuse l'enregistrement.
class DeviceRegistrar extends StatefulWidget {
  final DeviceRegistration registration;

  /// Faux tant que la carte se charge sous l'onboarding : l'enregistrement
  /// démarre à son arrivée.
  final bool active;
  final Widget child;

  const DeviceRegistrar({
    super.key,
    required this.registration,
    this.active = true,
    required this.child,
  });

  @override
  State<DeviceRegistrar> createState() => _DeviceRegistrarState();
}

class _DeviceRegistrarState extends State<DeviceRegistrar> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(widget.registration.start());
    // Au retour dans l'app, l'autorisation de notifications a pu changer :
    // dans les réglages, ou dans la fenêtre système qui met l'app en pause.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (widget.active) unawaited(widget.registration.register());
      },
    );
  }

  @override
  void didUpdateWidget(covariant DeviceRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      unawaited(widget.registration.start());
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(widget.registration.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
  final Widget child;

  const DeviceRegistrar({
    super.key,
    required this.registration,
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
    unawaited(widget.registration.start());
    // Au retour dans l'app, l'autorisation de notifications a pu changer :
    // dans les réglages, ou dans la fenêtre système qui met l'app en pause.
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(widget.registration.register()),
    );
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

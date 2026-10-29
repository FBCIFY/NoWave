import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/device/device_position_reporter.dart';
import '../../../core/device/device_registration.dart';

import '../../../core/notifications/alert_push_controller.dart';
import '../../alerts/data/alert_service.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../map/data/report_tiles.dart';
import '../../profile/data/profile_service.dart';
import '../../profile/presentation/profile_gate.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import '../data/auth_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';
import 'widgets/flow_transition.dart';

/// Premier aiguillage de l'app, piloté par la session Firebase :
/// connexion ou inscription → vérification de l'e-mail → [ProfileGate].
///
/// `step` ne sert qu'au sens de l'animation entre deux écrans.
class AuthGate extends StatefulWidget {
  final AuthService authService;
  final AlertService? alertService;
  final AlertPushController? pushController;
  final ProfileService profileService;
  final ManualReportService reportService;
  final PositionEstimateService positionEstimateService;
  final ReportTiles reportTiles;
  final ReportDetailService reportDetailService;
  final DeviceRegistration deviceRegistration;
  final DevicePositionReporter devicePositionReporter;
  final ValueListenable<int>? inactiveUserEvents;

  const AuthGate({
    super.key,
    required this.authService,
    this.alertService,
    this.pushController,
    required this.profileService,
    required this.reportService,
    required this.positionEstimateService,
    required this.reportTiles,
    required this.reportDetailService,
    required this.deviceRegistration,
    required this.devicePositionReporter,
    this.inactiveUserEvents,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _userChanges;
  bool _showRegistration = false;
  String? _previousUid;

  @override
  void initState() {
    super.initState();
    _userChanges = widget.authService.userChanges.map((user) {
      if (_previousUid != null && _previousUid != user?.uid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
      }
      _previousUid = user?.uid;
      widget.pushController?.setSession(user?.uid);
      return user;
    });
    unawaited(widget.pushController?.start());
  }

  @override
  void dispose() {
    widget.pushController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _userChanges,
      builder: (context, snapshot) {
        late final int step;
        late final Widget screen;

        if (snapshot.connectionState == ConnectionState.waiting) {
          step = -1;
          screen = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          step = -1;
          screen = const Scaffold(
            body: Center(child: Text('Impossible de vérifier votre session.')),
          );
        } else if (snapshot.data case final user?) {
          _showRegistration = false;
          if (!user.emailVerified) {
            step = 2;
            screen = VerifyEmailScreen(authService: widget.authService);
          } else {
            // Compte vérifié : on écoute les notifications et on passe au profil.
            step = 3;
            screen = ProfileGate(
              key: ValueKey(user.uid),
              alertService: widget.alertService,
              pushController: widget.pushController,
              authService: widget.authService,
              inactiveUserEvents: widget.inactiveUserEvents,
              profileService: widget.profileService,
              reportService: widget.reportService,
              positionEstimateService: widget.positionEstimateService,
              reportTiles: widget.reportTiles,
              reportDetailService: widget.reportDetailService,
              deviceRegistration: widget.deviceRegistration,
              devicePositionReporter: widget.devicePositionReporter,
            );
          }
        } else if (_showRegistration) {
          step = 1;
          screen = RegisterScreen(
            authService: widget.authService,
            onBack: () => setState(() => _showRegistration = false),
          );
        } else {
          step = 0;
          screen = LoginScreen(
            authService: widget.authService,
            onRegister: () => setState(() => _showRegistration = true),
          );
        }

        // Le bouton retour du téléphone est géré par l'inscription : page
        // précédente, puis connexion.
        return FlowTransition(step: step, child: screen);
      },
    );
  }
}

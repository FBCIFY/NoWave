import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/notifications/push_notification_listener.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../profile/data/profile_service.dart';
import '../../profile/presentation/profile_gate.dart';
import '../../reports/data/manual_report_service.dart';
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
  final ProfileService profileService;
  final ManualReportService reportService;
  final PositionEstimateService positionEstimateService;

  const AuthGate({
    super.key,
    required this.authService,
    required this.profileService,
    required this.reportService,
    required this.positionEstimateService,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _userChanges;
  bool _showRegistration = false;

  @override
  void initState() {
    super.initState();
    _userChanges = widget.authService.userChanges;
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
            screen = PushNotificationListener(
              child: ProfileGate(
                authService: widget.authService,
                profileService: widget.profileService,
                reportService: widget.reportService,
                positionEstimateService: widget.positionEstimateService,
              ),
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

        // Le bouton retour du téléphone ramène de l'inscription à la connexion.
        return PopScope(
          canPop: step != 1,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && step == 1) {
              setState(() => _showRegistration = false);
            }
          },
          child: FlowTransition(step: step, child: screen),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import 'widgets/auth_photo_layout.dart';
import 'widgets/auth_primary_button.dart';

/// Attente de la vérification de l'e-mail.
///
/// Vérifie toutes les 5 secondes et au retour dans l'app. Dès que l'adresse
/// est vérifiée, `AuthGate` passe automatiquement au profil.
class VerifyEmailScreen extends StatefulWidget {
  final AuthService authService;

  const VerifyEmailScreen({super.key, required this.authService});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  String? _message;
  Timer? _verificationTimer;
  bool _isAutoChecking = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _verificationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isAppActive) {
        _checkVerificationSilently();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;

    if (_isAppActive) {
      _checkVerificationSilently();
    }
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkVerificationSilently() async {
    if (_isLoading || _isAutoChecking) {
      return;
    }

    _isAutoChecking = true;

    try {
      await widget.authService.reloadAndCheckEmailVerification();
    } catch (_) {
      // La vérification automatique réessaiera dans quelques secondes.
    } finally {
      _isAutoChecking = false;
    }
  }

  Future<void> _checkVerification({bool showUnverifiedMessage = true}) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final isVerified = await widget.authService
          .reloadAndCheckEmailVerification();

      if (!mounted) return;

      if (!isVerified && showUnverifiedMessage) {
        setState(() {
          _message = 'L’adresse e-mail n’est pas encore vérifiée.';
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = 'Impossible de vérifier l’adresse pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await widget.authService.sendEmailVerification();

      if (!mounted) return;

      setState(() {
        _message = 'Un nouveau courriel de vérification a été envoyé.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = 'Impossible d’envoyer le courriel pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await widget.authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.authService.currentUser?.email;

    return AuthPhotoLayout(
      title: 'Vérifiez votre e-mail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                color: Color(0xFF22D3EE),
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email == null
                          ? 'Un lien de vérification vous a été envoyé.'
                          : 'Un lien de vérification a été envoyé à',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          color: Color(0xFF22D3EE),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: const Color(0xFF22D3EE).withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Actualisation automatique de la vérification…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
          const SizedBox(height: 28),
          AuthPrimaryButton(
            label: 'Vérifier maintenant',
            onPressed: _isLoading ? null : () => _checkVerification(),
            isLoading: _isLoading,
            showArrow: false,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading ? null : _resendEmail,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF22D3EE),
              minimumSize: const Size(0, 44),
            ),
            child: const Text(
              'Renvoyer le courriel',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : _signOut,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.70),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Se déconnecter', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

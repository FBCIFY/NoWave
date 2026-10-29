import 'dart:async';

import 'package:flutter/material.dart';

/// Garde le parcours de déconnexion ouvert jusqu'à son succès. En cas
/// d'échec, la session reste disponible pour réessayer le nettoyage, ou
/// pour y renoncer et continuer sur le compte actuel (hors ligne).
class SignOutDialog extends StatefulWidget {
  final Future<void> Function() onSignOut;
  final VoidCallback onCancel;

  const SignOutDialog({
    super.key,
    required this.onSignOut,
    required this.onCancel,
  });

  @override
  State<SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<SignOutDialog> {
  bool _running = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_trySignOut());
  }

  Future<void> _trySignOut() async {
    if (_running) return;
    setState(() {
      _running = true;
      _failed = false;
    });
    try {
      await widget.onSignOut();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _failed = true;
      });
    }
  }

  void _cancel() {
    widget.onCancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Déconnexion'),
      content: _failed
          ? const Text(
              'Impossible de terminer la déconnexion. Votre session est '
              'conservée pour réessayer. Vérifiez votre connexion Internet.',
            )
          : const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Déconnexion en cours…')),
              ],
            ),
      actions: [
        if (_failed) ...[
          TextButton(onPressed: _cancel, child: const Text('Annuler')),
          TextButton(onPressed: _trySignOut, child: const Text('Réessayer')),
        ],
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../data/account_deletion.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    super.key,
    required this.deletion,
    required this.onCancel,
    required this.onDone,
  });
  final AccountDeletion deletion;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool _busy = false;
  bool _failed = false;
  bool _finished = false;

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.deletion.run();
      if (mounted) {
        setState(() {
          _busy = false;
          _finished = true;
        });
        widget.onDone();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.deletion.leave();
      if (mounted) {
        setState(() => _busy = false);
        widget.onDone();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.deletion.pending;
    final confirmed = widget.deletion.confirmed;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Suppression du compte'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _finished
                  ? 'Votre compte a été supprimé et votre session locale est fermée.'
                  : confirmed
                  ? 'Le serveur a confirmé la suppression. Le nettoyage de ce téléphone reste à terminer.'
                  : pending
                  ? 'Votre demande de suppression est en attente de confirmation. Certaines données peuvent déjà avoir été supprimées. Votre session locale est conservée pour réessayer.'
                  : 'Supprimer définitivement votre compte ? Vos données personnelles, votre bateau et vos appareils seront supprimés. Vos signalements seront conservés sans votre identité, sous « Utilisateur supprimé ». Cette action est irréversible.',
            ),
            if (_failed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Impossible de terminer. Vérifiez votre connexion et réessayez, ou déconnectez-vous : la suppression reprendra à votre prochaine connexion. Si le problème persiste, contactez le support.',
                ),
              ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_finished)
              const Text('Compte supprimé. Session fermée.')
            else ...[
              FilledButton(
                onPressed: _delete,
                child: Text(
                  pending ? 'Réessayer' : 'Supprimer définitivement mon compte',
                ),
              ),
              // Une demande déjà envoyée ne s'annule plus, mais l'utilisateur
              // peut toujours quitter cet écran.
              TextButton(
                onPressed: pending ? _leave : widget.onCancel,
                child: Text(pending ? 'Se déconnecter' : 'Annuler'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

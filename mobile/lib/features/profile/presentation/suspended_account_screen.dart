import 'package:flutter/material.dart';

class SuspendedAccountScreen extends StatelessWidget {
  final VoidCallback onSignOut;

  const SuspendedAccountScreen({super.key, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NoWave')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_outlined, size: 64),
              const SizedBox(height: 24),
              Text(
                'Votre compte est suspendu.',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Vous ne pouvez plus accéder à NoWave tant que '
                'la suspension est active.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onSignOut,
                child: const Text('Déconnexion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

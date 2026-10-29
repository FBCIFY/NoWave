import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/text/capitalize_first_letter_formatter.dart';
import '../data/profile_service.dart';
import '../data/boat_profile_loader.dart';
import '../domain/boat.dart';
import 'profile_panel.dart';
import 'profile_fields.dart';

/// Un seul bateau par compte. Les valeurs saisies restent présentes en erreur.
class BoatScreen extends StatefulWidget {
  const BoatScreen({super.key, required this.profileService, this.boatLoader});
  final ProfileService profileService;
  final BoatProfileLoader? boatLoader;

  @override
  State<BoatScreen> createState() => _BoatScreenState();
}

class _BoatScreenState extends State<BoatScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _country = TextEditingController();
  BoatType _type = BoatType.sailboat;
  Boat? _boat;
  bool _busy = true;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final loader = widget.boatLoader;
    if (loader != null && loader.loaded) {
      _apply(loader.boat);
      _busy = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  void _apply(Boat? boat) {
    widget.boatLoader?.update(boat);
    _boat = boat;
    _type = boat?.type ?? BoatType.sailboat;
    _name.text = boat?.name ?? '';
    _country.text = boat?.flagCountry ?? '';
    _loaded = true;
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final boat =
          await (widget.boatLoader?.load(refresh: refresh) ??
              widget.profileService.getBoat());
      if (mounted) setState(() => _apply(boat));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Impossible de charger le bateau. Vérifiez votre connexion puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _hasChanges =>
      _boat == null ||
      _type != _boat!.type ||
      _name.text.trim() != (_boat!.name ?? '').trim() ||
      _country.text.trim().toUpperCase() !=
          (_boat!.flagCountry ?? '').trim().toUpperCase();

  Future<void> _save() async {
    if (_busy || !_hasChanges || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final boat = await widget.profileService.saveBoat(
        create: _boat == null,
        type: _type,
        name: _name.text,
        flagCountry: _country.text,
      );
      if (mounted) {
        setState(() => _apply(boat));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bateau enregistré.')));
      }
    } catch (error) {
      // Une réponse perdue peut cacher un enregistrement réussi côté serveur.
      widget.boatLoader?.invalidate();
      if (mounted) {
        setState(
          () => _error = error is ApiException && error.statusCode == 409
              ? 'Un bateau existe déjà. Rechargez le bateau pour le consulter avant de le modifier.'
              : 'Enregistrement non confirmé. Vos saisies sont conservées. Réessayez ou rechargez le bateau pour vérifier.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le bateau ?'),
        content: const Text(
          'Les informations de votre bateau seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profileService.deleteBoat();
      if (mounted) setState(() => _apply(null));
    } catch (_) {
      widget.boatLoader?.invalidate();
      if (mounted) {
        setState(
          () => _error = 'Suppression non confirmée. Rechargez le bateau pour vérifier avant de réessayer.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ProfilePanel(
      title: 'Mon bateau',
      onBack: _busy ? null : () => Navigator.of(context).pop(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF8A96A3),
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : () => _load(refresh: true),
              child: const Text('Recharger le bateau'),
            ),
          ],
          if (_loaded)
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _boat == null ? 'Aucun bateau enregistré' : 'Votre bateau',
                  ),
                  const SizedBox(height: 16),
                  ProfileGroup(
                    children: [
                      ProfileField(
                        label: 'Type de bateau',
                        child: DropdownButtonFormField<BoatType>(
                          key: ValueKey(_type),
                          initialValue: _type,
                          isExpanded: true,
                          menuMaxHeight: 280,
                          borderRadius: BorderRadius.circular(14),
                          style: profileValueStyle,
                          decoration: profileInputDecoration,
                          items: [
                            for (final type in BoatType.values)
                              DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (type) => setState(() => _type = type!),
                        ),
                      ),
                      ProfileField(
                        label: 'Nom (facultatif)',
                        child: TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          onChanged: (_) => setState(() {}),
                          style: profileValueStyle,
                          decoration: profileInputDecoration.copyWith(
                            hintText: 'Non renseigné',
                          ),
                          maxLength: 100,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [
                            CapitalizeFirstLetterFormatter(),
                          ],
                          validator: (value) =>
                              (value?.trim().length ?? 0) > 100
                              ? '100 caractères maximum.'
                              : null,
                        ),
                      ),
                      ProfileField(
                        label: 'Pavillon (facultatif)',
                        child: TextFormField(
                          controller: _country,
                          enabled: !_busy,
                          onChanged: (_) => setState(() {}),
                          style: profileValueStyle,
                          decoration: profileInputDecoration.copyWith(
                            hintText: 'Code pays, ex. FR',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          validator: (value) =>
                              value!.trim().isNotEmpty &&
                                  !RegExp(r'^[a-zA-Z]{2}$')
                                      .hasMatch(value.trim())
                              ? 'Saisissez un code pays de deux lettres.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_hasChanges || _busy)
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _boat == null ? 'Créer le bateau' : 'Enregistrer',
                      ),
                    ),
                  if (_boat != null)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                      child: const Text('Supprimer le bateau'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

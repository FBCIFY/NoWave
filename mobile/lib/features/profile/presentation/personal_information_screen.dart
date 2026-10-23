import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/profile_service.dart';
import '../domain/user_profile.dart';
import 'profile_countries.dart';
import 'profile_panel.dart';
import 'profile_fields.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({
    super.key,
    required this.profile,
    required this.service,
  });

  final UserProfile profile;
  final ProfileService service;

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  late DateTime? _birthday = widget.profile.dateOfBirth;
  late String? _nationality = widget.profile.nationality;
  bool _saving = false;
  bool _nationalitiesOpen = false;
  final _nationalityMenuKey = GlobalKey();
  String? _error;

  Future<void> _chooseBirthday() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthday == null || _birthday!.isAfter(today)
          ? today
          : _birthday!.isBefore(DateTime(1900))
          ? DateTime(1900)
          : _birthday,
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('fr'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child!,
      ),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Date de naissance',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
      fieldLabelText: 'Date de naissance',
      errorFormatText: 'Date invalide.',
      errorInvalidText: 'Choisissez une date passée.',
    );
    if (selected != null && mounted) setState(() => _birthday = selected);
  }

  bool get _hasChanges =>
      !DateUtils.isSameDay(_birthday, widget.profile.dateOfBirth) ||
      _nationality != widget.profile.nationality;

  Future<void> _save() async {
    if (_saving || !_hasChanges) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _nationalitiesOpen = false;
      _saving = true;
      _error = null;
    });
    try {
      final profile = await widget.service.updatePersonalInformation(
        dateOfBirth: _birthday,
        nationality: _nationality,
      );
      if (mounted) Navigator.of(context).pop(profile);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Impossible d’enregistrer. Vos saisies sont conservées.';
        });
      }
    }
  }

  String get _birthdayLabel {
    final date = _birthday;
    if (date == null) return 'Non renseignée';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _toggleNationalities() {
    FocusScope.of(context).unfocus();
    setState(() {
      _nationalitiesOpen = !_nationalitiesOpen;
    });
    if (!_nationalitiesOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final menuContext = _nationalityMenuKey.currentContext;
      if (mounted && menuContext != null) {
        Scrollable.ensureVisible(
          menuContext,
          alignment: 1,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _selectNationality(String value) {
    FocusScope.of(context).unfocus();
    setState(() {
      _nationality = value.isEmpty ? null : value;
      _nationalitiesOpen = false;
    });
  }

  Widget _nationalityField() {
    final options = <String, String>{
      '': 'Non renseignée',
      // Le pays actuel reste accessible en tête de liste.
      ?_nationality: profileCountries[_nationality] ?? _nationality!,
      ...profileCountries,
    }.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileField(
          key: const Key('nationalityField'),
          label: 'Nationalité',
          onTap: _saving ? null : _toggleNationalities,
          trailing: Icon(
            _nationalitiesOpen ? Icons.expand_less : Icons.chevron_right,
            size: 20,
            color: const Color(0xFF8A96A3),
          ),
          child: Text(
            profileCountries[_nationality] ?? _nationality ?? 'Non renseignée',
          ),
        ),
        if (_nationalitiesOpen) ...[
          const SizedBox(height: 8),
          Material(
            key: _nationalityMenuKey,
            color: profileInteractiveColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFD7E3EC)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: ListView(
                    key: const Key('nationalityOptions'),
                    padding: EdgeInsets.zero,
                    children: [
                      for (final country in options)
                        ListTile(
                          title: Text(country.value),
                          selected: country.key == (_nationality ?? ''),
                          trailing: country.key == (_nationality ?? '')
                              ? const Icon(Icons.check, size: 20)
                              : null,
                          onTap: () => _selectNationality(country.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: ProfilePanel(
      title: 'Informations personnelles',
      onBack: _saving ? null : () => Navigator.of(context).pop(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ProfileGroup(
            children: [
              ProfileField(
                label: 'Nom d’utilisateur',
                child: Text(widget.profile.username),
              ),
              ProfileField(
                key: const Key('birthdayField'),
                label: 'Date de naissance',
                onTap: _saving ? null : _chooseBirthday,
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF8A96A3),
                ),
                child: Text(_birthdayLabel),
              ),
              _nationalityField(),
            ],
          ),
          if (_birthday != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _birthday = null),
                child: const Text('Effacer la date'),
              ),
            ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
          ],
          if (_hasChanges || _saving)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
            ),
        ],
      ),
    ),
  );
}

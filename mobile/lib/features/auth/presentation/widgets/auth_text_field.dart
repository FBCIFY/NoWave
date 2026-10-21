import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';

/// Champ de saisie du thème sombre. Il gère l'affichage du mot de passe et le
/// bouton pour masquer le clavier.
class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final IconData? icon;
  final bool obscureText;
  final bool enableInteractiveSelection;

  /// Prend le focus à l'affichage, même si un autre champ l'a encore : le
  /// clavier reste ouvert en passant d'une page à l'autre d'un parcours.
  final bool autofocus;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;

  /// Remplace le passage au champ suivant quand l'utilisateur valide au
  /// clavier : le champ garde le focus, et le clavier reste ouvert.
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.icon,
    this.obscureText = false,
    this.enableInteractiveSelection = true,
    this.autofocus = false,
    this.maxLength,
    this.inputFormatters,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  static const _suffixButtonSize = 36.0;
  static final _suffixButtonStyle = IconButton.styleFrom(
    minimumSize: const Size.square(_suffixButtonSize),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  final _focusNode = FocusNode();

  late bool _isObscured;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
    if (widget.autofocus) _focusNode.requestFocus();

    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _hasFocus = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.cyan500, width: 1.5),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          maxLength: widget.maxLength,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          focusNode: _focusNode,
          obscureText: _isObscured,
          enableInteractiveSelection: widget.enableInteractiveSelection,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          validator: widget.validator,
          onFieldSubmitted: widget.onFieldSubmitted,
          onEditingComplete: widget.onEditingComplete,
          onTapOutside: (_) => _focusNode.unfocus(),
          autocorrect: false,
          enableSuggestions: !widget.obscureText,
          cursorColor: AppColors.cyan500,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            counterStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.30),
              fontSize: 9,
            ),
            // Sinon, Flutter impose au champ 48 px de haut au minimum.
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: _hasFocus ? 0.16 : 0.10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            prefixIcon: widget.icon == null
                ? null
                : Icon(
                    widget.icon,
                    size: 18,
                    color: AppColors.cyan500.withValues(alpha: 0.80),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            // Sans ça, les boutons du bout du champ lui imposent 48 px de
            // haut : il grandirait en prenant le focus.
            suffixIconConstraints: const BoxConstraints(
              minWidth: _suffixButtonSize,
              minHeight: _suffixButtonSize,
            ),
            suffixIcon: widget.obscureText || _hasFocus
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.obscureText)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _isObscured = !_isObscured;
                            });
                          },
                          style: _suffixButtonStyle,
                          tooltip: _isObscured
                              ? 'Afficher le mot de passe'
                              : 'Masquer le mot de passe',
                          icon: Icon(
                            _isObscured
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      if (_hasFocus)
                        IconButton(
                          onPressed: _focusNode.unfocus,
                          style: _suffixButtonStyle,
                          tooltip: 'Masquer le clavier',
                          icon: Icon(
                            Icons.keyboard_hide_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.60),
                          ),
                        ),
                    ],
                  )
                : null,
            border: normalBorder,
            enabledBorder: normalBorder,
            focusedBorder: focusedBorder,
            errorBorder: normalBorder.copyWith(
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: focusedBorder.copyWith(
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            errorStyle: const TextStyle(color: Color(0xFFFFCDD2), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

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
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.icon,
    this.obscureText = false,
    this.enableInteractiveSelection = true,
    this.maxLength,
    this.inputFormatters,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final _focusNode = FocusNode();

  late bool _isObscured;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;

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
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.cyan500.withValues(alpha: 0.50)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
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
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          validator: widget.validator,
          onFieldSubmitted: widget.onFieldSubmitted,
          onTapOutside: (_) => _focusNode.unfocus(),
          autocorrect: false,
          enableSuggestions: !widget.obscureText,
          cursorColor: AppColors.cyan500,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
            counterStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.30),
              fontSize: 10,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: _hasFocus ? 0.12 : 0.08),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            prefixIcon: widget.icon == null
                ? null
                : Icon(
                    widget.icon,
                    size: 18,
                    color: AppColors.cyan500.withValues(alpha: 0.50),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 42),
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
                          tooltip: _isObscured
                              ? 'Afficher le mot de passe'
                              : 'Masquer le mot de passe',
                          icon: Icon(
                            _isObscured
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      if (_hasFocus)
                        IconButton(
                          onPressed: _focusNode.unfocus,
                          tooltip: 'Masquer le clavier',
                          icon: Icon(
                            Icons.keyboard_hide_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.45),
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

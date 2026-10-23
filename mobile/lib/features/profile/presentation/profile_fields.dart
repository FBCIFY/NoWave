import 'package:flutter/material.dart';

const profileInteractiveColor = Color(0xFFF0F2F5);

const profileValueStyle = TextStyle(fontSize: 16, color: Color(0xFF172330));
const profileInputDecoration = InputDecoration(
  isDense: true,
  filled: false,
  contentPadding: EdgeInsets.zero,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
);

/// Un groupe de réglages, commun aux pages du profil.
class ProfileGroup extends StatelessWidget {
  const ProfileGroup({
    super.key,
    required this.children,
    this.color = profileInteractiveColor,
  });
  final List<Widget> children;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            const Divider(height: 1, indent: 16, color: Color(0xFFE7EBEF)),
          children[index],
        ],
      ],
    ),
  );
}

/// Même présentation pour une valeur, une saisie et un choix.
class ProfileField extends StatelessWidget {
  const ProfileField({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
    this.trailing,
  });
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF637180),
                  ),
                ),
                const SizedBox(height: 6),
                DefaultTextStyle.merge(style: profileValueStyle, child: child),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    ),
  );
}

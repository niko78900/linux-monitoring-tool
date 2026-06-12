import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

class TerminalAccessoryBar extends StatelessWidget {
  const TerminalAccessoryBar({
    super.key,
    required this.ctrlEnabled,
    required this.altEnabled,
    required this.onCtrlToggle,
    required this.onAltToggle,
    required this.onKeyPressed,
    required this.onShortcutPressed,
  });

  final bool ctrlEnabled;
  final bool altEnabled;
  final ValueChanged<bool> onCtrlToggle;
  final ValueChanged<bool> onAltToggle;
  final ValueChanged<String> onKeyPressed;
  final ValueChanged<String> onShortcutPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          _ToggleKeyChip(
            label: 'Ctrl',
            selected: ctrlEnabled,
            onSelected: onCtrlToggle,
          ),
          const SizedBox(width: AppSpacing.sm),
          _ToggleKeyChip(
            label: 'Alt',
            selected: altEnabled,
            onSelected: onAltToggle,
          ),
          const SizedBox(width: AppSpacing.sm),
          for (final key in const [
            'Esc',
            'Tab',
            '|',
            '/',
            '-',
            '_',
            '~',
            'Up',
            'Down',
            'Left',
            'Right',
          ]) ...[
            _KeyChip(label: key, onPressed: () => onKeyPressed(key)),
            const SizedBox(width: AppSpacing.sm),
          ],
          for (final shortcut in const ['Ctrl+C', 'Ctrl+D', 'Ctrl+L']) ...[
            _KeyChip(
              label: shortcut,
              onPressed: () => onShortcutPressed(shortcut),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      child: Text(label),
    );
  }
}

class _ToggleKeyChip extends StatelessWidget {
  const _ToggleKeyChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
    );
  }
}

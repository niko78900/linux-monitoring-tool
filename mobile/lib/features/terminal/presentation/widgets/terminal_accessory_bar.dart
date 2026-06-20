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
    this.compact = false,
  });

  final bool ctrlEnabled;
  final bool altEnabled;
  final ValueChanged<bool> onCtrlToggle;
  final ValueChanged<bool> onAltToggle;
  final ValueChanged<String> onKeyPressed;
  final ValueChanged<String> onShortcutPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 44.0 : 52.0;
    final verticalPadding = compact ? AppSpacing.xs : AppSpacing.sm;
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: verticalPadding,
        ),
        children: [
          _ToggleKeyChip(
            label: 'Ctrl',
            selected: ctrlEnabled,
            onSelected: onCtrlToggle,
            compact: compact,
          ),
          const SizedBox(width: AppSpacing.sm),
          _ToggleKeyChip(
            label: 'Alt',
            selected: altEnabled,
            onSelected: onAltToggle,
            compact: compact,
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
            _KeyChip(
              label: key,
              compact: compact,
              onPressed: () => onKeyPressed(key),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          for (final shortcut in const ['Ctrl+C', 'Ctrl+D', 'Ctrl+L']) ...[
            _KeyChip(
              label: shortcut,
              compact: compact,
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
  const _KeyChip({
    required this.label,
    required this.onPressed,
    required this.compact,
  });

  final String label;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: compact ? VisualDensity.compact : null,
        minimumSize: Size(0, compact ? 32 : 36),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        ),
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
    required this.compact,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }
}

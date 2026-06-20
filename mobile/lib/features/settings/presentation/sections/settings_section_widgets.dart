import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../server_widget/data/server_widget_catalog.dart';

class PollingField extends StatelessWidget {
  const PollingField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 1000, child: Text('1 second')),
          DropdownMenuItem(value: 3000, child: Text('3 seconds')),
          DropdownMenuItem(value: 5000, child: Text('5 seconds')),
          DropdownMenuItem(value: 10000, child: Text('10 seconds')),
          DropdownMenuItem(value: 15000, child: Text('15 seconds')),
          DropdownMenuItem(value: 30000, child: Text('30 seconds')),
          DropdownMenuItem(value: 60000, child: Text('1 minute')),
        ],
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
      ),
    );
  }
}

class SettingsInfoLine extends StatelessWidget {
  const SettingsInfoLine({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(value)
        : Text(value, style: Theme.of(context).textTheme.bodyMedium);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: valueWidget),
      ],
    );
  }
}

class WidgetCatalogCard extends StatelessWidget {
  const WidgetCatalogCard({
    super.key,
    required this.widget,
    required this.requesting,
    required this.onAdd,
  });

  final HomeScreenWidgetDescriptor widget;
  final bool requesting;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.widgets),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${widget.recommendedSize} | ${widget.purpose}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: requesting ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(requesting ? 'Adding...' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../server_widget/data/server_widget_catalog.dart';
import 'settings_section_widgets.dart';

class WidgetSettingsSection extends StatelessWidget {
  const WidgetSettingsSection({
    super.key,
    required this.settings,
    required this.mountpointController,
    required this.labelController,
    required this.secondaryMountpointController,
    required this.secondaryLabelController,
    required this.requestingWidgetPinProvider,
    required this.onSave,
    required this.onRefreshSnapshots,
    required this.onRequestPinWidget,
  });

  final AppSettings settings;
  final TextEditingController mountpointController;
  final TextEditingController labelController;
  final TextEditingController secondaryMountpointController;
  final TextEditingController secondaryLabelController;
  final String? requestingWidgetPinProvider;
  final ValueChanged<AppSettings> onSave;
  final VoidCallback onRefreshSnapshots;
  final ValueChanged<String> onRequestPinWidget;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Widgets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Home-screen widgets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: mountpointController,
            decoration: const InputDecoration(
              labelText: 'Primary storage mountpoint',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'Primary widget label',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: secondaryMountpointController,
            decoration: const InputDecoration(
              labelText: 'Secondary storage mountpoint',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: secondaryLabelController,
            decoration: const InputDecoration(
              labelText: 'Secondary widget label',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.widgetShowSecondaryStorage,
            onChanged: (value) =>
                onSave(settings.copyWith(widgetShowSecondaryStorage: value)),
            title: const Text('Show secondary storage row'),
          ),
          DropdownButtonFormField<int>(
            initialValue: settings.widgetBackgroundRefreshMinutes,
            decoration: const InputDecoration(
              labelText: 'Background refresh interval',
            ),
            items: const [
              DropdownMenuItem(value: 15, child: Text('15 minutes')),
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
              DropdownMenuItem(value: 60, child: Text('60 minutes')),
            ],
            onChanged: (value) {
              if (value != null) {
                onSave(
                  settings.copyWith(widgetBackgroundRefreshMinutes: value),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.widgetShowNetworkThroughput,
            onChanged: (value) =>
                onSave(settings.copyWith(widgetShowNetworkThroughput: value)),
            title: const Text('Show network throughput row'),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: () => onSave(
                  settings.copyWith(
                    widgetStorageMountpoint: mountpointController.text,
                    widgetStorageLabel: labelController.text,
                    widgetSecondaryStorageMountpoint:
                        secondaryMountpointController.text,
                    widgetSecondaryStorageLabel: secondaryLabelController.text,
                  ),
                ),
                child: const Text('Save widget settings'),
              ),
              OutlinedButton.icon(
                onPressed: onRefreshSnapshots,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh widget data now'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: columns == 1 ? 4.2 : 3.2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final widget in homeScreenWidgets)
                    WidgetCatalogCard(
                      widget: widget,
                      requesting:
                          requestingWidgetPinProvider == widget.providerName,
                      onAdd: () => onRequestPinWidget(widget.providerName),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

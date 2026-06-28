import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.rawValue,
    this.infoTooltip,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? rawValue;
  final String? infoTooltip;

  @override
  Widget build(BuildContext context) {
    final detailsValue = _rawValueForDetails;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          if (detailsValue != null)
            IconButton(
              tooltip: infoTooltip ?? 'Show raw $label value',
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => _showDetailsDialog(context, detailsValue),
            ),
        ],
      ),
    );
  }

  String? get _rawValueForDetails {
    final raw = rawValue?.trim();
    if (raw == null || raw.isEmpty || raw == value.trim()) {
      return null;
    }
    return raw;
  }

  void _showDetailsDialog(BuildContext context, String detailsValue) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(label),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(child: SelectableText(detailsValue)),
          ),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: detailsValue)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

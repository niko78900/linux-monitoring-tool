import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: EmptyState(
        icon: Icons.devices_other,
        title: 'Known devices pending control agent',
        message:
            'Phase 7 will load manually configured known devices from the control agent. Without router API access, this view will be a known-device dashboard rather than a full network inventory.',
      ),
    );
  }
}

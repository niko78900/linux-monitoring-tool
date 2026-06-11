import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';

class ActionsPage extends StatelessWidget {
  const ActionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: EmptyState(
        icon: Icons.power_settings_new,
        title: 'Wake-on-LAN arrives with the control agent',
        message:
            'This privileged tab is gated now. Phase 6 will add a fixed, allowlisted Wake Main PC action through control_agent. The mobile app will not accept arbitrary MAC addresses.',
      ),
    );
  }
}

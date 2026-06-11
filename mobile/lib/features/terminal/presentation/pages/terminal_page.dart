import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';

class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: EmptyState(
        icon: Icons.terminal,
        title: 'SSH terminal configured later',
        message:
            'Phase 4 will add direct dartssh2 SSH with xterm, host-key verification, PTY resize, reconnect, and touch-friendly control keys.',
      ),
    );
  }
}

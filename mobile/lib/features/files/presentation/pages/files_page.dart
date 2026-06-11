import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: EmptyState(
        icon: Icons.folder,
        title: 'Restricted SFTP browser configured later',
        message:
            'Phase 5 will add direct restricted SFTP browsing for the warm-storage root with streaming downloads and a transfer queue. Destructive file operations stay disabled.',
      ),
    );
  }
}

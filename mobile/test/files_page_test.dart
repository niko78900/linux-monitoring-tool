import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/files/presentation/pages/files_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows restricted-key import state when SFTP key is missing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'sftp.host': 'server.tailnet.ts.net',
      'sftp.port': 22,
      'sftp.username': 'tablet_files',
      'sftp.hasImportedKey': false,
      'sftpVirtualRoot': '/warm',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );

    await tester.pump();

    expect(find.text('Import the restricted SFTP key'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });
}

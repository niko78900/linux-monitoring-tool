import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/terminal/presentation/pages/terminal_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows private-key import state when SSH key is missing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'ssh.host': 'server.tailnet.ts.net',
      'ssh.port': 22,
      'ssh.username': 'tablet_shell',
      'ssh.hasImportedKey': false,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: TerminalPage())),
      ),
    );

    await tester.pump();

    expect(find.text('Private key required'), findsOneWidget);
    expect(find.text('Configure SSH host and user'), findsOneWidget);
    expect(find.text('Import private key'), findsOneWidget);
    expect(find.text('Trust host fingerprint'), findsOneWidget);
    expect(find.text('Open SSH Settings'), findsOneWidget);
    expect(find.text('Import Key'), findsOneWidget);
  });

  testWidgets(
    'shows connection header and quick input when SSH is configured',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboardingComplete': true,
        'ssh.displayName': 'Homelab SSH',
        'ssh.host': 'server.tailnet.ts.net',
        'ssh.port': 22,
        'ssh.username': 'tablet_shell',
        'ssh.hasImportedKey': true,
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const MaterialApp(home: Scaffold(body: TerminalPage())),
        ),
      );

      await tester.pump();

      expect(find.text('Homelab SSH'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('server.tailnet.ts.net:22'), findsOneWidget);
      expect(find.text('tablet_shell'), findsOneWidget);
      expect(find.text('Quick input'), findsOneWidget);
      expect(find.text('docker ps'), findsOneWidget);
    },
  );

  testWidgets('uses compact layout in constrained landscape height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'ssh.displayName': 'Homelab SSH',
      'ssh.host': 'server.tailnet.ts.net',
      'ssh.port': 22,
      'ssh.username': 'tablet_shell',
      'ssh.hasImportedKey': true,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: TerminalPage())),
      ),
    );

    await tester.pump();

    expect(find.text('Homelab SSH'), findsOneWidget);
    expect(find.text('Quick input'), findsNothing);
    expect(find.text('Ctrl'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

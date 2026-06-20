import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings renders widget and push alert actions', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'controlApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Widgets'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Widgets'), findsOneWidget);
    expect(find.text('Server Essentials'), findsOneWidget);
    expect(find.text('Compact Status'), findsOneWidget);
    expect(find.text('Primary widget label'), findsOneWidget);
    expect(find.text('Secondary widget label'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Push notifications'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('Mobile-alert backend token'), findsOneWidget);
    expect(find.text('Send test notification'), findsOneWidget);
  });

  testWidgets('settings renders SFTP background timeout option', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'sftpBackgroundTimeout': 'fifteenMinutes',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('SFTP background timeout'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('SFTP background timeout'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);
  });

  testWidgets('settings supports one and three second polling intervals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'summaryPollingMs': 1000,
      'detailsPollingMs': 3000,
      'healthPollingMs': 1000,
      'dockerPollingMs': 3000,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pump();

    expect(find.text('1 second'), findsWidgets);
    expect(find.text('3 seconds'), findsWidgets);
  });
}

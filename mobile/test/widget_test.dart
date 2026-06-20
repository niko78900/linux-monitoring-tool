import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/app.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows onboarding before setup is complete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const HomelabTabletApp(),
      ),
    );

    expect(find.text('Homelab Tablet'), findsOneWidget);
    expect(find.text('Monitoring API'), findsOneWidget);
  });

  testWidgets('onboarding shows tablet API examples and advances stably', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const HomelabTabletApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('http://100.64.10.22:4040/api'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('Android emulator only'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Monitoring API URL'),
      'http://100.64.10.22:4040/api',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
    await tester.pumpAndSettle();

    expect(find.text('Control API'), findsWidgets);
    expect(
      find.textContaining('http://100.64.10.22:4042/api'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('/control/api'), findsNothing);
  });

  testWidgets('shows overview shell after onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const HomelabTabletApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Homelab Tablet'), findsWidgets);
    expect(find.byIcon(Icons.dashboard), findsWidgets);
  });

  testWidgets('saving unrelated settings does not leave settings route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': 'http://100.64.10.22:4040/api',
    });
    final preferences = await SharedPreferences.getInstance();
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const HomelabTabletApp(initialWidgetRoute: '/settings');
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Monitoring'), findsOneWidget);

    final settings = capturedRef.read(settingsControllerProvider);
    capturedRef
        .read(settingsControllerProvider.notifier)
        .save(settings.copyWith(showRawApiErrors: true));
    await tester.pumpAndSettle();

    expect(find.text('Monitoring'), findsOneWidget);
    expect(find.text('CPU Usage'), findsNothing);
  });
}

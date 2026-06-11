import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/actions/presentation/pages/actions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows control-agent setup state when URL is missing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'controlApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: ActionsPage())),
      ),
    );

    await tester.pump();

    expect(find.text('Configure the control agent first'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/terminal/domain/models/ssh_connection_models.dart';
import 'package:homelab_tablet/features/terminal/presentation/widgets/terminal_connection_dialogs.dart';

void main() {
  testWidgets('passphrase prompt returns passphrase and remember choice', (
    tester,
  ) async {
    PassphrasePromptResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showPassphrasePromptDialog(
                    context,
                    title: 'Enter passphrase',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret-passphrase');
    await tester.tap(find.text('Remember in secure storage'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result?.passphrase, 'secret-passphrase');
    expect(result?.remember, isTrue);
  });
}

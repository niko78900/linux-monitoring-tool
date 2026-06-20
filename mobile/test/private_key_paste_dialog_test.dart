import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/settings/presentation/widgets/private_key_paste_dialog.dart';

void main() {
  testWidgets('private key paste dialog returns pasted text', (tester) async {
    String? result;
    await _pumpDialogHost(tester, (context) async {
      result = await showPrivateKeyPasteDialog(
        context,
        title: 'Paste private key',
        label: 'PEM or OpenSSH private key',
      );
    });

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '-----BEGIN OPENSSH PRIVATE KEY-----\nabc',
    );
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(result, '-----BEGIN OPENSSH PRIVATE KEY-----\nabc');
    expect(tester.takeException(), isNull);
  });

  testWidgets('private key paste dialog returns null on cancel', (
    tester,
  ) async {
    var result = 'unchanged';
    await _pumpDialogHost(tester, (context) async {
      result =
          await showPrivateKeyPasteDialog(
            context,
            title: 'Paste private key',
            label: 'PEM or OpenSSH private key',
          ) ??
          'cancelled';
    });

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, 'cancelled');
    expect(tester.takeException(), isNull);
  });

  testWidgets('private key paste dialog opens and closes repeatedly', (
    tester,
  ) async {
    await _pumpDialogHost(tester, (context) async {
      await showPrivateKeyPasteDialog(
        context,
        title: 'Paste private key',
        label: 'PEM or OpenSSH private key',
      );
    });

    for (var index = 0; index < 3; index += 1) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('private key paste dialog handles keyboard insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await _pumpDialogHost(tester, (context) async {
      await showPrivateKeyPasteDialog(
        context,
        title: 'Paste private key',
        label: 'PEM or OpenSSH private key',
      );
    });

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Paste private key'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialogHost(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onOpen,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () => onOpen(context),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

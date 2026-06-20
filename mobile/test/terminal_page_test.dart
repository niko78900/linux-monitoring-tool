import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/terminal/data/ssh_connection_service.dart';
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

  testWidgets('closes stale SSH connection after page disposal', (
    tester,
  ) async {
    final service = _FakeSshConnectionClient();
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: TerminalPage())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();

    final connection = _FakeSshShellConnection();
    await tester.pumpWidget(const SizedBox.shrink());
    service.complete(connection);
    await tester.pump();

    expect(connection.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnect cancels pending SSH connection attempt', (
    tester,
  ) async {
    final service = _FakeSshConnectionClient();
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: TerminalPage())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    final connection = _FakeSshShellConnection();
    service.complete(connection);
    await tester.pump();

    expect(connection.closed, isTrue);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeSshConnectionClient implements SshConnectionClient {
  final _openCompleter = Completer<SshShellConnection>();

  void complete(SshShellConnection connection) {
    _openCompleter.complete(connection);
  }

  @override
  Future<SshShellConnection> openShell({
    required ConnectionProfile profile,
    required int width,
    required int height,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) {
    return _openCompleter.future;
  }

  @override
  Future<String?> readTrustedFingerprint(ConnectionProfile profile) async {
    return null;
  }

  @override
  Future<void> resetTrustedFingerprint(ConnectionProfile profile) async {}

  @override
  Future<void> testConnection({
    required ConnectionProfile profile,
    required SshHostTrustPrompt onTrustHost,
    SshPassphrasePrompt? onPassphraseRequired,
  }) async {}
}

class _FakeSshShellConnection implements SshShellConnection {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  bool closed = false;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closed = true;
    await _stdout.close();
    await _stderr.close();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  void resizeTerminal(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  void write(Uint8List data) {}
}

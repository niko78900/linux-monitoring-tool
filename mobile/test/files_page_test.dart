import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/files/data/sftp_connection_service.dart';
import 'package:homelab_tablet/features/files/presentation/pages/files_page.dart';
import 'package:homelab_tablet/features/terminal/domain/models/ssh_connection_models.dart';
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

  testWidgets('auto-connects configured SFTP profile on open', (tester) async {
    final service = _FakeSftpConnectionClient();
    SharedPreferences.setMockInitialValues(_configuredSftpSettings());
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sftpConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );

    await tester.pump();

    expect(service.openCount, 1);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('manual disconnect suppresses immediate auto-reconnect', (
    tester,
  ) async {
    final service = _FakeSftpConnectionClient();
    SharedPreferences.setMockInitialValues(_configuredSftpSettings());
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sftpConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );

    await tester.pump();
    expect(service.openCount, 1);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();

    expect(service.openCount, 1);
    expect(find.text('Disconnected'), findsOneWidget);
  });

  testWidgets('closes stale SFTP connection after page disposal', (
    tester,
  ) async {
    final service = _FakeSftpConnectionClient();
    SharedPreferences.setMockInitialValues(_configuredSftpSettings());
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sftpConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );
    await tester.pump();

    final connection = _FakeSftpSessionConnection();
    await tester.pumpWidget(const SizedBox.shrink());
    service.complete(connection);
    await tester.pump();

    expect(connection.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnect cancels pending SFTP connection attempt', (
    tester,
  ) async {
    final service = _FakeSftpConnectionClient();
    SharedPreferences.setMockInitialValues(_configuredSftpSettings());
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sftpConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    final connection = _FakeSftpSessionConnection();
    service.complete(connection);
    await tester.pump();

    expect(connection.closed, isTrue);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows friendly SFTP key error without raw parser cause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = _ThrowingSftpConnectionClient(
      const SshInvalidPrivateKeyException.sftp(
        cause: FormatException('PEM header must start with ---- BEGIN'),
      ),
    );
    SharedPreferences.setMockInitialValues(_configuredSftpSettings());
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sftpConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: FilesPage())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'The imported SFTP private key is invalid. Remove it and import the private key file again, not the .pub file.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.textContaining('PEM header'), findsNothing);
  });
}

Map<String, Object> _configuredSftpSettings() {
  return {
    'onboardingComplete': true,
    'sftp.displayName': 'Files',
    'sftp.host': 'server.tailnet.ts.net',
    'sftp.port': 22,
    'sftp.username': 'tablet_files',
    'sftp.hasImportedKey': true,
    'sftpVirtualRoot': '/warm',
  };
}

class _FakeSftpConnectionClient implements SftpConnectionClient {
  final _openCompleter = Completer<SftpSessionConnection>();
  int openCount = 0;

  void complete(SftpSessionConnection connection) {
    _openCompleter.complete(connection);
  }

  @override
  Future<SftpSessionConnection> open({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) {
    openCount += 1;
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
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) async {}
}

class _ThrowingSftpConnectionClient implements SftpConnectionClient {
  const _ThrowingSftpConnectionClient(this.error);

  final Object error;

  @override
  Future<SftpSessionConnection> open({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) async {
    throw error;
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
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
  }) async {}
}

class _FakeSftpSessionConnection implements SftpSessionConnection {
  bool closed = false;

  @override
  SftpClient get sftp => throw StateError('stale SFTP should not be used');

  @override
  Future<void> close() async {
    closed = true;
  }
}

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/files/data/sftp_connection_service.dart';
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
    await tester.tap(find.text('Connect'));
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
    await tester.tap(find.text('Connect'));
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

  void complete(SftpSessionConnection connection) {
    _openCompleter.complete(connection);
  }

  @override
  Future<SftpSessionConnection> open({
    required ConnectionProfile profile,
    required SftpHostTrustPrompt onTrustHost,
    SftpPassphrasePrompt? onPassphraseRequired,
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

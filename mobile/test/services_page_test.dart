import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/errors/app_exception.dart';
import 'package:homelab_tablet/features/services/data/service_repository.dart';
import 'package:homelab_tablet/features/services/domain/models/service_models.dart';
import 'package:homelab_tablet/features/services/presentation/pages/services_page.dart';

void main() {
  testWidgets('renders service cards', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(
            FakeServiceRepository(services: [_service()]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('HTTP healthy'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
  });

  testWidgets('shows confirmation dialog before action', (tester) async {
    final repository = FakeServiceRepository(services: [_service()]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    expect(find.text('Restart Jellyfin?'), findsOneWidget);
  });

  testWidgets('disables buttons while action is pending', (tester) async {
    final repository = FakeServiceRepository(
      services: [_service()],
      actionDelay: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart').last);
    await tester.pump();

    final restartButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Restart'),
    );
    expect(restartButton.onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state when service list fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(
            FakeServiceRepository(error: const AppException('offline')),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Service controls unavailable'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
  });
}

class FakeServiceRepository extends ServiceRepository {
  FakeServiceRepository({
    this.services = const [],
    this.error,
    this.actionDelay = Duration.zero,
  });

  final List<ManagedService> services;
  final AppException? error;
  final Duration actionDelay;

  @override
  Future<List<ManagedService>> getServices() async {
    if (error != null) {
      throw error!;
    }
    return services;
  }

  @override
  Future<ManagedService> getService(String serviceId) async {
    return services.firstWhere((service) => service.serviceId == serviceId);
  }

  @override
  Future<ServiceActionResult> sendAction({
    required String serviceId,
    required String action,
  }) async {
    if (actionDelay > Duration.zero) {
      await Future<void>.delayed(actionDelay);
    }
    return ServiceActionResult(
      serviceId: serviceId,
      action: action,
      status: 'accepted',
      requestedAt: DateTime.utc(2026, 6, 11, 20),
      detail: 'accepted',
    );
  }
}

ManagedService _service() {
  return ManagedService(
    serviceId: 'jellyfin',
    displayName: 'Jellyfin',
    hostId: 'homelab-server',
    runtimeAdapter: 'docker',
    runtimeState: 'running',
    healthProbeState: 'healthy',
    lastChecked: DateTime.utc(2026, 6, 11, 20),
    allowedActions: const ['start', 'stop', 'restart'],
    lastAction: const ServiceActionResult(
      serviceId: 'jellyfin',
      action: 'restart',
      status: 'accepted',
      requestedAt: null,
      detail: 'accepted',
    ),
  );
}

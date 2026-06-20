import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homelab_tablet/core/errors/app_exception.dart';
import 'package:homelab_tablet/features/services/data/service_repository.dart';
import 'package:homelab_tablet/features/services/domain/models/service_models.dart';
import 'package:homelab_tablet/features/services/presentation/pages/service_detail_page.dart';
import 'package:homelab_tablet/features/services/presentation/pages/services_page.dart';
import 'package:homelab_tablet/features/services/presentation/service_dashboard_filters.dart';

void main() {
  testWidgets('renders service cards', (tester) async {
    _setTabletSurface(tester);
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
    expect(find.text('Running'), findsAtLeastNWidgets(1));
    expect(find.text('HTTP healthy'), findsOneWidget);
    expect(find.text('media'), findsAtLeastNWidgets(1));
    expect(find.text('8096/tcp'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
  });

  testWidgets('tapping service details opens detail page', (tester) async {
    _setTabletSurface(tester);
    final repository = FakeServiceRepository(services: [_service()]);
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesPage(),
          routes: [
            GoRoute(
              path: ':serviceId',
              builder: (context, state) => ServiceDetailPage(
                serviceId: state.pathParameters['serviceId'] ?? '',
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    final detailsButton = find.widgetWithText(OutlinedButton, 'Details');
    await tester.ensureVisible(detailsButton);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(find.text('Runtime'), findsOneWidget);
    expect(find.text('Container'), findsOneWidget);
    expect(find.text('jellyfin'), findsAtLeastNWidgets(1));
  });

  testWidgets('empty state still works when no services are configured', (
    tester,
  ) async {
    _setTabletSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No services configured'), findsOneWidget);
  });

  testWidgets('shows confirmation dialog before action', (tester) async {
    _setTabletSurface(tester);
    final repository = FakeServiceRepository(services: [_service()]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviceRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();
    final restartButtonFinder = find.widgetWithText(OutlinedButton, 'Restart');
    await tester.ensureVisible(restartButtonFinder);
    await tester.tap(restartButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Restart Jellyfin?'), findsOneWidget);
  });

  testWidgets('disables buttons while action is pending', (tester) async {
    _setTabletSurface(tester);
    final repository = FakeServiceRepository(
      services: [_service()],
      actionDelay: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviceRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: ServicesPage())),
      ),
    );

    await tester.pumpAndSettle();
    final restartButtonFinder = find.widgetWithText(OutlinedButton, 'Restart');
    await tester.ensureVisible(restartButtonFinder);
    await tester.tap(restartButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart').last);
    await tester.pump();

    final restartButton = tester.widget<OutlinedButton>(restartButtonFinder);
    expect(restartButton.onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state when service list fails', (tester) async {
    _setTabletSurface(tester);
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

  test('filters services by category, runtime, health, and search', () {
    final services = [
      _service(),
      _service(
        serviceId: 'crafty',
        displayName: 'Crafty',
        category: 'game',
        runtimeState: 'running',
        healthProbeState: 'healthy',
      ),
      _service(
        serviceId: 'hfs',
        displayName: 'HFS',
        category: 'files',
        runtimeState: 'stopped',
        healthProbeState: 'timeout',
      ),
    ];

    final filtered = filterAndSortServices(
      services: services,
      searchQuery: 'jelly',
      category: 'media',
      runtime: 'running',
      health: 'healthy',
      sortMode: ServiceSortMode.name,
    );

    expect(filtered.map((service) => service.serviceId), ['jellyfin']);
  });

  test('sorts unhealthy services first', () {
    final services = [
      _service(serviceId: 'healthy', displayName: 'Healthy'),
      _service(
        serviceId: 'unhealthy',
        displayName: 'Unhealthy',
        healthProbeState: 'unreachable',
      ),
      _service(
        serviceId: 'stopped',
        displayName: 'Stopped',
        runtimeState: 'stopped',
      ),
    ];

    final sorted = filterAndSortServices(
      services: services,
      searchQuery: '',
      category: 'all',
      runtime: 'all',
      health: 'all',
      sortMode: ServiceSortMode.unhealthyFirst,
    );

    expect(sorted.map((service) => service.serviceId), [
      'unhealthy',
      'stopped',
      'healthy',
    ]);
  });
}

void _setTabletSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

ManagedService _service({
  String serviceId = 'jellyfin',
  String displayName = 'Jellyfin',
  String hostId = 'homelab-server',
  String runtimeAdapter = 'docker',
  String runtimeTarget = 'jellyfin',
  String runtimeState = 'running',
  String healthProbeState = 'healthy',
  String category = 'media',
  String? description = 'Media streaming server',
  String? url = 'http://127.0.0.1:8096',
  List<String> ports = const ['8096/tcp'],
  String? image = 'jellyfin/jellyfin',
  ServiceActionResult? lastAction = const ServiceActionResult(
    serviceId: 'jellyfin',
    action: 'restart',
    status: 'accepted',
    requestedAt: null,
    detail: 'accepted',
  ),
}) {
  return ManagedService(
    serviceId: serviceId,
    displayName: displayName,
    hostId: hostId,
    runtimeAdapter: runtimeAdapter,
    runtimeTarget: runtimeTarget,
    runtimeState: runtimeState,
    healthProbeState: healthProbeState,
    category: category,
    description: description,
    url: url,
    ports: ports,
    image: image,
    lastChecked: DateTime.utc(2026, 6, 11, 20),
    allowedActions: const ['start', 'stop', 'restart'],
    lastAction: lastAction,
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../network/data/control_repository.dart';
import '../../domain/models/host_models.dart';

final managedHostsProvider = FutureProvider<ManagedHostsDashboard>((ref) async {
  return ref.watch(controlRepositoryProvider).fetchHostsDashboard();
});

final managedHostProvider = FutureProvider.family<ManagedHost, String>((
  ref,
  hostId,
) async {
  final dashboard = await ref.watch(managedHostsProvider.future);
  return dashboard.hosts.firstWhere(
    (host) => host.id == hostId,
    orElse: () => throw StateError('Managed host not found'),
  );
});

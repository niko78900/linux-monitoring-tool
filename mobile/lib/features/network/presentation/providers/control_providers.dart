import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/control_repository.dart';
import '../../domain/models/device_models.dart';

final devicesDashboardProvider = FutureProvider<DevicesDashboard>((ref) async {
  return ref.watch(controlRepositoryProvider).fetchDevicesDashboard();
});

final knownDeviceProvider = FutureProvider.family<KnownDevice, String>((
  ref,
  deviceId,
) async {
  final dashboard = await ref.watch(devicesDashboardProvider.future);
  return dashboard.devices.firstWhere(
    (device) => device.id == deviceId,
    orElse: () => throw StateError('Device not found'),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/secure_storage_service.dart';
import '../domain/models/device_models.dart';
import 'control_api_client.dart';

final controlRepositoryProvider = Provider<ControlRepository>((ref) {
  return ControlRepository(
    readSettings: () => ref.read(settingsControllerProvider),
    storage: ref.watch(secureStorageServiceProvider),
  );
});

class ControlRepository {
  ControlRepository({
    required AppSettings Function() readSettings,
    required SecureStorageService storage,
  }) : _readSettings = readSettings,
       _storage = storage;

  final AppSettings Function() _readSettings;
  final SecureStorageService _storage;

  Future<ControlHealth> getHealth() async {
    final client = await _client();
    return client.getHealth();
  }

  Future<DevicesDashboard> fetchDevicesDashboard() async {
    final client = await _client();
    final devices = await client.getDevices();
    final neighbors = await client.getNeighbors();
    return DevicesDashboard(
      devices: devices,
      neighbors: neighbors.neighbors,
      neighborsNotice: neighbors.notice,
    );
  }

  Future<WakeActionResult> wakeMainPc() async {
    final client = await _client();
    return client.wakeMainPc();
  }

  Future<ControlApiClient> _client() async {
    final settings = _readSettings();
    final baseUrl = settings.controlApiUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AppException('Configure the Control API URL first.');
    }
    final token = await _storage.readControlToken();
    if (token == null || token.trim().isEmpty) {
      throw const AppException('Store the Control API token first.');
    }
    return ControlApiClient(baseUrl: baseUrl, token: token);
  }
}

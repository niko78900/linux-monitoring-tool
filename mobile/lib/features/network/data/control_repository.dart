import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../hosts/domain/models/host_models.dart';
import '../../services/domain/models/service_models.dart';
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
    return DevicesDashboard(devices: devices);
  }

  Future<WakeActionResult> wakeMainPc() async {
    final client = await _client();
    return client.wakeMainPc();
  }

  Future<ManagedHostsDashboard> fetchHostsDashboard() async {
    final client = await _client();
    final hosts = await client.getHosts();
    return ManagedHostsDashboard(hosts: hosts);
  }

  Future<ManagedHost> fetchHost(String hostId) async {
    final client = await _client();
    return client.getHost(hostId);
  }

  Future<List<ManagedService>> fetchServices() async {
    final client = await _client();
    return client.getServices();
  }

  Future<ManagedService> fetchService(String serviceId) async {
    final client = await _client();
    return client.getService(serviceId);
  }

  Future<ServiceActionResult> performServiceAction({
    required String serviceId,
    required String action,
  }) async {
    final client = await _client();
    return client.sendServiceAction(serviceId: serviceId, action: action);
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

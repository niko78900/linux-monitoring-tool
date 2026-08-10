import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/secure_storage_service.dart';
import 'wake_api_client.dart';

final wakeRepositoryProvider = Provider<WakeRepository>((ref) {
  return WakeRepository(
    readSettings: () => ref.read(settingsControllerProvider),
    storage: ref.watch(secureStorageServiceProvider),
  );
});

class WakeRepository {
  WakeRepository({
    required AppSettings Function() readSettings,
    required SecureStorageService storage,
  }) : _readSettings = readSettings,
       _storage = storage;

  final AppSettings Function() _readSettings;
  final SecureStorageService _storage;

  Future<WakeHealth> getHealth() async => (await _client()).getHealth();

  Future<WakeResult> wakeMainPc() async => (await _client()).wakeMainPc();

  Future<WakeApiClient> _client() async {
    final settings = _readSettings();
    final baseUrl = settings.controlApiUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AppException('Configure the Wake API URL first.');
    }
    final token = await _storage.readWakeToken();
    if (token == null || token.trim().isEmpty) {
      throw const AppException('Store the Wake API token first.');
    }
    return WakeApiClient(baseUrl: baseUrl, token: token);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/networking/dio_factory.dart';
import 'monitoring_api_client.dart';

final monitoringRepositoryProvider = Provider<MonitoringRepository>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return MonitoringRepository(
    MonitoringApiClient(
      DioFactory.create(
        baseUrl: settings.monitoringApiUrl,
        showTiming: settings.showRequestTiming,
      ),
    ),
  );
});

class MonitoringRepository {
  MonitoringRepository(this.client);

  final MonitoringApiClient client;
}

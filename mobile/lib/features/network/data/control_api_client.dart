import 'package:dio/dio.dart';

import '../../../core/networking/dio_factory.dart';

class ControlApiClient {
  ControlApiClient({required String baseUrl, required String? token})
    : _dio = DioFactory.create(baseUrl: baseUrl, bearerToken: token);

  final Dio _dio;

  Future<ControlHealth> getHealth() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    final payload = response.data ?? const <String, dynamic>{};
    return ControlHealth(
      status: payload['status'] as String? ?? 'unknown',
      appName: payload['app_name'] as String? ?? 'Control Agent',
      version: payload['version'] as String? ?? 'unknown',
    );
  }

  Future<WakeActionResult> wakeMainPc() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/actions/wake-main-pc',
      data: const <String, dynamic>{},
    );
    final payload = response.data ?? const <String, dynamic>{};
    return WakeActionResult(
      action: payload['action'] as String? ?? 'wake-main-pc',
      status: payload['status'] as String? ?? 'accepted',
      target: payload['target'] as String? ?? 'main_pc',
      rateLimitSeconds: payload['rate_limit_seconds'] as int? ?? 0,
    );
  }
}

class ControlHealth {
  const ControlHealth({
    required this.status,
    required this.appName,
    required this.version,
  });

  final String status;
  final String appName;
  final String version;
}

class WakeActionResult {
  const WakeActionResult({
    required this.action,
    required this.status,
    required this.target,
    required this.rateLimitSeconds,
  });

  final String action;
  final String status;
  final String target;
  final int rateLimitSeconds;
}

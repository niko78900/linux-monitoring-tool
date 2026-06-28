import 'package:dio/dio.dart';

import '../../../core/networking/dio_factory.dart';
import '../../actions/domain/models/benchmark_models.dart';
import '../domain/models/device_models.dart';
import '../../hosts/domain/models/host_models.dart';
import '../../services/domain/models/service_models.dart';

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

  Future<List<KnownDevice>> getDevices() async {
    final response = await _dio.get<Map<String, dynamic>>('/devices');
    final payload = response.data ?? const <String, dynamic>{};
    final devices = payload['devices'] as List<dynamic>? ?? const [];
    return devices
        .map((item) => KnownDevice.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<ManagedHost>> getHosts() async {
    final response = await _dio.get<Map<String, dynamic>>('/hosts');
    final payload = response.data ?? const <String, dynamic>{};
    final hosts = payload['hosts'] as List<dynamic>? ?? const [];
    return hosts
        .map((item) => ManagedHost.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ManagedHost> getHost(String hostId) async {
    final response = await _dio.get<Map<String, dynamic>>('/hosts/$hostId');
    final payload = response.data ?? const <String, dynamic>{};
    return ManagedHost.fromJson(payload);
  }

  Future<List<ManagedService>> getServices() async {
    final response = await _dio.get<Map<String, dynamic>>('/services');
    final payload = response.data ?? const <String, dynamic>{};
    final services = payload['services'] as List<dynamic>? ?? const [];
    return services
        .map((item) => ManagedService.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ManagedService> getService(String serviceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/services/$serviceId',
    );
    final payload = response.data ?? const <String, dynamic>{};
    return ManagedService.fromJson(payload);
  }

  Future<ServiceActionResult> sendServiceAction({
    required String serviceId,
    required String action,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/services/$serviceId/actions/$action',
    );
    final payload = response.data ?? const <String, dynamic>{};
    return ServiceActionResult.fromJson(payload);
  }

  Future<BenchmarkStatus> getBenchmarkStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/benchmarks/status');
    final payload = response.data ?? const <String, dynamic>{};
    return BenchmarkStatus.fromJson(payload);
  }

  Future<BenchmarkStatus> startBenchmark(BenchmarkStartRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/benchmarks/start',
      data: request.toJson(),
    );
    final payload = response.data ?? const <String, dynamic>{};
    return BenchmarkStatus.fromJson(payload);
  }

  Future<BenchmarkStatus> stopBenchmark() async {
    final response = await _dio.post<Map<String, dynamic>>('/benchmarks/stop');
    final payload = response.data ?? const <String, dynamic>{};
    return BenchmarkStatus.fromJson(payload);
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

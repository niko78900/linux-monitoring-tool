import 'package:dio/dio.dart';

import '../domain/models/monitoring_models.dart';

class MonitoringApiClient {
  MonitoringApiClient(this._dio);

  final Dio _dio;

  Future<HealthResponse> getHealth() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    return HealthResponse.fromJson(response.data ?? const {});
  }

  Future<SummaryResponse> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>('/summary');
    return SummaryResponse.fromJson(response.data ?? const {});
  }

  Future<SystemResponse> getSystem() async {
    final response = await _dio.get<Map<String, dynamic>>('/system');
    return SystemResponse.fromJson(response.data ?? const {});
  }

  Future<GpuResponse> getGpu() async {
    final response = await _dio.get<Map<String, dynamic>>('/gpu');
    return GpuResponse.fromJson(response.data ?? const {});
  }

  Future<DockerResponse> getDocker() async {
    final response = await _dio.get<Map<String, dynamic>>('/docker');
    return DockerResponse.fromJson(response.data ?? const {});
  }
}

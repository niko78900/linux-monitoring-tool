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

  Future<Map<String, dynamic>> getHistoryRangesPayload() async {
    final response = await _dio.get<Map<String, dynamic>>('/history/ranges');
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getHistoryOverviewPayload({
    required String range,
    required int maxPoints,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/history/overview',
      queryParameters: {
        'range': range,
        'max_points': maxPoints,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getHistoryStoragePayload({
    required String range,
    required String mountpoint,
    required int maxPoints,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/history/storage',
      queryParameters: {
        'range': range,
        'mountpoint': mountpoint,
        'max_points': maxPoints,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getHistoryDiskPayload({
    required String range,
    required String device,
    required int maxPoints,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/history/disks',
      queryParameters: {
        'range': range,
        'device': device,
        'max_points': maxPoints,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getHistoryRaidPayload({
    required String range,
    required String arrayName,
    required int maxPoints,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/history/raid',
      queryParameters: {
        'range': range,
        'array': arrayName,
        'max_points': maxPoints,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }
}

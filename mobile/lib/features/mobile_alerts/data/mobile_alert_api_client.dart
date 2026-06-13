import 'package:dio/dio.dart';

import '../../../core/networking/dio_factory.dart';
import '../domain/models/mobile_alert_models.dart';

class MobileAlertApiClient {
  MobileAlertApiClient({required String baseUrl, required String? token})
    : _dio = DioFactory.create(baseUrl: baseUrl, bearerToken: token);

  final Dio _dio;

  Future<MobileAlertStatus> getStatus({required String installationId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/mobile-alerts/status',
      queryParameters: {'installation_id': installationId},
    );
    return MobileAlertStatus.fromJson(response.data ?? const {});
  }

  Future<MobileAlertStatus> registerDevice(
    MobileAlertRegistrationRequest request,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/mobile-alerts/register',
      data: request.toJson(),
    );
    return MobileAlertStatus.fromJson(response.data ?? const {});
  }

  Future<MobileAlertStatus> unregisterDevice(String installationId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/mobile-alerts/register/$installationId',
    );
    return MobileAlertStatus.fromJson(response.data ?? const {});
  }

  Future<MobileAlertTestResult> sendTest({
    required String installationId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/mobile-alerts/test',
      data: {'installation_id': installationId},
    );
    return MobileAlertTestResult.fromJson(response.data ?? const {});
  }
}

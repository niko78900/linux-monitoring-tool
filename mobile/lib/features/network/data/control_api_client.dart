import 'package:dio/dio.dart';

import '../../../core/networking/dio_factory.dart';

class ControlApiClient {
  ControlApiClient({required String baseUrl, required String? token})
    : _dio = DioFactory.create(baseUrl: baseUrl, bearerToken: token);

  final Dio _dio;

  Future<void> getHealth() async {
    await _dio.get<Map<String, dynamic>>('/health');
  }
}

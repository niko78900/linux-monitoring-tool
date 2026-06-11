import 'package:dio/dio.dart';

class DioFactory {
  const DioFactory._();

  static Dio create({
    required String baseUrl,
    String? bearerToken,
    bool showTiming = false,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: _normalizeBaseUrl(baseUrl),
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'accept': 'application/json',
          if (bearerToken != null && bearerToken.trim().isNotEmpty)
            'authorization': 'Bearer ${bearerToken.trim()}',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (showTiming) {
            options.extra['startedAt'] = DateTime.now();
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          handler.next(response);
        },
      ),
    );
    return dio;
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }
}

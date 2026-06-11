import 'package:dio/dio.dart';

import 'app_exception.dart';

String mapError(Object error, {bool raw = false}) {
  if (raw) {
    return error.toString();
  }
  if (error is AppException) {
    return error.message;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timed out';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Server unreachable';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        return status == null ? 'Request failed' : 'HTTP $status';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.badCertificate:
        return 'Certificate validation failed';
    }
  }
  return 'Request failed';
}

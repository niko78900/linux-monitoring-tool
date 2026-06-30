import 'package:dio/dio.dart';

import '../../../../core/errors/app_exception.dart';
import 'benchmark_ui_state.dart';

BenchmarkNotice mapBenchmarkError(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final detail = _dioDetail(error);
    final rawDetail = detail ?? error.message ?? error.toString();
    if (statusCode == 401 || statusCode == 403) {
      return BenchmarkNotice(
        'Control-agent token missing or invalid.',
        stateOverride: BenchmarkUiState.authError,
        rawDetail: rawDetail,
      );
    }
    if (statusCode == 404) {
      return BenchmarkNotice(
        'Benchmark endpoints are unavailable. Update/restart the control agent.',
        stateOverride: BenchmarkUiState.unavailable,
        rawDetail: rawDetail,
      );
    }
    if (_isConnectionFailure(error)) {
      return BenchmarkNotice(
        'Control agent unreachable.',
        stateOverride: BenchmarkUiState.unreachable,
        rawDetail: rawDetail,
      );
    }
    if (statusCode == 409) {
      return BenchmarkNotice(
        'Another benchmark is already running. Refresh status.',
        stateOverride: BenchmarkUiState.running,
        rawDetail: rawDetail,
      );
    }
    if (statusCode == 503 || looksBenchmarkUnavailable(rawDetail)) {
      return BenchmarkNotice(
        'Benchmark tool is unavailable on the control agent.',
        stateOverride: BenchmarkUiState.unavailable,
        rawDetail: rawDetail,
      );
    }
    return BenchmarkNotice(
      'Benchmark action failed. Open details for diagnostics.',
      stateOverride: BenchmarkUiState.failed,
      rawDetail: rawDetail,
    );
  }
  if (error is AppException) {
    return BenchmarkNotice(
      'Benchmark action failed. Open details for diagnostics.',
      stateOverride: BenchmarkUiState.failed,
      rawDetail: error.cause?.toString() ?? error.message,
    );
  }
  return BenchmarkNotice(
    'Benchmark action failed. Open details for diagnostics.',
    stateOverride: BenchmarkUiState.failed,
    rawDetail: error.toString(),
  );
}

String? _dioDetail(DioException error) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    return data['detail']?.toString();
  }
  if (data is String && data.trim().isNotEmpty) {
    return data;
  }
  return null;
}

bool _isConnectionFailure(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => true,
    _ => false,
  };
}

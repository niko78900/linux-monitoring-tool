import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/ring_buffer.dart';
import '../../../../core/utils/throughput_calculator.dart';
import '../../data/monitoring_repository.dart';
import '../../domain/models/metric_sample.dart';
import '../../domain/models/monitoring_models.dart';
import '../../domain/models/resource_state.dart';

final monitoringControllerProvider =
    NotifierProvider<MonitoringController, MonitoringState>(
      MonitoringController.new,
    );

class MonitoringState {
  const MonitoringState({
    required this.health,
    required this.summary,
    required this.system,
    required this.gpu,
    required this.docker,
    required this.cpuHistory,
    required this.cpuTemperatureHistory,
    required this.memoryHistory,
    required this.gpuUtilizationHistory,
    required this.gpuTemperatureHistory,
    required this.gpuVramHistory,
    required this.gpuPowerHistory,
    required this.networkReceiveHistory,
    required this.networkSendHistory,
    required this.throughput,
    required this.lastRefresh,
  });

  factory MonitoringState.initial() => MonitoringState(
    health: ResourceState<HealthResponse>.initial(),
    summary: ResourceState<SummaryResponse>.initial(),
    system: ResourceState<SystemResponse>.initial(),
    gpu: ResourceState<GpuResponse>.initial(),
    docker: ResourceState<DockerResponse>.initial(),
    cpuHistory: const [],
    cpuTemperatureHistory: const [],
    memoryHistory: const [],
    gpuUtilizationHistory: const [],
    gpuTemperatureHistory: const [],
    gpuVramHistory: const [],
    gpuPowerHistory: const [],
    networkReceiveHistory: const [],
    networkSendHistory: const [],
    throughput: NetworkThroughput.zero,
    lastRefresh: null,
  );

  final ResourceState<HealthResponse> health;
  final ResourceState<SummaryResponse> summary;
  final ResourceState<SystemResponse> system;
  final ResourceState<GpuResponse> gpu;
  final ResourceState<DockerResponse> docker;
  final List<MetricSample> cpuHistory;
  final List<MetricSample> cpuTemperatureHistory;
  final List<MetricSample> memoryHistory;
  final List<MetricSample> gpuUtilizationHistory;
  final List<MetricSample> gpuTemperatureHistory;
  final List<MetricSample> gpuVramHistory;
  final List<MetricSample> gpuPowerHistory;
  final List<MetricSample> networkReceiveHistory;
  final List<MetricSample> networkSendHistory;
  final NetworkThroughput throughput;
  final DateTime? lastRefresh;

  bool get firstLoadPending =>
      !summary.hasData && !system.hasData && !health.hasData && summary.loading;

  bool get serverReachable =>
      health.data?.status == 'ok' && health.errorMessage == null;

  String? get globalError {
    if (summary.hasData || system.hasData || health.hasData) {
      return null;
    }
    return summary.errorMessage ?? system.errorMessage ?? health.errorMessage;
  }

  MonitoringState copyWith({
    ResourceState<HealthResponse>? health,
    ResourceState<SummaryResponse>? summary,
    ResourceState<SystemResponse>? system,
    ResourceState<GpuResponse>? gpu,
    ResourceState<DockerResponse>? docker,
    List<MetricSample>? cpuHistory,
    List<MetricSample>? cpuTemperatureHistory,
    List<MetricSample>? memoryHistory,
    List<MetricSample>? gpuUtilizationHistory,
    List<MetricSample>? gpuTemperatureHistory,
    List<MetricSample>? gpuVramHistory,
    List<MetricSample>? gpuPowerHistory,
    List<MetricSample>? networkReceiveHistory,
    List<MetricSample>? networkSendHistory,
    NetworkThroughput? throughput,
    DateTime? lastRefresh,
  }) {
    return MonitoringState(
      health: health ?? this.health,
      summary: summary ?? this.summary,
      system: system ?? this.system,
      gpu: gpu ?? this.gpu,
      docker: docker ?? this.docker,
      cpuHistory: cpuHistory ?? this.cpuHistory,
      cpuTemperatureHistory:
          cpuTemperatureHistory ?? this.cpuTemperatureHistory,
      memoryHistory: memoryHistory ?? this.memoryHistory,
      gpuUtilizationHistory:
          gpuUtilizationHistory ?? this.gpuUtilizationHistory,
      gpuTemperatureHistory:
          gpuTemperatureHistory ?? this.gpuTemperatureHistory,
      gpuVramHistory: gpuVramHistory ?? this.gpuVramHistory,
      gpuPowerHistory: gpuPowerHistory ?? this.gpuPowerHistory,
      networkReceiveHistory:
          networkReceiveHistory ?? this.networkReceiveHistory,
      networkSendHistory: networkSendHistory ?? this.networkSendHistory,
      throughput: throughput ?? this.throughput,
      lastRefresh: lastRefresh ?? this.lastRefresh,
    );
  }
}

class MonitoringController extends Notifier<MonitoringState> {
  final _cpuHistory = RingBuffer<MetricSample>(120);
  final _cpuTemperatureHistory = RingBuffer<MetricSample>(120);
  final _memoryHistory = RingBuffer<MetricSample>(120);
  final _gpuUtilizationHistory = RingBuffer<MetricSample>(120);
  final _gpuTemperatureHistory = RingBuffer<MetricSample>(120);
  final _gpuVramHistory = RingBuffer<MetricSample>(120);
  final _gpuPowerHistory = RingBuffer<MetricSample>(120);
  final _networkReceiveHistory = RingBuffer<MetricSample>(120);
  final _networkSendHistory = RingBuffer<MetricSample>(120);
  final List<Timer> _timers = [];
  AppSettings? _settings;
  NetworkCounterSample? _previousNetworkSample;

  @override
  MonitoringState build() {
    ref.listen<AppSettings>(settingsControllerProvider, (_, next) {
      updateSettings(next);
    });
    ref.onDispose(_cancelTimers);
    Future.microtask(
      () => updateSettings(ref.read(settingsControllerProvider)),
    );
    return MonitoringState.initial();
  }

  void updateSettings(AppSettings settings) {
    final shouldRestart =
        _settings == null ||
        _settings!.monitoringApiUrl != settings.monitoringApiUrl ||
        _settings!.summaryPollingMs != settings.summaryPollingMs ||
        _settings!.detailsPollingMs != settings.detailsPollingMs ||
        _settings!.healthPollingMs != settings.healthPollingMs ||
        _settings!.dockerPollingMs != settings.dockerPollingMs ||
        _settings!.onboardingComplete != settings.onboardingComplete;
    _settings = settings;
    if (shouldRestart) {
      _restartTimers(settings);
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      fetchHealth(),
      fetchSummary(),
      fetchSystem(),
      fetchGpu(),
      fetchDocker(),
    ]);
  }

  Future<void> fetchHealth() async {
    state = state.copyWith(health: state.health.startRequest());
    try {
      final data = await _repo.client.getHealth();
      state = state.copyWith(
        health: state.health.success(data),
        lastRefresh: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(health: state.health.failure(_message(error)));
    }
  }

  Future<void> fetchSummary() async {
    state = state.copyWith(summary: state.summary.startRequest());
    try {
      final data = await _repo.client.getSummary();
      final now = DateTime.now();
      _cpuHistory.add(MetricSample(timestamp: now, value: data.cpuPercent));
      _memoryHistory.add(
        MetricSample(timestamp: now, value: data.memoryPercent),
      );
      if (data.gpuUtilizationPercent != null) {
        _gpuUtilizationHistory.add(
          MetricSample(timestamp: now, value: data.gpuUtilizationPercent!),
        );
      }
      if (data.gpuTempC != null) {
        _gpuTemperatureHistory.add(
          MetricSample(timestamp: now, value: data.gpuTempC!),
        );
      }
      state = state.copyWith(
        summary: state.summary.success(data),
        cpuHistory: _cpuHistory.values,
        memoryHistory: _memoryHistory.values,
        gpuUtilizationHistory: _gpuUtilizationHistory.values,
        gpuTemperatureHistory: _gpuTemperatureHistory.values,
        lastRefresh: now,
      );
    } catch (error) {
      state = state.copyWith(summary: state.summary.failure(_message(error)));
    }
  }

  Future<void> fetchSystem() async {
    state = state.copyWith(system: state.system.startRequest());
    try {
      final data = await _repo.client.getSystem();
      final now = DateTime.now();
      if (data.cpu.temperatureC != null) {
        _cpuTemperatureHistory.add(
          MetricSample(timestamp: now, value: data.cpu.temperatureC!),
        );
      }
      final currentSample = NetworkCounterSample(
        timestamp: now,
        bytesRecv: data.network.bytesRecv,
        bytesSent: data.network.bytesSent,
      );
      final throughput = calculateThroughput(
        previous: _previousNetworkSample,
        current: currentSample,
      );
      _previousNetworkSample = currentSample;
      _networkReceiveHistory.add(
        MetricSample(timestamp: now, value: throughput.receiveBytesPerSecond),
      );
      _networkSendHistory.add(
        MetricSample(timestamp: now, value: throughput.sendBytesPerSecond),
      );
      state = state.copyWith(
        system: state.system.success(data),
        cpuTemperatureHistory: _cpuTemperatureHistory.values,
        networkReceiveHistory: _networkReceiveHistory.values,
        networkSendHistory: _networkSendHistory.values,
        throughput: throughput,
        lastRefresh: now,
      );
    } catch (error) {
      state = state.copyWith(system: state.system.failure(_message(error)));
    }
  }

  Future<void> fetchGpu() async {
    state = state.copyWith(gpu: state.gpu.startRequest());
    try {
      final data = await _repo.client.getGpu();
      final now = DateTime.now();
      if (data.available) {
        if (data.utilizationPercent != null) {
          _gpuUtilizationHistory.add(
            MetricSample(timestamp: now, value: data.utilizationPercent!),
          );
        }
        if (data.temperatureC != null) {
          _gpuTemperatureHistory.add(
            MetricSample(timestamp: now, value: data.temperatureC!),
          );
        }
        if (data.memoryUsedPercent != null) {
          _gpuVramHistory.add(
            MetricSample(timestamp: now, value: data.memoryUsedPercent!),
          );
        }
        if (data.powerUsageW != null) {
          _gpuPowerHistory.add(
            MetricSample(timestamp: now, value: data.powerUsageW!),
          );
        }
      }
      state = state.copyWith(
        gpu: state.gpu.success(data),
        gpuUtilizationHistory: _gpuUtilizationHistory.values,
        gpuTemperatureHistory: _gpuTemperatureHistory.values,
        gpuVramHistory: _gpuVramHistory.values,
        gpuPowerHistory: _gpuPowerHistory.values,
        lastRefresh: now,
      );
    } catch (error) {
      state = state.copyWith(gpu: state.gpu.failure(_message(error)));
    }
  }

  Future<void> fetchDocker() async {
    state = state.copyWith(docker: state.docker.startRequest());
    try {
      final data = await _repo.client.getDocker();
      state = state.copyWith(
        docker: state.docker.success(data),
        lastRefresh: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(docker: state.docker.failure(_message(error)));
    }
  }

  MonitoringRepository get _repo => ref.read(monitoringRepositoryProvider);

  String _message(Object error) {
    final AppSettings settings =
        _settings ?? ref.read(settingsControllerProvider);
    return mapError(error, raw: settings.showRawApiErrors);
  }

  void _restartTimers(AppSettings settings) {
    _cancelTimers();
    if (!settings.onboardingComplete ||
        settings.monitoringApiUrl.trim().isEmpty) {
      return;
    }

    refreshAll();
    _timers.add(
      Timer.periodic(
        Duration(milliseconds: settings.summaryPollingMs),
        (_) => fetchSummary(),
      ),
    );
    _timers.add(
      Timer.periodic(
        Duration(milliseconds: settings.detailsPollingMs),
        (_) => fetchSystem(),
      ),
    );
    _timers.add(
      Timer.periodic(
        Duration(milliseconds: settings.detailsPollingMs),
        (_) => fetchGpu(),
      ),
    );
    _timers.add(
      Timer.periodic(
        Duration(milliseconds: settings.healthPollingMs),
        (_) => fetchHealth(),
      ),
    );
    _timers.add(
      Timer.periodic(
        Duration(milliseconds: settings.dockerPollingMs),
        (_) => fetchDocker(),
      ),
    );
  }

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

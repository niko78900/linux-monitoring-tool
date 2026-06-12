import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/data/monitoring_api_client.dart';
import '../../dashboard/data/monitoring_repository.dart';
import '../../dashboard/domain/models/monitoring_models.dart';
import '../domain/models/history_models.dart';
import 'history_cache_service.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(
    client: ref.watch(monitoringRepositoryProvider).client,
    cache: ref.watch(historyCacheServiceProvider),
  );
});

class HistoryRepository {
  HistoryRepository({
    required MonitoringApiClient client,
    required HistoryCacheService cache,
  }) : _client = client,
       _cache = cache;

  final MonitoringApiClient _client;
  final HistoryCacheService _cache;

  Future<HistoryRangesResponseModel> getRanges() async {
    final payload = await _client.getHistoryRangesPayload();
    return HistoryRangesResponseModel.fromJson(payload);
  }

  Future<CachedHistoryData<HistoryOverviewResponseModel>> getOverview({
    required HistoryRangeValue range,
    required int maxPoints,
  }) {
    return _fetchCached(
      key: 'overview-${range.apiKey}-$maxPoints',
      request: () => _client.getHistoryOverviewPayload(
        range: range.apiKey,
        maxPoints: maxPoints,
      ),
      parser: HistoryOverviewResponseModel.fromJson,
    );
  }

  Future<CachedHistoryData<StorageHistoryResponseModel>> getStorage({
    required HistoryRangeValue range,
    required String mountpoint,
    required int maxPoints,
  }) {
    return _fetchCached(
      key:
          'storage-${range.apiKey}-${Uri.encodeComponent(mountpoint)}-$maxPoints',
      request: () => _client.getHistoryStoragePayload(
        range: range.apiKey,
        mountpoint: mountpoint,
        maxPoints: maxPoints,
      ),
      parser: StorageHistoryResponseModel.fromJson,
    );
  }

  Future<CachedHistoryData<DiskHistoryResponseModel>> getDisk({
    required HistoryRangeValue range,
    required String device,
    required int maxPoints,
  }) {
    return _fetchCached(
      key: 'disk-${range.apiKey}-${Uri.encodeComponent(device)}-$maxPoints',
      request: () => _client.getHistoryDiskPayload(
        range: range.apiKey,
        device: device,
        maxPoints: maxPoints,
      ),
      parser: DiskHistoryResponseModel.fromJson,
    );
  }

  Future<CachedHistoryData<RaidHistoryResponseModel>> getRaid({
    required HistoryRangeValue range,
    required String arrayName,
    required int maxPoints,
  }) {
    return _fetchCached(
      key: 'raid-${range.apiKey}-${Uri.encodeComponent(arrayName)}-$maxPoints',
      request: () => _client.getHistoryRaidPayload(
        range: range.apiKey,
        arrayName: arrayName,
        maxPoints: maxPoints,
      ),
      parser: RaidHistoryResponseModel.fromJson,
    );
  }

  Future<HistoryInventory> getInventory() async {
    final system = await _client.getSystem();
    return HistoryInventory(
      mountpoints: _preferredMountpoints(system),
      diskDevices: [for (final disk in system.physicalDisks) disk.device],
      raidArrays: [for (final raid in system.raidArrays) raid.name],
    );
  }

  Future<CachedHistoryData<T>> _fetchCached<T>({
    required String key,
    required Future<Map<String, dynamic>> Function() request,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    try {
      final payload = await request();
      await _cache.write(key, payload);
      return CachedHistoryData(
        data: parser(payload),
        fromCache: false,
        cachedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      final cached = await _cache.read(key);
      if (cached == null) {
        rethrow;
      }
      return CachedHistoryData(
        data: parser(cached.payload),
        fromCache: true,
        cachedAt: cached.cachedAt,
      );
    }
  }

  List<String> _preferredMountpoints(SystemResponse system) {
    final preferred = <String>{'/', '/mnt/warm', '/mnt/storage'};
    final discovered = {for (final disk in system.disks) disk.mountpoint};
    final ordered = <String>[
      for (final mountpoint in preferred)
        if (discovered.contains(mountpoint)) mountpoint,
      for (final mountpoint in discovered)
        if (!preferred.contains(mountpoint)) mountpoint,
    ];
    return ordered.isEmpty ? ['/', '/mnt/warm', '/mnt/storage'] : ordered;
  }
}

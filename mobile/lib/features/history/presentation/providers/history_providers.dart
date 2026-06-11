import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history_repository.dart';
import '../../domain/models/history_models.dart';

final historyRangesProvider = FutureProvider<HistoryRangesResponseModel>((ref) async {
  return ref.watch(historyRepositoryProvider).getRanges();
});

final historyInventoryProvider = FutureProvider<HistoryInventory>((ref) async {
  return ref.watch(historyRepositoryProvider).getInventory();
});

final overviewHistoryProvider =
    FutureProvider.family<CachedHistoryData<HistoryOverviewResponseModel>, HistoryRangeValue>((
      ref,
      range,
    ) async {
      final ranges = await ref.watch(historyRangesProvider.future);
      return ref.watch(historyRepositoryProvider).getOverview(
        range: range,
        maxPoints: ranges.maxPointsCap.clamp(120, 360),
      );
    });

final storageHistoryProvider = FutureProvider.family<
  CachedHistoryData<StorageHistoryResponseModel>,
  ({HistoryRangeValue range, String mountpoint})
>((ref, params) async {
  final ranges = await ref.watch(historyRangesProvider.future);
  return ref.watch(historyRepositoryProvider).getStorage(
    range: params.range,
    mountpoint: params.mountpoint,
    maxPoints: ranges.maxPointsCap.clamp(120, 360),
  );
});

final diskHistoryProvider = FutureProvider.family<
  CachedHistoryData<DiskHistoryResponseModel>,
  ({HistoryRangeValue range, String device})
>((ref, params) async {
  final ranges = await ref.watch(historyRangesProvider.future);
  return ref.watch(historyRepositoryProvider).getDisk(
    range: params.range,
    device: params.device,
    maxPoints: ranges.maxPointsCap.clamp(120, 360),
  );
});

final raidHistoryProvider = FutureProvider.family<
  CachedHistoryData<RaidHistoryResponseModel>,
  ({HistoryRangeValue range, String arrayName})
>((ref, params) async {
  final ranges = await ref.watch(historyRangesProvider.future);
  return ref.watch(historyRepositoryProvider).getRaid(
    range: params.range,
    arrayName: params.arrayName,
    maxPoints: ranges.maxPointsCap.clamp(120, 360),
  );
});

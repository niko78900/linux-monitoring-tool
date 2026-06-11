import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/service_repository.dart';
import '../../domain/models/service_models.dart';

final serviceListProvider = FutureProvider<List<ManagedService>>((ref) async {
  return ref.watch(serviceRepositoryProvider).getServices();
});

final serviceDetailsProvider = FutureProvider.family<ManagedService, String>((
  ref,
  serviceId,
) async {
  return ref.watch(serviceRepositoryProvider).getService(serviceId);
});

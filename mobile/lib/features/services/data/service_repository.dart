import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/service_models.dart';
import '../../network/data/control_repository.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) {
  return ControlAgentServiceRepository(
    controlRepository: ref.watch(controlRepositoryProvider),
  );
});

abstract class ServiceRepository {
  Future<List<ManagedService>> getServices();

  Future<ManagedService> getService(String serviceId);

  Future<ServiceActionResult> sendAction({
    required String serviceId,
    required String action,
  });
}

class ControlAgentServiceRepository implements ServiceRepository {
  const ControlAgentServiceRepository({required ControlRepository controlRepository})
    : _controlRepository = controlRepository;

  final ControlRepository _controlRepository;

  @override
  Future<List<ManagedService>> getServices() {
    return _controlRepository.fetchServices();
  }

  @override
  Future<ManagedService> getService(String serviceId) {
    return _controlRepository.fetchService(serviceId);
  }

  @override
  Future<ServiceActionResult> sendAction({
    required String serviceId,
    required String action,
  }) {
    return _controlRepository.performServiceAction(
      serviceId: serviceId,
      action: action,
    );
  }
}

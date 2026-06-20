import '../domain/models/service_models.dart';

enum ServiceSortMode {
  unhealthyFirst('Unhealthy first'),
  name('Name'),
  category('Category'),
  host('Host');

  const ServiceSortMode(this.label);

  final String label;
}

List<ManagedService> filterAndSortServices({
  required List<ManagedService> services,
  required String searchQuery,
  required String category,
  required String runtime,
  required String health,
  required ServiceSortMode sortMode,
}) {
  final query = searchQuery.trim().toLowerCase();
  final filtered = services.where((service) {
    if (!_matches(category, service.category)) {
      return false;
    }
    if (!_matches(runtime, runtimeBucket(service.runtimeState))) {
      return false;
    }
    if (!_matches(health, healthBucket(service.healthProbeState))) {
      return false;
    }
    if (query.isEmpty) {
      return true;
    }
    return [
      service.displayName,
      service.serviceId,
      service.hostId,
      service.runtimeAdapter,
      service.runtimeTarget,
      service.category,
      service.description,
      service.url,
      service.image,
      ...service.ports,
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }).toList();

  filtered.sort((left, right) {
    return switch (sortMode) {
      ServiceSortMode.unhealthyFirst => _compareRisk(
        left,
        right,
      ).nonZeroOr(_compareText(left.displayName, right.displayName)),
      ServiceSortMode.name => _compareText(left.displayName, right.displayName),
      ServiceSortMode.category => _compareText(
        left.category,
        right.category,
      ).nonZeroOr(_compareText(left.displayName, right.displayName)),
      ServiceSortMode.host => _compareText(
        left.hostId,
        right.hostId,
      ).nonZeroOr(_compareText(left.displayName, right.displayName)),
    };
  });

  return filtered;
}

List<String> serviceCategories(List<ManagedService> services) {
  final categories = {
    for (final service in services)
      if (service.category.trim().isNotEmpty) service.category.trim(),
  }.toList();
  categories.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return categories;
}

String runtimeBucket(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'running' || normalized == 'active') {
    return 'running';
  }
  if (normalized == 'stopped' || normalized == 'inactive') {
    return 'stopped';
  }
  return 'unknown';
}

String healthBucket(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'healthy') {
    return 'healthy';
  }
  if (normalized == 'unconfigured' || normalized == 'unknown') {
    return 'unknown';
  }
  return 'unhealthy';
}

bool _matches(String filter, String value) {
  return filter == 'all' || filter == value.trim().toLowerCase();
}

int _compareRisk(ManagedService left, ManagedService right) {
  return _riskScore(left).compareTo(_riskScore(right));
}

int _riskScore(ManagedService service) {
  final health = healthBucket(service.healthProbeState);
  final runtime = runtimeBucket(service.runtimeState);
  if (health == 'unhealthy') {
    return 0;
  }
  if (runtime == 'stopped') {
    return 1;
  }
  if (health == 'unknown' || runtime == 'unknown') {
    return 2;
  }
  return 3;
}

int _compareText(String left, String right) {
  return left.toLowerCase().compareTo(right.toLowerCase());
}

extension on int {
  int nonZeroOr(int fallback) {
    return this == 0 ? fallback : this;
  }
}

String? routeForWidgetUri(Uri? uri) {
  if (uri == null) {
    return null;
  }

  final target = uri.pathSegments.isNotEmpty
      ? uri.pathSegments.first
      : uri.host;

  return switch (target.toLowerCase()) {
    'overview' => '/overview',
    'storage' => '/storage',
    'history' => '/history',
    'hosts' => '/hosts',
    _ => null,
  };
}

String? widgetActionFromUri(Uri? uri) {
  if (uri == null) {
    return null;
  }
  if (uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first.toLowerCase();
  }
  if (uri.host.isNotEmpty) {
    return uri.host.toLowerCase();
  }
  return null;
}

import '../../../../core/config/app_variant.dart';

String? routeForWidgetUri(Uri? uri, {AppVariant variant = AppVariant.tablet}) {
  if (uri == null) {
    return null;
  }

  final target = uri.pathSegments.isNotEmpty
      ? uri.pathSegments.first
      : uri.host;

  final route = switch (target.toLowerCase()) {
    'overview' => '/overview',
    'storage' => '/storage',
    'gpu' => '/gpu',
    'network' => '/network',
    'history' => '/history',
    'hosts' => '/hosts',
    'terminal' => '/terminal',
    'files' => '/files',
    'actions' => '/actions',
    'wake' => '/wake',
    _ => null,
  };
  return route != null && variant.allowsRoute(route) ? route : null;
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

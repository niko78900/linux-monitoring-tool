String routeForMobileAlertKey(String? alertKey) {
  final key = alertKey?.trim().toLowerCase() ?? '';
  if (key == 'gpu-usage') {
    return '/gpu';
  }
  if (key.startsWith('disk-usage:')) {
    return '/storage';
  }
  return '/overview';
}

class AppConfig {
  const AppConfig._();

  static const appName = 'Homelab Tablet';
  static const defaultMonitoringApiUrl = 'http://10.0.2.2:4040/api';
  static const defaultControlApiUrl = '';
  static const defaultSshPort = 22;
  static const defaultSftpPort = 22;
  static const minPollingMs = 1000;
  static const maxPollingMs = 60 * 60 * 1000;
}

class MobileAlertStatus {
  const MobileAlertStatus({
    required this.pushConfigured,
    required this.registered,
    required this.enabled,
    required this.installationId,
    required this.deviceName,
    required this.platform,
    required this.lastRegisteredAt,
    required this.lastTestSentAt,
  });

  factory MobileAlertStatus.fromJson(Map<String, dynamic> json) {
    return MobileAlertStatus(
      pushConfigured: json['push_configured'] as bool? ?? false,
      registered: json['registered'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      installationId: json['installation_id'] as String?,
      deviceName: json['device_name'] as String?,
      platform: json['platform'] as String?,
      lastRegisteredAt: _date(json['last_registered_at']),
      lastTestSentAt: _date(json['last_test_sent_at']),
    );
  }

  final bool pushConfigured;
  final bool registered;
  final bool enabled;
  final String? installationId;
  final String? deviceName;
  final String? platform;
  final DateTime? lastRegisteredAt;
  final DateTime? lastTestSentAt;
}

class MobileAlertTestResult {
  const MobileAlertTestResult({required this.status, required this.sentCount});

  factory MobileAlertTestResult.fromJson(Map<String, dynamic> json) {
    return MobileAlertTestResult(
      status: json['status'] as String? ?? 'unknown',
      sentCount: json['sent_count'] as int? ?? 0,
    );
  }

  final String status;
  final int sentCount;
}

class MobileAlertRegistrationRequest {
  const MobileAlertRegistrationRequest({
    required this.installationId,
    required this.deviceName,
    required this.fcmToken,
    this.platform = 'android',
    this.enabled = true,
  });

  final String installationId;
  final String deviceName;
  final String fcmToken;
  final String platform;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return {
      'installation_id': installationId,
      'device_name': deviceName,
      'fcm_token': fcmToken,
      'platform': platform,
      'enabled': enabled,
    };
  }
}

DateTime? _date(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

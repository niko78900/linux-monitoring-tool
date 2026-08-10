import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/models/mobile_alert_models.dart';
import 'mobile_alert_api_client.dart';
import 'mobile_alert_routes.dart';

const homelabUrgentAlertChannelId = 'homelab_urgent_alerts_v1';
const homelabUrgentAlertChannelName = 'Homelab urgent alerts';
const homelabUrgentAlertChannelDescription =
    'Sustained CPU, GPU, RAM, and storage alerts from the homelab server.';

const _installationIdKey = 'mobilePushInstallationId';
const _channel = MethodChannel('com.niko.homelab_tablet/notifications');
bool _backgroundHandlerRegistered = false;

@pragma('vm:entry-point')
Future<void> homelabFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
    if (message.notification != null) {
      return;
    }
    await MobileAlertService.instance.ensureLocalNotificationsInitialized();
    await MobileAlertService.instance.showVisibleNotificationFromMessage(
      message,
    );
  } catch (_) {
    // Firebase is not configured yet or the platform is unavailable.
  }
}

enum MobileNotificationPermissionState {
  unsupported('Unsupported'),
  unavailable('Firebase unavailable'),
  granted('Granted'),
  provisional('Provisional'),
  denied('Denied'),
  notDetermined('Not requested');

  const MobileNotificationPermissionState(this.label);

  final String label;
}

Map<String, dynamic> buildMobileAlertRegistrationPayload({
  required String installationId,
  required String deviceName,
  required String fcmToken,
  bool enabled = true,
  bool includeRecovery = true,
}) {
  return MobileAlertRegistrationRequest(
    installationId: installationId,
    deviceName: deviceName,
    fcmToken: fcmToken,
    enabled: enabled,
    includeRecovery: includeRecovery,
  ).toJson();
}

class MobileAlertReadiness {
  const MobileAlertReadiness({
    required this.firebaseReady,
    required this.tokenAvailable,
    required this.permissionGranted,
    required this.serverRegistered,
    required this.channelExists,
    required this.channelImportance,
    required this.channelSoundEnabled,
    required this.channelVibrationEnabled,
  });

  factory MobileAlertReadiness.unavailable({
    bool firebaseReady = false,
    bool tokenAvailable = false,
    bool permissionGranted = false,
    bool serverRegistered = false,
  }) {
    return MobileAlertReadiness(
      firebaseReady: firebaseReady,
      tokenAvailable: tokenAvailable,
      permissionGranted: permissionGranted,
      serverRegistered: serverRegistered,
      channelExists: false,
      channelImportance: 0,
      channelSoundEnabled: false,
      channelVibrationEnabled: false,
    );
  }

  final bool firebaseReady;
  final bool tokenAvailable;
  final bool permissionGranted;
  final bool serverRegistered;
  final bool channelExists;
  final int channelImportance;
  final bool channelSoundEnabled;
  final bool channelVibrationEnabled;

  bool get headsUpReady =>
      permissionGranted && channelExists && channelImportance >= 4;

  bool get fullyReady =>
      firebaseReady && tokenAvailable && serverRegistered && headsUpReady;

  String get readinessMessage {
    if (!firebaseReady) {
      return 'Firebase unavailable';
    }
    if (!serverRegistered) {
      return 'Server registration unavailable';
    }
    if (!permissionGranted) {
      return 'Registered, but Android permission is denied';
    }
    if (!channelExists) {
      return 'Registered, but urgent channel is missing';
    }
    if (channelImportance < 4) {
      return 'Registered, but urgent channel is muted';
    }
    if (!channelSoundEnabled || !channelVibrationEnabled) {
      return 'Ready, but sound or vibration is disabled';
    }
    return 'Ready for heads-up alerts';
  }
}

class MobileAlertService {
  MobileAlertService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? notifications,
  }) : _messaging = messaging,
       _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static final instance = MobileAlertService();

  final FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _notifications;
  final _routes = StreamController<String>.broadcast();
  bool _firebaseReady = false;
  bool _notificationsReady = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  AppSettings? _settings;
  SharedPreferences? _preferences;
  Future<String?> Function()? _readMobileAlertToken;
  String _deviceName = 'Homelab Tablet';

  Stream<String> get notificationRoutes => _routes.stream;

  bool get firebaseReady => _firebaseReady;

  static Future<void> initializeFirebaseAndRegisterBackgroundHandler() async {
    if (!Platform.isAndroid || _backgroundHandlerRegistered) {
      return;
    }
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        homelabFirebaseMessagingBackgroundHandler,
      );
      _backgroundHandlerRegistered = true;
      instance._firebaseReady = true;
    } catch (_) {
      instance._firebaseReady = false;
    }
  }

  Future<void> bootstrap({
    required AppSettings settings,
    required SharedPreferences preferences,
    required Future<String?> Function() readMobileAlertToken,
    required String deviceName,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    _settings = settings;
    _preferences = preferences;
    _readMobileAlertToken = readMobileAlertToken;
    _deviceName = deviceName;
    try {
      await initializeFirebaseAndRegisterBackgroundHandler();
    } catch (_) {
      _firebaseReady = false;
      return;
    }
    if (!_firebaseReady) {
      return;
    }

    await ensureLocalNotificationsInitialized();
    FirebaseMessaging.onMessage.listen(showVisibleNotificationFromMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
    _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen(
      _handleTokenRefresh,
    );
  }

  Future<void> configure({
    required AppSettings settings,
    required SharedPreferences preferences,
    required Future<String?> Function() readMobileAlertToken,
    required String deviceName,
  }) async {
    final previous = _settings;
    _settings = settings;
    _preferences = preferences;
    _readMobileAlertToken = readMobileAlertToken;
    _deviceName = deviceName;
    if (previous != null &&
        previous.mobilePushIncludeRecovery !=
            settings.mobilePushIncludeRecovery &&
        settings.mobilePushAlertsEnabled &&
        _firebaseReady) {
      try {
        await _registerWithCurrentToken(
          settings: settings,
          preferences: preferences,
          mobileAlertToken: await readMobileAlertToken(),
        );
      } catch (_) {
        // Explicit re-registration remains available from Settings.
      }
    }
  }

  FirebaseMessaging get messaging => _messaging ?? FirebaseMessaging.instance;

  Future<void> ensureLocalNotificationsInitialized() async {
    if (_notificationsReady) {
      return;
    }
    const androidInitialization = AndroidInitializationSettings(
      'ic_homelab_notification',
    );
    const initialization = InitializationSettings(
      android: androidInitialization,
    );
    await _notifications.initialize(
      settings: initialization,
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) {
          _routes.add(route);
        }
      },
    );
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        homelabUrgentAlertChannelId,
        homelabUrgentAlertChannelName,
        description: homelabUrgentAlertChannelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    _notificationsReady = true;
  }

  Future<void> showVisibleNotificationFromMessage(RemoteMessage message) async {
    await ensureLocalNotificationsInitialized();
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'Homelab alert';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Resource alert received.';
    final route =
        message.data['route']?.toString() ??
        routeForMobileAlertKey(message.data['alert_key']?.toString());
    await _notifications.show(
      id: Random().nextInt(1 << 31),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          homelabUrgentAlertChannelId,
          homelabUrgentAlertChannelName,
          channelDescription: homelabUrgentAlertChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          icon: 'ic_homelab_notification',
        ),
      ),
      payload: route,
    );
  }

  Future<MobileNotificationPermissionState> permissionState() async {
    if (!Platform.isAndroid) {
      return MobileNotificationPermissionState.unsupported;
    }
    if (!_firebaseReady) {
      return MobileNotificationPermissionState.unavailable;
    }
    final settings = await messaging.getNotificationSettings();
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  Future<MobileNotificationPermissionState> requestPermission() async {
    if (!Platform.isAndroid) {
      return MobileNotificationPermissionState.unsupported;
    }
    if (!_firebaseReady) {
      return MobileNotificationPermissionState.unavailable;
    }
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  Future<String> ensureInstallationId(SharedPreferences preferences) async {
    final existing = preferences.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final value = const Uuid().v4();
    await preferences.setString(_installationIdKey, value);
    return value;
  }

  Future<String?> fcmToken() async {
    if (!_firebaseReady || !Platform.isAndroid) {
      return null;
    }
    return messaging.getToken();
  }

  Future<MobileAlertReadiness> readiness({
    MobileAlertStatus? serverStatus,
    MobileNotificationPermissionState? permission,
  }) async {
    if (!Platform.isAndroid) {
      return MobileAlertReadiness.unavailable();
    }
    final token = await fcmToken();
    final resolvedPermission = permission ?? await permissionState();
    Map<dynamic, dynamic> native = const {};
    try {
      native =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'notificationReadiness',
          ) ??
          const {};
    } catch (_) {
      native = const {};
    }
    return MobileAlertReadiness(
      firebaseReady: _firebaseReady,
      tokenAvailable: token != null && token.isNotEmpty,
      permissionGranted:
          (native['notificationsEnabled'] as bool? ?? true) &&
          (resolvedPermission == MobileNotificationPermissionState.granted ||
              resolvedPermission ==
                  MobileNotificationPermissionState.provisional),
      serverRegistered: serverStatus?.registered == true,
      channelExists: native['channelExists'] as bool? ?? false,
      channelImportance: native['channelImportance'] as int? ?? 0,
      channelSoundEnabled: native['channelSoundEnabled'] as bool? ?? false,
      channelVibrationEnabled:
          native['channelVibrationEnabled'] as bool? ?? false,
    );
  }

  Future<MobileAlertStatus> register({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? mobileAlertToken,
  }) async {
    final token = await fcmToken();
    if (token == null || token.isEmpty) {
      throw const AppException(
        'Firebase is not configured. Add google-services.json and rebuild the APK.',
      );
    }
    return _registerWithCurrentToken(
      settings: settings,
      preferences: preferences,
      mobileAlertToken: mobileAlertToken,
      fcmToken: token,
    );
  }

  Future<MobileAlertStatus> _registerWithCurrentToken({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? mobileAlertToken,
    String? fcmToken,
  }) async {
    final token = fcmToken ?? await this.fcmToken();
    if (token == null || token.isEmpty) {
      throw const AppException(
        'Firebase is not configured. Add google-services.json and rebuild the APK.',
      );
    }
    final installationId = await ensureInstallationId(preferences);
    final client = MobileAlertApiClient(
      baseUrl: settings.monitoringApiUrl,
      token: _requireMobileAlertToken(mobileAlertToken),
    );
    return client.registerDevice(
      MobileAlertRegistrationRequest(
        installationId: installationId,
        deviceName: _deviceName,
        fcmToken: token,
        enabled: true,
        includeRecovery: settings.mobilePushIncludeRecovery,
      ),
    );
  }

  Future<MobileAlertStatus> status({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? mobileAlertToken,
  }) async {
    final installationId = await ensureInstallationId(preferences);
    final client = MobileAlertApiClient(
      baseUrl: settings.monitoringApiUrl,
      token: _requireMobileAlertToken(mobileAlertToken),
    );
    return client.getStatus(installationId: installationId);
  }

  Future<MobileAlertStatus> disable({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? mobileAlertToken,
  }) async {
    final installationId = await ensureInstallationId(preferences);
    final client = MobileAlertApiClient(
      baseUrl: settings.monitoringApiUrl,
      token: _requireMobileAlertToken(mobileAlertToken),
    );
    return client.unregisterDevice(installationId);
  }

  Future<MobileAlertTestResult> sendRoundTripTest({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? mobileAlertToken,
  }) async {
    await register(
      settings: settings,
      preferences: preferences,
      mobileAlertToken: mobileAlertToken,
    );
    final installationId = await ensureInstallationId(preferences);
    final client = MobileAlertApiClient(
      baseUrl: settings.monitoringApiUrl,
      token: _requireMobileAlertToken(mobileAlertToken),
    );
    return client.sendTest(installationId: installationId);
  }

  Future<void> openAndroidNotificationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openUrgentAlertChannelSettings');
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final route =
        message.data['route']?.toString() ??
        routeForMobileAlertKey(message.data['alert_key']?.toString());
    _routes.add(route);
  }

  Future<void> _handleTokenRefresh(String token) async {
    final settings = _settings;
    final preferences = _preferences;
    final readMobileAlertToken = _readMobileAlertToken;
    if (settings == null ||
        preferences == null ||
        readMobileAlertToken == null ||
        !settings.mobilePushAlertsEnabled) {
      return;
    }
    try {
      final installationId = await ensureInstallationId(preferences);
      final mobileAlertToken = await readMobileAlertToken();
      final client = MobileAlertApiClient(
        baseUrl: settings.monitoringApiUrl,
        token: _requireMobileAlertToken(mobileAlertToken),
      );
      await client.registerDevice(
        MobileAlertRegistrationRequest(
          installationId: installationId,
          deviceName: _deviceName,
          fcmToken: token,
          enabled: true,
          includeRecovery: settings.mobilePushIncludeRecovery,
        ),
      );
    } catch (_) {
      // Token refresh will be retried by explicit registration or the next refresh.
    }
  }
}

String _requireMobileAlertToken(String? token) {
  final trimmed = token?.trim() ?? '';
  if (trimmed.isEmpty) {
    throw const AppException(
      'Enter the mobile-alert backend token in Settings.',
    );
  }
  return trimmed;
}

MobileNotificationPermissionState _mapAuthorizationStatus(
  AuthorizationStatus status,
) {
  return switch (status) {
    AuthorizationStatus.authorized => MobileNotificationPermissionState.granted,
    AuthorizationStatus.provisional =>
      MobileNotificationPermissionState.provisional,
    AuthorizationStatus.denied => MobileNotificationPermissionState.denied,
    AuthorizationStatus.notDetermined =>
      MobileNotificationPermissionState.notDetermined,
  };
}

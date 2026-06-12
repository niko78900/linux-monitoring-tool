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
import '../../network/data/control_api_client.dart';
import '../domain/models/mobile_alert_models.dart';
import 'mobile_alert_routes.dart';

const homelabUrgentAlertChannelId = 'homelab_urgent_alerts_v1';
const homelabUrgentAlertChannelName = 'Homelab urgent alerts';
const homelabUrgentAlertChannelDescription =
    'Sustained CPU, GPU, RAM, and storage alerts from the homelab server.';

const _installationIdKey = 'mobilePushInstallationId';
const _channel = MethodChannel('com.niko.homelab_tablet/notifications');

@pragma('vm:entry-point')
Future<void> homelabFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
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
}) {
  return MobileAlertRegistrationRequest(
    installationId: installationId,
    deviceName: deviceName,
    fcmToken: fcmToken,
    enabled: enabled,
  ).toJson();
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
  Future<String?> Function()? _readControlToken;

  Stream<String> get notificationRoutes => _routes.stream;

  bool get firebaseReady => _firebaseReady;

  Future<void> bootstrap({
    required AppSettings settings,
    required SharedPreferences preferences,
    required Future<String?> Function() readControlToken,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    _settings = settings;
    _preferences = preferences;
    _readControlToken = readControlToken;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        homelabFirebaseMessagingBackgroundHandler,
      );
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
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
    required Future<String?> Function() readControlToken,
  }) async {
    _settings = settings;
    _preferences = preferences;
    _readControlToken = readControlToken;
  }

  FirebaseMessaging get messaging => _messaging ?? FirebaseMessaging.instance;

  Future<void> ensureLocalNotificationsInitialized() async {
    if (_notificationsReady) {
      return;
    }
    const androidInitialization = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
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
          visibility: NotificationVisibility.public,
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

  Future<MobileAlertStatus> register({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? controlToken,
  }) async {
    final token = await fcmToken();
    if (token == null || token.isEmpty) {
      throw const AppException(
        'Firebase is not configured. Add google-services.json and rebuild the APK.',
      );
    }
    final installationId = await ensureInstallationId(preferences);
    final client = ControlApiClient(
      baseUrl: settings.controlApiUrl,
      token: controlToken,
    );
    return client.registerMobileAlertDevice(
      MobileAlertRegistrationRequest(
        installationId: installationId,
        deviceName: 'Homelab Tablet',
        fcmToken: token,
        enabled: true,
      ),
    );
  }

  Future<MobileAlertStatus> status({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? controlToken,
  }) async {
    final installationId = await ensureInstallationId(preferences);
    final client = ControlApiClient(
      baseUrl: settings.controlApiUrl,
      token: controlToken,
    );
    return client.getMobileAlertStatus(installationId: installationId);
  }

  Future<MobileAlertStatus> disable({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? controlToken,
  }) async {
    final installationId = await ensureInstallationId(preferences);
    final client = ControlApiClient(
      baseUrl: settings.controlApiUrl,
      token: controlToken,
    );
    return client.unregisterMobileAlertDevice(installationId);
  }

  Future<MobileAlertTestResult> sendRoundTripTest({
    required AppSettings settings,
    required SharedPreferences preferences,
    required String? controlToken,
  }) async {
    await register(
      settings: settings,
      preferences: preferences,
      controlToken: controlToken,
    );
    final installationId = await ensureInstallationId(preferences);
    final client = ControlApiClient(
      baseUrl: settings.controlApiUrl,
      token: controlToken,
    );
    return client.sendMobileAlertTest(installationId: installationId);
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
    final readControlToken = _readControlToken;
    if (settings == null ||
        preferences == null ||
        readControlToken == null ||
        !settings.mobilePushAlertsEnabled) {
      return;
    }
    try {
      final installationId = await ensureInstallationId(preferences);
      final client = ControlApiClient(
        baseUrl: settings.controlApiUrl,
        token: await readControlToken(),
      );
      await client.registerMobileAlertDevice(
        MobileAlertRegistrationRequest(
          installationId: installationId,
          deviceName: 'Homelab Tablet',
          fcmToken: token,
          enabled: true,
        ),
      );
    } catch (_) {
      // Token refresh will be retried by explicit registration or the next refresh.
    }
  }
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

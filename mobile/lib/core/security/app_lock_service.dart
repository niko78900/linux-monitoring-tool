import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../config/app_settings.dart';

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

class AppLockState {
  const AppLockState({
    required this.unlockedUntil,
    required this.lastError,
    required this.authenticating,
  });

  factory AppLockState.locked() => const AppLockState(
    unlockedUntil: null,
    lastError: null,
    authenticating: false,
  );

  final DateTime? unlockedUntil;
  final String? lastError;
  final bool authenticating;

  bool get isUnlocked {
    final expires = unlockedUntil;
    return expires != null && DateTime.now().isBefore(expires);
  }

  AppLockState copyWith({
    DateTime? unlockedUntil,
    String? lastError,
    bool? authenticating,
    bool clearUnlock = false,
    bool clearError = false,
  }) {
    return AppLockState(
      unlockedUntil: clearUnlock ? null : unlockedUntil ?? this.unlockedUntil,
      lastError: clearError ? null : lastError ?? this.lastError,
      authenticating: authenticating ?? this.authenticating,
    );
  }
}

class AppLockController extends Notifier<AppLockState> {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  AppLockState build() => AppLockState.locked();

  Future<bool> ensureUnlocked(AppSettings settings) async {
    if (!settings.requirePrivilegedUnlock) {
      _markUnlocked(settings);
      return true;
    }
    if (state.isUnlocked) {
      return true;
    }
    state = state.copyWith(authenticating: true, clearError: true);
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Unlock privileged Homelab Tablet features',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) {
        state = state.copyWith(
          authenticating: false,
          lastError: 'Authentication was cancelled',
        );
        return false;
      }
      _markUnlocked(settings);
      return true;
    } catch (_) {
      state = state.copyWith(
        authenticating: false,
        lastError: 'Device authentication is unavailable',
      );
      return false;
    }
  }

  void lock() {
    state = AppLockState.locked();
  }

  void _markUnlocked(AppSettings settings) {
    final duration = settings.unlockTimeout.duration;
    final unlockedUntil = duration == Duration.zero
        ? DateTime.now()
        : DateTime.now().add(duration);
    state = AppLockState(
      unlockedUntil: unlockedUntil,
      lastError: null,
      authenticating: false,
    );
  }
}

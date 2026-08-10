import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppVariant { tablet, phone }

extension AppVariantDetails on AppVariant {
  bool get isPhone => this == AppVariant.phone;

  String get displayName => switch (this) {
    AppVariant.tablet => 'Homelab Tablet',
    AppVariant.phone => 'Mobile Homelab',
  };

  String get deviceLabel => switch (this) {
    AppVariant.tablet => 'Homelab Tablet',
    AppVariant.phone => 'Mobile Homelab phone',
  };

  bool allowsRoute(String route) {
    if (!isPhone) {
      return true;
    }
    return const {
      '/overview',
      '/hardware',
      '/storage',
      '/gpu',
      '/network',
      '/history',
      '/wake',
      '/settings',
      '/more',
    }.contains(route);
  }
}

final appVariantProvider = Provider<AppVariant>((ref) => AppVariant.tablet);

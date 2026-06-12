class HomeScreenWidgetDescriptor {
  const HomeScreenWidgetDescriptor({
    required this.providerName,
    required this.displayName,
    required this.purpose,
    required this.recommendedSize,
  });

  final String providerName;
  final String displayName;
  final String purpose;
  final String recommendedSize;
}

const serverEssentialsWidgetProviderName = 'ServerEssentialsWidgetProvider';
const compactStatusWidgetProviderName = 'CompactStatusWidgetProvider';
const performanceWidgetProviderName = 'PerformanceWidgetProvider';
const storageHealthWidgetProviderName = 'StorageHealthWidgetProvider';
const networkActivityWidgetProviderName = 'NetworkActivityWidgetProvider';
const quickAccessWidgetProviderName = 'QuickAccessWidgetProvider';

const homeScreenWidgets = [
  HomeScreenWidgetDescriptor(
    providerName: serverEssentialsWidgetProviderName,
    displayName: 'Server Essentials',
    purpose: 'One-glance server overview.',
    recommendedSize: '4 x 2',
  ),
  HomeScreenWidgetDescriptor(
    providerName: compactStatusWidgetProviderName,
    displayName: 'Compact Status',
    purpose: 'Small CPU, RAM, and storage glance.',
    recommendedSize: '2 x 2',
  ),
  HomeScreenWidgetDescriptor(
    providerName: performanceWidgetProviderName,
    displayName: 'Performance',
    purpose: 'CPU, RAM, and GPU load.',
    recommendedSize: '4 x 2',
  ),
  HomeScreenWidgetDescriptor(
    providerName: storageHealthWidgetProviderName,
    displayName: 'Storage Health',
    purpose: 'Capacity and disk health.',
    recommendedSize: '4 x 2',
  ),
  HomeScreenWidgetDescriptor(
    providerName: networkActivityWidgetProviderName,
    displayName: 'Network Activity',
    purpose: 'Throughput and link totals.',
    recommendedSize: '4 x 2',
  ),
  HomeScreenWidgetDescriptor(
    providerName: quickAccessWidgetProviderName,
    displayName: 'Quick Access',
    purpose: 'Deep links into app screens.',
    recommendedSize: '4 x 1',
  ),
];

const homeScreenWidgetProviderNames = [
  serverEssentialsWidgetProviderName,
  compactStatusWidgetProviderName,
  performanceWidgetProviderName,
  storageHealthWidgetProviderName,
  networkActivityWidgetProviderName,
  quickAccessWidgetProviderName,
];

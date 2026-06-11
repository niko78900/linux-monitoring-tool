class ResourceState<T> {
  const ResourceState({
    required this.data,
    required this.loading,
    required this.refreshing,
    required this.errorMessage,
    required this.lastSuccessfulRefresh,
    required this.lastAttemptedRefresh,
  });

  factory ResourceState.initial() => const ResourceState(
    data: null,
    loading: true,
    refreshing: false,
    errorMessage: null,
    lastSuccessfulRefresh: null,
    lastAttemptedRefresh: null,
  );

  final T? data;
  final bool loading;
  final bool refreshing;
  final String? errorMessage;
  final DateTime? lastSuccessfulRefresh;
  final DateTime? lastAttemptedRefresh;

  bool get hasData => data != null;
  bool get isStale => data != null && errorMessage != null;
  bool get isOffline => data == null && errorMessage != null;

  ResourceState<T> startRequest() {
    return copyWith(
      loading: data == null,
      refreshing: data != null,
      lastAttemptedRefresh: DateTime.now(),
    );
  }

  ResourceState<T> success(T nextData) {
    final now = DateTime.now();
    return ResourceState(
      data: nextData,
      loading: false,
      refreshing: false,
      errorMessage: null,
      lastSuccessfulRefresh: now,
      lastAttemptedRefresh: now,
    );
  }

  ResourceState<T> failure(String message) {
    return copyWith(
      loading: false,
      refreshing: false,
      errorMessage: message,
      lastAttemptedRefresh: DateTime.now(),
    );
  }

  ResourceState<T> copyWith({
    T? data,
    bool? loading,
    bool? refreshing,
    String? errorMessage,
    DateTime? lastSuccessfulRefresh,
    DateTime? lastAttemptedRefresh,
    bool clearError = false,
  }) {
    return ResourceState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastSuccessfulRefresh:
          lastSuccessfulRefresh ?? this.lastSuccessfulRefresh,
      lastAttemptedRefresh: lastAttemptedRefresh ?? this.lastAttemptedRefresh,
    );
  }
}

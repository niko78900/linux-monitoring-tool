function resolveBackendBaseUrl(): string {
  if (typeof window === 'undefined') {
    return 'http://localhost:4040';
  }

  const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
  const hostname = window.location.hostname || 'localhost';
  return `${protocol}//${hostname}:4040`;
}

export const environment = {
  production: false,
  backendBaseUrl: resolveBackendBaseUrl(),
  apiPrefix: '/api',
  polling: {
    summaryMs: 1000,
    detailsMs: 5000,
    healthMs: 15000
  }
};

export const ENV_SHARED = {
  backendBaseUrl: 'http://192.168.100.34:4040',
  apiPrefix: '/api',
  polling: {
    summaryMs: 1000,
    detailsMs: 5000,
    healthMs: 15000
  }
} as const;

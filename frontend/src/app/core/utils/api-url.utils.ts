function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '');
}

function ensureLeadingSlash(value: string): string {
  if (!value) {
    return '';
  }
  return value.startsWith('/') ? value : `/${value}`;
}

function normalizePrefix(apiPrefix: string): string {
  const trimmed = trimTrailingSlash(apiPrefix.trim());
  return ensureLeadingSlash(trimmed);
}

export function buildApiUrl(baseUrl: string, apiPrefix: string, endpoint: string): string {
  const safeBase = trimTrailingSlash(baseUrl.trim());
  const safePrefix = normalizePrefix(apiPrefix);
  const safeEndpoint = ensureLeadingSlash(endpoint);
  return `${safeBase}${safePrefix}${safeEndpoint}`;
}

export function buildDocsUrl(baseUrl: string, apiPrefix: string): string {
  return buildApiUrl(baseUrl, apiPrefix, '/docs');
}

import { buildApiUrl, buildDocsUrl } from './api-url.utils';

describe('api-url utils', () => {
  it('buildApiUrl joins base, prefix, and endpoint safely', () => {
    const result = buildApiUrl('http://localhost:4040/', '/api/', 'summary');
    expect(result).toBe('http://localhost:4040/api/summary');
  });

  it('buildApiUrl normalizes missing leading slashes', () => {
    const result = buildApiUrl('http://localhost:4040', 'api', 'health');
    expect(result).toBe('http://localhost:4040/api/health');
  });

  it('buildApiUrl supports same-origin relative API paths', () => {
    const result = buildApiUrl('', '/api', 'summary');
    expect(result).toBe('/api/summary');
  });

  it('buildDocsUrl points to docs endpoint', () => {
    const result = buildDocsUrl('', '/api');
    expect(result).toBe('/api/docs');
  });
});

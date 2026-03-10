import { buildApiUrl, buildDocsUrl } from './api-url.utils';

describe('api-url utils', () => {
  it('buildApiUrl joins base, prefix, and endpoint safely', () => {
    const result = buildApiUrl('http://192.168.100.34:4040/', '/api/', 'summary');
    expect(result).toBe('http://192.168.100.34:4040/api/summary');
  });

  it('buildApiUrl normalizes missing leading slashes', () => {
    const result = buildApiUrl('http://localhost:4040', 'api', 'health');
    expect(result).toBe('http://localhost:4040/api/health');
  });

  it('buildDocsUrl points to docs endpoint', () => {
    const result = buildDocsUrl('http://192.168.100.34:4040', '/api');
    expect(result).toBe('http://192.168.100.34:4040/api/docs');
  });
});

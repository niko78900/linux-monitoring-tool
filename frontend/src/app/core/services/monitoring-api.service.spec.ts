import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { buildApiUrl, buildDocsUrl } from '../utils/api-url.utils';
import { MonitoringApiService } from './monitoring-api.service';

describe('MonitoringApiService', () => {
  let service: MonitoringApiService;
  let httpController: HttpTestingController;

  const endpoint = (path: string): string =>
    buildApiUrl(environment.backendBaseUrl, environment.apiPrefix, path);

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        MonitoringApiService,
        provideHttpClient(),
        provideHttpClientTesting()
      ]
    });

    service = TestBed.inject(MonitoringApiService);
    httpController = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    httpController.verify();
  });

  it('calls GET /health', () => {
    service.getHealth().subscribe((payload) => {
      expect(payload.status).toBe('ok');
      expect(payload.app_name).toBe('Linux Server monitoring tool');
    });

    const request = httpController.expectOne(endpoint('/health'));
    expect(request.request.method).toBe('GET');
    request.flush({
      status: 'ok',
      app_name: 'Linux Server monitoring tool',
      version: '0.2.0',
      timestamp: '2026-03-10T16:00:00Z'
    });
  });

  it('calls GET /summary', () => {
    service.getSummary().subscribe((payload) => {
      expect(payload.hostname).toBe('homelab-server');
      expect(payload.running_containers).toBe(6);
    });

    const request = httpController.expectOne(endpoint('/summary'));
    expect(request.request.method).toBe('GET');
    request.flush({
      hostname: 'homelab-server',
      uptime_human: '2 days',
      cpu_percent: 20,
      memory_percent: 45,
      disk_percent: 52,
      gpu_available: true,
      gpu_utilization_percent: 30,
      gpu_temp_c: 56,
      docker_available: true,
      running_containers: 6
    });
  });

  it('calls GET /docker', () => {
    service.getDocker().subscribe((payload) => {
      expect(payload.docker_available).toBeTrue();
      expect(payload.container_count).toBe(1);
      expect(payload.containers[0].name).toBe('grafana');
    });

    const request = httpController.expectOne(endpoint('/docker'));
    expect(request.request.method).toBe('GET');
    request.flush({
      docker_available: true,
      reason: null,
      container_count: 1,
      containers: [
        {
          id: 'abc123',
          name: 'grafana',
          image: 'grafana/grafana:latest',
          state: 'running',
          status: 'running',
          ports: { '3000/tcp': ['0.0.0.0:3000'] },
          created: '2026-03-10T14:00:00Z',
          running_for: '2 hours'
        }
      ]
    });
  });

  it('builds docs URL from configured base and prefix', () => {
    expect(service.getDocsUrl()).toBe(buildDocsUrl(environment.backendBaseUrl, environment.apiPrefix));
  });
});

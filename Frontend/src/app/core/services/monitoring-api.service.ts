import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import {
  DockerResponse,
  GpuResponse,
  HealthResponse,
  SummaryResponse,
  SystemResponse
} from '../models/api.models';
import { buildApiUrl, buildDocsUrl } from '../utils/api-url.utils';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class MonitoringApiService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = environment.backendBaseUrl;
  private readonly apiPrefix = environment.apiPrefix;

  getHealth(): Observable<HealthResponse> {
    return this.http.get<HealthResponse>(this.endpoint('/health'));
  }

  getSystem(): Observable<SystemResponse> {
    return this.http.get<SystemResponse>(this.endpoint('/system'));
  }

  getGpu(): Observable<GpuResponse> {
    return this.http.get<GpuResponse>(this.endpoint('/gpu'));
  }

  getDocker(): Observable<DockerResponse> {
    return this.http.get<DockerResponse>(this.endpoint('/docker'));
  }

  getSummary(): Observable<SummaryResponse> {
    return this.http.get<SummaryResponse>(this.endpoint('/summary'));
  }

  getDocsUrl(): string {
    return buildDocsUrl(this.baseUrl, this.apiPrefix);
  }

  private endpoint(path: string): string {
    return buildApiUrl(this.baseUrl, this.apiPrefix, path);
  }
}

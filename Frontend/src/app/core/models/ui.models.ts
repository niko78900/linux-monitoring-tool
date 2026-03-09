import {
  DockerResponse,
  GpuResponse,
  HealthResponse,
  SummaryResponse,
  SystemResponse
} from './api.models';

export interface ResourceState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  lastUpdated: string | null;
}

export interface DashboardViewModel {
  summary: ResourceState<SummaryResponse>;
  system: ResourceState<SystemResponse>;
  gpu: ResourceState<GpuResponse>;
  docker: ResourceState<DockerResponse>;
  health: ResourceState<HealthResponse>;
  lastUpdated: string | null;
  firstLoadPending: boolean;
  backendReachable: boolean;
  globalError: string | null;
}

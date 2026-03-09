import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { combineLatest, Observable, of, timer } from 'rxjs';
import { catchError, map, scan, shareReplay, startWith, switchMap } from 'rxjs/operators';

import {
  DockerResponse,
  GpuResponse,
  HealthResponse,
  SummaryResponse,
  SystemResponse
} from '../models/api.models';
import { DashboardViewModel, ResourceState } from '../models/ui.models';
import { MonitoringApiService } from './monitoring-api.service';
import { environment } from '../../../environments/environment';

type PollEvent<T> =
  | { kind: 'success'; data: T; timestamp: string }
  | { kind: 'error'; message: string; timestamp: string };

@Injectable({
  providedIn: 'root'
})
export class DashboardFacadeService {
  private readonly api = inject(MonitoringApiService);

  readonly summaryState$ = this.createPollingState(
    () => this.api.getSummary(),
    environment.polling.summaryMs
  );
  readonly systemState$ = this.createPollingState(
    () => this.api.getSystem(),
    environment.polling.detailsMs
  );
  readonly gpuState$ = this.createPollingState(() => this.api.getGpu(), environment.polling.detailsMs);
  readonly dockerState$ = this.createPollingState(
    () => this.api.getDocker(),
    environment.polling.detailsMs
  );
  readonly healthState$ = this.createPollingState(
    () => this.api.getHealth(),
    environment.polling.healthMs
  );

  readonly viewModel$: Observable<DashboardViewModel> = combineLatest({
    summary: this.summaryState$,
    system: this.systemState$,
    gpu: this.gpuState$,
    docker: this.dockerState$,
    health: this.healthState$
  }).pipe(
    map(({ summary, system, gpu, docker, health }) => {
      const states = [summary, system, gpu, docker, health];
      const anyData = states.some((state) => state.data !== null);
      const anyLoading = states.some((state) => state.loading);
      const allErrored = states.every((state) => !!state.error);

      const timestamps = states
        .map((state) => state.lastUpdated)
        .filter((item): item is string => !!item)
        .sort();

      return {
        summary,
        system,
        gpu,
        docker,
        health,
        lastUpdated: timestamps.length > 0 ? timestamps[timestamps.length - 1] : null,
        firstLoadPending: !anyData && anyLoading,
        backendReachable: !!health.data && !health.error,
        globalError: !anyData && allErrored ? 'Backend API is currently unreachable.' : null
      };
    }),
    shareReplay({ bufferSize: 1, refCount: true })
  );

  private createPollingState<T>(request: () => Observable<T>, intervalMs: number): Observable<ResourceState<T>> {
    const initialState: ResourceState<T> = {
      data: null,
      loading: true,
      error: null,
      lastUpdated: null
    };

    return timer(0, intervalMs).pipe(
      switchMap(() =>
        request().pipe(
          map((data): PollEvent<T> => ({
            kind: 'success',
            data,
            timestamp: new Date().toISOString()
          })),
          catchError((error: unknown) =>
            of<PollEvent<T>>({
              kind: 'error',
              message: this.describeError(error),
              timestamp: new Date().toISOString()
            })
          )
        )
      ),
      scan((state: ResourceState<T>, event: PollEvent<T>): ResourceState<T> => {
        if (event.kind === 'success') {
          return {
            data: event.data,
            loading: false,
            error: null,
            lastUpdated: event.timestamp
          };
        }

        return {
          ...state,
          loading: false,
          error: event.message,
          lastUpdated: event.timestamp
        };
      }, initialState),
      startWith(initialState),
      shareReplay({ bufferSize: 1, refCount: true })
    );
  }

  private describeError(error: unknown): string {
    if (error instanceof HttpErrorResponse) {
      if (error.status === 0) {
        return 'Connection failed';
      }
      return `${error.status} ${error.statusText || 'Request failed'}`.trim();
    }
    return 'Request failed';
  }
}

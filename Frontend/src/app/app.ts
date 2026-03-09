import { HttpClient } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';

interface HealthResponse {
  status: string;
  service: string;
  timestamp: string;
  python: string;
}

type ApiStatus = 'idle' | 'loading' | 'success' | 'error';

@Component({
  selector: 'app-root',
  imports: [],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App {
  private readonly http = inject(HttpClient);

  protected readonly title = 'Linux Monitoring';
  protected readonly apiStatus = signal<ApiStatus>('idle');
  protected readonly health = signal<HealthResponse | null>(null);
  protected readonly errorMessage = signal<string | null>(null);

  constructor() {
    this.checkBackend();
  }

  protected checkBackend(): void {
    this.apiStatus.set('loading');
    this.errorMessage.set(null);

    this.http.get<HealthResponse>('/api/health').subscribe({
      next: (response) => {
        this.health.set(response);
        this.apiStatus.set('success');
      },
      error: (error) => {
        this.health.set(null);
        this.apiStatus.set('error');
        this.errorMessage.set(error?.message ?? 'Backend is unavailable.');
      }
    });
  }
}

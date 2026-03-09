import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { App } from './app';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideHttpClient(), provideHttpClientTesting()]
    }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(App);
    const httpTesting = TestBed.inject(HttpTestingController);
    httpTesting.expectOne('/api/health').flush({
      status: 'ok',
      service: 'linux-monitoring-api',
      timestamp: '2026-03-09T20:00:00+00:00',
      python: '3.12.10'
    });
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
    httpTesting.verify();
  });
});

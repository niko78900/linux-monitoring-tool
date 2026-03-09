import { DockerPorts, LoadAverage } from '../models/api.models';

export type StatusTone = 'good' | 'warn' | 'bad' | 'neutral';

const BYTE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'] as const;

export function formatBytes(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return 'N/A';
  }

  const abs = Math.abs(value);
  if (abs < 1024) {
    return `${value.toFixed(0)} B`;
  }

  let unitIndex = 0;
  let normalized = abs;
  while (normalized >= 1024 && unitIndex < BYTE_UNITS.length - 1) {
    normalized /= 1024;
    unitIndex += 1;
  }

  const display = normalized >= 10 ? normalized.toFixed(1) : normalized.toFixed(2);
  const sign = value < 0 ? '-' : '';
  return `${sign}${display} ${BYTE_UNITS[unitIndex]}`;
}

export function formatMegabytes(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return 'N/A';
  }
  return formatBytes(value * 1024 * 1024);
}

export function formatOptional(value: unknown): string {
  if (value === null || value === undefined || value === '') {
    return 'N/A';
  }
  return String(value);
}

export function normalizeLoadAverage(loadAverage: LoadAverage | undefined): [number, number, number] | null {
  if (!loadAverage) {
    return null;
  }

  if (Array.isArray(loadAverage) && loadAverage.length === 3) {
    return [loadAverage[0], loadAverage[1], loadAverage[2]];
  }

  if ('one_min' in loadAverage) {
    return [loadAverage.one_min, loadAverage.five_min, loadAverage.fifteen_min];
  }

  return null;
}

export function formatDockerPorts(ports: DockerPorts): string {
  if (!ports) {
    return 'N/A';
  }

  if (typeof ports === 'string') {
    return ports;
  }

  const values = Object.entries(ports).map(([containerPort, hostPorts]) => {
    if (!hostPorts || hostPorts.length === 0) {
      return `${containerPort} -> unbound`;
    }
    return `${containerPort} -> ${hostPorts.join(', ')}`;
  });

  if (values.length === 0) {
    return 'N/A';
  }

  return values.join(' | ');
}

export function clampPercent(value: number | null | undefined): number {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return 0;
  }
  return Math.max(0, Math.min(100, value));
}

export function usageTone(value: number | null | undefined): StatusTone {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return 'neutral';
  }
  if (value >= 90) {
    return 'bad';
  }
  if (value >= 70) {
    return 'warn';
  }
  return 'good';
}

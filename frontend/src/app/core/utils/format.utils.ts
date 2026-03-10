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

  const mappedRangeCandidates: DockerPortRangeCandidate[] = [];
  const mappedDirectLabels: string[] = [];
  const unboundLabels: string[] = [];
  const unboundNumericSinglesByProtocol = new Map<string, number[]>();

  for (const [containerPort, hostPorts] of Object.entries(ports)) {
    if (!hostPorts || hostPorts.length === 0) {
      registerUnboundPort(containerPort, unboundNumericSinglesByProtocol, unboundLabels);
      continue;
    }

    const parsedContainerPort = parseContainerPort(containerPort);
    for (const hostBinding of hostPorts) {
      const parsedHostBinding = parseHostBinding(hostBinding);
      if (
        parsedContainerPort &&
        parsedContainerPort.start === parsedContainerPort.end &&
        parsedHostBinding.port !== null
      ) {
        mappedRangeCandidates.push({
          hostIp: parsedHostBinding.ip,
          hostPort: parsedHostBinding.port,
          containerPort: parsedContainerPort.start,
          protocol: parsedContainerPort.protocol
        });
        continue;
      }

      mappedDirectLabels.push(formatDirectPortMapping(containerPort, hostBinding));
    }
  }

  const mappedRangeLabels = compressMappedPortRanges(mappedRangeCandidates);
  const compressedUnboundLabels = compressUnboundSingles(unboundNumericSinglesByProtocol);

  const labels = dedupeLabels([
    ...mappedRangeLabels,
    ...mappedDirectLabels,
    ...compressedUnboundLabels,
    ...unboundLabels
  ]);

  if (labels.length === 0) {
    return 'N/A';
  }

  const maxSegments = 8;
  if (labels.length > maxSegments) {
    const hiddenCount = labels.length - maxSegments;
    return `${labels.slice(0, maxSegments).join(' | ')} | +${hiddenCount} more`;
  }

  return labels.join(' | ');
}

interface ParsedContainerPort {
  protocol: string;
  start: number;
  end: number;
}

interface ParsedHostBinding {
  ip: string | null;
  port: number | null;
}

interface DockerPortRangeCandidate {
  hostIp: string | null;
  hostPort: number;
  containerPort: number;
  protocol: string;
}

function parseContainerPort(raw: string): ParsedContainerPort | null {
  const clean = raw.trim();
  const match = /^(\d+)(?:-(\d+))?\/([a-z0-9]+)$/i.exec(clean);
  if (!match) {
    return null;
  }

  const start = Number(match[1]);
  const end = match[2] ? Number(match[2]) : start;
  if (Number.isNaN(start) || Number.isNaN(end)) {
    return null;
  }

  return {
    protocol: match[3].toLowerCase(),
    start,
    end
  };
}

function parseHostBinding(raw: string): ParsedHostBinding {
  const clean = String(raw || '').trim();
  if (clean === '') {
    return { ip: null, port: null };
  }

  if (/^\d+$/.test(clean)) {
    return { ip: null, port: Number(clean) };
  }

  const lastColonIndex = clean.lastIndexOf(':');
  if (lastColonIndex > -1 && lastColonIndex < clean.length - 1) {
    const maybePort = clean.slice(lastColonIndex + 1);
    if (/^\d+$/.test(maybePort)) {
      const rawIp = clean.slice(0, lastColonIndex).replace(/^\[|\]$/g, '');
      return { ip: rawIp || null, port: Number(maybePort) };
    }
  }

  return { ip: null, port: null };
}

function formatDirectPortMapping(containerPort: string, hostBinding: string): string {
  const clean = String(hostBinding || '').trim();
  if (!clean) {
    return `${containerPort} -> mapped`;
  }
  return `${clean} -> ${containerPort}`;
}

function registerUnboundPort(
  containerPort: string,
  unboundSinglesByProtocol: Map<string, number[]>,
  unboundLabels: string[]
): void {
  const parsed = parseContainerPort(containerPort);
  if (!parsed) {
    unboundLabels.push(`${containerPort} unbound`);
    return;
  }

  if (parsed.start !== parsed.end) {
    unboundLabels.push(`${parsed.start}-${parsed.end}/${parsed.protocol} unbound`);
    return;
  }

  const existing = unboundSinglesByProtocol.get(parsed.protocol) ?? [];
  existing.push(parsed.start);
  unboundSinglesByProtocol.set(parsed.protocol, existing);
}

function compressUnboundSingles(unboundSinglesByProtocol: Map<string, number[]>): string[] {
  const labels: string[] = [];

  for (const [protocol, ports] of [...unboundSinglesByProtocol.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    if (ports.length === 0) {
      continue;
    }

    const sortedPorts = [...ports].sort((a, b) => a - b);
    let rangeStart = sortedPorts[0];
    let previous = sortedPorts[0];

    for (let index = 1; index < sortedPorts.length; index += 1) {
      const current = sortedPorts[index];
      if (current === previous || current === previous + 1) {
        previous = current;
        continue;
      }

      labels.push(formatUnboundLabel(rangeStart, previous, protocol));
      rangeStart = current;
      previous = current;
    }

    labels.push(formatUnboundLabel(rangeStart, previous, protocol));
  }

  return labels;
}

function formatUnboundLabel(start: number, end: number, protocol: string): string {
  if (start === end) {
    return `${start}/${protocol} unbound`;
  }
  return `${start}-${end}/${protocol} unbound`;
}

function compressMappedPortRanges(candidates: DockerPortRangeCandidate[]): string[] {
  if (candidates.length === 0) {
    return [];
  }

  const grouped = new Map<string, DockerPortRangeCandidate[]>();
  for (const candidate of candidates) {
    const offset = candidate.containerPort - candidate.hostPort;
    const key = `${candidate.protocol}|${candidate.hostIp ?? ''}|${offset}`;
    const list = grouped.get(key) ?? [];
    list.push(candidate);
    grouped.set(key, list);
  }

  const labels: string[] = [];
  for (const group of [...grouped.values()]) {
    group.sort((a, b) => {
      if (a.hostPort !== b.hostPort) {
        return a.hostPort - b.hostPort;
      }
      return a.containerPort - b.containerPort;
    });

    let start = group[0];
    let end = group[0];

    for (let index = 1; index < group.length; index += 1) {
      const current = group[index];
      const isContiguous =
        current.hostPort === end.hostPort + 1 && current.containerPort === end.containerPort + 1;
      if (isContiguous) {
        end = current;
        continue;
      }

      labels.push(formatMappedRangeLabel(start, end));
      start = current;
      end = current;
    }

    labels.push(formatMappedRangeLabel(start, end));
  }

  return labels;
}

function formatMappedRangeLabel(start: DockerPortRangeCandidate, end: DockerPortRangeCandidate): string {
  const hostSegment = formatHostRange(start.hostIp, start.hostPort, end.hostPort);
  const containerSegment = start.containerPort === end.containerPort
    ? `${start.containerPort}`
    : `${start.containerPort}-${end.containerPort}`;
  return `${hostSegment} -> ${containerSegment}/${start.protocol}`;
}

function formatHostRange(ip: string | null, start: number, end: number): string {
  if (ip) {
    if (start === end) {
      return `${ip}:${start}`;
    }
    return `${ip}:${start}-${end}`;
  }
  if (start === end) {
    return `${start}`;
  }
  return `${start}-${end}`;
}

function dedupeLabels(labels: string[]): string[] {
  const unique: string[] = [];
  const seen = new Set<string>();
  for (const label of labels) {
    if (seen.has(label)) {
      continue;
    }
    seen.add(label);
    unique.push(label);
  }
  return unique;
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

export interface HealthResponse {
  status: string;
  app_name: string;
  version: string;
  timestamp: string;
}

export interface PlatformInfo {
  system: string;
  release: string;
  version: string;
  machine: string;
  platform: string;
}

export interface LoadAverageInfo {
  one_min: number;
  five_min: number;
  fifteen_min: number;
}

export type LoadAverage = LoadAverageInfo | [number, number, number] | null;

export interface CpuInfo {
  usage_percent: number;
  physical_cores: number;
  logical_cores: number;
  load_average: LoadAverage;
}

export interface MemoryInfo {
  total: number;
  available: number;
  used: number;
  percent: number;
}

export interface SwapInfo {
  total: number;
  used: number;
  percent: number;
}

export interface DiskInfo {
  total: number;
  used: number;
  free: number;
  percent: number;
  mountpoint: string;
}

export type DiskHealthStatus = 'healthy' | 'warning' | 'critical' | 'unknown';

export interface DiskHealthInfo {
  status: DiskHealthStatus;
  reason: string;
}

export interface DiskDeviceInfo {
  device: string;
  mountpoint: string;
  fstype: string;
  total: number;
  used: number;
  free: number;
  percent: number;
  read_only: boolean;
  available: boolean;
  health: DiskHealthInfo;
}

export interface NetworkInfo {
  bytes_sent: number;
  bytes_recv: number;
  packets_sent: number;
  packets_recv: number;
}

export interface SystemResponse {
  hostname: string;
  os?: PlatformInfo;
  platform?: string;
  kernel_version: string;
  boot_time: string;
  uptime_seconds: number;
  uptime_human: string;
  cpu: CpuInfo;
  memory: MemoryInfo;
  swap: SwapInfo;
  disk: DiskInfo;
  disks?: DiskDeviceInfo[];
  network: NetworkInfo;
}

export interface GpuResponse {
  available: boolean;
  reason?: string | null;
  name?: string | null;
  temperature_c?: number | null;
  utilization_percent?: number | null;
  memory_total_mb?: number | null;
  memory_used_mb?: number | null;
  memory_free_mb?: number | null;
  power_usage_w?: number | null;
  fan_speed_percent?: number | null;
  driver_version?: string | null;
}

export type DockerPorts = Record<string, string[]> | string | null;

export interface DockerContainerInfo {
  id: string;
  name: string;
  image: string;
  state: string;
  status: string;
  ports: DockerPorts;
  created?: string | null;
  running_for?: string | null;
}

export interface DockerResponse {
  docker_available: boolean;
  reason?: string | null;
  container_count: number;
  containers: DockerContainerInfo[];
}

export interface SummaryResponse {
  hostname: string;
  uptime_human: string;
  cpu_percent: number;
  memory_percent: number;
  disk_percent: number;
  gpu_available: boolean;
  gpu_utilization_percent?: number | null;
  gpu_temp_c?: number | null;
  docker_available: boolean;
  running_containers: number;
}

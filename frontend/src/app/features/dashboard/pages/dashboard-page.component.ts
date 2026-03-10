import { AsyncPipe, DecimalPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import {
  CpuSpecs,
  DockerContainerInfo,
  DiskDeviceInfo,
  DiskHealthStatus,
  DiskInfo,
  PhysicalDiskInfo,
  RaidArrayInfo,
  SystemResponse
} from '../../../core/models/api.models';
import { LocalDatePipe } from '../../../core/pipes/local-date.pipe';
import { MbSizePipe } from '../../../core/pipes/mb-size.pipe';
import { NaPipe } from '../../../core/pipes/na.pipe';
import { DashboardFacadeService } from '../../../core/services/dashboard-facade.service';
import { MonitoringApiService } from '../../../core/services/monitoring-api.service';
import {
  formatDockerPorts,
  normalizeLoadAverage,
  StatusTone,
  usageTone
} from '../../../core/utils/format.utils';
import { BytesPipe } from '../../../core/pipes/bytes.pipe';
import { InfoRowComponent } from '../../../shared/components/info-row/info-row.component';
import { MetricCardComponent } from '../../../shared/components/metric-card/metric-card.component';
import { ProgressBarComponent } from '../../../shared/components/progress-bar/progress-bar.component';
import { SectionPanelComponent } from '../../../shared/components/section-panel/section-panel.component';
import { StatusBadgeComponent } from '../../../shared/components/status-badge/status-badge.component';

@Component({
  selector: 'app-dashboard-page',
  standalone: true,
  imports: [
    AsyncPipe,
    DecimalPipe,
    BytesPipe,
    InfoRowComponent,
    LocalDatePipe,
    MbSizePipe,
    MetricCardComponent,
    NaPipe,
    ProgressBarComponent,
    SectionPanelComponent,
    StatusBadgeComponent
  ],
  templateUrl: './dashboard-page.component.html',
  styleUrl: './dashboard-page.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class DashboardPageComponent {
  private readonly facade = inject(DashboardFacadeService);
  private readonly api = inject(MonitoringApiService);

  protected isPollingMenuOpen = false;
  protected isSpecsExpanded = true;

  readonly vm$ = this.facade.viewModel$;
  readonly docsUrl = this.api.getDocsUrl();
  readonly pollingIntervalMs$ = this.facade.pollingIntervalMs$;
  readonly minPollingIntervalMs = this.facade.minPollingIntervalMs;
  readonly maxPollingIntervalMs = this.facade.maxPollingIntervalMs;
  readonly pollingStepMs = 500;

  protected usageTone = usageTone;

  protected asPercent(value: number | null | undefined): string {
    if (value === null || value === undefined || Number.isNaN(value)) {
      return 'N/A';
    }
    return `${Math.round(value)}%`;
  }

  protected platformLabel(platform: string | undefined, osPlatform: string | undefined): string {
    return osPlatform || platform || 'N/A';
  }

  protected cpuFrequencyLabel(minMhz: number | null | undefined, maxMhz: number | null | undefined): string {
    const minLabel = this.frequencyLabel(minMhz);
    const maxLabel = this.frequencyLabel(maxMhz);

    if (minLabel === null && maxLabel === null) {
      return 'N/A';
    }
    if (minLabel && maxLabel) {
      if (minLabel === maxLabel) {
        return maxLabel;
      }
      return `${minLabel} - ${maxLabel}`;
    }
    return minLabel || maxLabel || 'N/A';
  }

  protected cpuCapabilityPreview(capabilities: string[] | null | undefined, limit = 18): string[] {
    if (!Array.isArray(capabilities) || capabilities.length === 0) {
      return [];
    }
    return capabilities.slice(0, limit);
  }

  protected cpuCapabilityHiddenCount(capabilities: string[] | null | undefined, limit = 18): number {
    if (!Array.isArray(capabilities) || capabilities.length <= limit) {
      return 0;
    }
    return capabilities.length - limit;
  }

  protected cpuThreadDensity(specs: CpuSpecs | null | undefined): string {
    if (!specs || specs.physical_cores <= 0 || specs.logical_cores <= 0) {
      return 'N/A';
    }

    const ratio = specs.logical_cores / specs.physical_cores;
    return `${ratio.toFixed(2).replace(/\.00$/, '')}x threads/core`;
  }

  protected loadAverageLabel(loadAverage: unknown, logicalCores: number | null | undefined): string {
    const normalized = normalizeLoadAverage(loadAverage as never);
    if (!normalized) {
      return 'N/A';
    }

    const rawLabel = normalized.map((item) => item.toFixed(2)).join(' / ');
    if (logicalCores === null || logicalCores === undefined || Number.isNaN(logicalCores) || logicalCores <= 0) {
      return rawLabel;
    }

    const percentLabel = normalized
      .map((item) => `${Math.round((item / logicalCores) * 100)}%`)
      .join(' / ');
    return `${percentLabel} (${rawLabel})`;
  }

  protected portsLabel(ports: unknown): string {
    return formatDockerPorts(ports as never);
  }

  protected usagePairLabel(used: number | null | undefined, total: number | null | undefined): string {
    if (
      used === null ||
      used === undefined ||
      total === null ||
      total === undefined ||
      Number.isNaN(used) ||
      Number.isNaN(total)
    ) {
      return 'N/A';
    }

    const gb = 1000 ** 3;
    return `${(used / gb).toFixed(1)} / ${(total / gb).toFixed(1)} GB`;
  }

  protected networkTopSpeedLabel(speedMbps: number | null | undefined): string {
    if (speedMbps === null || speedMbps === undefined || Number.isNaN(speedMbps) || speedMbps <= 0) {
      return 'N/A';
    }

    if (speedMbps >= 1000) {
      const speedGbps = speedMbps / 1000;
      const decimals = speedGbps >= 10 ? 1 : 2;
      return `${speedGbps.toFixed(decimals).replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1')} Gbps`;
    }

    return `${Math.round(speedMbps).toLocaleString()} Mbps`;
  }

  protected pollingIntervalLabel(intervalMs: number): string {
    if (intervalMs >= 60 * 60 * 1000) {
      return '1 hour';
    }
    if (intervalMs >= 60 * 1000) {
      const minutes = intervalMs / (60 * 1000);
      return `${minutes.toFixed(minutes >= 10 ? 0 : 1).replace(/\.0$/, '')} min`;
    }
    if (intervalMs >= 1000) {
      const seconds = intervalMs / 1000;
      return `${seconds.toFixed(seconds >= 10 ? 0 : 1).replace(/\.0$/, '')} sec`;
    }
    return `${intervalMs} ms`;
  }

  protected onPollingIntervalInput(event: Event): void {
    const target = event.target as HTMLInputElement | null;
    if (!target) {
      return;
    }

    const nextValue = Number(target.value);
    this.facade.setPollingIntervalMs(nextValue);
  }

  protected togglePollingMenu(): void {
    this.isPollingMenuOpen = !this.isPollingMenuOpen;
  }

  protected closePollingMenu(): void {
    this.isPollingMenuOpen = false;
  }

  protected toggleSpecsPanel(): void {
    this.isSpecsExpanded = !this.isSpecsExpanded;
  }

  protected memoryBrandLabel(system: SystemResponse): string {
    const brands = system.specs?.memory?.manufacturers ?? [];
    if (!Array.isArray(brands) || brands.length === 0) {
      return 'N/A';
    }
    return brands.join(', ');
  }

  protected memorySpeedLabel(system: SystemResponse): string {
    const speedMhz = system.specs?.memory?.speed_mhz;
    if (speedMhz === null || speedMhz === undefined || Number.isNaN(speedMhz) || speedMhz <= 0) {
      return 'N/A';
    }
    return `${Math.round(speedMhz).toLocaleString()} MT/s`;
  }

  protected memoryModulesSummary(system: SystemResponse): string {
    const modules = system.specs?.memory?.modules ?? [];
    if (!Array.isArray(modules) || modules.length === 0) {
      return 'No module details';
    }
    return `${modules.length} module${modules.length === 1 ? '' : 's'} detected`;
  }

  protected gpuStaticCapabilityPreview(capabilities: string[] | null | undefined, limit = 8): string[] {
    if (!Array.isArray(capabilities) || capabilities.length === 0) {
      return [];
    }
    return capabilities.slice(0, limit);
  }

  protected gpuStaticCapabilityHiddenCount(capabilities: string[] | null | undefined, limit = 8): number {
    if (!Array.isArray(capabilities) || capabilities.length <= limit) {
      return 0;
    }
    return capabilities.length - limit;
  }

  protected gpuVramUsageLabel(usedMb: number | null | undefined, totalMb: number | null | undefined): string {
    const usedLabel = this.megabytesToGbLabel(usedMb);
    const totalLabel = this.megabytesToGbLabel(totalMb);
    if (usedLabel === null || totalLabel === null) {
      return 'N/A';
    }
    return `${usedLabel} / ${totalLabel}`;
  }

  protected systemDisks(system: SystemResponse): DiskDeviceInfo[] {
    if (Array.isArray(system.disks) && system.disks.length > 0) {
      return system.disks;
    }
    return [this.asLegacyDiskDevice(system.disk)];
  }

  protected disksOnlineLabel(system: SystemResponse): string {
    const disks = this.systemDisks(system);
    const onlineCount = disks.filter((disk) => disk.available).length;
    return `${onlineCount}/${disks.length} Online`;
  }

  protected disksOnlineTone(system: SystemResponse): StatusTone {
    const disks = this.systemDisks(system);
    if (disks.length === 0) {
      return 'neutral';
    }
    const onlineCount = disks.filter((disk) => disk.available).length;
    if (onlineCount === disks.length) {
      return 'good';
    }
    if (onlineCount === 0) {
      return 'bad';
    }
    return 'warn';
  }

  protected diskAvailabilityLabel(disk: DiskDeviceInfo): string {
    return disk.available ? 'Online' : 'Offline';
  }

  protected diskAvailabilityTone(disk: DiskDeviceInfo): StatusTone {
    return disk.available ? 'good' : 'bad';
  }

  protected diskHealthLabel(disk: DiskDeviceInfo): string {
    const status = disk.health?.status ?? 'unknown';
    return status.charAt(0).toUpperCase() + status.slice(1);
  }

  protected diskHealthTone(disk: DiskDeviceInfo): StatusTone {
    if (!disk.available) {
      return 'bad';
    }
    switch (disk.health?.status) {
      case 'healthy':
        return 'good';
      case 'warning':
        return 'warn';
      case 'critical':
        return 'bad';
      default:
        return 'neutral';
    }
  }

  protected diskHealthReason(disk: DiskDeviceInfo): string {
    return disk.health?.reason || 'N/A';
  }

  protected diskRaidLabel(disk: DiskDeviceInfo): string {
    if (!disk.raid_array) {
      return 'No';
    }
    if (disk.raid_level) {
      return `${disk.raid_array} (${disk.raid_level})`;
    }
    return disk.raid_array;
  }

  protected systemRaidArrays(system: SystemResponse): RaidArrayInfo[] {
    if (!Array.isArray(system.raid_arrays)) {
      return [];
    }
    return system.raid_arrays;
  }

  protected raidHealthLabel(raidArray: RaidArrayInfo): string {
    const status = raidArray.health?.status ?? 'unknown';
    return status.charAt(0).toUpperCase() + status.slice(1);
  }

  protected raidHealthTone(raidArray: RaidArrayInfo): StatusTone {
    switch (raidArray.health?.status) {
      case 'healthy':
        return 'good';
      case 'warning':
        return 'warn';
      case 'critical':
        return 'bad';
      default:
        return 'neutral';
    }
  }

  protected raidMembersLabel(raidArray: RaidArrayInfo): string {
    if (!Array.isArray(raidArray.members) || raidArray.members.length === 0) {
      return 'N/A';
    }
    return raidArray.members.join(', ');
  }

  protected systemPhysicalDisks(system: SystemResponse): PhysicalDiskInfo[] {
    if (!Array.isArray(system.physical_disks)) {
      return [];
    }
    return system.physical_disks;
  }

  protected physicalDiskTypeLabel(disk: PhysicalDiskInfo): string {
    if (disk.rotational === true) {
      return 'HDD';
    }
    if (disk.rotational === false) {
      return 'SSD';
    }
    return 'N/A';
  }

  protected physicalDiskMountsLabel(disk: PhysicalDiskInfo): string {
    if (!Array.isArray(disk.mounted_partitions) || disk.mounted_partitions.length === 0) {
      return 'None';
    }
    return disk.mounted_partitions.join(', ');
  }

  protected physicalDiskRaidLabel(disk: PhysicalDiskInfo): string {
    if (!Array.isArray(disk.raid_arrays) || disk.raid_arrays.length === 0) {
      return 'No';
    }
    return disk.raid_arrays.join(', ');
  }

  protected physicalDiskHealthLabel(disk: PhysicalDiskInfo): string {
    const status = disk.health?.status ?? 'unknown';
    return status.charAt(0).toUpperCase() + status.slice(1);
  }

  protected physicalDiskHealthTone(disk: PhysicalDiskInfo): StatusTone {
    switch (disk.health?.status) {
      case 'healthy':
        return 'good';
      case 'warning':
        return 'warn';
      case 'critical':
        return 'bad';
      default:
        return 'neutral';
    }
  }

  protected physicalDiskStateLabel(disk: PhysicalDiskInfo): string {
    return disk.state || 'N/A';
  }

  protected dockerRunningCount(containers: DockerContainerInfo[] | null | undefined): number {
    if (!Array.isArray(containers) || containers.length === 0) {
      return 0;
    }
    return containers.filter((container) => this.isContainerRunning(container.state)).length;
  }

  protected dockerStoppedCount(containers: DockerContainerInfo[] | null | undefined): number {
    if (!Array.isArray(containers) || containers.length === 0) {
      return 0;
    }
    return containers.length - this.dockerRunningCount(containers);
  }

  protected dockerUniqueImagesCount(containers: DockerContainerInfo[] | null | undefined): number {
    if (!Array.isArray(containers) || containers.length === 0) {
      return 0;
    }
    return new Set(containers.map((container) => (container.image || '').trim()).filter(Boolean)).size;
  }

  protected dockerRunningPercent(containers: DockerContainerInfo[] | null | undefined): number {
    if (!Array.isArray(containers) || containers.length === 0) {
      return 0;
    }
    return Math.round((this.dockerRunningCount(containers) / containers.length) * 100);
  }

  protected dockerStateLabel(state: string | null | undefined): string {
    if (!state) {
      return 'Unknown';
    }
    const normalized = state.trim().toLowerCase();
    return normalized.charAt(0).toUpperCase() + normalized.slice(1);
  }

  protected dockerStateTone(state: string | null | undefined): StatusTone {
    const normalized = (state || '').trim().toLowerCase();
    if (!normalized) {
      return 'neutral';
    }
    if (normalized === 'running') {
      return 'good';
    }
    if (normalized === 'paused' || normalized === 'restarting') {
      return 'warn';
    }
    if (normalized === 'exited' || normalized === 'dead' || normalized === 'removing') {
      return 'bad';
    }
    return 'neutral';
  }

  protected shortContainerId(id: string | null | undefined): string {
    if (!id) {
      return 'N/A';
    }
    return id.length > 12 ? id.slice(0, 12) : id;
  }

  protected trackByPhysicalDisk(index: number, item: PhysicalDiskInfo): string {
    return `${item.device}-${index}`;
  }

  protected trackByDiskKey(index: number, item: DiskDeviceInfo): string {
    return `${item.mountpoint}-${item.device}-${index}`;
  }

  protected trackByRaidDevice(index: number, item: RaidArrayInfo): string {
    return `${item.device}-${index}`;
  }

  protected trackByContainerId(index: number, item: { id: string }): string {
    return `${item.id}-${index}`;
  }

  private asLegacyDiskDevice(disk: DiskInfo): DiskDeviceInfo {
    const available = disk.total > 0;
    const healthStatus = this.legacyDiskHealthStatus(disk.percent, available);
    return {
      device: 'primary',
      mountpoint: disk.mountpoint,
      fstype: 'unknown',
      total: disk.total,
      used: disk.used,
      free: disk.free,
      percent: disk.percent,
      read_only: false,
      available,
      health: {
        status: healthStatus,
        reason: available ? 'Primary disk usage from backend.' : 'Disk metrics unavailable.'
      }
    };
  }

  private legacyDiskHealthStatus(percent: number, available: boolean): DiskHealthStatus {
    if (!available || Number.isNaN(percent)) {
      return 'unknown';
    }
    if (percent >= 95) {
      return 'critical';
    }
    if (percent >= 85) {
      return 'warning';
    }
    return 'healthy';
  }

  private isContainerRunning(state: string | null | undefined): boolean {
    return (state || '').trim().toLowerCase() === 'running';
  }

  private frequencyLabel(valueMhz: number | null | undefined): string | null {
    if (valueMhz === null || valueMhz === undefined || Number.isNaN(valueMhz) || valueMhz <= 0) {
      return null;
    }

    if (valueMhz >= 1000) {
      const ghz = valueMhz / 1000;
      const decimals = ghz >= 10 ? 1 : 2;
      return `${ghz.toFixed(decimals).replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1')} GHz`;
    }
    return `${Math.round(valueMhz).toLocaleString()} MHz`;
  }

  private megabytesToGbLabel(valueMb: number | null | undefined): string | null {
    if (valueMb === null || valueMb === undefined || Number.isNaN(valueMb) || valueMb < 0) {
      return null;
    }

    const valueGb = valueMb / 1000;
    const decimals = valueGb >= 10 ? 1 : 2;
    return `${valueGb.toFixed(decimals).replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1')} GB`;
  }
}

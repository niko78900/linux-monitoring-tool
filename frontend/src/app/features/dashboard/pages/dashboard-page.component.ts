import { AsyncPipe, DecimalPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import {
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
}

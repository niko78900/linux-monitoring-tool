import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import {
  DiskDeviceInfo,
  DiskHealthStatus,
  DiskInfo,
  SystemResponse
} from '../../../core/models/api.models';
import { LocalDatePipe } from '../../../core/pipes/local-date.pipe';
import { MbSizePipe } from '../../../core/pipes/mb-size.pipe';
import { NaPipe } from '../../../core/pipes/na.pipe';
import { UptimePipe } from '../../../core/pipes/uptime.pipe';
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
    BytesPipe,
    InfoRowComponent,
    LocalDatePipe,
    MbSizePipe,
    MetricCardComponent,
    NaPipe,
    ProgressBarComponent,
    SectionPanelComponent,
    StatusBadgeComponent,
    UptimePipe
  ],
  templateUrl: './dashboard-page.component.html',
  styleUrl: './dashboard-page.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class DashboardPageComponent {
  private readonly facade = inject(DashboardFacadeService);
  private readonly api = inject(MonitoringApiService);

  readonly vm$ = this.facade.viewModel$;
  readonly docsUrl = this.api.getDocsUrl();

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

  protected loadAverageLabel(loadAverage: unknown): string {
    const normalized = normalizeLoadAverage(loadAverage as never);
    if (!normalized) {
      return 'N/A';
    }
    return normalized.map((item) => item.toFixed(2)).join(' / ');
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

  protected trackByDiskKey(index: number, item: DiskDeviceInfo): string {
    return `${item.mountpoint}-${item.device}-${index}`;
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

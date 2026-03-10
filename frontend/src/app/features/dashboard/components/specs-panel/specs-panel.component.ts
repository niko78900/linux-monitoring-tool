import { DecimalPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { SystemResponse } from '../../../../core/models/api.models';
import { BytesPipe } from '../../../../core/pipes/bytes.pipe';
import { MbSizePipe } from '../../../../core/pipes/mb-size.pipe';
import { NaPipe } from '../../../../core/pipes/na.pipe';

@Component({
  selector: 'app-dashboard-specs-panel',
  standalone: true,
  imports: [BytesPipe, DecimalPipe, MbSizePipe, NaPipe],
  templateUrl: './specs-panel.component.html',
  styleUrl: './specs-panel.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class SpecsPanelComponent {
  @Input({ required: true }) system!: SystemResponse;

  protected isExpanded = true;

  protected togglePanel(): void {
    this.isExpanded = !this.isExpanded;
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

  protected cpuThreadDensity(): string {
    const specs = this.system.specs?.cpu;
    if (!specs || specs.physical_cores <= 0 || specs.logical_cores <= 0) {
      return 'N/A';
    }

    const ratio = specs.logical_cores / specs.physical_cores;
    return `${ratio.toFixed(2).replace(/\.00$/, '')}x threads/core`;
  }

  protected memoryBrandLabel(): string {
    const brands = this.system.specs?.memory?.manufacturers ?? [];
    if (!Array.isArray(brands) || brands.length === 0) {
      return 'N/A';
    }
    return brands.join(', ');
  }

  protected memorySpeedLabel(): string {
    const speedMhz = this.system.specs?.memory?.speed_mhz;
    if (speedMhz === null || speedMhz === undefined || Number.isNaN(speedMhz) || speedMhz <= 0) {
      return 'N/A';
    }
    return `${Math.round(speedMhz).toLocaleString()} MT/s`;
  }

  protected memoryModulesSummary(): string {
    const modules = this.system.specs?.memory?.modules ?? [];
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
}

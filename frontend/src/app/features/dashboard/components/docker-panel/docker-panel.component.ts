import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { DockerContainerInfo, DockerResponse } from '../../../../core/models/api.models';
import { ResourceState } from '../../../../core/models/ui.models';
import { LocalDatePipe } from '../../../../core/pipes/local-date.pipe';
import { NaPipe } from '../../../../core/pipes/na.pipe';
import { StatusTone, formatDockerPorts, usageTone } from '../../../../core/utils/format.utils';
import { ProgressBarComponent } from '../../../../shared/components/progress-bar/progress-bar.component';
import { SectionPanelComponent } from '../../../../shared/components/section-panel/section-panel.component';
import { StatusBadgeComponent } from '../../../../shared/components/status-badge/status-badge.component';

@Component({
  selector: 'app-dashboard-docker-panel',
  standalone: true,
  imports: [LocalDatePipe, NaPipe, ProgressBarComponent, SectionPanelComponent, StatusBadgeComponent],
  templateUrl: './docker-panel.component.html',
  styleUrl: './docker-panel.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class DockerPanelComponent {
  @Input({ required: true }) dockerState!: ResourceState<DockerResponse>;

  protected usageTone = usageTone;

  protected portsLabel(ports: unknown): string {
    return formatDockerPorts(ports as never);
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

  protected trackByContainerId(index: number, item: { id: string }): string {
    return `${item.id}-${index}`;
  }

  private isContainerRunning(state: string | null | undefined): boolean {
    return (state || '').trim().toLowerCase() === 'running';
  }
}

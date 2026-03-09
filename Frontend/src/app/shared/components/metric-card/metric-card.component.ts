import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { NaPipe } from '../../../core/pipes/na.pipe';
import { StatusTone } from '../../../core/utils/format.utils';
import { ProgressBarComponent } from '../progress-bar/progress-bar.component';
import { StatusBadgeComponent } from '../status-badge/status-badge.component';

@Component({
  selector: 'app-metric-card',
  standalone: true,
  imports: [NaPipe, ProgressBarComponent, StatusBadgeComponent],
  templateUrl: './metric-card.component.html',
  styleUrl: './metric-card.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MetricCardComponent {
  @Input({ required: true }) title = '';
  @Input() value: string | number | null = 'N/A';
  @Input() subtitle: string | null = null;
  @Input() progressValue: number | null = null;
  @Input() progressTone: StatusTone = 'neutral';
  @Input() badgeLabel: string | null = null;
  @Input() badgeTone: StatusTone = 'neutral';
}

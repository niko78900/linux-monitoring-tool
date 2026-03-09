import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { StatusTone, clampPercent } from '../../../core/utils/format.utils';

@Component({
  selector: 'app-progress-bar',
  standalone: true,
  templateUrl: './progress-bar.component.html',
  styleUrl: './progress-bar.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ProgressBarComponent {
  @Input() value: number | null | undefined = null;
  @Input() tone: StatusTone = 'neutral';
  @Input() showLabel = true;

  get widthPercent(): number {
    return clampPercent(this.value);
  }

  get valueLabel(): string {
    if (this.value === null || this.value === undefined || Number.isNaN(this.value)) {
      return 'N/A';
    }
    return `${Math.round(this.value)}%`;
  }
}

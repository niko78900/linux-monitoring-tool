import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { StatusTone } from '../../../core/utils/format.utils';

@Component({
  selector: 'app-status-badge',
  standalone: true,
  templateUrl: './status-badge.component.html',
  styleUrl: './status-badge.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class StatusBadgeComponent {
  @Input() label = 'Unknown';
  @Input() tone: StatusTone = 'neutral';
}

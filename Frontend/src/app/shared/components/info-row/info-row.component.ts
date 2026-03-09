import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { NaPipe } from '../../../core/pipes/na.pipe';

@Component({
  selector: 'app-info-row',
  standalone: true,
  imports: [NaPipe],
  templateUrl: './info-row.component.html',
  styleUrl: './info-row.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class InfoRowComponent {
  @Input({ required: true }) label = '';
  @Input() value: string | number | null = 'N/A';
}

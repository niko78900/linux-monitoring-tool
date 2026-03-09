import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

@Component({
  selector: 'app-section-panel',
  standalone: true,
  templateUrl: './section-panel.component.html',
  styleUrl: './section-panel.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class SectionPanelComponent {
  @Input({ required: true }) title = '';
  @Input() subtitle: string | null = null;
}

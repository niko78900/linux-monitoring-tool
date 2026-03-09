import { Pipe, PipeTransform } from '@angular/core';

@Pipe({
  name: 'uptime',
  standalone: true
})
export class UptimePipe implements PipeTransform {
  transform(value: number | null | undefined): string {
    if (value === null || value === undefined || Number.isNaN(value)) {
      return 'N/A';
    }

    const total = Math.max(0, Math.floor(value));
    const days = Math.floor(total / 86400);
    const hours = Math.floor((total % 86400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;

    const parts: string[] = [];
    if (days > 0) {
      parts.push(`${days}d`);
    }
    parts.push(`${hours}h`, `${minutes}m`, `${seconds}s`);
    return parts.join(' ');
  }
}

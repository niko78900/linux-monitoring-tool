import { Pipe, PipeTransform } from '@angular/core';

import { formatMegabytes } from '../utils/format.utils';

@Pipe({
  name: 'mbSize',
  standalone: true
})
export class MbSizePipe implements PipeTransform {
  transform(value: number | null | undefined): string {
    return formatMegabytes(value);
  }
}

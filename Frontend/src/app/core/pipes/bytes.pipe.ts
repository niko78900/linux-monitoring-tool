import { Pipe, PipeTransform } from '@angular/core';

import { formatBytes } from '../utils/format.utils';

@Pipe({
  name: 'bytes',
  standalone: true
})
export class BytesPipe implements PipeTransform {
  transform(value: number | null | undefined): string {
    return formatBytes(value);
  }
}

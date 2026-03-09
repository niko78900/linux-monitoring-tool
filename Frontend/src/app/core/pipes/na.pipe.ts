import { Pipe, PipeTransform } from '@angular/core';

import { formatOptional } from '../utils/format.utils';

@Pipe({
  name: 'na',
  standalone: true
})
export class NaPipe implements PipeTransform {
  transform(value: unknown): string {
    return formatOptional(value);
  }
}

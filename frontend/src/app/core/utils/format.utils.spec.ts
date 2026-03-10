import {
  formatDockerPorts,
  normalizeLoadAverage,
  usageTone
} from './format.utils';

describe('format utils', () => {
  describe('formatDockerPorts', () => {
    it('returns N/A when ports are unavailable', () => {
      expect(formatDockerPorts(null)).toBe('N/A');
    });

    it('returns string payloads as-is', () => {
      expect(formatDockerPorts('3000/tcp')).toBe('3000/tcp');
    });

    it('compresses mapped contiguous port ranges', () => {
      const ports = {
        '25565/tcp': ['0.0.0.0:25565'],
        '25566/tcp': ['0.0.0.0:25566'],
        '25567/tcp': ['0.0.0.0:25567']
      };

      expect(formatDockerPorts(ports)).toBe('0.0.0.0:25565-25567 -> 25565-25567/tcp');
    });

    it('compresses unbound contiguous ports by protocol', () => {
      const ports = {
        '8080/tcp': [],
        '8081/tcp': [],
        '8443/tcp': []
      };

      expect(formatDockerPorts(ports)).toBe('8080-8081/tcp unbound | 8443/tcp unbound');
    });
  });

  describe('normalizeLoadAverage', () => {
    it('normalizes object-based load averages', () => {
      expect(
        normalizeLoadAverage({
          one_min: 0.6,
          five_min: 0.8,
          fifteen_min: 1.0
        })
      ).toEqual([0.6, 0.8, 1.0]);
    });

    it('normalizes tuple-based load averages', () => {
      expect(normalizeLoadAverage([0.7, 0.9, 1.1])).toEqual([0.7, 0.9, 1.1]);
    });
  });

  describe('usageTone', () => {
    it('returns neutral for null', () => {
      expect(usageTone(null)).toBe('neutral');
    });

    it('returns good under warning threshold', () => {
      expect(usageTone(65)).toBe('good');
    });

    it('returns warn in warning threshold', () => {
      expect(usageTone(75)).toBe('warn');
    });

    it('returns bad in critical threshold', () => {
      expect(usageTone(95)).toBe('bad');
    });
  });
});

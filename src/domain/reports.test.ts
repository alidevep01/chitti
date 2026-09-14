import { describe, expect, it } from 'vitest';

import { demoChittis, demoUsers } from '@/data/demo';
import { buildDemoReports } from './reports';

describe('reliability reports', () => {
  it('shows all members to the administrator and only self to a member', () => {
    expect(buildDemoReports(demoUsers[0]!, demoChittis, '2026-09-14')).toHaveLength(4);
    const memberReports = buildDemoReports(demoUsers[1]!, demoChittis, '2026-09-14');
    expect(memberReports).toHaveLength(1);
    expect(memberReports[0]?.userId).toBe(demoUsers[1]?.id);
  });

  it('calculates a score out of ten from assessed due dates', () => {
    const report = buildDemoReports(demoUsers[0]!, demoChittis, '2026-09-14')[0]!;
    expect(report.onTimePayments).toBe(1);
    expect(report.reliabilityScore).toBe(10);
    expect(report.confirmedAmountPaise).toBe(500_000);
  });
});

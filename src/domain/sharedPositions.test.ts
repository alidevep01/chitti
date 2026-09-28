import { describe, expect, it } from 'vitest';
import { manualRankingEntries, parseShareAmount, sharedPositionError, sharedPositionSources } from './sharedPositions';
import type { Chitti } from './types';

const chitti: Chitti = {
  id: 'test', name: 'Shared test', description: '', createdAt: '2026-01-01', monthlyAmountPaise: 2000000,
  memberCount: 3, startDate: '2026-01-01', firstDueDate: '2026-01-01', endDate: '2026-03-01',
  dueDay: 1, upiId: 'admin@test', payeeName: 'Admin', status: 'inviting', isImported: true,
  members: [
    { id: 'admin', name: 'Admin', email: 'admin@test.com', phone: '9000000000', joined: true, isAdmin: true, approval: 'accepted', payoutPosition: 1 },
    { id: 'owner', name: 'Owner', email: 'owner@test.com', phone: '9000000001', joined: true, isAdmin: false, approval: 'accepted', payoutPosition: 2 },
  ],
  invitations: [{ id: 'main', name: 'Invited main', email: 'main@test.com', phone: '9000000002', status: 'pending', payoutPosition: 3 }],
  rounds: [],
};
const child = { id: 'child', name: 'Child', email: 'child@test.com', phone: '9000000003', status: 'pending' as const, payoutPosition: 3, coOwnerSourceInvitationId: 'main', coOwnerShareBps: 5000 };

describe('shared position form and ranking', () => {
  it('offers joined and invited main owners before activation', () => {
    expect(sharedPositionSources(chitti).map((source) => source.key)).toEqual(['member:admin', 'member:owner', 'invitation:main']);
  });
  it('reserves invited shares and never offers a pending co-owner as a main owner', () => {
    const sources = sharedPositionSources({ ...chitti, invitations: [...chitti.invitations!, child] });
    expect(sources.find((source) => source.id === 'main')?.availableAmountPaise).toBe(1000000);
    expect(sources.some((source) => source.id === 'child')).toBe(false);
  });
  it('allows more than three owners while money remains available', () => {
    const sources = sharedPositionSources({ ...chitti, invitations: [...chitti.invitations!, child, { ...child, id: 'third', coOwnerShareBps: 2500 }] });
    expect(sources.find((source) => source.payoutPosition === 3)?.availableAmountPaise).toBe(500000);
  });
  it('subtracts pending reservations from the remaining joined-owner share', () => {
    const sources = sharedPositionSources({ ...chitti, invitations: [{ ...child, payoutPosition: 2, coOwnerSourceInvitationId: undefined, coOwnerSourceMemberId: 'owner' }] });
    expect(sources.find((source) => source.id === 'owner')?.availableAmountPaise).toBe(1000000);
  });
  it('groups a pending main and co-owner into one draggable position', () => {
    const entries = manualRankingEntries({ ...chitti, invitations: [...chitti.invitations!, child] });
    expect(entries).toHaveLength(2);
    expect(entries[1]?.name).toContain('Child');
    expect(entries[1]?.name).toContain('Invited main');
    expect(entries[1]?.detail).toContain('move together');
  });
  it('keeps the administrator and their co-owners at position one', () => {
    expect(manualRankingEntries({ ...chitti, invitations: [...chitti.invitations!, { ...child, payoutPosition: 1, coOwnerSourceMemberId: 'admin', coOwnerSourceInvitationId: undefined }] })).toHaveLength(2);
  });
  it('does not offer completed, cancelled or non-imported pending chittis', () => {
    for (const status of ['completed', 'cancelled', 'ready'] as const) expect(sharedPositionSources({ ...chitti, status })).toEqual([]);
    expect(sharedPositionSources({ ...chitti, isImported: false })).toEqual([]);
    expect(sharedPositionSources({ ...chitti, status: 'active', rounds: [] })).toEqual([]);
  });
  it('keeps unshared positions editable and explains missing migrations', () => {
    expect(manualRankingEntries(chitti).map((entry) => entry.previousPosition)).toEqual([2, 3]);
    expect(sharedPositionError({ message: 'add_coowner_invitation is missing in schema cache' })).toContain('202609270003');
    expect(sharedPositionError({ message: 'Administrator access required' })).toBe('Administrator access required');
  });
  it('accepts exact paise and rejects invalid or over-precise amounts', () => {
    expect(parseShareAmount('5000')).toBe(500000);
    expect(parseShareAmount('6666.67')).toBe(666667);
    for (const amount of ['', '0', '-1', '1.001', 'NaN', '33%', '1e3']) expect(parseShareAmount(amount)).toBeUndefined();
  });
  it('reserves exact third amounts and leaves the one-paise remainder with the source', () => {
    const invites = [child, { ...child, id: 'second' }].map((invite) => ({ ...invite, coOwnerAmountPaise: 666667 }));
    expect(sharedPositionSources({ ...chitti, invitations: [...chitti.invitations!, ...invites] }).find((source) => source.id === 'main')?.availableAmountPaise).toBe(666666);
  });
  it('leaves ₹15,000 when a co-owner reserves ₹5,000 of a ₹20,000 position', () => {
    const sources = sharedPositionSources({ ...chitti, invitations: [...chitti.invitations!, { ...child, coOwnerAmountPaise: 500000 }] });
    expect(sources.find((source) => source.id === 'main')?.availableAmountPaise).toBe(1500000);
  });
});

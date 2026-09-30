import { describe, expect, it } from 'vitest';
import { combineCandidates, combinePositions, movableCombineCandidates } from './combinePositions';
import type { Chitti } from './types';

const base: Chitti = {
  id: 'test', name: 'Test', monthlyAmountPaise: 2000000, memberCount: 4,
  startDate: '2026-01-01', firstDueDate: '2026-01-31', endDate: '2026-04-30', dueDay: 31,
  upiId: 'admin@test', payeeName: 'Admin', status: 'inviting', isImported: true, createdAt: '', rounds: [],
  members: [1, 2, 3].map((p) => ({ id: `m${p}`, name: `Member ${p}`, email: `m${p}@test.com`, phone: '9000000000', joined: true, isAdmin: p === 1, approval: 'accepted', payoutPosition: p })),
  invitations: [{ id: 'i4', name: 'Invited', email: 'i4@test.com', phone: '9000000000', status: 'pending', payoutPosition: 4 }],
};
describe('combine existing full positions', () => {
  it('keeps two accounts, exact amounts and one shared rank; shortens and compacts', () => {
    const result = combinePositions(base, 'member:m2', 'member:m3', 500000);
    expect(result.members).toHaveLength(3);
    expect(result.members.map((m) => m.payoutPosition)).toEqual([1,2,2]);
    expect(result.members.slice(1).map((m) => m.contributionAmountPaise)).toEqual([1500000,500000]);
    expect(result.invitations![0]!.payoutPosition).toBe(3);
    expect(result.memberCount).toBe(3);
    expect(result.endDate).toBe('2026-03-31');
    expect(base.memberCount).toBe(4);
  });
  it('compacts the kept rank when the removed rank precedes it', () => {
    expect(combinePositions(base, 'member:m3', 'member:m2', 666667).members.map((m) => m.payoutPosition)).toEqual([1,2,2]);
  });
  it('reserves pending invite amounts without deducting twice on acceptance', () => {
    const result = combinePositions(base, 'member:m2', 'invitation:i4', 500000);
    expect(result.invitations![0]).toMatchObject({ payoutPosition: 2, coOwnerSourceMemberId: 'm2', coOwnerAmountPaise: 500000 });
    expect(result.members[1]!.contributionAmountPaise).toBeUndefined();
  });
  it('supports keeping an invited position and moving a joined member', () => {
    const result = combinePositions(base, 'invitation:i4', 'member:m2', 500000);
    expect(result.invitations![0]).toMatchObject({ payoutPosition: 3 });
    expect(result.invitations!.find((i) => i.status === 'accepted')).toMatchObject({ coOwnerSourceInvitationId: 'i4', coOwnerAmountPaise: 500000 });
    expect(combineCandidates(result).find((p) => p.key === 'invitation:i4')?.availableAmountPaise).toBe(1500000);
    expect(result.members[1]!.payoutPosition).toBe(3);
  });
  it('supports two pending invitations and preserves their IDs', () => {
    const input = { ...base, members: base.members.slice(0,2), invitations: [...base.invitations!, { ...base.invitations![0]!, id: 'i3', payoutPosition: 3 }] };
    expect(combinePositions(input, 'invitation:i3', 'invitation:i4', 500000).invitations![0]).toMatchObject({ id: 'i4', coOwnerSourceInvitationId: 'i3', coOwnerAmountPaise: 500000, payoutPosition: 3 });
  });
  it('keeps the admin first and prevents merging a position twice', () => {
    expect(() => combinePositions(base, 'member:m2', 'member:m1', 500000)).toThrow();
    const result = combinePositions(base, 'member:m1', 'member:m2', 500000);
    expect(result.members[0]!.payoutPosition).toBe(1);
    expect(movableCombineCandidates(result).some((p) => p.payoutPosition === 1)).toBe(false);
    expect(combineCandidates(result).some((p) => p.payoutPosition === 1)).toBe(true);
  });
  it('blocks started/history-bearing, too-small and already shared chittis', () => {
    for (const input of [{ ...base, status: 'active' as const }, { ...base, importedCompletedMonths: 1 }, { ...base, memberCount: 2 }, { ...base, isImported: false }]) expect(combineCandidates(input)).toEqual([]);
    expect(() => combinePositions(base, 'member:m2', 'member:m2', 500000)).toThrow();
    for (const amount of [0,-1,2000000,0.5,NaN]) expect(() => combinePositions(base,'member:m2','member:m3',amount)).toThrow();
  });
  it('combines five joined people into one slot without changing prior co-owner amounts', () => {
    let result: Chitti = { ...base, memberCount: 7, members: Array.from({ length: 6 }, (_, i) => ({ ...base.members[0]!, id: `m${i+1}`, email: `m${i+1}@test.com`, isAdmin: i === 0, payoutPosition: i+1 })), invitations: [{ ...base.invitations![0]!, payoutPosition: 7 }] };
    for (let p = 3; p <= 6; p++) result = combinePositions(result, 'member:m2', `member:m${p}`, 300000);
    expect(result.memberCount).toBe(3);
    expect(result.members.filter((m) => m.payoutPosition === 2)).toHaveLength(5);
    expect(result.members.slice(1).map((m) => m.contributionAmountPaise)).toEqual([800000,300000,300000,300000,300000]);
    expect(() => combinePositions(result, 'member:m2', 'invitation:i4', 800000)).toThrow();
  });
  it('combines multiple pending invitations into an already shared pending main position', () => {
    let result: Chitti = { ...base, memberCount: 6, members: [base.members[0]!], invitations: [2,3,4,5,6].map((p) => ({ ...base.invitations![0]!, id: `i${p}`, email: `i${p}@test.com`, payoutPosition: p })) };
    for (const p of [3,4,5,6]) result = combinePositions(result, 'invitation:i2', `invitation:i${p}`, 333333);
    expect(result.memberCount).toBe(2);
    expect(result.invitations!.filter((i) => i.payoutPosition === 2)).toHaveLength(5);
    expect(result.invitations!.filter((i) => i.coOwnerSourceInvitationId === 'i2').map((i) => i.coOwnerAmountPaise)).toEqual([333333,333333,333333,333333]);
  });
  it('keeps pending reservations when another joined owner is combined', () => {
    const reserved = combinePositions(base, 'member:m2', 'invitation:i4', 500000);
    const result = combinePositions(reserved, 'member:m2', 'member:m3', 666667);
    expect(result.members[1]!.contributionAmountPaise).toBe(1333333);
    expect(result.invitations![0]!.coOwnerAmountPaise).toBe(500000);
  });
});

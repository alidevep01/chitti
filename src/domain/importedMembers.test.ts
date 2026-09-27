import { describe, expect, it } from 'vitest';
import { importedMemberError, importedMemberPositions } from './importedMembers';
import type { Chitti } from './types';

describe('pending imported member positions', () => {
  const full: Pick<Chitti, 'memberCount' | 'members' | 'invitations'> = {
    memberCount: 3,
    members: [{ id: 'admin', name: 'Admin', email: 'admin@example.com', phone: '9000000000', joined: true, isAdmin: true, approval: 'accepted', payoutPosition: 1 }],
    invitations: [2, 3].map((payoutPosition) => ({ id: String(payoutPosition), name: 'Member', email: `member${payoutPosition}@example.com`, phone: '9000000000', status: 'pending', payoutPosition })),
  };
  it('offers the next month when accepted members and pending invites fill every slot', () => {
    expect(importedMemberPositions(full)).toEqual([4]);
    expect(full.memberCount).toBe(3);
  });
  it('fills empty planned positions before extending', () => {
    expect(importedMemberPositions({ ...full, memberCount: 5 })).toEqual([4, 5]);
  });
  it('keeps accepted invitations reserved and frees revoked/expired invitations', () => {
    expect(importedMemberPositions({ ...full, invitations: full.invitations!.map((item) => ({ ...item, status: 'accepted' })) })).toEqual([4]);
    for (const status of ['revoked', 'expired'] as const) {
      expect(importedMemberPositions({ ...full, invitations: full.invitations!.map((item) => ({ ...item, status })) })).toEqual([2, 3]);
    }
  });
  it('reserves joined-member positions even without their invitation record', () => {
    expect(importedMemberPositions({ ...full, invitations: [], members: [1, 2, 3].map((payoutPosition) => ({ ...full.members[0]!, payoutPosition })) })).toEqual([4]);
  });
  it('enforces the 50-month limit but allows empty slots at the limit', () => {
    const invitations = Array.from({ length: 49 }, (_, index) => ({ ...full.invitations![0]!, payoutPosition: index + 2 }));
    expect(importedMemberPositions({ ...full, memberCount: 50, invitations })).toEqual([]);
    expect(importedMemberPositions({ ...full, memberCount: 50, invitations: invitations.slice(1) })).toEqual([2]);
  });
  it('explains an unapplied migration without masking authorization errors', () => {
    expect(importedMemberError({ message: 'Choose an available payout month between 2 and 7' })).toContain('202609270001');
    expect(importedMemberError({ message: 'Administrator access required' })).toBe('Administrator access required');
  });
});

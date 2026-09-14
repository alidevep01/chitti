import { describe, expect, it } from 'vitest';
import { addMonthsClamped } from '@/lib/format';
import { assignPayoutPositions, buildRounds, canTransitionChitti, refreshRound, totalPot } from './rules';
import type { ChittiMember, ChittiRound } from './types';

const members: ChittiMember[] = [
  { id: 'admin', name: 'Admin', email: 'a@example.com', phone: '1', joined: true, approval: 'pending', isAdmin: true },
  { id: 'b', name: 'B', email: 'b@example.com', phone: '2', joined: true, approval: 'pending' },
  { id: 'c', name: 'C', email: 'c@example.com', phone: '3', joined: true, approval: 'pending' },
];

describe('chitti rules', () => {
  it('calculates the monthly pot in paise', () => expect(totalPot(500_000, 10)).toBe(5_000_000));
  it('clamps month-end dates', () => expect(addMonthsClamped('2028-01-31', 1)).toBe('2028-02-29'));
  it('keeps the administrator first and assigns each position once', () => {
    for (let run = 0; run < 100; run += 1) {
      const result = assignPayoutPositions(members);
      expect(result[0]?.id).toBe('admin');
      expect(new Set(result.map((item) => item.payoutPosition)).size).toBe(3);
      expect(new Set(result.map((item) => item.id))).toEqual(new Set(members.map((item) => item.id)));
    }
  });
  it('allows only defined lifecycle transitions', () => {
    expect(canTransitionChitti('draft', 'inviting')).toBe(true);
    expect(canTransitionChitti('awaiting_approval', 'ready')).toBe(true);
    expect(canTransitionChitti('active', 'ready')).toBe(false);
    expect(canTransitionChitti('completed', 'active')).toBe(false);
  });
  it('creates one clamped round per payout position', () => {
    const positioned = members.map((member, index) => ({ ...member, payoutPosition: index + 1 }));
    const rounds = buildRounds(positioned, '2028-01-31', '2028-01-10');
    expect(rounds.map((round) => round.dueDate)).toEqual(['2028-01-31', '2028-02-29', '2028-03-31']);
    expect(rounds.map((round) => round.periodStartDate)).toEqual(['2028-01-10', '2028-02-10', '2028-03-10']);
    expect(rounds.every((round) => round.contributions.length === members.length)).toBe(true);
  });
  it('makes payout ready only when all contributions are confirmed', () => {
    const round: ChittiRound = {
      id: 'r1', number: 1, periodStartDate: '2026-01-01', dueDate: '2026-01-01', recipientMemberId: 'admin', status: 'collecting', payoutStatus: 'blocked',
      contributions: members.map((member) => ({ id: member.id, memberId: member.id, status: 'confirmed' })),
    };
    expect(refreshRound(round).payoutStatus).toBe('ready');
    round.contributions[0]!.status = 'submitted';
    expect(refreshRound(round).payoutStatus).toBe('blocked');
  });
});

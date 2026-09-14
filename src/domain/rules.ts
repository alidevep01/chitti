import { addMonthsClamped } from '@/lib/format';
import type { ChittiMember, ChittiRound, ChittiStatus } from './types';

const allowedTransitions: Record<ChittiStatus, readonly ChittiStatus[]> = {
  draft: ['inviting', 'cancelled'],
  inviting: ['ready', 'cancelled'],
  ready: ['shuffle_scheduled', 'cancelled'],
  shuffle_scheduled: ['awaiting_approval'],
  awaiting_approval: ['ready', 'active'],
  active: ['completed'],
  completed: [],
  cancelled: [],
};

export function canTransitionChitti(from: ChittiStatus, to: ChittiStatus): boolean {
  return allowedTransitions[from].includes(to);
}

export function totalPot(monthlyAmountPaise: number, memberCount: number): number {
  if (!Number.isInteger(monthlyAmountPaise) || monthlyAmountPaise <= 0) throw new Error('Monthly amount must be positive');
  if (!Number.isInteger(memberCount) || memberCount < 2) throw new Error('At least two members are required');
  return monthlyAmountPaise * memberCount;
}

export function secureShuffle<T>(items: readonly T[], randomValues?: Uint32Array): T[] {
  const result = [...items];
  const values = randomValues ?? crypto.getRandomValues(new Uint32Array(Math.max(1, result.length)));
  for (let index = result.length - 1; index > 0; index -= 1) {
    const swapIndex = values[index % values.length]! % (index + 1);
    [result[index], result[swapIndex]] = [result[swapIndex]!, result[index]!];
  }
  return result;
}

export function assignPayoutPositions(members: ChittiMember[]): ChittiMember[] {
  const admin = members.find((member) => member.isAdmin);
  if (!admin) throw new Error('An administrator member is required');
  const rest = secureShuffle(members.filter((member) => !member.isAdmin));
  return [admin, ...rest].map((member, index) => ({ ...member, payoutPosition: index + 1, approval: 'pending' }));
}

export function buildRounds(members: ChittiMember[], firstDueDate: string, startDate = firstDueDate): ChittiRound[] {
  return [...members]
    .sort((a, b) => (a.payoutPosition ?? 0) - (b.payoutPosition ?? 0))
    .map((recipient, index) => ({
      id: `round-${Date.now()}-${index + 1}`,
      number: index + 1,
      periodStartDate: addMonthsClamped(startDate, index),
      dueDate: addMonthsClamped(firstDueDate, index),
      recipientMemberId: recipient.id,
      status: index === 0 ? 'collecting' : 'upcoming',
      payoutStatus: 'blocked',
      contributions: members.map((member) => ({
        id: `contribution-${index + 1}-${member.id}`,
        memberId: member.id,
        status: 'due',
      })),
    }));
}

export function refreshRound(round: ChittiRound): ChittiRound {
  const ready = round.contributions.length > 0 && round.contributions.every((item) => item.status === 'confirmed');
  return {
    ...round,
    status: ready && round.payoutStatus !== 'paid' ? 'ready_for_payout' : round.status,
    payoutStatus: ready && round.payoutStatus !== 'paid' ? 'ready' : round.payoutStatus,
  };
}

import type { Chitti } from './types';
import { sharedPositionSources } from './sharedPositions';
import { addMonthsClamped } from '../lib/format';

export function canCombinePositions(chitti: Chitti) {
  return chitti.isImported && chitti.status === 'inviting' && chitti.rounds.length === 0
    && !chitti.importedCompletedMonths && chitti.memberCount > 2;
}

export function combineCandidates(chitti: Chitti) {
  if (!canCombinePositions(chitti)) return [];
  return sharedPositionSources(chitti);
}

export function movableCombineCandidates(chitti: Chitti) {
  return combineCandidates(chitti).filter((owner) => {
    const occupants = chitti.members.filter((m) => m.payoutPosition === owner.payoutPosition).length
      + (chitti.invitations ?? []).filter((i) => i.status === 'pending' && i.payoutPosition === owner.payoutPosition).length;
    return occupants === 1 && owner.availableAmountPaise === chitti.monthlyAmountPaise;
  });
}

/** Demo equivalent of the transactional RPC; pending shares are deducted on acceptance. */
export function combinePositions(chitti: Chitti, keepKey: string, moveKey: string, amount: number): Chitti {
  const candidates = combineCandidates(chitti);
  const keep = candidates.find((p) => p.key === keepKey);
  const move = movableCombineCandidates(chitti).find((p) => p.key === moveKey);
  if (!keep || !move || keep.payoutPosition === move.payoutPosition || move.payoutPosition === 1) throw new Error('Move a separate full position into the selected position; keep the administrator at position 1.');
  if (!Number.isSafeInteger(amount) || amount <= 0 || amount >= keep.availableAmountPaise) throw new Error('Enter an amount below the selected owner’s available amount, leaving at least one paise.');
  // Joined owners still hold pending reservations until those invitations are accepted.
  const sourceMember = chitti.members.find((m) => keep.kind === 'member' && m.id === keep.id);
  const remainder = (sourceMember?.contributionAmountPaise ?? Math.floor(chitti.monthlyAmountPaise * (sourceMember?.contributionShareBps ?? 10000) / 10000)) - amount;
  const invitations = [...(chitti.invitations ?? [])];
  if (move.kind === 'member') {
    const person = chitti.members.find((m) => m.id === move.id)!;
    if (!invitations.some((i) => i.status === 'accepted' && i.email.toLowerCase() === person.email.toLowerCase())) {
      invitations.push({ id: `combined-${person.id}`, name: person.name, email: person.email, phone: person.phone, status: 'accepted', payoutPosition: move.payoutPosition });
    }
  }
  const newPosition = (position?: number) => {
    const target = position === move.payoutPosition ? keep.payoutPosition : position;
    return target && target > move.payoutPosition ? target - 1 : target;
  };
  const shareBps = (value: number) => Math.max(1, Math.floor(value * 10000 / chitti.monthlyAmountPaise));
  return {
    ...chitti, memberCount: chitti.memberCount - 1,
    endDate: addMonthsClamped(chitti.firstDueDate, chitti.memberCount - 2),
    members: chitti.members.map((m) => ({ ...m, payoutPosition: newPosition(m.payoutPosition),
      ...(move.kind === 'member' && (m.id === move.id || (keep.kind === 'member' && m.id === keep.id))
        ? { contributionAmountPaise: m.id === move.id ? amount : remainder, contributionShareBps: shareBps(m.id === move.id ? amount : remainder) } : {}),
    })),
    invitations: invitations.map((i) => {
      const result = { ...i, payoutPosition: newPosition(i.payoutPosition) };
      const movedMember = chitti.members.find((m) => move.kind === 'member' && m.id === move.id);
      if ((move.kind === 'invitation' && i.id === move.id) || (movedMember && i.status === 'accepted' && i.email.toLowerCase() === movedMember.email.toLowerCase())) return { ...result, coOwnerAmountPaise: amount, coOwnerShareBps: shareBps(amount), coOwnerSourceMemberId: keep.kind === 'member' ? keep.id : undefined, coOwnerSourceInvitationId: keep.kind === 'invitation' ? keep.id : undefined };
      return result;
    }),
  };
}

import type { Chitti, ManualPayoutOrderItem } from './types';

export interface SharedPositionSource extends ManualPayoutOrderItem {
  key: string;
  name: string;
  payoutPosition: number;
  availableAmountPaise: number;
}

export function sharedPositionSources(chitti: Chitti): SharedPositionSource[] {
  const pendingImport = chitti.isImported && chitti.status === 'inviting';
  if (!pendingImport && chitti.status !== 'active') return [];
  const invitations = chitti.invitations ?? [];
  const owners = [
    ...chitti.members.map((member) => ({ kind: 'member' as const, id: member.id, name: member.name, payoutPosition: member.payoutPosition, amount: member.contributionAmountPaise ?? Math.floor(chitti.monthlyAmountPaise * (member.contributionShareBps ?? 10000) / 10000) })),
    ...(pendingImport ? invitations.filter((invite) => invite.status === 'pending' && !invite.coOwnerShareBps)
      .map((invite) => ({ kind: 'invitation' as const, id: invite.id, name: invite.name, payoutPosition: invite.payoutPosition, amount: chitti.monthlyAmountPaise })) : []),
  ];
  return owners.flatMap((owner) => {
    if (!owner.payoutPosition || (!pendingImport && !chitti.rounds.some((round) => round.number === owner.payoutPosition && round.status !== 'completed' && round.payoutStatus !== 'paid'))) return [];
    const reserved = invitations.filter((invite) => owner.kind === 'member'
      ? invite.status === 'pending' && invite.coOwnerSourceMemberId === owner.id
      : ['pending', 'accepted'].includes(invite.status) && invite.coOwnerSourceInvitationId === owner.id)
      .reduce((sum, invite) => sum + (invite.coOwnerAmountPaise ?? Math.floor(chitti.monthlyAmountPaise * (invite.coOwnerShareBps ?? 0) / 10000)), 0);
    const availableAmountPaise = owner.amount - reserved;
    if (availableAmountPaise <= 1) return [];
    return [{ ...owner, key: `${owner.kind}:${owner.id}`, payoutPosition: owner.payoutPosition, availableAmountPaise }];
  });
}

export function manualRankingEntries(chitti: Chitti) {
  const people = [
    ...chitti.members.filter((member) => !member.isAdmin).map((member) => ({ kind: 'member' as const, id: member.id, name: member.name, detail: member.email, previousPosition: member.payoutPosition })),
    ...(chitti.invitations ?? []).filter((invite) => invite.status === 'pending').map((invite) => ({ kind: 'invitation' as const, id: invite.id, name: invite.name, detail: invite.email, previousPosition: invite.payoutPosition })),
  ].sort((a, b) => (a.previousPosition ?? 99) - (b.previousPosition ?? 99) || a.name.localeCompare(b.name));
  if (!chitti.isImported) return people;
  const groups = new Map<number, typeof people>();
  for (const person of people) {
    if (!person.previousPosition || person.previousPosition === 1) continue;
    groups.set(person.previousPosition, [...(groups.get(person.previousPosition) ?? []), person]);
  }
  return [...groups.values()].map((group) => ({
    ...group[0]!, name: group.map((person) => person.name).join(' + '),
    detail: group.length > 1 ? 'Shared payout position · all co-owners move together' : group[0]!.detail,
  }));
}

export function sharedPositionError(value: unknown) {
  const message = value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not create the shared invitation.';
  return message.includes('add_coowner_') || message.includes('after the payout order is active') || message.includes('schema cache')
    ? 'Apply migration 202609270003_amount_based_coowners.sql with Supabase db push, then retry. This device has the new form, but the database needs the amount-based sharing update.' : message;
}

/** Parse currency without silently accepting percentages, extra decimal places or fractional paise. */
export function parseShareAmount(value: string): number | undefined {
  if (!/^\d+(?:\.\d{1,2})?$/.test(value.trim())) return undefined;
  const [rupees, fraction = ''] = value.trim().split('.');
  const paise = Number(rupees) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(paise) && paise > 0 ? paise : undefined;
}

import type { Chitti } from './types';

// Pending imports fill their planned slots first, then extend one month at a time.
export function importedMemberPositions(chitti: Pick<Chitti, 'memberCount' | 'members' | 'invitations'>): number[] {
  const assigned = new Set([
    ...chitti.members.map((member) => member.payoutPosition),
    ...(chitti.invitations ?? [])
      .filter((invite) => invite.status === 'pending' || invite.status === 'accepted')
      .map((invite) => invite.payoutPosition),
  ]);
  const empty = Array.from({ length: chitti.memberCount - 1 }, (_, index) => index + 2)
    .filter((position) => !assigned.has(position));
  return empty.length ? empty : chitti.memberCount < 50 ? [chitti.memberCount + 1] : [];
}

export function importedMemberError(value: unknown): string {
  const message = value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not add this member.';
  if (message.includes('Choose an available payout month between') || message.includes('add_imported_chitti_invitation') || message.includes('schema cache')) {
    return 'Apply database migration 202609270001_expand_pending_existing_chitti.sql with Supabase db push, then retry. Redeploying the website alone does not update the database.';
  }
  return message;
}

import type { ManualPayoutOrderItem } from './types';

export function moveRankingItem<T>(items: T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return items;
  const next = [...items];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item!);
  return next;
}

export function rankingChanged(saved: ManualPayoutOrderItem[], draft: ManualPayoutOrderItem[]) {
  return saved.length !== draft.length || saved.some((item, index) => item.id !== draft[index]?.id || item.kind !== draft[index]?.kind);
}

export function rankingSaveError(value: unknown): string {
  const message = value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not save the payout ranking.';
  if (message.includes('This is already an existing chitti') || message.includes('convert_pending_chitti_to_existing') || message.includes('schema cache')) {
    return 'The database still has the older ranking function. Apply migration 202609260007_edit_pending_existing_ranking.sql with Supabase db push, then retry. Redeploying the website alone does not update the database. Your unsaved order is still shown.';
  }
  return message;
}

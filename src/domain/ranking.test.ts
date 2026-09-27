import { describe, expect, it } from 'vitest';
import { moveRankingItem, rankingChanged, rankingSaveError } from './ranking';
import type { ManualPayoutOrderItem } from './types';

describe('ranking editing', () => {
  const saved: ManualPayoutOrderItem[] = [{ kind: 'member', id: 'a' }, { kind: 'invitation', id: 'b' }, { kind: 'member', id: 'c' }];
  it('moves upward and downward without mutating the saved ranking', () => {
    expect(moveRankingItem(saved, 0, 2).map((item) => item.id)).toEqual(['b', 'c', 'a']);
    expect(moveRankingItem(saved, 2, 0).map((item) => item.id)).toEqual(['c', 'a', 'b']);
    expect(saved.map((item) => item.id)).toEqual(['a', 'b', 'c']);
  });
  it('ignores out-of-range moves so the fixed admin slot cannot be entered', () => {
    expect(moveRankingItem(saved, 0, -1)).toBe(saved);
    expect(moveRankingItem(saved, 2, 3)).toBe(saved);
  });
  it('shows unsaved changes only until the original order is restored', () => {
    const moved = moveRankingItem(saved, 0, 2);
    expect(rankingChanged(saved, moved)).toBe(true);
    expect(rankingChanged(saved, moveRankingItem(moved, 2, 0))).toBe(false);
    expect(rankingChanged(saved, [...saved])).toBe(false);
  });
  it('recognizes the old deployed function and retains other errors', () => {
    expect(rankingSaveError({ message: 'This is already an existing chitti' })).toContain('202609260007');
    expect(rankingSaveError({ message: 'Administrator access required' })).toBe('Administrator access required');
  });
});

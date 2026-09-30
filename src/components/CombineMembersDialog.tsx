import { useState } from 'react';
import { ScrollView, StyleSheet, useWindowDimensions } from 'react-native';
import { Button, Dialog, Portal, Text, TextInput } from 'react-native-paper';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { combineCandidates, movableCombineCandidates } from '@/domain/combinePositions';
import { parseShareAmount } from '@/domain/sharedPositions';
import type { Chitti } from '@/domain/types';
import { addMonthsClamped, formatDate, formatINR } from '@/lib/format';

export function CombineMembersDialog({ chitti, onDismiss, onConfirm }: {
  chitti: Chitti; onDismiss: () => void;
  onConfirm: (keepKey: string, moveKey: string, amount: number) => Promise<void>;
}) {
  const { height } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [keepKey, setKeepKey] = useState('');
  const [moveKey, setMoveKey] = useState('');
  const [amountText, setAmountText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const candidates = combineCandidates(chitti);
  const keep = candidates.find((p) => p.key === keepKey);
  const movable = movableCombineCandidates(chitti);
  const move = movable.find((p) => p.key === moveKey);
  const amount = parseShareAmount(amountText);
  const valid = keep && move && keepKey !== moveKey && move.payoutPosition !== 1
    && keep.payoutPosition !== move.payoutPosition && amount !== undefined && amount < keep.availableAmountPaise;
  async function save() {
    if (!valid || amount === undefined || busy) return;
    setBusy(true); setError('');
    try { await onConfirm(keepKey, moveKey, amount); onDismiss(); }
    catch (value) {
      const message = value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not combine these members.';
      setError(message.includes('schema cache') || message.includes('function public.combine_existing_members') || message.includes('Choose full positions that do not already have co-owners')
        ? 'Apply pending migrations through 202609280002_combine_into_shared_positions.sql with Supabase db push, then retry.' : message);
    } finally { setBusy(false); }
  }
  return <Portal><Dialog visible onDismiss={() => !busy && onDismiss()} style={[styles.dialog, { maxHeight: Math.max(0, height - insets.top - insets.bottom - 48) }]}>
    <Dialog.Title>Combine existing members</Dialog.Title>
    <Dialog.ScrollArea style={styles.scrollArea}><ScrollView style={styles.scroll} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled" automaticallyAdjustKeyboardInsets>
      <Text>Move an existing full position into a new or already shared position. There is no fixed limit on co-owners. Repeat this for each additional person. Everyone keeps their account or invitation; each combine removes one payout month and reduces the pot.</Text>
      <Text variant="titleMedium">Choose the owner whose amount will be split</Text>
      <Text>Their payout position is kept. Other co-owners’ amounts stay unchanged. The administrator must stay at position 1.</Text>
      {candidates.map((p) => <Button key={p.key} disabled={busy} mode={keepKey === p.key ? 'contained-tonal' : 'outlined'} onPress={() => { setKeepKey(p.key); if (moveKey === p.key) setMoveKey(''); setError(''); }}>{p.name} · Month {p.payoutPosition} · {formatINR(p.availableAmountPaise)} available</Button>)}
      <Text variant="titleMedium">Move this person into the shared position</Text>
      {movable.filter((p) => p.payoutPosition !== keep?.payoutPosition && p.payoutPosition !== 1).map((p) => <Button key={p.key} disabled={busy} mode={moveKey === p.key ? 'contained-tonal' : 'outlined'} onPress={() => { setMoveKey(p.key); setError(''); }}>{p.name} · Month {p.payoutPosition}</Button>)}
      <TextInput mode="outlined" label="Moving person's monthly amount (₹)" value={amountText} onChangeText={setAmountText} keyboardType="decimal-pad" disabled={busy} />
      {valid ? <>
        <Text>{move.name}: {formatINR(amount)}/month. {keep.name}: {formatINR(keep.availableAmountPaise - amount)}/month after all pending shares are accepted. Other co-owners keep their amounts.</Text>
        <Text>Both share payout month {keep.payoutPosition > move.payoutPosition ? keep.payoutPosition - 1 : keep.payoutPosition}. Month {move.payoutPosition} is removed; later positions shift up by one.</Text>
        <Text>Duration: {chitti.memberCount} → {chitti.memberCount - 1} months. Monthly pot: {formatINR(chitti.monthlyAmountPaise * chitti.memberCount)} → {formatINR(chitti.monthlyAmountPaise * (chitti.memberCount - 1))}. New end date: {formatDate(addMonthsClamped(chitti.firstDueDate, chitti.memberCount - 2))}.</Text>
        <Text>Each owner’s payout is confirmed separately. If all remaining positions are filled and all invitations accepted, this will activate the chitti.</Text>
      </> : <Text>Choose an owner and a person with a separate full position. Enter an amount above zero and below {formatINR(keep?.availableAmountPaise ?? chitti.monthlyAmountPaise)}, leaving some amount for the selected owner.</Text>}
      {error ? <Text accessibilityRole="alert">{error}</Text> : null}
    </ScrollView></Dialog.ScrollArea>
    <Dialog.Actions style={styles.actions}><Button disabled={busy} onPress={onDismiss}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy || !valid} onPress={() => void save()}>Combine and shorten</Button></Dialog.Actions>
  </Dialog></Portal>;
}
const styles = StyleSheet.create({
  dialog: { width: '92%', maxWidth: 480, alignSelf: 'center', marginVertical: 24 },
  scrollArea: { minHeight: 0, flexShrink: 1, paddingHorizontal: 0 },
  scroll: { minHeight: 0, flexShrink: 1 }, content: { padding: 20, gap: 14 },
  actions: { flexShrink: 0, flexWrap: 'wrap', rowGap: 8 },
});

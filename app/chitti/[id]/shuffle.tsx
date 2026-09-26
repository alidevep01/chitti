import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Dialog, Divider, Icon, Portal, ProgressBar, Snackbar, Text, TextInput, useTheme } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { StatusPill } from '@/components/StatusPill';
import { UserAvatar } from '@/components/UserAvatar';
import { useApp } from '@/data/AppProvider';
import { useChittiPresence } from '@/hooks/useChittiPresence';

export default function ShuffleScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { chittis, currentUser, runShuffle, voteShuffle, simulateApprovals, demoMode } = useApp();
  const chitti = chittis.find((item) => item.id === id);
  const watching = useChittiPresence(id);
  const [revealed, setRevealed] = useState(0);
  const [voting, setVoting] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [rejectionReason, setRejectionReason] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (chitti?.status !== 'awaiting_approval' || revealed >= chitti.memberCount) return;
    const timer = setTimeout(() => setRevealed((value) => value + 1), 650);
    return () => clearTimeout(timer);
  }, [chitti?.status, chitti?.memberCount, revealed]);

  if (!chitti || !currentUser) return <Screen title="Live shuffle" back><EmptyState icon="alert-circle-outline" title="Shuffle unavailable" message="You do not have access to this chitti." /></Screen>;
  const ordered = [...chitti.members].sort((a, b) => (a.payoutPosition ?? 99) - (b.payoutPosition ?? 99));
  const accepted = chitti.members.filter((member) => member.approval === 'accepted').length;
  const rejectedMembers = chitti.members.filter((member) => member.approval === 'rejected');
  const mine = chitti.members.find((member) => member.id === currentUser.id);
  const vote = async (approved: boolean, reason?: string) => {
    setVoting(true);
    setError('');
    try {
      await voteShuffle(chitti.id, approved, reason);
      setRejectOpen(false);
      setRejectionReason('');
      if (!approved) router.replace(`/chitti/${chitti.id}`);
    } catch (value) {
      setError(value instanceof Error
        ? value.message
        : value && typeof value === 'object' && 'message' in value
          ? String(value.message)
          : 'Could not record your decision');
    } finally {
      setVoting(false);
    }
  };

  return (
    <Screen title="Live payout shuffle" back backHref={`/chitti/${chitti.id}`}>
      <Card mode="contained" style={{ backgroundColor: theme.colors.primaryContainer }}><Card.Content style={styles.hero}>
        <View style={styles.shuffleIcon}><Icon source="shuffle-variant" size={40} color={theme.colors.primary} /></View>
        <Text variant="headlineSmall" style={styles.center}>{chitti.name}</Text>
        <Text variant="bodyLarge" style={styles.center}>The administrator always receives month 1. Everyone else is assigned once by the server.</Text>
        <View style={styles.live}><View style={styles.liveDot} /><Text variant="labelLarge">{watching} watching now</Text></View>
      </Card.Content></Card>

      {chitti.status === 'shuffle_scheduled' ? <Card mode="elevated"><Card.Content style={styles.section}><Text variant="titleLarge">Everyone is ready</Text><Text>Connected members will see the same reveal. Members who are away can review it later.</Text>{currentUser.role === 'admin' ? <Button mode="contained" icon="play" contentStyle={styles.bigButton} onPress={() => void runShuffle(chitti.id)}>Start secure shuffle</Button> : <Text>Waiting for the administrator to start…</Text>}</Card.Content></Card> : null}

      {chitti.status === 'awaiting_approval' ? <>
        <Card mode="elevated"><Card.Content style={styles.section}>
          <View style={styles.rowBetween}><Text variant="titleLarge" style={styles.heading}>Payout order</Text><StatusPill status={revealed >= chitti.memberCount ? 'awaiting_approval' : 'shuffle_scheduled'} /></View>
          {ordered.slice(0, Math.max(1, revealed)).map((member, index) => <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View style={styles.person}><View style={[styles.position, { backgroundColor: index === 0 ? theme.colors.secondaryContainer : theme.colors.surfaceVariant }]}><Text variant="titleLarge" style={styles.heading}>{index + 1}</Text></View><UserAvatar name={member.name} uri={member.avatarUri} size={42} /><View><Text variant="titleMedium">{member.name}</Text><Text>{index === 0 ? 'Administrator’s fixed month' : `Receives in month ${index + 1}`}</Text></View></View>{revealed >= chitti.memberCount ? <StatusPill status={member.approval} /> : null}</View></View>)}
          {revealed < chitti.memberCount ? <><View style={styles.progressTrack}><ProgressBar indeterminate color={theme.colors.primary} style={styles.progress} /></View><Text style={styles.center}>Revealing the next member…</Text></> : null}
          {revealed >= chitti.memberCount ? <View style={styles.hash}><Icon source="shield-check-outline" size={20} /><Text variant="bodySmall">Result saved before reveal · {chitti.resultHash}</Text></View> : null}
        </Card.Content></Card>

        {revealed >= chitti.memberCount ? <Card mode="outlined"><Card.Content style={styles.section}>
          <Text variant="titleLarge" style={styles.heading}>Do you agree to this order?</Text>
          <Text>Once every member accepts, the order and membership are locked and monthly rounds are created.</Text>
          <View style={styles.progressTrack}><ProgressBar progress={accepted / chitti.memberCount} style={styles.progress} /></View><Text>{accepted} of {chitti.memberCount} members accepted</Text>
          {mine?.approval === 'pending' ? <View style={styles.voteButtons}><Button mode="outlined" icon="close" disabled={voting} onPress={() => setRejectOpen(true)}>Reject</Button><Button mode="contained" icon="check" loading={voting} disabled={voting} onPress={() => void vote(true)}>I agree</Button></View> : <StatusPill status={mine?.approval ?? 'pending'} />}
          {demoMode && currentUser.role === 'admin' && mine?.approval === 'accepted' ? <Button mode="contained-tonal" icon="account-multiple-check" onPress={() => void simulateApprovals(chitti.id).then(() => router.replace(`/chitti/${chitti.id}`))}>Simulate remaining approvals</Button> : null}
        </Card.Content></Card> : null}
      </> : null}

      {chitti.status === 'ready' && currentUser.role === 'admin' && rejectedMembers.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Reshuffle requested</Text>
        {rejectedMembers.map((member, index) => <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<Text variant="titleMedium">{member.name}</Text><Text>{member.approvalReason || 'No reason was recorded.'}</Text></View>)}
        <Button mode="contained" onPress={() => router.replace(`/chitti/${chitti.id}`)}>Return and schedule a new shuffle</Button>
      </Card.Content></Card> : chitti.status === 'ready' ? <EmptyState icon="calendar-clock" title="Shuffle not scheduled" message="The administrator can schedule the next reveal from the chitti page." action="Back to chitti" onAction={() => router.replace(`/chitti/${chitti.id}`)} /> : null}
      {chitti.status === 'active' ? <EmptyState icon="lock-check-outline" title="Order locked" message="Every member accepted this payout order. It can no longer be changed." action="View chitti" onAction={() => router.replace(`/chitti/${chitti.id}`)} /> : null}
      <Portal><Dialog visible={rejectOpen} onDismiss={() => !voting && setRejectOpen(false)} style={styles.dialog}>
        <Dialog.Title>Why do you want a reshuffle?</Dialog.Title>
        <Dialog.Content style={styles.section}><Text>Your comment will be shown to the administrator.</Text><TextInput mode="outlined" label="Reason for rejecting" value={rejectionReason} onChangeText={setRejectionReason} multiline maxLength={500} autoFocus /></Dialog.Content>
        <Dialog.Actions><Button disabled={voting} onPress={() => setRejectOpen(false)}>Cancel</Button><Button mode="contained" loading={voting} disabled={voting || rejectionReason.trim().length < 3} onPress={() => void vote(false, rejectionReason.trim())}>Request reshuffle</Button></Dialog.Actions>
      </Dialog></Portal>
      <Snackbar visible={Boolean(error)} onDismiss={() => setError('')}>{error}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({
  hero: { alignItems: 'center', gap: 10 }, shuffleIcon: { width: 72, height: 72, borderRadius: 36, backgroundColor: '#ffffff', alignItems: 'center', justifyContent: 'center' },
  center: { textAlign: 'center' }, section: { gap: 14 }, heading: { fontWeight: '700' }, bigButton: { minHeight: 54 },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' },
  person: { flexDirection: 'row', alignItems: 'center', gap: 11 }, position: { width: 42, height: 42, borderRadius: 12, alignItems: 'center', justifyContent: 'center' },
  divider: { marginVertical: 10 }, hash: { backgroundColor: '#eef5e9', padding: 12, borderRadius: 12, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 8 },
  live: { flexDirection: 'row', alignItems: 'center', gap: 7 }, liveDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#5e7464' },
  progress: { height: 10, borderRadius: 10 }, voteButtons: { flexDirection: 'row', justifyContent: 'flex-end', gap: 12 },
  progressTrack: { height: 10, width: '100%' },
  dialog: { width: '92%', maxWidth: 480, alignSelf: 'center' },
});

import { router } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { StyleSheet, View } from 'react-native';
import { Button, Card, FAB, Icon, ProgressBar, Text, useTheme } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { StatusPill } from '@/components/StatusPill';
import { useApp } from '@/data/AppProvider';
import { formatDate, formatINR } from '@/lib/format';
import { brandColors } from '@/theme';

export default function DashboardScreen() {
  const theme = useTheme();
  const { currentUser, chittis, pendingInvitations } = useApp();
  if (!currentUser) return null;
  const active = chittis.filter((item) => !['completed', 'cancelled'].includes(item.status));
  const totalMonthly = active.reduce((sum, item) => {
    const membership = item.members.find((member) => member.id === currentUser.id);
    return sum + Math.floor(item.monthlyAmountPaise * (membership?.contributionShareBps ?? 10000) / 10000);
  }, 0);
  const upcoming = active.flatMap((item) => item.rounds.filter((round) => round.status === 'collecting').map((round) => ({ item, round })))[0];

  return (
    <Screen title="Chitti" titleHomeLink>
      <Text variant="headlineSmall" style={styles.greeting}>Hello, {currentUser.name.split(' ')[0]}</Text>
      <View style={styles.summaryGrid}>
        <LinearGradient colors={[brandColors.lightGold, '#E5C77E', brandColors.gold]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.summary}>
          <View style={styles.summaryContent}>
            <Icon source="calendar-month-outline" size={26} color={brandColors.black} />
            <Text variant="labelLarge">Your monthly total</Text>
            <Text variant="headlineMedium" style={styles.amount}>{formatINR(totalMonthly)}</Text>
          </View>
        </LinearGradient>
        <LinearGradient colors={[brandColors.white, brandColors.lightGold]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.summary}>
          <View style={styles.summaryContent}>
            <Icon source="account-group-outline" size={26} color={brandColors.black} />
            <Text variant="labelLarge">Active chittis</Text>
            <Text variant="headlineMedium" style={styles.amount}>{active.length}</Text>
          </View>
        </LinearGradient>
      </View>

      <Button mode="outlined" textColor={brandColors.black} icon="file-chart-outline" contentStyle={styles.reportButton} onPress={() => router.push('/reports')}>
        {currentUser.role === 'admin' ? 'View all member reports' : 'View my payment report'}
      </Button>

      {pendingInvitations.length > 0 ? <View style={styles.invitationSection}>
        <View style={styles.rowBetween}><Text variant="headlineSmall" style={styles.sectionTitle}>Invitations waiting for you</Text><Text variant="labelLarge">{pendingInvitations.length}</Text></View>
        {pendingInvitations.map((invitation) => <Card key={invitation.id} mode="elevated" style={{ backgroundColor: theme.colors.primaryContainer }}>
          <Card.Content style={styles.cardContent}>
            <View style={styles.rowBetween}><View style={styles.grow}><Text variant="titleLarge" style={styles.cardTitle}>{invitation.chittiName}</Text><Text>Invited by {invitation.administratorName}</Text></View><Icon source="email-fast-outline" size={30} color={theme.colors.primary} /></View>
            <Text>{invitation.memberCount} payout months · {formatINR(invitation.contributionAmountPaise ?? invitation.monthlyAmountPaise)}/month{invitation.coOwnerShareBps ? ` · ${(invitation.coOwnerShareBps / 100).toFixed(2)}% shared slot` : ''} · {formatINR(invitation.monthlyAmountPaise * invitation.memberCount)} pot</Text>
            <Button mode="contained" icon="email-open-outline" contentStyle={styles.reportButton} onPress={() => router.push(`/invite?invitation=${invitation.id}`)}>Review and join</Button>
          </Card.Content>
        </Card>)}
      </View> : null}

      {upcoming ? (
        <Card mode="outlined">
          <Card.Content style={styles.rowBetween}>
            <View style={styles.grow}>
              <Text variant="labelLarge">NEXT PAYMENT</Text>
              <Text variant="titleLarge">{formatINR(upcoming.round.contributions.find((contribution) => contribution.memberId === currentUser.id)?.amountPaise ?? upcoming.item.monthlyAmountPaise)}</Text>
              <Text variant="bodyMedium">Due {formatDate(upcoming.round.dueDate)} · {upcoming.item.name}</Text>
            </View>
            <Button mode="contained-tonal" icon="bank-transfer" onPress={() => router.push(`/chitti/${upcoming.item.id}`)}>Pay / view</Button>
          </Card.Content>
        </Card>
      ) : null}

      <View style={styles.rowBetween}>
        <Text variant="headlineSmall" style={styles.sectionTitle}>Your chittis</Text>
        {currentUser.role === 'admin' ? <View style={styles.adminActions}>
          <Button icon="plus" textColor={brandColors.black} onPress={() => router.push('/chitti/new')}>Create new</Button>
          <Button icon="history" mode="outlined" textColor={brandColors.black} onPress={() => router.push('/chitti/import')}>Add existing</Button>
        </View> : null}
      </View>

      {active.length === 0 ? (
        <EmptyState icon="account-group-outline" title="No active chittis" message="Your private invitations and active chittis will appear here." />
      ) : active.map((chitti) => {
        const currentRound = chitti.rounds.find((round) => round.status === 'collecting' || round.status === 'ready_for_payout');
        const payoutNames = currentRound?.payoutShares?.map((share) => chitti.members.find((member) => member.id === share.recipientMemberId)?.name).filter(Boolean);
        const recipient = chitti.members.find((member) => member.id === currentRound?.recipientMemberId);
        const confirmed = currentRound?.confirmedCount ?? currentRound?.contributions.filter((item) => item.status === 'confirmed').length ?? 0;
        const completed = chitti.rounds.filter((round) => round.status === 'completed').length;
        return (
          <Card key={chitti.id} mode="elevated" onPress={() => router.push(`/chitti/${chitti.id}`)}>
            <Card.Content style={styles.cardContent}>
              <View style={styles.rowBetween}>
                <View style={styles.grow}><Text variant="titleLarge" style={styles.cardTitle}>{chitti.name}</Text><Text>{chitti.memberCount} members · {formatINR(chitti.monthlyAmountPaise)}/month</Text></View>
                <StatusPill status={chitti.status} />
              </View>
              {chitti.status === 'active' && currentRound ? (
                <>
                  <View style={styles.rowBetween}><Text>Current recipient</Text><Text variant="titleMedium">{payoutNames?.length ? payoutNames.join(' + ') : recipient?.name}</Text></View>
                  <View style={styles.progressTrack}><ProgressBar progress={confirmed / Math.max(1, currentRound.contributions.length)} color={theme.colors.primary} style={styles.progress} /></View>
                  <View style={styles.rowBetween}><Text>{confirmed} of {currentRound.contributions.length} payments confirmed</Text><Text>{chitti.memberCount - completed} months left</Text></View>
                </>
              ) : <Text variant="bodyMedium">{chitti.status === 'inviting'
                ? chitti.isImported ? 'Waiting for invited members to join. The saved payout order will activate automatically.' : 'Waiting for invited members to join.'
                : 'Everyone has joined. Schedule the payout-order reveal.'}</Text>}
            </Card.Content>
          </Card>
        );
      })}
      {currentUser.role === 'admin' ? <FAB icon="plus" label="New chitti" style={styles.fab} onPress={() => router.push('/chitti/new')} /> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  summaryGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  greeting: { textAlign: 'center', fontWeight: '700' },
  summary: { flexGrow: 1, minWidth: 210, borderRadius: 4, overflow: 'hidden' },
  summaryContent: { gap: 5, padding: 16 },
  amount: { fontWeight: '800', marginTop: 4 },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  grow: { flex: 1 },
  sectionTitle: { fontWeight: '700' },
  cardContent: { gap: 14 },
  cardTitle: { fontWeight: '700' },
  progress: { height: 9, borderRadius: 8 },
  progressTrack: { height: 9, width: '100%' },
  fab: { alignSelf: 'flex-end', marginTop: 8 },
  reportButton: { minHeight: 50 },
  invitationSection: { gap: 12 },
  adminActions: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap', justifyContent: 'flex-end' },
});

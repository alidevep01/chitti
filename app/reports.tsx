import { useQuery } from '@tanstack/react-query';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { ActivityIndicator, Avatar, Button, Card, Divider, ProgressBar, Searchbar, Text, useTheme } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { StatusPill } from '@/components/StatusPill';
import { useApp } from '@/data/AppProvider';
import { buildDemoReports } from '@/domain/reports';
import type { UserReliabilityReport } from '@/domain/types';
import { env } from '@/lib/env';
import { formatDate, formatINR, initials } from '@/lib/format';
import { supabase } from '@/lib/supabase';

export default function ReportsScreen() {
  const theme = useTheme();
  const { currentUser, chittis } = useApp();
  const [search, setSearch] = useState('');
  const reportQuery = useQuery({
    queryKey: ['reports', currentUser?.id],
    enabled: Boolean(currentUser),
    queryFn: async () => {
      if (!currentUser) return [];
      if (env.isDemo) return buildDemoReports(currentUser, chittis);
      const { data, error } = await supabase!.rpc('get_reports');
      if (error) throw error;
      return data as unknown as UserReliabilityReport[];
    },
  });
  const reports = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return reportQuery.data ?? [];
    return (reportQuery.data ?? []).filter((report) =>
      report.name.toLowerCase().includes(query)
      || report.email.toLowerCase().includes(query)
      || report.phone.toLowerCase().includes(query));
  }, [reportQuery.data, search]);

  if (!currentUser) return null;
  return (
    <Screen title={currentUser.role === 'admin' ? 'Member reports' : 'My report'} back>
      <Card mode="contained" style={{ backgroundColor: theme.colors.primaryContainer }}>
        <Card.Content style={styles.section}>
          <Text variant="headlineSmall" style={styles.heading}>Payment history and reliability</Text>
          <Text>The score is out of 10: on-time confirmed payments divided by all on-time, late, and currently missed due dates.</Text>
          <Text variant="bodySmall">A payment waiting for administrator confirmation is counted as missed only after its due date passes.</Text>
        </Card.Content>
      </Card>

      {currentUser.role === 'admin' ? <Searchbar placeholder="Search name, email, or phone" value={search} onChangeText={setSearch} /> : null}
      {reportQuery.isLoading ? <ActivityIndicator size="large" style={styles.loading} /> : null}
      {reportQuery.isError ? (
        <EmptyState icon="alert-circle-outline" title="Reports could not load" message={reportQuery.error.message} action="Try again" onAction={() => void reportQuery.refetch()} />
      ) : null}
      {!reportQuery.isLoading && !reportQuery.isError && reports.length === 0 ? (
        <EmptyState icon="file-chart-outline" title="No report history yet" message="Reports will appear after you join a chitti and monthly contributions are created." />
      ) : null}

      {reports.map((report) => {
        const hasScore = typeof report.reliabilityScore === 'number';
        const score = report.reliabilityScore ?? 0;
        return (
          <Card key={report.userId} mode="elevated">
            <Card.Content style={styles.section}>
              <View style={styles.personRow}>
                {report.avatarUri ? <Avatar.Image size={52} source={{ uri: report.avatarUri }} /> : <Avatar.Text size={52} label={initials(report.name)} />}
                <View style={styles.grow}>
                  <Text variant="titleLarge" style={styles.heading}>{report.name}{report.userId === currentUser.id ? ' · You' : ''}</Text>
                  {currentUser.role === 'admin' ? <Text>{report.email} · {report.phone || 'No phone'}</Text> : <Text>{report.chittiCount} chittis in your history</Text>}
                </View>
                <View style={styles.score}><Text variant="headlineMedium" style={styles.heading}>{hasScore ? score.toFixed(1) : '—'}</Text><Text variant="labelMedium">out of 10</Text></View>
              </View>
              <View style={styles.progressTrack}><ProgressBar progress={hasScore ? score / 10 : 0} style={styles.progress} color={hasScore && score < 6 ? theme.colors.error : theme.colors.primary} /></View>
              <View style={styles.metrics}>
                <Metric label="On time" value={report.onTimePayments} />
                <Metric label="Paid late" value={report.latePayments} />
                <Metric label="Missed now" value={report.missedDueDates} />
                <Metric label="Chittis" value={report.chittiCount} />
              </View>
              <View style={styles.amounts}><Text>Confirmed contributions: <Text style={styles.heading}>{formatINR(report.confirmedAmountPaise)}</Text></Text><Text>Currently overdue: <Text style={[styles.heading, report.overdueAmountPaise > 0 && { color: theme.colors.error }]}>{formatINR(report.overdueAmountPaise)}</Text></Text></View>

              <Divider />
              <Text variant="titleMedium" style={styles.heading}>Chitti history</Text>
              {report.chittis.length === 0 ? <Text>No chitti history yet.</Text> : report.chittis.map((history, index) => (
                <View key={history.chittiId}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.historyRow}>
                  <View style={styles.grow}>
                    <View style={styles.titleRow}><Text variant="titleMedium" style={styles.heading}>{history.name}</Text><StatusPill status={history.status} /></View>
                    <Text>{formatDate(history.startDate)} – {formatDate(history.endDate)}</Text>
                    <Text>{formatINR(history.monthlyAmountPaise)}/month · payout {history.payoutPosition ? `month ${history.payoutPosition}` : 'not assigned'}{history.payoutDate ? ` (${formatDate(history.payoutDate)})` : ''}</Text>
                    <Text>{history.onTimePayments} on time · {history.latePayments} late · {history.missedDueDates} missed now</Text>
                  </View>
                  <Button compact mode="outlined" onPress={() => router.push(`/chitti/${history.chittiId}`)}>Open</Button>
                </View></View>
              ))}
            </Card.Content>
          </Card>
        );
      })}
      {!reportQuery.isLoading ? <Button icon="refresh" onPress={() => void reportQuery.refetch()}>Refresh reports</Button> : null}
    </Screen>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return <View style={styles.metric}><Text variant="headlineSmall" style={styles.heading}>{value}</Text><Text variant="labelMedium">{label}</Text></View>;
}

const styles = StyleSheet.create({
  section: { gap: 14 },
  heading: { fontWeight: '700' },
  loading: { marginVertical: 40 },
  personRow: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' },
  grow: { flex: 1, minWidth: 180, gap: 3 },
  score: { alignItems: 'center', minWidth: 72 },
  progressTrack: { height: 10, width: '100%' },
  progress: { height: 10, borderRadius: 8 },
  metrics: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  metric: { minWidth: 105, flexGrow: 1, padding: 12, borderRadius: 12, backgroundColor: '#fff8f6' },
  amounts: { gap: 5 },
  historyRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' },
  titleRow: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' },
  divider: { marginVertical: 12 },
});

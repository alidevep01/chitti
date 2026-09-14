import { StyleSheet } from 'react-native';
import { Chip } from 'react-native-paper';

const labels: Record<string, string> = {
  draft: 'Draft', inviting: 'Inviting', ready: 'Ready to shuffle', shuffle_scheduled: 'Shuffle scheduled',
  awaiting_approval: 'Awaiting approval', active: 'Active', completed: 'Completed', cancelled: 'Cancelled',
  due: 'Due', submitted: 'Submitted', confirmed: 'Confirmed', rejected: 'Needs attention', overdue: 'Overdue',
};

export function StatusPill({ status }: { status: string }) {
  const icon = status === 'confirmed' || status === 'completed' || status === 'active' ? 'check-circle-outline'
    : status === 'rejected' || status === 'overdue' ? 'alert-circle-outline' : 'clock-outline';
  return <Chip compact icon={icon} style={styles.chip} textStyle={styles.text}>{labels[status] ?? status}</Chip>;
}

const styles = StyleSheet.create({ chip: { alignSelf: 'flex-start' }, text: { fontSize: 12 } });

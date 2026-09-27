import { StyleSheet, View } from 'react-native';
import { Chip, Icon, Tooltip, useTheme } from 'react-native-paper';

const labels: Record<string, string> = {
  accepted: 'Accepted', pending_invitation: 'Pending invitation',
  draft: 'Draft', inviting: 'Inviting', ready: 'Ready to shuffle', shuffle_scheduled: 'Shuffle scheduled',
  awaiting_approval: 'Awaiting approval', active: 'Active', completed: 'Completed', cancelled: 'Cancelled',
  due: 'Due', submitted: 'Submitted', confirmed: 'Confirmed', rejected: 'Needs attention', overdue: 'Overdue',
};

export function StatusPill({ status, iconOnly = false }: { status: string; iconOnly?: boolean }) {
  const theme = useTheme();
  const label = labels[status] ?? status;
  const icon = status === 'accepted' || status === 'confirmed' || status === 'completed' || status === 'active' ? 'check-circle-outline'
    : status === 'rejected' || status === 'overdue' ? 'alert-circle-outline' : 'clock-outline';
  if (iconOnly) return <Tooltip title={label}><View accessible accessibilityRole="image" accessibilityLabel={label} style={[styles.iconBadge, { backgroundColor: theme.colors.secondaryContainer }]}><Icon source={icon} size={22} color={theme.colors.onSecondaryContainer} /></View></Tooltip>;
  return <Chip compact icon={icon} style={styles.chip} textStyle={styles.text}>{labels[status] ?? status}</Chip>;
}

const styles = StyleSheet.create({ chip: { alignSelf: 'flex-start' }, text: { fontSize: 12 }, iconBadge: { width: 44, height: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center' } });

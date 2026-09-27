import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Divider, Icon, Snackbar, Text } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { useApp } from '@/data/AppProvider';
import { enableWebPush, getWebPushStatus, watchWebPushStatus } from '@/lib/push';
import { shouldShowPushSetup, type WebPushStatus } from '@/lib/push.types';

export default function NotificationsScreen() {
  const { notifications, markNotificationRead, markAllNotificationsRead, currentUser } = useApp();
  const userId = currentUser?.id;
  const [message, setMessage] = useState('');
  const [pushStatus, setPushStatus] = useState<WebPushStatus>('checking');
  const [enablingPush, setEnablingPush] = useState(false);
  useFocusEffect(useCallback(() => {
    // Cancel older status reads while the user is actively enabling notifications.
    if (enablingPush) return;
    let disposed = false;
    let latestRead = 0;
    const refresh = async () => {
      const read = ++latestRead;
      try {
        const status = await getWebPushStatus(userId);
        if (!disposed && read === latestRead) setPushStatus(status);
      } catch {
        if (!disposed && read === latestRead) setPushStatus('unknown');
      }
    };
    const stopWatching = watchWebPushStatus(() => void refresh());
    void refresh();
    return () => { disposed = true; stopWatching(); };
  }, [userId, enablingPush]));
  const enablePush = async () => {
    if (enablingPush) return;
    setEnablingPush(true);
    try {
      setMessage(await enableWebPush());
      setPushStatus('enabled');
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not enable notifications');
    } finally { setEnablingPush(false); }
  };
  const open = async (id: string, route?: string) => {
    await markNotificationRead(id);
    if (route) router.push(route as never);
  };

  return (
    <Screen title="Notifications" back action={notifications.some((item) => !item.read) ? <Button onPress={() => void markAllNotificationsRead()}>Mark all read</Button> : undefined}>
      {shouldShowPushSetup(pushStatus) ? <Card mode="contained" style={styles.pushCard}><Card.Content style={styles.pushContent}><Icon source="bell-ring-outline" size={30} color="#C79A33" /><View style={styles.grow}><Text variant="titleMedium">{pushStatus === 'blocked' ? 'Notifications are blocked' : pushStatus === 'needs-subscription' ? 'Finish notification setup' : 'Get important updates'}</Text><Text>{pushStatus === 'blocked' ? 'Allow notifications for Chitti in this browser’s site settings, then return here.' : pushStatus === 'needs-subscription' ? 'Permission is already allowed. Connect this device to receive private background alerts for your account.' : 'Enable private background alerts on this device. Notification text never includes payment details.'}</Text></View>{pushStatus !== 'blocked' ? <Button mode="contained-tonal" loading={enablingPush} disabled={enablingPush} onPress={() => void enablePush()}>{pushStatus === 'needs-subscription' ? 'Finish setup' : 'Enable'}</Button> : null}</Card.Content></Card> : null}
      {notifications.length === 0 ? <EmptyState icon="bell-outline" title="All caught up" message="Invitations, payment reminders, and payout updates will appear here." /> : (
        <Card mode="outlined"><Card.Content>{notifications.map((item, index) => <View key={item.id}>{index ? <Divider /> : null}<Card.Title title={item.title} subtitle={new Date(item.createdAt).toLocaleString('en-IN')} left={(props) => <Icon {...props} source={item.read ? 'bell-outline' : 'bell-badge-outline'} size={28} color={item.read ? '#9A7A35' : '#C79A33'} />} right={() => !item.read ? <View style={styles.dot} /> : null} /><Card.Content><Text>{item.message}</Text></Card.Content><Card.Actions><Button onPress={() => void open(item.id, item.route)}>{item.route ? 'Open' : 'Mark read'}</Button></Card.Actions></View>)}</Card.Content></Card>
      )}
      <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({ pushCard: { backgroundColor: '#F5EDDB' }, pushContent: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' }, grow: { flex: 1, minWidth: 220 }, dot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#C79A33', marginRight: 16 } });

import { router } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Divider, Icon, Snackbar, Text } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { useApp } from '@/data/AppProvider';
import { enableWebPush } from '@/lib/push';

export default function NotificationsScreen() {
  const { notifications, markNotificationRead, markAllNotificationsRead } = useApp();
  const [message, setMessage] = useState('');
  const enablePush = async () => {
    try { setMessage(await enableWebPush()); }
    catch (value) { setMessage(value instanceof Error ? value.message : 'Could not enable notifications'); }
  };
  const open = async (id: string, route?: string) => {
    await markNotificationRead(id);
    if (route) router.push(route as never);
  };

  return (
    <Screen title="Notifications" back action={notifications.some((item) => !item.read) ? <Button onPress={() => void markAllNotificationsRead()}>Mark all read</Button> : undefined}>
      <Card mode="contained" style={styles.pushCard}><Card.Content style={styles.pushContent}><Icon source="bell-ring-outline" size={30} color="#C79A33" /><View style={styles.grow}><Text variant="titleMedium">Get important updates</Text><Text>Enable private background alerts on this device. Notification text never includes payment details.</Text></View><Button mode="contained-tonal" onPress={() => void enablePush()}>Enable</Button></Card.Content></Card>
      {notifications.length === 0 ? <EmptyState icon="bell-outline" title="All caught up" message="Invitations, payment reminders, and payout updates will appear here." /> : (
        <Card mode="outlined"><Card.Content>{notifications.map((item, index) => <View key={item.id}>{index ? <Divider /> : null}<Card.Title title={item.title} subtitle={new Date(item.createdAt).toLocaleString('en-IN')} left={(props) => <Icon {...props} source={item.read ? 'bell-outline' : 'bell-badge-outline'} size={28} color={item.read ? '#9A7A35' : '#C79A33'} />} right={() => !item.read ? <View style={styles.dot} /> : null} /><Card.Content><Text>{item.message}</Text></Card.Content><Card.Actions><Button onPress={() => void open(item.id, item.route)}>{item.route ? 'Open' : 'Mark read'}</Button></Card.Actions></View>)}</Card.Content></Card>
      )}
      <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({ pushCard: { backgroundColor: '#F5EDDB' }, pushContent: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' }, grow: { flex: 1, minWidth: 220 }, dot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#C79A33', marginRight: 16 } });

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Icon, Snackbar, Text, useTheme } from 'react-native-paper';

import { Screen } from '@/components/Screen';
import { useApp } from '@/data/AppProvider';

export default function InviteScreen() {
  const theme = useTheme();
  const { token, invitation } = useLocalSearchParams<{ token?: string; invitation?: string }>();
  const { currentUser, signInGoogle, redeemInvitation } = useApp();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const accept = async () => {
    if (!token && !invitation) return setError('This invitation link is incomplete. Ask the administrator for a new one.');
    setBusy(true);
    try { const chittiId = await redeemInvitation(token, invitation); router.replace(`/chitti/${chittiId}`); }
    catch (value) {
      const message = value instanceof Error
        ? value.message
        : value && typeof value === 'object' && 'message' in value
          ? String(value.message)
          : 'Could not accept this invitation';
      setError(message);
    }
    finally { setBusy(false); }
  };

  return (
    <Screen title="Private invitation" back={Boolean(currentUser)}>
      <View style={styles.wrap}>
        <Card mode="elevated" style={styles.card}><Card.Content style={styles.content}>
          <View style={[styles.icon, { backgroundColor: theme.colors.primaryContainer }]}><Icon source="email-lock-outline" size={42} color={theme.colors.primary} /></View>
          <Text variant="headlineSmall" style={styles.center}>You’re invited to a chitti</Text>
          <Text variant="bodyLarge" style={styles.center}>This is a private, single-use invitation. Sign in with the exact Google email the administrator invited.</Text>
          {!currentUser ? <Button mode="contained" icon="google" contentStyle={styles.button} onPress={() => void signInGoogle(token ?? (invitation ? `invitation:${invitation}` : undefined))}>Continue with Google</Button> : <><View style={styles.account}><Text variant="labelLarge">SIGNED IN AS</Text><Text variant="titleMedium">{currentUser.email}</Text></View><Button mode="contained" icon="check" loading={busy} contentStyle={styles.button} onPress={() => void accept()}>Review and join</Button></>}
          <View style={styles.safety}><Icon source="shield-check-outline" size={20} /><Text variant="bodySmall">Joining does not move any money. Payment records begin only after everyone approves the payout order.</Text></View>
        </Card.Content></Card>
      </View>
      <Snackbar visible={Boolean(error)} onDismiss={() => setError('')}>{error}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 30 }, card: { width: '100%', maxWidth: 520 },
  content: { alignItems: 'stretch', gap: 18, padding: 16 }, icon: { width: 76, height: 76, borderRadius: 24, alignSelf: 'center', alignItems: 'center', justifyContent: 'center' },
  center: { textAlign: 'center' }, button: { minHeight: 54 }, account: { backgroundColor: '#e5ede6', padding: 15, borderRadius: 12, gap: 4, alignItems: 'center' },
  safety: { flexDirection: 'row', alignItems: 'center', gap: 9, backgroundColor: '#eef5e9', padding: 12, borderRadius: 12 },
});

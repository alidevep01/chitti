import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Icon, Snackbar, Text, useTheme } from 'react-native-paper';

import { useApp } from '@/data/AppProvider';

export default function SignInScreen() {
  const theme = useTheme();
  const { token } = useLocalSearchParams<{ token?: string }>();
  const { signInDemo, signInGoogle, demoMode } = useApp();
  const [error, setError] = useState('');
  const run = async (fn: () => Promise<void>) => {
    try { await fn(); router.replace(token ? `/invite?token=${encodeURIComponent(token)}` : '/dashboard'); }
    catch (value) { setError(value instanceof Error ? value.message : 'Could not sign in'); }
  };

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      <View style={styles.hero}>
        <View style={[styles.logo, { backgroundColor: theme.colors.primary }]}><Text style={styles.logoText}>ಚಿ</Text></View>
        <Text variant="displaySmall" style={styles.title}>Chitti</Text>
        <Text variant="titleMedium" style={styles.subtitle}>Save together. Plan with confidence.</Text>
      </View>
      <Card mode="elevated" style={styles.card}>
        <Card.Content style={styles.cardContent}>
          <Text variant="headlineSmall" style={styles.center}>Welcome</Text>
          <Text variant="bodyLarge" style={styles.center}>Use the Google account that received your private invitation.</Text>
          <Button icon="google" mode="contained" contentStyle={styles.button} onPress={() => void run(() => signInGoogle(token))}>
            Continue with Google
          </Button>
          {demoMode ? (
            <View style={styles.demoBox}>
              <Text variant="titleSmall">Explore without setup</Text>
              <Text variant="bodyMedium">This device stores sample data only. No money or messages are sent.</Text>
              <Button mode="outlined" contentStyle={styles.button} onPress={() => void run(() => signInDemo('admin'))}>Preview as administrator</Button>
              <Button mode="text" contentStyle={styles.button} onPress={() => void run(() => signInDemo('member'))}>Preview as member</Button>
            </View>
          ) : null}
          <View style={styles.safety}><Icon source="shield-check-outline" size={22} color={theme.colors.tertiary} /><Text variant="bodySmall" style={styles.safetyText}>Chitti records payments made outside the app. It never holds your money.</Text></View>
        </Card.Content>
      </Card>
      <Text variant="bodySmall" style={styles.footer}>Private family prototype · English</Text>
      <Snackbar visible={Boolean(error)} onDismiss={() => setError('')}>{error}</Snackbar>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 26 },
  hero: { alignItems: 'center', gap: 8 },
  logo: { width: 74, height: 74, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
  logoText: { color: '#fff', fontSize: 34, fontWeight: '800' },
  title: { fontWeight: '800', color: '#502018' },
  subtitle: { color: '#735b2e', textAlign: 'center' },
  card: { width: '100%', maxWidth: 460 },
  cardContent: { padding: 12, gap: 18 },
  center: { textAlign: 'center' },
  button: { minHeight: 50 },
  demoBox: { backgroundColor: '#fff4dc', borderRadius: 16, padding: 16, gap: 10 },
  safety: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  safetyText: { flex: 1, color: '#4d6546' },
  footer: { color: '#756b67' },
});

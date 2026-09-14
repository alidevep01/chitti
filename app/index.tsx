import { Redirect } from 'expo-router';
import { ActivityIndicator } from 'react-native-paper';
import { View } from 'react-native';

import { useApp } from '@/data/AppProvider';

export default function Index() {
  const { ready, currentUser } = useApp();
  if (!ready) return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator size="large" /></View>;
  return <Redirect href={currentUser ? (currentUser.phone.trim() ? '/dashboard' : '/profile') : '/sign-in'} />;
}

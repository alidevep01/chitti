import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { router, Stack, useSegments } from 'expo-router';
import { useEffect, useState } from 'react';
import { PaperProvider } from 'react-native-paper';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

import { PwaBootstrap } from '@/components/PwaBootstrap';
import { AppProvider, useApp } from '@/data/AppProvider';
import { theme } from '@/theme';

function NavigationGuard() {
  const { ready, currentUser } = useApp();
  const segments = useSegments();

  useEffect(() => {
    if (!ready) return;
    const route = segments[0];
    const isPublic = route === 'sign-in' || route === 'invite' || route === 'privacy';
    if (!currentUser && !isPublic) router.replace('/sign-in');
    if (currentUser && !currentUser.phone.trim() && route !== 'profile' && route !== 'invite') router.replace('/profile');
  }, [currentUser, ready, segments]);

  return null;
}

export default function RootLayout() {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <SafeAreaProvider>
      <QueryClientProvider client={queryClient}>
        <PaperProvider theme={theme}>
          <AppProvider>
            <NavigationGuard />
            <PwaBootstrap />
            <StatusBar style="dark" />
            <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: theme.colors.background } }} />
          </AppProvider>
        </PaperProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}

import type { ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Appbar, Badge, Text, useTheme } from 'react-native-paper';
import { router, type Href } from 'expo-router';

import { useApp } from '@/data/AppProvider';
import { UserAvatar } from '@/components/UserAvatar';

type Props = {
  title: string;
  children: ReactNode;
  back?: boolean;
  backHref?: Href;
  scroll?: boolean;
  action?: ReactNode;
};

export function Screen({ title, children, back = false, backHref, scroll = true, action }: Props) {
  const theme = useTheme();
  const { currentUser, notifications, demoMode } = useApp();
  const unread = notifications.filter((item) => !item.read).length;
  const content = <View style={styles.content}>{children}</View>;
  const goBack = () => {
    if (router.canGoBack()) router.back();
    else router.replace(backHref ?? (currentUser ? '/dashboard' : '/sign-in'));
  };

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        {back ? <Appbar.BackAction accessibilityLabel="Go back" onPress={goBack} /> : null}
        <Appbar.Content title={title} titleStyle={styles.title} />
        {action}
        {currentUser ? (
          <View>
            <Appbar.Action icon="bell-outline" accessibilityLabel={`${unread} unread notifications`} onPress={() => router.push('/notifications')} />
            {unread > 0 ? <Badge size={17} style={styles.badge}>{unread}</Badge> : null}
          </View>
        ) : null}
        {currentUser ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Open profile"
            hitSlop={6}
            onPress={() => router.push('/profile')}
            style={({ pressed }) => [styles.avatarButton, pressed && styles.avatarPressed]}
          >
            <UserAvatar name={currentUser.name} uri={currentUser.avatarUri} size={36} style={styles.avatar} />
          </Pressable>
        ) : null}
      </Appbar.Header>
      {demoMode && currentUser ? (
        <View style={styles.demoBanner}><Text variant="labelMedium">Demo mode · Sample data only</Text></View>
      ) : null}
      {scroll ? <ScrollView contentContainerStyle={styles.scroll}>{content}</ScrollView> : content}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { width: '100%', maxWidth: 960, alignSelf: 'center', padding: 20, gap: 16 },
  scroll: { paddingBottom: 48 },
  title: { fontWeight: '700' },
  badge: { position: 'absolute', right: 3, top: 5 },
  avatarButton: { width: 48, height: 48, marginRight: 8, alignItems: 'center', justifyContent: 'center', borderRadius: 24 },
  avatarPressed: { opacity: 0.65 },
  avatar: { backgroundColor: '#e5ede6' },
  demoBanner: { backgroundColor: '#e5ede6', paddingHorizontal: 20, paddingVertical: 7, alignItems: 'center' },
});

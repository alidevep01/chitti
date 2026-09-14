import { StyleSheet, View } from 'react-native';
import { Button, Icon, Text } from 'react-native-paper';

export function EmptyState({ icon, title, message, action, onAction }: { icon: string; title: string; message: string; action?: string; onAction?: () => void }) {
  return (
    <View style={styles.root}>
      <Icon source={icon} size={44} color="#9b3b2c" />
      <Text variant="titleLarge">{title}</Text>
      <Text variant="bodyLarge" style={styles.message}>{message}</Text>
      {action && onAction ? <Button mode="contained" onPress={onAction}>{action}</Button> : null}
    </View>
  );
}

const styles = StyleSheet.create({ root: { alignItems: 'center', padding: 32, gap: 12 }, message: { textAlign: 'center', color: '#655d5a' } });

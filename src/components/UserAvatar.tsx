import { useState } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';
import { Avatar } from 'react-native-paper';

import { initials } from '@/lib/format';

type Props = {
  name: string;
  uri?: string | null;
  size: number;
  style?: StyleProp<ViewStyle>;
};

export function UserAvatar({ name, uri, size, style }: Props) {
  const [failedUri, setFailedUri] = useState<string | null>(null);

  const label = initials(name) || '?';
  const showImage = Boolean(uri) && failedUri !== uri;
  const accessibilityLabel = showImage
    ? `${name} profile picture`
    : `${name} initials ${label}`;

  return showImage
    ? <Avatar.Image accessibilityLabel={accessibilityLabel} size={size} source={{ uri: uri! }} onError={() => setFailedUri(uri ?? null)} />
    : <Avatar.Text accessibilityLabel={accessibilityLabel} size={size} label={label} style={style} />;
}

import * as ImagePicker from 'expo-image-picker';
import { router } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Divider, Snackbar, Text, TextInput } from 'react-native-paper';

import { Screen } from '@/components/Screen';
import { UserAvatar } from '@/components/UserAvatar';
import { useApp } from '@/data/AppProvider';
import { demoUsers } from '@/data/demo';
import { exportChittiData } from '@/lib/exportData';

export default function ProfileScreen() {
  const { currentUser, chittis, updateProfile, signOut, demoMode, switchDemoUser } = useApp();
  if (!currentUser) return null;
  return <ProfileForm key={currentUser.id} currentUser={currentUser} chittis={chittis} updateProfile={updateProfile} signOut={signOut} demoMode={demoMode} switchDemoUser={switchDemoUser} />;
}

function ProfileForm({ currentUser, chittis, updateProfile, signOut, demoMode, switchDemoUser }: {
  currentUser: NonNullable<ReturnType<typeof useApp>['currentUser']>;
  chittis: ReturnType<typeof useApp>['chittis'];
  updateProfile: ReturnType<typeof useApp>['updateProfile'];
  signOut: ReturnType<typeof useApp>['signOut'];
  demoMode: boolean;
  switchDemoUser: ReturnType<typeof useApp>['switchDemoUser'];
}) {
  const [name, setName] = useState(currentUser?.name ?? '');
  const [phone, setPhone] = useState(currentUser?.phone ?? '');
  const [avatarUri, setAvatarUri] = useState(currentUser?.avatarUri);
  const [message, setMessage] = useState('');

  const choosePhoto = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.75 });
    if (!result.canceled) {
      const asset = result.assets[0];
      if (asset?.fileSize && asset.fileSize > 5 * 1024 * 1024) return setMessage('Choose an image smaller than 5 MB.');
      setAvatarUri(asset?.uri);
    }
  };
  const save = async () => {
    if (name.trim().length < 2 || phone.trim().length < 8) return setMessage('Enter a valid name and phone number.');
    await updateProfile({ name: name.trim(), phone: phone.trim(), avatarUri });
    setMessage('Profile updated.');
  };
  const logout = async () => { await signOut(); router.replace('/sign-in'); };

  return (
    <Screen title="Profile" back>
      <Card mode="elevated"><Card.Content style={styles.content}>
        <View style={styles.avatarWrap}><UserAvatar name={name} uri={avatarUri} size={94} /><Button icon="camera" onPress={() => void choosePhoto()}>Choose photo</Button></View>
        <TextInput mode="outlined" label="Full name" value={name} onChangeText={setName} />
        <TextInput mode="outlined" label="Phone number" value={phone} onChangeText={setPhone} keyboardType="phone-pad" />
        <TextInput mode="outlined" label="Google email" value={currentUser.email} disabled />
        <Text variant="bodySmall">Your email and phone number are visible only to the administrator.</Text>
        <Button mode="contained" contentStyle={styles.button} onPress={() => void save()}>Save profile</Button>
      </Card.Content></Card>

      {demoMode ? <Card mode="contained" style={styles.demo}><Card.Content style={styles.content}><Text variant="titleLarge">Preview another member</Text><Text>Use these accounts to test member-only screens and approvals.</Text>{demoUsers.map((user, index) => <View key={user.id}>{index ? <Divider /> : null}<View style={styles.userRow}><View><Text variant="titleMedium">{user.name}</Text><Text>{user.role === 'admin' ? 'Administrator' : 'Member'}</Text></View><Button disabled={user.id === currentUser.id} onPress={() => { switchDemoUser(user.id); setMessage(`Now previewing as ${user.name}`); }}>Preview</Button></View></View>)}</Card.Content></Card> : null}

      <Card mode="outlined"><Card.Content style={styles.content}><Text variant="titleMedium">Account and data</Text><Button mode="outlined" icon="file-chart-outline" contentStyle={styles.button} onPress={() => router.push('/reports')}>{currentUser.role === 'admin' ? 'All member reports' : 'My payment report'}</Button>{currentUser.role === 'admin' ? <Button mode="outlined" icon="download" contentStyle={styles.button} onPress={() => void exportChittiData(chittis).then(setMessage).catch((error) => setMessage(error.message))}>Export private data</Button> : null}<Button mode="text" icon="shield-account-outline" onPress={() => router.push('/privacy')}>Privacy and safety</Button><Button mode="outlined" textColor="#3f5b49" icon="logout" contentStyle={styles.button} onPress={() => void logout()}>Sign out</Button></Card.Content></Card>
      <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({ content: { gap: 14 }, avatarWrap: { alignItems: 'center', gap: 6 }, button: { minHeight: 50 }, demo: { backgroundColor: '#e5ede6' }, userRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 8 } });

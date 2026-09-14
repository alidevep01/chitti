import { Card, Text } from 'react-native-paper';

import { Screen } from '@/components/Screen';

export default function PrivacyScreen() {
  return (
    <Screen title="Privacy and safety" back>
      <Card mode="elevated"><Card.Content style={{ gap: 12 }}>
        <Text variant="headlineSmall">Private by design</Text>
        <Text variant="bodyLarge">Chitti is an invitation-only prototype. Members see names, profile photos, group totals, their own contribution, and aggregate collection progress. Only the administrator sees contact details and individual payment references.</Text>
        <Text variant="titleMedium">Money</Text>
        <Text>Payments happen outside Chitti through a UPI app or cash. Chitti does not hold funds, access bank accounts, or automatically verify payments.</Text>
        <Text variant="titleMedium">Notifications</Text>
        <Text>Background notifications contain generic text. Details are visible only after opening the signed-in application. Notification permission is optional.</Text>
        <Text variant="titleMedium">Profile photos</Text>
        <Text>Profile photos are limited to 5 MB. Do not upload identity documents, bank screenshots, or payment receipts as an avatar.</Text>
        <Text variant="titleMedium">Before real use</Text>
        <Text>This prototype is not legal or financial advice. The administrator must complete applicable legal, privacy, registration, agreement, security, and retention reviews before recording real chitti activity.</Text>
      </Card.Content></Card>
    </Screen>
  );
}

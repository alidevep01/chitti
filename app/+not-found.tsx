import { router } from 'expo-router';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';

export default function NotFoundScreen() {
  return <Screen title="Page not found" back><EmptyState icon="map-marker-question-outline" title="This page is unavailable" message="The link may be incomplete, expired, or outside your account." action="Go home" onAction={() => router.replace('/')} /></Screen>;
}

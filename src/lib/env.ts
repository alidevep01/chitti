const url = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim();
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

export const env = {
  supabaseUrl: url,
  supabaseKey: key,
  appUrl: process.env.EXPO_PUBLIC_APP_URL?.trim() || 'http://localhost:8081',
  vapidPublicKey: process.env.EXPO_PUBLIC_VAPID_PUBLIC_KEY?.trim(),
  isDemo: !url || !key,
};

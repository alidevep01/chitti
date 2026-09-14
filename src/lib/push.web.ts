import { env } from './env';
import { supabase } from './supabase';

function base64ToBytes(value: string) {
  const padding = '='.repeat((4 - value.length % 4) % 4);
  const raw = atob((value + padding).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)));
}

export async function enableWebPush(): Promise<string> {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) throw new Error('This browser does not support background notifications.');
  if (!env.vapidPublicKey && !env.isDemo) throw new Error('Web Push is not configured yet.');
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Notification permission was not granted.');
  if (env.isDemo) {
    new Notification('Chitti notifications enabled', { body: 'This is a local demo notification.' });
    return 'Demo notifications are enabled on this device.';
  }
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: base64ToBytes(env.vapidPublicKey!) });
  const json = subscription.toJSON();
  const { error } = await supabase!.rpc('register_push_subscription', {
    p_endpoint: json.endpoint,
    p_p256dh: json.keys?.p256dh,
    p_auth: json.keys?.auth,
    p_user_agent: navigator.userAgent,
  });
  if (error) throw error;
  return 'Background notifications are enabled on this device.';
}

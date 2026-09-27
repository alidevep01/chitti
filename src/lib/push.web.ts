import { env } from './env';
import { supabase } from './supabase';
import type { WebPushStatus } from './push.types';

function supportsWebPush() {
  return typeof window !== 'undefined' && typeof navigator !== 'undefined'
    && 'Notification' in window && 'serviceWorker' in navigator && 'PushManager' in window;
}

export async function getWebPushStatus(userId?: string): Promise<WebPushStatus> {
  if (!supportsWebPush()) return 'unsupported';
  if (Notification.permission === 'denied') return 'blocked';
  if (Notification.permission !== 'granted') return 'prompt';
  if (env.isDemo) return 'enabled';
  if (!userId) return 'unknown';

  // Unlike serviceWorker.ready, this does not hang if no worker is registered yet.
  const registration = await navigator.serviceWorker.getRegistration('/');
  const subscription = await registration?.pushManager.getSubscription();
  if (!subscription || (subscription.expirationTime !== null && subscription.expirationTime <= Date.now())) return 'needs-subscription';

  // Permission alone is not enough: this device must be registered for the signed-in user.
  const { data, error } = await supabase!.from('push_subscriptions').select('id')
    .eq('user_id', userId).eq('endpoint', subscription.endpoint).maybeSingle();
  if (error) return 'unknown'; // An offline check must not nag an already-enabled user.
  return data ? 'enabled' : 'needs-subscription';
}

export function watchWebPushStatus(onChange: () => void): () => void {
  if (!supportsWebPush()) return () => {};
  let disposed = false;
  let permission: PermissionStatus | undefined;
  const onVisible = () => { if (document.visibilityState === 'visible') onChange(); };
  window.addEventListener('focus', onChange);
  document.addEventListener('visibilitychange', onVisible);
  navigator.serviceWorker.addEventListener('controllerchange', onChange);
  // Some browsers lack notification permission queries; focus/visibility still work there.
  if (navigator.permissions?.query) {
    void navigator.permissions.query({ name: 'notifications' }).then((result) => {
      if (disposed) return;
      permission = result;
      permission.addEventListener('change', onChange);
    }).catch(() => {});
  }
  return () => {
    disposed = true;
    window.removeEventListener('focus', onChange);
    document.removeEventListener('visibilitychange', onVisible);
    navigator.serviceWorker.removeEventListener('controllerchange', onChange);
    permission?.removeEventListener('change', onChange);
  };
}

function base64ToBytes(value: string) {
  const padding = '='.repeat((4 - value.length % 4) % 4);
  const raw = atob((value + padding).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)));
}

export async function enableWebPush(): Promise<string> {
  if (!supportsWebPush()) throw new Error('This browser does not support background notifications.');
  if (!env.vapidPublicKey && !env.isDemo) throw new Error('Web Push is not configured yet.');
  const permission = Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Notification permission was not granted.');
  if (env.isDemo) {
    new Notification('Chitti notifications enabled', { body: 'This is a local demo notification.' });
    return 'Demo notifications are enabled on this device.';
  }
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.getSubscription()
    ?? await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: base64ToBytes(env.vapidPublicKey!) });
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

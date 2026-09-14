import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET')!;
const vapidPublic = Deno.env.get('VAPID_PUBLIC_KEY')!;
const vapidPrivate = Deno.env.get('VAPID_PRIVATE_KEY')!;
const vapidSubject = Deno.env.get('VAPID_SUBJECT')!;

webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

Deno.serve(async (request) => {
  if (request.headers.get('x-chitti-webhook-secret') !== webhookSecret) return new Response('Unauthorized', { status: 401 });
  const body = await request.json();
  const notificationId = body.record?.id ?? body.notification_id;
  const { data: notification } = await supabase.from('notifications').select('id,user_id,route').eq('id', notificationId).single();
  if (!notification) return new Response('Notification not found', { status: 404 });
  const { data: subscriptions } = await supabase.from('push_subscriptions').select('*').eq('user_id', notification.user_id);
  const payload = JSON.stringify({ title: 'Chitti', body: 'You have a Chitti update', url: notification.route ?? '/notifications' });
  const results = await Promise.allSettled((subscriptions ?? []).map(async (subscription) => {
    try {
      await webpush.sendNotification({ endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } }, payload);
    } catch (error) {
      const statusCode = (error as { statusCode?: number }).statusCode;
      if (statusCode === 404 || statusCode === 410) await supabase.from('push_subscriptions').delete().eq('id', subscription.id);
      else throw error;
    }
  }));
  return Response.json({ attempted: results.length, failed: results.filter((result) => result.status === 'rejected').length });
});

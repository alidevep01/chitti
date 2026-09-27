import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableWebPush, getWebPushStatus, watchWebPushStatus } from './push.web';
import { shouldShowPushSetup } from './push.types';

const mocks = vi.hoisted(() => ({
  env: { isDemo: false, vapidPublicKey: 'AQID' },
  from: vi.fn(), select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn(), rpc: vi.fn(),
}));
vi.mock('./env', () => ({ env: mocks.env }));
vi.mock('./supabase', () => ({ supabase: mocks }));

function browser(permission: NotificationPermission = 'granted') {
  const subscription = { endpoint: 'https://push.example.test/device', expirationTime: null as number | null, toJSON: () => ({ endpoint: 'https://push.example.test/device', keys: { p256dh: 'public-key', auth: 'auth-key' } }) };
  const registration = { pushManager: { getSubscription: vi.fn().mockResolvedValue(subscription), subscribe: vi.fn().mockResolvedValue(subscription) } };
  const notification = { permission, requestPermission: vi.fn().mockResolvedValue('granted') };
  const permissionStatus = new EventTarget();
  const windowTarget = Object.assign(new EventTarget(), { Notification: notification, PushManager: {} });
  const documentTarget = Object.assign(new EventTarget(), { visibilityState: 'visible' });
  const serviceWorker = Object.assign(new EventTarget(), { getRegistration: vi.fn().mockResolvedValue(registration), ready: Promise.resolve(registration) });
  const permissions = { query: vi.fn().mockResolvedValue(permissionStatus) };
  vi.stubGlobal('window', windowTarget);
  vi.stubGlobal('document', documentTarget);
  vi.stubGlobal('Notification', notification);
  vi.stubGlobal('navigator', { serviceWorker, permissions, userAgent: 'Test browser' });
  return { subscription, registration, notification, permissionStatus, windowTarget, documentTarget, serviceWorker, permissions };
}

beforeEach(() => {
  vi.resetAllMocks();
  mocks.env.isDemo = false;
  mocks.env.vapidPublicKey = 'AQID';
  mocks.from.mockReturnValue(mocks);
  mocks.select.mockReturnValue(mocks);
  mocks.eq.mockReturnValue(mocks);
  mocks.maybeSingle.mockResolvedValue({ data: { id: 'registered' }, error: null });
  mocks.rpc.mockResolvedValue({ data: 'registered', error: null });
});
afterEach(() => vi.unstubAllGlobals());

describe('web push setup visibility', () => {
  it('hides the card for an enabled device, including after a fresh status read', async () => {
    const { notification } = browser();
    expect(await getWebPushStatus('user-1')).toBe('enabled');
    expect(shouldShowPushSetup(await getWebPushStatus('user-1'))).toBe(false);
    expect(mocks.eq).toHaveBeenCalledWith('user_id', 'user-1');
    expect(mocks.eq).toHaveBeenCalledWith('endpoint', 'https://push.example.test/device');
    expect(notification.requestPermission).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it('does not flash the prompt while checking or when offline', async () => {
    browser();
    mocks.maybeSingle.mockResolvedValue({ data: null, error: { message: 'Offline' } });
    expect(await getWebPushStatus('user-1')).toBe('unknown');
    expect(shouldShowPushSetup('checking')).toBe(false);
    expect(shouldShowPushSetup('unknown')).toBe(false);
  });
  it('shows setup only if permission or device registration is missing', async () => {
    const { notification, registration } = browser('default');
    expect(await getWebPushStatus('user-1')).toBe('prompt');
    notification.permission = 'granted';
    registration.pushManager.getSubscription.mockResolvedValue(null);
    expect(await getWebPushStatus('user-1')).toBe('needs-subscription');
    expect(shouldShowPushSetup('prompt')).toBe(true);
    expect(shouldShowPushSetup('needs-subscription')).toBe(true);
  });
  it('detects a missing worker without waiting forever for serviceWorker.ready', async () => {
    const { serviceWorker } = browser();
    serviceWorker.getRegistration.mockResolvedValue(undefined);
    serviceWorker.ready = new Promise(() => {});
    expect(await getWebPushStatus('user-1')).toBe('needs-subscription');
  });
  it('checks the signed-in account rather than treating permission alone as enabled', async () => {
    browser();
    expect(await getWebPushStatus()).toBe('unknown');
    mocks.maybeSingle.mockResolvedValue({ data: null, error: null });
    expect(await getWebPushStatus('other-user')).toBe('needs-subscription');
    expect(mocks.eq).toHaveBeenCalledWith('user_id', 'other-user');
  });
  it('recognizes expired subscriptions and revoked permission', async () => {
    const { subscription, notification } = browser();
    subscription.expirationTime = Date.now() - 1;
    expect(await getWebPushStatus('user-1')).toBe('needs-subscription');
    notification.permission = 'denied';
    expect(await getWebPushStatus('user-1')).toBe('blocked');
    expect(shouldShowPushSetup('blocked')).toBe(true);
  });
  it('hides unsupported/native-style environments safely', async () => {
    vi.stubGlobal('window', undefined);
    expect(await getWebPushStatus('user-1')).toBe('unsupported');
    expect(shouldShowPushSetup('unsupported')).toBe(false);
    expect(watchWebPushStatus(vi.fn())).toBeTypeOf('function');
  });
  it('treats granted demo permission as enabled without a production registration', async () => {
    browser();
    mocks.env.isDemo = true;
    expect(await getWebPushStatus('demo-user')).toBe('enabled');
    expect(mocks.from).not.toHaveBeenCalled();
  });
});

describe('enabling and watching push', () => {
  it('reuses an existing device subscription without asking permission again', async () => {
    const { notification, registration } = browser();
    expect(await enableWebPush()).toContain('enabled on this device');
    expect(notification.requestPermission).not.toHaveBeenCalled();
    expect(registration.pushManager.subscribe).not.toHaveBeenCalled();
    expect(mocks.rpc).toHaveBeenCalledWith('register_push_subscription', expect.objectContaining({ p_endpoint: 'https://push.example.test/device' }));
  });
  it('creates and saves a missing subscription after permission is granted', async () => {
    const { notification, registration } = browser('default');
    registration.pushManager.getSubscription.mockResolvedValue(null);
    await enableWebPush();
    expect(notification.requestPermission).toHaveBeenCalledOnce();
    expect(registration.pushManager.subscribe).toHaveBeenCalledOnce();
    expect(mocks.rpc).toHaveBeenCalledOnce();
  });
  it('never reports success when server registration fails', async () => {
    browser();
    mocks.rpc.mockResolvedValue({ error: new Error('Registration failed') });
    await expect(enableWebPush()).rejects.toThrow('Registration failed');
  });
  it('refreshes on return/settings changes and removes listeners on cleanup', async () => {
    const { windowTarget, documentTarget, permissionStatus, serviceWorker } = browser();
    const onChange = vi.fn();
    const cleanup = watchWebPushStatus(onChange);
    await Promise.resolve();
    windowTarget.dispatchEvent(new Event('focus'));
    documentTarget.dispatchEvent(new Event('visibilitychange'));
    permissionStatus.dispatchEvent(new Event('change'));
    serviceWorker.dispatchEvent(new Event('controllerchange'));
    expect(onChange).toHaveBeenCalledTimes(4);
    cleanup();
    windowTarget.dispatchEvent(new Event('focus'));
    documentTarget.dispatchEvent(new Event('visibilitychange'));
    permissionStatus.dispatchEvent(new Event('change'));
    serviceWorker.dispatchEvent(new Event('controllerchange'));
    expect(onChange).toHaveBeenCalledTimes(4);
  });
  it('does not attach late permission listeners after the screen is closed', async () => {
    const { permissionStatus } = browser();
    const onChange = vi.fn();
    watchWebPushStatus(onChange)();
    await Promise.resolve();
    permissionStatus.dispatchEvent(new Event('change'));
    expect(onChange).not.toHaveBeenCalled();
  });
  it('still refreshes on focus if notification permission queries are unsupported', async () => {
    const { windowTarget, permissions } = browser();
    permissions.query.mockRejectedValue(new Error('Unsupported permission name'));
    const onChange = vi.fn();
    const cleanup = watchWebPushStatus(onChange);
    await Promise.resolve();
    windowTarget.dispatchEvent(new Event('focus'));
    expect(onChange).toHaveBeenCalledOnce();
    cleanup();
  });
});

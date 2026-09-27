export type WebPushStatus = 'checking' | 'enabled' | 'prompt' | 'needs-subscription' | 'blocked' | 'unsupported' | 'unknown';

export function shouldShowPushSetup(status: WebPushStatus): boolean {
  return status === 'prompt' || status === 'needs-subscription' || status === 'blocked';
}

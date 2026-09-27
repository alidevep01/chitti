import type { WebPushStatus } from './push.types';

export async function getWebPushStatus(_userId?: string): Promise<WebPushStatus> {
  return 'unsupported';
}

export function watchWebPushStatus(_onChange: () => void): () => void {
  return () => {};
}

export async function enableWebPush(): Promise<string> {
  throw new Error('Background Web Push is available from the installed web app.');
}

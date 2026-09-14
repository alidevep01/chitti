import type { Chitti } from '@/domain/types';

export async function exportChittiData(chittis: Chitti[]): Promise<string> {
  const payload = JSON.stringify({ exportedAt: new Date().toISOString(), schemaVersion: 1, chittis }, null, 2);
  const blob = new Blob([payload], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `chitti-export-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  URL.revokeObjectURL(url);
  return 'Private data export downloaded.';
}

import type { Chitti } from '@/domain/types';

export async function exportChittiData(chittis: Chitti[]): Promise<string> {
  throw new Error('Data export is currently available from the web app.');
}

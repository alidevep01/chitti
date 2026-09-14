import { useEffect, useState } from 'react';

import { useApp } from '@/data/AppProvider';
import { env } from '@/lib/env';
import { supabase } from '@/lib/supabase';

export function useChittiPresence(chittiId: string) {
  const { currentUser } = useApp();
  const [count, setCount] = useState(env.isDemo ? 1 : 0);

  useEffect(() => {
    if (env.isDemo || !currentUser) return;
    const channel = supabase!.channel(`chitti:${chittiId}:presence`, {
      config: { private: true, presence: { key: currentUser.id } },
    });
    channel
      .on('presence', { event: 'sync' }, () => setCount(Object.keys(channel.presenceState()).length))
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') await channel.track({ name: currentUser.name, online_at: new Date().toISOString() });
      });
    return () => { void supabase!.removeChannel(channel); };
  }, [chittiId, currentUser]);

  return count;
}

import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import React, { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { Platform } from 'react-native';

import { assignPayoutPositions, buildRounds, refreshRound } from '@/domain/rules';
import type {
  AppNotification,
  Chitti,
  CreateChittiInput,
  InviteDraft,
  PaymentMethod,
  PaymentProofUpload,
  PendingInvitation,
  SavedMemberContact,
  UserProfile,
} from '@/domain/types';
import { env } from '@/lib/env';
import { addMonthsClamped } from '@/lib/format';
import { supabase } from '@/lib/supabase';
import { demoChittis, demoNotifications, demoUsers } from './demo';

WebBrowser.maybeCompleteAuthSession();

type AppContextValue = {
  ready: boolean;
  demoMode: boolean;
  currentUser: UserProfile | null;
  chittis: Chitti[];
  notifications: AppNotification[];
  pendingInvitations: PendingInvitation[];
  inviteLinks: Record<string, string>;
  savedContacts: SavedMemberContact[];
  signInDemo: (role: 'admin' | 'member') => Promise<void>;
  signInGoogle: (inviteToken?: string) => Promise<void>;
  signOut: () => Promise<void>;
  switchDemoUser: (id: string) => void;
  createChitti: (input: CreateChittiInput) => Promise<string>;
  redeemInvitation: (token?: string, invitationId?: string) => Promise<string>;
  regenerateInvitation: (invitationId: string) => Promise<string>;
  updateInvitation: (chittiId: string, invitationId: string, member: InviteDraft) => Promise<string>;
  addMemberInvitation: (chittiId: string, member: InviteDraft) => Promise<{ invitationId: string; token: string; lateJoin: boolean; shuffleReset: boolean }>;
  swapPayoutMonths: (chittiId: string, firstMemberId: string, secondMemberId: string) => Promise<void>;
  scheduleShuffle: (chittiId: string) => Promise<void>;
  runShuffle: (chittiId: string) => Promise<void>;
  voteShuffle: (chittiId: string, accepted: boolean, reason?: string) => Promise<void>;
  simulateApprovals: (chittiId: string) => Promise<void>;
  submitContribution: (chittiId: string, roundId: string, method: PaymentMethod, reference?: string, proof?: PaymentProofUpload) => Promise<void>;
  getPaymentProofUrl: (path: string) => Promise<string>;
  reviewContribution: (chittiId: string, roundId: string, contributionId: string, accepted: boolean) => Promise<void>;
  confirmPayout: (chittiId: string, roundId: string) => Promise<void>;
  confirmPayoutAdjustment: (chittiId: string, roundId: string, adjustmentId: string) => Promise<void>;
  markNotificationRead: (id: string) => Promise<void>;
  markAllNotificationsRead: () => Promise<void>;
  updateProfile: (changes: Pick<UserProfile, 'name' | 'phone' | 'avatarUri'>) => Promise<void>;
  reload: () => Promise<void>;
};

const AppContext = createContext<AppContextValue | undefined>(undefined);
const STORE_KEY = 'chitti-demo-state-v1';

type PersistedState = {
  userId: string | null;
  users: UserProfile[];
  chittis: Chitti[];
  notifications: AppNotification[];
  pendingInvitations: PendingInvitation[];
};

function initialState(): PersistedState {
  return {
    userId: null,
    users: demoUsers,
    chittis: demoChittis,
    notifications: demoNotifications,
    pendingInvitations: [],
  };
}

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [state, setState] = useState<PersistedState>(initialState);
  const [inviteLinks, setInviteLinks] = useState<Record<string, string>>({});
  const [savedContacts, setSavedContacts] = useState<SavedMemberContact[]>([]);

  const persist = useCallback(async (next: PersistedState) => {
    setState(next);
    if (env.isDemo) await AsyncStorage.setItem(STORE_KEY, JSON.stringify(next));
  }, []);

  const reload = useCallback(async () => {
    if (env.isDemo) return;
    const { data, error } = await supabase!.rpc('get_app_snapshot');
    if (error) throw error;
    const snapshot = data as PersistedState;
    if (snapshot.users[0]?.role === 'admin') {
      const { data: contacts, error: contactsError } = await supabase!.rpc('get_admin_contacts');
      if (contactsError) throw contactsError;
      setSavedContacts(contacts as unknown as SavedMemberContact[]);
    } else {
      setSavedContacts([]);
    }
    setState(snapshot);
  }, []);

  useEffect(() => {
    async function bootstrap() {
      if (env.isDemo) {
        const stored = await AsyncStorage.getItem(STORE_KEY);
        if (stored) {
          try { setState(JSON.parse(stored) as PersistedState); } catch { setState(initialState()); }
        }
      } else {
        const { data } = await supabase!.auth.getSession();
        if (data.session) await reload();
        supabase!.auth.onAuthStateChange((_event, session) => {
          if (session) void reload();
          else setState((current) => ({ ...current, userId: null }));
        });
      }
      setReady(true);
    }
    void bootstrap();
  }, [reload]);

  useEffect(() => {
    if (env.isDemo || !state.userId) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const refreshSoon = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => void reload(), 150);
    };
    const channel = supabase!
      .channel(`private-app-updates:${state.userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications', filter: `user_id=eq.${state.userId}` }, refreshSoon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'shuffle_runs' }, refreshSoon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'shuffle_approvals' }, refreshSoon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rounds' }, refreshSoon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contributions' }, refreshSoon)
      .subscribe();
    return () => {
      if (timer) clearTimeout(timer);
      void supabase!.removeChannel(channel);
    };
  }, [reload, state.userId]);

  const remoteOrLocal = useCallback(async (
    rpcName: string,
    args: Record<string, unknown>,
    localUpdate: (current: PersistedState) => PersistedState,
  ) => {
    if (!env.isDemo) {
      const { error } = await supabase!.rpc(rpcName, args);
      if (error) throw error;
      await reload();
      return;
    }
    await persist(localUpdate(state));
  }, [persist, reload, state]);

  const signInDemo = async (role: 'admin' | 'member') => {
    const user = state.users.find((item) => item.role === role)!;
    await persist({ ...state, userId: user.id });
  };

  const signInGoogle = async (inviteToken?: string) => {
    if (env.isDemo) return signInDemo('admin');
    const inviteRoute = inviteToken?.startsWith('invitation:')
      ? `/invite?invitation=${encodeURIComponent(inviteToken.slice('invitation:'.length))}`
      : inviteToken ? `/invite?token=${encodeURIComponent(inviteToken)}` : '/dashboard';
    const redirectTo = Platform.OS === 'web'
      ? `${env.appUrl}${inviteRoute}`
      : Linking.createURL(inviteRoute.replace(/^\//, ''));
    const { error } = await supabase!.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } });
    if (error) throw error;
  };

  const signOut = async () => {
    if (!env.isDemo) await supabase!.auth.signOut();
    await persist({ ...state, userId: null });
  };

  const switchDemoUser = (id: string) => void persist({ ...state, userId: id });

  const createChitti = async (input: CreateChittiInput) => {
    let createdId = '';
    if (!env.isDemo) {
      const { data, error } = await supabase!.rpc('create_chitti', { input });
      if (error) throw error;
      const result = data as { chitti_id: string; invitations: { id: string; token: string }[] };
      setInviteLinks((current) => ({ ...current, ...Object.fromEntries(result.invitations.map((invite) => [invite.id, invite.token])) }));
      await reload();
      return String(result.chitti_id);
    }
    const admin = state.users.find((user) => user.id === state.userId && user.role === 'admin');
    if (!admin) throw new Error('Only the administrator can create a chitti');
    createdId = `${input.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}-${Date.now()}`;
    const chitti: Chitti = {
      id: createdId,
      name: input.name,
      description: input.description,
      monthlyAmountPaise: input.monthlyAmountPaise,
      memberCount: input.memberCount,
      startDate: input.startDate,
      firstDueDate: input.firstDueDate,
      endDate: addMonthsClamped(input.firstDueDate, input.memberCount - 1),
      dueDay: input.dueDay,
      upiId: input.upiId,
      payeeName: input.payeeName,
      status: 'ready',
      members: [
        { ...admin, joined: true, isAdmin: true, approval: 'pending' },
        ...input.invites.map((invite, index) => ({
          id: state.users.find((user) => user.email.toLowerCase() === invite.email.toLowerCase())?.id ?? `invite-${Date.now()}-${index}`,
          ...invite,
          joined: true,
          approval: 'pending' as const,
        })),
      ],
      rounds: [],
      createdAt: new Date().toISOString(),
    };
    await persist({
      ...state,
      chittis: [chitti, ...state.chittis],
      notifications: [{
        id: `notification-${Date.now()}`,
        userId: admin.id,
        title: `${chitti.name} created`,
        message: 'All demo invitees are marked joined. Schedule the shuffle when ready.',
        route: `/chitti/${createdId}`,
        read: false,
        createdAt: new Date().toISOString(),
      }, ...state.notifications],
    });
    return createdId;
  };

  const redeemInvitation = async (token?: string, invitationId?: string) => {
    if (!state.userId) throw new Error('Sign in before accepting an invitation');
    if (!env.isDemo) {
      const { data, error } = await supabase!.rpc('redeem_invitation', { p_token: token || null, p_invitation_id: invitationId || null });
      if (error) throw error;
      await reload();
      return String(data);
    }
    const parts = (token ?? '').split('-');
    const matching = state.chittis.find((item) => token?.includes(item.id));
    if (matching) return matching.id;
    return state.chittis[0]?.id ?? parts[1] ?? '';
  };

  const regenerateInvitation = async (invitationId: string) => {
    if (env.isDemo) {
      const token = `demo-${crypto.randomUUID()}`;
      setInviteLinks((current) => ({ ...current, [invitationId]: token }));
      return token;
    }
    const { data, error } = await supabase!.rpc('regenerate_invitation', { p_invitation_id: invitationId });
    if (error) throw error;
    const token = String(data);
    setInviteLinks((current) => ({ ...current, [invitationId]: token }));
    return token;
  };

  const addMemberInvitation = async (chittiId: string, member: InviteDraft) => {
    if (!env.isDemo) {
      const { data, error } = await supabase!.rpc('add_chitti_member_invitation', {
        p_chitti_id: chittiId,
        p_name: member.name,
        p_email: member.email,
        p_phone: member.phone,
      });
      if (error) throw error;
      const result = data as { invitation_id: string; token: string; late_join: boolean; shuffle_reset: boolean };
      setInviteLinks((current) => ({ ...current, [result.invitation_id]: result.token }));
      await reload();
      return { invitationId: result.invitation_id, token: result.token, lateJoin: result.late_join, shuffleReset: result.shuffle_reset };
    }
    const invitationId = `invite-${crypto.randomUUID()}`;
    const token = `demo-${crypto.randomUUID()}`;
    const previousStatus = state.chittis.find((item) => item.id === chittiId)?.status;
    const shuffleReset = previousStatus === 'shuffle_scheduled' || previousStatus === 'awaiting_approval';
    setInviteLinks((current) => ({ ...current, [invitationId]: token }));
    await persist(updateChitti(state, chittiId, (chitti) => ({
      ...chitti,
      memberCount: chitti.status === 'active' ? chitti.memberCount : chitti.memberCount + 1,
      status: chitti.status === 'active' ? 'active' : 'inviting',
      shuffleScheduledAt: shuffleReset ? undefined : chitti.shuffleScheduledAt,
      resultHash: shuffleReset ? undefined : chitti.resultHash,
      members: shuffleReset ? chitti.members.map((existing) => ({
        ...existing,
        payoutPosition: existing.isAdmin ? 1 : undefined,
        approval: 'pending' as const,
      })) : chitti.members,
      invitations: [...(chitti.invitations ?? []), { id: invitationId, ...member, status: 'pending', lateJoin: chitti.status === 'active' }],
    })));
    return {
      invitationId,
      token,
      lateJoin: previousStatus === 'active',
      shuffleReset,
    };
  };

  const updateInvitation = async (chittiId: string, invitationId: string, member: InviteDraft) => {
    if (!env.isDemo) {
      const { data, error } = await supabase!.rpc('update_invitation', {
        p_invitation_id: invitationId,
        p_name: member.name,
        p_email: member.email,
        p_phone: member.phone,
      });
      if (error) throw error;
      const result = data as { invitation_id: string; token: string };
      setInviteLinks((current) => ({ ...current, [result.invitation_id]: result.token }));
      await reload();
      return result.token;
    }
    const token = `demo-${crypto.randomUUID()}`;
    setInviteLinks((current) => ({ ...current, [invitationId]: token }));
    await persist(updateChitti(state, chittiId, (chitti) => ({
      ...chitti,
      invitations: (chitti.invitations ?? []).map((invitation) => invitation.id === invitationId
        ? { ...invitation, ...member }
        : invitation),
    })));
    return token;
  };

  const updateChitti = (current: PersistedState, id: string, updater: (value: Chitti) => Chitti) => ({
    ...current,
    chittis: current.chittis.map((chitti) => chitti.id === id ? updater(chitti) : chitti),
  });

  const scheduleShuffle = (chittiId: string) => remoteOrLocal('schedule_shuffle', { p_chitti_id: chittiId, p_starts_at: new Date().toISOString() },
    (current) => updateChitti(current, chittiId, (chitti) => ({ ...chitti, status: 'shuffle_scheduled', shuffleScheduledAt: new Date().toISOString() })));

  const runShuffle = (chittiId: string) => remoteOrLocal('run_shuffle', { p_chitti_id: chittiId, p_idempotency_key: crypto.randomUUID() },
    (current) => updateChitti(current, chittiId, (chitti) => ({
      ...chitti,
      status: 'awaiting_approval',
      members: assignPayoutPositions(chitti.members),
      resultHash: crypto.randomUUID().replace(/-/g, '').slice(0, 12),
    })));

  const voteShuffle = (chittiId: string, accepted: boolean, reason?: string) => remoteOrLocal('respond_to_shuffle', { p_chitti_id: chittiId, p_accepted: accepted, p_reason: reason ?? null },
    (current) => updateChitti(current, chittiId, (chitti) => {
      const members = chitti.members.map((member) => member.id === current.userId ? {
        ...member,
        approval: accepted ? 'accepted' as const : 'rejected' as const,
        approvalReason: accepted ? undefined : reason,
      } : member);
      if (!accepted) return { ...chitti, members, status: 'ready', resultHash: undefined };
      const allAccepted = members.every((member) => member.approval === 'accepted');
      return allAccepted ? { ...chitti, members, status: 'active', rounds: buildRounds(members, chitti.firstDueDate, chitti.startDate) } : { ...chitti, members };
    }));

  const simulateApprovals = (chittiId: string) => remoteOrLocal('respond_to_shuffle_demo', { p_chitti_id: chittiId },
    (current) => updateChitti(current, chittiId, (chitti) => {
      const members = chitti.members.map((member) => ({ ...member, approval: 'accepted' as const }));
      return { ...chitti, status: 'active', members, rounds: buildRounds(members, chitti.firstDueDate, chitti.startDate) };
    }));

  const submitContribution = async (chittiId: string, roundId: string, method: PaymentMethod, reference?: string, proof?: PaymentProofUpload) => {
    if (!env.isDemo) {
      const contribution = state.chittis.find((item) => item.id === chittiId)?.rounds
        .find((round) => round.id === roundId)?.contributions.find((item) => item.memberId === state.userId);
      if (!contribution) throw new Error('Your contribution record is unavailable');
      let proofPath: string | null = null;
      if (proof) {
        const response = await fetch(proof.uri);
        const bytes = await response.arrayBuffer();
        if (bytes.byteLength > 5 * 1024 * 1024) throw new Error('Choose a payment photo smaller than 5 MB.');
        const requestedMime = proof.mimeType || response.headers.get('content-type') || '';
        const extensionFromName = proof.fileName?.split('.').pop()?.toLowerCase();
        const mime = requestedMime === 'image/png' || extensionFromName === 'png'
          ? 'image/png'
          : requestedMime === 'image/webp' || extensionFromName === 'webp'
            ? 'image/webp'
            : requestedMime === 'image/jpeg' || requestedMime === 'image/jpg' || extensionFromName === 'jpg' || extensionFromName === 'jpeg'
              ? 'image/jpeg'
              : '';
        if (!mime) throw new Error('Payment proof must be a JPEG, PNG, or WebP image.');
        const extension = mime === 'image/png' ? 'png' : mime === 'image/webp' ? 'webp' : 'jpg';
        proofPath = `${state.userId}/${contribution.id}/${crypto.randomUUID()}.${extension}`;
        const { error: uploadError } = await supabase!.storage.from('payment-proofs').upload(proofPath, bytes, { contentType: mime, upsert: false });
        if (uploadError) throw uploadError;
      }
      const { error } = await supabase!.rpc('submit_contribution', {
        p_round_id: roundId,
        p_method: method,
        p_reference: reference || null,
        p_proof_path: proofPath,
      });
      if (error) {
        if (proofPath) await supabase!.storage.from('payment-proofs').remove([proofPath]);
        throw error;
      }
      await reload();
      return;
    }
    await persist(updateChitti(state, chittiId, (chitti) => ({
      ...chitti,
      rounds: chitti.rounds.map((round) => round.id === roundId ? {
        ...round,
        contributions: round.contributions.map((item) => item.memberId === state.userId ? {
          ...item, method, reference, proofPath: proof?.uri ?? item.proofPath, status: 'submitted', submittedAt: new Date().toISOString(),
        } : item),
      } : round),
    })));
  };

  const getPaymentProofUrl = async (path: string) => {
    if (env.isDemo) return path;
    const { data, error } = await supabase!.storage.from('payment-proofs').createSignedUrl(path, 300);
    if (error) throw error;
    return data.signedUrl;
  };

  const reviewContribution = (chittiId: string, roundId: string, contributionId: string, accepted: boolean) =>
    remoteOrLocal('review_contribution', { p_contribution_id: contributionId, p_accepted: accepted }, (current) =>
      updateChitti(current, chittiId, (chitti) => ({
        ...chitti,
        rounds: chitti.rounds.map((round) => round.id === roundId ? refreshRound({
          ...round,
          contributions: round.contributions.map((item) => item.id === contributionId ? {
            ...item, status: accepted ? 'confirmed' : 'rejected', confirmedAt: accepted ? new Date().toISOString() : undefined,
          } : item),
        }) : round),
      })));

  const confirmPayout = (chittiId: string, roundId: string) => remoteOrLocal('confirm_payout', { p_round_id: roundId, p_reference: null }, (current) =>
    updateChitti(current, chittiId, (chitti) => {
      const rounds = chitti.rounds.map((round) => round.id === roundId ? { ...round, status: 'completed' as const, payoutStatus: 'paid' as const } : round);
      const completedIndex = rounds.findIndex((round) => round.id === roundId);
      if (rounds[completedIndex + 1]) rounds[completedIndex + 1] = { ...rounds[completedIndex + 1]!, status: 'collecting' };
      const completed = rounds.every((round) => round.status === 'completed');
      return { ...chitti, rounds, status: completed ? 'completed' : chitti.status };
    }));

  const confirmPayoutAdjustment = (chittiId: string, roundId: string, adjustmentId: string) =>
    remoteOrLocal('confirm_payout_adjustment', { p_adjustment_id: adjustmentId, p_reference: null }, (current) =>
      updateChitti(current, chittiId, (chitti) => ({
        ...chitti,
        rounds: chitti.rounds.map((round) => round.id === roundId ? {
          ...round,
          adjustments: round.adjustments?.map((item) => item.id === adjustmentId
            ? { ...item, status: 'paid' as const, paidAt: new Date().toISOString() }
            : item),
        } : round),
      })));

  const swapPayoutMonths = (chittiId: string, firstMemberId: string, secondMemberId: string) =>
    remoteOrLocal('swap_payout_months', {
      p_chitti_id: chittiId,
      p_first_member_id: firstMemberId,
      p_second_member_id: secondMemberId,
    }, (current) => updateChitti(current, chittiId, (chitti) => {
      const first = chitti.members.find((item) => item.id === firstMemberId);
      const second = chitti.members.find((item) => item.id === secondMemberId);
      if (!first?.payoutPosition || !second?.payoutPosition) return chitti;
      const firstMonth = first.payoutPosition;
      const secondMonth = second.payoutPosition;
      return {
        ...chitti,
        members: chitti.members.map((member) => member.id === firstMemberId
          ? { ...member, payoutPosition: secondMonth }
          : member.id === secondMemberId ? { ...member, payoutPosition: firstMonth } : member),
        rounds: chitti.rounds.map((round) => round.number === firstMonth
          ? { ...round, recipientMemberId: secondMemberId }
          : round.number === secondMonth ? { ...round, recipientMemberId: firstMemberId } : round),
      };
    }));

  const markNotificationRead = (id: string) => remoteOrLocal('mark_notification_read', { p_notification_id: id }, (current) => ({
    ...current, notifications: current.notifications.map((item) => item.id === id ? { ...item, read: true } : item),
  }));

  const markAllNotificationsRead = async () => {
    const unread = state.notifications.filter((item) => item.userId === state.userId && !item.read);
    if (!env.isDemo) {
      await Promise.all(unread.map((item) => supabase!.rpc('mark_notification_read', { p_notification_id: item.id })));
      await reload();
    } else await persist({ ...state, notifications: state.notifications.map((item) => item.userId === state.userId ? { ...item, read: true } : item) });
  };

  const updateProfile = async (changes: Pick<UserProfile, 'name' | 'phone' | 'avatarUri'>) => {
    if (!env.isDemo) {
      let avatarUrl = changes.avatarUri;
      if (avatarUrl && !avatarUrl.startsWith('http')) {
        const response = await fetch(avatarUrl);
        const bytes = await response.arrayBuffer();
        const extension = response.headers.get('content-type')?.split('/')[1]?.replace('jpeg', 'jpg') || 'jpg';
        const path = `${state.userId}/avatar-${Date.now()}.${extension}`;
        const { error: uploadError } = await supabase!.storage.from('avatars').upload(path, bytes, { contentType: response.headers.get('content-type') ?? 'image/jpeg', upsert: true });
        if (uploadError) throw uploadError;
        avatarUrl = supabase!.storage.from('avatars').getPublicUrl(path).data.publicUrl;
      }
      const { error } = await supabase!.from('profiles').update({ display_name: changes.name, phone: changes.phone, avatar_url: avatarUrl }).eq('id', state.userId!);
      if (error) throw error;
      await reload();
    } else await persist({
      ...state,
      users: state.users.map((user) => user.id === state.userId ? { ...user, ...changes } : user),
      chittis: state.chittis.map((chitti) => ({
        ...chitti,
        members: chitti.members.map((member) => member.id === state.userId ? { ...member, ...changes } : member),
      })),
    });
  };

  const value: AppContextValue = {
    ready,
    demoMode: env.isDemo,
    currentUser: state.users.find((user) => user.id === state.userId) ?? null,
    chittis: state.chittis.filter((chitti) => chitti.members.some((member) => member.id === state.userId)),
    notifications: state.notifications.filter((item) => item.userId === state.userId),
    pendingInvitations: state.pendingInvitations ?? [],
    inviteLinks,
    savedContacts: env.isDemo && state.users.find((user) => user.id === state.userId)?.role === 'admin'
      ? state.users.filter((user) => user.id !== state.userId).map((user) => ({ ...user, timesInvited: 1, lastInvitedAt: new Date().toISOString() }))
      : savedContacts,
    signInDemo, signInGoogle, signOut, switchDemoUser, createChitti, redeemInvitation, regenerateInvitation, updateInvitation, addMemberInvitation,
    swapPayoutMonths, scheduleShuffle, runShuffle, voteShuffle, simulateApprovals, submitContribution, getPaymentProofUrl, reviewContribution,
    confirmPayout, confirmPayoutAdjustment, markNotificationRead,
    markAllNotificationsRead, updateProfile, reload,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp() {
  const value = useContext(AppContext);
  if (!value) throw new Error('useApp must be used inside AppProvider');
  return value;
}

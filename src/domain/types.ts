export type ChittiStatus =
  | 'draft'
  | 'inviting'
  | 'ready'
  | 'shuffle_scheduled'
  | 'awaiting_approval'
  | 'active'
  | 'completed'
  | 'cancelled';

export type ContributionStatus = 'due' | 'submitted' | 'confirmed' | 'rejected' | 'overdue';
export type PaymentMethod = 'upi' | 'cash';
export type ApprovalStatus = 'pending' | 'accepted' | 'rejected';

export interface UserProfile {
  id: string;
  name: string;
  email: string;
  phone: string;
  avatarUri?: string;
  role: 'admin' | 'member';
}

export interface ChittiMember {
  id: string;
  name: string;
  email: string;
  phone: string;
  avatarUri?: string;
  joined: boolean;
  payoutPosition?: number;
  approval: ApprovalStatus;
  approvalReason?: string;
  isAdmin?: boolean;
}

export interface Contribution {
  id: string;
  memberId: string;
  status: ContributionStatus;
  method?: PaymentMethod;
  reference?: string;
  submittedAt?: string;
  confirmedAt?: string;
  confirmedOnTime?: boolean;
  overdueAt?: string;
  proofPath?: string;
}

export interface PaymentProofUpload {
  uri: string;
  mimeType?: string | null;
  fileName?: string | null;
}

export interface ChittiRound {
  id: string;
  number: number;
  periodStartDate: string;
  dueDate: string;
  recipientMemberId: string;
  status: 'upcoming' | 'collecting' | 'ready_for_payout' | 'completed';
  payoutStatus: 'blocked' | 'ready' | 'paid';
  confirmedCount?: number;
  contributions: Contribution[];
  adjustments?: PayoutAdjustment[];
}

export interface PayoutAdjustment {
  id: string;
  recipientMemberId: string;
  sourceMemberId: string;
  amountPaise: number;
  status: 'awaiting_contribution' | 'ready' | 'paid';
  paidAt?: string;
}

export interface Chitti {
  id: string;
  name: string;
  description?: string;
  monthlyAmountPaise: number;
  memberCount: number;
  startDate: string;
  firstDueDate: string;
  endDate: string;
  dueDay: number;
  upiId: string;
  payeeName: string;
  status: ChittiStatus;
  members: ChittiMember[];
  invitations?: ChittiInvitation[];
  rounds: ChittiRound[];
  shuffleScheduledAt?: string;
  resultHash?: string;
  createdAt: string;
}

export interface ChittiInvitation {
  id: string;
  name: string;
  email: string;
  phone: string;
  status: 'pending' | 'accepted' | 'revoked' | 'expired';
  lateJoin?: boolean;
}

export interface PendingInvitation {
  id: string;
  chittiId: string;
  chittiName: string;
  invitedName: string;
  monthlyAmountPaise: number;
  memberCount: number;
  administratorName: string;
  expiresAt: string;
  createdAt: string;
}

export interface AppNotification {
  id: string;
  userId: string;
  title: string;
  message: string;
  route?: string;
  read: boolean;
  createdAt: string;
}

export interface InviteDraft {
  name: string;
  email: string;
  phone: string;
}

export interface SavedMemberContact extends InviteDraft {
  avatarUri?: string;
  timesInvited: number;
  lastInvitedAt: string;
}

export interface CreateChittiInput {
  name: string;
  description?: string;
  monthlyAmountPaise: number;
  memberCount: number;
  startDate: string;
  firstDueDate: string;
  dueDay: number;
  upiId: string;
  payeeName: string;
  invites: InviteDraft[];
}

export interface ChittiHistoryReport {
  chittiId: string;
  name: string;
  status: ChittiStatus;
  monthlyAmountPaise: number;
  totalAmountPaise: number;
  startDate: string;
  endDate: string;
  payoutPosition?: number;
  payoutDate?: string;
  payoutStatus?: 'blocked' | 'ready' | 'paid';
  onTimePayments: number;
  latePayments: number;
  missedDueDates: number;
  confirmedAmountPaise: number;
  overdueAmountPaise: number;
}

export interface UserReliabilityReport {
  userId: string;
  name: string;
  email: string;
  phone: string;
  avatarUri?: string;
  chittiCount: number;
  activeChittis: number;
  completedChittis: number;
  onTimePayments: number;
  latePayments: number;
  missedDueDates: number;
  assessedPayments: number;
  reliabilityScore?: number;
  confirmedAmountPaise: number;
  overdueAmountPaise: number;
  chittis: ChittiHistoryReport[];
}

import { addMonthsClamped } from '@/lib/format';
import type { AppNotification, Chitti, UserProfile } from '@/domain/types';

export const demoUsers: UserProfile[] = [
  { id: 'user-admin', name: 'Lakshmi Rao', email: 'lakshmi@example.com', phone: '+91 98765 43210', role: 'admin' },
  { id: 'user-anita', name: 'Anita Sharma', email: 'anita@example.com', phone: '+91 98765 43211', role: 'member' },
  { id: 'user-meera', name: 'Meera Reddy', email: 'meera@example.com', phone: '+91 98765 43212', role: 'member' },
  { id: 'user-sunita', name: 'Sunita Devi', email: 'sunita@example.com', phone: '+91 98765 43213', role: 'member' },
];

const memberRows = demoUsers.map((user, index) => ({
  id: user.id,
  name: user.name,
  email: user.email,
  phone: user.phone,
  joined: true,
  payoutPosition: index + 1,
  approval: 'accepted' as const,
  isAdmin: user.role === 'admin',
}));

const rounds = memberRows.map((recipient, index) => ({
  id: `round-demo-${index + 1}`,
  number: index + 1,
  periodStartDate: addMonthsClamped('2026-09-01', index),
  dueDate: addMonthsClamped('2026-09-15', index),
  recipientMemberId: recipient.id,
  status: (index === 0 ? 'collecting' : 'upcoming') as 'collecting' | 'upcoming',
  payoutStatus: 'blocked' as const,
  contributions: memberRows.map((member, memberIndex) => ({
    id: `demo-${index + 1}-${member.id}`,
    memberId: member.id,
    status: (index === 0 && memberIndex < 2 ? 'confirmed' : 'due') as 'confirmed' | 'due',
    method: index === 0 && memberIndex < 2 ? ('upi' as const) : undefined,
    confirmedOnTime: index === 0 && memberIndex < 2 ? true : undefined,
  })),
}));

export const demoChittis: Chitti[] = [
  {
    id: 'festival-fund',
    name: 'Festival Fund',
    description: 'Our family savings circle for the festive season.',
    monthlyAmountPaise: 500_000,
    memberCount: 4,
    startDate: '2026-09-01',
    firstDueDate: '2026-09-15',
    endDate: '2026-12-15',
    dueDay: 15,
    upiId: 'lakshmi@upi',
    payeeName: 'Lakshmi Rao',
    status: 'active',
    members: memberRows,
    rounds,
    resultHash: 'demo-7a9c2e4f',
    createdAt: '2026-08-20T10:00:00.000Z',
  },
  {
    id: 'new-year-circle',
    name: 'New Year Circle',
    description: 'A new group beginning in January.',
    monthlyAmountPaise: 300_000,
    memberCount: 4,
    startDate: '2027-01-01',
    firstDueDate: '2027-01-10',
    endDate: '2027-04-10',
    dueDay: 10,
    upiId: 'lakshmi@upi',
    payeeName: 'Lakshmi Rao',
    status: 'ready',
    members: memberRows.map((member) => ({ ...member, payoutPosition: undefined, approval: 'pending' as const })),
    rounds: [],
    createdAt: '2026-09-01T10:00:00.000Z',
  },
];

export const demoNotifications: AppNotification[] = [
  {
    id: 'notification-1',
    userId: 'user-admin',
    title: '2 of 4 payments confirmed',
    message: 'Festival Fund is halfway collected for September.',
    route: '/chitti/festival-fund',
    read: false,
    createdAt: '2026-09-12T07:30:00.000Z',
  },
  {
    id: 'notification-2',
    userId: 'user-admin',
    title: 'New Year Circle is ready',
    message: 'Everyone has joined. You can schedule the live shuffle.',
    route: '/chitti/new-year-circle/shuffle',
    read: false,
    createdAt: '2026-09-11T09:00:00.000Z',
  },
];

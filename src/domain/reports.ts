import type { Chitti, UserProfile, UserReliabilityReport } from './types';
import { todayInIndia } from '@/lib/format';

export function buildDemoReports(currentUser: UserProfile, chittis: Chitti[], today = todayInIndia()): UserReliabilityReport[] {
  const users = currentUser.role === 'admin'
    ? Array.from(new Map(chittis.flatMap((chitti) => chitti.members).map((member) => [member.id, member])).values())
    : chittis.flatMap((chitti) => chitti.members).filter((member) => member.id === currentUser.id).slice(0, 1);
  return users.map((user) => {
    const userChittis = chittis.filter((chitti) => chitti.members.some((member) => member.id === user.id));
    const histories = userChittis.map((chitti) => {
      const contributions = chitti.rounds.flatMap((round) => {
        const contribution = round.contributions.find((item) => item.memberId === user.id);
        return contribution ? [{ round, contribution }] : [];
      });
      const onTimePayments = contributions.filter(({ contribution }) => contribution.status === 'confirmed' && contribution.confirmedOnTime === true).length;
      const latePayments = contributions.filter(({ contribution }) => contribution.status === 'confirmed' && contribution.confirmedOnTime === false).length;
      const missedDueDates = contributions.filter(({ round, contribution }) => round.dueDate < today && contribution.status !== 'confirmed').length;
      const confirmedAmountPaise = contributions.filter(({ contribution }) => contribution.status === 'confirmed')
        .reduce((sum, { contribution }) => sum + (contribution.amountPaise ?? chitti.monthlyAmountPaise), 0);
      const overdueAmountPaise = contributions.filter(({ round, contribution }) => round.dueDate < today && contribution.status !== 'confirmed')
        .reduce((sum, { contribution }) => sum + (contribution.amountPaise ?? chitti.monthlyAmountPaise), 0);
      const payoutRound = chitti.rounds.find((round) => round.payoutShares?.some((share) => share.recipientMemberId === user.id) || round.recipientMemberId === user.id);
      const membership = chitti.members.find((member) => member.id === user.id);
      return {
        chittiId: chitti.id,
        name: chitti.name,
        status: chitti.status,
        monthlyAmountPaise: membership?.contributionAmountPaise ?? Math.floor(chitti.monthlyAmountPaise * (membership?.contributionShareBps ?? 10000) / 10000),
        totalAmountPaise: chitti.monthlyAmountPaise * chitti.memberCount,
        startDate: chitti.startDate,
        endDate: chitti.endDate,
        payoutPosition: chitti.members.find((member) => member.id === user.id)?.payoutPosition,
        payoutDate: payoutRound?.dueDate,
        payoutStatus: payoutRound?.payoutStatus,
        onTimePayments,
        latePayments,
        missedDueDates,
        confirmedAmountPaise,
        overdueAmountPaise,
      };
    });
    const onTimePayments = histories.reduce((sum, item) => sum + item.onTimePayments, 0);
    const latePayments = histories.reduce((sum, item) => sum + item.latePayments, 0);
    const missedDueDates = histories.reduce((sum, item) => sum + item.missedDueDates, 0);
    const assessedPayments = onTimePayments + latePayments + missedDueDates;
    return {
      userId: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUri: user.avatarUri,
      chittiCount: histories.length,
      activeChittis: histories.filter((item) => item.status === 'active').length,
      completedChittis: histories.filter((item) => item.status === 'completed').length,
      onTimePayments,
      latePayments,
      missedDueDates,
      assessedPayments,
      reliabilityScore: assessedPayments ? Math.round((onTimePayments / assessedPayments) * 100) / 10 : undefined,
      confirmedAmountPaise: histories.reduce((sum, item) => sum + item.confirmedAmountPaise, 0),
      overdueAmountPaise: histories.reduce((sum, item) => sum + item.overdueAmountPaise, 0),
      chittis: histories,
    };
  });
}

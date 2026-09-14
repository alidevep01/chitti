import * as Linking from 'expo-linking';
import * as ImagePicker from 'expo-image-picker';
import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Image, ScrollView, Share, StyleSheet, View } from 'react-native';
import QRCode from 'react-native-qrcode-svg';
import { Avatar, Button, Card, Dialog, Divider, Icon, Portal, ProgressBar, SegmentedButtons, Snackbar, Text, TextInput, useTheme } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { StatusPill } from '@/components/StatusPill';
import { useApp } from '@/data/AppProvider';
import type { ChittiInvitation, PaymentMethod } from '@/domain/types';
import { env } from '@/lib/env';
import { addMonthsClamped, formatDate, formatINR, initials, todayInIndia } from '@/lib/format';

export default function ChittiDetailScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { chittis, currentUser, inviteLinks, regenerateInvitation, updateInvitation, addMemberInvitation, swapPayoutMonths, scheduleShuffle, submitContribution, getPaymentProofUrl, reviewContribution, confirmPayout, confirmPayoutAdjustment, demoMode } = useApp();
  const chitti = chittis.find((item) => item.id === id);
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [paymentRoundId, setPaymentRoundId] = useState<string>();
  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [editInvitationId, setEditInvitationId] = useState<string>();
  const [swapOpen, setSwapOpen] = useState(false);
  const [memberName, setMemberName] = useState('');
  const [memberEmail, setMemberEmail] = useState('');
  const [memberPhone, setMemberPhone] = useState('');
  const [firstSwapMember, setFirstSwapMember] = useState('');
  const [secondSwapMember, setSecondSwapMember] = useState('');
  const [busy, setBusy] = useState(false);
  const [method, setMethod] = useState<PaymentMethod>('upi');
  const [reference, setReference] = useState('');
  const [paymentProof, setPaymentProof] = useState<ImagePicker.ImagePickerAsset>();
  const [proofPreviewUri, setProofPreviewUri] = useState('');
  const [message, setMessage] = useState('');
  const currentRound = chitti?.rounds.find((round) => round.status === 'collecting' || round.status === 'ready_for_payout');
  const paymentRound = chitti?.rounds.find((round) => round.id === paymentRoundId) ?? currentRound;
  const currentRecipient = chitti?.members.find((member) => member.id === currentRound?.recipientMemberId);
  const myContribution = currentRound?.contributions.find((item) => item.memberId === currentUser?.id);
  const upiUri = chitti ? `upi://pay?pa=${encodeURIComponent(chitti.upiId)}&pn=${encodeURIComponent(chitti.payeeName)}&am=${(chitti.monthlyAmountPaise / 100).toFixed(2)}&cu=INR&tn=${encodeURIComponent(`${chitti.name} month ${paymentRound?.number ?? ''}`)}` : '';

  if (!chitti || !currentUser) return <Screen title="Chitti" back><EmptyState icon="alert-circle-outline" title="Chitti not found" message="This chitti is unavailable or you no longer have access." /></Screen>;
  const confirmed = currentRound?.confirmedCount ?? currentRound?.contributions.filter((item) => item.status === 'confirmed').length ?? 0;
  const completed = chitti.rounds.filter((round) => round.status === 'completed').length;
  const catchUpRounds = chitti.rounds.filter((round) => round.adjustments?.some((item) => item.sourceMemberId === currentUser.id && item.status !== 'paid'));
  const catchUpReviews = chitti.rounds.flatMap((round) => round.status === 'completed'
    ? round.contributions.filter((item) => item.status === 'submitted').map((contribution) => ({ round, contribution }))
    : []);
  const adjustments = chitti.rounds.flatMap((round) => (round.adjustments ?? []).map((adjustment) => ({ round, adjustment })));
  const rejectedMembers = chitti.members.filter((member) => member.approval === 'rejected');
  const swappableMembers = chitti.members.filter((member) => !member.isAdmin && member.payoutPosition && chitti.rounds.some((round) => round.number === member.payoutPosition && round.status !== 'completed' && round.payoutStatus !== 'paid'));
  const today = todayInIndia();
  const reliability = chitti.members.map((member) => {
    const history = chitti.rounds.flatMap((round) => {
      const contribution = round.contributions.find((item) => item.memberId === member.id);
      return contribution ? [{ round, contribution }] : [];
    });
    const onTime = history.filter(({ contribution }) => contribution.status === 'confirmed' && contribution.confirmedOnTime === true).length;
    const late = history.filter(({ contribution }) => contribution.status === 'confirmed' && contribution.confirmedOnTime === false).length;
    const missed = history.filter(({ round, contribution }) => round.dueDate < today && contribution.status !== 'confirmed').length;
    const assessed = onTime + late + missed;
    return { member, onTime, late, missed, assessed, rate: assessed ? Math.round((onTime / assessed) * 100) : undefined };
  });
  const reliabilityTotals = reliability.reduce((total, item) => ({
    onTime: total.onTime + item.onTime,
    late: total.late + item.late,
    missed: total.missed + item.missed,
  }), { onTime: 0, late: 0, missed: 0 });

  const invitationUrl = (token: string) => `${env.appUrl}/invite?token=${encodeURIComponent(token)}`;
  const invitationMessage = (memberName: string, email: string, token: string) => `Hi ${memberName},\n\nYou are privately invited to join ${chitti.name} on Chitti. Sign in using this Google email: ${email}\n\nOpen your invitation: ${invitationUrl(token)}`;

  const shareInvite = async (memberName: string, token?: string) => {
    const actualToken = token ?? `demo-${encodeURIComponent(chitti.id)}-${encodeURIComponent(memberName)}`;
    const url = invitationUrl(actualToken);
    await Share.share({ title: `Join ${chitti.name}`, message: `Hi ${memberName}, you are privately invited to join ${chitti.name} on Chitti. Open this unique link: ${url}`, url });
  };

  const emailInvite = async (memberName: string, email: string, token: string) => {
    const subject = `Invitation to join ${chitti.name} on Chitti`;
    const mailto = `mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(invitationMessage(memberName, email, token))}`;
    await Linking.openURL(mailto);
  };

  const ensureInvitationToken = async (invitationId: string) => inviteLinks[invitationId] ?? regenerateInvitation(invitationId);

  const emailPendingInvitation = async (invitation: ChittiInvitation) => {
    try {
      const token = await ensureInvitationToken(invitation.id);
      await emailInvite(invitation.name, invitation.email, token);
    } catch {
      setMessage('Could not open an email app. You can still use Share link.');
    }
  };

  const sharePendingInvitation = async (invitation: ChittiInvitation) => {
    try {
      const token = await ensureInvitationToken(invitation.id);
      await shareInvite(invitation.name, token);
    } catch {
      setMessage('Could not open the share menu.');
    }
  };

  const openEditInvitation = (invitation: ChittiInvitation) => {
    setMemberName(invitation.name);
    setMemberEmail(invitation.email);
    setMemberPhone(invitation.phone);
    setEditInvitationId(invitation.id);
  };

  const closeMemberForm = () => {
    setAddMemberOpen(false);
    setEditInvitationId(undefined);
    setMemberName('');
    setMemberEmail('');
    setMemberPhone('');
  };

  const openUpi = async () => {
    try { await Linking.openURL(upiUri); } catch { setMessage('No UPI app opened. Copy the UPI ID or scan the QR code.'); }
  };

  const submitPayment = async () => {
    if (!paymentRound) return;
    setBusy(true);
    try {
      await submitContribution(chitti.id, paymentRound.id, method, reference.trim() || undefined, paymentProof ? {
        uri: paymentProof.uri,
        mimeType: paymentProof.mimeType,
        fileName: paymentProof.fileName,
      } : undefined);
      setPaymentOpen(false);
      setPaymentProof(undefined);
      setMessage('Payment submitted for administrator confirmation.');
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not submit this payment.');
    } finally { setBusy(false); }
  };

  const openPayment = (roundId: string) => {
    setPaymentRoundId(roundId);
    setReference('');
    setPaymentProof(undefined);
    setPaymentOpen(true);
  };

  const choosePaymentProof = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: true, quality: 0.8 });
    if (result.canceled) return;
    const asset = result.assets[0];
    if (!asset) return;
    if (asset.fileSize && asset.fileSize > 5 * 1024 * 1024) return setMessage('Choose a payment photo smaller than 5 MB.');
    if (asset.mimeType && !['image/jpeg', 'image/png', 'image/webp'].includes(asset.mimeType)) return setMessage('Choose a JPEG, PNG, or WebP image.');
    setPaymentProof(asset);
  };

  const viewPaymentProof = async (path: string) => {
    setBusy(true);
    try {
      setProofPreviewUri(await getPaymentProofUrl(path));
    } catch {
      setMessage('Could not open this payment photo.');
    } finally { setBusy(false); }
  };

  const addMember = async () => {
    if (memberName.trim().length < 2 || !memberEmail.includes('@') || memberPhone.trim().length < 8) {
      return setMessage('Enter a valid name, email, and phone number.');
    }
    setBusy(true);
    try {
      const result = await addMemberInvitation(chitti.id, { name: memberName.trim(), email: memberEmail.trim(), phone: memberPhone.trim() });
      closeMemberForm();
      setMessage(result.lateJoin
        ? 'Late-member invitation created. Their payout will be added as the final month after they join.'
        : result.shuffleReset
          ? 'Invitation created. The unfinished shuffle was cancelled; shuffle again after the member joins.'
          : 'Member invitation created.');
      try {
        await emailInvite(memberName.trim(), memberEmail.trim(), result.token);
      } catch {
        setMessage('Invitation created. You can email or share it from Pending invitations.');
      }
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not add this member.');
    } finally { setBusy(false); }
  };

  const saveInvitation = async () => {
    if (!editInvitationId) return;
    if (memberName.trim().length < 2 || !memberEmail.includes('@') || memberPhone.trim().length < 8) {
      return setMessage('Enter a valid name, email, and phone number.');
    }
    setBusy(true);
    try {
      await updateInvitation(chitti.id, editInvitationId, {
        name: memberName.trim(),
        email: memberEmail.trim(),
        phone: memberPhone.trim(),
      });
      closeMemberForm();
      setMessage('Invitation updated. The previous link no longer works. Use Email invite to send the new link.');
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not update this invitation.');
    } finally { setBusy(false); }
  };

  const swapMonths = async () => {
    if (!firstSwapMember || !secondSwapMember || firstSwapMember === secondSwapMember) return setMessage('Choose two different members.');
    setBusy(true);
    try {
      await swapPayoutMonths(chitti.id, firstSwapMember, secondSwapMember);
      setSwapOpen(false); setFirstSwapMember(''); setSecondSwapMember('');
      setMessage('Payout months swapped. Both members were notified.');
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not swap these payout months.');
    } finally { setBusy(false); }
  };

  return (
    <Screen title={chitti.name} back action={<Button onPress={() => router.push('/dashboard')}>Home</Button>}>
      <Card mode="contained" style={{ backgroundColor: theme.colors.primaryContainer }}><Card.Content style={styles.hero}>
        <View style={styles.rowBetween}><StatusPill status={chitti.status} /><Text variant="labelLarge">{chitti.memberCount} months</Text></View>
        <Text variant="headlineMedium" style={styles.amount}>{formatINR(chitti.monthlyAmountPaise * chitti.memberCount)}</Text>
        <Text variant="bodyLarge">Monthly pot · {formatINR(chitti.monthlyAmountPaise)} from each member</Text>
        {chitti.description ? <Text>{chitti.description}</Text> : null}
      </Card.Content></Card>

      <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Schedule</Text>
        <View style={styles.scheduleGrid}><View><Text variant="labelLarge">Starts</Text><Text>{formatDate(chitti.startDate ?? chitti.firstDueDate)}</Text></View><View><Text variant="labelLarge">First due date</Text><Text>{formatDate(chitti.firstDueDate)}</Text></View><View><Text variant="labelLarge">Ends</Text><Text>{formatDate(chitti.endDate ?? addMonthsClamped(chitti.firstDueDate, chitti.memberCount - 1))}</Text></View></View>
        <Text>Unpaid members receive an in-app reminder every day while the current collection period is open.</Text>
      </Card.Content></Card>

      {currentUser.role === 'admin' && chitti.status === 'ready' && rejectedMembers.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Reshuffle requested</Text>
        <Text>The following member rejected the previous payout order:</Text>
        {rejectedMembers.map((member, index) => <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<Text variant="titleMedium">{member.name}</Text><Text>{member.approvalReason || 'No reason was recorded.'}</Text></View>)}
      </Card.Content></Card> : null}

      {['ready', 'shuffle_scheduled', 'awaiting_approval'].includes(chitti.status) ? (
        <Card mode="elevated"><Card.Content style={styles.section}>
          <View style={styles.iconTitle}><Icon source="shuffle-variant" size={28} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payout order</Text></View>
          <Text>{chitti.status === 'ready' ? 'Everyone has joined. Schedule a fair, server-side shuffle.' : chitti.status === 'shuffle_scheduled' ? 'The shuffle is scheduled and ready to begin.' : 'The order has been revealed and needs unanimous approval.'}</Text>
          {currentUser.role === 'admin' && chitti.status === 'ready' ? <Button mode="contained" onPress={() => void scheduleShuffle(chitti.id).then(() => router.push(`/chitti/${chitti.id}/shuffle`))}>Schedule now</Button> : <Button mode="contained" onPress={() => router.push(`/chitti/${chitti.id}/shuffle`)}>Open live shuffle</Button>}
        </Card.Content></Card>
      ) : null}

      {chitti.status === 'active' && currentRound ? (
        <>
          <Card mode="elevated"><Card.Content style={styles.section}>
            <Text variant="labelLarge" style={{ color: theme.colors.primary }}>MONTH {currentRound.number} OF {chitti.memberCount}</Text>
            <View style={styles.recipient}><Avatar.Text size={52} label={initials(currentRecipient?.name ?? '?')} /><View style={styles.grow}><Text variant="bodyMedium">Current recipient</Text><Text variant="headlineSmall" style={styles.heading}>{currentRecipient?.name}</Text></View></View>
            <View style={styles.rowBetween}><Text>Due {formatDate(currentRound.dueDate)}</Text><Text>{confirmed}/{chitti.memberCount} confirmed</Text></View>
            <View style={styles.progressTrack}><ProgressBar progress={confirmed / chitti.memberCount} style={styles.progress} /></View>
            {myContribution ? <View style={styles.rowBetween}><Text variant="titleMedium">Your payment</Text><StatusPill status={myContribution.status} /></View> : null}
            {myContribution && ['due', 'rejected', 'overdue'].includes(myContribution.status) ? <Button mode="contained" icon="bank-transfer" contentStyle={styles.bigButton} onPress={() => openPayment(currentRound.id)}>Pay {formatINR(chitti.monthlyAmountPaise)}</Button> : null}
            {currentRound.payoutStatus === 'ready' && currentUser.role === 'admin' ? <Button mode="contained" icon="cash-check" contentStyle={styles.bigButton} onPress={() => void confirmPayout(chitti.id, currentRound.id)}>Confirm payout delivered</Button> : null}
          </Card.Content></Card>

          {currentUser.role === 'admin' ? (
            <Card mode="outlined"><Card.Content style={styles.section}>
              <Text variant="titleLarge" style={styles.heading}>Payment review</Text>
              {currentRound.contributions.map((contribution, index) => {
                const member = chitti.members.find((item) => item.id === contribution.memberId)!;
                return <View key={contribution.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View style={styles.recipient}><Avatar.Text size={38} label={initials(member.name)} /><View><Text variant="titleMedium">{member.name}</Text><Text>{contribution.method?.toUpperCase() ?? 'Not submitted'}{contribution.reference ? ` · ${contribution.reference}` : ''}</Text>{contribution.proofPath ? <Button compact icon="image-outline" onPress={() => void viewPaymentProof(contribution.proofPath!)}>View payment photo</Button> : null}</View></View><View style={styles.actions}><StatusPill status={contribution.status} />{contribution.status === 'submitted' ? <><Button compact onPress={() => void reviewContribution(chitti.id, currentRound.id, contribution.id, false)}>Reject</Button><Button compact mode="contained-tonal" onPress={() => void reviewContribution(chitti.id, currentRound.id, contribution.id, true)}>Confirm received</Button></> : null}</View></View></View>;
              })}
            </Card.Content></Card>
          ) : null}
        </>
      ) : null}

      {!['active', 'completed'].includes(chitti.status) ? <Card mode="outlined"><Card.Content style={styles.section}><View style={styles.iconTitle}><Icon source="bank-transfer" size={26} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payments are not open yet</Text></View><Text>The “I have paid” option appears after everyone accepts the payout order and the chitti becomes active.</Text></Card.Content></Card> : null}
      {chitti.status === 'active' && !currentRound ? <Card mode="outlined"><Card.Content style={styles.section}><View style={styles.iconTitle}><Icon source="calendar-clock" size={26} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payments start {formatDate(chitti.startDate)}</Text></View><Text>The first “Pay / record payment” button appears when the first collection period opens.</Text></Card.Content></Card> : null}

      {catchUpRounds.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Catch-up contributions</Text>
        <Text>You joined after this chitti began. Submit each missed contribution separately.</Text>
        {catchUpRounds.map((round, index) => {
          const contribution = round.contributions.find((item) => item.memberId === currentUser.id);
          return <View key={round.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">Month {round.number}</Text><Text>{formatDate(round.dueDate)} · {formatINR(chitti.monthlyAmountPaise)}</Text></View><View style={styles.actions}>{contribution ? <StatusPill status={contribution.status} /> : null}{contribution && ['due', 'rejected', 'overdue'].includes(contribution.status) ? <Button mode="contained-tonal" onPress={() => openPayment(round.id)}>Pay catch-up</Button> : null}</View></View></View>;
        })}
      </Card.Content></Card> : null}

      {currentUser.role === 'admin' && catchUpReviews.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Catch-up payment review</Text>
        {catchUpReviews.map(({ round, contribution }, index) => { const member = chitti.members.find((item) => item.id === contribution.memberId); return <View key={contribution.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">{member?.name} · Month {round.number}</Text><Text>{contribution.method?.toUpperCase()}{contribution.reference ? ` · ${contribution.reference}` : ''}</Text>{contribution.proofPath ? <Button compact icon="image-outline" onPress={() => void viewPaymentProof(contribution.proofPath!)}>View payment photo</Button> : null}</View><View style={styles.actions}><Button compact onPress={() => void reviewContribution(chitti.id, round.id, contribution.id, false)}>Reject</Button><Button compact mode="contained-tonal" onPress={() => void reviewContribution(chitti.id, round.id, contribution.id, true)}>Confirm received</Button></View></View></View>; })}
      </Card.Content></Card> : null}

      {adjustments.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Additional payouts</Text>
        <Text>Top-ups created when a member joined after earlier payouts were delivered.</Text>
        {adjustments.map(({ round, adjustment }, index) => { const recipient = chitti.members.find((item) => item.id === adjustment.recipientMemberId); const source = chitti.members.find((item) => item.id === adjustment.sourceMemberId); return <View key={adjustment.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">{formatINR(adjustment.amountPaise)} to {recipient?.name}</Text><Text>Month {round.number} catch-up from {source?.name}</Text></View><View style={styles.actions}><StatusPill status={adjustment.status} />{currentUser.role === 'admin' && adjustment.status === 'ready' ? <Button mode="contained-tonal" onPress={() => void confirmPayoutAdjustment(chitti.id, round.id, adjustment.id)}>Confirm delivered</Button> : null}</View></View></View>; })}
      </Card.Content></Card> : null}

      {currentUser.role === 'admin' && chitti.rounds.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Payment reliability</Text>
        <Text>Based on when a valid payment was submitted compared with each recorded due date.</Text>
        <Text variant="titleMedium">{reliabilityTotals.onTime} on time · {reliabilityTotals.late} paid late · {reliabilityTotals.missed} currently overdue</Text>
        {reliability.map(({ member, onTime, late, missed, assessed, rate }, index) => <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View style={styles.grow}><Text variant="titleMedium">{member.name}{member.isAdmin ? ' · Admin' : ''}</Text><Text>{onTime} on time · {late} paid late · {missed} currently overdue</Text></View><Text variant="titleMedium">{assessed ? `${rate}% on time` : 'No due history'}</Text></View></View>)}
      </Card.Content></Card> : null}

      <Card mode="outlined"><Card.Content style={styles.section}>
        <View style={styles.rowBetween}><Text variant="titleLarge" style={styles.heading}>Members</Text><Text>{chitti.members.filter((item) => item.joined).length}/{chitti.memberCount} joined</Text></View>
        {currentUser.role === 'admin' && !['completed', 'cancelled'].includes(chitti.status) ? <View style={styles.memberActions}><Button icon="account-plus" mode="contained-tonal" onPress={() => setAddMemberOpen(true)}>Add member</Button>{chitti.status === 'active' && swappableMembers.length >= 2 ? <Button icon="swap-horizontal" mode="outlined" onPress={() => setSwapOpen(true)}>Swap months</Button> : null}</View> : null}
        {[...chitti.members].sort((a, b) => (a.payoutPosition ?? 99) - (b.payoutPosition ?? 99)).map((member, index) => (
          <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View style={styles.recipient}><Avatar.Text size={40} label={initials(member.name)} /><View><Text variant="titleMedium">{member.name}{member.isAdmin ? ' · Admin' : ''}</Text><Text>{member.payoutPosition ? `Payout month ${member.payoutPosition}` : member.joined ? 'Ready for shuffle' : 'Invitation pending'}</Text></View></View>{demoMode && currentUser.role === 'admin' && !member.isAdmin && chitti.status !== 'active' ? <Button compact icon="share-variant" onPress={() => void shareInvite(member.name)}>Share</Button> : null}</View></View>
        ))}
      </Card.Content></Card>

      {currentUser.role === 'admin' && chitti.invitations?.some((invite) => invite.status === 'pending') ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Pending invitations</Text>
        <Text>For security, raw links are shown only when created or regenerated. Regenerating invalidates the previous link.</Text>
        {chitti.invitations.filter((invite) => invite.status === 'pending').map((invite, index) => <View key={invite.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">{invite.name}</Text><Text>{invite.email} · {invite.phone}</Text></View><View style={styles.inviteActions}><Button compact icon="pencil-outline" onPress={() => openEditInvitation(invite)}>Edit</Button><Button compact icon="email-outline" mode="contained-tonal" onPress={() => void emailPendingInvitation(invite)}>Email invite</Button><Button compact icon="share-variant" onPress={() => void sharePendingInvitation(invite)}>Share link</Button></View></View></View>)}
      </Card.Content></Card> : null}

      {chitti.status === 'active' ? <Card mode="outlined"><Card.Content style={styles.section}><Text variant="titleLarge" style={styles.heading}>Schedule</Text>{chitti.rounds.map((round, index) => { const recipient = chitti.members.find((member) => member.id === round.recipientMemberId); return <View key={round.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">Month {round.number} · {recipient?.name}</Text><Text>{formatDate(round.dueDate)}</Text></View><StatusPill status={round.status === 'completed' ? 'completed' : round.status} /></View></View>; })}<Text>{chitti.memberCount - completed} months remaining</Text></Card.Content></Card> : null}

      <Portal><Dialog visible={addMemberOpen} onDismiss={closeMemberForm} style={styles.dialog}><Dialog.Title>Add a member</Dialog.Title><Dialog.Content style={styles.section}>
        <Text>{chitti.status === 'active'
          ? 'After joining, this member receives the final payout month and owes every elapsed contribution.'
          : ['shuffle_scheduled', 'awaiting_approval'].includes(chitti.status)
            ? 'Adding a member will cancel the unfinished shuffle. Shuffle everyone again after the new member joins.'
            : 'The member will join through a private invitation.'}</Text>
        <TextInput mode="outlined" label="Full name" value={memberName} onChangeText={setMemberName} />
        <TextInput mode="outlined" label="Google email" value={memberEmail} onChangeText={setMemberEmail} autoCapitalize="none" keyboardType="email-address" />
        <TextInput mode="outlined" label="Phone number" value={memberPhone} onChangeText={setMemberPhone} keyboardType="phone-pad" />
      </Dialog.Content><Dialog.Actions><Button onPress={closeMemberForm}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy} onPress={() => void addMember()}>Create invitation</Button></Dialog.Actions></Dialog></Portal>

      <Portal><Dialog visible={Boolean(editInvitationId)} onDismiss={closeMemberForm} style={styles.dialog}><Dialog.Title>Edit invitation</Dialog.Title><Dialog.Content style={styles.section}>
        <Text>Saving rotates the private invitation link, so any previously shared link will stop working.</Text>
        <TextInput mode="outlined" label="Full name" value={memberName} onChangeText={setMemberName} />
        <TextInput mode="outlined" label="Google email" value={memberEmail} onChangeText={setMemberEmail} autoCapitalize="none" keyboardType="email-address" />
        <TextInput mode="outlined" label="Phone number" value={memberPhone} onChangeText={setMemberPhone} keyboardType="phone-pad" />
      </Dialog.Content><Dialog.Actions><Button onPress={closeMemberForm}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy} onPress={() => void saveInvitation()}>Save changes</Button></Dialog.Actions></Dialog></Portal>

      <Portal><Dialog visible={swapOpen} onDismiss={() => setSwapOpen(false)} style={styles.dialog}><Dialog.Title>Swap payout months</Dialog.Title><Dialog.ScrollArea><ScrollView contentContainerStyle={styles.swapContent}>
        <Text variant="titleMedium">First member</Text>{swappableMembers.map((member) => <Button key={`first-${member.id}`} mode={firstSwapMember === member.id ? 'contained-tonal' : 'text'} onPress={() => setFirstSwapMember(member.id)}>{member.name} · Month {member.payoutPosition}</Button>)}
        <Divider /><Text variant="titleMedium">Second member</Text>{swappableMembers.map((member) => <Button key={`second-${member.id}`} disabled={firstSwapMember === member.id} mode={secondSwapMember === member.id ? 'contained-tonal' : 'text'} onPress={() => setSecondSwapMember(member.id)}>{member.name} · Month {member.payoutPosition}</Button>)}
        <Text variant="bodySmall">Completed payouts cannot be changed. Both affected members will be notified automatically.</Text>
      </ScrollView></Dialog.ScrollArea><Dialog.Actions><Button onPress={() => setSwapOpen(false)}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy || !firstSwapMember || !secondSwapMember} onPress={() => void swapMonths()}>Swap months</Button></Dialog.Actions></Dialog></Portal>

      <Portal><Dialog visible={paymentOpen} onDismiss={() => setPaymentOpen(false)} style={styles.dialog}><Dialog.Title>Pay / record {formatINR(chitti.monthlyAmountPaise)}{paymentRound ? ` · Month ${paymentRound.number}` : ''}</Dialog.Title><Dialog.ScrollArea><ScrollView contentContainerStyle={styles.paymentContent}>
        <SegmentedButtons value={method} onValueChange={(value) => setMethod(value as PaymentMethod)} buttons={[{ value: 'upi', label: 'UPI / GPay', icon: 'qrcode' }, { value: 'cash', label: 'Cash', icon: 'cash' }]} />
        {method === 'upi' ? <><View style={styles.qr}><QRCode value={upiUri} size={176} color="#502018" backgroundColor="#ffffff" /></View><Text style={styles.center}>Pay to {chitti.payeeName}</Text><Text selectable style={[styles.upi, styles.center]}>{chitti.upiId}</Text><Button mode="contained-tonal" icon="open-in-new" onPress={() => void openUpi()}>Open a UPI app</Button><TextInput mode="outlined" label="UPI reference (optional)" value={reference} onChangeText={setReference} /></> : <Text variant="bodyLarge">Hand the cash to {chitti.payeeName}, then mark it submitted. The administrator will confirm receipt.</Text>}
        <Divider /><Text variant="titleMedium">Payment photo (optional)</Text><Text variant="bodySmall">Attach a receipt, transfer screenshot, or cash handover photo. Only you and the administrator can open it.</Text>
        {paymentProof ? <View style={styles.proofSelection}><Image source={{ uri: paymentProof.uri }} style={styles.proofThumbnail} accessibilityLabel="Selected payment proof" /><View style={styles.grow}><Text numberOfLines={1}>{paymentProof.fileName || 'Selected photo'}</Text><Button compact textColor={theme.colors.error} onPress={() => setPaymentProof(undefined)}>Remove</Button></View></View> : <Button mode="outlined" icon="camera-outline" contentStyle={styles.bigButton} onPress={() => void choosePaymentProof()}>Add payment photo</Button>}
      </ScrollView></Dialog.ScrollArea><Dialog.Actions><Button disabled={busy} onPress={() => setPaymentOpen(false)}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy} onPress={() => void submitPayment()}>I have paid</Button></Dialog.Actions></Dialog></Portal>
      <Portal><Dialog visible={Boolean(proofPreviewUri)} onDismiss={() => setProofPreviewUri('')} style={styles.proofDialog}><Dialog.Title>Payment photo</Dialog.Title><Dialog.Content>{proofPreviewUri ? <Image source={{ uri: proofPreviewUri }} resizeMode="contain" style={styles.proofPreview} accessibilityLabel="Payment proof submitted by member" /> : null}</Dialog.Content><Dialog.Actions><Button onPress={() => setProofPreviewUri('')}>Close</Button></Dialog.Actions></Dialog></Portal>
      <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
      {demoMode ? <Text variant="bodySmall" style={styles.center}>Demo actions change only this browser’s local sample data.</Text> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  hero: { gap: 9 }, section: { gap: 14 }, heading: { fontWeight: '700' }, amount: { fontWeight: '800', color: '#6b261b' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 12, flexWrap: 'wrap' },
  iconTitle: { flexDirection: 'row', alignItems: 'center', gap: 10 }, recipient: { flexDirection: 'row', alignItems: 'center', gap: 12 }, grow: { flex: 1 },
  progress: { height: 10, borderRadius: 10 }, bigButton: { minHeight: 50 }, divider: { marginVertical: 12 },
  progressTrack: { height: 10, width: '100%' },
  actions: { alignItems: 'flex-end', gap: 5 }, dialog: { width: '92%', maxWidth: 480, alignSelf: 'center' }, qr: { backgroundColor: '#fff', alignSelf: 'center', padding: 12, borderRadius: 12 }, center: { textAlign: 'center' }, upi: { fontWeight: '700', fontSize: 17 },
  memberActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 }, inviteActions: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 4 }, scheduleGrid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', gap: 16 }, swapContent: { paddingHorizontal: 24, paddingVertical: 12, gap: 8 },
  paymentContent: { paddingHorizontal: 24, paddingVertical: 12, gap: 14 }, proofSelection: { flexDirection: 'row', alignItems: 'center', gap: 12 }, proofThumbnail: { width: 88, height: 88, borderRadius: 10 }, proofDialog: { width: '94%', maxWidth: 700, alignSelf: 'center' }, proofPreview: { width: '100%', height: 480 },
});

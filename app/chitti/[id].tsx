import * as Linking from 'expo-linking';
import * as ImagePicker from 'expo-image-picker';
import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Image, ScrollView, Share, StyleSheet, View, useWindowDimensions } from 'react-native';
import QRCode from 'react-native-qrcode-svg';
import { Button, Card, Checkbox, Dialog, Divider, Icon, IconButton, Portal, ProgressBar, SegmentedButtons, Snackbar, Text, TextInput, Tooltip, useTheme } from 'react-native-paper';

import { EmptyState } from '@/components/EmptyState';
import { Screen } from '@/components/Screen';
import { StatusPill } from '@/components/StatusPill';
import { UserAvatar } from '@/components/UserAvatar';
import { RankingList } from '@/components/RankingList';
import { moveRankingItem, rankingChanged, rankingSaveError } from '@/domain/ranking';
import { importedMemberError, importedMemberPositions } from '@/domain/importedMembers';
import { manualRankingEntries, parseShareAmount, sharedPositionError, sharedPositionSources } from '@/domain/sharedPositions';
import { useApp } from '@/data/AppProvider';
import type { ChittiInvitation, ManualPayoutOrderItem, PaymentMethod } from '@/domain/types';
import { env } from '@/lib/env';
import { addMonthsClamped, formatDate, formatINR, todayInIndia } from '@/lib/format';
import { brandColors } from '@/theme';

export default function ChittiDetailScreen() {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const compactRoster = width < 600;
  const { id } = useLocalSearchParams<{ id: string }>();
  const { chittis, currentUser, inviteLinks, regenerateInvitation, updateInvitation, addMemberInvitation, addImportedMemberInvitation, addCoOwnerInvitation, convertPendingChittiToExisting, cancelChitti, swapPayoutMonths, scheduleShuffle, submitContribution, getPaymentProofUrl, reviewContribution, confirmPayout, confirmPayoutShare, confirmPayoutAdjustment, demoMode } = useApp();
  const chitti = chittis.find((item) => item.id === id);
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [paymentRoundId, setPaymentRoundId] = useState<string>();
  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [editInvitationId, setEditInvitationId] = useState<string>();
  const [swapOpen, setSwapOpen] = useState(false);
  const [memberMode, setMemberMode] = useState('full');
  const [coOwnerSourceId, setCoOwnerSourceId] = useState('');
  const [coOwnerAmount, setCoOwnerAmount] = useState('');
  const [memberFormError, setMemberFormError] = useState('');
  const [existingConversionEnabled, setExistingConversionEnabled] = useState(false);
  const [completedMonths, setCompletedMonths] = useState('0');
  const [manualOrder, setManualOrder] = useState<(ManualPayoutOrderItem & { name: string; detail: string; previousPosition?: number })[]>([]);
  const [savedManualOrder, setSavedManualOrder] = useState<ManualPayoutOrderItem[]>([]);
  const [memberName, setMemberName] = useState('');
  const [memberEmail, setMemberEmail] = useState('');
  const [memberPhone, setMemberPhone] = useState('');
  const [memberPayoutPosition, setMemberPayoutPosition] = useState('');
  const [cancelOpen, setCancelOpen] = useState(false);
  const [firstSwapMember, setFirstSwapMember] = useState('');
  const [secondSwapMember, setSecondSwapMember] = useState('');
  const [busy, setBusy] = useState(false);
  const [method, setMethod] = useState<PaymentMethod>('upi');
  const [reference, setReference] = useState('');
  const [paymentProof, setPaymentProof] = useState<ImagePicker.ImagePickerAsset>();
  const [proofPreviewUri, setProofPreviewUri] = useState('');
  const [message, setMessage] = useState('');
  const [conversionFeedback, setConversionFeedback] = useState('');
  const currentRound = chitti?.rounds.find((round) => round.status === 'collecting' || round.status === 'ready_for_payout');
  const paymentRound = chitti?.rounds.find((round) => round.id === paymentRoundId) ?? currentRound;
  const currentRecipient = chitti?.members.find((member) => member.id === currentRound?.recipientMemberId);
  const myContribution = currentRound?.contributions.find((item) => item.memberId === currentUser?.id);
  const paymentContribution = paymentRound?.contributions.find((item) => item.memberId === currentUser?.id);
  const paymentAmountPaise = paymentContribution?.amountPaise ?? chitti?.monthlyAmountPaise ?? 0;
  const upiUri = chitti ? `upi://pay?pa=${encodeURIComponent(chitti.upiId)}&pn=${encodeURIComponent(chitti.payeeName)}&am=${(paymentAmountPaise / 100).toFixed(2)}&cu=INR&tn=${encodeURIComponent(`${chitti.name} month ${paymentRound?.number ?? ''}`)}` : '';

  if (!chitti || !currentUser) return <Screen title="Chitti" back><EmptyState icon="alert-circle-outline" title="Chitti not found" message="This chitti is unavailable or you no longer have access." /></Screen>;
  const confirmed = currentRound?.confirmedCount ?? currentRound?.contributions.filter((item) => item.status === 'confirmed').length ?? 0;
  const completed = chitti.rounds.filter((round) => round.status === 'completed').length;
  const catchUpRounds = chitti.rounds.filter((round) => round.adjustments?.some((item) => item.sourceMemberId === currentUser.id && item.status !== 'paid'));
  const catchUpReviews = chitti.rounds.flatMap((round) => round.status === 'completed'
    ? round.contributions.filter((item) => item.status === 'submitted').map((contribution) => ({ round, contribution }))
    : []);
  const adjustments = chitti.rounds.flatMap((round) => (round.adjustments ?? []).map((adjustment) => ({ round, adjustment })));
  const rejectedMembers = chitti.members.filter((member) => member.approval === 'rejected');
  const swappableMembers = chitti.members.filter((member) => !member.isAdmin
    && member.payoutPosition
    && chitti.members.filter((candidate) => candidate.payoutPosition === member.payoutPosition).length === 1
    && chitti.rounds.some((round) => round.number === member.payoutPosition && round.status !== 'completed' && round.payoutStatus !== 'paid'));
  const eligibleShareOwners = sharedPositionSources(chitti);
  const selectedShareOwner = eligibleShareOwners.find((owner) => owner.key === coOwnerSourceId);
  const shareAmountPaise = parseShareAmount(coOwnerAmount);
  const availableImportedPositions = importedMemberPositions(chitti);
  const addingImportedPosition = chitti.isImported && chitti.status === 'inviting';
  const extendingImportedSchedule = addingImportedPosition && availableImportedPositions[0] === chitti.memberCount + 1;
  const canAddFullMember = currentUser.role === 'admin'
    && !['completed', 'cancelled'].includes(chitti.status)
    && (!chitti.isImported || chitti.status === 'active' || (addingImportedPosition && availableImportedPositions.length > 0));
  const canAddMember = canAddFullMember || (currentUser.role === 'admin' && eligibleShareOwners.length > 0);
  const canCancelChitti = currentUser.role === 'admin' && ['draft', 'inviting', 'ready', 'shuffle_scheduled', 'awaiting_approval'].includes(chitti.status);
  const canEditPendingOrder = canCancelChitti && chitti.rounds.length === 0;
  const expectedManualOrderCount = manualRankingEntries(chitti).length;
  const roster = [
    ...chitti.members.map((member) => ({ kind: 'member' as const, value: member })),
    ...(currentUser.role === 'admin' ? (chitti.invitations ?? []).filter((invite) => invite.status === 'pending').map((invite) => ({ kind: 'invitation' as const, value: invite })) : []),
  ].sort((a, b) => Number(b.kind === 'member' && b.value.isAdmin) - Number(a.kind === 'member' && a.value.isAdmin)
    || (a.value.payoutPosition ?? 99) - (b.value.payoutPosition ?? 99) || a.value.name.localeCompare(b.value.name));
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

  const shareInvite = async (memberName: string, token?: string) => {
    const actualToken = token ?? `demo-${encodeURIComponent(chitti.id)}-${encodeURIComponent(memberName)}`;
    const url = invitationUrl(actualToken);
    await Share.share({ title: `Join ${chitti.name}`, message: `Hi ${memberName}, you are privately invited to join ${chitti.name} on Chitti. Open this unique link: ${url}`, url });
  };

  const ensureInvitationToken = async (invitationId: string) => inviteLinks[invitationId] ?? regenerateInvitation(invitationId);

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
    setMemberPayoutPosition('');
    setMemberMode('full');
    setCoOwnerSourceId('');
    setCoOwnerAmount('');
    setMemberFormError('');
  };

  const openMemberForm = () => {
    setMemberFormError('');
    setMemberPayoutPosition(addingImportedPosition ? String(availableImportedPositions[0] ?? '') : '');
    setMemberMode(canAddFullMember ? 'full' : 'shared');
    setCoOwnerSourceId(eligibleShareOwners[0]?.key ?? '');
    setAddMemberOpen(true);
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
    const payoutPosition = Number(memberPayoutPosition);
    if (addingImportedPosition && !availableImportedPositions.includes(payoutPosition)) {
      return setMessage('Choose one of the available payout months.');
    }
    const member = { name: memberName.trim(), email: memberEmail.trim(), phone: memberPhone.trim() };
    setBusy(true);
    try {
      if (addingImportedPosition) {
        const result = await addImportedMemberInvitation(chitti.id, member, payoutPosition);
        closeMemberForm();
        setMessage(`Invitation created for payout month ${result.payoutPosition}.${extendingImportedSchedule ? ' The total months and end date have been updated; the existing ranking is unchanged.' : ''}`);
        return;
      }
      const result = await addMemberInvitation(chitti.id, member);
      closeMemberForm();
      setMessage(result.lateJoin
        ? 'Late-member invitation created. Their payout will be added as the final month after they join.'
        : result.shuffleReset
          ? 'Invitation created. The unfinished shuffle was cancelled; shuffle again after the member joins.'
          : 'Member invitation created. Use Share link in Members to send it through WhatsApp.');
    } catch (value) {
      setMessage(addingImportedPosition ? importedMemberError(value) : value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not add this member.');
    } finally { setBusy(false); }
  };

  const deletePendingChitti = async () => {
    setBusy(true);
    try {
      await cancelChitti(chitti.id);
      setCancelOpen(false);
      router.replace('/dashboard');
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not delete this chitti.');
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
      setMessage('Invitation updated. The previous link no longer works. Use Share link to send the new link.');
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

  const createCoOwnerInvitation = async () => {
    const source = selectedShareOwner;
    if (!source?.payoutPosition) return setMemberFormError('Choose the existing owner whose amount will be split.');
    if (!shareAmountPaise || shareAmountPaise >= source.availableAmountPaise) {
      return setMemberFormError(`Enter a positive monthly amount below ${formatINR(source.availableAmountPaise)}, with at most two decimal places. Leave at least ₹0.01 for the original owner.`);
    }
    if (memberName.trim().length < 2 || !memberEmail.includes('@') || memberPhone.trim().length < 8) {
      return setMemberFormError('Enter this co-owner’s name, Google sign-in email, and phone number. Each person needs their own invitation.');
    }
    setMemberFormError('');
    setBusy(true);
    try {
      const member = { name: memberName.trim(), email: memberEmail.trim(), phone: memberPhone.trim() };
      const result = await addCoOwnerInvitation(chitti.id, source, shareAmountPaise, member);
      closeMemberForm();
      setMessage(`Shared invitation created for month ${result.payoutPosition} (${formatINR(result.amountPaise)}/month). Use Share link in Members to send it through WhatsApp. Add another co-owner by selecting the same original owner again.`);
    } catch (value) {
      setMemberFormError(sharedPositionError(value));
    } finally { setBusy(false); }
  };

  const buildManualOrder = () => manualRankingEntries(chitti);

  const toggleExistingConversion = () => {
    const next = !existingConversionEnabled;
    setExistingConversionEnabled(next);
    setConversionFeedback('');
    if (next) {
      const order = buildManualOrder();
      setManualOrder(order);
      setSavedManualOrder(order);
      setCompletedMonths(String(chitti.importedCompletedMonths ?? 0));
    }
  };

  const moveManualOrder = (fromIndex: number, toIndex: number) => {
    if (busy) return;
    setManualOrder((current) => moveRankingItem(current, fromIndex, toIndex));
    setConversionFeedback('');
  };

  const saveExistingConversion = async () => {
    const completed = Number(completedMonths);
    if (!Number.isInteger(completed) || completed < 0 || completed > chitti.memberCount) {
      const feedback = `Completed months must be between 0 and ${chitti.memberCount}.`;
      setConversionFeedback(feedback);
      return setMessage(feedback);
    }
    if (manualOrder.length !== expectedManualOrderCount) {
      const feedback = 'Arrange every member and pending invitation before saving the existing chitti.';
      setConversionFeedback(feedback);
      return setMessage(feedback);
    }
    setBusy(true);
    setConversionFeedback('Saving the existing chitti and its payout order…');
    try {
      await convertPendingChittiToExisting(chitti.id, completed, manualOrder.map(({ kind, id }) => ({ kind, id })));
      setExistingConversionEnabled(false);
      setConversionFeedback('Payout ranking saved. You can edit it again while the chitti is pending. Joined members have been notified.');
      setMessage('Payout ranking saved. Joined members have been notified.');
    } catch (value) {
      const feedback = rankingSaveError(value);
      setConversionFeedback(feedback);
      setMessage(feedback);
    } finally { setBusy(false); }
  };

  const confirmSharedPayout = async (shareId: string, recipientName: string) => {
    setBusy(true);
    try {
      await confirmPayoutShare(chitti.id, currentRound!.id, shareId);
      setMessage(`Payout to ${recipientName} confirmed. Confirm the other co-owner separately.`);
    } catch (value) {
      setMessage(value && typeof value === 'object' && 'message' in value ? String(value.message) : 'Could not confirm this payout.');
    } finally { setBusy(false); }
  };

  return (
    <Screen title={chitti.name} back action={<Button onPress={() => router.push('/dashboard')}>Home</Button>}>
      <Card mode="contained" style={{ backgroundColor: theme.colors.primaryContainer }}><Card.Content style={styles.hero}>
        <View style={styles.rowBetween}><StatusPill status={chitti.status} /><Text variant="labelLarge">{chitti.memberCount} months</Text></View>
        <Text variant="headlineMedium" style={styles.amount}>{formatINR(chitti.monthlyAmountPaise * chitti.memberCount)}</Text>
        <Text variant="bodyLarge">Monthly pot · {formatINR(chitti.monthlyAmountPaise)} per payout position, split between its owners</Text>
        {chitti.description ? <Text>{chitti.description}</Text> : null}
      </Card.Content></Card>

      <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Schedule</Text>
        <View style={styles.scheduleGrid}><View><Text variant="labelLarge">Starts</Text><Text>{formatDate(chitti.startDate ?? chitti.firstDueDate)}</Text></View><View><Text variant="labelLarge">First due date</Text><Text>{formatDate(chitti.firstDueDate)}</Text></View><View><Text variant="labelLarge">Ends</Text><Text>{formatDate(chitti.endDate ?? addMonthsClamped(chitti.firstDueDate, chitti.memberCount - 1))}</Text></View></View>
        <Text>Unpaid members receive an in-app reminder every day while the current collection period is open.</Text>
      </Card.Content></Card>

      {chitti.isImported ? <Card mode="outlined"><Card.Content style={styles.section}>
        <View style={styles.iconTitle}><Icon source="history" size={26} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Existing chitti</Text></View>
        <Text>{chitti.importedCompletedMonths ?? 0} of {chitti.memberCount} months were marked completed when this chitti was added. Its saved payout order is used without a shuffle.</Text>
        <Text>Earlier individual payments are unassessed, so they do not increase missed-due counts or reduce anyone’s reliability score.</Text>
        {chitti.status === 'inviting' && availableImportedPositions.some((position) => position <= chitti.memberCount) ? <Text variant="titleMedium">Unassigned payout months: {availableImportedPositions.filter((position) => position <= chitti.memberCount).join(', ')}</Text> : null}
      </Card.Content></Card> : null}

      {canEditPendingOrder ? <Card mode="outlined"><Card.Content style={styles.section}>
        {chitti.isImported ? <Button icon="sort-numeric-ascending" mode="outlined" disabled={busy} onPress={toggleExistingConversion}>{existingConversionEnabled ? 'Cancel ranking changes' : 'Edit payout ranking'}</Button> : <Checkbox.Item
          label="This chitti has already started"
          status={existingConversionEnabled ? 'checked' : 'unchecked'}
          onPress={toggleExistingConversion}
          disabled={busy}
          position="leading"
          mode="android"
          style={styles.checkboxRow}
          labelStyle={styles.checkboxLabel}
        />}
        <Text>{chitti.isImported ? 'You can rearrange the saved ranking until this chitti activates after everyone joins. The administrator stays first. Unassigned months and the recorded completed-month count are preserved.' : 'Use this only when the payout order was already decided outside the app. The random shuffle and approval step will be removed.'}</Text>
        {existingConversionEnabled ? <View style={styles.section}>
          {!chitti.isImported ? <TextInput
            mode="outlined"
            label="Months already completed"
            value={completedMonths}
            onChangeText={(value) => /^\d*$/.test(value) && setCompletedMonths(value)}
            keyboardType="numeric"
            disabled={busy}
          /> : <Text>Months already completed: {chitti.importedCompletedMonths ?? 0}</Text>}
          <View>
            <Text variant="titleMedium" style={styles.heading}>Manual payout ranking</Text>
            <Text>Drag the grip to change the order. On a phone, hold the grip briefly, then slide and release. You can also use the arrow buttons. The administrator remains fixed at position 1.</Text>
          </View>
          <View style={[styles.rankRow, styles.fixedRankRow]}>
            <View style={styles.rankNumber}><Text variant="titleMedium">1</Text></View>
            <View style={styles.grow}><Text variant="titleMedium">{chitti.members.find((member) => member.isAdmin)?.name ?? currentUser.name} · Admin</Text><Text>Fixed first payout</Text></View>
            <Icon source="lock-outline" size={22} color={theme.colors.primary} />
          </View>
          <RankingList disabled={busy} onMove={moveManualOrder} rows={manualOrder.map((item, index) => ({
            key: `${item.kind}:${item.id}`,
            name: item.name,
            detail: `${item.kind === 'invitation' ? 'Pending invitation' : 'Accepted'} · ${item.detail}`,
            position: chitti.isImported ? (buildManualOrder()[index]?.previousPosition ?? index + 2) : index + 2,
          }))} />
          <Text variant="bodySmall">You are assigning {manualOrder.length + 1} of {chitti.memberCount} positions now. Any empty positions can be filled later with “Add member”.</Text>
          {manualOrder.length !== expectedManualOrderCount ? <Text style={{ color: theme.colors.error }}>The list changed. Turn this option off and on again to refresh every current member and invitation.</Text> : null}
          {rankingChanged(savedManualOrder, manualOrder) ? <Text accessibilityLiveRegion="polite">You have unsaved position changes.</Text> : null}
          {(!chitti.isImported || rankingChanged(savedManualOrder, manualOrder)) ? <Button mode="contained" icon="content-save-check-outline" loading={busy} disabled={busy || manualOrder.length !== expectedManualOrderCount} onPress={() => void saveExistingConversion()}>{rankingChanged(savedManualOrder, manualOrder) ? 'Save Updated Position' : 'Save existing chitti and order'}</Button> : null}
        </View> : null}
        {conversionFeedback ? <View accessibilityLiveRegion="polite" style={styles.inlineFeedback}><Icon source={busy ? 'progress-clock' : 'information-outline'} size={22} color={brandColors.black} /><Text style={styles.feedbackText}>{conversionFeedback}</Text></View> : null}
      </Card.Content></Card> : null}

      {currentUser.role === 'admin' && chitti.status === 'ready' && rejectedMembers.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Reshuffle requested</Text>
        <Text>The following member rejected the previous payout order:</Text>
        {rejectedMembers.map((member, index) => <View key={member.id}>{index ? <Divider style={styles.divider} /> : null}<Text variant="titleMedium">{member.name}</Text><Text>{member.approvalReason || 'No reason was recorded.'}</Text></View>)}
      </Card.Content></Card> : null}

      {!existingConversionEnabled && !chitti.isImported && ['ready', 'shuffle_scheduled', 'awaiting_approval'].includes(chitti.status) ? (
        <Card mode="elevated"><Card.Content style={styles.section}>
          <View style={styles.iconTitle}><Icon source="shuffle-variant" size={28} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payout order</Text></View>
          <Text>{chitti.status === 'ready' ? 'Everyone has joined. Schedule a fair, server-side shuffle.' : chitti.status === 'shuffle_scheduled' ? 'The shuffle is scheduled and ready to begin.' : 'The order has been revealed and needs unanimous approval.'}</Text>
          {currentUser.role === 'admin' && chitti.status === 'ready' ? <Button mode="contained" onPress={() => void scheduleShuffle(chitti.id).then(() => router.push(`/chitti/${chitti.id}/shuffle`))}>Schedule now</Button> : <Button mode="contained" onPress={() => router.push(`/chitti/${chitti.id}/shuffle`)}>Open live shuffle</Button>}
        </Card.Content></Card>
      ) : null}

      {chitti.status === 'active' && currentRound ? (
        <>
          <Card mode="elevated"><Card.Content style={styles.section}>
            <Text variant="labelLarge">MONTH {currentRound.number} OF {chitti.memberCount}</Text>
            {(currentRound.payoutShares?.length ?? 0) > 1 ? <View style={styles.section}>
              <Text variant="bodyMedium">Current co-owners</Text>
              {currentRound.payoutShares?.map((share) => { const recipient = chitti.members.find((member) => member.id === share.recipientMemberId); return <View key={share.id} style={styles.rowBetween}><View style={styles.recipient}><UserAvatar name={recipient?.name ?? '?'} uri={recipient?.avatarUri} size={42} /><View><Text variant="titleMedium">{recipient?.name}</Text><Text>{formatINR(share.amountPaise)} payout</Text></View></View><StatusPill status={share.status} /></View>; })}
            </View> : <View style={styles.recipient}><UserAvatar name={currentRecipient?.name ?? '?'} uri={currentRecipient?.avatarUri} size={52} /><View style={styles.grow}><Text variant="bodyMedium">Current recipient</Text><Text variant="headlineSmall" style={styles.heading}>{currentRecipient?.name}</Text></View></View>}
            <View style={styles.rowBetween}><Text>Due {formatDate(currentRound.dueDate)}</Text><Text>{confirmed}/{currentRound.contributions.length} confirmed</Text></View>
            <View style={styles.progressTrack}><ProgressBar progress={confirmed / Math.max(1, currentRound.contributions.length)} style={styles.progress} /></View>
            {myContribution ? <View style={styles.rowBetween}><Text variant="titleMedium">Your payment</Text><StatusPill status={myContribution.status} /></View> : null}
            {myContribution && ['due', 'rejected', 'overdue'].includes(myContribution.status) ? <Button mode="contained" icon="bank-transfer" contentStyle={styles.bigButton} onPress={() => openPayment(currentRound.id)}>Pay {formatINR(myContribution.amountPaise ?? chitti.monthlyAmountPaise)}</Button> : null}
            {currentRound.payoutStatus === 'ready' && currentUser.role === 'admin' ? (currentRound.payoutShares?.length
              ? <View style={styles.payoutConfirmations}>
                <Text variant="titleMedium" style={styles.heading}>Confirm each co-owner payout separately</Text>
                <Text>The round completes only after every proportional payout is confirmed.</Text>
                {currentRound.payoutShares.map((share) => {
                  const recipient = chitti.members.find((member) => member.id === share.recipientMemberId);
                  return share.status === 'ready'
                    ? <Button key={share.id} mode="contained" icon="cash-check" loading={busy} disabled={busy} contentStyle={styles.bigButton} onPress={() => void confirmSharedPayout(share.id, recipient?.name ?? 'co-owner')}>Confirm {formatINR(share.amountPaise)} delivered to {recipient?.name}</Button>
                    : <View key={share.id} style={styles.rowBetween}><Text>{recipient?.name} · {formatINR(share.amountPaise)}</Text><StatusPill status={share.status} /></View>;
                })}
              </View>
              : <Button mode="contained" icon="cash-check" contentStyle={styles.bigButton} onPress={() => void confirmPayout(chitti.id, currentRound.id)}>Confirm payout delivered</Button>) : null}
          </Card.Content></Card>

          {currentUser.role === 'admin' ? (
            <Card mode="outlined"><Card.Content style={styles.section}>
              <Text variant="titleLarge" style={styles.heading}>Payment review</Text>
              {currentRound.contributions.map((contribution, index) => {
                const member = chitti.members.find((item) => item.id === contribution.memberId)!;
                return <View key={contribution.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View style={styles.recipient}><UserAvatar name={member.name} uri={member.avatarUri} size={38} /><View><Text variant="titleMedium">{member.name} · {formatINR(contribution.amountPaise ?? chitti.monthlyAmountPaise)}</Text><Text>{contribution.method?.toUpperCase() ?? 'Not submitted'}{contribution.reference ? ` · ${contribution.reference}` : ''}</Text>{contribution.proofPath ? <Button compact icon="image-outline" onPress={() => void viewPaymentProof(contribution.proofPath!)}>View payment photo</Button> : null}</View></View><View style={styles.actions}><StatusPill status={contribution.status} />{contribution.status === 'submitted' ? <><Button compact onPress={() => void reviewContribution(chitti.id, currentRound.id, contribution.id, false)}>Reject</Button><Button compact mode="contained-tonal" onPress={() => void reviewContribution(chitti.id, currentRound.id, contribution.id, true)}>Confirm received</Button></> : null}</View></View></View>;
              })}
            </Card.Content></Card>
          ) : null}
        </>
      ) : null}

      {!['active', 'completed'].includes(chitti.status) ? <Card mode="outlined"><Card.Content style={styles.section}><View style={styles.iconTitle}><Icon source="bank-transfer" size={26} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payments are not open yet</Text></View><Text>{chitti.isImported ? 'Payment tracking opens automatically after every invited member joins. The saved payout order will not be shuffled.' : 'The “I have paid” option appears after everyone accepts the payout order and the chitti becomes active.'}</Text></Card.Content></Card> : null}
      {chitti.status === 'active' && !currentRound ? <Card mode="outlined"><Card.Content style={styles.section}><View style={styles.iconTitle}><Icon source="calendar-clock" size={26} color={theme.colors.primary} /><Text variant="titleLarge" style={styles.heading}>Payments start {formatDate(chitti.startDate)}</Text></View><Text>The first “Pay / record payment” button appears when the first collection period opens.</Text></Card.Content></Card> : null}

      {catchUpRounds.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Catch-up contributions</Text>
        <Text>You joined after this chitti began. Submit each missed contribution separately.</Text>
        {catchUpRounds.map((round, index) => {
          const contribution = round.contributions.find((item) => item.memberId === currentUser.id);
          return <View key={round.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">Month {round.number}</Text><Text>{formatDate(round.dueDate)} · {formatINR(contribution?.amountPaise ?? chitti.monthlyAmountPaise)}</Text></View><View style={styles.actions}>{contribution ? <StatusPill status={contribution.status} /> : null}{contribution && ['due', 'rejected', 'overdue'].includes(contribution.status) ? <Button mode="contained-tonal" onPress={() => openPayment(round.id)}>Pay catch-up</Button> : null}</View></View></View>;
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
        <View style={styles.rowBetween}><Text variant="titleLarge" style={styles.heading}>Members</Text><Text>{chitti.members.filter((item) => item.joined).length} joined · {chitti.memberCount} payout months</Text></View>
        {canAddMember ? <View style={styles.memberActions}><Button icon="account-plus" mode="contained-tonal" onPress={openMemberForm}>Add member</Button>{eligibleShareOwners.length > 0 ? <Button icon="account-multiple-plus" mode="outlined" onPress={() => { openMemberForm(); setMemberMode('shared'); }}>Add co-owner</Button> : null}{chitti.status === 'active' && swappableMembers.length >= 2 ? <Button icon="swap-horizontal" mode="outlined" onPress={() => setSwapOpen(true)}>Swap months</Button> : null}</View> : null}
        {currentUser.role === 'admin' && addingImportedPosition && availableImportedPositions.length === 0 ? <Text variant="bodySmall">All 50 payout months are assigned. This chitti has reached the member limit.</Text> : null}
        {roster.map((entry, index) => {
          const person = entry.value;
          return <View key={`${entry.kind}:${person.id}`}>
            {index ? <Divider style={styles.divider} /> : null}
            <View style={styles.rowBetween}>
              <View style={[styles.recipient, styles.rosterPerson]}>
                {person.payoutPosition ? <View style={styles.rankNumber}><Text variant="titleMedium">{person.payoutPosition}</Text></View> : null}
                <UserAvatar name={person.name} uri={entry.kind === 'member' ? entry.value.avatarUri : undefined} size={40} />
                <View style={styles.grow}>
                  <Text variant="titleMedium">{person.name}{entry.kind === 'member' && entry.value.isAdmin ? ' · Admin' : ''}</Text>
                  <Text>{person.payoutPosition ? `Payout month ${person.payoutPosition}` : 'Month not assigned'}</Text>
                  {entry.kind === 'member' && (entry.value.contributionAmountPaise ?? chitti.monthlyAmountPaise) < chitti.monthlyAmountPaise ? <Text>{formatINR(entry.value.contributionAmountPaise!)}/month · Shared position</Text> : null}
                  {entry.kind === 'invitation' ? <><Text>{entry.value.email} · {entry.value.phone}</Text>{entry.value.coOwnerAmountPaise ? <Text>{formatINR(entry.value.coOwnerAmountPaise)}/month · Co-owner</Text> : null}</> : null}
                </View>
              </View>
              <View style={[styles.rosterControls, compactRoster && styles.compactRosterControls]}>
                <StatusPill iconOnly={compactRoster} status={entry.kind === 'member' && entry.value.joined ? 'accepted' : 'pending_invitation'} />
                {entry.kind === 'invitation' ? compactRoster ? <View style={styles.inviteActions}>
                  <Tooltip title="Edit invitation"><IconButton icon="pencil-outline" size={22} iconColor={brandColors.black} style={styles.compactAction} accessibilityLabel={`Edit invitation for ${person.name}`} onPress={() => openEditInvitation(entry.value)} /></Tooltip>
                  <Tooltip title="Share link"><IconButton icon="share-variant" size={22} iconColor={brandColors.black} style={styles.compactAction} accessibilityLabel={`Share invitation link for ${person.name}`} onPress={() => void sharePendingInvitation(entry.value)} /></Tooltip>
                </View> : <View style={styles.inviteActions}>
                  <Button compact textColor={brandColors.black} icon="pencil-outline" onPress={() => openEditInvitation(entry.value)}>Edit</Button>
                  <Button compact textColor={brandColors.black} icon="share-variant" onPress={() => void sharePendingInvitation(entry.value)}>Share link</Button>
                </View> : demoMode && currentUser.role === 'admin' && !entry.value.isAdmin && chitti.status !== 'active' ? <Button compact icon="share-variant" onPress={() => void shareInvite(person.name)}>Share</Button> : null}
              </View>
            </View>
          </View>;
        })}
        {currentUser.role === 'admin' && chitti.invitations?.some((invite) => invite.status === 'pending') ? <Text variant="bodySmall">Regenerating an invitation link invalidates the previous link.</Text> : null}
      </Card.Content></Card>

      {canCancelChitti ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Pending chitti controls</Text>
        <Text>This chitti has not started, so the administrator can delete it. Pending invitations will stop working, it will disappear from dashboards, and a cancelled audit record will remain for safety.</Text>
        <Button mode="outlined" icon="delete-outline" onPress={() => setCancelOpen(true)}>Delete pending chitti</Button>
      </Card.Content></Card> : null}

      {['active', 'completed'].includes(chitti.status) && chitti.rounds.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}><Text variant="titleLarge" style={styles.heading}>Schedule</Text>{chitti.rounds.map((round, index) => { const recipients = round.payoutShares?.map((share) => chitti.members.find((member) => member.id === share.recipientMemberId)?.name).filter(Boolean); const recipient = chitti.members.find((member) => member.id === round.recipientMemberId); return <View key={round.id}>{index ? <Divider style={styles.divider} /> : null}<View style={styles.rowBetween}><View><Text variant="titleMedium">Month {round.number} · {recipients?.length ? recipients.join(' + ') : recipient?.name}</Text><Text>{formatDate(round.dueDate)}</Text></View><StatusPill status={round.status === 'completed' ? 'completed' : round.status} /></View></View>; })}<Text>{chitti.memberCount - completed} months remaining</Text></Card.Content></Card> : null}

      <Portal><Dialog visible={addMemberOpen} onDismiss={closeMemberForm} style={styles.dialog}><Dialog.Title>Add a member</Dialog.Title><Dialog.ScrollArea><ScrollView contentContainerStyle={styles.paymentContent}>
        {(addingImportedPosition || chitti.status === 'active') ? <SegmentedButtons value={memberMode} onValueChange={setMemberMode} buttons={[{ value: 'full', label: 'Full position', disabled: !canAddFullMember }, { value: 'shared', label: 'Shared position' }]} /> : null}
        {memberMode === 'shared' ? <>
          <Text variant="titleMedium">Share an existing position</Text>
          <Text>Choose the owner whose monthly amount will be split. There is no fixed limit on co-owners. Their amounts must add up to {formatINR(chitti.monthlyAmountPaise)} for this position. The total months and monthly pot stay unchanged.</Text>
          {eligibleShareOwners.length === 0 ? <Text>No position is currently available to share. An owner must have an unpaid payout and enough unreserved contribution left.</Text> : null}
          {eligibleShareOwners.map((owner) => <Button key={owner.key} mode={coOwnerSourceId === owner.key ? 'contained-tonal' : 'outlined'} onPress={() => setCoOwnerSourceId(owner.key)}>{owner.name} · Month {owner.payoutPosition} · {owner.kind === 'invitation' ? 'Invited' : 'Joined'}</Button>)}
          <TextInput mode="outlined" label="New co-owner monthly amount (₹)" value={coOwnerAmount} onChangeText={setCoOwnerAmount} keyboardType="decimal-pad" />
          {selectedShareOwner ? <Text>{formatINR(selectedShareOwner.availableAmountPaise)} is available from this owner, after other invitations. {shareAmountPaise && shareAmountPaise < selectedShareOwner.availableAmountPaise ? `New co-owner: ${formatINR(shareAmountPaise)}/month. Original owner remaining: ${formatINR(selectedShareOwner.availableAmountPaise - shareAmountPaise)}/month.` : ''}</Text> : null}
          <Text variant="bodySmall">Add one person at a time. To add more, create their invitation, reopen Add co-owner, and select the same original owner. For thirds of ₹20,000, enter ₹6,666.67 for each of two co-owners; the original owner keeps ₹6,666.66.</Text>
          <Text variant="bodySmall">Each co-owner receives a private invitation. You confirm their proportional payouts separately. Co-owners move together when the ranking changes.</Text>
        </> : <Text>{addingImportedPosition
          ? extendingImportedSchedule
            ? `All ${chitti.memberCount} positions are assigned. This invitation adds payout month ${chitti.memberCount + 1}, increasing the total months and monthly pot and extending the end date to ${formatDate(addMonthsClamped(chitti.firstDueDate, chitti.memberCount))}. The contribution per member, existing ranking, and recorded completed months stay unchanged.`
            : 'Assign this member to one of the payout months that is still empty. The total number of months will not change.'
          : chitti.status === 'active'
          ? 'After joining, this member receives the final payout month and owes every elapsed contribution.'
          : ['shuffle_scheduled', 'awaiting_approval'].includes(chitti.status)
            ? 'Adding a member will cancel the unfinished shuffle. Shuffle everyone again after the new member joins.'
            : 'The member will join through a private invitation.'}</Text>}
        <TextInput mode="outlined" label="Full name" value={memberName} onChangeText={setMemberName} />
        <TextInput mode="outlined" label="Google email" value={memberEmail} onChangeText={setMemberEmail} autoCapitalize="none" keyboardType="email-address" />
        <Text variant="bodySmall">Email identifies the Google account allowed to join; no email invitation is sent. Use Share link to send the invitation through WhatsApp.</Text>
        <TextInput mode="outlined" label="Phone number" value={memberPhone} onChangeText={setMemberPhone} keyboardType="phone-pad" />
        {memberMode === 'full' && addingImportedPosition ? <><TextInput mode="outlined" label="Payout month" value={memberPayoutPosition} onChangeText={(value) => /^\d*$/.test(value) && setMemberPayoutPosition(value)} keyboardType="numeric" editable={!extendingImportedSchedule} /><Text variant="bodySmall">{extendingImportedSchedule ? 'The new member starts at the last position. You can edit the payout ranking before activation.' : `Available months: ${availableImportedPositions.join(', ')}`}</Text></> : null}
        {memberFormError ? <Text accessibilityRole="alert">{memberFormError}</Text> : null}
      </ScrollView></Dialog.ScrollArea><Dialog.Actions><Button onPress={closeMemberForm}>Cancel</Button><Button mode="contained" loading={busy} disabled={busy || (memberMode === 'shared' && !selectedShareOwner)} onPress={() => void (memberMode === 'shared' ? createCoOwnerInvitation() : addMember())}>{memberMode === 'shared' ? 'Create shared invitation' : 'Create invitation'}</Button></Dialog.Actions></Dialog></Portal>

      <Portal><Dialog visible={cancelOpen} onDismiss={() => setCancelOpen(false)} style={styles.dialog}><Dialog.Title>Delete this pending chitti?</Dialog.Title><Dialog.Content style={styles.section}>
        <Text>This removes it from everyone’s dashboard and revokes all pending invitation links. Active and completed chittis cannot be deleted.</Text>
      </Dialog.Content><Dialog.Actions><Button disabled={busy} onPress={() => setCancelOpen(false)}>Keep chitti</Button><Button mode="contained" icon="delete-outline" loading={busy} disabled={busy} onPress={() => void deletePendingChitti()}>Delete</Button></Dialog.Actions></Dialog></Portal>

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

      <Portal><Dialog visible={paymentOpen} onDismiss={() => setPaymentOpen(false)} style={styles.dialog}><Dialog.Title>Pay / record {formatINR(paymentAmountPaise)}{paymentRound ? ` · Month ${paymentRound.number}` : ''}</Dialog.Title><Dialog.ScrollArea><ScrollView contentContainerStyle={styles.paymentContent}>
        <SegmentedButtons value={method} onValueChange={(value) => setMethod(value as PaymentMethod)} buttons={[{ value: 'upi', label: 'UPI / GPay', icon: 'qrcode' }, { value: 'cash', label: 'Cash', icon: 'cash' }]} />
        {method === 'upi' ? <><View style={styles.qr}><QRCode value={upiUri} size={176} color="#111111" backgroundColor="#ffffff" /></View><Text style={styles.center}>Pay to {chitti.payeeName}</Text><Text selectable style={[styles.upi, styles.center]}>{chitti.upiId}</Text><Button mode="contained-tonal" icon="open-in-new" onPress={() => void openUpi()}>Open a UPI app</Button><TextInput mode="outlined" label="UPI reference (optional)" value={reference} onChangeText={setReference} /></> : <Text variant="bodyLarge">Hand the cash to {chitti.payeeName}, then mark it submitted. The administrator will confirm receipt.</Text>}
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
  hero: { gap: 9 }, section: { gap: 14 }, heading: { fontWeight: '700' }, amount: { fontWeight: '800', color: '#111111' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 12, flexWrap: 'wrap' },
  iconTitle: { flexDirection: 'row', alignItems: 'center', gap: 10 }, recipient: { flexDirection: 'row', alignItems: 'center', gap: 12 }, grow: { flex: 1 },
  progress: { height: 10, borderRadius: 10 }, bigButton: { minHeight: 50 }, divider: { marginVertical: 12 },
  progressTrack: { height: 10, width: '100%' },
  actions: { alignItems: 'flex-end', gap: 5 }, dialog: { width: '92%', maxWidth: 480, alignSelf: 'center' }, qr: { backgroundColor: '#fff', alignSelf: 'center', padding: 12, borderRadius: 12 }, center: { textAlign: 'center' }, upi: { fontWeight: '700', fontSize: 17 },
  memberActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 }, inviteActions: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 4 }, scheduleGrid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', gap: 16 }, swapContent: { paddingHorizontal: 24, paddingVertical: 12, gap: 8 },
  paymentContent: { paddingHorizontal: 24, paddingVertical: 12, gap: 14 }, proofSelection: { flexDirection: 'row', alignItems: 'center', gap: 12 }, proofThumbnail: { width: 88, height: 88, borderRadius: 10 }, proofDialog: { width: '94%', maxWidth: 700, alignSelf: 'center' }, proofPreview: { width: '100%', height: 480 },
  checkboxRow: { paddingHorizontal: 0 }, checkboxLabel: { fontSize: 18, fontWeight: '700' },
  rankRow: { minHeight: 64, flexDirection: 'row', alignItems: 'center', gap: 10, borderWidth: 1, borderColor: '#C79A33', padding: 10, backgroundColor: '#ffffff' },
  fixedRankRow: { backgroundColor: '#F5EDDB' },
  rankNumber: { width: 36, height: 36, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#C79A33', backgroundColor: '#ffffff' },
  rosterPerson: { flexGrow: 1, flexBasis: 220, minWidth: 0 },
  rosterControls: { alignItems: 'flex-end', gap: 8, flexShrink: 1, marginLeft: 'auto' },
  compactRosterControls: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6 },
  compactAction: { width: 44, height: 44, margin: 0 },
  inlineFeedback: { flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12, backgroundColor: '#F5EDDB', borderLeftWidth: 4, borderLeftColor: '#C79A33' },
  feedbackText: { flex: 1 },
  payoutConfirmations: { gap: 10, paddingTop: 4 },
});

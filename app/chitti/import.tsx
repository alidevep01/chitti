import { zodResolver } from '@hookform/resolvers/zod';
import { router } from 'expo-router';
import { useState } from 'react';
import { Controller, useFieldArray, useForm, useWatch } from 'react-hook-form';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Divider, HelperText, Snackbar, Text, TextInput } from 'react-native-paper';
import { DatePickerModal, en, registerTranslation } from 'react-native-paper-dates';
import { z } from 'zod';

import { Screen } from '@/components/Screen';
import { UserAvatar } from '@/components/UserAvatar';
import { useApp } from '@/data/AppProvider';
import { addMonthsClamped, formatDate, formatINR, toPaise } from '@/lib/format';

registerTranslation('en', en);

function isoToDate(value: string): Date {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year!, month! - 1, day!, 12);
}

function dateToIso(value: Date): string {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

const completeMemberSchema = z.object({
  name: z.string().trim().min(2, 'Enter the member name'),
  email: z.email('Enter a valid Google email').transform((value) => value.toLowerCase()),
  phone: z.string().trim().min(8, 'Enter a valid phone number'),
});

const memberDraftSchema = z.object({ name: z.string(), email: z.string(), phone: z.string() });

const schema = z.object({
  name: z.string().trim().min(3, 'Enter a name for this chitti'),
  description: z.string().trim().max(200).optional(),
  monthlyAmount: z.string().refine((value) => Number(value) >= 100, 'Enter an amount of at least ₹100'),
  memberCount: z.number().int('Enter a whole number').min(2, 'At least 2 members are required').max(50, 'A chitti can have at most 50 members'),
  completedMonths: z.number().int('Enter a whole number').min(0, 'Completed months cannot be negative'),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Choose the original start date'),
  firstDueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Choose the original first due date'),
  upiId: z.string().trim().min(3, 'Enter the administrator UPI ID'),
  payeeName: z.string().trim().min(2, 'Enter the UPI payee name'),
  invites: z.array(memberDraftSchema),
}).superRefine((value, context) => {
  if (value.completedMonths > value.memberCount) context.addIssue({ code: 'custom', path: ['completedMonths'], message: 'Completed months cannot exceed total months' });
  value.invites.forEach((invite, index) => {
    const hasAnyValue = Boolean(invite.name.trim() || invite.email.trim() || invite.phone.trim());
    if (!hasAnyValue) return;
    const result = completeMemberSchema.safeParse(invite);
    if (!result.success) result.error.issues.forEach((issue) => context.addIssue({ ...issue, path: ['invites', index, ...issue.path] }));
  });
  const emails = value.invites.filter((invite) => invite.email.trim()).map((invite) => invite.email.trim().toLowerCase());
  if (new Set(emails).size !== emails.length) context.addIssue({ code: 'custom', path: ['invites'], message: 'Each member needs a unique email' });
  if (value.firstDueDate < value.startDate) context.addIssue({ code: 'custom', path: ['firstDueDate'], message: 'The first due date cannot be before the start date' });
});

type FormValues = z.infer<typeof schema>;

function Field({ control, name, label, keyboardType, error }: { control: any; name: string; label: string; keyboardType?: 'default' | 'numeric' | 'email-address' | 'phone-pad'; error?: string }) {
  return <View>
    <Controller control={control} name={name} render={({ field: { onChange, onBlur, value } }) => (
      <TextInput mode="outlined" label={label} value={String(value ?? '')} onBlur={onBlur} onChangeText={onChange} keyboardType={keyboardType} error={Boolean(error)} />
    )} />
    {error ? <HelperText type="error" visible>{error}</HelperText> : null}
  </View>;
}

export default function ImportChittiScreen() {
  const { currentUser, importExistingChitti, savedContacts } = useApp();
  const today = dateToIso(new Date());
  const [datePicker, setDatePicker] = useState<'start' | 'due'>();
  const [memberCountText, setMemberCountText] = useState('4');
  const [completedMonthsText, setCompletedMonthsText] = useState('0');
  const [message, setMessage] = useState('');
  const { control, handleSubmit, getValues, setValue, formState: { errors, isSubmitting } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: '', description: '', monthlyAmount: '5000', memberCount: 4, completedMonths: 0,
      startDate: today, firstDueDate: today, upiId: '', payeeName: currentUser?.name ?? '',
      invites: Array.from({ length: 3 }, () => ({ name: '', email: '', phone: '' })),
    },
  });
  const { fields, replace, move } = useFieldArray({ control, name: 'invites' });
  const memberCountValue = useWatch({ control, name: 'memberCount' });
  const completedMonthsValue = useWatch({ control, name: 'completedMonths' });
  const memberCount = Number.isInteger(memberCountValue) && memberCountValue >= 1 ? memberCountValue : 0;
  const completedMonths = Number.isInteger(completedMonthsValue) && completedMonthsValue >= 0 ? completedMonthsValue : -1;
  const monthlyAmount = useWatch({ control, name: 'monthlyAmount' });
  const startDate = useWatch({ control, name: 'startDate' });
  const firstDueDate = useWatch({ control, name: 'firstDueDate' });
  const amount = toPaise(monthlyAmount || '0');
  const endDate = addMonthsClamped(firstDueDate, Math.max(0, memberCount - 1));
  const validCounts = memberCount >= 2 && memberCount <= 50 && completedMonths >= 0 && completedMonths <= memberCount;

  const changeMemberCount = (text: string) => {
    if (!/^\d*$/.test(text)) return;
    setMemberCountText(text);
    const count = text === '' ? Number.NaN : Number(text);
    setValue('memberCount', count, { shouldDirty: true, shouldValidate: true });
    const current = getValues('invites');
    const inviteCount = Number.isInteger(count) ? Math.max(0, Math.min(49, count - 1)) : 0;
    replace(Array.from({ length: inviteCount }, (_, index) => current[index] ?? { name: '', email: '', phone: '' }));
  };

  const changeCompletedMonths = (text: string) => {
    if (!/^\d*$/.test(text)) return;
    setCompletedMonthsText(text);
    setValue('completedMonths', text === '' ? Number.NaN : Number(text), { shouldDirty: true, shouldValidate: true });
  };

  const addSavedContact = (contact: (typeof savedContacts)[number]) => {
    const current = getValues('invites');
    if (current.some((member) => member.email.toLowerCase() === contact.email.toLowerCase())) return setMessage(`${contact.name} is already in this chitti.`);
    const empty = current.findIndex((member) => !member.name.trim() && !member.email.trim() && !member.phone.trim());
    if (empty < 0) return setMessage('All payout months are assigned. Increase the total members to add another person.');
    setValue(`invites.${empty}`, { name: contact.name, email: contact.email, phone: contact.phone }, { shouldDirty: true, shouldValidate: true });
    setMessage(`${contact.name} assigned to payout month ${empty + 2}.`);
  };

  const submit = async (values: FormValues) => {
    const id = await importExistingChitti({
      name: values.name,
      description: values.description,
      monthlyAmountPaise: toPaise(values.monthlyAmount),
      memberCount: values.memberCount,
      completedMonths: values.completedMonths,
      startDate: values.startDate,
      firstDueDate: values.firstDueDate,
      dueDay: Number(values.firstDueDate.slice(-2)),
      upiId: values.upiId,
      payeeName: values.payeeName,
      invites: values.invites.flatMap((member, index) => member.name.trim() || member.email.trim() || member.phone.trim()
        ? [{ name: member.name.trim(), email: member.email.trim().toLowerCase(), phone: member.phone.trim(), payoutPosition: index + 2 }]
        : []),
    });
    router.replace(`/chitti/${id}`);
  };

  if (currentUser?.role !== 'admin') return null;
  return <Screen title="Add existing chitti" back>
    <Card mode="contained"><Card.Content style={styles.section}>
      <Text variant="titleMedium" style={styles.heading}>Keep the order already decided</Text>
      <Text>Your payout month remains 1. Add the members you know now and leave the other payout months blank. You can invite the remaining members later. No shuffle or approval vote will run.</Text>
    </Card.Content></Card>

    <Card mode="elevated"><Card.Content style={styles.section}>
      <Text variant="titleLarge" style={styles.heading}>Existing chitti details</Text>
      <Field control={control} name="name" label="Chitti name" error={errors.name?.message} />
      <Field control={control} name="description" label="Description (optional)" error={errors.description?.message} />
      <View style={styles.twoColumns}>
        <View style={styles.column}><Field control={control} name="monthlyAmount" label="Monthly amount (₹)" keyboardType="numeric" error={errors.monthlyAmount?.message} /></View>
        <View style={styles.column}>
          <TextInput mode="outlined" label="Total members / months" keyboardType="numeric" value={memberCountText} onChangeText={changeMemberCount} error={Boolean(errors.memberCount)} />
          {errors.memberCount ? <HelperText type="error">{memberCountText === '' ? 'Enter total members' : errors.memberCount.message}</HelperText> : <HelperText type="info">Includes the administrator</HelperText>}
        </View>
        <View style={styles.column}>
          <TextInput mode="outlined" label="Months already completed" keyboardType="numeric" value={completedMonthsText} onChangeText={changeCompletedMonths} error={Boolean(errors.completedMonths)} />
          {errors.completedMonths ? <HelperText type="error">{completedMonthsText === '' ? 'Enter completed months' : errors.completedMonths.message}</HelperText> : <HelperText type="info">The next month becomes the active collection</HelperText>}
        </View>
      </View>
      <Card mode="contained" style={styles.calculation}><Card.Content>
        <Text variant="labelLarge">Monthly pot</Text>
        <Text variant="headlineMedium" style={styles.amount}>{formatINR(amount * memberCount)}</Text>
        <Text>{memberCount || '—'} members × {formatINR(amount)} for {memberCount || '—'} months</Text>
      </Card.Content></Card>

      <View style={styles.twoColumns}>
        <View style={styles.column}><Text variant="labelLarge">Original start date</Text><Button mode="outlined" icon="calendar-start" contentStyle={styles.dateButton} onPress={() => setDatePicker('start')}>{formatDate(startDate)}</Button></View>
        <View style={styles.column}><Text variant="labelLarge">Original first due date</Text><Button mode="outlined" icon="calendar-clock" contentStyle={styles.dateButton} onPress={() => setDatePicker('due')}>{formatDate(firstDueDate)}</Button>{errors.firstDueDate?.message ? <HelperText type="error">{errors.firstDueDate.message}</HelperText> : null}</View>
        <View style={styles.column}><Text variant="labelLarge">Calculated end date</Text><Text variant="titleLarge" style={styles.heading}>{formatDate(endDate)}</Text></View>
      </View>
      <View style={styles.twoColumns}>
        <View style={styles.column}><Field control={control} name="upiId" label="Administrator UPI ID" error={errors.upiId?.message} /></View>
        <View style={styles.column}><Field control={control} name="payeeName" label="UPI payee name" error={errors.payeeName?.message} /></View>
      </View>
    </Card.Content></Card>

    <Card mode="outlined"><Card.Content style={styles.section}>
      <Text variant="titleLarge" style={styles.heading}>Historical payment treatment</Text>
      <Text>Completed months are recorded as completed, but their individual payments are left unassessed. They will not lower anyone’s reliability score. Current and future months use normal payment tracking.</Text>
    </Card.Content></Card>

    {savedContacts.length ? <Card mode="outlined"><Card.Content style={styles.section}>
      <Text variant="titleLarge" style={styles.heading}>Saved members</Text>
      <View style={styles.savedGrid}>{savedContacts.map((contact) => <View key={contact.email} style={styles.savedMember}><UserAvatar name={contact.name} uri={contact.avatarUri} size={38} /><View style={styles.grow}><Text variant="titleMedium">{contact.name}</Text><Text variant="bodySmall">{contact.email}</Text></View><Button compact mode="outlined" onPress={() => addSavedContact(contact)}>Add</Button></View>)}</View>
    </Card.Content></Card> : null}

    <Card mode="elevated"><Card.Content style={styles.section}>
      <Text variant="titleLarge" style={styles.heading}>Existing payout order</Text>
      <Text>Member details are optional while importing. A blank payout month stays available so you can assign it later from the chitti page.</Text>
      <View style={styles.adminMonth}><Text variant="titleMedium">Month 1 · {currentUser.name}</Text><Text>Administrator’s fixed month</Text></View>
      {fields.map((field, index) => <View key={field.id} style={styles.member}>
        <Divider />
        <View style={styles.orderHeader}><Text variant="titleMedium">Payout month {index + 2}</Text><View style={styles.orderButtons}><Button compact disabled={index === 0} onPress={() => move(index, index - 1)}>Earlier</Button><Button compact disabled={index === fields.length - 1} onPress={() => move(index, index + 1)}>Later</Button></View></View>
        <Field control={control} name={`invites.${index}.name`} label="Full name" error={errors.invites?.[index]?.name?.message} />
        <Field control={control} name={`invites.${index}.email`} label="Google email" keyboardType="email-address" error={errors.invites?.[index]?.email?.message} />
        <Field control={control} name={`invites.${index}.phone`} label="Phone number" keyboardType="phone-pad" error={errors.invites?.[index]?.phone?.message} />
      </View>)}
      {typeof errors.invites?.message === 'string' ? <HelperText type="error">{errors.invites.message}</HelperText> : null}
    </Card.Content></Card>

    <DatePickerModal locale="en" mode="single" visible={Boolean(datePicker)} date={isoToDate(datePicker === 'start' ? startDate : firstDueDate)} onDismiss={() => setDatePicker(undefined)} onConfirm={({ date }) => {
      if (!date || !datePicker) return setDatePicker(undefined);
      const selected = dateToIso(date);
      if (datePicker === 'start') setValue('startDate', selected, { shouldValidate: true });
      else setValue('firstDueDate', selected, { shouldValidate: true });
      setDatePicker(undefined);
    }} />
    <Button mode="contained" icon="history" loading={isSubmitting} disabled={isSubmitting || !validCounts} contentStyle={styles.submit} onPress={handleSubmit(submit)}>Add existing chitti</Button>
    <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
  </Screen>;
}

const styles = StyleSheet.create({
  section: { gap: 14 }, heading: { fontWeight: '700' }, amount: { fontWeight: '800', color: '#111111' },
  twoColumns: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 }, column: { flex: 1, minWidth: 220 },
  calculation: { backgroundColor: '#F5EDDB' }, dateButton: { minHeight: 48 }, submit: { minHeight: 54 },
  adminMonth: { gap: 3, paddingVertical: 6 }, member: { gap: 9 }, orderHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' },
  orderButtons: { flexDirection: 'row', gap: 4 }, savedGrid: { gap: 10 }, savedMember: { flexDirection: 'row', alignItems: 'center', gap: 10 }, grow: { flex: 1 },
});

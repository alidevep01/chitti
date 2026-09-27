import { zodResolver } from '@hookform/resolvers/zod';
import { router } from 'expo-router';
import { useState } from 'react';
import { Controller, useFieldArray, useForm, useWatch } from 'react-hook-form';
import { StyleSheet, View } from 'react-native';
import { Button, Card, Divider, HelperText, Searchbar, Snackbar, Text, TextInput } from 'react-native-paper';
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

const inviteSchema = z.object({
  name: z.string().trim().min(2, 'Enter the member name'),
  email: z.email('Enter a valid Google email').transform((value) => value.toLowerCase()),
  phone: z.string().trim().min(8, 'Enter a valid phone number'),
});

const schema = z.object({
  name: z.string().trim().min(3, 'Enter a name for this chitti'),
  description: z.string().trim().max(200).optional(),
  monthlyAmount: z.string().refine((value) => Number(value) >= 100, 'Enter an amount of at least ₹100'),
  memberCount: z.number().int('Enter a whole number').min(2, 'At least 2 members are required').max(50, 'A chitti can have at most 50 members'),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Choose a start date'),
  firstDueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use YYYY-MM-DD'),
  upiId: z.string().trim().min(3, 'Enter the administrator UPI ID'),
  payeeName: z.string().trim().min(2, 'Enter the UPI payee name'),
  invites: z.array(inviteSchema),
}).superRefine((value, context) => {
  if (value.invites.length !== value.memberCount - 1) context.addIssue({ code: 'custom', path: ['invites'], message: `Add exactly ${value.memberCount - 1} invited members` });
  const emails = value.invites.map((invite) => invite.email.toLowerCase());
  if (new Set(emails).size !== emails.length) context.addIssue({ code: 'custom', path: ['invites'], message: 'Each invitation needs a unique email' });
  if (value.firstDueDate < value.startDate) context.addIssue({ code: 'custom', path: ['firstDueDate'], message: 'The first due date cannot be before the start date' });
});

type FormValues = z.infer<typeof schema>;

function Field({ control, name, label, keyboardType, error }: { control: any; name: string; label: string; keyboardType?: 'default' | 'numeric' | 'email-address' | 'phone-pad'; error?: string }) {
  return (
    <View>
      <Controller control={control} name={name} render={({ field: { onChange, onBlur, value } }) => (
        <TextInput mode="outlined" label={label} value={String(value ?? '')} onBlur={onBlur} onChangeText={onChange} keyboardType={keyboardType} error={Boolean(error)} />
      )} />
      {error ? <HelperText type="error" visible>{error}</HelperText> : null}
    </View>
  );
}

export default function NewChittiScreen() {
  const { currentUser, createChitti, savedContacts } = useApp();
  const today = dateToIso(new Date());
  const [datePicker, setDatePicker] = useState<'start' | 'due'>();
  const [contactSearch, setContactSearch] = useState('');
  const [memberCountText, setMemberCountText] = useState('4');
  const [message, setMessage] = useState('');
  const { control, handleSubmit, getValues, reset, setValue, formState: { errors, isSubmitting } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: '', description: '', monthlyAmount: '5000', memberCount: 4, startDate: today, firstDueDate: today,
      upiId: '', payeeName: currentUser?.name ?? '',
      invites: Array.from({ length: 3 }, () => ({ name: '', email: '', phone: '' })),
    },
  });
  const { fields, replace } = useFieldArray({ control, name: 'invites' });
  const memberCountValue = useWatch({ control, name: 'memberCount' });
  const memberCount = Number.isInteger(memberCountValue) && memberCountValue >= 1 ? memberCountValue : 0;
  const monthlyAmount = useWatch({ control, name: 'monthlyAmount' });
  const startDate = useWatch({ control, name: 'startDate' });
  const firstDueDate = useWatch({ control, name: 'firstDueDate' });
  const invites = useWatch({ control, name: 'invites' });
  const amount = toPaise(monthlyAmount || '0');
  const endDate = addMonthsClamped(firstDueDate, Math.max(0, memberCount - 1));
  const hasValidMemberCount = memberCount >= 2 && memberCount <= 50;

  const changeMemberCount = (text: string) => {
    if (!/^\d*$/.test(text)) return;
    setMemberCountText(text);
    const count = text === '' ? Number.NaN : Number(text);
    setValue('memberCount', count, { shouldDirty: true, shouldValidate: true });
    const currentInvites = getValues('invites');
    const inviteCount = Number.isInteger(count) ? Math.max(0, Math.min(49, count - 1)) : 0;
    replace(Array.from({ length: inviteCount }, (_, index) => currentInvites[index] ?? { name: '', email: '', phone: '' }));
  };

  const addSavedContact = (contact: (typeof savedContacts)[number]) => {
    const currentInvites = getValues('invites');
    const existingIndex = currentInvites.findIndex((invite) => invite.email.toLowerCase() === contact.email.toLowerCase());
    if (existingIndex >= 0) return setMessage(`${contact.name} is already in this chitti.`);
    const emptyIndex = currentInvites.findIndex((invite) => !invite.name.trim() && !invite.email.trim() && !invite.phone.trim());
    if (emptyIndex < 0) return setMessage('All member spaces are filled. Increase “Total members / months” to add another person.');
    reset({
      ...getValues(),
      invites: currentInvites.map((invite, index) => index === emptyIndex
        ? { name: contact.name, email: contact.email, phone: contact.phone }
        : invite),
    }, { keepErrors: true });
    setMessage(`${contact.name} added as Member ${emptyIndex + 2}.`);
  };

  const selectedEmails = new Set((invites ?? []).map((invite) => invite.email.toLowerCase()).filter(Boolean));
  const visibleContacts = savedContacts.filter((contact) => {
    const query = contactSearch.trim().toLowerCase();
    return !query || contact.name.toLowerCase().includes(query) || contact.email.toLowerCase().includes(query) || contact.phone.toLowerCase().includes(query);
  });

  const submit = async (values: FormValues) => {
    const id = await createChitti({
      name: values.name,
      description: values.description,
      monthlyAmountPaise: toPaise(values.monthlyAmount),
      memberCount: values.memberCount,
      startDate: values.startDate,
      firstDueDate: values.firstDueDate,
      dueDay: Number(values.firstDueDate.slice(-2)),
      upiId: values.upiId,
      payeeName: values.payeeName,
      invites: values.invites,
    });
    router.replace(`/chitti/${id}`);
  };

  if (currentUser?.role !== 'admin') return null;
  return (
    <Screen title="Create a chitti" back>
      <Card mode="contained"><Card.Content style={styles.info}><Text variant="titleMedium">Simple and consistent</Text><Text>The administrator is member 1. Member count, months, and payout order all stay linked.</Text></Card.Content></Card>
      <Card mode="elevated"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Chitti details</Text>
        <Field control={control} name="name" label="Chitti name" error={errors.name?.message} />
        <Field control={control} name="description" label="Description (optional)" error={errors.description?.message} />
        <View style={styles.twoColumns}>
          <View style={styles.column}><Field control={control} name="monthlyAmount" label="Monthly amount (₹)" keyboardType="numeric" error={errors.monthlyAmount?.message} /></View>
          <View style={styles.column}>
            <TextInput mode="outlined" label="Total members / months" keyboardType="numeric" value={memberCountText} onChangeText={changeMemberCount} error={Boolean(errors.memberCount)} />
            {errors.memberCount ? <HelperText type="error" visible>{memberCountText === '' ? 'Enter total members' : errors.memberCount.message}</HelperText> : <HelperText type="info">Includes the administrator</HelperText>}
          </View>
        </View>
        <Card mode="contained" style={styles.calculation}><Card.Content><Text variant="labelLarge">Calculated monthly pot</Text><Text variant="headlineMedium" style={styles.amount}>{formatINR(amount * memberCount)}</Text><Text>{memberCount || '—'} members × {formatINR(amount)} for {memberCount || '—'} months</Text></Card.Content></Card>
        <Card mode="outlined"><Card.Content style={styles.schedule}>
          <Text variant="titleMedium" style={styles.heading}>Schedule</Text>
          <View style={styles.twoColumns}>
            <View style={styles.column}><Text variant="labelLarge">Chitti starts</Text><Button mode="outlined" icon="calendar-start" contentStyle={styles.dateButton} onPress={() => setDatePicker('start')}>{formatDate(startDate)}</Button>{errors.startDate?.message ? <HelperText type="error">{errors.startDate.message}</HelperText> : null}</View>
            <View style={styles.column}><Text variant="labelLarge">First contribution due</Text><Button mode="outlined" icon="calendar-clock" contentStyle={styles.dateButton} onPress={() => setDatePicker('due')}>{formatDate(firstDueDate)}</Button>{errors.firstDueDate?.message ? <HelperText type="error">{errors.firstDueDate.message}</HelperText> : null}</View>
          </View>
          <View style={styles.dateSummary}><Text variant="labelLarge">Calculated end date</Text><Text variant="titleLarge" style={styles.heading}>{formatDate(endDate)}</Text><Text>{memberCount || '—'} monthly rounds · contributions are due on day {Number(firstDueDate.slice(-2))} of each month, clamped to month end.</Text></View>
        </Card.Content></Card>
        <View style={styles.twoColumns}>
          <View style={styles.column}><Field control={control} name="upiId" label="Administrator UPI ID" error={errors.upiId?.message} /></View>
          <View style={styles.column}><Field control={control} name="payeeName" label="UPI payee name" error={errors.payeeName?.message} /></View>
        </View>
      </Card.Content></Card>

      {savedContacts.length > 0 ? <Card mode="outlined"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>Saved members</Text>
        <Text>People invited to an earlier chitti are remembered automatically. Tap Add instead of entering their information again.</Text>
        {savedContacts.length > 5 ? <Searchbar placeholder="Search saved members" value={contactSearch} onChangeText={setContactSearch} /> : null}
        {visibleContacts.map((contact, index) => <View key={contact.email}>{index ? <Divider style={styles.contactDivider} /> : null}<View style={styles.contactRow}>
          <UserAvatar name={contact.name} uri={contact.avatarUri} size={42} />
          <View style={styles.contactDetails}><Text variant="titleMedium">{contact.name}</Text><Text>{contact.email}</Text><Text variant="bodySmall">{contact.phone} · invited {contact.timesInvited} {contact.timesInvited === 1 ? 'time' : 'times'}</Text></View>
          <Button mode={selectedEmails.has(contact.email.toLowerCase()) ? 'contained-tonal' : 'outlined'} disabled={selectedEmails.has(contact.email.toLowerCase())} icon={selectedEmails.has(contact.email.toLowerCase()) ? 'check' : 'account-plus'} onPress={() => addSavedContact(contact)}>{selectedEmails.has(contact.email.toLowerCase()) ? 'Added' : 'Add'}</Button>
        </View></View>)}
      </Card.Content></Card> : null}

      <Card mode="elevated"><Card.Content style={styles.section}>
        <Text variant="titleLarge" style={styles.heading}>{memberCount > 1 ? `Invite ${memberCount - 1} members` : 'Invite members'}</Text>
        <Text>Each person receives a unique, single-use link. Their Google email must match this invitation.</Text>
        {fields.map((field, index) => (
          <View key={field.id} style={styles.invite}>
            <Text variant="titleMedium">Member {index + 2}</Text>
            <Field control={control} name={`invites.${index}.name`} label="Full name" error={errors.invites?.[index]?.name?.message} />
            <Field control={control} name={`invites.${index}.email`} label="Google email" keyboardType="email-address" error={errors.invites?.[index]?.email?.message} />
            <Field control={control} name={`invites.${index}.phone`} label="Phone number" keyboardType="phone-pad" error={errors.invites?.[index]?.phone?.message} />
            {index < fields.length - 1 ? <Divider /> : null}
          </View>
        ))}
        {typeof errors.invites?.message === 'string' ? <HelperText type="error">{errors.invites.message}</HelperText> : null}
      </Card.Content></Card>
      <DatePickerModal
        locale="en"
        mode="single"
        visible={Boolean(datePicker)}
        date={isoToDate(datePicker === 'start' ? startDate : firstDueDate)}
        validRange={datePicker === 'due' ? { startDate: isoToDate(startDate) } : undefined}
        onDismiss={() => setDatePicker(undefined)}
        onConfirm={({ date }) => {
          if (!date || !datePicker) return setDatePicker(undefined);
          const selected = dateToIso(date);
          if (datePicker === 'start') {
            setValue('startDate', selected, { shouldValidate: true });
            if (firstDueDate < selected) setValue('firstDueDate', selected, { shouldValidate: true });
          } else {
            setValue('firstDueDate', selected, { shouldValidate: true });
          }
          setDatePicker(undefined);
        }}
      />
      <Button mode="contained" icon="check" loading={isSubmitting} disabled={isSubmitting || !hasValidMemberCount} contentStyle={styles.submit} onPress={handleSubmit(submit)}>Create private chitti</Button>
      <Snackbar visible={Boolean(message)} onDismiss={() => setMessage('')}>{message}</Snackbar>
    </Screen>
  );
}

const styles = StyleSheet.create({
  section: { gap: 14 }, info: { gap: 5 }, heading: { fontWeight: '700' },
  twoColumns: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 }, column: { flex: 1, minWidth: 220 },
  calculation: { backgroundColor: '#F5EDDB' }, amount: { fontWeight: '800', color: '#111111' },
  schedule: { gap: 12 }, dateButton: { minHeight: 48 }, dateSummary: { gap: 4, paddingTop: 4 },
  invite: { gap: 8, paddingTop: 8 }, submit: { minHeight: 54 },
  contactRow: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' }, contactDetails: { flex: 1, minWidth: 190 }, contactDivider: { marginVertical: 10 },
});

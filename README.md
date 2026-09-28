# Chitti

Chitti is a private, invitation-only family savings-circle tracker. It is an Expo Router application that runs as an installable web app today and can produce Android and iOS builds later. Supabase supplies Google authentication, PostgreSQL, realtime events, storage, and server-side business rules.

> **Prototype boundary:** Chitti records payments that happen through UPI or cash outside the app. It does not receive, hold, verify, or transfer money. Do not use it for real-money activity until the relevant state-specific chit-fund, privacy, agreement, registration, security, and record-retention requirements have been reviewed by a qualified professional.

## What is implemented

- Mobile-first administrator and member dashboards
- Google OAuth production path and a zero-setup local demo
- Administrator-only chitti creation with derived pot/month rules
- Unique invitation model, editable pending invitations, and prefilled email/WhatsApp/Web Share messages
- Server-side payout shuffle, immutable result hash, unanimous approval, and required private rejection comments for the administrator
- Monthly rounds, UPI/QR/cash submissions, administrator review, and payout confirmation
- Calendar-based start/first-due scheduling with a calculated final date, daily unpaid reminders, and administrator-only payment reliability history
- Exceptional late-member joining with missed/current contributions, audited recipient top-ups, and a new final payout month
- Personal payment-history reports with a reliability score out of 10, plus administrator-wide member reports
- UPI/cash payment submissions, optional private payment photos, and administrator receipt confirmation
- Reusable saved-member contacts sourced from the administrator's previous invitations
- Pending invitation cards on the member dashboard with a direct review-and-join action
- Administrator month swaps for unpaid payouts, with an audit event and automatic notifications to both affected members
- Private notification inbox, realtime-ready tables, Web Push subscription, and daily reminder function
- Profile editing and 5 MB avatar selection/storage
- PostgreSQL constraints, transactional RPCs, RLS policies, and append-only audit events
- PWA manifest, conservative service worker, and universal Expo routing

## Run the local demo

Requirements: Node.js 22+ and npm.

```bash
npm install
npm run web
```

Open the displayed local address. With no `.env` file, Chitti clearly enters **Demo mode**. Choose the administrator or member preview. Demo data is stored only in the browser/device through AsyncStorage; no messages or payments are sent.

Reset the demo by clearing site storage, or remove the `chitti-demo-state-v1` AsyncStorage entry.

## Connect Supabase

1. Install the Supabase CLI and Docker, then start the local services:

   ```bash
   npx supabase start
   npx supabase db reset
   ```

2. Copy `.env.example` to `.env.local` and enter the local or hosted project URL and publishable key.
3. Create Google OAuth web credentials, enable the Google provider in Supabase, and add the exact local and deployed redirect URLs.
4. Sign in once, then bootstrap the sole administrator from the Supabase SQL editor using the real Google email:

   ```sql
   select public.bootstrap_admin('owner@example.com');
   ```

   `bootstrap_admin` is intentionally unavailable to browser roles.
5. For a hosted project, apply the migration with `npx supabase db push`.

After every database migration, refresh the checked-in schema types with `npm run supabase:types` while the local Supabase stack is running.

The initial schema is in `supabase/migrations/202609120001_initial_schema.sql`. All amounts are integer paise. The browser receives only a publishable key; privileged mutations verify the authenticated user inside database transactions.

### Adding members to a pending existing chitti

From the **Members** card, choose **Add member**. Empty planned payout months are filled first. When every position is assigned to a joined member or pending invitation, adding a member appends the next month (up to 50). The form explains the increase in total months, monthly pot, and end date before the invitation is created. Existing rankings, the contribution per member, and recorded completed months remain unchanged; the administrator can still edit the ranking before activation.

This requires `202609270001_expand_pending_existing_chitti.sql`. Apply locally with `npx supabase migration up --local`, then run `npm run supabase:types` and `npm run test:db`. Apply pending migrations to the hosted project with `npx supabase db push` (use the password-based connection if required) **before** building and deploying the new website. Do not reset a database containing real users.

### Sharing a payout position before activation

In a pending existing chitti, choose **Members → Add member → Shared position** (or **Add co-owner**). Select a joined owner or a pending main-owner invitation, enter the new person's monthly rupee amount and contact details, then create their invitation. For a ₹20,000 position, assigning ₹5,000 leaves ₹15,000 for the main owner. There is no fixed co-owner count limit; each owner must retain at least ₹0.01. This does not add months or increase the pot. Add people individually, selecting the same original owner again to allocate another amount. For thirds of ₹20,000, two co-owners at ₹6,666.67 leave ₹6,666.66 for the main owner.

Co-owners may accept in any order. All pending invitations must be accepted before activation, with each position's amounts totaling its monthly contribution. Ranking edits move co-owners together; the administrator's group stays at month 1. Future contributions and payouts use exact paise amounts, and the administrator confirms each owner's payout separately. Historical completed months remain historical, without invented contribution records. Active positions can be split only while the source owner's payout is unpaid and their outstanding contributions have not been submitted or confirmed.

Apply all pending migrations through `202609270003_amount_based_coowners.sql` locally with `npx supabase migration up --local`, and to your linked hosted database with `npx supabase db push` (not `--dry-run`) before deploying the web build. No database reset is needed. `npm run test:db` also runs the shared-position regression suites via its post-test hook.

Invitations use **Share link**, including WhatsApp through the device share menu. There are no email-invite buttons or automatic email prompts. The Google email field remains required to restrict acceptance to the correct signed-in account.

### Web Push

Generate VAPID keys and set `EXPO_PUBLIC_VAPID_PUBLIC_KEY` in the web build. Add the following server-only Supabase function secrets:

```text
VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY
VAPID_SUBJECT=mailto:owner@example.com
PUSH_WEBHOOK_SECRET
```

Deploy `send-push`, then create a Supabase Database Webhook for inserts on `public.notifications`. Point it to the function and include the same `PUSH_WEBHOOK_SECRET` as the `x-chitti-webhook-secret` header. The function reloads the notification by ID and always sends privacy-safe text.

On iPhone, users must add Chitti to the Home Screen before enabling Web Push. Permission is requested only from the explicit **Enable** button.

### Scheduled reminders

Enable Supabase Cron and schedule the idempotent reminder function:

```sql
select cron.schedule(
  'chitti-due-reminders',
  '15 3 * * *',
  $$select public.process_due_reminders();$$
);
```

This runs at 03:15 UTC (08:45 India time), opens eligible calendar periods, sends one reminder per unpaid member each day before and after the due date, records overdue contributions, and avoids duplicate reminders on repeated runs. Reminders stop while a payment is awaiting administrator review and resume if it is rejected.

## Verification

```bash
npm run typecheck
npm test
npm run test:db
npm run lint
npm run build:web
```

`npm run test:db` requires the local Supabase stack to be running. It exercises late joining, catch-up payment review, recipient top-ups, atomic month swapping, and both affected-user notifications inside a transaction that is rolled back after the test.

Before real use, additionally run the migration against a disposable Supabase project and test RLS using separate administrator/member/outsider JWTs. Important cases are invitation email matching and reuse, simultaneous redemption, duplicate shuffle idempotency, unanimous approval, cross-member contribution privacy, rejected payments, month-end dates, and payout locking.

## Deployment

For a free Expo-hosted web preview:

```bash
npx eas-cli@latest login
npx eas-cli@latest deploy
```

Set `EXPO_PUBLIC_APP_URL` to the final HTTPS origin and add it to the Supabase and Google OAuth allowlists before sharing invitation links. Keep separate Supabase projects for development and production.

Native Android/iOS releases use the same Expo project. Before an iOS App Store release, add Sign in with Apple, native push credentials, universal links, privacy declarations, and the required paid store memberships.

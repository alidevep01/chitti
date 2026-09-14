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

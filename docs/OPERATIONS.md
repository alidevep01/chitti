# Chitti operations and recovery

## Daily operation

- Review Supabase Auth, Database, Edge Function, and Cron logs for failures.
- Treat failed Web Push as advisory; the notification inbox is the durable source of truth.
- Never confirm a contribution from the application without independently checking the UPI account or receiving cash.
- Never place full names, amounts, phone numbers, payment references, or payout details in push text.
- Use **Add member** on an active chitti only for the exceptional late-join case. The new member owes each elapsed contribution, receives the new final payout month, and creates one explicit top-up for each already-completed recipient.
- Use **Swap months** only after confirming both affected members requested the change. The swap is immediate, limited to unpaid months, audited, and notifies both members without an in-app approval step.
- When someone rejects a shuffle, review the named member and their comment in the chitti or shuffle screen before scheduling the next draw. Rejection comments are visible only to that member and the administrator.
- Pending invitations can be edited. Saving an edit rotates the private token, so always send the newly generated link and treat every previously shared link as invalid.
- Payment reliability uses the member's recorded submission time against the round due date in `Asia/Kolkata`. Do not interpret a low score without discussing failed transfers, admin review errors, or other exceptional circumstances with the member.

## Backup

The Supabase free plan is not a production backup strategy. Before any real-money use:

1. Export the administrator JSON from Profile after each completed round.
2. Store the export in a private, access-controlled location.
3. Use `supabase db dump` before and after every schema migration.
4. Periodically restore a dump into a disposable project and verify row counts, memberships, payout assignments, contributions, payouts, and audit events.

Never commit exports, database dumps, `.env` files, service-role keys, or VAPID private keys to Git.

## Incident response

If account access, invitation links, or data integrity may be compromised:

1. Stop sharing invitations and pause administrator actions.
2. Revoke affected invitations by changing their status in an audited administrator operation; regenerate only after confirming the intended email.
3. Rotate any exposed server secret in Supabase and redeploy the Edge Function.
4. Export current data and preserve relevant audit events before changing records.
5. Notify affected members outside the application using an already trusted contact method.

Active payout orders and financial records must not be deleted or silently edited. Corrections require a new append-only audit event and an explanatory note.

## Deployment checklist

- `npm run typecheck`, `npm test`, `npm run test:db`, `npm run lint`, `npm run build:web`, and `npx expo-doctor` pass.
- Production uses a separate Supabase project from development.
- Google OAuth redirect origins exactly match the final HTTPS application URL.
- Only the intended owner email has the `admin` role.
- RLS tests are run with administrator, member, and outsider accounts.
- VAPID private key, webhook secret, and service-role key exist only in Supabase secrets.
- Database Webhook sends only a notification ID to `send-push`.
- Cron reminder history shows successful daily runs.
- Privacy notice and state-specific legal review are complete.

## Recovery priority

Restore in this order: profiles and roles; chittis and invitations; memberships and shuffle audit; rounds, contributions, and payouts; notifications and push subscriptions. Push subscriptions may be discarded and collected again. Never synthesize missing approvals, confirmations, or payout records.

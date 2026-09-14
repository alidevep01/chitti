-- Production data is intentionally not seeded.
-- After the owner signs in with Google once, run this from the SQL editor using
-- the service/postgres role, replacing the sample email:
-- select public.bootstrap_admin('owner@example.com');

-- Optional daily reminder job (enable the Cron integration first):
-- select cron.schedule('chitti-due-reminders', '15 3 * * *', $$select public.process_due_reminders();$$);

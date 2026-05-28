-- supabase/migrations/20260528000004_fix_admin_audit_log_nullable_admin_id.sql
-- Fixes a conflict in the previous migration: admin_id was declared
-- `not null` while the FK is `on delete set null`. Deleting an admin
-- user would otherwise abort with a constraint violation. We want
-- audit history to survive when the original admin user is deleted,
-- so we drop the NOT NULL constraint.

alter table public.admin_audit_log
  alter column admin_id drop not null;

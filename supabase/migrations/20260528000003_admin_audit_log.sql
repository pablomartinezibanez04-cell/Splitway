-- supabase/migrations/20260528000003_admin_audit_log.sql
-- Audit log for every mutating admin action in the admin panel.
--
-- NOTE: admin_id below is declared `not null` while the FK is
-- `on delete set null`, which is contradictory: deleting the
-- referenced auth.users row would violate the NOT NULL constraint.
-- This migration was already applied to the cloud project before the
-- issue was noticed, so it is preserved as-is for history integrity.
-- The follow-up migration 20260528000004_fix_admin_audit_log_nullable_admin_id.sql
-- drops the NOT NULL constraint, which is the intended final state
-- (audit rows must survive deletion of the original admin user).

create table if not exists public.admin_audit_log (
  id          uuid primary key default gen_random_uuid(),
  admin_id    uuid not null references auth.users(id) on delete set null,
  action      text not null,
  target_type text not null,
  target_id   text not null,
  details     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);

create index if not exists admin_audit_log_admin_idx
  on public.admin_audit_log (admin_id, created_at desc);

alter table public.admin_audit_log enable row level security;

-- Admins and superadmins can read the log. Writes only happen via the
-- service_role client from Server Actions, which bypasses RLS, so no
-- insert policy is needed.
drop policy if exists "admins read audit log" on public.admin_audit_log;
create policy "admins read audit log"
  on public.admin_audit_log
  for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role in ('admin', 'superadmin')
    )
  );

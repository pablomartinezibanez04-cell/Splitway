-- supabase/migrations/20260528000000_add_admin_role.sql
-- Add a role column to profiles so the admin panel can gate access.

alter table public.profiles
  add column if not exists role text not null default 'user'
    check (role in ('user', 'admin', 'superadmin'));

-- Partial index so role lookups for admins/superadmins are O(1) without
-- bloating the index for the typical 'user' value.
create index if not exists profiles_role_idx
  on public.profiles (role)
  where role != 'user';

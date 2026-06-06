-- supabase/migrations/20260606000000_official_routes_public_read.sql
-- Open the official-routes catalog to anonymous reads, and harden the
-- write side so only the curator account (splitwayoficial@gmail.com)
-- can publish `is_official = true` rows.
--
-- Visibility:
--   - Anyone (anon + authenticated) can SELECT routes where
--     `is_official = true`, plus the sectors belonging to those routes.
--   - The existing per-owner policies still scope each user's own
--     routes — these new policies are additive (RLS is OR-ed across
--     policies), so a signed-in user sees their own routes PLUS the
--     official catalog.
--   - INSERT, UPDATE and DELETE on `route_templates`/`sectors` remain
--     restricted to the owner via the policies from migration
--     20260504000000.
--
-- Write guardrail:
--   - A BEFORE INSERT/UPDATE trigger rejects any attempt to set
--     `is_official = true` unless the owning user is the splitway
--     curator. RPCs like `duplicate_route_as_official` and
--     `toggle_route_official` already transfer ownership to splitway
--     in the same statement, so they continue to work unchanged.

-- 1. Public-read policy for official routes.
drop policy if exists "official_routes_public_read" on public.route_templates;
create policy "official_routes_public_read"
  on public.route_templates
  for select
  to anon, authenticated
  using (is_official = true);

-- 2. Public-read policy for sectors of official routes.
drop policy if exists "official_sectors_public_read" on public.sectors;
create policy "official_sectors_public_read"
  on public.sectors
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.route_templates rt
      where rt.id = sectors.route_id and rt.is_official = true
    )
  );

-- 3. Enforce-owner trigger: only splitway can publish official routes.
-- security definer so the function can read auth.users regardless of
-- the calling role's grants on that table. The function is owned by
-- the migration role (postgres / superuser in Supabase), so it has
-- full visibility.
create or replace function public.enforce_official_owner()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_splitway_id uuid;
begin
  if new.is_official = true then
    select id into v_splitway_id
      from auth.users
      where lower(email) = 'splitwayoficial@gmail.com'
      limit 1;
    if v_splitway_id is null then
      raise exception
        'splitwayoficial@gmail.com user not found; cannot validate is_official write'
        using errcode = 'P0002';
    end if;
    if new.owner_id is null or new.owner_id <> v_splitway_id then
      raise exception
        'Only the Splitway official account can publish official routes'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end$$;

-- Tighten privileges on the trigger function itself: nothing outside
-- the trigger should be calling it.
revoke execute on function public.enforce_official_owner() from public;
revoke execute on function public.enforce_official_owner() from anon;
revoke execute on function public.enforce_official_owner() from authenticated;

drop trigger if exists enforce_official_owner_trg on public.route_templates;
create trigger enforce_official_owner_trg
  before insert or update on public.route_templates
  for each row execute function public.enforce_official_owner();

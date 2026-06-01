-- supabase/migrations/20260601000005_splitway_owns_official_routes.sql
-- Make `splitway@gmail.com` the curator account that owns every
-- official route. Promotes the account to superadmin, transfers
-- ownership of existing official routes, and rewires the duplicate +
-- toggle flows so future marks-as-official atomically transfer
-- ownership too.
--
-- If `splitway@gmail.com` does not exist yet, this migration creates
-- the auth.users row directly with NO password — it's a system
-- account, not meant for interactive sign-in. If you ever need to
-- log in as splitway, use Supabase Dashboard → Authentication →
-- Users → splitway@gmail.com → "Send password recovery" to set one.

do $$
declare
  v_splitway_id uuid;
begin
  select id into v_splitway_id from auth.users
    where lower(email) = 'splitway@gmail.com';

  if v_splitway_id is null then
    v_splitway_id := gen_random_uuid();

    insert into auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, is_sso_user, is_anonymous
    ) values (
      v_splitway_id,
      '00000000-0000-0000-0000-000000000000'::uuid,
      'authenticated', 'authenticated', 'splitway@gmail.com',
      null,
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('nickname', 'splitway'),
      now(), now(), false, false
    );

    -- Mirror the auth identity row so Supabase considers the email
    -- provider linked.
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_splitway_id, v_splitway_id::text,
      jsonb_build_object('sub', v_splitway_id::text, 'email', 'splitway@gmail.com'),
      'email', null, now(), now()
    );

    raise notice 'Created splitway@gmail.com system user (no password set).';
  end if;

  -- Ensure profile row exists (a fresh auth.users insert does NOT
  -- auto-create a profile row).
  insert into public.profiles (id, nickname, role, nickname_changed_at)
  values (v_splitway_id, 'splitway', 'superadmin', now())
  on conflict (id) do update
    set nickname = 'splitway',
        role = 'superadmin',
        updated_at = now();

  -- Transfer ownership of all existing official routes to splitway.
  update public.route_templates
  set owner_id = v_splitway_id,
      updated_at = now()
  where is_official = true and owner_id <> v_splitway_id;
end $$;

-- Stable helper so future code (RPCs, server actions) can look up
-- splitway's id without hardcoding a UUID.
create or replace function public.get_splitway_user_id()
returns uuid
language sql
security definer
stable
set search_path = public, auth
as $$
  select id from auth.users where lower(email) = 'splitway@gmail.com' limit 1;
$$;

revoke execute on function public.get_splitway_user_id() from public;
revoke execute on function public.get_splitway_user_id() from anon;
revoke execute on function public.get_splitway_user_id() from authenticated;
grant execute on function public.get_splitway_user_id() to service_role;

-- New duplicate_route_as_official: drops the p_admin_id parameter
-- (no longer relevant since the new owner is always splitway), and
-- looks splitway up at runtime via the helper above.
drop function if exists public.duplicate_route_as_official(uuid, uuid);

create or replace function public.duplicate_route_as_official(
  p_source_route_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_new_id uuid := gen_random_uuid();
  v_source record;
  v_splitway_id uuid;
begin
  v_splitway_id := public.get_splitway_user_id();
  if v_splitway_id is null then
    raise exception 'splitway@gmail.com user not found — cannot create official route'
      using errcode = 'P0002';
  end if;

  select * into v_source from public.route_templates where id = p_source_route_id;
  if not found then
    raise exception 'Source route % not found', p_source_route_id
      using errcode = 'P0002';
  end if;

  insert into public.route_templates (
    id, name, description, difficulty, elevation_range_m,
    location_label, owner_id, path_json, start_finish_gate_json,
    thumbnail_url, is_official, created_at, updated_at
  ) values (
    v_new_id,
    'Oficial — ' || v_source.name,
    v_source.description,
    v_source.difficulty,
    v_source.elevation_range_m,
    v_source.location_label,
    v_splitway_id,
    v_source.path_json,
    v_source.start_finish_gate_json,
    v_source.thumbnail_url,
    true,
    now(),
    now()
  );

  insert into public.sectors (id, route_id, label, order_index, gate_json)
  select gen_random_uuid(), v_new_id, label, order_index, gate_json
  from public.sectors
  where route_id = p_source_route_id;

  return v_new_id;
end;
$$;

revoke execute on function
  public.duplicate_route_as_official(uuid) from public;
revoke execute on function
  public.duplicate_route_as_official(uuid) from anon;
revoke execute on function
  public.duplicate_route_as_official(uuid) from authenticated;
grant execute on function
  public.duplicate_route_as_official(uuid) to service_role;

-- toggle_route_official: atomically flip is_official and (when
-- marking) transfer ownership to splitway. Used by the admin panel's
-- toggle so the two updates can't drift apart.
create or replace function public.toggle_route_official(
  p_route_id uuid,
  p_official boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_splitway_id uuid;
begin
  if p_official then
    v_splitway_id := public.get_splitway_user_id();
    if v_splitway_id is null then
      raise exception 'splitway@gmail.com user not found'
        using errcode = 'P0002';
    end if;
    update public.route_templates
    set is_official = true,
        owner_id = v_splitway_id,
        updated_at = now()
    where id = p_route_id;
  else
    -- Unmarking leaves owner_id at splitway. There is no original
    -- owner to "restore" — the admin can manually edit if needed.
    update public.route_templates
    set is_official = false,
        updated_at = now()
    where id = p_route_id;
  end if;
end;
$$;

revoke execute on function
  public.toggle_route_official(uuid, boolean) from public;
revoke execute on function
  public.toggle_route_official(uuid, boolean) from anon;
revoke execute on function
  public.toggle_route_official(uuid, boolean) from authenticated;
grant execute on function
  public.toggle_route_official(uuid, boolean) to service_role;

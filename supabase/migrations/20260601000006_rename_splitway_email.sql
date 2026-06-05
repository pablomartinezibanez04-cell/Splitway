-- supabase/migrations/20260601000006_rename_splitway_email.sql
-- Move the curator role from splitway@gmail.com to
-- splitwayoficial@gmail.com (which already existed as a separate
-- account). Transfer ownership of every official route to the new
-- account, promote it to superadmin, point the helper function at
-- it, then delete the now-redundant splitway@gmail.com auth row.

do $$
declare
  v_old_id uuid;
  v_new_id uuid;
begin
  select id into v_old_id from auth.users
    where lower(email) = 'splitway@gmail.com';
  select id into v_new_id from auth.users
    where lower(email) = 'splitwayoficial@gmail.com';

  if v_new_id is null then
    raise exception
      'splitwayoficial@gmail.com user does not exist. Create it first via the Flutter app or Supabase Dashboard.'
      using errcode = 'P0002';
  end if;

  -- Upsert profile for the new curator with the splitway identity.
  insert into public.profiles (id, nickname, role, nickname_changed_at)
  values (v_new_id, 'splitway', 'superadmin', now())
  on conflict (id) do update
    set nickname = 'splitway',
        role = 'superadmin',
        updated_at = now();

  if v_old_id is not null then
    -- Move every route currently owned by the old splitway to the new
    -- one (covers both is_official routes and any hypothetical
    -- non-official ones that ended up there).
    update public.route_templates
    set owner_id = v_new_id,
        updated_at = now()
    where owner_id = v_old_id;

    -- Deleting the old auth.users row cascades the profile (the FK
    -- on profiles.id is ON DELETE CASCADE).
    delete from auth.users where id = v_old_id;
  end if;

  -- Belt-and-suspenders: even if v_old_id was null, sweep any
  -- official routes that don't yet point at the new curator.
  update public.route_templates
  set owner_id = v_new_id,
      updated_at = now()
  where is_official = true and owner_id <> v_new_id;
end $$;

-- Point the helper at the new email so duplicate_route_as_official
-- and toggle_route_official automatically resolve to the new id.
create or replace function public.get_splitway_user_id()
returns uuid
language sql
security definer
stable
set search_path = public, auth
as $$
  select id from auth.users
  where lower(email) = 'splitwayoficial@gmail.com'
  limit 1;
$$;

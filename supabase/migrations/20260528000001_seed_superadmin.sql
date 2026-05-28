-- supabase/migrations/20260528000001_seed_superadmin.sql
-- Promote the founding superadmin. Idempotent: only runs if the user
-- exists and isn't already a superadmin. Safe to re-run.

do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where email = 'pabmariba@gmail.com';

  if v_user_id is null then
    raise notice 'Superadmin seed skipped: user pabmariba@gmail.com not found.';
    return;
  end if;

  -- Ensure a profile row exists (some installs create profiles lazily).
  insert into public.profiles (id, nickname, role)
  values (v_user_id, 'admin', 'superadmin')
  on conflict (id) do update
    set role = 'superadmin'
    where public.profiles.role <> 'superadmin';
end
$$;

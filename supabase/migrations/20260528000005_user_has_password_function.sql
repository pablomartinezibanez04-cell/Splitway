-- supabase/migrations/20260528000005_user_has_password_function.sql
-- SECURITY DEFINER function so authenticated users can check whether
-- their own auth.users row has a password set without needing direct
-- read access to the auth schema. Used by the admin panel proxy to
-- detect "complete profile" reliably — checking user.identities is
-- unreliable because `updateUser({ password })` on an OAuth user does
-- NOT add an email identity (the encrypted_password column does get
-- populated though).

create or replace function public.user_has_password()
returns boolean
language sql
security definer
stable
set search_path = public, auth
as $$
  select encrypted_password is not null
  from auth.users
  where id = auth.uid();
$$;

grant execute on function public.user_has_password() to authenticated;

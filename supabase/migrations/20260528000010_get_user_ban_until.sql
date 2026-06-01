-- supabase/migrations/20260528000010_get_user_ban_until.sql
-- Public read of "is this email currently banned, and until when".
-- Used by the Flutter login screen to show a useful message instead
-- of a generic "unexpected error" when a banned user attempts to sign
-- in. SECURITY DEFINER so callers (the user, possibly without a
-- session) can read auth.users.banned_until without direct schema
-- access.
--
-- Information leak: this reveals "email X is banned until Y" to any
-- caller who guesses email X. Acceptable trade-off: the banned user
-- already knows they're banned, and Supabase's sign-in error already
-- leaks "email X is registered" unless enumeration protection is on.

create or replace function public.get_user_ban_until(p_email text)
returns timestamptz
language sql
security definer
stable
set search_path = public, auth
as $$
  select banned_until
  from auth.users
  where lower(email) = lower(p_email)
    and banned_until is not null
    and banned_until > now()
  limit 1;
$$;

revoke execute on function public.get_user_ban_until(text) from public;
grant execute on function public.get_user_ban_until(text) to anon, authenticated;

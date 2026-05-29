-- supabase/migrations/20260528000006_find_user_id_by_email.sql
-- Service-role-only RPC to look up an auth user by email. Used by the
-- admin panel's promote-admin action — auth.admin.listUsers() is
-- capped at perPage=1000 and silently drops users beyond that page,
-- which made it possible to "fail to find" a real user OR (in a
-- different shape) succeed when the user did not actually exist
-- because the action's success branch didn't guard against an empty
-- UPDATE on profiles.

create or replace function public.find_user_id_by_email(p_email text)
returns uuid
language sql
security definer
stable
set search_path = public, auth
as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$$;

-- Hide from every role except service_role. The admin panel reaches it
-- via the service-role client from a guarded Server Action.
revoke execute on function public.find_user_id_by_email(text) from public;
revoke execute on function public.find_user_id_by_email(text) from anon;
revoke execute on function public.find_user_id_by_email(text)
  from authenticated;
grant execute on function public.find_user_id_by_email(text) to service_role;

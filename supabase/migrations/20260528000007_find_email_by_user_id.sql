-- supabase/migrations/20260528000007_find_email_by_user_id.sql
-- Symmetric counterpart to find_user_id_by_email. Used by the admin
-- panel to enrich audit log entries with the target user's email
-- without forcing the human reading the log to JOIN auth.users.

create or replace function public.find_email_by_user_id(p_user_id uuid)
returns text
language sql
security definer
stable
set search_path = public, auth
as $$
  select email from auth.users where id = p_user_id limit 1;
$$;

revoke execute on function public.find_email_by_user_id(uuid) from public;
revoke execute on function public.find_email_by_user_id(uuid) from anon;
revoke execute on function public.find_email_by_user_id(uuid)
  from authenticated;
grant execute on function public.find_email_by_user_id(uuid) to service_role;

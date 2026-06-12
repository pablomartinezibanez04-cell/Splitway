-- supabase/migrations/20260601000008_admin_app_logs_view.sql
-- Admin-only view over public.app_logs with the user's nickname
-- joined in for display. Service-role-only access — RLS on the
-- underlying table already restricts SELECT to service_role, but we
-- repeat the grants explicitly on the view so a future change to
-- app_logs RLS doesn't accidentally expose this.

drop view if exists public.admin_app_logs_view;

create view public.admin_app_logs_view as
select
  l.id,
  l.timestamp,
  l.level,
  l.tag,
  l.message,
  l.error,
  l.stack_trace,
  l.context,
  l.app_version,
  l.platform,
  l.device_model,
  l.user_id,
  p.nickname as user_nickname
from public.app_logs l
left join public.profiles p on p.id = l.user_id;

revoke all on public.admin_app_logs_view from public;
revoke all on public.admin_app_logs_view from anon;
revoke all on public.admin_app_logs_view from authenticated;
grant select on public.admin_app_logs_view to service_role;

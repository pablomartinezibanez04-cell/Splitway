-- supabase/migrations/20260528000009_admin_users_view_started_at.sql
-- Fix consistency in admin_users_view: speed_sessions.last_activity
-- now uses started_at, matching session_runs and free_rides and the
-- Activity tab's display. The original migration used created_at,
-- which is when the row was inserted (essentially identical for
-- speed_sessions but semantically less correct).

create or replace view public.admin_users_view as
select
  p.id,
  p.nickname,
  p.avatar_url,
  p.role,
  p.created_at as profile_created_at,
  u.email,
  u.created_at as signup_date,
  u.banned_until,
  greatest(
    coalesce(
      (select max(started_at) from public.session_runs where owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(started_at) from public.free_rides where owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(started_at) from public.speed_sessions where user_id = p.id),
      'epoch'::timestamptz
    )
  ) as last_activity,
  (
    coalesce((select count(*) from public.session_runs where owner_id = p.id), 0) +
    coalesce((select count(*) from public.free_rides where owner_id = p.id), 0) +
    coalesce((select count(*) from public.speed_sessions where user_id = p.id), 0)
  ) as sessions_count,
  coalesce(
    (select count(*) from public.route_templates where owner_id = p.id),
    0
  ) as routes_count
from public.profiles p
left join auth.users u on u.id = p.id;

revoke all on public.admin_users_view from public, anon, authenticated;
grant select on public.admin_users_view to service_role;

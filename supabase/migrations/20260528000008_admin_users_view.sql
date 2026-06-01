-- supabase/migrations/20260528000008_admin_users_view.sql
-- One-shot read for the admin panel's /users list. Joins profiles with
-- auth.users (for email, signup date, ban status) and computes per-user
-- aggregates so the list page can sort/filter without N+1 queries.
--
-- Service-role only. Granted explicitly because views default to
-- inheriting privileges from underlying tables; auth.users would
-- otherwise be off-limits to lower roles.
--
-- Note: session_runs and free_rides use started_at (no created_at column);
-- speed_sessions uses created_at.

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
      (select max(sr.started_at) from public.session_runs sr where sr.owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(fr.started_at) from public.free_rides fr where fr.owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(ss.created_at) from public.speed_sessions ss where ss.user_id = p.id),
      'epoch'::timestamptz
    )
  ) as last_activity,
  (
    coalesce((select count(*) from public.session_runs sr where sr.owner_id = p.id), 0) +
    coalesce((select count(*) from public.free_rides fr where fr.owner_id = p.id), 0) +
    coalesce((select count(*) from public.speed_sessions ss where ss.user_id = p.id), 0)
  ) as sessions_count,
  coalesce(
    (select count(*) from public.route_templates rt where rt.owner_id = p.id),
    0
  ) as routes_count
from public.profiles p
left join auth.users u on u.id = p.id;

revoke all on public.admin_users_view from public, anon, authenticated;
grant select on public.admin_users_view to service_role;

-- supabase/migrations/20260601000007_admin_sessions_views.sql
-- Three read-only views, one per session type, that the admin panel
-- queries directly to drive its /sessions tabs. Each view joins the
-- session table with the owner's profile and (when applicable) the
-- route and vehicle for filter-friendly display columns. Service-role
-- only — admins read via adminClient().

create or replace view public.admin_session_runs_view as
select
  s.id,
  s.owner_id,
  s.route_id,
  s.vehicle_id,
  s.started_at,
  s.ended_at,
  s.status,
  s.total_distance_m,
  s.avg_speed_mps,
  s.max_speed_mps,
  p.nickname as owner_nickname,
  rt.name as route_name,
  v.name as vehicle_name,
  extract(epoch from coalesce(s.ended_at, s.started_at) - s.started_at)::int
    as duration_seconds
from public.session_runs s
left join public.profiles p on p.id = s.owner_id
left join public.route_templates rt on rt.id = s.route_id
left join public.vehicles v on v.id = s.vehicle_id::uuid;

create or replace view public.admin_free_rides_view as
select
  s.id,
  s.owner_id,
  s.vehicle_id,
  s.name,
  s.description,
  s.location_label,
  s.started_at,
  s.ended_at,
  s.status,
  s.total_distance_m,
  s.avg_speed_mps,
  s.max_speed_mps,
  p.nickname as owner_nickname,
  v.name as vehicle_name,
  extract(epoch from coalesce(s.ended_at, s.started_at) - s.started_at)::int
    as duration_seconds
from public.free_rides s
left join public.profiles p on p.id = s.owner_id
left join public.vehicles v on v.id = s.vehicle_id::uuid;

create or replace view public.admin_speed_sessions_view as
select
  s.id,
  s.user_id as owner_id,
  s.vehicle_id,
  s.name,
  s.selected_metrics,
  s.results,
  s.countdown_seconds,
  s.is_partial,
  s.started_at,
  s.finished_at,
  s.created_at,
  p.nickname as owner_nickname,
  v.name as vehicle_name
from public.speed_sessions s
left join public.profiles p on p.id = s.user_id
left join public.vehicles v on v.id = s.vehicle_id
where s.deleted_at is null;

revoke all on public.admin_session_runs_view
  from public, anon, authenticated;
grant select on public.admin_session_runs_view to service_role;

revoke all on public.admin_free_rides_view
  from public, anon, authenticated;
grant select on public.admin_free_rides_view to service_role;

revoke all on public.admin_speed_sessions_view
  from public, anon, authenticated;
grant select on public.admin_speed_sessions_view to service_role;

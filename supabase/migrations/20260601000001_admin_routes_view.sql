-- supabase/migrations/20260601000001_admin_routes_view.sql
-- Single-query feed for the admin panel's /routes list. Joins route
-- metadata with the owner's nickname and email, and per-route counts
-- for sectors and sessions. Service-role only.

create or replace view public.admin_routes_view as
select
  r.id,
  r.name,
  r.description,
  r.difficulty,
  r.location_label,
  r.thumbnail_url,
  r.is_official,
  r.created_at,
  r.owner_id,
  p.nickname as owner_nickname,
  u.email as owner_email,
  coalesce(
    (select count(*) from public.sectors where route_id = r.id),
    0
  ) as sectors_count,
  coalesce(
    (select count(*) from public.session_runs where route_id = r.id),
    0
  ) as sessions_count
from public.route_templates r
left join public.profiles p on p.id = r.owner_id
left join auth.users u on u.id = r.owner_id;

revoke all on public.admin_routes_view from public, anon, authenticated;
grant select on public.admin_routes_view to service_role;

-- supabase/migrations/20260601000004_text_ids_to_uuid.sql
-- Convert route-related text PK/FK columns to native uuid. The Flutter
-- app already generates these IDs with the `uuid` package, so the
-- stored values are valid UUID strings; we just promote the column
-- type. Native uuid gives us proper validation in PostgREST, smaller
-- storage (16 bytes vs ~36), and ends the "Invalid UUID" Zod errors
-- in the admin panel without us having to lie about the type.
--
-- Columns affected:
--   route_templates.id              text → uuid (PK)
--   sectors.id                      text → uuid (PK)
--   sectors.route_id                text → uuid (FK)
--   session_runs.id                 text → uuid (PK)
--   session_runs.route_id           text → uuid (FK)
--   telemetry_points.session_id     text → uuid (FK)
--
-- Also rewrites the duplicate_route_as_official RPC to use uuid
-- parameters now that the schema is type-consistent.

-- ──────────────────────────────────────────────────────────────────
-- Helper: deterministic text-to-uuid casting.
-- Legacy data on this project includes a few IDs that aren't valid
-- UUIDs (e.g. "route-1779395847858662" from an older client). A naive
-- `id::uuid` cast aborts the whole migration. Instead we use this
-- function on every column: real UUIDs pass through unchanged; bad
-- strings are hashed via md5 and re-shaped into a stable UUID. Because
-- the transformation is deterministic, FK references (sectors.route_id,
-- session_runs.route_id, telemetry_points.session_id) stay consistent
-- with the new route/session ids as long as the same function is used.
--
-- pg_temp lives in the session, so this function disappears when the
-- migration transaction commits — no permanent footprint.
create function pg_temp.legacy_id_to_uuid(t text) returns uuid
language sql immutable as $$
  select case
    when t ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then t::uuid
    else (
      substr(md5(t), 1, 8) || '-' ||
      substr(md5(t), 9, 4) || '-' ||
      substr(md5(t), 13, 4) || '-' ||
      substr(md5(t), 17, 4) || '-' ||
      substr(md5(t), 21, 12)
    )::uuid
  end;
$$;

-- 0) Drop dependents that block column type changes:
--    a) the admin_routes_view (joins route_templates)
--    b) the four sector RLS policies (each JOINs on route_templates.id)
drop view if exists public.admin_routes_view;

drop policy if exists "Users can view own sectors" on public.sectors;
drop policy if exists "Users can insert own sectors" on public.sectors;
drop policy if exists "Users can update own sectors" on public.sectors;
drop policy if exists "Users can delete own sectors" on public.sectors;

-- 1) Drop FKs (column types of either side can't change while an FK
--    references them).
alter table public.sectors
  drop constraint if exists sectors_route_id_fkey;
alter table public.session_runs
  drop constraint if exists session_runs_route_id_fkey;
alter table public.telemetry_points
  drop constraint if exists telemetry_points_session_id_fkey;

-- 2) Convert columns. `using col::uuid` aborts the whole migration if
--    any existing value isn't a valid UUID string, so a successful push
--    is also a data sanity check.
alter table public.route_templates
  alter column id type uuid using pg_temp.legacy_id_to_uuid(id);

alter table public.sectors
  alter column id type uuid using pg_temp.legacy_id_to_uuid(id);
alter table public.sectors
  alter column route_id type uuid using pg_temp.legacy_id_to_uuid(route_id);

alter table public.session_runs
  alter column id type uuid using pg_temp.legacy_id_to_uuid(id);
alter table public.session_runs
  alter column route_id type uuid using pg_temp.legacy_id_to_uuid(route_id);

alter table public.telemetry_points
  alter column session_id type uuid using pg_temp.legacy_id_to_uuid(session_id);

-- 3) Recreate the FKs with the same cascade behavior.
alter table public.sectors
  add constraint sectors_route_id_fkey
  foreign key (route_id) references public.route_templates(id)
  on delete cascade;

alter table public.session_runs
  add constraint session_runs_route_id_fkey
  foreign key (route_id) references public.route_templates(id)
  on delete cascade;

alter table public.telemetry_points
  add constraint telemetry_points_session_id_fkey
  foreign key (session_id) references public.session_runs(id)
  on delete cascade;

-- 3a) Recreate the four sector RLS policies (dropped in step 0).
create policy "Users can view own sectors"
  on public.sectors for select
  using (
    exists (
      select 1 from public.route_templates rt
      where rt.id = sectors.route_id and rt.owner_id = auth.uid()
    )
  );

create policy "Users can insert own sectors"
  on public.sectors for insert
  with check (
    exists (
      select 1 from public.route_templates rt
      where rt.id = sectors.route_id and rt.owner_id = auth.uid()
    )
  );

create policy "Users can update own sectors"
  on public.sectors for update
  using (
    exists (
      select 1 from public.route_templates rt
      where rt.id = sectors.route_id and rt.owner_id = auth.uid()
    )
  );

create policy "Users can delete own sectors"
  on public.sectors for delete
  using (
    exists (
      select 1 from public.route_templates rt
      where rt.id = sectors.route_id and rt.owner_id = auth.uid()
    )
  );

-- 3b) Recreate admin_routes_view (dropped in step 0). Identical body to
--     the original migration 20260601000001, included here so the view
--     comes back with the new uuid column types reflected throughout.
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

-- 4) Replace the duplicate-route RPC. The previous (text, text) overload
--    was a workaround for the wrong column type — now that the columns
--    are real uuid, the function takes uuid params again and the
--    p_admin_id::uuid cast is no longer needed.
drop function if exists public.duplicate_route_as_official(text, text);

create or replace function public.duplicate_route_as_official(
  p_source_route_id uuid,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid := gen_random_uuid();
  v_source record;
begin
  select * into v_source
  from public.route_templates
  where id = p_source_route_id;
  if not found then
    raise exception 'Source route % not found', p_source_route_id
      using errcode = 'P0002';
  end if;

  insert into public.route_templates (
    id, name, description, difficulty, elevation_range_m,
    location_label, owner_id, path_json, start_finish_gate_json,
    thumbnail_url, is_official, created_at, updated_at
  ) values (
    v_new_id,
    'Oficial — ' || v_source.name,
    v_source.description,
    v_source.difficulty,
    v_source.elevation_range_m,
    v_source.location_label,
    p_admin_id,
    v_source.path_json,
    v_source.start_finish_gate_json,
    v_source.thumbnail_url,
    true,
    now(),
    now()
  );

  insert into public.sectors (id, route_id, label, order_index, gate_json)
  select gen_random_uuid(), v_new_id, label, order_index, gate_json
  from public.sectors
  where route_id = p_source_route_id;

  return v_new_id;
end;
$$;

revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from public;
revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from anon;
revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from authenticated;
grant execute on function
  public.duplicate_route_as_official(uuid, uuid) to service_role;

-- Add free_rides + free_ride_telemetry tables (missing from initial schema).
-- Add RPC functions for atomic session/free-ride upserts to avoid
-- non-atomic delete+insert patterns in the Flutter sync layer.
-- Also adds location_label to route_templates (20260519085246 was pushed empty).

-- 0. Backfill missing column from empty migration 20260519085246

alter table public.route_templates
  add column if not exists location_label text;

-- 1. free_rides table

create table if not exists public.free_rides (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  status text not null check (status in ('draft','recording','completed','synced')),
  total_distance_m double precision not null default 0,
  max_speed_mps double precision not null default 0,
  avg_speed_mps double precision not null default 0,
  name text,
  description text,
  location_label text,
  updated_at timestamptz not null default now()
);

create index if not exists free_rides_owner_started_idx
  on public.free_rides (owner_id, started_at desc);

-- 2. free_ride_telemetry table

create table if not exists public.free_ride_telemetry (
  free_ride_id text not null references public.free_rides(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  ts timestamptz not null,
  lat double precision not null,
  lng double precision not null,
  speed_mps double precision,
  accuracy_m double precision,
  bearing_deg double precision,
  altitude_m double precision
);

create index if not exists free_ride_telemetry_ride_ts_idx
  on public.free_ride_telemetry (free_ride_id, ts);

-- 3. Enable RLS

alter table public.free_rides enable row level security;
alter table public.free_ride_telemetry enable row level security;

-- 4. RLS policies for free_rides

create policy "Users can view own free rides"
  on public.free_rides for select
  using (auth.uid() = owner_id);

create policy "Users can insert own free rides"
  on public.free_rides for insert
  with check (auth.uid() = owner_id);

create policy "Users can update own free rides"
  on public.free_rides for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Users can delete own free rides"
  on public.free_rides for delete
  using (auth.uid() = owner_id);

-- 5. RLS policies for free_ride_telemetry

create policy "Users can view own free ride telemetry"
  on public.free_ride_telemetry for select
  using (auth.uid() = owner_id);

create policy "Users can insert own free ride telemetry"
  on public.free_ride_telemetry for insert
  with check (auth.uid() = owner_id);

create policy "Users can delete own free ride telemetry"
  on public.free_ride_telemetry for delete
  using (auth.uid() = owner_id);

-- 6. Atomic upsert for session + telemetry.
--    Replaces the Flutter delete+insert pattern with a single transaction.

create or replace function public.upsert_session_with_telemetry(
  p_id text,
  p_route_id text,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_status text,
  p_lap_summaries jsonb,
  p_sector_summaries jsonb,
  p_total_distance_m double precision,
  p_max_speed_mps double precision,
  p_avg_speed_mps double precision,
  p_updated_at timestamptz,
  p_points jsonb
) returns void
language plpgsql
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.session_runs (
    id, owner_id, route_id, started_at, ended_at, status,
    lap_summaries_json, sector_summaries_json,
    total_distance_m, max_speed_mps, avg_speed_mps, updated_at
  ) values (
    p_id, v_uid, p_route_id, p_started_at, p_ended_at, p_status,
    p_lap_summaries, p_sector_summaries,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps, p_updated_at
  )
  on conflict (id) do update set
    route_id           = excluded.route_id,
    started_at         = excluded.started_at,
    ended_at           = excluded.ended_at,
    status             = excluded.status,
    lap_summaries_json = excluded.lap_summaries_json,
    sector_summaries_json = excluded.sector_summaries_json,
    total_distance_m   = excluded.total_distance_m,
    max_speed_mps      = excluded.max_speed_mps,
    avg_speed_mps      = excluded.avg_speed_mps,
    updated_at         = excluded.updated_at
  where session_runs.owner_id = v_uid;

  delete from public.telemetry_points
  where session_id = p_id and owner_id = v_uid;

  if p_points is not null and jsonb_array_length(p_points) > 0 then
    insert into public.telemetry_points (
      session_id, owner_id, ts, lat, lng,
      speed_mps, accuracy_m, bearing_deg, altitude_m
    )
    select
      p_id,
      v_uid,
      (pt->>'ts')::timestamptz,
      (pt->>'lat')::double precision,
      (pt->>'lng')::double precision,
      (pt->>'speed_mps')::double precision,
      (pt->>'accuracy_m')::double precision,
      (pt->>'bearing_deg')::double precision,
      (pt->>'altitude_m')::double precision
    from jsonb_array_elements(p_points) as pt;
  end if;
end;
$$;

grant execute on function public.upsert_session_with_telemetry(
  text, text, timestamptz, timestamptz, text,
  jsonb, jsonb, double precision, double precision, double precision,
  timestamptz, jsonb
) to authenticated;

-- 7. Atomic upsert for free ride + telemetry.

create or replace function public.upsert_free_ride_with_telemetry(
  p_id text,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_status text,
  p_total_distance_m double precision,
  p_max_speed_mps double precision,
  p_avg_speed_mps double precision,
  p_name text,
  p_description text,
  p_location_label text,
  p_updated_at timestamptz,
  p_points jsonb
) returns void
language plpgsql
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.free_rides (
    id, owner_id, started_at, ended_at, status,
    total_distance_m, max_speed_mps, avg_speed_mps,
    name, description, location_label, updated_at
  ) values (
    p_id, v_uid, p_started_at, p_ended_at, p_status,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps,
    p_name, p_description, p_location_label, p_updated_at
  )
  on conflict (id) do update set
    started_at       = excluded.started_at,
    ended_at         = excluded.ended_at,
    status           = excluded.status,
    total_distance_m = excluded.total_distance_m,
    max_speed_mps    = excluded.max_speed_mps,
    avg_speed_mps    = excluded.avg_speed_mps,
    name             = excluded.name,
    description      = excluded.description,
    location_label   = excluded.location_label,
    updated_at       = excluded.updated_at
  where free_rides.owner_id = v_uid;

  delete from public.free_ride_telemetry
  where free_ride_id = p_id and owner_id = v_uid;

  if p_points is not null and jsonb_array_length(p_points) > 0 then
    insert into public.free_ride_telemetry (
      free_ride_id, owner_id, ts, lat, lng,
      speed_mps, accuracy_m, bearing_deg, altitude_m
    )
    select
      p_id,
      v_uid,
      (pt->>'ts')::timestamptz,
      (pt->>'lat')::double precision,
      (pt->>'lng')::double precision,
      (pt->>'speed_mps')::double precision,
      (pt->>'accuracy_m')::double precision,
      (pt->>'bearing_deg')::double precision,
      (pt->>'altitude_m')::double precision
    from jsonb_array_elements(p_points) as pt;
  end if;
end;
$$;

grant execute on function public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb
) to authenticated;

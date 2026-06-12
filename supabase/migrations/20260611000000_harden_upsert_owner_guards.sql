-- Hardening for the atomic upsert RPCs (audit BUG-4 + BUG-5).
--
-- BUG-4: `INSERT ... ON CONFLICT (id) DO UPDATE ... WHERE owner_id = v_uid`
--        silently no-ops when the conflicting row belongs to ANOTHER user,
--        then still deletes/inserts telemetry against that foreign id. We now
--        detect a foreign-owned id up front and raise, so an id collision is a
--        hard error instead of silent partial writes.
-- BUG-5: these two functions were the only ones in the schema without a fixed
--        `search_path`. Pin it for consistency and hardening.
--
-- `create or replace` preserves the existing EXECUTE grants to `authenticated`.

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
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- BUG-4 guard: reject an id that already belongs to another user instead
  -- of silently no-op'ing the update and orphaning telemetry.
  perform 1 from public.session_runs
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'session % is owned by another user', p_id
      using errcode = '42501';
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
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  perform 1 from public.free_rides
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'free ride % is owned by another user', p_id
      using errcode = '42501';
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

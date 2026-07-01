-- Add expected_duration_ms (Mapbox "normal time") to free_rides and thread it
-- through the atomic upsert RPC. Mirrors 20260619000000 for route_templates.
--
-- The live function created by 20260614000001_free_ride_upsert_dedupe.sql has a
-- 13-arg signature (… p_vehicle_id text). Drop it and recreate with a 14th
-- argument p_expected_duration_ms, keeping the BUG-4 owner guard and pinned
-- search_path.

alter table public.free_rides
  add column if not exists expected_duration_ms bigint;

drop function if exists public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text
);

create function public.upsert_free_ride_with_telemetry(
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
  p_points jsonb,
  p_vehicle_id text default null,
  p_expected_duration_ms bigint default null
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
    name, description, location_label, updated_at, vehicle_id,
    expected_duration_ms
  ) values (
    p_id, v_uid, p_started_at, p_ended_at, p_status,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps,
    p_name, p_description, p_location_label, p_updated_at,
    p_vehicle_id, p_expected_duration_ms
  )
  on conflict (id) do update set
    started_at           = excluded.started_at,
    ended_at             = excluded.ended_at,
    status               = excluded.status,
    total_distance_m     = excluded.total_distance_m,
    max_speed_mps        = excluded.max_speed_mps,
    avg_speed_mps        = excluded.avg_speed_mps,
    name                 = excluded.name,
    description          = excluded.description,
    location_label       = excluded.location_label,
    updated_at           = excluded.updated_at,
    vehicle_id           = excluded.vehicle_id,
    expected_duration_ms = excluded.expected_duration_ms
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

revoke execute on function public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text, bigint
) from public, anon;
grant execute on function public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text, bigint
) to authenticated;

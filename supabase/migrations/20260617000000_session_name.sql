-- Add an optional user-given name to sessions and thread it through the
-- session upsert RPC. Mirrors how free_rides.name already works.

alter table public.session_runs
  add column if not exists name text;

-- Drop the current 13-arg overload (uuid ids, with p_vehicle_id) so we can
-- replace it with a 14-arg version that also accepts p_name.
drop function if exists public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text
);

create function public.upsert_session_with_telemetry(
  p_id uuid,
  p_route_id uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_status text,
  p_lap_summaries jsonb,
  p_sector_summaries jsonb,
  p_total_distance_m double precision,
  p_max_speed_mps double precision,
  p_avg_speed_mps double precision,
  p_updated_at timestamptz,
  p_points jsonb,
  p_vehicle_id text default null,
  p_name text default null
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

  perform 1 from public.session_runs
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'session % is owned by another user', p_id
      using errcode = '42501';
  end if;

  insert into public.session_runs (
    id, owner_id, route_id, started_at, ended_at, status,
    lap_summaries_json, sector_summaries_json,
    total_distance_m, max_speed_mps, avg_speed_mps, updated_at, vehicle_id, name
  ) values (
    p_id, v_uid, p_route_id, p_started_at, p_ended_at, p_status,
    p_lap_summaries, p_sector_summaries,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps, p_updated_at,
    p_vehicle_id, p_name
  )
  on conflict (id) do update set
    route_id              = excluded.route_id,
    started_at            = excluded.started_at,
    ended_at              = excluded.ended_at,
    status                = excluded.status,
    lap_summaries_json    = excluded.lap_summaries_json,
    sector_summaries_json = excluded.sector_summaries_json,
    total_distance_m      = excluded.total_distance_m,
    max_speed_mps         = excluded.max_speed_mps,
    avg_speed_mps         = excluded.avg_speed_mps,
    updated_at            = excluded.updated_at,
    vehicle_id            = excluded.vehicle_id,
    name                  = excluded.name
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

revoke execute on function public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text, text
) from public, anon;
grant execute on function public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text, text
) to authenticated;

-- Fix `upsert_session_with_telemetry` parameter types after the uuid migration.
--
-- Migration 20260601000004_text_ids_to_uuid.sql promoted session_runs.id,
-- session_runs.route_id and telemetry_points.session_id to native `uuid`, but
-- only rewrote the `duplicate_route_as_official` RPC. The session upsert RPC
-- still declares `p_id text` / `p_route_id text` and inserts those text values
-- straight into the now-uuid columns, so every session sync fails with:
--
--   column "id" is of type uuid but expression is of type text  (42804)
--
-- (The route upsert in 20260611000001 already uses `p_id uuid`, which is why
-- routes sync fine and only sessions break.)
--
-- Two overloads currently exist and must both go:
--   * the 13-arg version WITH `p_vehicle_id` (20260520000002) — the one the
--     client actually calls, since it always sends p_vehicle_id;
--   * the 12-arg version WITHOUT `p_vehicle_id` (20260611000000) — a dead
--     overload accidentally created by a `create or replace` whose arg count
--     differed, which is also why that migration's BUG-4 owner guard never
--     applied to the function the client invokes.
--
-- Drop both, then create the correct version: uuid id params, `p_vehicle_id`
-- restored so the client's call still resolves, plus the BUG-4 owner guard and
-- pinned search_path carried forward from the hardening migration.
--
-- free_rides.id stayed `text`, so upsert_free_ride_with_telemetry needs no
-- type change and is left untouched.

drop function if exists public.upsert_session_with_telemetry(
  text, text, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text
);
drop function if exists public.upsert_session_with_telemetry(
  text, text, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb
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
  p_vehicle_id text default null
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
    total_distance_m, max_speed_mps, avg_speed_mps, updated_at, vehicle_id
  ) values (
    p_id, v_uid, p_route_id, p_started_at, p_ended_at, p_status,
    p_lap_summaries, p_sector_summaries,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps, p_updated_at,
    p_vehicle_id
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
    vehicle_id            = excluded.vehicle_id
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
  double precision, double precision, double precision, timestamptz, jsonb, text
) from public, anon;
grant execute on function public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text
) to authenticated;

ALTER TABLE public.route_templates
  ADD COLUMN IF NOT EXISTS expected_duration_ms bigint;

drop function if exists public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb
);

create or replace function public.upsert_route_with_sectors(
  p_id uuid,
  p_name text,
  p_description text,
  p_path_json jsonb,
  p_start_finish_gate_json jsonb,
  p_difficulty text,
  p_location_label text,
  p_created_at timestamptz,
  p_updated_at timestamptz,
  p_thumbnail_url text,
  p_elevation_range_m double precision,
  p_is_official boolean,
  p_sectors jsonb,
  p_expected_duration_ms bigint
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

  -- Reject an id that already belongs to another user (parity with the
  -- session/free-ride upsert guards).
  perform 1 from public.route_templates
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'route % is owned by another user', p_id
      using errcode = '42501';
  end if;

  insert into public.route_templates (
    id, owner_id, name, description, path_json, start_finish_gate_json,
    difficulty, location_label, created_at, updated_at, thumbnail_url,
    elevation_range_m, is_official, expected_duration_ms
  ) values (
    p_id, v_uid, p_name, p_description, p_path_json, p_start_finish_gate_json,
    p_difficulty, p_location_label, p_created_at, p_updated_at, p_thumbnail_url,
    p_elevation_range_m, coalesce(p_is_official, false), p_expected_duration_ms
  )
  on conflict (id) do update set
    name                   = excluded.name,
    description            = excluded.description,
    path_json              = excluded.path_json,
    start_finish_gate_json = excluded.start_finish_gate_json,
    difficulty             = excluded.difficulty,
    location_label         = excluded.location_label,
    updated_at             = excluded.updated_at,
    thumbnail_url          = excluded.thumbnail_url,
    elevation_range_m      = excluded.elevation_range_m,
    is_official            = excluded.is_official,
    expected_duration_ms   = excluded.expected_duration_ms
  where route_templates.owner_id = v_uid;

  -- Replace sectors atomically. Both statements run in the same transaction,
  -- so a failure rolls back the delete too.
  delete from public.sectors where route_id = p_id;

  if p_sectors is not null and jsonb_array_length(p_sectors) > 0 then
    insert into public.sectors (id, route_id, order_index, label, gate_json)
    select
      (s->>'id')::uuid,
      p_id,
      (s->>'order_index')::int,
      s->>'label',
      s->'gate_json'
    from jsonb_array_elements(p_sectors) as s;
  end if;
end;
$$;

revoke execute on function public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb, bigint
) from public, anon;
grant execute on function public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb, bigint
) to authenticated;

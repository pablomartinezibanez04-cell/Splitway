-- supabase/migrations/20260601000002_duplicate_route_as_official.sql
-- Atomic clone of a route + its sectors into a new route_templates row
-- marked is_official = true, owned by the admin who triggered the
-- duplication. Returns the new route's id. SECURITY DEFINER + a
-- service-role grant keeps it usable only from Server Actions.

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
